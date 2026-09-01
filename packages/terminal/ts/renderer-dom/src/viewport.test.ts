import { describe, expect, it } from "vitest";
import { computeWindow, findNeighbourBlock } from "./viewport";

function blocks(counts: number[]) {
	let firstRow = 0;
	return counts.map((rowCount, index) => {
		const block = {
			id: `0:${index}`,
			firstRow,
			rowCount,
			state: "finished" as const,
			source: "osc133" as const,
			exitCode: 0,
			durationMs: null,
			command: "",
			cwd: "",
			gitBranch: "",
			bookmarked: false,
		};
		firstRow += rowCount;
		return block;
	});
}

const base = { rowHeight: 20, headerHeight: 24, overscanRows: 2, viewportHeight: 100 };

describe("computeWindow", () => {
	it("selects only the blocks intersecting the viewport", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2, 2, 2, 2]), scrollTop: 0 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBeLessThan(4);
	});

	it("skips blocks entirely above the viewport and reports a leading spacer", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2, 2, 2, 2]), scrollTop: 200 });
		expect(result.firstBlock).toBeGreaterThan(0);
		expect(result.leadingSpacer).toBeGreaterThan(0);
	});

	it("windows rows inside a single very tall block", () => {
		const result = computeWindow({ ...base, blocks: blocks([10_000]), scrollTop: 40_000 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBe(0);
		const window = result.rowWindows.get(0);
		expect(window).toBeDefined();
		expect(window!.lastRow - window!.firstRow).toBeLessThan(20);
		expect(window!.firstRow).toBeGreaterThan(1_000);
	});

	it("spacers plus rendered height equal the total content height", () => {
		const list = blocks([3, 7, 5, 11]);
		const result = computeWindow({ ...base, blocks: list, scrollTop: 60 });
		const total = list.reduce((sum, b) => sum + b.rowCount * 20 + 24, 0);
		let rendered = 0;
		for (let i = result.firstBlock; i <= result.lastBlock; i += 1) {
			rendered += list[i].rowCount * 20 + 24;
		}
		expect(result.leadingSpacer + rendered + result.trailingSpacer).toBe(total);
	});

	it("an empty block list produces an empty window", () => {
		const result = computeWindow({ ...base, blocks: [], scrollTop: 0 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBe(-1);
		expect(result.leadingSpacer).toBe(0);
		expect(result.trailingSpacer).toBe(0);
	});

	it("clamps a scrollTop past the end instead of producing a negative window", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2]), scrollTop: 999_999 });
		expect(result.firstBlock).toBeLessThanOrEqual(result.lastBlock);
		expect(result.trailingSpacer).toBeGreaterThanOrEqual(0);
	});

	describe("pinned block", () => {
		const pinnedBase = { rowHeight: 20, headerHeight: 24, overscanRows: 2, viewportHeight: 100 };

		it("names the block that owns the center of the viewport", () => {
			const list = blocks([2, 100, 2]);
			const block1Start = 2 * 20 + 24;
			const insideBlock1 = block1Start + 50 * 20;
			const result = computeWindow({ ...pinnedBase, blocks: list, scrollTop: insideBlock1 });
			expect(result.pinnedBlockIndex).toBe(1);
		});

		it("hands over to the next block once the viewport's center passes into it", () => {
			const list = blocks([2, 100, 2]);
			const block1Start = 2 * 20 + 24;
			const block1End = block1Start + 100 * 20 + 24;
			const justPast = block1End + 1;
			const result = computeWindow({ ...pinnedBase, blocks: list, scrollTop: justPast });
			expect(result.pinnedBlockIndex).toBe(2);
		});

		it("keeps the first block pinned at the very top of the document", () => {
			const result = computeWindow({ ...pinnedBase, blocks: blocks([2, 2, 2]), scrollTop: 0 });
			expect(result.pinnedBlockIndex).toBe(0);
		});

		it("returns the last block when scrollTop is clamped past the document end", () => {
			const list = blocks([2, 2]);
			const result = computeWindow({ ...pinnedBase, blocks: list, scrollTop: 999_999 });
			expect(result.pinnedBlockIndex).toBe(list.length - 1);
		});

		it("returns -1 when there are no blocks", () => {
			const result = computeWindow({ ...pinnedBase, blocks: [], scrollTop: 0 });
			expect(result.pinnedBlockIndex).toBe(-1);
		});
	});
});

describe("findNeighbourBlock", () => {
	it("returns -1 for an empty list", () => {
		expect(findNeighbourBlock([], 0, 1)).toBe(-1);
		expect(findNeighbourBlock([], -1, -1)).toBe(-1);
	});

	it("returns the first block when stepping forward from -1", () => {
		expect(findNeighbourBlock(blocks([2, 2, 2]), -1, 1)).toBe(0);
	});

	it("returns the last block when stepping backward from -1", () => {
		expect(findNeighbourBlock(blocks([2, 2, 2]), -1, -1)).toBe(2);
	});

	it("clamps to the start when stepping past the first block", () => {
		expect(findNeighbourBlock(blocks([2, 2, 2]), 0, -1)).toBe(0);
	});

	it("clamps to the end when stepping past the last block", () => {
		expect(findNeighbourBlock(blocks([2, 2, 2]), 2, 1)).toBe(2);
	});

	it("moves by exactly delta in the middle of the list", () => {
		expect(findNeighbourBlock(blocks([2, 2, 2, 2, 2]), 2, 1)).toBe(3);
		expect(findNeighbourBlock(blocks([2, 2, 2, 2, 2]), 2, -1)).toBe(1);
	});
});
