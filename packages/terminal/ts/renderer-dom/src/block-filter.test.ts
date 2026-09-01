import { describe, expect, it } from "vitest";
import type { BlockView } from "@operator/terminal-core";
import { applyFilter, extractBlockIds, filterByFailed } from "./block-filter";

function makeBlock(overrides: Partial<BlockView> & { id: string }): BlockView {
	return {
		firstRow: 0,
		rowCount: 2,
		state: "finished",
		source: "osc133",
		exitCode: 0,
		durationMs: null,
		command: "cmd",
		cwd: "",
		gitBranch: "",
		bookmarked: false,
		...overrides,
	};
}

const BLOCKS: BlockView[] = [
	makeBlock({ id: "0:0", state: "finished", exitCode: 0 }),
	makeBlock({ id: "0:1", state: "finished", exitCode: 1 }),
	makeBlock({ id: "0:2", state: "running", exitCode: null }),
	makeBlock({ id: "0:3", state: "finished", exitCode: 0, source: "synthetic" }),
	makeBlock({ id: "0:4", state: "abandoned", exitCode: null, bookmarked: true }),
];

describe("applyFilter", () => {
	it("returns a copy of the full list when filter is null", () => {
		const result = applyFilter(BLOCKS, null);
		expect(result).toEqual(BLOCKS);
		expect(result).not.toBe(BLOCKS);
	});

	it("does not mutate the input", () => {
		const original = BLOCKS.slice();
		applyFilter(BLOCKS, { state: "running" });
		expect(BLOCKS).toEqual(original);
	});

	it("filters by state", () => {
		const result = applyFilter(BLOCKS, { state: "running" });
		expect(extractBlockIds(result)).toEqual(["0:2"]);
	});

	it("filters by exit code non-zero", () => {
		const result = applyFilter(BLOCKS, { exitCodeNonZero: true });
		expect(extractBlockIds(result)).toEqual(["0:1"]);
	});

	it("filters by source", () => {
		const result = applyFilter(BLOCKS, { source: "synthetic" });
		expect(extractBlockIds(result)).toEqual(["0:3"]);
	});

	it("filters by bookmarked", () => {
		const result = applyFilter(BLOCKS, { bookmarked: true });
		expect(extractBlockIds(result)).toEqual(["0:4"]);
	});

	it("combines multiple predicates with AND semantics", () => {
		const result = applyFilter(BLOCKS, {
			state: "finished",
			exitCodeNonZero: true,
		});
		expect(extractBlockIds(result)).toEqual(["0:1"]);
	});

	it("preserves block ids across a filter-and-clear cycle", () => {
		const before = extractBlockIds(BLOCKS);
		const filtered = applyFilter(BLOCKS, { state: "finished" });
		const cleared = applyFilter(BLOCKS, null);
		const after = extractBlockIds(cleared);
		expect(after).toEqual(before);
		expect(filtered.length).toBeLessThan(cleared.length);
	});

	it("returns an empty list when nothing matches", () => {
		const result = applyFilter(BLOCKS, { state: "abandoned", exitCodeNonZero: true });
		expect(result).toEqual([]);
	});
});

describe("filterByFailed", () => {
	it("keeps only finished blocks with a non-zero exit code", () => {
		const result = filterByFailed(BLOCKS);
		expect(extractBlockIds(result)).toEqual(["0:1"]);
	});

	it("returns an empty list when no blocks failed", () => {
		const allOk = BLOCKS.map((b) => ({ ...b, exitCode: 0 }));
		expect(filterByFailed(allOk)).toEqual([]);
	});

	it("excludes synthetic blocks that lack an exit code", () => {
		const result = filterByFailed([
			makeBlock({ id: "0:0", source: "synthetic", exitCode: null }),
		]);
		expect(result).toEqual([]);
	});
});
