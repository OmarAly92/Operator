export const COMPACT_REDRAW_LOOKBACK = 256;

export const COMPACT_MIN_REDRAW_LINES = 3;

const SPINNER_LINE = /^\s*[⠀-⣿·✢✳✶✻✽◐-◓]\s+\S[^…]*?(?:…|\.\.\.)(?:\s+\([^()]*\))?$/u;

export function isSpinnerLine(line: string): boolean {
	return SPINNER_LINE.test(line);
}

export function compactLines(lines: readonly string[]): string[] {
	const normalized: string[] = [];
	for (const raw of lines) {
		const line = raw.trimEnd();
		if (isSpinnerLine(line)) continue;
		if (line === "" && (normalized.length === 0 || normalized.at(-1) === "")) continue;
		if (line !== "" && normalized.at(-1) === line) continue;
		normalized.push(line);
	}
	const kept: string[] = [];
	const seen = new Map<string, number[]>();
	let index = 0;
	while (index < normalized.length) {
		const line = normalized[index]!;
		const repeated = line === "" ? 0 : repeatedRun(normalized, index, kept, seen.get(line));
		if (repeated > 0) {
			index += repeated;
			continue;
		}
		if (line !== "") {
			const positions = seen.get(line);
			if (positions) positions.push(kept.length);
			else seen.set(line, [kept.length]);
		}
		kept.push(line);
		index += 1;
	}
	while (kept.at(-1) === "") kept.pop();
	return kept;
}

function repeatedRun(lines: readonly string[], at: number, kept: readonly string[], positions: readonly number[] | undefined): number {
	if (!positions) return 0;
	const floor = kept.length - COMPACT_REDRAW_LOOKBACK;
	let best = 0;
	for (let slot = positions.length - 1; slot >= 0; slot -= 1) {
		const start = positions[slot]!;
		if (start < floor) break;
		const length = kept.length - start;
		if (length <= best || at + length > lines.length) continue;
		let visible = 0;
		let offset = 0;
		while (offset < length && lines[at + offset] === kept[start + offset]) {
			if (lines[at + offset] !== "") visible += 1;
			offset += 1;
		}
		if (offset === length && visible >= COMPACT_MIN_REDRAW_LINES) best = length;
	}
	return best;
}

export function capLines(lines: readonly string[], maxLines: number): string[] {
	if (Number.isNaN(maxLines)) throw new RangeError("maxLines must be a number, got NaN");
	const cap = Math.floor(maxLines);
	if (cap <= 0) return [];
	if (lines.length <= cap) return [...lines];
	const head = Math.ceil((cap - 1) / 2);
	const tail = cap - 1 - head;
	const omitted = lines.length - head - tail;
	return [...lines.slice(0, head), `… ${omitted} lines omitted …`, ...lines.slice(lines.length - tail)];
}
