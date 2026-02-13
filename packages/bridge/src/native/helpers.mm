#include "helpers.h"

#include <napi.h>

#include <MacTypes.h>

namespace ae_js_bridge {

FourCharCode StringToFourCharCodeOrThrow(const Napi::Env &env,
                                         const Napi::String &str) {
  std::string s = str.Utf8Value();
  if (s.length() != 4) {
    throw Napi::Error::New(env, "Invalid FourCharCode string");
  }
  return (static_cast<uint8_t>(s[0]) << 24) |
         (static_cast<uint8_t>(s[1]) << 16) |
         (static_cast<uint8_t>(s[2]) << 8) | (static_cast<uint8_t>(s[3]));
}

Napi::String FourCharCodeToStringOrThrow(const Napi::Env &env,
                                         FourCharCode fourCharCode) {
  std::string s;
  s.reserve(4);
  s.push_back(static_cast<char>((fourCharCode >> 24) & 0xFF));
  s.push_back(static_cast<char>((fourCharCode >> 16) & 0xFF));
  s.push_back(static_cast<char>((fourCharCode >> 8) & 0xFF));
  s.push_back(static_cast<char>(fourCharCode & 0xFF));
  return Napi::String::New(env, s);
}

} // namespace ae_js_bridge
