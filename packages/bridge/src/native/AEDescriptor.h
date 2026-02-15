#pragma once

#include "OSError.h"
#include "helpers.h"

#include <CoreServices/CoreServices.h>
#include <napi.h>

#include <stdexcept>
#include <type_traits>
#include <vector>

namespace ae_js_bridge {

#define AEJS_CPP_DESCRIPTOR_CLASS_COMMON(ClassName)                            \
public:                                                                        \
  static constexpr const char *JSClassName = #ClassName;                       \
  using AEDescriptorWrapper<ClassName>::AEDescriptorWrapper;                   \
  void InitFromJS(const Napi::CallbackInfo &info);                             \
  static std::vector<Napi::ClassPropertyDescriptor<ClassName>> JSProperties();

template <typename Derived> class AEDescriptorWrapper;
class AEDescriptor;
class AENullDescriptor;
class AEDataDescriptor;
class AEListDescriptor;
class AERecordDescriptor;
class AEEventDescriptor;
class AEUnknownDescriptor;
Napi::Value CopyAndWrapAEDescOrThrow(Napi::Env env, const AEDesc *desc);

template <typename Derived>
class AEDescriptorWrapper : public Napi::ObjectWrap<Derived> {
public:
  static Napi::FunctionReference constructor;
  AEDesc *desc = nullptr;

  explicit AEDescriptorWrapper(const Napi::CallbackInfo &info)
      : Napi::ObjectWrap<Derived>(info) {
    if (info.Length() == 1 && info[0].IsExternal()) {
      desc = info[0].As<Napi::External<AEDesc>>().Data();
      return;
    }

    static_cast<Derived *>(this)->InitFromJS(info);
    if (!desc && !info.Env().IsExceptionPending()) {
      Napi::Error::New(info.Env(), "Descriptor initialization failed")
          .ThrowAsJavaScriptException();
    }
  }

public:
  ~AEDescriptorWrapper() override {
    if (desc) {
      AEDisposeDesc(desc);
      delete desc;
    }
  }

  const AEDesc *GetRawDescriptor() const { return desc; }

  DescType GetRawDescriptorType() const {
    if (!desc) {
      throw std::runtime_error("Uninitialized AEDesc");
    }
    return desc->descriptorType;
  }

  Napi::Value GetDescriptorTypeOrThrow(const Napi::CallbackInfo &info) {
    return Napi::String::New(info.Env(),
                             FourCharCodeToString(GetRawDescriptorType()));
  }

  Napi::Value AsOrThrow(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    if (info.Length() != 1 || !info[0].IsString()) {
      Napi::TypeError::New(env, "as(descriptorType) expects a string")
          .ThrowAsJavaScriptException();
      return env.Null();
    }

    if (!desc) {
      Napi::Error::New(env, "Uninitialized descriptor")
          .ThrowAsJavaScriptException();
      return env.Null();
    }

    FourCharCode targetType =
        StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
    if (targetType == 0) {
      Napi::Error::New(env, "Invalid descriptor type")
          .ThrowAsJavaScriptException();
      return env.Null();
    }

    AEDesc *coerced = new AEDesc;
    OSErr err = AECoerceDesc(desc, targetType, coerced);
    if (err != noErr) {
      delete coerced;
      OSError::Throw(env, err, "AECoerceDesc failed");
      return env.Null();
    }

    return WrapAEDesc(env, coerced);
  }

  static Napi::Object WrapAEDesc(Napi::Env env, AEDesc *rawDesc) {
    return constructor.New({Napi::External<AEDesc>::New(env, rawDesc)});
  }

  static void Init(Napi::Env env, Napi::Object exports) {
    std::vector<Napi::ClassPropertyDescriptor<Derived>> properties = {
        Derived::InstanceAccessor("descriptorType",
                                  &Derived::GetDescriptorTypeOrThrow, nullptr),
        Derived::InstanceMethod("as", &Derived::AsOrThrow),
    };

    std::vector<Napi::ClassPropertyDescriptor<Derived>> extraProperties =
        Derived::JSProperties();
    properties.insert(properties.end(), extraProperties.begin(),
                      extraProperties.end());

    Napi::Function ctor =
        Derived::DefineClass(env, Derived::JSClassName, properties);

    // Don't set the prototype chain for AEDescriptor itself.
    if constexpr (!std::is_same_v<Derived, AEDescriptor>) {
      Napi::Value objectValue = env.Global().Get("Object");
      if (objectValue.IsObject()) {
        Napi::Object object = objectValue.As<Napi::Object>();
        Napi::Value setPrototypeOfValue = object.Get("setPrototypeOf");
        if (setPrototypeOfValue.IsFunction()) {
          Napi::Function setPrototypeOf =
              setPrototypeOfValue.As<Napi::Function>();
          Napi::Value baseCtorValue = exports.Get("AEDescriptor");
          if (baseCtorValue.IsFunction()) {
            Napi::Function baseCtor = baseCtorValue.As<Napi::Function>();
            Napi::Value ctorPrototype = ctor.Get("prototype");
            Napi::Value basePrototype = baseCtor.Get("prototype");
            if (ctorPrototype.IsObject() && basePrototype.IsObject()) {
              setPrototypeOf.Call(object, {ctorPrototype, basePrototype});
            }
            setPrototypeOf.Call(object, {ctor, baseCtor});
          }
        }
      }
    }

    constructor = Napi::Persistent(ctor);
    constructor.SuppressDestruct();
    exports.Set(Derived::JSClassName, ctor);
  }
};

template <typename Derived>
Napi::FunctionReference AEDescriptorWrapper<Derived>::constructor;

class AEDescriptor : public AEDescriptorWrapper<AEDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AEDescriptor)
};

class AENullDescriptor : public AEDescriptorWrapper<AENullDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AENullDescriptor)
};

class AEDataDescriptor : public AEDescriptorWrapper<AEDataDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AEDataDescriptor)
  Napi::Value GetDataOrThrow(const Napi::CallbackInfo &info);
};

class AEListDescriptor : public AEDescriptorWrapper<AEListDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AEListDescriptor)
  Napi::Value GetItemsOrThrow(const Napi::CallbackInfo &info);
};

class AERecordDescriptor : public AEDescriptorWrapper<AERecordDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AERecordDescriptor)
  Napi::Value GetFieldsOrThrow(const Napi::CallbackInfo &info);
};

class AEEventDescriptor : public AEDescriptorWrapper<AEEventDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AEEventDescriptor)
  Napi::Value GetEventClassOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetEventIDOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetTargetOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetReturnIDOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetTransactionIDOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetParametersOrThrow(const Napi::CallbackInfo &info);
  Napi::Value GetAttributeOrThrow(const Napi::CallbackInfo &info);
};

class AEUnknownDescriptor : public AEDescriptorWrapper<AEUnknownDescriptor> {
  AEJS_CPP_DESCRIPTOR_CLASS_COMMON(AEUnknownDescriptor)
};

AEDescriptorWrapper<AEDescriptor> *
UnwrapDescriptorOrThrow(const Napi::Env &env, const Napi::Value &value,
                        const char *errorMessage);

#undef AEJS_CPP_DESCRIPTOR_CLASS_COMMON

} // namespace ae_js_bridge