# `@ae-js/bridge`

## Introduction

This is a Node.js library for working with Apple events. Apple events are passed between applications on macOS. Generally, there are five types of descriptor:

1. **null** descriptors (contain no data or information),
2. **data** descriptors (contain a single data buffer),
3. **list** descriptors (contain a list of descriptors),
4. **record** descriptors (contain key-descriptor pairs), and
5. **event** descriptors (contain a full Apple event).

This library provides wrappers for all five types. It also includes wrappers for "unknown" descriptors in cases where the native code could not represent a descriptor as one of the five types. Beyond that, it expects you are fairly familiar with building and handling Apple events. For more information, see [the Apple documentation on Apple events.](https://developer.apple.com/documentation/coreservices/apple_events)

## Using the library

### `@ae-js/bridge`

From `@ae-js/bridge`, this library exports: 

- JavaScript classes that each wrap the five types of descriptors (and "unknown") each named in the format `AEJS[Type]Descriptor`
- a function `sendJSAppleEvent` for sending Apple events,
- a function `handleJSAppleEvent` for installing event handlers for incoming Apple events, and
- a function `unhandleJSAppleEvent` for uninstalling event handlers.

### `@ae-js/bridge/native`

The exports from `@ae-js/bridge/native` are essentially the same as those from `@ae-js/bridge`, except for two things:

1. the lack of `JS` in the names of the classes and functions, and
2. the classes from `@ae-js/bridge/native` are native objects written in C++, while those from `@ae-js/bridge/native` are written in JS and wrap the native onces.

*Note: the classes from `@ae-js/bridge` are preferred as they provide more helpful functionality in JS-land.* 
