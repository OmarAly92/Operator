import type { BootstrapOptions, SpawnRecipe } from "./types.js";

/**
 * Compose the argv and env to spawn the requested shell.
 *
 * `integration: "auto"` sources the additive zsh bootstrap and consumes both
 * mark tiers. `integration: "osc133-only"` returns a bare shell and consumes
 * only Tier 1 — this is the host's path when it must not touch the user's
 * shell. `integration: "off"` is for hosts that want a plain grid with no
 * mark consumption at all.
 *
 * `suppressPrompt` exists in the type for forward compatibility but is not
 * available in Phase 1a — calling with `suppressPrompt: true` throws, so a
 * future caller cannot take prompt suppression by accident. Phase 2 removes
 * the guard deliberately when the editor lands.
 */
export function spawnRecipe(shell: "zsh", options: BootstrapOptions): SpawnRecipe {
	if (options.suppressPrompt) {
		throw new Error(
			"prompt suppression is not available in Phase 1a; it lands with the editor in Phase 2",
		);
	}

	if (shell !== "zsh") {
		throw new Error(`unsupported shell: ${shell as string}`);
	}

	const integration = options.integration;

	if (integration === "off") {
		return {
			argv: ["zsh"],
			env: { OPERATOR_TERMINAL_INTEGRATION: "off" },
		};
	}

	if (integration === "osc133-only") {
		return {
			argv: ["zsh"],
			env: { OPERATOR_TERMINAL_INTEGRATION: "osc133-only" },
		};
	}

	const bootstrap = new URL("./shell/zsh.sh", import.meta.url).pathname;
	return {
		argv: ["zsh", "-c", `source ${JSON.stringify(bootstrap)}; exec zsh`],
		env: {
			OPERATOR_TERMINAL_INTEGRATION: "auto",
			OPERATOR_TERMINAL_SUPPRESS_PROMPT: "0",
		},
	};
}
