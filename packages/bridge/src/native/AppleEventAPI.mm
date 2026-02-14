#include "AppleEventAPI.h"

#include "AEDescriptor.h"
#include "OSError.h"

#include <CoreServices/CoreServices.h>
#include <napi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <exception>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
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
    Napi::Value wrapped = CopyAndWrapAEDescOrThrow(env, result);
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

  auto *wrapper = UnwrapDescriptorOrThrow(
      env, info[0], "sendAppleEvent expects AEDescriptor");
  if (!wrapper) {
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
struct HandlerKey {
  AEEventClass eventClass = 0;
  AEEventID eventID = 0;

  bool operator==(const HandlerKey &other) const {
    return eventClass == other.eventClass && eventID == other.eventID;
  }

  bool operator<(const HandlerKey &other) const {
    return eventClass < other.eventClass ||
           (eventClass == other.eventClass && eventID < other.eventID);
  }
};

struct HandlerKeyHasher {
  std::size_t operator()(const HandlerKey &key) const {
    return (static_cast<std::size_t>(key.eventClass) << 32) ^
           static_cast<std::size_t>(key.eventID);
  }
};

bool ParseHandlerKeyOrThrow(const Napi::Env &env, const Napi::Value &classValue,
                            const Napi::Value &idValue, HandlerKey *outKey) {
  if (!classValue.IsString() || !idValue.IsString()) {
    Napi::TypeError::New(env,
                         "eventClass and eventID must be FourCharCode strings")
        .ThrowAsJavaScriptException();
    return false;
  }

  try {
    outKey->eventClass =
        StringToFourCharCodeOrThrow(env, classValue.As<Napi::String>());
    outKey->eventID =
        StringToFourCharCodeOrThrow(env, idValue.As<Napi::String>());
  } catch (const Napi::Error &error) {
    error.ThrowAsJavaScriptException();
    return false;
  }
  return true;
}

struct HandlerContext {
  napi_env env;
  std::thread::id jsThreadId;
  Napi::FunctionReference handlerRef;
  Napi::ThreadSafeFunction handlerTsfn;
};

std::mutex gAEJSHandlersMutex;
std::unordered_map<HandlerKey, std::unique_ptr<HandlerContext>,
                   HandlerKeyHasher>
    gAEJSHandlers;
std::atomic<uint32_t> gActiveHandlerCallbacks{0};

std::mutex gAEEventHandlerUPPsByEnvMutex;
std::unordered_map<napi_env, AEEventHandlerUPP> gAEEventHandlerUPPsByEnv;
std::unordered_set<napi_env> gEnvsWithCleanupHooks;
std::unordered_set<napi_env> gPoisonedEnvs;

static OSErr AppleEventHandlerThunk(const AppleEvent *event, AppleEvent *reply,
                                    SRefCon refCon);

static void CleanupEnvAppleEventState(void *data) {
  auto env = static_cast<napi_env>(data);

  AEEventHandlerUPP envUPP = nullptr;
  {
    std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
    auto uppIt = gAEEventHandlerUPPsByEnv.find(env);
    if (uppIt != gAEEventHandlerUPPsByEnv.end()) {
      envUPP = uppIt->second;
      gAEEventHandlerUPPsByEnv.erase(uppIt);
    }
    gEnvsWithCleanupHooks.erase(env);
    gPoisonedEnvs.erase(env);
  }

  if (!envUPP) {
    return;
  }

  std::vector<HandlerKey> keysForEnv;
  {
    std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
    for (const auto &[key, ctx] : gAEJSHandlers) {
      if (ctx && ctx->env == env) {
        keysForEnv.push_back(key);
      }
    }
  }

  for (const auto &key : keysForEnv) {
    AERemoveEventHandler(key.eventClass, key.eventID, envUPP, false);
  }

  {
    std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
    for (const auto &key : keysForEnv) {
      gAEJSHandlers.erase(key);
    }
  }

  DisposeAEEventHandlerUPP(envUPP);
}

static napi_status EnsureEnvCleanupHookRegistered(napi_env env) {
  std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
  if (gEnvsWithCleanupHooks.find(env) != gEnvsWithCleanupHooks.end()) {
    return napi_ok;
  }

  napi_status status = napi_add_env_cleanup_hook(env, CleanupEnvAppleEventState,
                                                 static_cast<void *>(env));
  if (status == napi_ok) {
    gEnvsWithCleanupHooks.insert(env);
  }
  return status;
}

static AEEventHandlerUPP GetAEHandlerUPP(napi_env env) {
  std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
  auto it = gAEEventHandlerUPPsByEnv.find(env);
  if (it == gAEEventHandlerUPPsByEnv.end()) {
    return nullptr;
  }
  return it->second;
}

static bool IsEnvPoisoned(napi_env env) {
  std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
  return gPoisonedEnvs.find(env) != gPoisonedEnvs.end();
}

static void MarkEnvPoisoned(napi_env env) {
  std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
  gPoisonedEnvs.insert(env);
}

static AEEventHandlerUPP EnsureAEHandlerUPP(napi_env env) {
  AEEventHandlerUPP existingUPP = nullptr;
  bool hasCleanupHook = false;
  {
    std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
    if (gPoisonedEnvs.find(env) != gPoisonedEnvs.end()) {
      return nullptr;
    }
    auto it = gAEEventHandlerUPPsByEnv.find(env);
    if (it != gAEEventHandlerUPPsByEnv.end()) {
      existingUPP = it->second;
    }
    hasCleanupHook =
        gEnvsWithCleanupHooks.find(env) != gEnvsWithCleanupHooks.end();
  }

  if (existingUPP) {
    // State is consistent, so we can return the cached UPP.
    if (hasCleanupHook) {
      return existingUPP;
    }

    // Repair inconsistent state: cached UPP exists but cleanup hook is missing.
    if (EnsureEnvCleanupHookRegistered(env) == napi_ok) {
      return existingUPP;
    }
    MarkEnvPoisoned(env);
    return nullptr;
  }

  if (EnsureEnvCleanupHookRegistered(env) != napi_ok) {
    MarkEnvPoisoned(env);
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(gAEEventHandlerUPPsByEnvMutex);
  auto existing = gAEEventHandlerUPPsByEnv.find(env);
  if (existing != gAEEventHandlerUPPsByEnv.end()) {
    return existing->second;
  }

  auto handler = NewAEEventHandlerUPP(AppleEventHandlerThunk);
  gAEEventHandlerUPPsByEnv[env] = handler;
  return handler;
}

static OSErr AppleEventHandlerThunk(const AppleEvent *event, AppleEvent *reply,
                                    SRefCon refCon);

Napi::Value HandleAppleEvent(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 3 || !info[0].IsString() || !info[1].IsString() ||
      !info[2].IsFunction()) {
    Napi::TypeError::New(env, "handleAppleEvent takes (eventClass: string, "
                              "eventID: string, handler: function)")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  HandlerKey key;
  if (!ParseHandlerKeyOrThrow(env, info[0], info[1], &key)) {
    return env.Undefined();
  }

  HandlerContext *ctx = nullptr;

  {
    std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);

    auto it = gAEJSHandlers.find(key);
    if (it != gAEJSHandlers.end()) {
      Napi::Error::New(env, "Handler already registered")
          .ThrowAsJavaScriptException();
      return env.Undefined();
    }

    Napi::ThreadSafeFunction tsfn = Napi::ThreadSafeFunction::New(
        env, info[2].As<Napi::Function>(), "AppleEventHandler", 0, 1);

    auto ctxPtr = std::make_unique<HandlerContext>(
        HandlerContext{env, std::this_thread::get_id(),
                       Napi::Persistent(info[2].As<Napi::Function>()), tsfn});

    HandlerContext *raw = ctxPtr.get();

    auto [insertedIt, didInsert] =
        gAEJSHandlers.emplace(key, std::move(ctxPtr));
    if (!didInsert) {
      Napi::Error::New(env, "Failed to register handler")
          .ThrowAsJavaScriptException();
      return env.Undefined();
    }

    ctx = raw;
  }

  AEEventHandlerUPP handlerUPP = EnsureAEHandlerUPP(env);
  if (!handlerUPP) {
    {
      std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
      gAEJSHandlers.erase(key);
    }
    const char *msg = IsEnvPoisoned(env)
                          ? POISONED_ENV_ERROR_MESSAGE
                          : "Failed to install Apple event handler";
    Napi::Error::New(env, msg).ThrowAsJavaScriptException();
    return env.Undefined();
  }

  OSErr err = AEInstallEventHandler(key.eventClass, key.eventID, handlerUPP,
                                    ctx, false);

  if (err != noErr) {
    std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
    gAEJSHandlers.erase(key);
    OSError::Throw(env, err, "AEInstallEventHandler failed");
    return env.Undefined();
  }

  return env.Undefined();
}

OSErr InvokeJSHandlerOnMainThreadOrThrow(const Napi::Env &env,
                                         const AppleEvent *event,
                                         AppleEvent *reply,
                                         Napi::Function handler) {
  // TODO: We actually shouldn't be doing this. It defers to any other handlers
  //    and ultimately leads to Cocoa scripting initializing, which may step on
  //    our toes and register its own event handlers for the same event IDs.
  //    If we use `events` instead of `commands` in the scripting definition,
  //    that mitigates that behavior, but we should still be careful.
  auto failAsNotHandled = [&env]() -> OSErr {
    if (env.IsExceptionPending()) {
      // Clear pending JS exception so it does not bubble out of the native
      // AppleEvent callback boundary and terminate the process.
      env.GetAndClearPendingException();
    }
    return errAEEventNotHandled;
  };

  try {
    if (!event) {
      return failAsNotHandled();
    }

    auto wrappedEvent = CopyAndWrapAEDescOrThrow(env, event);
    if (!wrappedEvent.IsObject() ||
        !wrappedEvent.As<Napi::Object>().InstanceOf(
            AEEventDescriptor::constructor.Value())) {
      return failAsNotHandled();
    }

    bool replyExpected = reply->descriptorType != typeNull;
    auto result =
        handler.Call({wrappedEvent, Napi::Boolean::New(env, replyExpected)});
    if (env.IsExceptionPending() || !result.IsObject()) {
      return failAsNotHandled();
    }

    Napi::Object resultObject = result.As<Napi::Object>();
    Napi::Array keys = resultObject.GetPropertyNames();
    for (uint32_t i = 0; i < keys.Length(); ++i) {
      Napi::Value key = keys.Get(i);
      if (!key.IsString()) {
        return failAsNotHandled();
      }
      FourCharCode keyword =
          StringToFourCharCodeOrThrow(env, key.As<Napi::String>());
      Napi::Value value = resultObject.Get(key);
      // The function expects a string error message, so we pass one even
      //    though we'll actually end up swallowing any JS exception that
      //    it throws (since we're not on a JS path here).
      auto *wrapper = UnwrapDescriptorOrThrow(
          env, value, "Reply values must be descriptors");
      if (!wrapper) {
        return failAsNotHandled();
      }
      OSErr putErr =
          AEPutParamDesc(reply, keyword, wrapper->GetRawDescriptor());
      if (putErr != noErr) {
        return putErr;
      }
    }
    return noErr;
  } catch (const Napi::Error &) {
    return failAsNotHandled();
  } catch (const std::exception &) {
    return failAsNotHandled();
  } catch (...) {
    return failAsNotHandled();
  }
}

static OSErr AppleEventHandlerThunk(const AppleEvent *event, AppleEvent *reply,
                                    SRefCon refCon) {
  HandlerContext *ctx = reinterpret_cast<HandlerContext *>(refCon);
  if (!ctx) {
    return errAEEventNotHandled;
  }
  gActiveHandlerCallbacks.fetch_add(1, std::memory_order_acq_rel);
  auto finish = []() {
    gActiveHandlerCallbacks.fetch_sub(1, std::memory_order_acq_rel);
  };
  // fast path if we're on the right thread
  if (ctx->jsThreadId == std::this_thread::get_id()) {
    Napi::HandleScope scope(ctx->env);
    Napi::Function handler = ctx->handlerRef.Value();
    OSErr result =
        InvokeJSHandlerOnMainThreadOrThrow(ctx->env, event, reply, handler);
    finish();
    return result;
  }
  // otherwise, block the main thread and call the handler
  struct CallData {
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;
    OSErr result = noErr;
  };
  CallData data;
  ctx->handlerTsfn.BlockingCall([event, reply, &data](Napi::Env env,
                                                      Napi::Function handler) {
    OSErr err = InvokeJSHandlerOnMainThreadOrThrow(env, event, reply, handler);
    std::lock_guard<std::mutex> lock(data.mtx);
    data.result = err;
    data.done = true;
    data.cv.notify_all();
  });

  {
    std::unique_lock<std::mutex> lock(data.mtx);
    data.cv.wait(lock, [&] { return data.done; });
  }
  OSErr result = data.result;
  finish();
  return result;
}

Napi::Value UnhandleAppleEvent(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsString() || !info[1].IsString()) {
    Napi::TypeError::New(env, "unhandleAppleEvent takes (eventClass: string, "
                              "eventID: string)")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  HandlerKey key;
  if (!ParseHandlerKeyOrThrow(env, info[0], info[1], &key)) {
    return env.Undefined();
  }

  if (IsEnvPoisoned(env)) {
    Napi::Error::New(env, POISONED_ENV_ERROR_MESSAGE)
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  if (gActiveHandlerCallbacks.load(std::memory_order_acquire) != 0) {
    Napi::Error::New(env, UNHANDLE_DURING_CALLBACK_ERROR_MESSAGE)
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  AEEventHandlerUPP handlerUPP = GetAEHandlerUPP(env);
  if (!handlerUPP) {
    std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
    gAEJSHandlers.erase(key);
    return env.Undefined();
  }

  OSErr err =
      AERemoveEventHandler(key.eventClass, key.eventID, handlerUPP, false);
  if (err != noErr) {
    OSError::Throw(env, err, "AERemoveEventHandler failed");
    return env.Undefined();
  }
  std::lock_guard<std::mutex> lock(gAEJSHandlersMutex);
  gAEJSHandlers.erase(key);
  return env.Undefined();
}
} // namespace Handling
} // namespace AppleEventAPI

void InitAppleEventAPI(Napi::Env env, Napi::Object exports) {
  exports.Set("sendAppleEvent",
              Napi::Function::New(env, AppleEventAPI::Sending::SendAppleEvent));
  exports.Set(
      "handleAppleEvent",
      Napi::Function::New(env, AppleEventAPI::Handling::HandleAppleEvent));
  exports.Set(
      "unhandleAppleEvent",
      Napi::Function::New(env, AppleEventAPI::Handling::UnhandleAppleEvent));
}

} // namespace ae_js_bridge
