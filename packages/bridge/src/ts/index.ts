
import {
    type AEJSBridgeNative,
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
} from './native.js';

import { endianness } from 'node:os';

/**
 * A JavaScript wrapper for an Apple event descriptor.
 * @template T - The type of the descriptor.
 */
abstract class AEJSDescriptor<T extends AEJSBridgeNative.AEDescriptor> {
    /**
     * The native descriptor.
     */
    protected nativeDescriptor: T;

    /**
     * Creates a new JavaScript wrapper for an Apple event descriptor.
     * @param nativeDescriptor - The native descriptor.
     */
    protected constructor(nativeDescriptor: T) {
        this.nativeDescriptor = nativeDescriptor;
    }

    /**
     * Gets the type of the descriptor.
     * @returns The type of the descriptor.
     */
    public get descriptorType(): AEJSBridgeNative.DescType {
        return this.nativeDescriptor.descriptorType;
    }

    /**
     * Creates a new JavaScript wrapper for an Apple event descriptor from a native descriptor.
     * @param nativeDescriptor - The native descriptor.
     * @returns The JavaScript wrapper for the descriptor.
     */
    static fromNative
        (native: AEJSBridgeNative.AENullDescriptor): AEJSNullDescriptor;
    static fromNative
        (native: AEJSBridgeNative.AEDataDescriptor): AEJSDataDescriptor;
    static fromNative
        (native: AEJSBridgeNative.AEListDescriptor): AEJSListDescriptor;
    static fromNative
        (native: AEJSBridgeNative.AERecordDescriptor): AEJSRecordDescriptor;
    static fromNative
        (native: AEJSBridgeNative.AEEventDescriptor): AEJSEventDescriptor;
    static fromNative
        (native: AEJSBridgeNative.AEUnknownDescriptor): AEJSUnknownDescriptor {
        if (native instanceof AENullDescriptor)
            return new AEJSNullDescriptor();
        if (native instanceof AEDataDescriptor)
            return new AEJSDataDescriptor(native);
        if (native instanceof AEListDescriptor)
            return new AEJSListDescriptor(native);
        if (native instanceof AERecordDescriptor)
            return new AEJSRecordDescriptor(native);
        if (native instanceof AEEventDescriptor)
            return new AEJSEventDescriptor(native);
        if (native instanceof AEUnknownDescriptor)
            return new AEJSUnknownDescriptor(native);
        throw new TypeError('Invalid native descriptor');
    }

    /**
     * Gets a copy of the native descriptor.
     * @returns A copy of the native descriptor.
     */
    public toNative(): T {
        return this.nativeDescriptor
            // Use coercion to the same type in lieu of a copy constructor.
            .as(this.nativeDescriptor.descriptorType);
    }

    /**
     * Gets the string value of the descriptor.
     * @returns The string value of the descriptor.
     */
    public toString(): string {
        const asString: AEJSBridgeNative.AEDataDescriptor
            = this.nativeDescriptor.as('utf8');
        return new TextDecoder('utf-8').decode(asString.data);
    }

    /**
     * Gets the number value of the descriptor.
     * @returns The number value of the descriptor.
     */
    public asNumber(): number {
        const asNumber: AEJSBridgeNative.AEDataDescriptor
            // 'doub' is IEEE 64-bit floating point number, the
            //  same as JavaScript's Number type.
            = this.nativeDescriptor.as('doub');
        return new DataView(asNumber.data.buffer)
            .getFloat64(0, endianness() === 'LE');
    }

    /**
     * Gets the boolean value of the descriptor.
     * @returns The boolean value of the descriptor.
     */
    public asBoolean(): boolean {
        try {
            const asBoolean: AEJSBridgeNative.AEDataDescriptor
                = this.nativeDescriptor.as('bool');
            return new DataView(asBoolean.data.buffer)
                .getUint8(0) !== 0;
        }
        catch (_) {
            throw new TypeError('Descriptor cannot be converted to a boolean');
        }
    }

    /**
     * Converts the JavaScript wrapper to a primitive value.
     * @param hint - The hint for the conversion.
     * @returns The primitive value of the descriptor.
     */
    public [Symbol.toPrimitive](hint: 'string' | 'number' | 'default'): unknown {
        switch (hint) {
            case 'string':
                try {
                    return this.toString();
                }
                catch (_) {
                    try {
                        return this.asNumber().toString();
                    }
                    catch (_) {
                        throw new TypeError('Descriptor cannot be converted \
                            to a string.');
                    }
                }
            case 'number':
                try {
                    return this.asNumber();
                }
                catch (_) {
                    return NaN;
                }
            case 'default':
                try {
                    return this.toString();
                }
                catch (_) {
                    try {
                        return this.asNumber();
                    }
                    catch (_) {
                        throw new TypeError('Descriptor cannot be converted \
                            to a string or number.');
                    }
                }
        }
        throw new TypeError('Invalid hint');
    }

