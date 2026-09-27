import { cap_lines_text, compact_lines_text, is_spinner_line } from "../wasm/vt_core.js";

export const COMPACT_REDRAW_LOOKBACK = 256;

export const COMPACT_MIN_REDRAW_LINES = 3;

export function isSpinnerLine(line: string): boolean {
	return is_spinner_line(line);
}

export function compactLines(lines: readonly string[]): string[] {
	const text = compact_lines_text(lines.join("\n"));
	return text === "" ? [] : text.split("\n");
}

export function capLines(lines: readonly string[], maxLines: number): string[] {
	if (Number.isNaN(maxLines)) throw new RangeError("maxLines must be a number, got NaN");
	const cap = Math.floor(maxLines);
	if (cap <= 0) return [];
	if (lines.length <= cap) return [...lines];
	return cap_lines_text(lines.join("\n"), cap).split("\n");
}
