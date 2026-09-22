export const terminalSecretRedactionStorageKey = "opr.terminal.secretRedaction";
export const defaultTerminalSecretRedaction = false;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function readStoredTerminalSecretRedaction(): boolean {
	try {
		return getLocalStorage()?.getItem(terminalSecretRedactionStorageKey) === "1";
	} catch {
		return defaultTerminalSecretRedaction;
	}
}
