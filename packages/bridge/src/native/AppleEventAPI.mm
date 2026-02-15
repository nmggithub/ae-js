#include "AppleEventAPI.h"

#include "AEDescriptor.h"
#include "OSError.h"

#include <Carbon/Carbon.h>
#include <CoreServices/CoreServices.h>
#include <napi.h>

#include <atomic>
#include <chrono>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace ae_js_bridge {

namespace AppleEventAPI {
namespace Sending {
class SendAppleEventWorker : public Napi::AsyncWorker {
public:
  SendAppleEventWorker(Napi::Env env, AEDesc *request, bool expectReply)
      : Napi::AsyncWorker(env), deferred(Napi::Promise::Deferred::New(env)),
        requestDesc(request), shouldExpectReply(expectReply) {}

  ~SendAppleEventWorker() override {
    if (requestDesc) {
      AEDisposeDesc(requestDesc);
      delete requestDesc;
    }
    if (replyDesc) {
      AEDisposeDesc(replyDesc);
      delete replyDesc;
    }
  }

  Napi::Promise GetPromise() { return deferred.Promise(); }

  void Execute() override {
    if (!requestDesc) {
      errorCode = paramErr;
      errorMessage = "Missing Apple event request descriptor";
      SetError(errorMessage);
      return;
    }

    AppleEvent *replyPtr = nullptr;
    if (shouldExpectReply) {
      replyDesc = new AppleEvent{};
      replyPtr = reinterpret_cast<AppleEvent *>(replyDesc);
    }

    OSErr err = AESendMessage(
        reinterpret_cast<const AppleEvent *>(requestDesc), replyPtr,
        shouldExpectReply ? kAEWaitReply : kAENoReply, kAEDefaultTimeout);
    if (err != noErr) {
      errorCode = err;
      errorMessage = "AESendMessage failed";
      SetError(errorMessage);
    }
  }

  void OnOK() override {
    Napi::Env env = Env();
    if (!shouldExpectReply) {
      deferred.Resolve(env.Null());
      return;
    }

    AEDesc *result = replyDesc;
    Napi::Value wrapped = Descriptors::CopyAndWrapAEDescOrThrow(env, result);
    if (env.IsExceptionPending()) {
      Napi::Error error = env.GetAndClearPendingException();
      deferred.Reject(error.Value());
      return;
    }
    if (wrapped.IsUndefined() || wrapped.IsNull()) {
      deferred.Reject(
          Napi::Error::New(env, "Failed to wrap Apple event reply").Value());
      return;
    }
    deferred.Resolve(wrapped);
  }

