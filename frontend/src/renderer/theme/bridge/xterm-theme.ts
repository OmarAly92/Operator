import type { ITheme } from "@xterm/xterm";
import type { AppSkin } from "../app-skin";
import type { Theme } from "../../lib/theme";

/**
 * Bridge from the app's static AppSkin tokens to xterm's ITheme.
 *
 * Cursor and selection colors are appearance-dependent rather than a single
 * fixed skin slot:
 *  - cursor: the "working" accent on dark, but the terminal foreground on
 *    light — --color-working reads as a low-contrast wash on the light
 *    terminal background, especially while blinking.
 *  - selectionBackground / selectionInactiveBackground: the skin carries
 *    distinct dark/light selection tokens (termSelectionDark/Light,
 *    termSelectionInactive/InactiveLight); pick the pair matching `theme`.
 */
export function skinToXtermTheme(skin: AppSkin, theme: Theme): ITheme {
	return {
		background: skin.bgTerminalOpaque,
		foreground: skin.textTerminal,
		cursor: theme === "light" ? skin.textTerminal : skin.statusWorking,
		cursorAccent: skin.bgTerminalOpaque,
		selectionBackground: theme === "light" ? skin.termSelectionLight : skin.termSelectionDark,
		selectionInactiveBackground:
			theme === "light" ? skin.termSelectionInactiveLight : skin.termSelectionInactive,
		black: skin.termBlack,
		red: skin.termRed,
		green: skin.termGreen,
		yellow: skin.termYellow,
		blue: skin.termBlue,
		magenta: skin.termMagenta,
		cyan: skin.termCyan,
		white: skin.termWhite,
		brightBlack: skin.termBrightBlack,
		brightRed: skin.termBrightRed,
		brightGreen: skin.termBrightGreen,
		brightYellow: skin.termBrightYellow,
		brightBlue: skin.termBrightBlue,
		brightMagenta: skin.termBrightMagenta,
		brightCyan: skin.termBrightCyan,
		brightWhite: skin.termBrightWhite,
	};
}
