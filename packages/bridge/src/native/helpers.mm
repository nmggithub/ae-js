#include "helpers.h"

#include <cstddef>
#include <napi.h>

#include <MacTypes.h>

namespace ae_js_bridge {

FourCharCode StringToFourCharCode(const std::string &s) {
  if (s.length() != 4) {
    return 0;
  }
  return (static_cast<uint8_t>(s[0]) << 24) |
         (static_cast<uint8_t>(s[1]) << 16) |
         (static_cast<uint8_t>(s[2]) << 8) | (static_cast<uint8_t>(s[3]));
}

std::string FourCharCodeToString(FourCharCode fourCharCode) {
  std::string s;
  s.reserve(4);
  s.push_back(static_cast<char>((fourCharCode >> 24) & 0xFF));
  s.push_back(static_cast<char>((fourCharCode >> 16) & 0xFF));
  s.push_back(static_cast<char>((fourCharCode >> 8) & 0xFF));
  s.push_back(static_cast<char>(fourCharCode & 0xFF));
  return std::string(s);
}

} // namespace ae_js_bridge
