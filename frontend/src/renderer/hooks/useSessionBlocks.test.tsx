import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { BlockEventView, TerminalMux } from "../lib/terminal-mux";
import { BLOCK_MAX_WINDOW, BLOCK_PAGE, BLOCK_WINDOW, useSessionBlocks } from "./useSessionBlocks";

const { getMock } = vi.hoisted(() => ({ getMock: vi.fn() }));

vi.mock("../lib/api-client", () => ({
	apiClient: { GET: getMock },
	apiErrorMessage: (error: unknown, fallback = "Request failed") =>
		error instanceof Error ? error.message : fallback,
	getApiBaseUrl: () => "http://127.0.0.1:3001",
}));

function block(seq: number, kind: string, extra: Partial<BlockEventView> = {}): BlockEventView {
	return { seq, sessionId: "s-1", kind, createdAt: "2026-08-27T10:00:00Z", ...extra };
}

function fakeMux() {
	const listeners = new Map<string, Set<(value: BlockEventView) => void>>();
	const subscribed: string[] = [];
	const unsubscribed: string[] = [];
	const mux: TerminalMux = {
		open: vi.fn(),
		sendInput: vi.fn(),
		resize: vi.fn(),
		close: vi.fn(),
		onData: vi.fn(() => () => undefined),
		onExit: vi.fn(() => () => undefined),
		onOpened: vi.fn(() => () => undefined),
		onError: vi.fn(() => () => undefined),
		onConnectionChange: vi.fn(() => () => undefined),
		dispose: vi.fn(),
		subscribeBlocks: (sessionId: string) => {
			subscribed.push(sessionId);
		},
		unsubscribeBlocks: (sessionId: string) => {
			unsubscribed.push(sessionId);
		},
		onBlock: (sessionId: string, listener: (value: BlockEventView) => void) => {
			const set = listeners.get(sessionId) ?? new Set();
			set.add(listener);
			listeners.set(sessionId, set);
			return () => set.delete(listener);
		},
	};
	return {
		mux,
		subscribed,
		unsubscribed,
		emit: (sessionId: string, value: BlockEventView) =>
			listeners.get(sessionId)?.forEach((listener) => listener(value)),
	};
}

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

function respondWith(blocks: BlockEventView[]) {
	getMock.mockResolvedValue({ data: { blocks }, error: undefined });
}

