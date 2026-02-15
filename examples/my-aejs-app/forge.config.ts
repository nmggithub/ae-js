import { FusesPlugin } from '@electron-forge/plugin-fuses';
import { FuseV1Options, FuseVersion } from '@electron/fuses';

import type { ForgeConfig } from '@electron-forge/shared-types';

import { Dictionary, Suite, Event, DirectParameter } from '@ae-js/sdef/elements';

import AEJSForgePlugin from '@ae-js/forge-plugin';

import { basename, extname } from 'node:path';

import { env } from 'node:process';

const scriptingDefinition = new Dictionary(
    { title: 'My AEJS Dictionary' },
    {
        suites: [
            new Suite(
                {
                    name: 'My AEJS Suite',
                    code: 'AEJS',
                },
                {
                    // It's not documented, but using `events` here instead of `commands`
                    //  keeps Cocoa scripting from stepping on our toes and registering
                    //  its own event handlers for the same event IDs. More to come.
                    events: [
                        new Event(
                            {
                                name: 'doThing',
                                code: 'aejsDOTH',
                            },
                            {} // No children
                        ),
                        new Event(
                            {
                                name: 'doPing',
                                code: 'aejsPING',
                            },
                            {
                                directParameter: new DirectParameter(
                                    { type: 'text' },
                                    {} // No children
                                ),
                            }
                        ),
                        new Event(
                            {
                                name: 'doError',
                                code: 'aejsERR1',
                            },
                            {} // No children
                        ),
                        new Event(
                            {
                                name: 'doAsyncError',
                                code: 'aejsERR2',
                            },
                            {} // No children
                        ),
                    ],
                }),
        ],
    });

export default <ForgeConfig>{
    packagerConfig: {
        asar: true,
        // Apps *must* be signed to be able to use Apple events.
        osxSign: {
            identity: env.CODE_SIGN_IDENTITY,
            ignore(path) {
                if (extname(basename(path)) === '.pak') {
                    return true;
                }
                return false;
            }
        }
    },
    rebuildConfig: {},
    makers: [
        {
            name: '@electron-forge/maker-squirrel',
            config: {},
        },
        {
            name: '@electron-forge/maker-zip',
            platforms: ['darwin'],
        },
        {
            name: '@electron-forge/maker-deb',
            config: {},
        },
        {
            name: '@electron-forge/maker-rpm',
            config: {},
        },
    ],
    plugins: [
        {
            name: '@electron-forge/plugin-auto-unpack-natives',
            config: {},
        },
        new FusesPlugin({
            version: FuseVersion.V1,
            [FuseV1Options.RunAsNode]: false,
            [FuseV1Options.EnableCookieEncryption]: true,
            [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
            [FuseV1Options.EnableNodeCliInspectArguments]: false,
            [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
            [FuseV1Options.OnlyLoadAppFromAsar]: true,
        }),
        new AEJSForgePlugin({
            scriptingDefinition,
        }),
    ],
};
