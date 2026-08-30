import { describe, expect, it, vi } from "vitest";
import { CompletionDispatcher } from "./completions.js";
import type { CompletionRequest, CompletionResult } from "./completions.js";

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
};

const result = (value: string): CompletionResult => ({
	items: [{ value, displayValue: value, description: null, kind: "command", matchedIndices: [] }],
	span: { start: 0, end: 0 },
	query: "",
});

describe("CompletionDispatcher", () => {
	it("delivers a provider's result to a listener", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		dispatcher.register(async () => result("git"));
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toHaveLength(1));
		expect(seen[0]?.items[0]?.value).toBe("git");
	});

	it("passes the line, cursor and cwd through to the provider", async () => {
		const dispatcher = new CompletionDispatcher(() => "/repo", host);
		let seen: CompletionRequest | null = null;
		dispatcher.register(async (request) => {
			seen = request;
			return null;
		});
		dispatcher.request("git co", 6);
		await vi.waitFor(() => expect(seen).not.toBeNull());
		expect(seen!.line).toBe("git co");
		expect(seen!.cursor).toBe(6);
		expect(seen!.cwd).toBe("/repo");
	});

	it("drops a stale result when a newer request has been made", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		let release: (() => void) | null = null;
		const gate = new Promise<void>((resolve) => {
			release = resolve;
		});
		let call = 0;
		dispatcher.register(async (request) => {
			call += 1;
			if (call === 1) {
				await gate;
				return result("stale");
			}
			return result("fresh");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));

		dispatcher.request("g", 1);
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toHaveLength(1));
		release!();
		await Promise.resolve();
		await Promise.resolve();

		expect(seen.map((entry) => entry?.items[0]?.value)).toEqual(["fresh"]);
	});

	it("aborts the previous request's signal when a new one arrives", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const signals: AbortSignal[] = [];
		dispatcher.register(async (request) => {
			signals.push(request.signal);
			return null;
		});
		dispatcher.request("g", 1);
		await vi.waitFor(() => expect(signals).toHaveLength(1));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(signals).toHaveLength(2));
		expect(signals[0]!.aborted).toBe(true);
		expect(signals[1]!.aborted).toBe(false);
	});

	it("emits null and aborts on cancel", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const signals: AbortSignal[] = [];
		dispatcher.register(async (request) => {
			signals.push(request.signal);
			return result("git");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(signals).toHaveLength(1));
		dispatcher.cancel();
		expect(signals[0]!.aborted).toBe(true);
		expect(seen.at(-1)).toBeNull();
	});

	it("emits null when no provider is registered", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});

	it("survives a provider that throws, emitting null", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		dispatcher.register(async () => {
			throw new Error("provider exploded");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});

	it("stops delivering to an unregistered provider", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const dispose = dispatcher.register(async () => result("git"));
		dispose();
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});
});
