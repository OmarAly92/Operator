export const terminalPredictiveEchoStorageKey = "opr.terminal.predictiveEcho";
export const defaultTerminalPredictiveEcho = false;
export const terminalPredictiveEchoThresholdMs = 30;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function readStoredTerminalPredictiveEcho(): boolean {
	try {
		return getLocalStorage()?.getItem(terminalPredictiveEchoStorageKey) === "1";
	} catch {
		return defaultTerminalPredictiveEcho;
	}
}
