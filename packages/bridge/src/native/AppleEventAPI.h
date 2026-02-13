#pragma once

#include <napi.h>

namespace ae_js_bridge {

void InitAppleEventAPI(Napi::Env env, Napi::Object exports);

} // namespace ae_js_bridge
