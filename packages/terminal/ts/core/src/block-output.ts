import { capLines, compactLines } from "./compact-output.js";
import { snapshotLogicalLines } from "./logical-lines.js";
import type { BlockView, TerminalSnapshot } from "./types.js";

export type BlockOutputOptions = Readonly<{ compact?: boolean; maxLines?: number }>;

export function blockOutputText(
	snapshot: TerminalSnapshot,
	block: BlockView,
	decoder: TextDecoder,
	options: BlockOutputOptions = {},
): string {
	const range = { start: block.firstRow, end: block.firstRow + block.rowCount };
	let lines = snapshotLogicalLines(snapshot, range, decoder).map((line) => line.text);
	if (options.compact) {
		lines = compactLines(lines);
	} else {
		while (lines.length > 0 && lines.at(-1)!.trim() === "") lines.pop();
	}
	if (options.maxLines !== undefined) lines = capLines(lines, options.maxLines);
	return lines.join("\n");
}
