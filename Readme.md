# `@ae-js/*`

## Introduction

This monorepo contains several Node.js packages for use with Apple events. They can be used all together build an AppleScript API for an Electron app, or they can be used separately as needed. More documentation to come.

## Packages

- [`@ae-js/bridge`](./packages/bridge/Readme.md): the core runtime package
- [`@ae-js/sdef`](./packages/sdef/Readme.md): the core package-time `.sdef` file builder
- [`@ae-js/forge-plugin`](./packages/forge-plugin/Readme.md) the Electron Forge plugin

## Authorship

I have wrote most of the core TypeScript code for these packages myself, with AI serving as, at most, boilerplate auto-complete. The C++ was written (and accidentally deleted before being written again) with the help of AI (although the current version is mostly my own writing with some lessons learned from the previous attempt).

This isn't really meant for production yet, but I hope these packages serve as good references.