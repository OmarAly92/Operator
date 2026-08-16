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

	it("gives every style its own status colours", () => {
		const base = skinFor("orchestrate", "dark");
		for (const style of ["github", "dracula", "nord", "gruvbox"] as const) {
			const skin = skinFor(style, "dark");
			expect(skin.background, style).not.toBe(base.background);
			expect(skin.statusWorking, style).not.toBe(base.statusWorking);
		}
	});

	it("derives each style's derived slots from that style's own palette", () => {
		const styles = [
			"github", "catppuccin", "dracula", "tokyo-night",
			"rose-pine", "nord", "gruvbox", "solarized",
		] as const;
		for (const style of styles) {
			for (const theme of ["dark", "light"] as const) {
				const skin = skinFor(style, theme);
				const where = `${style}/${theme}`;
				expect(skin.bgPrimary, where).toBe(skin.background);
				expect(skin.colorAccent, where).toBe(skin.primary);
				expect(skin.warning, where).toBe(skin.statusNeedsYou);
				expect(skin.success, where).toBe(skin.statusReady);
				expect(skin.danger, where).toBe(skin.destructive);
			}
		}
	});
});
