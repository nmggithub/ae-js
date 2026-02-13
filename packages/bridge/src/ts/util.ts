import { AEJSRecordDescriptor } from "./index.js";

/**
 * Creates an object of parameters for an error response.
 * @param errorMessage - The error message.
 * @param errorNumber - The error number.
 * @param briefErrorMessage - The brief error message.
 * @returns The object of parameters for the error response.
 */
function makeErrorParameters(
    errorMessage: string = 'Unknown error',
    errorNumber: number = -2700,
    briefErrorMessage?: string
) {
    return AEJSRecordDescriptor.fromValue({
        errn: { value: errorNumber, as: 'long' },
        errs: errorMessage,
        ...(
            briefErrorMessage
                ? { errb: briefErrorMessage }
                : {}
        ),
    }).fields;
}
export { makeErrorParameters }