{
    "targets": [
        {
            "target_name": "ae_js_bridge_native",
            "sources": [
                "src/native/ae_js_bridge.mm",
                "src/native/AEDescriptor.mm",
                "src/native/AppleEventAPI.mm",
                "src/native/helpers.mm",
                "src/native/OSError.mm",

            ],
            "defines": [
                "NODE_ADDON_API_CPP_EXCEPTIONS"
            ],
            "include_dirs": [
                "<!@(node -p \"require('node-addon-api').include\")"
            ],
            # Including this causes the build to emit a mock `node_modules` directory
            #   one level up from our project root. This behavior is not desired, and
            #   it's also (weirdly) not really documented anywhere. Removing it stops
            #   this behavior and doesn't seem to affect the build in any other way.
            # "dependencies": [
            #     "<!(node -p \"require('node-addon-api').gyp\")"
            # ],
            "xcode_settings": {
                "MACOSX_DEPLOYMENT_TARGET": "13.3",
                "CLANG_CXX_LIBRARY": "libc++",
                "OTHER_CPLUSPLUSFLAGS": [
                    "-std=c++20",
                    "-fexceptions"
                ],
                "OTHER_CFLAGS": [
                    "-fobjc-arc"
                ]
            }
        }
    ]
}