#include "AEDescriptor.h"
#include <napi.h>

#include <cstdint>

namespace ae_js_bridge {
namespace {

#define AEJS_DEFINE_EMPTY_JS_PROPERTIES(ClassName)                             \
  std::vector<Napi::ClassPropertyDescriptor<ClassName>>                        \
  ClassName::JSProperties() {                                                  \
    return {};                                                                 \
  }

template <typename T>
bool ReadAttributeOrThrow(Napi::Env env, const AEDesc *source,
                          AEKeyword keyword, DescType expectedType, T *out,
                          const char *errorContext) {
  if (!source) {
    Napi::Error::New(env, "Uninitialized descriptor")
        .ThrowAsJavaScriptException();
    return false;
  }

  OSErr err = AEGetAttributePtr(source, keyword, expectedType, nullptr, out,
                                sizeof(T), nullptr);
  if (err != noErr) {
    OSError::Throw(env, err, errorContext);
    return false;
  }
  return true;
}

bool ReadAttributeDescOrThrow(Napi::Env env, const AEDesc *source,
                              AEKeyword keyword, AEDesc *out,
                              const char *errorContext) {
  if (!source) {
    Napi::Error::New(env, "Uninitialized descriptor")
        .ThrowAsJavaScriptException();
    return false;
  }

  OSErr err = AEGetAttributeDesc(source, keyword, typeWildCard, out);
  if (err != noErr) {
    OSError::Throw(env, err, errorContext);
    return false;
  }
  return true;
}

Napi::Object ReadKeyedItemsOrThrow(Napi::Env env, const AEDesc *source,
                                   const char *countError,
                                   const char *itemError) {
  long count = 0;
  OSErr countErr = AECountItems(source, &count);
  if (countErr != noErr) {
    OSError::Throw(env, countErr, countError);
    return Napi::Object::New(env);
  }

  Napi::Object result = Napi::Object::New(env);
  for (long index = 1; index <= count; ++index) {
    AEKeyword keyword = 0;
    AEDesc itemDesc;
    OSErr getErr =
        AEGetNthDesc(source, index, typeWildCard, &keyword, &itemDesc);
    if (getErr != noErr) {
      OSError::Throw(env, getErr, itemError);
      return Napi::Object::New(env);
    }

    Napi::Value wrappedItem = CopyAndWrapAEDescOrThrow(env, &itemDesc);
    AEDisposeDesc(&itemDesc);
    if (env.IsExceptionPending()) {
      return Napi::Object::New(env);
    }
    result.Set(FourCharCodeToString(keyword), wrappedItem);
  }

  return result;
}

template <typename PutFn>
bool InsertKeywordMap(Napi::Env env, AEDesc *target, const Napi::Object &map,
                      const char *invalidValueMessage, const char *putError,
                      PutFn putFn) {
  Napi::Array keys = map.GetPropertyNames();
  const uint32_t length = keys.Length();
  for (uint32_t i = 0; i < length; ++i) {
    Napi::Value keyValue = keys[i];
    if (!keyValue.IsString()) {
      continue;
    }

    FourCharCode keyword =
        StringToFourCharCode(keyValue.As<Napi::String>().Utf8Value());
    if (keyword == 0) {
      Napi::Error::New(env, "Invalid keyword").ThrowAsJavaScriptException();
      return false;
    }

    Napi::Value entry = map.Get(keyValue);
    auto *wrapper = UnwrapDescriptorOrThrow(env, entry, invalidValueMessage);
    if (!wrapper) {
      return false;
    }

    OSErr err = putFn(target, keyword, wrapper->GetRawDescriptor());
    if (err != noErr) {
      OSError::Throw(env, err, putError);
      return false;
    }
  }
  return true;
}

enum class DescriptorKind {
  Null,
  Data,
  List,
  Record,
  Event,
  Unknown,
};

DescriptorKind GetDescriptorKind(const AEDesc *desc) {
  if (!desc) {
    return DescriptorKind::Unknown;
  }
  switch (desc->descriptorType) {
  case typeNull:
    return DescriptorKind::Null;
  case typeAppleEvent:
    return DescriptorKind::Event;
  default:
    long itemCount = 0;
    OSErr err = AECountItems(desc, &itemCount);
    if (err == errAEWrongDataType) {
      return DescriptorKind::Data;
    } else if (err != noErr) {
      return DescriptorKind::Unknown;
    }
    return AECheckIsRecord(desc) ? DescriptorKind::Record
                                 : DescriptorKind::List;
  }
}

} // namespace

AEDescriptorWrapper<AEDescriptor> *
UnwrapDescriptorOrThrow(const Napi::Env &env, const Napi::Value &value,
                        const char *errorMessage) {
  if (!value.IsObject()) {
    Napi::TypeError::New(env, errorMessage).ThrowAsJavaScriptException();
    return nullptr;
  }

  auto *wrapper =
      Napi::ObjectWrap<AEDescriptor>::Unwrap(value.As<Napi::Object>());
  if (!wrapper) {
    Napi::TypeError::New(env, errorMessage).ThrowAsJavaScriptException();
    return nullptr;
  }

  return wrapper;
}

Napi::Value CopyAndWrapAEDescOrThrow(Napi::Env env, const AEDesc *desc) {
  AEDesc *copyDesc = new AEDesc;
  OSErr err = AEDuplicateDesc(desc, copyDesc);
  if (err != noErr) {
    delete copyDesc;
    OSError::Throw(env, err, "AEDuplicateDesc failed");
    return env.Undefined();
  }
  DescriptorKind kind = GetDescriptorKind(copyDesc);
  switch (kind) {
  case DescriptorKind::Null:
    return AENullDescriptor::WrapAEDesc(env, copyDesc);
  case DescriptorKind::Data:
    return AEDataDescriptor::WrapAEDesc(env, copyDesc);
  case DescriptorKind::List:
    return AEListDescriptor::WrapAEDesc(env, copyDesc);
  case DescriptorKind::Record:
    return AERecordDescriptor::WrapAEDesc(env, copyDesc);
  case DescriptorKind::Event:
    return AEEventDescriptor::WrapAEDesc(env, copyDesc);
  case DescriptorKind::Unknown:
    return AEUnknownDescriptor::WrapAEDesc(env, copyDesc);
  }

  return AEUnknownDescriptor::WrapAEDesc(env, copyDesc);
}

void AEDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::TypeError::New(info.Env(),
                       "AEDescriptor is abstract and not constructable")
      .ThrowAsJavaScriptException();
}

