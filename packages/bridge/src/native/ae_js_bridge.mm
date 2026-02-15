#include "AEDescriptor.h"
#include "AppleEventAPI.h"
#include "OSError.h"
#include <napi.h>

static Napi::Object Init(Napi::Env env, Napi::Object exports) {
  ae_js_bridge::Descriptors::AEDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AENullDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AEDataDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AEListDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AERecordDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AEEventDescriptor::Init(env, exports);
  ae_js_bridge::Descriptors::AEUnknownDescriptor::Init(env, exports);

  ae_js_bridge::AppleEventAPI::Init(env, exports);
  exports.Set("OSError", ae_js_bridge::InitOSError(env));
  return exports;
}
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
