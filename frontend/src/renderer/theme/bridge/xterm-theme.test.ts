import { describe, expect, it } from "vitest";
import { skinToXtermTheme } from "./xterm-theme";
import { skinFor } from "../skins";
import { darkSkin } from "../skins/dark";
import { lightSkin } from "../skins/light";

const ITHEME_FIELDS = [
	"background", "foreground", "cursor", "cursorAccent",
	"selectionBackground", "selectionInactiveBackground",
	"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
	"brightBlack", "brightRed", "brightGreen", "brightYellow",
	"brightBlue", "brightMagenta", "brightCyan", "brightWhite",
] as const;

// The inactive-selection wash is a deliberately theme-neutral grey scrim: every
// skin carries the same value, so it is the one ITheme field a named style is
// not expected to repaint. A separate test pins that it stays shared.
const SHARED_FIELDS = new Set<string>(["selectionInactiveBackground"]);

// Genuine palette coincidences, not gaps: the base light skin's terminal ink is
// GitHub Light's `#24292f`, so GitHub Light legitimately lands on the same value
// for the two slots that use it. Anything beyond this pair means a style is
// falling through to the base skin.
const KNOWN_COINCIDENCES = new Set<string>([
	"github/light black",
	"github/light brightWhite",
]);

const NAMED_STYLES = [
	"github", "catppuccin", "dracula", "tokyo-night",
	"rose-pine", "nord", "gruvbox", "solarized",
] as const;

describe("skinToXtermTheme", () => {
	it("maps the terminal slots onto xterm's ITheme", () => {
		const theme = skinToXtermTheme(darkSkin, "dark");
		expect(theme.background).toBe(darkSkin.bgTerminalOpaque);
		expect(theme.foreground).toBe(darkSkin.textTerminal);
	});

	it("produces every field xterm reads, for both skins", () => {
		for (const [skin, theme] of [
			[darkSkin, "dark"],
			[lightSkin, "light"],
		] as const) {
			const result = skinToXtermTheme(skin, theme) as Record<string, unknown>;
			for (const field of ITHEME_FIELDS) {
				expect(result[field], field).toBeTruthy();
			}
		}
	});

	it("gives every named style its own value for every xterm field", () => {
		for (const theme of ["dark", "light"] as const) {
			const base = skinToXtermTheme(
				theme === "light" ? lightSkin : darkSkin,
				theme,
			) as Record<string, unknown>;
			for (const style of NAMED_STYLES) {
				const result = skinToXtermTheme(skinFor(style, theme), theme) as Record<
					string,
					unknown
				>;
				for (const field of ITHEME_FIELDS) {
					const where = `${style}/${theme} ${field}`;
					expect(result[field], where).toBeTruthy();
					if (SHARED_FIELDS.has(field) || KNOWN_COINCIDENCES.has(where)) continue;
					expect(result[field], where).not.toBe(base[field]);
				}
			}
		}
	});

	it("keeps the inactive-selection wash shared across every style", () => {
		for (const theme of ["dark", "light"] as const) {
			const base = skinToXtermTheme(theme === "light" ? lightSkin : darkSkin, theme);
			for (const style of NAMED_STYLES) {
				const result = skinToXtermTheme(skinFor(style, theme), theme);
				expect(result.selectionInactiveBackground, `${style}/${theme}`).toBe(
					base.selectionInactiveBackground,
				);
			}
		}
	});

	it("uses the working accent for the dark cursor and the terminal foreground for the light cursor", () => {
		const dark = skinToXtermTheme(darkSkin, "dark");
		expect(dark.cursor).toBe(darkSkin.statusWorking);

		const light = skinToXtermTheme(lightSkin, "light");
		expect(light.cursor).toBe(lightSkin.textTerminal);
	});

	it("paints cursorAccent as the terminal's own background", () => {
		const dark = skinToXtermTheme(darkSkin, "dark");
		expect(dark.cursorAccent).toBe(darkSkin.bgTerminalOpaque);

		const light = skinToXtermTheme(lightSkin, "light");
		expect(light.cursorAccent).toBe(lightSkin.bgTerminalOpaque);
	});

	it("selects the dark/light selection tokens by appearance", () => {
		const dark = skinToXtermTheme(darkSkin, "dark");
		expect(dark.selectionBackground).toBe(darkSkin.termSelectionDark);
		expect(dark.selectionInactiveBackground).toBe(darkSkin.termSelectionInactive);

		const light = skinToXtermTheme(lightSkin, "light");
		expect(light.selectionBackground).toBe(lightSkin.termSelectionLight);
		expect(light.selectionInactiveBackground).toBe(lightSkin.termSelectionInactiveLight);
	});
});