  void OnError(const Napi::Error &) override {
    deferred.Reject(OSError::New(Env(), errorCode, errorMessage));
  }

private:
  Napi::Promise::Deferred deferred;
  AEDesc *requestDesc = nullptr;
  AEDesc *replyDesc = nullptr;
  bool shouldExpectReply = false;
  OSErr errorCode = noErr;
  std::string errorMessage;
};
Napi::Value SendAppleEvent(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsObject() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "sendAppleEvent takes (event, expectReply)")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  auto *wrapper = Descriptors::UnwrapDescriptor(info[0]);
  if (!wrapper) {
    Napi::Error::New(env, "Invalid event descriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }
  const AEDesc *rawDesc = wrapper->GetRawDescriptor();
  if (!rawDesc) {
    Napi::Error::New(env, "Uninitialized descriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }
  if (rawDesc->descriptorType != typeAppleEvent) {
    Napi::TypeError::New(env, "sendAppleEvent requires AEEventDescriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  AEDesc *requestCopy = new AEDesc{};
  OSErr dupErr = AEDuplicateDesc(rawDesc, requestCopy);
  if (dupErr != noErr) {
    delete requestCopy;
    OSError::Throw(env, dupErr, "AEDuplicateDesc failed");
    return env.Null();
  }

  bool expectReply = info[1].As<Napi::Boolean>().Value();
  auto *worker = new SendAppleEventWorker(env, requestCopy, expectReply);
  Napi::Promise promise = worker->GetPromise();
  worker->Queue();
  return promise;
}
} // namespace Sending
namespace Handling {
#define POISONED_ENV_ERROR_MESSAGE                                             \
  "Apple event bridge is unavailable for this environment"
#define UNHANDLE_DURING_CALLBACK_ERROR_MESSAGE                                 \
  "Cannot unhandle Apple events while any Apple event callback is in "         \
  "progress. "                                                                 \
  "Defer unhandle (e.g. setTimeout) and retry."

namespace Carbon {
namespace {
OSErr AppleEventHandlerThunk(const AppleEvent *event, AppleEvent *reply,
                             SRefCon refCon);
}
} // namespace Carbon

namespace Handlers {
struct Key {
  AEEventClass eventClass = 0;
  AEEventID eventID = 0;

  bool operator==(const Key &other) const {
    return eventClass == other.eventClass && eventID == other.eventID;
  }
};

struct KeyHasher {
  std::size_t operator()(const Key &key) const {
    return (static_cast<std::size_t>(key.eventClass) << 32) ^
           static_cast<std::size_t>(key.eventID);
  }
};

struct Context {
  napi_env env;
  std::thread::id jsThreadId;
  Napi::FunctionReference handlerRef;
  Napi::ThreadSafeFunction handlerTsfn;
};

std::mutex mutex;
std::unordered_map<Key, std::shared_ptr<Context>, KeyHasher> map;
std::unordered_map<Context *, std::shared_ptr<Context>> byRefCon;
std::atomic<uint32_t> activeCallbackCount{0};

bool ParseKeyOrThrow(const Napi::Env &env, const Napi::Value &classValue,
                     const Napi::Value &idValue, Key *outKey) {
  if (!classValue.IsString() || !idValue.IsString()) {
    Napi::TypeError::New(env,
                         "eventClass and eventID must be FourCharCode strings")
        .ThrowAsJavaScriptException();
    return false;
  }

  try {
    outKey->eventClass =
        StringToFourCharCode(classValue.As<Napi::String>().Utf8Value());
    if (outKey->eventClass == 0) {
      Napi::Error::New(env, "Invalid event class").ThrowAsJavaScriptException();
      return false;
    }
    outKey->eventID =
        StringToFourCharCode(idValue.As<Napi::String>().Utf8Value());
    if (outKey->eventID == 0) {
      Napi::Error::New(env, "Invalid event ID").ThrowAsJavaScriptException();
      return false;
    }
  } catch (const Napi::Error &error) {
    error.ThrowAsJavaScriptException();
    return false;
  }
  return true;
}
} // namespace Handlers

namespace UPPs {
std::mutex byEnvMutex;
std::unordered_map<napi_env, AEEventHandlerUPP> byEnv;
} // namespace UPPs

namespace Envs {
std::mutex setWithCleanupHooksMutex;
std::unordered_set<napi_env> setWithCleanupHooks;
std::mutex poisonedSetMutex;
std::unordered_set<napi_env> poisonedSet;

namespace {
void CleanupEnvAppleEventState(void *data) {
  auto env = static_cast<napi_env>(data);

  AEEventHandlerUPP envUPP = nullptr;
  {
    std::lock_guard<std::mutex> lock(UPPs::byEnvMutex);
    auto uppIt = UPPs::byEnv.find(env);
    if (uppIt != UPPs::byEnv.end()) {
      envUPP = uppIt->second;
      UPPs::byEnv.erase(uppIt);
    }
  }
  {
    std::lock_guard<std::mutex> lock(Envs::setWithCleanupHooksMutex);
    Envs::setWithCleanupHooks.erase(env);
  }
  {
    std::lock_guard<std::mutex> lock(Envs::poisonedSetMutex);
    Envs::poisonedSet.erase(env);
  }

  if (!envUPP) {
    return;
  }

  std::vector<Handlers::Key> keysForEnv;
  {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    for (const auto &[key, ctx] : Handlers::map) {
      if (ctx && ctx->env == env) {
        keysForEnv.push_back(key);
      }
    }
  }

  for (const auto &key : keysForEnv) {
    AERemoveEventHandler(key.eventClass, key.eventID, envUPP, false);
  }

  {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    for (const auto &key : keysForEnv) {
      auto it = Handlers::map.find(key);
      if (it != Handlers::map.end()) {
        Handlers::byRefCon.erase(it->second.get());
        Handlers::map.erase(it);
      }
    }
  }

  DisposeAEEventHandlerUPP(envUPP);
}

napi_status EnsureEnvCleanupHookRegistered(napi_env env) {
  std::lock_guard<std::mutex> lock(Envs::setWithCleanupHooksMutex);
  if (Envs::setWithCleanupHooks.find(env) != Envs::setWithCleanupHooks.end()) {
    return napi_ok;
  }

  napi_status status = napi_add_env_cleanup_hook(env, CleanupEnvAppleEventState,
                                                 static_cast<void *>(env));
  if (status == napi_ok) {
    Envs::setWithCleanupHooks.insert(env);
  }
  return status;
}

bool IsEnvPoisoned(napi_env env) {
  std::lock_guard<std::mutex> lock(Envs::poisonedSetMutex);
  return Envs::poisonedSet.find(env) != Envs::poisonedSet.end();
}

void MarkEnvPoisoned(napi_env env) {
  std::lock_guard<std::mutex> lock(Envs::poisonedSetMutex);
  poisonedSet.insert(env);
}
} // namespace
} // namespace Envs

namespace UPPs {
namespace {
AEEventHandlerUPP GetAEHandlerUPP(napi_env env) {
  std::lock_guard<std::mutex> lock(UPPs::byEnvMutex);
  auto it = UPPs::byEnv.find(env);
  if (it == UPPs::byEnv.end()) {
    return nullptr;
  }
  return it->second;
}

AEEventHandlerUPP EnsureAEHandlerUPP(napi_env env) {
  AEEventHandlerUPP existingUPP = nullptr;
  bool hasCleanupHook = false;

  if (Envs::IsEnvPoisoned(env)) {
    return nullptr;
  }

  {
    std::lock_guard<std::mutex> lock(UPPs::byEnvMutex);
    auto it = UPPs::byEnv.find(env);
    if (it != UPPs::byEnv.end()) {
      existingUPP = it->second;
    }
  }
  {
    std::lock_guard<std::mutex> lock(Envs::setWithCleanupHooksMutex);
    hasCleanupHook =
        Envs::setWithCleanupHooks.find(env) != Envs::setWithCleanupHooks.end();
  }

  if (existingUPP) {
    // State is consistent, so we can return the cached UPP.
    if (hasCleanupHook) {
      return existingUPP;
    }

    // Repair inconsistent state: cached UPP exists but cleanup hook is missing.
    if (Envs::EnsureEnvCleanupHookRegistered(env) == napi_ok) {
      return existingUPP;
    }
    Envs::MarkEnvPoisoned(env);
    return nullptr;
  }

  if (Envs::EnsureEnvCleanupHookRegistered(env) != napi_ok) {
    Envs::MarkEnvPoisoned(env);
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(UPPs::byEnvMutex);
  auto existing = UPPs::byEnv.find(env);
  if (existing != UPPs::byEnv.end()) {
    return existing->second;
  }

  auto handler = NewAEEventHandlerUPP(Carbon::AppleEventHandlerThunk);
  UPPs::byEnv[env] = handler;
  return handler;
}
} // namespace
} // namespace UPPs

namespace Carbon {
namespace {
OSErr MakeErrorReply(AppleEvent *reply, OSStatus errorCode,
                     const std::string &errorMessage,
                     bool clearReplyIfNonEmpty = false);
bool GetAppleEventTimeoutDuration(const AppleEvent *event,
                                  std::chrono::milliseconds *outDuration);
} // namespace
} // namespace Carbon

namespace Node {
OSErr ApplyResultObjectToReply(const Napi::Env &env, Napi::Object &resultObject,
                               AppleEvent *reply);
namespace Promises {
namespace {

struct PromiseState {
  std::mutex mutex;
  std::condition_variable cv;
  bool settled = false;
  bool fulfilled = false;
  OSErr failureCode = errOSAGeneralError;
  std::string failureMessage = "JS handler promise rejected";
  Napi::ObjectReference fulfilledObject;
};
class ResumeSuspendedEventWorker : public Napi::AsyncWorker {
private:
  std::shared_ptr<PromiseState> state_;
  AppleEvent *suspendedEvent_ = nullptr;
  AppleEvent *reply_ = nullptr;
  std::chrono::milliseconds timeoutDuration_{};
  bool hasTimeout_ = false;
  std::thread::id suspendedEventThreadId_;
  bool resumed_ = false;

public:
  ResumeSuspendedEventWorker(Napi::Env env, std::shared_ptr<PromiseState> state,
                             AppleEvent *suspendedEvent, AppleEvent *reply,
                             std::chrono::milliseconds timeoutDuration,
                             bool hasTimeout,
                             std::thread::id suspendedEventThreadId)
      : Napi::AsyncWorker(env), state_(state), suspendedEvent_(suspendedEvent),
        reply_(reply), timeoutDuration_(timeoutDuration),
        hasTimeout_(hasTimeout),
        suspendedEventThreadId_(suspendedEventThreadId) {}

  ~ResumeSuspendedEventWorker() override {
    if (suspendedEvent_) {
      if (!resumed_) {
        AEDisposeDesc(suspendedEvent_);
      }
      delete suspendedEvent_;
    }
    if (reply_) {
      if (!resumed_) {
        AEDisposeDesc(reply_);
      }
      delete reply_;
    }
  }

  void Execute() override {
    std::unique_lock<std::mutex> lock(state_->mutex);
    if (hasTimeout_) {
      bool settled = state_->cv.wait_for(lock, timeoutDuration_,
                                         [&] { return state_->settled; });
      if (!settled) {
        state_->settled = true;
        state_->fulfilled = false;
        state_->failureCode = errAETimeout;
        state_->failureMessage =
            "Apple event handler promise timed out on the receiving end";
      }
      return;
    }
    state_->cv.wait(lock, [&] { return state_->settled; });
  }

  void OnOK() override {
    bool fulfilled = false;
    OSErr failureCode = errOSAGeneralError;
    std::string failureMessage;
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      fulfilled = state_->fulfilled;
      failureCode = state_->failureCode;
      failureMessage = state_->failureMessage;
    }
    if (std::this_thread::get_id() != suspendedEventThreadId_) {
      return;
    }
    OSErr replyErr = noErr;
    if (fulfilled) {
      Napi::HandleScope scope(Env());
      Napi::Object resultObject = state_->fulfilledObject.Value();
      replyErr = Node::ApplyResultObjectToReply(Env(), resultObject, reply_);
      if (replyErr != noErr) {
        replyErr =
            Carbon::MakeErrorReply(reply_, replyErr,
                                   "JS handler promise produced an invalid "
                                   "reply object");
      }
    } else {
      replyErr = Carbon::MakeErrorReply(reply_, failureCode, failureMessage);
    }

    if (replyErr != noErr) {
      Carbon::MakeErrorReply(reply_, replyErr,
                             "Failed to build reply for suspended Apple event");
    }

    OSErr resumeErr = AEResumeTheCurrentEvent(
        suspendedEvent_, reply_,
        reinterpret_cast<AEEventHandlerUPP>(kAENoDispatch), 0);
    if (resumeErr != noErr) {
      return; // We can't do anything about this, so we just give up.
    }
    resumed_ = true;
  }
};

std::string PromiseRejectionToMessage(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() == 0 || info[0].IsUndefined() || info[0].IsNull()) {
    return "JS handler promise rejected without a reason";
  }

  Napi::Value reason = info[0];
  try {
    if (reason.IsObject()) {
      Napi::Object objectReason = reason.As<Napi::Object>();
      Napi::Value message = objectReason.Get("message");
      if (message.IsString()) {
        std::string withMessage = message.As<Napi::String>().Utf8Value();
        if (!withMessage.empty()) {
          return "JS handler promise rejected: " + withMessage;
        }
      }
    }
    std::string asString = reason.ToString().Utf8Value();
    if (!asString.empty()) {
      return "JS handler promise rejected: " + asString;
    }
  } catch (const Napi::Error &) {
    if (env.IsExceptionPending()) {
      env.GetAndClearPendingException();
    }
  }
  return "JS handler promise rejected with an unknown reason";
}
} // namespace

OSErr HandlePromiseResult(const Napi::Env &env, Napi::Promise &promise,
                          const AppleEvent *event, AppleEvent *reply) {
  if (!event || !reply) {
    return paramErr;
  }

  // Documentation doesn't say we have to do this, but it seems to keep us from
  // crashing when the event is resumed. Copying the event and reply here seems
  // to give them more stable lifetimes across suspension and resumption.

  auto suspendedEventCopy = std::make_unique<AppleEvent>();
  OSErr eventCopyErr =
      AEDuplicateDesc(reinterpret_cast<const AEDesc *>(event),
                      reinterpret_cast<AEDesc *>(suspendedEventCopy.get()));
  if (eventCopyErr != noErr) {
    return eventCopyErr;
  }

  auto replyCopy = std::make_unique<AppleEvent>();
  OSErr replyCopyErr =
      AEDuplicateDesc(reinterpret_cast<const AEDesc *>(reply),
                      reinterpret_cast<AEDesc *>(replyCopy.get()));
  if (replyCopyErr != noErr) {
    return replyCopyErr;
  }

  OSErr suspendErr = AESuspendTheCurrentEvent(event);
  if (suspendErr != noErr) {
    return suspendErr;
  }

  std::chrono::milliseconds timeoutDuration{};
  bool hasTimeout =
      Carbon::GetAppleEventTimeoutDuration(event, &timeoutDuration);
  auto state = std::make_shared<PromiseState>();
  auto *worker = new ResumeSuspendedEventWorker(
      env, state, suspendedEventCopy.release(), replyCopy.release(),
      timeoutDuration, hasTimeout, std::this_thread::get_id());

  Napi::Function onFulfilled = Napi::Function::New(
      env, [state](const Napi::CallbackInfo &info) -> Napi::Value {
        Napi::Env env = info.Env();
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->settled) {
          return env.Undefined();
        }
        Napi::Value value = info.Length() > 0 ? info[0] : env.Undefined();
        if (!value.IsObject()) {
          state->fulfilled = false;
          state->failureCode = errAEWrongDataType;
          state->failureMessage =
              "JS handler promise resolved with a non-object result";
        } else {
          state->fulfilled = true;
          state->fulfilledObject = Napi::Persistent(value.As<Napi::Object>());
        }
        state->settled = true;
        state->cv.notify_all();
        return env.Undefined();
      });

  Napi::Function onRejected = Napi::Function::New(
      env, [state](const Napi::CallbackInfo &info) -> Napi::Value {
        Napi::Env env = info.Env();
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->settled) {
          return env.Undefined();
        }
        state->fulfilled = false;
        state->failureCode = errOSAGeneralError;
        state->failureMessage = PromiseRejectionToMessage(info);
        state->settled = true;
        state->cv.notify_all();
        return env.Undefined();
      });

  try {
    promise.Then(onFulfilled, onRejected);
    if (env.IsExceptionPending()) {
      Napi::Error thenErr = env.GetAndClearPendingException();
      std::lock_guard<std::mutex> lock(state->mutex);
      state->fulfilled = false;
      state->failureCode = errOSAGeneralError;
      state->failureMessage =
          "Failed to attach promise handlers: " + thenErr.Message();
      state->settled = true;
      state->cv.notify_all();
    }
  } catch (const Napi::Error &thenErr) {
    if (env.IsExceptionPending()) {
      env.GetAndClearPendingException();
    }
    std::lock_guard<std::mutex> lock(state->mutex);
    state->fulfilled = false;
    state->failureCode = errOSAGeneralError;
    state->failureMessage =
        "Failed to attach promise handlers: " + thenErr.Message();
    state->settled = true;
    state->cv.notify_all();
  }

  worker->Queue();
  return noErr;
}
} // namespace Promises
} // namespace Node

namespace Node {
OSErr ApplyResultObjectToReply(const Napi::Env &env, Napi::Object &resultObject,
                               AppleEvent *reply) {
  Napi::Array keys = resultObject.GetPropertyNames();
  for (uint32_t i = 0; i < keys.Length(); ++i) {
    Napi::Value key = keys.Get(i);
    if (!key.IsString()) {
      return Carbon::MakeErrorReply(
          reply, errAEWrongDataType,
          "JS handler returned a property keyword that wasn't a string");
    }
    FourCharCode keyword =
        StringToFourCharCode(key.As<Napi::String>().Utf8Value());
    if (keyword == 0) {
      return Carbon::MakeErrorReply(reply, errAEWrongDataType,
                                    "JS handler returned a property keyword "
                                    "that wasn't a valid FourCharCode");
    }
    Napi::Value value = resultObject.Get(key);
    auto *wrapper = Descriptors::UnwrapDescriptor(value);
    if (!wrapper) {
      return Carbon::MakeErrorReply(
          reply, errAEWrongDataType,
          "JS handler returned a property value that wasn't a descriptor");
    }
    OSErr putErr = AEPutParamDesc(reply, keyword, wrapper->GetRawDescriptor());
    if (putErr != noErr) {
      return putErr;
    }
  }
  return noErr;
}

OSErr InvokeJSHandlerOnMainThreadOrThrow(const Napi::Env &env,
                                         const AppleEvent *event,
                                         AppleEvent *reply,
                                         Napi::Function handler) {
  try {
    if (!event) {
      return Carbon::MakeErrorReply(reply, errAEDescNotFound, "Missing event");
    }

    auto wrappedEvent = Descriptors::CopyAndWrapAEDescOrThrow(env, event);
    if (!wrappedEvent.IsObject() ||
        !wrappedEvent.As<Napi::Object>().InstanceOf(
            Descriptors::AEEventDescriptor::constructor.Value())) {
      return Carbon::MakeErrorReply(reply, errAENotAppleEvent, "Invalid event");
    }

    bool replyExpected = reply->descriptorType != typeNull;
    auto result =
        handler.Call({wrappedEvent, Napi::Boolean::New(env, replyExpected)});
    if (env.IsExceptionPending()) {
      Napi::Error error = env.GetAndClearPendingException();
      return Carbon::MakeErrorReply(
          reply, errOSAGeneralError,
          "JS handler encountered an uncaught exception: " + error.Message());
    }

    if (!result.IsObject()) {
      return Carbon::MakeErrorReply(reply, errOSAGeneralError,
                                    "JS handler returned a non-object result");
    }

    if (result.IsPromise()) {
      Napi::Promise promise = result.As<Napi::Promise>();
      return Node::Promises::HandlePromiseResult(env, promise, event, reply);
    }

    Napi::Object resultObject = result.As<Napi::Object>();
    return Node::ApplyResultObjectToReply(env, resultObject, reply);

  } catch (const Napi::Error &error) {
    return Carbon::MakeErrorReply(reply, errOSAGeneralError,
                                  "AEJS encountered an internal JS error: " +
                                      error.Message());
  } catch (const std::exception &exception) {
    return Carbon::MakeErrorReply(reply, errOSAGeneralError,
                                  "AEJS encountered an internal C++ error: " +
                                      std::string(exception.what()));
  } catch (...) {
    return Carbon::MakeErrorReply(reply, errOSAGeneralError,
                                  "AEJS encountered an unknown internal error");
  }
}
} // namespace Node

namespace Carbon {
OSErr ClearAppleEventReply(AppleEvent *reply) {
  if (reply == nullptr) {
    return paramErr;
  }

  long count = 0;
  OSErr countErr = AECountItems(reply, &count);
  if (countErr != noErr) {
    return countErr;
  }

  for (long i = count; i >= 1; i--) {
    AEKeyword keyword = 0;
    AEDesc desc = {};

    OSErr getErr = AEGetNthDesc(reply, i, typeWildCard, &keyword, &desc);

    if (getErr != noErr) {
      return getErr;
    }

    AEDisposeDesc(&desc);

    OSErr deleteErr = AEDeleteParam(reply, keyword);
    if (deleteErr != noErr) {
      return deleteErr;
    }
  }

  return noErr;
}
namespace {
OSErr MakeErrorReply(AppleEvent *reply, OSStatus errorCode,
                     const std::string &errorMessage,
                     bool clearReplyIfNonEmpty) {
  long itemCount = 0;
  OSErr itemCountErr = AECountItems(reply, &itemCount);
  if (itemCountErr != noErr) {
    return itemCountErr;
  }
  if (itemCount > 0) {
    if (clearReplyIfNonEmpty) {
      OSErr clearErr = ClearAppleEventReply(reply);
      if (clearErr != noErr) {
        return clearErr;
      }
    } else {
      return errAECorruptData;
    }
  }
  AEDesc errorNumberDesc = {};
  OSErr errorNumCreateErr =
      AECreateDesc(typeSInt32, &errorCode, sizeof(errorCode), &errorNumberDesc);
  if (errorNumCreateErr != noErr) {
    return errorNumCreateErr;
  }
  AEDesc errorMessageDesc = {};
  OSErr errorMessageCreateErr = AECreateDesc(
      typeChar, errorMessage.c_str(), errorMessage.size(), &errorMessageDesc);
  if (errorMessageCreateErr != noErr) {
    AEDisposeDesc(&errorNumberDesc);
    return errorMessageCreateErr;
  }
  OSErr putErr = AEPutParamDesc(reply, kOSAErrorNumber, &errorNumberDesc);
  if (putErr != noErr) {
    AEDisposeDesc(&errorMessageDesc);
    AEDisposeDesc(&errorNumberDesc);
    return putErr;
  }
  putErr = AEPutParamDesc(reply, kOSAErrorMessage, &errorMessageDesc);
  AEDisposeDesc(&errorMessageDesc);
  AEDisposeDesc(&errorNumberDesc);
  if (putErr != noErr) {
    return putErr;
  }
  return noErr;
}

bool GetAppleEventTimeoutDuration(const AppleEvent *event,
                                  std::chrono::milliseconds *outDuration) {
  if (!event || !outDuration) {
    return false;
  }

  SInt32 timeoutTicks = kAEDefaultTimeout;
  OSErr timeoutErr =
      AEGetAttributePtr(event, keyTimeoutAttr, typeSInt32, nullptr,
                        &timeoutTicks, sizeof(timeoutTicks), nullptr);
  if (timeoutErr != noErr && timeoutErr != errAEDescNotFound) {
    return false;
  }

  if (timeoutTicks == kNoTimeOut || timeoutTicks == kAEDefaultTimeout ||
      timeoutTicks <= 0) {
    return false;
  }

  // Apple event timeout is expressed in ticks (1/60s).
  *outDuration = std::chrono::milliseconds(
      (static_cast<int64_t>(timeoutTicks) * 1000 + 59) / 60);
  return true;
} // namespace Carbon

// The main thread handler thunk.
// WARNING: We shouldn't return `errAEEventNotHandled` here, as it will defer to
//    the Cocoa scripting event handler, which may step on our toes and register
//    its own event handlers for the same event IDs. If we use `events` instead
//    of `commands` in the scripting definition, that mitigates that behavior,
//    but we should still be careful. We send error replies instead.
OSErr AppleEventHandlerThunk(const AppleEvent *event, AppleEvent *reply,
                             SRefCon refCon) {
  Handlers::Context *rawCtx = reinterpret_cast<Handlers::Context *>(refCon);
  if (!rawCtx) {
    return MakeErrorReply(reply, paramErr, "Missing handler context");
  }
  std::shared_ptr<Handlers::Context> ctxRef;
  {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    auto it = Handlers::byRefCon.find(rawCtx);
    if (it == Handlers::byRefCon.end()) {
      return MakeErrorReply(reply, paramErr, "Missing handler context");
    }
    ctxRef = it->second;
    Handlers::activeCallbackCount.fetch_add(1, std::memory_order_acq_rel);
  }
  Handlers::Context *ctx = ctxRef.get();
  auto finish = []() {
    Handlers::activeCallbackCount.fetch_sub(1, std::memory_order_acq_rel);
  };
  // fast path if we're on the right thread
  if (ctx->jsThreadId == std::this_thread::get_id()) {
    Napi::HandleScope scope(ctx->env);
    Napi::Function handler = ctx->handlerRef.Value();
    OSErr result = Node::InvokeJSHandlerOnMainThreadOrThrow(ctx->env, event,
                                                            reply, handler);
    finish();
    return result;
  }
  // otherwise, block the main thread and call the handler
  struct CallData {
    std::mutex mtx;
    std::condition_variable cv;
    bool started = false;
    bool done = false;
    bool cancelled = false;
    OSErr result = noErr;
  };
  auto data = std::make_shared<CallData>();
  napi_status status = ctx->handlerTsfn.BlockingCall(
      [event, reply, data](Napi::Env env, Napi::Function handler) {
        {
          std::lock_guard<std::mutex> lock(data->mtx);
          data->started = true;
          if (data->cancelled) {
            data->done = true;
            data->cv.notify_all();
            return;
          }
        }

        OSErr err = Node::InvokeJSHandlerOnMainThreadOrThrow(env, event, reply,
                                                             handler);
        std::lock_guard<std::mutex> lock(data->mtx);
        data->result = err;
        data->done = true;
        data->cv.notify_all();
      });
  if (status != napi_ok) {
    finish();
    return MakeErrorReply(reply, errOSAGeneralError,
                          "Failed to block main thread. napi_status: " +
                              std::to_string(status));
  }

  std::chrono::milliseconds timeoutDuration{};
  bool hasTimeout = GetAppleEventTimeoutDuration(event, &timeoutDuration);
  if (hasTimeout) {
    std::unique_lock<std::mutex> lock(data->mtx);
    bool completedInTime =
        data->cv.wait_for(lock, timeoutDuration, [&] { return data->done; });
    if (!completedInTime) {
      // If callback hasn't started yet, cancel queued execution and return a
      // timeout reply. If it already started, we must continue waiting because
      // the callback may still be writing into the live reply event.
      if (!data->started) {
        data->cancelled = true;
        finish();
        return MakeErrorReply(
            reply, errAETimeout,
            "Apple event handler timed out on the receiving end");
      }
      data->cv.wait(lock, [&] { return data->done; });
    }
  } else {
    std::unique_lock<std::mutex> lock(data->mtx);
    data->cv.wait(lock, [&] { return data->done; });
  }
  OSErr result = data->result;
  finish();
  return result;
}
} // namespace
} // namespace Carbon

Napi::Value HandleAppleEvent(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 3 || !info[0].IsString() || !info[1].IsString() ||
      !info[2].IsFunction()) {
    Napi::TypeError::New(env, "handleAppleEvent takes (eventClass: string, "
                              "eventID: string, handler: function)")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  Handlers::Key key;
  if (!Handlers::ParseKeyOrThrow(env, info[0], info[1], &key)) {
    return env.Undefined();
  }

  Handlers::Context *ctx = nullptr;

  {
    std::lock_guard<std::mutex> lock(Handlers::mutex);

    auto it = Handlers::map.find(key);
    if (it != Handlers::map.end()) {
      Napi::Error::New(env, "Handler already registered")
          .ThrowAsJavaScriptException();
      return env.Undefined();
    }

    Napi::ThreadSafeFunction tsfn = Napi::ThreadSafeFunction::New(
        env, info[2].As<Napi::Function>(), "AppleEventHandler", 0, 1);

    auto ctxRef = std::make_shared<Handlers::Context>(Handlers::Context{
        env, std::this_thread::get_id(),
        Napi::Persistent(info[2].As<Napi::Function>()), tsfn});

    Handlers::Context *raw = ctxRef.get();

    auto [insertedIt, didInsert] = Handlers::map.emplace(key, ctxRef);
    if (!didInsert) {
      Napi::Error::New(env, "Failed to register handler")
          .ThrowAsJavaScriptException();
      return env.Undefined();
    }
    Handlers::byRefCon.emplace(raw, ctxRef);

    ctx = raw;
  }

  AEEventHandlerUPP handlerUPP = UPPs::EnsureAEHandlerUPP(env);
  if (!handlerUPP) {
    {
      std::lock_guard<std::mutex> lock(Handlers::mutex);
      Handlers::byRefCon.erase(ctx);
      Handlers::map.erase(key);
    }
    const char *msg = Envs::IsEnvPoisoned(env)
                          ? POISONED_ENV_ERROR_MESSAGE
                          : "Failed to install Apple event handler";
    Napi::Error::New(env, msg).ThrowAsJavaScriptException();
    return env.Undefined();
  }

  OSErr err = AEInstallEventHandler(key.eventClass, key.eventID, handlerUPP,
                                    ctx, false);

  if (err != noErr) {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    Handlers::byRefCon.erase(ctx);
    Handlers::map.erase(key);
    OSError::Throw(env, err, "AEInstallEventHandler failed");
    return env.Undefined();
  }

  return env.Undefined();
}

Napi::Value UnhandleAppleEvent(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsString() || !info[1].IsString()) {
    Napi::TypeError::New(env, "unhandleAppleEvent takes (eventClass: string, "
                              "eventID: string)")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  Handlers::Key key;
  if (!Handlers::ParseKeyOrThrow(env, info[0], info[1], &key)) {
    return env.Undefined();
  }

  if (Envs::IsEnvPoisoned(env)) {
    Napi::Error::New(env, POISONED_ENV_ERROR_MESSAGE)
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    if (Handlers::activeCallbackCount.load(std::memory_order_acquire) != 0) {
      Napi::Error::New(env, UNHANDLE_DURING_CALLBACK_ERROR_MESSAGE)
          .ThrowAsJavaScriptException();
      return env.Undefined();
    }
  }

  AEEventHandlerUPP handlerUPP = UPPs::GetAEHandlerUPP(env);
  if (!handlerUPP) {
    std::lock_guard<std::mutex> lock(Handlers::mutex);
    auto it = Handlers::map.find(key);
    if (it != Handlers::map.end()) {
      Handlers::byRefCon.erase(it->second.get());
    }
    Handlers::map.erase(key);
    return env.Undefined();
  }

  OSErr err =
      AERemoveEventHandler(key.eventClass, key.eventID, handlerUPP, false);
  if (err != noErr) {
    OSError::Throw(env, err, "AERemoveEventHandler failed");
    return env.Undefined();
  }
  std::lock_guard<std::mutex> lock(Handlers::mutex);
  auto it = Handlers::map.find(key);
  if (it != Handlers::map.end()) {
    Handlers::byRefCon.erase(it->second.get());
  }
  Handlers::map.erase(key);
  return env.Undefined();
}
} // namespace Handling
void Init(Napi::Env env, Napi::Object exports) {
  exports.Set("sendAppleEvent",
              Napi::Function::New(env, AppleEventAPI::Sending::SendAppleEvent));
  exports.Set(
      "handleAppleEvent",
      Napi::Function::New(env, AppleEventAPI::Handling::HandleAppleEvent));
  exports.Set(
      "unhandleAppleEvent",
      Napi::Function::New(env, AppleEventAPI::Handling::UnhandleAppleEvent));
}
} // namespace AppleEventAPI
} // namespace ae_js_bridge
