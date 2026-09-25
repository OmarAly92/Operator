export const COMPACT_REDRAW_LOOKBACK = 256;

export const COMPACT_MIN_REDRAW_LINES = 3;

const SPINNER_LINE = /^\s*[⠀-⣿·✢✳✶✻✽◐-◓]\s+\S.*(?:…|\.\.\.)/u;

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
		let length = 0;
		let visible = 0;
		while (at + length < lines.length && start + length < kept.length && lines[at + length] === kept[start + length]) {
			if (lines[at + length] !== "") visible += 1;
			length += 1;
		}
		if (visible >= COMPACT_MIN_REDRAW_LINES && length > best) best = length;
	}
	return best;
}

export function capLines(lines: readonly string[], maxLines: number): string[] {
	if (!Number.isInteger(maxLines) || maxLines < 3) {
		throw new RangeError(`maxLines must be an integer of at least 3, got ${maxLines}`);
	}
	if (lines.length <= maxLines) return [...lines];
	const head = Math.ceil((maxLines - 1) / 2);
	const tail = maxLines - 1 - head;
	const omitted = lines.length - head - tail;
	return [...lines.slice(0, head), `… ${omitted} lines omitted …`, ...lines.slice(lines.length - tail)];
}
