import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiGetMock } = vi.hoisted(() => ({ apiGetMock: vi.fn() }));

vi.mock("./api-client", () => ({
	apiClient: { GET: apiGetMock },
	apiErrorMessage: () => "Request failed",
}));

import { createCommandHistoryStore, fetchTerminalHistory, TERMINAL_HISTORY_LIMIT } from "./command-history";

type Entry = { command: string; at: number };

function deferred() {
	let resolve!: (entries: Entry[]) => void;
	let reject!: (error: Error) => void;
	const promise = new Promise<Entry[]>((res, rej) => {
		resolve = res;
		reject = rej;
	});
	return { promise, resolve, reject };
}

function harness() {
	const calls: Array<ReturnType<typeof deferred>> = [];
	const focus = new EventTarget();
	let scheduled: (() => void) | null = null;
	const store = createCommandHistoryStore({
		fetch: () => {
			const call = deferred();
			calls.push(call);
			return call.promise;
		},
		focusTarget: focus as unknown as Window,
		schedule: (run) => {
			scheduled = run;
			return () => {
				scheduled = null;
			};
		},
	});
	return { store, calls, focus, fireScheduled: () => scheduled?.(), hasScheduled: () => scheduled !== null };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("fetchTerminalHistory", () => {
	beforeEach(() => apiGetMock.mockReset());

	it("asks the daemon for the capped history and maps finishedAt to epoch milliseconds", async () => {
		apiGetMock.mockResolvedValue({
			data: {
				commands: [
					{ command: "make", finishedAt: "2026-09-27T10:00:00Z" },
					{ command: "", finishedAt: "2026-09-27T10:00:01Z" },
					{ command: "ls", finishedAt: "not a date" },
				],
			},
		});
		await expect(fetchTerminalHistory()).resolves.toEqual([{ command: "make", at: Date.parse("2026-09-27T10:00:00Z") }]);
		expect(apiGetMock).toHaveBeenCalledWith("/api/v1/terminal-history", {
			params: { query: { limit: TERMINAL_HISTORY_LIMIT } },
		});
	});

	it("throws on an error envelope", async () => {
		apiGetMock.mockResolvedValue({ error: { message: "boom" } });
		await expect(fetchTerminalHistory()).rejects.toThrow("Request failed");
	});
});

describe("createCommandHistoryStore", () => {
	it("fetches on the first subscriber and notifies when the answer lands", async () => {
		const { store, calls } = harness();
		const listener = vi.fn();
		store.subscribe(listener);
		store.subscribe(vi.fn());
		expect(calls).toHaveLength(1);
		calls[0]!.resolve([{ command: "npm test", at: 5 }]);
		await flush();
		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.entries()).toEqual([{ command: "npm test", at: 5 }]);
	});

	it("runs one fetch at a time and one more after a refresh asked for during it", async () => {
		const { store, calls } = harness();
		store.subscribe(vi.fn());
		store.refresh();
		store.refresh();
		expect(calls).toHaveLength(1);
		calls[0]!.resolve([]);
		await flush();
		expect(calls).toHaveLength(2);
		calls[1]!.resolve([{ command: "b", at: 2 }]);
		await flush();
		expect(calls).toHaveLength(2);
		expect(store.entries()).toEqual([{ command: "b", at: 2 }]);
	});

	it("keeps the last good entries when a fetch fails", async () => {
		const { store, calls } = harness();
		store.subscribe(vi.fn());
		calls[0]!.resolve([{ command: "a", at: 1 }]);
		await flush();
		store.refresh();
		calls[1]!.reject(new Error("daemon down"));
		await flush();
		expect(store.entries()).toEqual([{ command: "a", at: 1 }]);
	});

	it("refreshes on window focus only while someone listens", async () => {
		const { store, calls, focus } = harness();
		const off = store.subscribe(vi.fn());
		calls[0]!.resolve([]);
		await flush();
		focus.dispatchEvent(new Event("focus"));
		expect(calls).toHaveLength(2);
		calls[1]!.resolve([]);
		await flush();
		off();
		focus.dispatchEvent(new Event("focus"));
		expect(calls).toHaveLength(2);
	});

	it("refreshes once after a burst of finished commands", () => {
		const { store, calls, fireScheduled, hasScheduled } = harness();
		store.noteCommandFinished();
		store.noteCommandFinished();
		expect(calls).toHaveLength(0);
		expect(hasScheduled()).toBe(true);
		fireScheduled();
		expect(calls).toHaveLength(1);
	});
});
