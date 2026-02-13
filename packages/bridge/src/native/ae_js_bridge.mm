#include "AEDescriptor.h"
#include "AppleEventAPI.h"
#include "OSError.h"
#include <napi.h>

static Napi::Object Init(Napi::Env env, Napi::Object exports) {
  ae_js_bridge::AEDescriptor::Init(env, exports);
  ae_js_bridge::AENullDescriptor::Init(env, exports);
  ae_js_bridge::AEDataDescriptor::Init(env, exports);
  ae_js_bridge::AEListDescriptor::Init(env, exports);
  ae_js_bridge::AERecordDescriptor::Init(env, exports);
  ae_js_bridge::AEEventDescriptor::Init(env, exports);
  ae_js_bridge::AEUnknownDescriptor::Init(env, exports);

  ae_js_bridge::InitAppleEventAPI(env, exports);
  exports.Set("OSError", ae_js_bridge::InitOSError(env));
  return exports;
}
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
