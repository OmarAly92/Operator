import { describe, expect, it } from "vitest";
import {
	BLOCK_COMMAND_GAP_LINES,
	BLOCK_PADDING_BOTTOM_LINES,
	BLOCK_PADDING_TOP_LINES,
	BLOCK_PADDING_X_PX,
	blockPaddingY,
} from "./block-metrics";
import { terminalStyles } from "./styles";

// The virtualiser estimates a block's height from these constants while the
// stylesheet reserves the space. If the two disagree the estimate drifts from
// what is rendered, and with enough blocks the scroll position walks away from
// the content -- the top of the transcript becomes unreachable.
describe("block metrics match the stylesheet", () => {
	const padding = /\.terminal-block \{[^}]*?padding:\s*calc\(var\(--terminal-line-height\) \* ([\d.]+)\) (\d+)px calc\(var\(--terminal-line-height\) \* ([\d.]+)\)/s.exec(
		terminalStyles,
	);

	it("declares the block padding the stylesheet reserves", () => {
		expect(padding).not.toBeNull();
		expect(Number(padding![1])).toBe(BLOCK_PADDING_TOP_LINES);
		expect(Number(padding![2])).toBe(BLOCK_PADDING_X_PX);
		expect(Number(padding![3])).toBe(BLOCK_PADDING_BOTTOM_LINES);
	});

	it("declares the command-to-output gap the header reserves", () => {
		const gap = /\.terminal-block-header \{[^}]*?margin-bottom:\s*calc\(var\(--terminal-line-height\) \* ([\d.]+)\)/s.exec(
			terminalStyles,
		);
		expect(gap).not.toBeNull();
		expect(Number(gap![1])).toBe(BLOCK_COMMAND_GAP_LINES);
	});

	it("reserves top and bottom padding together", () => {
		expect(blockPaddingY(20)).toBe((BLOCK_PADDING_TOP_LINES + BLOCK_PADDING_BOTTOM_LINES) * 20);
	});
});
