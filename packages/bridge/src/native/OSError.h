#pragma once

#include <napi.h>

#include <string>

#include <MacTypes.h>

namespace ae_js_bridge {

class OSError {
 public:
  static Napi::Object New(Napi::Env env, OSErr code,
                          const std::string& message = std::string());

  static void Throw(Napi::Env env, OSErr code,
                    const std::string& message = std::string());

 private:
  static std::string ResolveMessage(OSErr code);
};


Napi::Function InitOSError(Napi::Env env);

}  // namespace ae_js_bridge
