import { describe, expect, it } from "vitest";
import { skinFor } from "./index";
import { darkSkin } from "./dark";
import { lightSkin } from "./light";

describe("skinFor", () => {
	it("resolves the default style to the base skins", () => {
		expect(skinFor("orchestrate", "dark")).toBe(darkSkin);
		expect(skinFor("orchestrate", "light")).toBe(lightSkin);
	});

	it("resolves every known style for both appearances", () => {
		const styles = [
			"orchestrate", "github", "catppuccin", "dracula",
			"tokyo-night", "rose-pine", "nord", "gruvbox", "solarized",
		] as const;
		for (const style of styles) {
			expect(skinFor(style, "dark"), style).toBeDefined();
			expect(skinFor(style, "light"), style).toBeDefined();
		}
	});
});
