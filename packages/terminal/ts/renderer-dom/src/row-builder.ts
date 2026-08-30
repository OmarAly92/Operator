import { styleCodeToCssVar } from "./style-code.js";

export const CLASS_ROW = "terminal-row";
export const CLASS_RUN = "terminal-run";

export type RowSource = Readonly<{
	content: Uint8Array;
	rows: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
}>;

export function buildRowNode(
	source: RowSource,
	snapshotRowIndex: number,
	label: number,
	decoder: TextDecoder,
): HTMLElement {
	const { content, rows, runRanges, stylePairs } = source;
	const rowsBase = snapshotRowIndex * 2;
	const rowContentStart = rows[rowsBase] ?? 0;
	const rowContentEnd = rows[rowsBase + 1] ?? rowContentStart;
	const rowLength = rowContentEnd - rowContentStart;
	const pairStart = runRanges[rowsBase] ?? 0;
	const pairEnd = runRanges[rowsBase + 1] ?? pairStart;
	const rowNode = document.createElement("div");
	rowNode.dataset.terminalRow = String(label);
	rowNode.className = CLASS_ROW;
	let rowCursor = 0;
	for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
		const elementIndex = pairIndex * 2;
		const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
		const styleCode = stylePairs[elementIndex + 1] ?? 255;
		const slice = content.subarray(rowContentStart + rowCursor, rowContentStart + pairRunEnd);
		const run = document.createElement("span");
		run.dataset.terminalRun = String(pairIndex);
		run.className = CLASS_RUN;
		run.style.color = styleCodeToCssVar(styleCode);
		run.textContent = decoder.decode(slice);
		rowNode.append(run);
		rowCursor = pairRunEnd;
	}
	if (rowCursor < rowLength) {
		const tail = content.subarray(rowContentStart + rowCursor, rowContentStart + rowLength);
		rowNode.append(document.createTextNode(decoder.decode(tail)));
	}
	return rowNode;
}
