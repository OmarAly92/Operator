const claims = new Map<symbol, ReadonlySet<string>>();

export function claimOnScreenTerminals(handleIds: Iterable<string>): () => void {
	const key = Symbol("on-screen-terminals");
	claims.set(key, new Set(handleIds));
	return () => {
		claims.delete(key);
	};
}

export function terminalShownInAPane(handleId: string): boolean {
	for (const handles of claims.values()) {
		if (handles.has(handleId)) return true;
	}
	return false;
}

export function isTerminalOnScreen(handleId: string): boolean {
	if (typeof document === "undefined") return false;
	if (document.visibilityState !== "visible" || !document.hasFocus()) return false;
	return terminalShownInAPane(handleId);
}
