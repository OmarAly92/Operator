import { defaultStrings, type BlockView, type HostCapabilities } from "@operator/terminal-core";
import { renderBlockActions, type BlockTextSource } from "./block-actions.js";
import { renderBlockHeader } from "./block-header.js";
import { createCursorElement, type CursorPlacement } from "./cursor.js";
import { buildRowNode, type RowSource } from "./row-builder.js";
import type { RowWindow } from "./viewport.js";

const CLASS_SPACER = "terminal-spacer";

export type BlockBodyInput = Readonly<{
	block: BlockView;
	snapshot: RowSource;
	rowWindow: RowWindow | null;
	rowHeight: number;
	cellWidth: number;
	cursor: CursorPlacement | null;
	decoder: TextDecoder;
	host: HostCapabilities | null;
	textSource: BlockTextSource;
}>;

export function populateBlock(section: HTMLElement, input: BlockBodyInput): void {
	const { block, snapshot, rowWindow, rowHeight, decoder, host, textSource } = input;
	const fragment = document.createDocumentFragment();
	fragment.append(renderBlockHeader(block, defaultStrings));
	if (host) {
		fragment.append(renderBlockActions(block, host, defaultStrings, textSource));
	}
	const blockFirstRow = block.firstRow;
	const firstRow = rowWindow ? rowWindow.firstRow : 0;
	const lastRow = rowWindow ? rowWindow.lastRow : block.rowCount - 1;
	if (rowWindow && firstRow > 0) {
		fragment.append(spacerOf(firstRow * rowHeight));
	}
	for (let rowOffset = firstRow; rowOffset <= lastRow; rowOffset += 1) {
		const snapshotRow = blockFirstRow + rowOffset;
		const rowNode = buildRowNode(snapshot, snapshotRow, rowOffset, decoder);
		if (input.cursor && input.cursor.row === snapshotRow) {
			rowNode.append(createCursorElement(input.cursor.column, input.cellWidth));
		}
		fragment.append(rowNode);
	}
	if (rowWindow) {
		const trailingRows = block.rowCount - 1 - lastRow;
		if (trailingRows > 0) {
			fragment.append(spacerOf(trailingRows * rowHeight));
		}
	}
	section.replaceChildren(fragment);
}

function spacerOf(height: number): HTMLElement {
	const spacer = document.createElement("div");
	spacer.className = CLASS_SPACER;
	spacer.dataset.terminalRowSpacer = "true";
	spacer.style.height = `${height}px`;
	return spacer;
}
