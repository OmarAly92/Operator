import { defaultStrings, type BlockView } from "@operator/terminal-core";
import { renderBlockHeader } from "./block-header.js";
import { placeCursor, type CursorPlacement } from "./cursor.js";
import type { RendererFeatures } from "./features.js";
import { buildRowNode, type RowSource } from "./row-builder.js";
import type { RowWindow } from "./viewport.js";

const CLASS_SPACER = "terminal-spacer";
const HEADER_KEY_SEPARATOR = "\u0000";
export const ROW_GENERATION_ATTR = "data-terminal-row-gen";

export type BlockBodyInput = Readonly<{
	block: BlockView;
	snapshot: RowSource;
	rowWindow: RowWindow | null;
	rowHeight: number;
	cellWidth: number;
	cursor: CursorPlacement | null;
	cursorElement: HTMLElement;
	decoder: TextDecoder;
	firstStableRow: number;
	generation: number;
	rowIsFresh: (stableRow: number, node: HTMLElement) => boolean;
	features: RendererFeatures;
}>;

type BlockBody = {
	rows: Map<number, HTMLElement>;
	header: HTMLElement | null;
	headerKey: string;
	leading: HTMLElement;
	trailing: HTMLElement;
};

const bodies = new WeakMap<HTMLElement, BlockBody>();

function bodyOf(section: HTMLElement): BlockBody {
	let body = bodies.get(section);
	if (!body) {
		body = { rows: new Map(), header: null, headerKey: "", leading: spacer(), trailing: spacer() };
		bodies.set(section, body);
	}
	return body;
}

function headerKeyOf(block: BlockView): string {
	return [block.state, block.source, block.exitCode, block.durationMs, block.command, block.cwd, block.gitBranch, block.bookmarked].join(HEADER_KEY_SEPARATOR);
}

export function populateBlock(section: HTMLElement, input: BlockBodyInput): { cursorPlaced: boolean } {
	const { block, snapshot, rowWindow, rowHeight, decoder } = input;
	const body = bodyOf(section);
	const key = headerKeyOf(block);
	if (!body.header || body.headerKey !== key) {
		body.header = renderBlockHeader(block, defaultStrings);
		body.headerKey = key;
	}
	const desired: Node[] = [body.header];
	const firstRow = rowWindow ? rowWindow.firstRow : 0;
	const lastRow = rowWindow ? rowWindow.lastRow : block.rowCount - 1;
	if (rowWindow && firstRow > 0) {
		body.leading.style.height = `${firstRow * rowHeight}px`;
		desired.push(body.leading);
	}
	let cursorPlaced = false;
	const keep = new Set<number>();
	for (let rowOffset = firstRow; rowOffset <= lastRow; rowOffset += 1) {
		const snapshotRow = block.firstRow + rowOffset;
		const stableRow = input.firstStableRow + snapshotRow;
		keep.add(stableRow);
		let node = body.rows.get(stableRow);
		if (!node || !input.rowIsFresh(stableRow, node)) {
			node = buildRowNode(snapshot, snapshotRow, stableRow, decoder, input.cellWidth, input.features);
			node.setAttribute(ROW_GENERATION_ATTR, String(input.generation));
			body.rows.set(stableRow, node);
		}
		if (input.cursor && input.cursor.row === snapshotRow) {
			placeCursor(node, input.cursorElement, input.cursor.column, input.cellWidth);
			cursorPlaced = true;
		}
		desired.push(node);
	}
	for (const stableRow of [...body.rows.keys()]) {
		if (!keep.has(stableRow)) body.rows.delete(stableRow);
	}
	if (rowWindow) {
		const trailingRows = block.rowCount - 1 - lastRow;
		if (trailingRows > 0) {
			body.trailing.style.height = `${trailingRows * rowHeight}px`;
			desired.push(body.trailing);
		}
	}
	reconcileChildren(section, desired);
	return { cursorPlaced };
}

export function reconcileChildren(section: HTMLElement, desired: readonly Node[]): void {
	const wanted = new Set(desired);
	for (const child of [...section.childNodes]) {
		if (!wanted.has(child)) child.remove();
	}
	for (let index = 0; index < desired.length; index += 1) {
		const want = desired[index]!;
		const have = section.childNodes[index] ?? null;
		if (have !== want) section.insertBefore(want, have);
	}
}

function spacer(): HTMLElement {
	const element = document.createElement("div");
	element.className = CLASS_SPACER;
	element.dataset.terminalRowSpacer = "true";
	return element;
}
