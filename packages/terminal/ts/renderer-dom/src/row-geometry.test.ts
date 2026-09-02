import { describe, expect, it } from "vitest";
import type { BlockId, BlockView } from "@operator/terminal-core";
import { paintedRowOrigin } from "./row-geometry.js";

const block = (id: string, firstRow: number, rowCount: number): BlockView => ({
	id,
	firstRow,
	rowCount,
	state: "finished",
	source: "synthetic",
	exitCode: null,
	durationMs: null,
	command: "",
	cwd: "",
	gitBranch: "",
	bookmarked: false,
});

function section(labels: number[], top: number, left: number, rowHeight: number): HTMLElement {
	const element = document.createElement("section");
	for (const label of labels) {
		const row = document.createElement("div");
		row.dataset.terminalRow = String(label);
		row.getBoundingClientRect = () =>
			({ left, top: top + label * rowHeight }) as DOMRect;
		element.append(row);
	}
	return element;
}

describe("paintedRowOrigin", () => {
	it("returns the painted position of the row itself", () => {
		const blocks = [block("a", 0, 3), block("b", 3, 4)];
		const elements = new Map<BlockId, HTMLElement>([
			["a", section([0, 1, 2], 100, 40, 16)],
			["b", section([0, 1, 2, 3], 200, 40, 16)],
		]);
		expect(paintedRowOrigin(blocks, elements, 4, 16)).toEqual({ left: 40, top: 216 });
	});

	it("extrapolates a row the virtualiser left unpainted", () => {
		const blocks = [block("a", 0, 40)];
		const elements = new Map<BlockId, HTMLElement>([["a", section([20, 21, 22], 500, 8, 16)]]);
		expect(paintedRowOrigin(blocks, elements, 25, 16)).toEqual({ left: 8, top: 900 });
	});

	it("extrapolates past the trimmed end of the last block", () => {
		const blocks = [block("a", 0, 2)];
		const elements = new Map<BlockId, HTMLElement>([["a", section([0, 1], 10, 4, 16)]]);
		expect(paintedRowOrigin(blocks, elements, 5, 16)).toEqual({ left: 4, top: 90 });
	});

	it("gives up when nothing is painted", () => {
		expect(paintedRowOrigin([], new Map(), 0, 16)).toBeNull();
		expect(paintedRowOrigin([block("a", 0, 1)], new Map(), 0, 16)).toBeNull();
		expect(
			paintedRowOrigin([block("a", 0, 1)], new Map([["a", section([], 0, 0, 16)]]), 0, 16),
		).toBeNull();
	});
});
