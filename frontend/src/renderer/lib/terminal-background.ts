export const TERMINAL_BACKGROUNDS = [
	{ id: "charcoal", labelKey: "settings.terminalColor.charcoal", color: "#1d2022" },
	{ id: "black", labelKey: "settings.terminalColor.black", color: "#000000" },
	{ id: "graphite", labelKey: "settings.terminalColor.graphite", color: "#22252a" },
	{ id: "midnight", labelKey: "settings.terminalColor.midnight", color: "#0d1117" },
	{ id: "slate", labelKey: "settings.terminalColor.slate", color: "#1a1f2b" },
] as const;

export type TerminalBackgroundOption = (typeof TERMINAL_BACKGROUNDS)[number];
export type TerminalBackground = TerminalBackgroundOption["id"];

export const defaultTerminalBackground: TerminalBackground = "charcoal";
export const terminalBackgroundStorageKey = "opr.terminal-background";

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function terminalBackgroundColor(id: TerminalBackground): string {
	const option = TERMINAL_BACKGROUNDS.find((candidate) => candidate.id === id);
	return option?.color ?? TERMINAL_BACKGROUNDS[0].color;
}

export function readStoredTerminalBackground(): TerminalBackground {
	try {
		const stored = getLocalStorage()?.getItem(terminalBackgroundStorageKey);
		const match = TERMINAL_BACKGROUNDS.find((option) => option.id === stored);
		if (match) return match.id;
	} catch {
		// ignore
	}
	return defaultTerminalBackground;
}

export function applyTerminalBackground(id: TerminalBackground): void {
	if (typeof document === "undefined") return;
	document.documentElement.style.setProperty("--terminal-background", terminalBackgroundColor(id));
}
