declare module '#ae_js_bridge_native' {
    /**
     * A 4-character code.
     */
    type FourCharCode = string;

    /**
     * A descriptor type.
     */
    type DescType = FourCharCode;

    /**
     * An Apple event keyword.
     */
    type AEKeyword = FourCharCode;

    /**
     * An Apple event class.
     */
    type AEEventClass = FourCharCode;

    /**
     * An Apple event ID.
     */
    type AEEventID = FourCharCode;


    /**
     * Base class for all Apple event descriptors.
     */
    export abstract class AEDescriptor {
        /**
         * The type of the descriptor.
         */
        public readonly descriptorType: DescType;


        /**
         * Casts the descriptor to the given type.
         * @param descriptorType - The type of the descriptor to cast to.
         * @returns The descriptor cast to the given type.
         */
        public as<T extends AEDescriptor>(descriptorType: DescType): T;
    }

    /**
     * A null descriptor.
     */
    export class AENullDescriptor extends AEDescriptor {
        /**
         * Creates a new null descriptor.
         */
        public constructor();
    }

    /**
     * A data descriptor.
     */
    export class AEDataDescriptor extends AEDescriptor {
        /**
         * Creates a new data descriptor.
         * @param descriptorType - The type of the descriptor.
         * @param data - The data of the descriptor.
         */
        public constructor(descriptorType: DescType, data: Uint8Array);

        /**
         * The data of the descriptor.
         */
        public readonly data: Uint8Array;
    }

    /**
     * A list descriptor.
     */
    export class AEListDescriptor extends AEDescriptor {
        /**
         * Creates a new list descriptor.
         * @param descriptorType - The type of the descriptor.
         * @param items - The items of the descriptor.
         */
        public constructor(descriptorType: DescType, items: AEDescriptor[]);

        /**
         * The items of the descriptor.
         */
        public readonly items: AEDescriptor[];
    }

    /**
     * A record descriptor.
     */
    export class AERecordDescriptor extends AEDescriptor {
        /**
         * Creates a new record descriptor.
         * @param descriptorType - The type of the descriptor.
         * @param fields - The fields of the descriptor.
         */
        public constructor(
            descriptorType: DescType,
            fields: Record<AEKeyword, AEDescriptor>
        );

        /**
         * The fields of the descriptor.
         */
        public readonly fields: Record<AEKeyword, AEDescriptor>;
    }

    /**
     * An event descriptor.
     */
    export class AEEventDescriptor extends AEDescriptor {
        /**
         * Creates a new event descriptor.
         * @param descriptorType - The type of the descriptor.
         * @param eventClass - The event class of the descriptor.
         * @param eventID - The event ID of the descriptor.
         * @param target - The target of the descriptor.
         * @param returnID - The return ID of the descriptor.
         * @param transactionID - The transaction ID of the descriptor.
         * @param parameters - The parameters of the descriptor.
         * @param attributes - The attributes of the descriptor.
         */
        public constructor(
            eventClass: AEEventClass,
            eventID: AEEventID,
            target: AEDescriptor,
            returnID: number,
            transactionID: number,
            parameters: Record<AEKeyword, AEDescriptor>,
            attributes: Record<AEKeyword, AEDescriptor>
        );

        /**
         * The event class of the descriptor.
         */
        public readonly eventClass: AEEventClass;

        /**
         * The event ID of the descriptor.
         */
        public readonly eventID: AEEventID;

        /**
         * The target of the descriptor.
         */
        public readonly target: AEDescriptor;

        /**
         * The return ID of the descriptor.
         */
        public readonly returnID: number;

        /**
         * The transaction ID of the descriptor.
         */
        public readonly transactionID: number;

        /**
         * The parameters of the descriptor.
         */
        public readonly parameters: Record<AEKeyword, AEDescriptor>;

        /**
         * Gets an attribute of the descriptor.
         * @param keyword - The keyword of the attribute.
         * @returns The attribute of the descriptor.
         */
        public getAttribute(keyword: AEKeyword): AEDescriptor | undefined;
    }

    /**
     * An unknown descriptor.
     */
    export class AEUnknownDescriptor extends AEDescriptor {
    }

    /**
     * Error class for native API failures. Exposes the underlying OSErr as
     * a numeric `code` property.
     */
    export class OSError extends Error {
        /**
         * The OSErr code from the failing API.
         */
        public readonly code: number;
    }

    /**
     * Sends an Apple event and returns a promise that resolves to the reply.
     * @param event - The event to send.
     * @param expectReply - Whether to expect a reply from the Apple event.
     * @returns A promise that resolves to the reply event, or
     *  null if no reply is expected.
     */
    export function sendAppleEvent(
        event: AEEventDescriptor,
        expectReply: true
    ): Promise<AEEventDescriptor>;
    export function sendAppleEvent(
        event: AEEventDescriptor,
        expectReply: false
    ): Promise<null>;
    export function sendAppleEvent(
        event: AEEventDescriptor,
        expectReply: boolean
    ): Promise<AEEventDescriptor | null>;

    /**
     * Installs an Apple event handler for the given event class and event ID.
     * @param eventClass - The event class of the Apple event to handle.
     * @param eventID - The event ID of the Apple event to handle.
     * @param handler - The handler function to call when an AppleEvent
     *  is received with the given event class and event ID.
     * The handler function should return an object of parameters if
     *  a reply is expected, or null if a reply is not expected.
     */
    export function handleAppleEvent(
        eventClass: AEEventClass,
        eventID: AEEventID,
        handler: (event: AEEventDescriptor, replyExpected: boolean)
            => Record<AEKeyword, AEDescriptor> | null
    ): void;

    /**
     * Deregisters an Apple event handler for the given event class and event ID.
     * If no handler is registered for the pair, this is a no-op.
     * @param eventClass - The event class of the Apple event handler.
     * @param eventID - The event ID of the Apple event handler.
     */
    export function unhandleAppleEvent(
        eventClass: AEEventClass,
        eventID: AEEventID
    ): void;
}