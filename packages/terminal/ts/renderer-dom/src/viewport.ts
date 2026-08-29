import type { BlockView } from "@operator/terminal-core";

export type WindowInput = Readonly<{
	blocks: readonly BlockView[];
	scrollTop: number;
	viewportHeight: number;
	rowHeight: number;
	headerHeight: number;
	overscanRows: number;
}>;

export type RowWindow = Readonly<{ firstRow: number; lastRow: number }>;

export type WindowResult = Readonly<{
	firstBlock: number;
	lastBlock: number;
	leadingSpacer: number;
	trailingSpacer: number;
	rowWindows: ReadonlyMap<number, RowWindow>;
}>;

const EMPTY_WINDOW: WindowResult = Object.freeze({
	firstBlock: 0,
	lastBlock: -1,
	leadingSpacer: 0,
	trailingSpacer: 0,
	rowWindows: new Map(),
});

function headerHeightFor(block: BlockView, headerHeight: number): number {
	return block.source === "synthetic" ? 0 : headerHeight;
}

function blockHeight(block: BlockView, rowHeight: number, headerHeight: number): number {
	return block.rowCount * rowHeight + headerHeightFor(block, headerHeight);
}

function clampScrollTop(scrollTop: number, total: number, viewport: number): number {
	if (!Number.isFinite(scrollTop) || scrollTop < 0) return 0;
	const max = Math.max(0, total - viewport);
	return scrollTop > max ? max : scrollTop;
}

export function computeWindow(input: WindowInput): WindowResult {
	const { blocks, rowHeight, headerHeight, viewportHeight, overscanRows } = input;
	if (blocks.length === 0) return EMPTY_WINDOW;

	let total = 0;
	for (let i = 0; i < blocks.length; i += 1) {
		total += blockHeight(blocks[i], rowHeight, headerHeight);
	}
	const scrollTop = clampScrollTop(input.scrollTop, total, viewportHeight);

	let accumulated = 0;
	let firstBlock = -1;
	let lastBlock = -1;
	let leadingSpacer = 0;
	const rowWindows = new Map<number, RowWindow>();
	const firstRowInWindow = scrollTop;
	const lastRowInWindow = scrollTop + viewportHeight;

	for (let i = 0; i < blocks.length; i += 1) {
		const block = blocks[i];
		const blockStart = accumulated;
		const blockEnd = accumulated + blockHeight(block, rowHeight, headerHeight);
		const isIntersecting = blockEnd > firstRowInWindow && blockStart < lastRowInWindow;
		if (isIntersecting) {
			if (firstBlock === -1) {
				firstBlock = i;
				leadingSpacer = blockStart;
			}
			lastBlock = i;
			if (block.rowCount * rowHeight > viewportHeight) {
				const headerOffset = headerHeightFor(block, headerHeight);
				const firstVisibleRow = Math.max(
					0,
					Math.floor((firstRowInWindow - blockStart - headerOffset) / rowHeight) - overscanRows,
				);
				const lastVisibleRow = Math.min(
					block.rowCount - 1,
					Math.ceil((lastRowInWindow - blockStart - headerOffset) / rowHeight) + overscanRows,
				);
				rowWindows.set(i, { firstRow: firstVisibleRow, lastRow: lastVisibleRow });
			}
		} else if (firstBlock !== -1) {
			break;
		}
		accumulated = blockEnd;
	}

	if (firstBlock === -1) {
		const last = blocks.length - 1;
		const tail = blockHeight(blocks[last], rowHeight, headerHeight);
		return Object.freeze({
			firstBlock: last,
			lastBlock: last,
			leadingSpacer: total - tail,
			trailingSpacer: 0,
			rowWindows: new Map(),
		});
	}

	const trailing = total - accumulated;
	return Object.freeze({
		firstBlock,
		lastBlock,
		leadingSpacer,
		trailingSpacer: trailing,
		rowWindows,
	});
}
