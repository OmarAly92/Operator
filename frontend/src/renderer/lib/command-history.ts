import type { CommandHistoryEntry, CommandHistorySource } from "@operator/terminal-react";
import { apiClient, apiErrorMessage } from "./api-client";
import { terminalDebug } from "./terminal-debug";

export const TERMINAL_HISTORY_LIMIT = 1000;
export const COMMAND_FINISHED_REFRESH_MS = 500;

export async function fetchTerminalHistory(): Promise<CommandHistoryEntry[]> {
	const { data, error } = await apiClient.GET("/api/v1/terminal-history", {
		params: { query: { limit: TERMINAL_HISTORY_LIMIT } },
	});
	if (error) throw new Error(apiErrorMessage(error, "Unable to load command history"));
	const entries: CommandHistoryEntry[] = [];
	for (const entry of data?.commands ?? []) {
		const at = Date.parse(entry.finishedAt);
		if (entry.command.length > 0 && Number.isFinite(at)) entries.push({ command: entry.command, at });
	}
	return entries;
}

export type CommandHistoryStore = CommandHistorySource & {
	refresh(): void;
	noteCommandFinished(): void;
};

type FocusTarget = Pick<Window, "addEventListener" | "removeEventListener">;

export type CommandHistoryStoreDeps = {
	fetch: () => Promise<CommandHistoryEntry[]>;
	focusTarget: FocusTarget | null;
	schedule: (run: () => void, delayMs: number) => () => void;
};

export function createCommandHistoryStore(deps: CommandHistoryStoreDeps): CommandHistoryStore {
	let entries: readonly CommandHistoryEntry[] = [];
	const listeners = new Set<() => void>();
	let inFlight = false;
	let again = false;
	let cancelScheduled: (() => void) | null = null;

	const refresh = (): void => {
		if (inFlight) {
			again = true;
			return;
		}
		inFlight = true;
		void deps
			.fetch()
			.then(
				(next) => {
					entries = next;
					for (const listener of [...listeners]) listener();
				},
				(error: unknown) => {
					terminalDebug("command-history", "refresh failed", { error: String(error) });
				},
			)
			.finally(() => {
				inFlight = false;
				if (!again) return;
				again = false;
				refresh();
			});
	};
	const onFocus = () => refresh();

	return {
		entries: () => entries,
		subscribe(listener) {
			listeners.add(listener);
			if (listeners.size === 1) {
				deps.focusTarget?.addEventListener("focus", onFocus);
				refresh();
			}
			return () => {
				if (!listeners.delete(listener) || listeners.size > 0) return;
				deps.focusTarget?.removeEventListener("focus", onFocus);
			};
		},
		refresh,
		noteCommandFinished() {
			cancelScheduled?.();
			cancelScheduled = deps.schedule(() => {
				cancelScheduled = null;
				refresh();
			}, COMMAND_FINISHED_REFRESH_MS);
		},
	};
}

export const commandHistory = createCommandHistoryStore({
	fetch: fetchTerminalHistory,
	focusTarget: typeof window === "undefined" ? null : window,
	schedule: (run, delayMs) => {
		const id = setTimeout(run, delayMs);
		return () => clearTimeout(id);
	},
});
