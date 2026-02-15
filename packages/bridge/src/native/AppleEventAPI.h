#pragma once

#include <napi.h>

namespace ae_js_bridge {
namespace AppleEventAPI {
void Init(Napi::Env env, Napi::Object exports);
} // namespace AppleEventAPI
} // namespace ae_js_bridge
