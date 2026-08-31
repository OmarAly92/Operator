import { existsSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { spawnRecipe } from "./index";

describe("spawnRecipe", () => {
	it("returns a bootstrap-sourcing recipe for auto integration", () => {
		const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: false });
		expect(recipe.argv[0]).toBe("zsh");
		expect(recipe.env.OPERATOR_TERMINAL_INTEGRATION).toBe("auto");
		expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("0");
	});

	it("returns a bare shell for osc133-only", () => {
		const recipe = spawnRecipe("zsh", { integration: "osc133-only", suppressPrompt: false });
		expect(recipe.argv).toEqual(["zsh"]);
		expect(recipe.env.OPERATOR_TERMINAL_INTEGRATION).toBe("osc133-only");
	});

	it.each(["bash", "fish"] as const)("returns an auto integration recipe for %s", (shell) => {
		const recipe = spawnRecipe(shell, { integration: "auto", suppressPrompt: false });
		expect(recipe.argv[0]).toBe(shell);
		expect(recipe.env.OPERATOR_TERMINAL_INTEGRATION).toBe("auto");
	});

	it("leaves fish OSC 133 enabled", () => {
		const recipe = spawnRecipe("fish", { integration: "auto", suppressPrompt: false });
		expect(recipe.argv).not.toContain("no-mark-prompt");
		expect(recipe.argv.some((argument) => /no-mark/.test(argument))).toBe(false);
	});

	it("accepts suppressPrompt now that the editor exists", () => {
		const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: true });
		expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("1");
	});

	it("still offers a show-shell-prompt fallback", () => {
		const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: false });
		expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("0");
	});

	it("templates the manifest argv so the manifest is the single source of truth", () => {
		const zsh = spawnRecipe("zsh", { integration: "auto", suppressPrompt: false });
		expect(zsh.argv[0]).toBe("zsh");
		expect(zsh.argv[1]).toBe("-c");
		expect(zsh.argv[2]).toMatch(
			/source "[^"]*shell\/zsh\.sh"; OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR="\$\{ZDOTDIR:-\$HOME\}" ZDOTDIR="[^"]*shell\/zsh\.sh"\.d exec zsh$/,
		);
		const zshScript = zsh.argv[2].match(/^source "([^"]+)";/)?.[1];
		expect(zshScript).toBeDefined();
		expect(existsSync(`${zshScript}.d/.zshrc`)).toBe(true);

		const bash = spawnRecipe("bash", { integration: "auto", suppressPrompt: false });
		expect(bash.argv[2]).toMatch(/source "[^"]*shell\/bash\.sh"; exec bash$/);

		const fish = spawnRecipe("fish", { integration: "auto", suppressPrompt: false });
		expect(fish.argv[0]).toBe("fish");
		expect(fish.argv[1]).toBe("-C");
		expect(fish.argv[2]).toMatch(/^source "[^"]*shell\/fish\.fish"$/);
	});
});