AEJS_DEFINE_EMPTY_JS_PROPERTIES(AEDescriptor)

void AENullDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 0) {
    Napi::TypeError::New(env, "AENullDescriptor takes no arguments")
        .ThrowAsJavaScriptException();
    return;
  }

  desc = new AEDesc;
  OSErr err = AECreateDesc(typeNull, nullptr, 0, desc);
  if (err != noErr) {
    delete desc;
    desc = nullptr;
    OSError::Throw(env, err, "AECreateDesc(typeNull) failed");
  }
}

AEJS_DEFINE_EMPTY_JS_PROPERTIES(AENullDescriptor)

void AEDataDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsString() || !info[1].IsTypedArray()) {
    Napi::TypeError::New(env, "AEDataDescriptor takes (type, Uint8Array)")
        .ThrowAsJavaScriptException();
    return;
  }

  FourCharCode type =
      StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
  if (type == 0) {
    Napi::Error::New(env, "Invalid descriptor type")
        .ThrowAsJavaScriptException();
    return;
  }
  Napi::Uint8Array array = info[1].As<Napi::Uint8Array>();

  desc = new AEDesc;
  OSErr err = AECreateDesc(type, array.Data(), array.ByteLength(), desc);
  if (err != noErr) {
    delete desc;
    desc = nullptr;
    OSError::Throw(env, err, "AECreateDesc failed");
  }
}

