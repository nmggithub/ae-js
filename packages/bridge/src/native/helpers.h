#pragma once

#include <napi.h>

#include <MacTypes.h>

namespace ae_js_bridge {
FourCharCode StringToFourCharCodeOrThrow(const Napi::Env &env,
                                         const Napi::String &str);
Napi::String FourCharCodeToStringOrThrow(const Napi::Env &env,
                                         FourCharCode fourCharCode);
} // namespace ae_js_bridge