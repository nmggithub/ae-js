# `@ae-js/sdef`

## Introduction

This is a simple Node.js library for working with `.sdef` files. The `.sdef` extension stands for "scripting definition." Scripting definition files are XML files used by the Open Scripting Architecture on macOS to define interfaces that scripting languages like AppleScript can use to write script code that sends and receives Apple events between applications. For more information, see the [Mac Automation Scripting Guide.](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/index.html)

## Using the library

### `@ae-js/sdef`

There is a single helper function, `writeDictionaryToPathWithName`, that is available to import from the root of the library (`@ae-js/sdef`).

### `@ae-js/sdef/elements`

This library includes several classes from `@ae-js/sdef/elements` that represet the different elements that can be part of a scripting definition file. The root element is always a `Dictionary` (`<dictionary>` element). To get the XML from a `Dictionary`, you can use the `.getSdefXML()` method on that class instance. It optionally accepts an object of serialization options that it will pass to its internal builder (see [the serialization options from `xmlbuilder2`](https://oozcitak.github.io/xmlbuilder2/serialization.html#serialization-settings)). ***Parsing is currently not supported in any meaningful way (but it may be added to a future release).***
