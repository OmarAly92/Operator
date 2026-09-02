export const OPEN_DIALOG_OR_MENU_SELECTOR =
	'[role="dialog"][data-state="open"], [role="alertdialog"][data-state="open"], [role="menu"][data-state="open"]';

// Native BrowserView pixels sit above the renderer, so only dialogs and
// explicitly marked browser-panel overlays should park that view. Generic
// menus elsewhere in the shell do not overlap the BrowserView and parking for
// every Radix menu causes the preview to flash on ordinary toolbar clicks.
export const OPEN_BROWSER_OVERLAY_SELECTOR =
	'[role="dialog"][data-state="open"], [role="alertdialog"][data-state="open"], [data-browser-native-overlay="true"][data-state="open"]';

export function isDialogOrMenuOpen(): boolean {
	if (typeof document === "undefined") return false;
	return document.querySelector(OPEN_DIALOG_OR_MENU_SELECTOR) !== null;
}

export const TERMINAL_SURFACE_SELECTOR = ".terminal-surface";

export const TERMINAL_INPUT_SELECTOR = "[data-terminal-input]";

const VISIBLE_TERMINAL_HOST_SELECTOR =
	"[data-terminal-activation-phase='visible'], [data-testid='session-terminal-slot']";

export function activeTerminalInput(): HTMLElement | null {
	if (typeof document === "undefined") return null;
	for (const host of document.querySelectorAll<HTMLElement>(VISIBLE_TERMINAL_HOST_SELECTOR)) {
		for (const input of host.querySelectorAll<HTMLElement>(TERMINAL_INPUT_SELECTOR)) {
			if (input.closest("[hidden]") === null) return input;
		}
	}
	return null;
}

export function terminalHasFocus(): boolean {
	if (typeof document === "undefined") return false;
	const active = document.activeElement;
	return active instanceof Element && active.closest(TERMINAL_SURFACE_SELECTOR) !== null;
}
