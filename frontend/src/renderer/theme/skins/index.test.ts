import { describe, expect, it } from "vitest";
import { skinFor } from "./index";
import { darkSkin } from "./dark";
import { lightSkin } from "./light";

const NAMED_STYLES = [
	"github", "catppuccin", "dracula", "tokyo-night",
	"rose-pine", "nord", "gruvbox", "solarized",
] as const;

const STATUS_SLOTS = [
	"statusWorking", "statusNeedsYou", "statusInReview",
	"statusReady", "statusTerminated",
] as const;

describe("skinFor", () => {
	it("resolves the default style to the base skins", () => {
		expect(skinFor("orchestrate", "dark")).toBe(darkSkin);
		expect(skinFor("orchestrate", "light")).toBe(lightSkin);
	});

	it("resolves every known style for both appearances", () => {
		for (const style of ["orchestrate", ...NAMED_STYLES] as const) {
			expect(skinFor(style, "dark"), style).toBeDefined();
			expect(skinFor(style, "light"), style).toBeDefined();
		}
	});

	it("gives every style its own background and its own status colours", () => {
		for (const style of NAMED_STYLES) {
			for (const theme of ["dark", "light"] as const) {
				const base = theme === "light" ? lightSkin : darkSkin;
				const skin = skinFor(style, theme);
				const where = `${style}/${theme}`;
				expect(skin.background, `${where} background`).not.toBe(base.background);
				for (const slot of STATUS_SLOTS) {
					expect(skin[slot], `${where} ${slot}`).not.toBe(base[slot]);
				}
			}
		}
	});

	it("derives each style's derived slots from that style's own palette", () => {
		for (const style of NAMED_STYLES) {
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