describe("useSessionBlocks", () => {
	beforeEach(() => {
		getMock.mockReset();
		respondWith([]);
	});

	it("subscribes before it fetches history", async () => {
		const order: string[] = [];
		const fake = fakeMux();
		const subscribe = fake.mux.subscribeBlocks;
		fake.mux.subscribeBlocks = (sessionId: string) => {
			order.push("subscribe");
			subscribe(sessionId);
		};
		getMock.mockImplementation(async () => {
			order.push("history");
			return { data: { blocks: [] }, error: undefined };
		});

		renderHook(() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }), {
			wrapper,
		});

		await waitFor(() => expect(order).toContain("history"));
		expect(order[0]).toBe("subscribe");
	});

	it("merges a live event that lands before history without duplicating it", async () => {
		const fake = fakeMux();
		respondWith([block(1, "prompt_submit", { text: "go" }), block(2, "stop", { text: "done" })]);

		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);

		act(() => fake.emit("s-1", block(2, "stop", { text: "done" })));
		await waitFor(() => expect(result.current.blocks.map((item) => item.id)).toEqual(["seq-1", "seq-2"]));
	});

	it("ignores events for another session", async () => {
		const fake = fakeMux();
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.isLoading).toBe(false));

		act(() => fake.emit("s-2", block(1, "stop", { text: "other" })));
		expect(result.current.blocks).toEqual([]);
	});

	it("keeps at most BLOCK_WINDOW events, dropping the oldest", async () => {
		const fake = fakeMux();
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.isLoading).toBe(false));

		act(() => {
			for (let seq = 1; seq <= BLOCK_WINDOW + 10; seq += 1) {
				fake.emit("s-1", block(seq, "stop", { text: `line ${seq}` }));
			}
		});

		await waitFor(() => expect(result.current.blocks).toHaveLength(BLOCK_WINDOW));
		expect(result.current.blocks[0].body).toBe("line 11");
	});

	it("pages backwards from the lowest sequence it holds, with beforeSeq only", async () => {
		const fake = fakeMux();
		respondWith([block(20, "stop", { text: "newest" })]);
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.blocks).toHaveLength(1));

		respondWith([block(18, "stop", { text: "older" })]);
		act(() => result.current.loadOlder());

		await waitFor(() => expect(result.current.blocks.map((item) => item.body)).toEqual(["older", "newest"]));
		const query = getMock.mock.calls.at(-1)?.[1]?.params?.query as Record<string, unknown>;
		expect(query.beforeSeq).toBe(20);
		expect(query.afterSeq).toBeUndefined();
	});

	it("stops offering older pages once the log is exhausted", async () => {
		const fake = fakeMux();
		respondWith([block(5, "stop", { text: "a" })]);
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.hasOlder).toBe(true));

		respondWith([]);
		act(() => result.current.loadOlder());
		await waitFor(() => expect(result.current.hasOlder).toBe(false));
	});

	it("retires the older control when the window can hold no more", async () => {
		const fake = fakeMux();
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.isLoading).toBe(false));

		act(() => {
			for (let seq = 100_000; seq < 100_000 + BLOCK_MAX_WINDOW; seq += 1) {
				fake.emit("s-1", block(seq, "stop", { text: "n" }));
			}
		});
		await waitFor(() => expect(result.current.blocks).toHaveLength(BLOCK_MAX_WINDOW > BLOCK_WINDOW ? BLOCK_WINDOW : BLOCK_MAX_WINDOW));

		for (let page = 0; page < 40 && result.current.hasOlder; page += 1) {
			const base = 99_000 - page * BLOCK_PAGE;
			respondWith(Array.from({ length: BLOCK_PAGE }, (_, index) => block(base + index, "stop", { text: "old" })));
			act(() => result.current.loadOlder());
			await waitFor(() => expect(result.current.isLoadingOlder).toBe(false));
		}

		expect(result.current.hasOlder).toBe(false);
		expect(result.current.blocks.length).toBeLessThanOrEqual(BLOCK_MAX_WINDOW);
	});

	it("never asks for more than the window can still hold", async () => {
		const fake = fakeMux();
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.isLoading).toBe(false));

		for (let page = 0; page < 40 && result.current.hasOlder; page += 1) {
			const base = 99_000 - page * BLOCK_PAGE;
			respondWith(Array.from({ length: BLOCK_PAGE }, (_, index) => block(base + index, "stop", { text: "old" })));
			act(() => result.current.loadOlder());
			await waitFor(() => expect(result.current.isLoadingOlder).toBe(false));
		}

		for (const call of getMock.mock.calls) {
			const query = call[1]?.params?.query as Record<string, unknown> | undefined;
			if (query?.beforeSeq === undefined) continue;
			expect(query.limit).toBeGreaterThan(0);
			expect(query.limit).toBeLessThanOrEqual(BLOCK_PAGE);
		}
	});

	it("leaves no block spinning once the session has ended", async () => {
		const fake = fakeMux();
		const { result, rerender } = renderHook(
			({ ended }: { ended: boolean }) =>
				useSessionBlocks("s-1", {
					enabled: true,
					harness: "claude-code",
					sessionEnded: ended,
					createMux: () => fake.mux,
				}),
			{ wrapper, initialProps: { ended: false } },
		);
		await waitFor(() => expect(result.current.isLoading).toBe(false));

		act(() => fake.emit("s-1", block(1, "prompt_submit", { text: "go" })));
		await waitFor(() => expect(result.current.blocks[0].status).toBe("running"));

		rerender({ ended: true });
		await waitFor(() => expect(result.current.blocks[0].status).toBe("failed"));
		expect(result.current.blocks[0].body).not.toBe("");
	});

	it("does nothing at all for an uncovered harness", async () => {
		const fake = fakeMux();
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "aider", createMux: () => fake.mux }),
			{ wrapper },
		);

		await waitFor(() => expect(result.current.isLoading).toBe(false));
		expect(fake.subscribed).toEqual([]);
		expect(getMock).not.toHaveBeenCalled();
	});

	it("does nothing while disabled", async () => {
		const fake = fakeMux();
		renderHook(() => useSessionBlocks("s-1", { enabled: false, harness: "claude-code", createMux: () => fake.mux }), {
			wrapper,
		});

		await waitFor(() => expect(getMock).not.toHaveBeenCalled());
		expect(fake.subscribed).toEqual([]);
	});

	it("unsubscribes and disposes its mux on unmount", async () => {
		const fake = fakeMux();
		const { unmount } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(fake.subscribed).toEqual(["s-1"]));

		unmount();
		expect(fake.unsubscribed).toEqual(["s-1"]);
		expect(fake.mux.dispose).toHaveBeenCalled();
	});

	it("surfaces a history failure without discarding live events", async () => {
		const fake = fakeMux();
		getMock.mockResolvedValue({ data: undefined, error: { message: "offline" } });
		const { result } = renderHook(
			() => useSessionBlocks("s-1", { enabled: true, harness: "claude-code", createMux: () => fake.mux }),
			{ wrapper },
		);
		await waitFor(() => expect(result.current.error).toBeDefined());

		act(() => fake.emit("s-1", block(1, "stop", { text: "live" })));
		await waitFor(() => expect(result.current.blocks[0].body).toBe("live"));
	});
});