Napi::Value AEDataDescriptor::GetDataOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (!desc) {
    Napi::Error::New(env, "Uninitialized descriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  const Size size = AEGetDescDataSize(desc);
  if (size < 0) {
    Napi::Error::New(env, "AEGetDescDataSize failed")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  Napi::Buffer<uint8_t> buffer =
      Napi::Buffer<uint8_t>::New(env, static_cast<size_t>(size));
  OSErr err = AEGetDescData(desc, buffer.Data(), size);
  if (err != noErr) {
    OSError::Throw(env, err, "AEGetDescData failed");
    return env.Null();
  }

  return buffer;
}

std::vector<Napi::ClassPropertyDescriptor<AEDataDescriptor>>
AEDataDescriptor::JSProperties() {
  return {
      InstanceAccessor("data", &AEDataDescriptor::GetDataOrThrow, nullptr),
  };
}

void AEListDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsString() || !info[1].IsArray()) {
    Napi::TypeError::New(env, "AEListDescriptor takes (type, AEDescriptor[])")
        .ThrowAsJavaScriptException();
    return;
  }

  FourCharCode type =
      StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
  if (type == 0) {
    Napi::Error::New(env, "Invalid descriptor type")
        .ThrowAsJavaScriptException();
    return;
  }
  Napi::Array items = info[1].As<Napi::Array>();

  desc = new AEDesc;
  OSErr err = AECreateList(nullptr, 0, false, desc);
  if (err != noErr) {
    delete desc;
    desc = nullptr;
    OSError::Throw(env, err, "AECreateList failed");
    return;
  }

  desc->descriptorType = type;
  const uint32_t length = items.Length();
  for (uint32_t i = 0; i < length; ++i) {
    auto *wrapper =
        UnwrapDescriptorOrThrow(env, items[i], "Invalid AEDescriptor item");
    if (!wrapper) {
      return;
    }

    OSErr putErr = AEPutDesc(desc, 0, wrapper->GetRawDescriptor());
    if (putErr != noErr) {
      OSError::Throw(env, putErr, "AEPutDesc failed");
      return;
    }
  }
}

Napi::Value AEListDescriptor::GetItemsOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  long count = 0;
  OSErr countErr = AECountItems(desc, &count);
  if (countErr != noErr) {
    OSError::Throw(env, countErr, "AECountItems failed");
    return env.Null();
  }

  Napi::Array result = Napi::Array::New(env, static_cast<uint32_t>(count));
  for (long index = 1; index <= count; ++index) {
    AEDesc itemDesc;
    OSErr getErr = AEGetNthDesc(desc, index, typeWildCard, nullptr, &itemDesc);
    if (getErr != noErr) {
      OSError::Throw(env, getErr, "AEGetNthDesc failed");
      return env.Null();
    }

    Napi::Value wrappedItem = CopyAndWrapAEDescOrThrow(env, &itemDesc);
    AEDisposeDesc(&itemDesc);
    if (env.IsExceptionPending()) {
      return env.Null();
    }
    result.Set(static_cast<uint32_t>(index - 1), wrappedItem);
  }

  return result;
}

std::vector<Napi::ClassPropertyDescriptor<AEListDescriptor>>
AEListDescriptor::JSProperties() {
  return {
      InstanceAccessor("items", &AEListDescriptor::GetItemsOrThrow, nullptr),
  };
}

void AERecordDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 2 || !info[0].IsString() || !info[1].IsObject()) {
    Napi::TypeError::New(
        env, "AERecordDescriptor takes (type, Record<AEKeyword, AEDescriptor>)")
        .ThrowAsJavaScriptException();
    return;
  }

  FourCharCode type =
      StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
  if (type == 0) {
    Napi::Error::New(env, "Invalid descriptor type")
        .ThrowAsJavaScriptException();
    return;
  }
  Napi::Object fields = info[1].As<Napi::Object>();

  desc = new AEDesc;
  OSErr err = AECreateList(nullptr, 0, true, desc);
  if (err != noErr) {
    delete desc;
    desc = nullptr;
    OSError::Throw(env, err, "AECreateList(record) failed");
    return;
  }

  desc->descriptorType = type;
  if (!InsertKeywordMap(
          env, desc, fields, "Record values must be AEDescriptor",
          "AEPutKeyDesc failed",
          [](AEDesc *target, AEKeyword keyword, const AEDesc *value) {
            return AEPutKeyDesc(target, keyword, value);
          })) {
    return;
  }
}

