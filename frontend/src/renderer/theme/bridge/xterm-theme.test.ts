import { describe, expect, it } from "vitest";
import { skinToXtermTheme } from "./xterm-theme";
import { darkSkin } from "../skins/dark";
import { lightSkin } from "../skins/light";

describe("skinToXtermTheme", () => {
	it("maps the terminal slots onto xterm's ITheme", () => {
		const theme = skinToXtermTheme(darkSkin, "dark");
		expect(theme.background).toBe(darkSkin.bgTerminalOpaque);
		expect(theme.foreground).toBe(darkSkin.textTerminal);
	});

	it("produces every field xterm reads, for both skins", () => {
		const fields = [
			"background", "foreground", "cursor", "cursorAccent",
			"selectionBackground", "selectionInactiveBackground",
			"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
			"brightBlack", "brightRed", "brightGreen", "brightYellow",
			"brightBlue", "brightMagenta", "brightCyan", "brightWhite",
		] as const;
		for (const [skin, theme] of [
			[darkSkin, "dark"],
			[lightSkin, "light"],
		] as const) {
			const result = skinToXtermTheme(skin, theme) as Record<string, unknown>;
			for (const field of fields) {
				expect(result[field], field).toBeTruthy();
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
