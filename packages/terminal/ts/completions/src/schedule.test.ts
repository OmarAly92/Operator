import { describe, expect, it } from "vitest";
import { rankChunked, FRAME_BUDGET_MS } from "./schedule.js";
import type { Candidate } from "./rank.js";

const many = (count: number): Candidate[] =>
	Array.from({ length: count }, (_, index) => ({
		value: `command-${index}`,
		kind: "command" as const,
	}));

const open = new AbortController().signal;

describe("rankChunked", () => {
	it("ranks a small set in one pass", async () => {
		const ranked = await rankChunked(many(10), "command-3", open);
		expect(ranked?.[0]?.candidate.value).toBe("command-3");
	});

	it("ranks a large set completely", async () => {
		const ranked = await rankChunked(many(20000), "command-19999", open);
		expect(ranked?.[0]?.candidate.value).toBe("command-19999");
	});

	it("yields rather than running past the frame budget in one go", async () => {
		let clock = 0;
		let yields = 0;
		const scheduler = {
			now: () => {
				clock += FRAME_BUDGET_MS;
				return clock;
			},
			yield: async () => {
				yields += 1;
			},
		};
		const ranked = await rankChunked(many(2000), "command", open, scheduler);
		expect(ranked).not.toBeNull();
		expect(yields).toBeGreaterThan(0);
	});

	it("does not yield when the whole set fits in one budget", async () => {
		let yields = 0;
		const scheduler = {
			now: () => 0,
			yield: async () => {
				yields += 1;
			},
		};
		await rankChunked(many(2000), "command", open, scheduler);
		expect(yields).toBe(0);
	});

	it("returns null when aborted partway", async () => {
		const controller = new AbortController();
		let clock = 0;
		const scheduler = {
			now: () => {
				clock += 1000;
				return clock;
			},
			yield: async () => {
				controller.abort();
			},
		};
		const ranked = await rankChunked(many(20000), "command", controller.signal, scheduler);
		expect(ranked).toBeNull();
	});

	it("returns null when it starts already aborted", async () => {
		const controller = new AbortController();
		controller.abort();
		expect(await rankChunked(many(10), "c", controller.signal)).toBeNull();
	});

	it("gives the same answer as the unchunked ranker", async () => {
		const candidates = many(500);
		const { rank } = await import("./rank.js");
		const chunked = await rankChunked(candidates, "c1", open);
		expect(chunked?.map((entry) => entry.candidate.value)).toEqual(
			rank(candidates, "c1").map((entry) => entry.candidate.value),
		);
	});
});
