export const terminalQuickFixesEnabledStorageKey = "opr.terminal.quickFixesEnabled";
export const defaultTerminalQuickFixesEnabled = true;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function readStoredTerminalQuickFixesEnabled(): boolean {
	try {
		const stored = getLocalStorage()?.getItem(terminalQuickFixesEnabledStorageKey);
		if (stored === null || stored === undefined) return defaultTerminalQuickFixesEnabled;
		return stored === "1";
	} catch {
		return defaultTerminalQuickFixesEnabled;
	}
}