Napi::Value
AERecordDescriptor::GetFieldsOrThrow(const Napi::CallbackInfo &info) {
  return ReadKeyedItemsOrThrow(info.Env(), desc, "AECountItems failed",
                               "AEGetNthDesc failed");
}

std::vector<Napi::ClassPropertyDescriptor<AERecordDescriptor>>
AERecordDescriptor::JSProperties() {
  return {
      InstanceAccessor("fields", &AERecordDescriptor::GetFieldsOrThrow,
                       nullptr),
  };
}

void AEEventDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 7 || !info[0].IsString() || !info[1].IsString() ||
      !info[2].IsObject() || !info[3].IsNumber() || !info[4].IsNumber() ||
      !info[5].IsObject() || !info[6].IsObject()) {
    Napi::TypeError::New(
        env, "AEEventDescriptor takes (eventClass, eventID, target, returnID, "
             "transactionID, parameters, attributes)")
        .ThrowAsJavaScriptException();
    return;
  }

  FourCharCode eventClass =
      StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
  if (eventClass == 0) {
    Napi::Error::New(env, "Invalid event class").ThrowAsJavaScriptException();
    return;
  }
  FourCharCode eventID =
      StringToFourCharCode(info[1].As<Napi::String>().Utf8Value());
  if (eventID == 0) {
    Napi::Error::New(env, "Invalid event ID").ThrowAsJavaScriptException();
    return;
  }

  auto *targetWrapper =
      UnwrapDescriptorOrThrow(env, info[2], "Invalid target descriptor");
  if (!targetWrapper) {
    return;
  }

  AEReturnID returnID =
      static_cast<AEReturnID>(info[3].As<Napi::Number>().Int32Value());
  AETransactionID transactionID =
      static_cast<AETransactionID>(info[4].As<Napi::Number>().Int32Value());
  Napi::Object parameters = info[5].As<Napi::Object>();
  Napi::Object attributes = info[6].As<Napi::Object>();

  desc = new AEDesc;
  OSErr err =
      AECreateAppleEvent(eventClass, eventID, targetWrapper->GetRawDescriptor(),
                         returnID, transactionID, desc);
  if (err != noErr) {
    delete desc;
    desc = nullptr;
    OSError::Throw(env, err, "AECreateAppleEvent failed");
    return;
  }

  if (!InsertKeywordMap(
          env, desc, parameters, "Parameter values must be AEDescriptor",
          "AEPutParamDesc failed",
          [](AEDesc *target, AEKeyword keyword, const AEDesc *value) {
            return AEPutParamDesc(target, keyword, value);
          })) {
    return;
  }

  InsertKeywordMap(env, desc, attributes,
                   "Attribute values must be AEDescriptor",
                   "AEPutAttributeDesc failed",
                   [](AEDesc *target, AEKeyword keyword, const AEDesc *value) {
                     return AEPutAttributeDesc(target, keyword, value);
                   });
}

Napi::Value
AEEventDescriptor::GetEventClassOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  AEEventClass eventClass = 0;
  if (!ReadAttributeOrThrow(env, desc, keyEventClassAttr, typeType, &eventClass,
                            "AEGetAttributePtr(keyEventClassAttr) failed")) {
    return env.Null();
  }
  return Napi::String::New(env, FourCharCodeToString(eventClass));
}