    /**
     * Converts the JavaScript wrapper to a value.
     * @returns The value of the descriptor.
     */
    public valueOf(): unknown {
        if (this.nativeDescriptor instanceof AENullDescriptor) {
            return null;
        }
        if (this.nativeDescriptor instanceof AEDataDescriptor) {
            return {
                type: this.nativeDescriptor.descriptorType,
                data: Buffer.from(this.nativeDescriptor.data)
                    .toString('base64'),
            };
        }
        if (this.nativeDescriptor instanceof AEListDescriptor) {
            return this.nativeDescriptor.items
                .map(item => AEJSDescriptor.fromNative(item).valueOf());
        }
        if (this.nativeDescriptor instanceof AERecordDescriptor) {
            return Object
                .fromEntries(Object
                    .entries(this.nativeDescriptor.fields)
                    .map(([key, value]) => [
                        key,
                        AEJSDescriptor
                            .fromNative(value)
                            .valueOf()
                    ]));
        }
        if (this.nativeDescriptor instanceof AEEventDescriptor) {
            return {
                type: this.nativeDescriptor.descriptorType,
                eventClass: this.nativeDescriptor.eventClass,
                eventID: this.nativeDescriptor.eventID,
                target: AEJSDescriptor.fromNative(this.nativeDescriptor.target)
                    .valueOf(),
                returnID: this.nativeDescriptor.returnID,
                transactionID: this.nativeDescriptor.transactionID,
                parameters: Object
                    .fromEntries(
                        Object
                            .entries(this.nativeDescriptor.parameters)
                            .map(
                                ([key, value]) => [
                                    key,
                                    AEJSDescriptor
                                        .fromNative(value)
                                        .valueOf()
                                ]
                            )
                    ),
                // Attributes are not iterable, and are thus not serializable.
            };
        }
        if (this.nativeDescriptor instanceof AEUnknownDescriptor) {
            return {
                type: this.nativeDescriptor.descriptorType,
            };
        }
        throw new TypeError('Descriptor cannot be converted to a value');
    }

    /**
     * Converts the JavaScript wrapper to a JSON value.
     * @returns The JSON value of the descriptor.
     */
    public toJSON(): unknown {
        return this.valueOf();
    }
}
/**
 * A JavaScript wrapper for an Apple event null descriptor.
 */
class AEJSNullDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AENullDescriptor> {
    /**
     * Creates a new JavaScript wrapper for an Apple event null descriptor.
     */
    public constructor() {
        super(new AENullDescriptor());
    }
}

/**
 * A JavaScript wrapper for an Apple event data descriptor.
 */
class AEJSDataDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AEDataDescriptor> {
    /**
    * The data of the descriptor.
    */
    public get data(): Uint8Array {
        return this.nativeDescriptor.data;
    }

    /**
     * Creates a new JavaScript wrapper for an Apple event data descriptor.
     */
    public constructor(nativeDescriptor: AEJSBridgeNative.AEDataDescriptor) {
        super(nativeDescriptor);
    }
}

/**
 * A JavaScript wrapper for an Apple event list descriptor.
 */
class AEJSListDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AEListDescriptor> {
    /**
    * The items of the descriptor.
    */
    public get items(): AEJSDescriptor<AEJSBridgeNative.AEDescriptor>[] {
        return this.nativeDescriptor.items
            .map(item => AEJSDescriptor.fromNative(item));
    }

    /**
     * Creates a new JavaScript wrapper for an Apple event list descriptor.
     */
    public constructor(nativeDescriptor: AEJSBridgeNative.AEListDescriptor) {
        super(nativeDescriptor);
    }
}

/**
 * A JavaScript wrapper for an Apple event record descriptor.
 */
class AEJSRecordDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AERecordDescriptor> {
    /**
    * The fields of the descriptor.
    */
    public get fields(): Record<AEJSBridgeNative.AEKeyword, AEJSDescriptor<AEJSBridgeNative.AEDescriptor>> {
        return Object
            .fromEntries(Object
                .entries(this.nativeDescriptor.fields)
                .map(([key, value]) => [key, AEJSDescriptor.fromNative(value)]));
    }

    /**
     * Creates a new JavaScript wrapper for an Apple event record descriptor.
     */
    public constructor(nativeDescriptor: AEJSBridgeNative.AERecordDescriptor) {
        super(nativeDescriptor);
    }
}

/**
 * A JavaScript wrapper for an Apple event event descriptor.
 */
class AEJSEventDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AEEventDescriptor> {

    /**
     * The event class of the descriptor.
    */
    public get eventClass(): AEJSBridgeNative.AEEventClass {
        return this.nativeDescriptor.eventClass;
    }

    /**
     * The event ID of the descriptor.
     */
    public get eventID(): AEJSBridgeNative.AEEventID {
        return this.nativeDescriptor.eventID;
    }

