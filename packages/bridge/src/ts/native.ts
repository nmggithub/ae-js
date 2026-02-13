import { createRequire } from 'node:module';

import type * as _bindingType from '#ae_js_bridge_native';

const require = createRequire(import.meta.url);
const _binding = require('../build/Release/ae_js_bridge_native.node') as
    typeof import('#ae_js_bridge_native');

const {
    AEDescriptor,
    AENullDescriptor,
    AEDataDescriptor,
    AEListDescriptor,
    AERecordDescriptor,
    AEEventDescriptor,
    AEUnknownDescriptor,
    OSError,
    sendAppleEvent,
    handleAppleEvent,
    unhandleAppleEvent,
} = _binding;
export {
    AEDescriptor,
    AENullDescriptor,
    AEDataDescriptor,
    AEListDescriptor,
    AERecordDescriptor,
    AEEventDescriptor,
    AEUnknownDescriptor,
    OSError,
    sendAppleEvent,
    handleAppleEvent,
    unhandleAppleEvent,
};
export type { _bindingType as AEJSBridgeNative };
