import { useSyncExternalStore } from "react";

const titles = new Map<string, string>();
const listeners = new Set<() => void>();

function notify(): void {
	for (const listener of [...listeners]) listener();
}

export function setTerminalTitle(handleId: string, title: string): void {
	const next = title.trim();
	if ((titles.get(handleId) ?? "") === next) return;
	if (next) titles.set(handleId, next);
	else titles.delete(handleId);
	notify();
}

export function clearTerminalTitles(): void {
	if (titles.size === 0) return;
	titles.clear();
	notify();
}

export function terminalTitle(handleId: string | undefined): string {
	return handleId ? (titles.get(handleId) ?? "") : "";
}

export function terminalTitleListenerCount(): number {
	return listeners.size;
}

export function subscribeTerminalTitles(listener: () => void): () => void {
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
	};
}

export function useTerminalTitle(handleId: string | undefined): string {
	return useSyncExternalStore(
		subscribeTerminalTitles,
		() => terminalTitle(handleId),
		() => "",
	);
}
