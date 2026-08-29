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

	it("refuses to suppress the prompt in this phase", () => {
		expect(() => spawnRecipe("zsh", { integration: "auto", suppressPrompt: true })).toThrow(
			/prompt suppression is not available/i,
		);
	});
});