    /**
     * The target of the descriptor.
     */
    public get target(): AEJSDescriptor<AEJSBridgeNative.AEDescriptor> {
        return AEJSDescriptor.fromNative(this.nativeDescriptor.target);
    }

    /**
     * The return ID of the descriptor.
     */
    public get returnID(): number {
        return this.nativeDescriptor.returnID;
    }

    /**
     * The transaction ID of the descriptor.
     */
    public get transactionID(): number {
        return this.nativeDescriptor.transactionID;
    }

    /**
     * The parameters of the descriptor.
     */
    public get parameters():
        Record<
            AEJSBridgeNative.AEKeyword,
            AEJSDescriptor<AEJSBridgeNative.AEDescriptor>
        > {
        return Object
            .fromEntries(Object
                .entries(this.nativeDescriptor.parameters)
                .map(
                    ([key, value]) => [
                        key,
                        AEJSDescriptor.fromNative(value)
                    ]
                )
            );
    }

    /**
     * Gets an attribute of the descriptor.
     * @param keyword - The keyword of the attribute.
     * @returns The attribute of the descriptor.
     */
    getAttribute(keyword: AEJSBridgeNative.AEKeyword):
        AEJSDescriptor<AEJSBridgeNative.AEDescriptor> | undefined {
        const attribute = this.nativeDescriptor.getAttribute(keyword);
        return attribute === undefined
            ? undefined
            : AEJSDescriptor.fromNative(attribute);
    }

    /**
     * Creates a new JavaScript wrapper for an Apple event event descriptor.
     */
    public constructor(nativeDescriptor: AEJSBridgeNative.AEEventDescriptor) {
        super(nativeDescriptor);
    }
}

/**
 * A JavaScript wrapper for an Apple event unknown descriptor.
 */
class AEJSUnknownDescriptor
    extends AEJSDescriptor<AEJSBridgeNative.AEUnknownDescriptor> {
}

/**
 * Sends an Apple event.
 * @param event - The event to send.
 * @param expectReply - Whether to expect a reply from the event.
 * @returns The reply to the event.
 */
async function sendJSAppleEvent(
    event: AEJSEventDescriptor,
    expectReply: true
): Promise<AEJSEventDescriptor>;
async function sendJSAppleEvent(
    event: AEJSEventDescriptor,
    expectReply: false
): Promise<null>;
async function sendJSAppleEvent(
    event: AEJSEventDescriptor,
    expectReply: boolean
): Promise<AEJSEventDescriptor | null> {
    const nativeResult =
        await sendAppleEvent(event.toNative(), expectReply);
    return nativeResult === null
        ? null
        : new AEJSEventDescriptor(nativeResult);
}

/**
 * Installs an AppleEvent handler for the given event class and event ID.
 * @param eventClass - The event class of the AppleEvent to handle.
 * @param eventID - The event ID of the AppleEvent to handle.
 * @param handler - The handler function to call when an AppleEvent
 *  is received with the given event class and event ID.
 * The handler function must return a Record<AEKeyword, AEDescriptor>
 *  if a reply is expected, or null if a reply is not expected.
 */
function handleJSAppleEvent(
    eventClass: AEJSBridgeNative.AEEventClass,
    eventID: AEJSBridgeNative.AEEventID,
    handler:
        (
            event: AEJSEventDescriptor,
            replyExpected: boolean
        ) =>
            Record<
                AEJSBridgeNative.AEKeyword,
                AEJSDescriptor<AEJSBridgeNative.AEDescriptor>
            > | null
) {
    handleAppleEvent(eventClass, eventID, (event, replyExpected) => {
        const jsResult = handler(
            new AEJSEventDescriptor(event),
            replyExpected
        );
        return jsResult === null
            ? null
            : Object
                .fromEntries(Object
                    .entries(jsResult)
                    .map(([key, value]) => [key, value.toNative()]));
    });
}
/**
 * Deregisters an AppleEvent handler for the given event class and event ID.
 * If no handler is registered for the pair, this is a no-op.
 * @param eventClass - The event class of the AppleEvent handler.
 * @param eventID - The event ID of the AppleEvent handler.
 */
function unhandleJSAppleEvent(
    eventClass: AEJSBridgeNative.AEEventClass,
    eventID: AEJSBridgeNative.AEEventID
) {
    unhandleAppleEvent(eventClass, eventID);
}
export {
    AEJSDescriptor,
    AEJSNullDescriptor,
    AEJSDataDescriptor,
    AEJSListDescriptor,
    AEJSRecordDescriptor,
    AEJSEventDescriptor,
    AEJSUnknownDescriptor,
    OSError, // re-export for convenience
    sendJSAppleEvent,
    handleJSAppleEvent,
    unhandleJSAppleEvent,
};
