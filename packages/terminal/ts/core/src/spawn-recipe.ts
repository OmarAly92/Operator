import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { BootstrapOptions, ShellKind, SpawnRecipe } from "./types.js";

type ManifestShell = {
	script: string;
	argv: readonly string[];
};

type Manifest = {
	version: number;
	shells: Record<ShellKind, ManifestShell>;
	env: Record<BootstrapOptions["integration"], Record<string, string>>;
};

const here = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(here, "..");
const assetsRoot = join(packageRoot, "assets");
const manifestPath = join(assetsRoot, "recipes.json");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;

function renderArgv(template: readonly string[], scriptPath: string): string[] {
	return template.map((piece) => piece.replaceAll("{{script}}", JSON.stringify(scriptPath)));
}

export function spawnRecipe(shell: ShellKind, options: BootstrapOptions): SpawnRecipe {
	const integration = options.integration;
	const envFromManifest = manifest.env[integration];
	const env: Record<string, string> = { ...envFromManifest };

	if (integration === "auto") {
		env.OPERATOR_TERMINAL_SUPPRESS_PROMPT = options.suppressPrompt ? "1" : "0";
		return {
			argv: renderArgv(
				manifest.shells[shell].argv,
				join(assetsRoot, "shell", manifest.shells[shell].script),
			),
			env,
		};
	}

	return { argv: [shell], env };
}
