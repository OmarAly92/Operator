import { CELL_SPAN_WORDS } from "@operator/terminal-core";

export type Cluster = Readonly<{ text: string; start: number; end: number }>;

function utf8Length(codePoint: number): number {
	if (codePoint < 0x80) return 1;
	if (codePoint < 0x800) return 2;
	if (codePoint < 0x10000) return 3;
	return 4;
}

export function rowClusters(text: string, spans: ArrayLike<number>): Cluster[] {
	const out: Cluster[] = [];
	const spanCount = Math.floor(spans.length / CELL_SPAN_WORDS);
	let spanIndex = 0;
	let byte = 0;
	let cell = 0;
	let pending: { text: string; end: number; width: number } | null = null;
	for (const character of text) {
		const length = utf8Length(character.codePointAt(0) ?? 0);
		if (pending) {
			pending.text += character;
			byte += length;
			if (byte >= pending.end) {
				out.push({ text: pending.text, start: cell, end: cell + Math.max(pending.width, 1) });
				cell += pending.width;
				pending = null;
			}
			continue;
		}
		if (spanIndex < spanCount && spans[spanIndex * CELL_SPAN_WORDS] === byte) {
			const end = spans[spanIndex * CELL_SPAN_WORDS + 1]!;
			const width = spans[spanIndex * CELL_SPAN_WORDS + 2]!;
			spanIndex += 1;
			byte += length;
			if (byte >= end) {
				out.push({ text: character, start: cell, end: cell + Math.max(width, 1) });
				cell += width;
			} else {
				pending = { text: character, end, width };
			}
			continue;
		}
		out.push({ text: character, start: cell, end: cell + 1 });
		cell += 1;
		byte += length;
	}
	if (pending) out.push({ text: pending.text, start: cell, end: cell + Math.max(pending.width, 1) });
	return out;
}

export function cellString(text: string, spans: ArrayLike<number>): string {
	let out = "";
	for (const cluster of rowClusters(text, spans)) {
		const width = cluster.end - cluster.start;
		out += width === 1 && cluster.text.length === 1 ? cluster.text : "\u0000".repeat(width);
	}
	return out;
}

export function cellCount(text: string, spans: ArrayLike<number>): number {
	const clusters = rowClusters(text, spans);
	return clusters.length === 0 ? 0 : clusters[clusters.length - 1]!.end;
}

export type Coordinate = Readonly<{ cell: number; byte: number; offset: number }>;

function utf8Bytes(text: string): number {
	let total = 0;
	for (const character of text) total += utf8Length(character.codePointAt(0) ?? 0);
	return total;
}

export function rowCoordinates(text: string, spans: ArrayLike<number>): Coordinate[] {
	const out: Coordinate[] = [];
	let byte = 0;
	let offset = 0;
	let cell = 0;
	for (const cluster of rowClusters(text, spans)) {
		out.push({ cell: cluster.start, byte, offset });
		byte += utf8Bytes(cluster.text);
		offset += cluster.text.length;
		cell = cluster.end;
	}
	out.push({ cell, byte, offset });
	return out;
}

function coordinateAt(coords: readonly Coordinate[], key: "byte" | "offset", value: number): Coordinate {
	for (let index = 0; index + 1 < coords.length; index += 1) {
		if (value < coords[index + 1]![key]) return coords[index]!;
	}
	return coords[coords.length - 1]!;
}

export function cellAtOffset(text: string, spans: ArrayLike<number>, offset: number): number {
	return coordinateAt(rowCoordinates(text, spans), "offset", offset).cell;
}

export function cellAtByte(text: string, spans: ArrayLike<number>, byte: number): number {
	return coordinateAt(rowCoordinates(text, spans), "byte", byte).cell;
}

export function offsetAtByte(text: string, spans: ArrayLike<number>, byte: number): number {
	return coordinateAt(rowCoordinates(text, spans), "byte", byte).offset;
}

export function cellSlice(text: string, spans: ArrayLike<number>, fromCell: number, toCell: number): string {
	let out = "";
	for (const cluster of rowClusters(text, spans)) {
		if (cluster.start < fromCell) continue;
		if (cluster.start >= toCell) break;
		out += cluster.text;
	}
	return out;
}