Napi::Value
AEEventDescriptor::GetEventIDOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  AEEventID eventID = 0;
  if (!ReadAttributeOrThrow(env, desc, keyEventIDAttr, typeType, &eventID,
                            "AEGetAttributePtr(keyEventIDAttr) failed")) {
    return env.Null();
  }
  return Napi::String::New(env, FourCharCodeToString(eventID));
}

Napi::Value
AEEventDescriptor::GetTargetOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  AEDesc targetDesc;
  if (!ReadAttributeDescOrThrow(env, desc, keyAddressAttr, &targetDesc,
                                "AEGetAttributeDesc(keyAddressAttr) failed")) {
    return env.Null();
  }
  Napi::Value wrappedTarget = CopyAndWrapAEDescOrThrow(env, &targetDesc);
  AEDisposeDesc(&targetDesc);
  return wrappedTarget;
}

Napi::Value
AEEventDescriptor::GetReturnIDOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  int16_t returnID = 0;
  if (!ReadAttributeOrThrow(env, desc, keyReturnIDAttr, typeSInt16, &returnID,
                            "AEGetAttributePtr(keyReturnIDAttr) failed")) {
    return env.Null();
  }
  return Napi::Number::New(env, returnID);
}

Napi::Value
AEEventDescriptor::GetTransactionIDOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  int32_t transactionID = 0;
  if (!ReadAttributeOrThrow(env, desc, keyTransactionIDAttr, typeSInt32,
                            &transactionID,
                            "AEGetAttributePtr(keyTransactionIDAttr) failed")) {
    return env.Null();
  }
  return Napi::Number::New(env, transactionID);
}

Napi::Value
AEEventDescriptor::GetParametersOrThrow(const Napi::CallbackInfo &info) {
  return ReadKeyedItemsOrThrow(info.Env(), desc, "AECountItems failed",
                               "AEGetNthDesc failed");
}

Napi::Value
AEEventDescriptor::GetAttributeOrThrow(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() != 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "getAttribute takes (keyword)")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }

  FourCharCode keyword =
      StringToFourCharCode(info[0].As<Napi::String>().Utf8Value());
  if (keyword == 0) {
    Napi::Error::New(env, "Invalid attribute keyword")
        .ThrowAsJavaScriptException();
    return env.Undefined();
  }
  AEDesc attributeDesc;
  OSErr err = AEGetAttributeDesc(desc, keyword, typeWildCard, &attributeDesc);
  if (err != noErr) {
    return env.Undefined();
  }

  Napi::Value wrappedAttribute = CopyAndWrapAEDescOrThrow(env, &attributeDesc);
  AEDisposeDesc(&attributeDesc);
  return wrappedAttribute;
}

std::vector<Napi::ClassPropertyDescriptor<AEEventDescriptor>>
AEEventDescriptor::JSProperties() {
  return {
      InstanceAccessor("eventClass", &AEEventDescriptor::GetEventClassOrThrow,
                       nullptr),
      InstanceAccessor("eventID", &AEEventDescriptor::GetEventIDOrThrow,
                       nullptr),
      InstanceAccessor("target", &AEEventDescriptor::GetTargetOrThrow, nullptr),
      InstanceAccessor("returnID", &AEEventDescriptor::GetReturnIDOrThrow,
                       nullptr),
      InstanceAccessor("transactionID",
                       &AEEventDescriptor::GetTransactionIDOrThrow, nullptr),
      InstanceAccessor("parameters", &AEEventDescriptor::GetParametersOrThrow,
                       nullptr),
      InstanceMethod("getAttribute", &AEEventDescriptor::GetAttributeOrThrow),
  };
}

void AEUnknownDescriptor::InitFromJS(const Napi::CallbackInfo &info) {
  Napi::TypeError::New(
      info.Env(), "AEUnknownDescriptor cannot be constructed from JavaScript")
      .ThrowAsJavaScriptException();
}

AEJS_DEFINE_EMPTY_JS_PROPERTIES(AEUnknownDescriptor)

#undef AEJS_DEFINE_EMPTY_JS_PROPERTIES

} // namespace ae_js_bridge