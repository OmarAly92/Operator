import type { BootstrapOptions, ShellKind, SpawnRecipe } from "./types.js";

const BOOTSTRAPS: Record<ShellKind, { file: string; argv: (path: string) => string[] }> = {
	zsh: { file: "zsh.sh", argv: (path) => ["zsh", "-c", `source ${JSON.stringify(path)}; exec zsh`] },
	bash: {
		file: "bash.sh",
		argv: (path) => ["bash", "-c", `source ${JSON.stringify(path)}; exec bash`],
	},
	fish: { file: "fish.fish", argv: (path) => ["fish", "-C", `source ${JSON.stringify(path)}`] },
};

/**
 * Compose the argv and env to spawn the requested shell.
 *
 * `integration: "auto"` sources the additive zsh bootstrap and consumes both
 * mark tiers. `integration: "osc133-only"` returns a bare shell and consumes
 * only Tier 1 — this is the host's path when it must not touch the user's
 * shell. `integration: "off"` is for hosts that want a plain grid with no
 * mark consumption at all.
 *
 */
export function spawnRecipe(shell: ShellKind, options: BootstrapOptions): SpawnRecipe {
	const integration = options.integration;

	if (integration === "off") {
		return {
			argv: [shell],
			env: { OPERATOR_TERMINAL_INTEGRATION: "off" },
		};
	}

	if (integration === "osc133-only") {
		return {
			argv: [shell],
			env: { OPERATOR_TERMINAL_INTEGRATION: "osc133-only" },
		};
	}

	const definition = BOOTSTRAPS[shell];
	const bootstrap = new URL(`../../../shell/${definition.file}`, import.meta.url).pathname;
	return {
		argv: definition.argv(bootstrap),
		env: {
			OPERATOR_TERMINAL_INTEGRATION: "auto",
			OPERATOR_TERMINAL_SUPPRESS_PROMPT: options.suppressPrompt ? "1" : "0",
		},
	};
}
