#include "OSError.h"

#include <CoreServices/CoreServices.h>

#include <string>
namespace ae_js_bridge {
namespace {
Napi::FunctionReference gOSErrorCtor;
}

static void SetPrototypeOf(Napi::Env env, const Napi::Object &obj,
                           const Napi::Value &proto) {
  Napi::Value objectValue = env.Global().Get("Object");
  if (!objectValue.IsObject())
    return;
  Napi::Object object = objectValue.As<Napi::Object>();
  Napi::Value setPrototypeOfValue = object.Get("setPrototypeOf");
  if (!setPrototypeOfValue.IsFunction())
    return;
  Napi::Function setPrototypeOf = setPrototypeOfValue.As<Napi::Function>();
  // Object.setPrototypeOf(obj, proto)
  setPrototypeOf.Call(object, {obj, proto});
}

std::string OSError::ResolveMessage(OSErr code) {
  std::string errorString = std::string(GetMacOSStatusErrorString(code));
  if (errorString.empty())
    errorString = "Unknown error";
  std::string errorComment = std::string(GetMacOSStatusCommentString(code));
  if (errorComment.empty())
    errorComment = "Unknown comment";
  return errorString + " (" + errorComment + ")";
}

Napi::Object OSError::New(Napi::Env env, OSErr code,
                          const std::string &message) {
  const std::string incomingMessage =
      !message.empty() ? message : "Something went wrong";

  const std::string resolvedMessage = incomingMessage + " [" +
                                      OSError::ResolveMessage(code) +
                                      "] (code: " + std::to_string(code) + ")";

  Napi::Function errorCtor = env.Global().Get("Error").As<Napi::Function>();
  Napi::Object err = errorCtor.New({Napi::String::New(env, resolvedMessage)});
  err.Set("name", Napi::String::New(env, "OSError"));
  err.Set("code", Napi::Number::New(env, static_cast<int32_t>(code)));

  // Ensure `instanceof OSError` works when the constructor has been
  // initialized.
  if (!gOSErrorCtor.IsEmpty()) {
    Napi::Object osProto =
        gOSErrorCtor.Value().Get("prototype").As<Napi::Object>();
    SetPrototypeOf(env, err, osProto);
  }
  return err;
}

void OSError::Throw(Napi::Env env, OSErr code, const std::string &message) {
  Napi::Object err = OSError::New(env, code, message);
  // Throw the constructed Error object directly.
  napi_throw(env, err);
}
static Napi::Value OSErrorConstructor(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  int32_t code = 0;
  if (info.Length() >= 1 && info[0].IsNumber()) {
    code = info[0].As<Napi::Number>().Int32Value();
  }
  std::string message;
  if (info.Length() >= 2 && info[1].IsString()) {
    message = info[1].As<Napi::String>().Utf8Value();
  }
  return OSError::New(env, static_cast<OSErr>(code), message);
}
Napi::Function InitOSError(Napi::Env env) {
  Napi::Function ctor = Napi::Function::New(env, OSErrorConstructor, "OSError");

  // Make `OSError.prototype` inherit from `Error.prototype` so:
  // - `new OSError(...) instanceof Error` is true
  // - and instances we re-prototype are also `instanceof OSError`
  Napi::Function errorCtor = env.Global().Get("Error").As<Napi::Function>();
  Napi::Object errorProto = errorCtor.Get("prototype").As<Napi::Object>();
  Napi::Object osProto = ctor.Get("prototype").As<Napi::Object>();
  SetPrototypeOf(env, osProto, errorProto);

  gOSErrorCtor = Napi::Persistent(ctor);
  gOSErrorCtor.SuppressDestruct();
  return ctor;
}
} // namespace ae_js_bridge
