import { FusesPlugin } from '@electron-forge/plugin-fuses';
import { FuseV1Options, FuseVersion } from '@electron/fuses';

import type { ForgeConfig } from '@electron-forge/shared-types';

import { Dictionary, Suite, Command } from '@ae-js/sdef/elements';

import AEJSForgePlugin from '@ae-js/forge-plugin';

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
                    commands: [
                        new Command(
                            {
                                name: 'doThing',
                                code: 'aejsDOTH',
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
