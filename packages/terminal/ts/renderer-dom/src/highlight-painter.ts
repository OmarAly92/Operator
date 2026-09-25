import { rowPaint, type FillLayer, type Highlight } from "./highlights.js";
import { fillGradient, runFill } from "./selection-fill.js";
import { compareBoundary, type BlockOrder } from "./selection-model.js";
import { measureRow, type RowRef } from "./selection-view.js";

export const CLASS_ROW_MATCH = "terminal-find-row-match";
export const CLASS_ROW_ACTIVE = "terminal-find-row-active";
export const ATTR_ROW_MATCH = "data-terminal-find-row-match";
export const ATTR_ROW_ACTIVE = "data-terminal-find-row-active";
export const BUCKET_ROWS = 64;

type ElementPaint = Readonly<{ image: string; findMatch: boolean; findFill: boolean; findCurrent: boolean }>;

const BLANK: ElementPaint = { image: "", findMatch: false, findFill: false, findCurrent: false };

function rowImage(layers: readonly FillLayer[]): string {
	return layers.map((layer) => fillGradient(layer.span, layer.colour)).join(", ");
}

function runImage(layers: readonly FillLayer[], run: HTMLElement, rowLeft: number): string {
	const box = run.getBoundingClientRect();
	const parts: string[] = [];
	for (const layer of layers) {
		const span = runFill(box, rowLeft, layer.span);
		if (span) parts.push(fillGradient(span, layer.colour));
	}
	return parts.join(", ");
}

function apply(element: HTMLElement, before: ElementPaint, after: ElementPaint): void {
	if (before.image !== after.image) element.style.backgroundImage = after.image;
	if (before.findFill !== after.findFill) element.classList.toggle(CLASS_ROW_MATCH, after.findFill);
	if (before.findMatch !== after.findMatch) element.toggleAttribute(ATTR_ROW_MATCH, after.findMatch);
	if (before.findCurrent !== after.findCurrent) {
		element.classList.toggle(CLASS_ROW_ACTIVE, after.findCurrent);
		element.toggleAttribute(ATTR_ROW_ACTIVE, after.findCurrent);
	}
}

function touches(highlight: Highlight, ref: RowRef, order: BlockOrder): boolean {
	const here = { blockId: ref.blockId, row: ref.row, cell: 0 };
	const { start, end } = highlight.range;
	const startsHere = start.blockId === ref.blockId && start.row === ref.row;
	const endsHere = end.blockId === ref.blockId && end.row === ref.row;
	if (!startsHere && compareBoundary(here, start, order) < 0) return false;
	if (!endsHere && compareBoundary(here, end, order) > 0) return false;
	return true;
}

export class HighlightIndex {
	private readonly buckets = new Map<string, Highlight[]>();
	private readonly wide: Highlight[] = [];

	constructor(highlights: readonly Highlight[], private readonly order: BlockOrder) {
		for (const highlight of highlights) {
			const { start, end } = highlight.range;
			if (start.blockId !== end.blockId || end.row - start.row > BUCKET_ROWS) {
				this.wide.push(highlight);
				continue;
			}
			for (let row = start.row; row <= end.row; row += 1) {
				const key = `${start.blockId}:${row}`;
				const bucket = this.buckets.get(key);
				if (bucket) bucket.push(highlight);
				else this.buckets.set(key, [highlight]);
			}
		}
	}

	at(ref: RowRef): Highlight[] {
		const near = this.buckets.get(`${ref.blockId}:${ref.row}`) ?? [];
		const far = this.wide.filter((highlight) => touches(highlight, ref, this.order));
		return far.length === 0 ? near : [...near, ...far];
	}
}

type RowCache = Readonly<{ key: string; entries: readonly (readonly [HTMLElement, ElementPaint])[] }>;

type RowFrame = Readonly<{ left: number; width: number; key: string }>;

function highlightKey(highlights: readonly Highlight[]): string {
	return highlights
		.map(({ kind, colour, rank, range: { start, end } }) => `${kind}:${colour}:${rank}:${start.blockId}:${start.row}:${start.cell}:${end.blockId}:${end.row}:${end.cell}`)
		.join("|");
}

function rowEntries(element: HTMLElement, paint: ReturnType<typeof rowPaint>, rowLeft: number): (readonly [HTMLElement, ElementPaint])[] {
	if (paint.layers.length === 0 && !paint.findMatch && !paint.findCurrent) return [];
	const entries: (readonly [HTMLElement, ElementPaint])[] = [
		[element, { image: rowImage(paint.layers), findMatch: paint.findMatch, findFill: paint.findFill, findCurrent: paint.findCurrent }],
	];
	if (paint.layers.length === 0) return entries;
	for (const run of element.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
		if (run.style.backgroundColor === "") continue;
		const image = runImage(paint.layers, run, rowLeft);
		if (image !== "") entries.push([run, { ...BLANK, image }]);
	}
	return entries;
}

export class HighlightPainter {
	private painted = new Map<HTMLElement, ElementPaint>();
	private rows = new Map<HTMLElement, RowCache>();

	idle(): boolean {
		return this.painted.size === 0;
	}

	paint(rows: readonly RowRef[], highlights: readonly Highlight[], order: BlockOrder, cellWidth: number): void {
		const next = new Map<HTMLElement, ElementPaint>();
		const cached = new Map<HTMLElement, RowCache>();
		if (highlights.length > 0) {
			const index = new HighlightIndex(highlights, order);
			let frame: RowFrame | null = null;
			for (const ref of rows) {
				const here = index.at(ref);
				if (here.length === 0) continue;
				if (frame === null) {
					const { box } = measureRow(ref);
					frame = { left: box.left, width: box.width, key: `${box.left}:${box.width}:${cellWidth}` };
				}
				const key = `${frame.key}|${highlightKey(here)}`;
				const previous = this.rows.get(ref.element);
				const entry = previous && previous.key === key ? previous : null;
				const row = entry ?? this.measure(ref, here, order, cellWidth, key, frame);
				cached.set(ref.element, row);
				for (const [element, paint] of row.entries) next.set(element, paint);
			}
		}
		for (const [element, before] of this.painted) {
			if (!next.has(element)) apply(element, before, BLANK);
		}
		for (const [element, after] of next) apply(element, this.painted.get(element) ?? BLANK, after);
		this.painted = next;
		this.rows = cached;
	}

	reset(): void {
		this.painted = new Map();
		this.rows = new Map();
	}

	private measure(ref: RowRef, here: readonly Highlight[], order: BlockOrder, cellWidth: number, key: string, frame: RowFrame): RowCache {
		const box = { blockId: ref.blockId, row: ref.row, firstRow: ref.firstRow, rowCount: ref.rowCount, left: frame.left, top: 0, bottom: 0, width: frame.width };
		return { key, entries: rowEntries(ref.element, rowPaint(here, box, order, cellWidth), frame.left) };
	}
}
