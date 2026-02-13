import { PluginBase } from "@electron-forge/plugin-base";
import { type ForgeHookFn, type ForgeHookMap } from "@electron-forge/shared-types";

import { randomUUID } from "node:crypto";
import { mkdirSync, rmSync } from "node:fs";
import { join, dirname, parse } from "node:path";
import { tmpdir } from "node:os";

import { Dictionary } from "@ae-js/sdef/elements";
import { writeDictionaryToPathWithName } from "@ae-js/sdef";

// TODO: Make a more friendly config type for the plugin.
interface AEJSForgePluginConfig {
    scriptingDefinition: Dictionary;
}

export default class AEJSForgePlugin extends PluginBase<AEJSForgePluginConfig> {

    private static SCRIPTING_DEFINITION_FILE_NAME = "AEJSScripting.sdef";
    private static PLUGIN_NAME = "@ae-js/forge-plugin";

    // Our class is instantiated once per run of Forge, so
    //  we can safely generate a unique ID for each run.
    private RUN_ID = randomUUID();

    private scriptingDefinition: Dictionary;

    constructor(config: AEJSForgePluginConfig) {
        super(config);
        this.scriptingDefinition = config.scriptingDefinition;
    }

    name: string = AEJSForgePlugin.PLUGIN_NAME;

    getHooks(): ForgeHookMap {
        return {
            resolveForgeConfig: this.resolveForgeConfig,
            generateAssets: this.generateAssets,
            postPackage: this.postPackage,
        };
    }

    resolveForgeConfig: ForgeHookFn<"resolveForgeConfig"> = async (forgeConfig) => {
        if (!forgeConfig.packagerConfig) {
            forgeConfig.packagerConfig = {};
        }

        const originalExtendInfo = forgeConfig.packagerConfig.extendInfo ?? {};
        if (typeof originalExtendInfo === "string") {
            throw new Error(
                `${AEJSForgePlugin.PLUGIN_NAME} requires extendInfo to be an object, not a string.`
            );
        }

        forgeConfig.packagerConfig.extendInfo = {
            ...originalExtendInfo,

            // Not strictly necessary, but helps backwards compatibility.
            NSAppleScriptEnabled: true,

            OSAScriptingDefinition: AEJSForgePlugin.SCRIPTING_DEFINITION_FILE_NAME,
        };

        const originalExtraResource =
            typeof forgeConfig.packagerConfig.extraResource === "string"
                ? [forgeConfig.packagerConfig.extraResource]
                : forgeConfig.packagerConfig.extraResource ?? [];

        forgeConfig.packagerConfig.extraResource = [
            ...originalExtraResource,
            this.temporaryScriptingDefinitionFilePath,
        ];

        return forgeConfig;
    };

    // Ensure the `.sdef` exists before Electron Packager runs.
    generateAssets: ForgeHookFn<"generateAssets"> = async (_, platform) => {
        if (platform !== "darwin") return;
        this.writeScriptingDefinitionFileToTemporaryPath();
    };

    postPackage: ForgeHookFn<"postPackage"> = async (_, options) => {
        if (options.platform !== "darwin") return;
        this.cleanupTemporaryScriptingDefinitionFile();
    };

    private temporaryScriptingDefinitionFilePath: string =
        join(
            tmpdir(),
            `aejs-${this.RUN_ID}`,
            AEJSForgePlugin.SCRIPTING_DEFINITION_FILE_NAME
        );

    private writeScriptingDefinitionFileToTemporaryPath() {
        mkdirSync(
            dirname(this.temporaryScriptingDefinitionFilePath),
            { recursive: true }
        );
        writeDictionaryToPathWithName(
            this.scriptingDefinition,
            dirname(this.temporaryScriptingDefinitionFilePath),
            parse(this.temporaryScriptingDefinitionFilePath).name
        );
    }

    private cleanupTemporaryScriptingDefinitionFile() {
        rmSync(
            dirname(this.temporaryScriptingDefinitionFilePath),
            { recursive: true, force: true }
        );
    }
}
