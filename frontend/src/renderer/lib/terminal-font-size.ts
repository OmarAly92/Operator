export const TERMINAL_FONT_SIZES = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] as const;

export type TerminalFontSize = (typeof TERMINAL_FONT_SIZES)[number];

export const defaultTerminalFontSize: TerminalFontSize = 14;
export const terminalFontSizeStorageKey = "opr.terminal.fontSize";

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function clampTerminalFontSize(value: number): TerminalFontSize {
	if (!Number.isFinite(value)) return defaultTerminalFontSize;
	const min = TERMINAL_FONT_SIZES[0];
	const max = TERMINAL_FONT_SIZES[TERMINAL_FONT_SIZES.length - 1];
	return Math.min(max, Math.max(min, Math.round(value))) as TerminalFontSize;
}

export function readStoredTerminalFontSize(): TerminalFontSize {
	try {
		const stored = getLocalStorage()?.getItem(terminalFontSizeStorageKey);
		if (stored === null || stored === undefined) return defaultTerminalFontSize;
		return clampTerminalFontSize(Number(stored));
	} catch {
		return defaultTerminalFontSize;
	}
}
