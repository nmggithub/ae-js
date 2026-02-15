#pragma once

#include <napi.h>

#include <MacTypes.h>

namespace ae_js_bridge {
FourCharCode StringToFourCharCode(const std::string &s);
std::string FourCharCodeToString(FourCharCode fourCharCode);
} // namespace ae_js_bridge