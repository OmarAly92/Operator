# Model-Owned Terminal Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the browser-owned transcript selection with a grid-coordinate selection the renderer owns, painted from geometry and copied from the snapshot, so repaints cannot destroy it.

**Architecture:** Pure modules in `renderer-dom` hold the model (`selection-model.ts`), map pointer to grid point and range to fill spans (`selection-geometry.ts`), and extract text (`selection-text.ts`, `cell-width.ts`, `words.ts`). `DomBlockRenderer` owns the state and exposes `pointAt`/`selectionBegin`/`selectionUpdate`/`selectionClear`/`hasSelection`/`selectedText`. The React surface owns gestures (`selection-gesture.ts` pure state, wired in `TerminalSurface.tsx`) and the copy chord.

**Tech Stack:** TypeScript, vitest + jsdom, React Testing Library, Playwright (bench), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-10-model-owned-terminal-selection-design.md`

## Global Constraints

- No comments in new code (user's global rule). Test names carry the Warp citations.
- `packages/terminal` stays product-independent: no Operator import or concept.
- `styles.ts` and `styles.css` must stay byte-identical (`styles-parity.test.ts`).
- Every task: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/<pkg> && npx vitest run <file>` green before commit. Use absolute paths in every command.
- Commit straight to master, message ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Ship recipe after the last task: `npm run build:ts` in `packages/terminal`, all three package suites, `npx tsc --noEmit -p .` in `frontend`, changelog entry, TERMINAL.md entry.

---

### Task 1: Cell widths

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/cell-width.ts`
- Test: `packages/terminal/ts/renderer-dom/src/cell-width.test.ts`

**Interfaces:**
- Produces: `cellWidthOf(codePoint: number): 0 | 1 | 2`, `cellSlice(text: string, fromCell: number, toCell: number): string` (characters whose first cell lies in `[fromCell, toCell)`), `cellCount(text: string): number`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { cellCount, cellSlice, cellWidthOf } from "./cell-width";

describe("cellWidthOf", () => {
	it("gives ascii one cell", () => {
		expect(cellWidthOf("a".codePointAt(0)!)).toBe(1);
	});
	it("gives CJK and fullwidth two cells", () => {
		expect(cellWidthOf("漢".codePointAt(0)!)).toBe(2);
		expect(cellWidthOf("Ａ".codePointAt(0)!)).toBe(2);
	});
	it("gives combining marks and joiners no cell", () => {
		expect(cellWidthOf(0x0301)).toBe(0);
		expect(cellWidthOf(0x200d)).toBe(0);
	});
	it("gives emoji presentation two cells", () => {
		expect(cellWidthOf("😀".codePointAt(0)!)).toBe(2);
	});
});

describe("cellSlice", () => {
	it("cuts ascii by column", () => {
		expect(cellSlice("hello world", 6, 11)).toBe("world");
	});
	it("keeps a wide character whose first cell is inside the cut", () => {
		expect(cellSlice("a漢b", 1, 3)).toBe("漢");
		expect(cellSlice("a漢b", 2, 4)).toBe("b");
	});
	it("keeps combining marks with their base", () => {
		expect(cellSlice("éx", 0, 1)).toBe("é");
	});
	it("clamps past the end", () => {
		expect(cellSlice("abc", 1, 99)).toBe("bc");
		expect(cellCount("a漢b")).toBe(4);
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/cell-width.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement**

```ts
const WIDE_RANGES: readonly (readonly [number, number])[] = [
	[0x1100, 0x115f],
	[0x2e80, 0x303e],
	[0x3041, 0x33ff],
	[0x3400, 0x4dbf],
	[0x4e00, 0x9fff],
	[0xa000, 0xa4cf],
	[0xac00, 0xd7a3],
	[0xf900, 0xfaff],
	[0xfe30, 0xfe4f],
	[0xff00, 0xff60],
	[0xffe0, 0xffe6],
	[0x1f300, 0x1f64f],
	[0x1f900, 0x1f9ff],
	[0x20000, 0x2fffd],
	[0x30000, 0x3fffd],
];

const ZERO_RANGES: readonly (readonly [number, number])[] = [
	[0x0300, 0x036f],
	[0x1ab0, 0x1aff],
	[0x1dc0, 0x1dff],
	[0x200b, 0x200f],
	[0x20d0, 0x20ff],
	[0xfe00, 0xfe0f],
	[0xfe20, 0xfe2f],
	[0xe0100, 0xe01ef],
];

function inRanges(codePoint: number, ranges: readonly (readonly [number, number])[]): boolean {
	for (const [start, end] of ranges) {
		if (codePoint < start) return false;
		if (codePoint <= end) return true;
	}
	return false;
}

export function cellWidthOf(codePoint: number): 0 | 1 | 2 {
	if (codePoint === 0) return 0;
	if (inRanges(codePoint, ZERO_RANGES)) return 0;
	if (inRanges(codePoint, WIDE_RANGES)) return 2;
	return 1;
}

export function cellCount(text: string): number {
	let cells = 0;
	for (const character of text) cells += cellWidthOf(character.codePointAt(0) ?? 0);
	return cells;
}

export function cellSlice(text: string, fromCell: number, toCell: number): string {
	let cell = 0;
	let out = "";
	for (const character of text) {
		const width = cellWidthOf(character.codePointAt(0) ?? 0);
		const inside = width === 0 ? out !== "" || (cell >= fromCell && cell < toCell) : cell >= fromCell && cell < toCell;
		if (inside) out += character;
		cell += width;
		if (cell >= toCell && width > 0) break;
	}
	return out;
}
```

- [ ] **Step 4: Run to see it pass**

Run: same command. Expected: PASS (adjust the combining-mark branch if `"éx"` fails: a zero-width character is kept when the previous character was kept).

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom/src/cell-width.ts packages/terminal/ts/renderer-dom/src/cell-width.test.ts
git commit -m "feat(terminal): cell width table for column cuts"
```

---

### Task 2: Word boundaries

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/words.ts`
- Test: `packages/terminal/ts/renderer-dom/src/words.test.ts`

**Interfaces:**
- Produces: `wordCellRange(text: string, cell: number): { start: number; end: number }` in cells, end exclusive. Boundaries are Warp's `is_default_word_boundary` (`crates/warpui_core/src/text/words.rs`) minus the allowlist `-.~/\` (`warp_core/src/semantic_selection/mod.rs:17`). A boundary character under the pointer selects just itself.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { isWordBoundary, wordCellRange } from "./words";

describe("isWordBoundary", () => {
	it("treats whitespace and Warp's punctuation set as boundaries", () => {
		for (const c of [" ", "\t", "(", ")", "[", "]", "{", "}", "'", '"', ",", ";", ":", "<", ">", "?", "!", "=", "+", "*", "&", "|", "^", "%", "$", "#", "@", "`", "«", "»"]) {
			expect(isWordBoundary(c), c).toBe(true);
		}
	});
	it("keeps Warp's allowlist and underscore inside a word", () => {
		for (const c of ["-", ".", "~", "/", "\\", "_", "a", "9", "漢"]) {
			expect(isWordBoundary(c), c).toBe(false);
		}
	});
});

describe("wordCellRange", () => {
	it("selects a path as one word", () => {
		const text = "see src/row-builder.ts now";
		expect(wordCellRange(text, 8)).toEqual({ start: 4, end: 22 });
	});
	it("selects only the boundary character under the pointer", () => {
		expect(wordCellRange("a (b)", 2)).toEqual({ start: 2, end: 3 });
	});
	it("measures in cells so a wide character counts twice", () => {
		expect(wordCellRange("漢字 x", 1)).toEqual({ start: 0, end: 4 });
	});
	it("clamps a pointer past the text to the last word", () => {
		expect(wordCellRange("ab", 10)).toEqual({ start: 0, end: 2 });
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/words.test.ts` (from renderer-dom). Expected: FAIL.

- [ ] **Step 3: Implement**

```ts
import { cellWidthOf } from "./cell-width.js";

const BOUNDARY_CHARS = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?«»";
const ALLOWLIST = "-.~/\\";

export function isWordBoundary(character: string): boolean {
	if (/\s/u.test(character)) return true;
	if (ALLOWLIST.includes(character)) return false;
	return BOUNDARY_CHARS.includes(character);
}

type Cell = Readonly<{ character: string; start: number; end: number }>;

function cells(text: string): Cell[] {
	const out: Cell[] = [];
	let cell = 0;
	for (const character of text) {
		const width = cellWidthOf(character.codePointAt(0) ?? 0);
		if (width === 0 && out.length > 0) continue;
		out.push({ character, start: cell, end: cell + Math.max(width, 1) });
		cell += width;
	}
	return out;
}

export function wordCellRange(text: string, cell: number): { start: number; end: number } {
	const list = cells(text);
	if (list.length === 0) return { start: 0, end: 0 };
	let index = list.findIndex((c) => cell >= c.start && cell < c.end);
	if (index < 0) index = list.length - 1;
	const hit = list[index]!;
	if (isWordBoundary(hit.character)) return { start: hit.start, end: hit.end };
	let first = index;
	while (first > 0 && !isWordBoundary(list[first - 1]!.character)) first -= 1;
	let last = index;
	while (last < list.length - 1 && !isWordBoundary(list[last + 1]!.character)) last += 1;
	return { start: list[first]!.start, end: list[last]!.end };
}
```

- [ ] **Step 4: Run to see it pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom/src/words.ts packages/terminal/ts/renderer-dom/src/words.test.ts
git commit -m "feat(terminal): Warp's word boundaries for double-click selection"
```

---

### Task 3: Selection model

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/selection-model.ts`
- Test: `packages/terminal/ts/renderer-dom/src/selection-model.test.ts`

**Interfaces:**
- Produces:

```ts
export type SelectionKind = "simple" | "word" | "line";
export type SelectionSide = "left" | "right";
export type SelectionPoint = Readonly<{ blockId: string; row: number; column: number; side: SelectionSide }>;
export type SelectionState = Readonly<{ head: SelectionPoint; tail: SelectionPoint; kind: SelectionKind }>;
export type Boundary = Readonly<{ blockId: string; row: number; cell: number }>;
export type SelectionRange = Readonly<{ start: Boundary; end: Boundary }>;
export const ROW_END = Number.POSITIVE_INFINITY;
export type RowText = (blockId: string, row: number) => string;
export type BlockOrder = (blockId: string) => number;
export function compareBoundary(a: Boundary, b: Boundary, order: BlockOrder): number;
export function resolveRange(state: SelectionState, order: BlockOrder, rowText: RowText): SelectionRange | null;
```

A boundary is a position between cells. A point's boundary is `column + (side === "right" ? 1 : 0)`; this is Warp's `range_simple` correction (`crates/warp_terminal/src/model/selection.rs:571`). `resolveRange` returns `null` when start equals end. Word kind expands each end with `wordCellRange`; line kind sets `{cell: 0}` and `{cell: ROW_END}`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { ROW_END, resolveRange, type SelectionPoint } from "./selection-model";

const order = (id: string) => Number(id);
const rows: Record<string, string[]> = { "0": ["first row here", "second row"], "1": ["third block row"] };
const rowText = (id: string, row: number) => rows[id]?.[row] ?? "";
const at = (blockId: string, row: number, column: number, side: "left" | "right" = "left"): SelectionPoint => ({ blockId, row, column, side });

describe("resolveRange", () => {
	it("orders head and tail whichever way the drag went", () => {
		const range = resolveRange({ head: at("1", 0, 3), tail: at("0", 0, 2), kind: "simple" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 2 });
		expect(range.end).toEqual({ blockId: "1", row: 0, cell: 3 });
	});
	it("puts a right-side point after its cell, Warp's range_simple correction", () => {
		const range = resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 5, "right"), kind: "simple" }, order, rowText)!;
		expect(range.start.cell).toBe(3);
		expect(range.end.cell).toBe(6);
	});
	it("is empty when both ends meet", () => {
		expect(resolveRange({ head: at("0", 0, 2, "right"), tail: at("0", 0, 3, "left"), kind: "simple" }, order, rowText)).toBeNull();
	});
	it("expands a word selection to word edges on both ends", () => {
		const range = resolveRange({ head: at("0", 0, 1), tail: at("0", 1, 8), kind: "word" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: 10 });
	});
	it("expands a line selection to the whole rows", () => {
		const range = resolveRange({ head: at("0", 1, 4), tail: at("0", 0, 4), kind: "line" }, order, rowText)!;
		expect(range.start).toEqual({ blockId: "0", row: 0, cell: 0 });
		expect(range.end).toEqual({ blockId: "0", row: 1, cell: ROW_END });
	});
});
```

- [ ] **Step 2: Run to see it fail.** `npx vitest run src/selection-model.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**

```ts
import { wordCellRange } from "./words.js";

export type SelectionKind = "simple" | "word" | "line";
export type SelectionSide = "left" | "right";
export type SelectionPoint = Readonly<{ blockId: string; row: number; column: number; side: SelectionSide }>;
export type SelectionState = Readonly<{ head: SelectionPoint; tail: SelectionPoint; kind: SelectionKind }>;
export type Boundary = Readonly<{ blockId: string; row: number; cell: number }>;
export type SelectionRange = Readonly<{ start: Boundary; end: Boundary }>;
export type RowText = (blockId: string, row: number) => string;
export type BlockOrder = (blockId: string) => number;

export const ROW_END = Number.POSITIVE_INFINITY;

export function compareBoundary(a: Boundary, b: Boundary, order: BlockOrder): number {
	const blocks = order(a.blockId) - order(b.blockId);
	if (blocks !== 0) return blocks;
	if (a.row !== b.row) return a.row - b.row;
	return a.cell - b.cell;
}

function boundaryOf(point: SelectionPoint): Boundary {
	return { blockId: point.blockId, row: point.row, cell: point.column + (point.side === "right" ? 1 : 0) };
}

function expand(point: SelectionPoint, kind: SelectionKind, rowText: RowText): [Boundary, Boundary] {
	if (kind === "line") {
		return [
			{ blockId: point.blockId, row: point.row, cell: 0 },
			{ blockId: point.blockId, row: point.row, cell: ROW_END },
		];
	}
	if (kind === "word") {
		const word = wordCellRange(rowText(point.blockId, point.row), point.column);
		return [
			{ blockId: point.blockId, row: point.row, cell: word.start },
			{ blockId: point.blockId, row: point.row, cell: word.end },
		];
	}
	const boundary = boundaryOf(point);
	return [boundary, boundary];
}

export function resolveRange(state: SelectionState, order: BlockOrder, rowText: RowText): SelectionRange | null {
	const [headStart, headEnd] = expand(state.head, state.kind, rowText);
	const [tailStart, tailEnd] = expand(state.tail, state.kind, rowText);
	const start = compareBoundary(headStart, tailStart, order) <= 0 ? headStart : tailStart;
	const end = compareBoundary(headEnd, tailEnd, order) >= 0 ? headEnd : tailEnd;
	if (compareBoundary(start, end, order) >= 0) return null;
	return { start, end };
}
```

- [ ] **Step 4: Run to see it pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom/src/selection-model.ts packages/terminal/ts/renderer-dom/src/selection-model.test.ts
git commit -m "feat(terminal): selection model in grid coordinates, like Warp's BlockListSelection"
```

---

### Task 4: Geometry, pointer to point and range to fill spans

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/selection-geometry.ts`
- Test: `packages/terminal/ts/renderer-dom/src/selection-geometry.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-fill.ts` (remove `selectionRowFills`, `paintedSpan`, `positionOf`, `RowPosition`, `rowFill`; keep `FillSpan`, `runFill`, `fillGradient`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-fill.test.ts` (delete the `rowFill` describe block)

**Interfaces:**
- Produces:

```ts
export type RowBox = Readonly<{ blockId: string; row: number; rowCount: number; left: number; top: number; bottom: number; width: number }>;
export function pointAtFromRows(rows: readonly RowBox[], x: number, y: number, cellWidth: number, cellHeight: number): SelectionPoint | null;
export function rowFillSpan(range: SelectionRange, box: RowBox, order: BlockOrder, cellWidth: number): FillSpan | null;
```

`pointAtFromRows` mirrors Warp's `screen_coord_to_blocklist_point` (column floored, `block_list_viewport.rs:1716`) and `get_mouse_side` (`runtime.rs:121`). `rowFillSpan` is `calculate_background_bounds` (`grid_renderer.rs:2500`).

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { pointAtFromRows, rowFillSpan, type RowBox } from "./selection-geometry";
import { ROW_END } from "./selection-model";

const cw = 8;
const ch = 16;
const box = (blockId: string, row: number, top: number, rowCount = 4): RowBox => ({ blockId, row, rowCount, left: 100, top, bottom: top + ch, width: 400 });
const rows = [box("a", 0, 0), box("a", 1, 16), box("b", 0, 60), box("b", 1, 76)];
const order = (id: string) => (id === "a" ? 0 : 1);

describe("pointAtFromRows", () => {
	it("floors the column and picks the side from the half cell", () => {
		expect(pointAtFromRows(rows, 100 + 8 * 3 + 2, 20, cw, ch)).toEqual({ blockId: "a", row: 1, column: 3, side: "left" });
		expect(pointAtFromRows(rows, 100 + 8 * 3 + 6, 20, cw, ch)).toEqual({ blockId: "a", row: 1, column: 3, side: "right" });
	});
	it("clamps left of the row to column zero", () => {
		expect(pointAtFromRows(rows, 10, 4, cw, ch)!.column).toBe(0);
	});
	it("extrapolates over a spacer from the nearest rendered row", () => {
		expect(pointAtFromRows(rows, 100, 45, cw, ch)).toEqual({ blockId: "a", row: 2, column: 0, side: "left" });
	});
	it("clamps the extrapolated row to the block", () => {
		expect(pointAtFromRows(rows, 100, 1000, cw, ch)!.row).toBe(3);
	});
	it("gives nothing with no rows", () => {
		expect(pointAtFromRows([], 1, 1, cw, ch)).toBeNull();
	});
});

describe("rowFillSpan", () => {
	const range = { start: { blockId: "a", row: 0, cell: 3 }, end: { blockId: "b", row: 1, cell: 5 } };
	it("runs the first row from its cell to the edge", () => {
		expect(rowFillSpan(range, rows[0]!, order, cw)).toEqual({ left: 24, right: 400 });
	});
	it("fills a middle row whole", () => {
		expect(rowFillSpan(range, rows[1]!, order, cw)).toEqual({ left: 0, right: 400 });
		expect(rowFillSpan(range, rows[2]!, order, cw)).toEqual({ left: 0, right: 400 });
	});
	it("runs the last row from the edge to its cell", () => {
		expect(rowFillSpan(range, rows[3]!, order, cw)).toEqual({ left: 0, right: 40 });
	});
	it("leaves rows outside the range alone", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 0 }, end: { blockId: "a", row: 1, cell: 2 } }, rows[0]!, order, cw)).toBeNull();
	});
	it("keeps a single row between its own cells", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 1 }, end: { blockId: "a", row: 1, cell: 3 } }, rows[1]!, order, cw)).toEqual({ left: 8, right: 24 });
	});
	it("paints nothing on a last row the range ends at the start of", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: 0 } }, rows[1]!, order, cw)).toBeNull();
	});
	it("runs a line selection to the edge", () => {
		expect(rowFillSpan({ start: { blockId: "a", row: 1, cell: 0 }, end: { blockId: "a", row: 1, cell: ROW_END } }, rows[1]!, order, cw)).toEqual({ left: 0, right: 400 });
	});
});
```

- [ ] **Step 2: Run to see it fail.** `npx vitest run src/selection-geometry.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**

```ts
import type { FillSpan } from "./selection-fill.js";
import { compareBoundary, type BlockOrder, type SelectionPoint, type SelectionRange } from "./selection-model.js";

export type RowBox = Readonly<{
	blockId: string;
	row: number;
	rowCount: number;
	left: number;
	top: number;
	bottom: number;
	width: number;
}>;

function nearestRow(rows: readonly RowBox[], y: number): RowBox | null {
	let best: RowBox | null = null;
	let bestDistance = Number.POSITIVE_INFINITY;
	for (const row of rows) {
		const distance = y < row.top ? row.top - y : y >= row.bottom ? y - row.bottom : 0;
		if (distance < bestDistance) {
			bestDistance = distance;
			best = row;
			if (distance === 0) break;
		}
	}
	return best;
}

export function pointAtFromRows(
	rows: readonly RowBox[],
	x: number,
	y: number,
	cellWidth: number,
	cellHeight: number,
): SelectionPoint | null {
	const anchor = nearestRow(rows, y);
	if (!anchor || cellWidth <= 0 || cellHeight <= 0) return null;
	const rowDelta = Math.floor((y - anchor.top) / cellHeight);
	const row = Math.min(Math.max(anchor.row + rowDelta, 0), Math.max(anchor.rowCount - 1, 0));
	const offset = Math.max(x - anchor.left, 0);
	const column = Math.floor(offset / cellWidth);
	const side = offset - column * cellWidth > cellWidth / 2 ? "right" : "left";
	return { blockId: anchor.blockId, row, column, side };
}

export function rowFillSpan(
	range: SelectionRange,
	box: RowBox,
	order: BlockOrder,
	cellWidth: number,
): FillSpan | null {
	const here = { blockId: box.blockId, row: box.row, cell: 0 };
	const startsHere = range.start.blockId === box.blockId && range.start.row === box.row;
	const endsHere = range.end.blockId === box.blockId && range.end.row === box.row;
	if (!startsHere && compareBoundary(here, range.start, order) < 0) return null;
	if (!endsHere && compareBoundary(here, range.end, order) > 0) return null;
	const left = startsHere ? Math.min(range.start.cell * cellWidth, box.width) : 0;
	const right = endsHere ? Math.min(range.end.cell * cellWidth, box.width) : box.width;
	if (right - left <= 0.5) return null;
	return { left, right };
}
```

Then in `selection-fill.ts` delete `rowFill`, `positionOf`, `paintedSpan`, `selectionRowFills`, `RowPosition`, `RowFill`, and the `Box` alias if unused; keep `FillSpan`, `runFill`, `fillGradient` (runFill's `Box` parameter type stays). Delete the `rowFill` describe from `selection-fill.test.ts` and its import.

- [ ] **Step 4: Run both files.** `npx vitest run src/selection-geometry.test.ts src/selection-fill.test.ts`. Expected: PASS. `dom-block-renderer.ts` still imports `selectionRowFills`; that breaks typecheck until Task 6, which is why Task 6 follows before any build.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom/src/selection-geometry.ts packages/terminal/ts/renderer-dom/src/selection-geometry.test.ts packages/terminal/ts/renderer-dom/src/selection-fill.ts packages/terminal/ts/renderer-dom/src/selection-fill.test.ts
git commit -m "feat(terminal): pointer-to-cell and fill geometry for the model selection"
```

---

### Task 5: Selected text from the snapshot

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/selection-text.ts`
- Test: `packages/terminal/ts/renderer-dom/src/selection-text.test.ts`

**Interfaces:**
- Consumes: `SelectionRange`, `ROW_END`, `cellSlice`.
- Produces:

```ts
export type TextRows = Readonly<{ rowText(blockId: string, row: number): string; rowCount(blockId: string): number; blockIds: readonly string[] }>;
export function selectedText(range: SelectionRange, rows: TextRows): string;
```

Rules from Warp's `line_to_string` and `selection_to_string` (spec §Text): rows joined by `\n`, blank rows as empty lines, trailing spaces trimmed per row, one `\n` between blocks, the trailing newline trimmed, an end boundary at cell 0 excludes that row.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { ROW_END } from "./selection-model";
import { selectedText, type TextRows } from "./selection-text";

const blocks: Record<string, string[]> = {
	a: ["alpha beta   ", "", "gamma 漢字 delta"],
	b: ["> hi                 "],
};
const rows: TextRows = {
	blockIds: ["a", "b"],
	rowCount: (id) => blocks[id]!.length,
	rowText: (id, row) => blocks[id]![row] ?? "",
};

describe("selectedText", () => {
	it("cuts the first and last rows by cell and joins rows with newlines", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 6 }, end: { blockId: "a", row: 2, cell: 5 } }, rows)).toBe("beta\n\ngamma");
	});
	it("keeps a blank row inside as an empty line and trims trailing spaces", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: ROW_END } }, rows)).toBe("alpha beta\n");
	});
	it("puts one newline between blocks", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 0 }, end: { blockId: "b", row: 0, cell: 4 } }, rows)).toBe("gamma 漢字 delta\n> hi");
	});
	it("excludes a last row the range ends at the start of", () => {
		expect(selectedText({ start: { blockId: "a", row: 0, cell: 0 }, end: { blockId: "a", row: 1, cell: 0 } }, rows)).toBe("alpha beta");
	});
	it("cuts a wide character by cell", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 6 }, end: { blockId: "a", row: 2, cell: 8 } }, rows)).toBe("漢");
	});
});
```

- [ ] **Step 2: Run to see it fail.** `npx vitest run src/selection-text.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**

```ts
import { cellSlice } from "./cell-width.js";
import { ROW_END, type SelectionRange } from "./selection-model.js";

export type TextRows = Readonly<{
	rowText(blockId: string, row: number): string;
	rowCount(blockId: string): number;
	blockIds: readonly string[];
}>;

function cut(text: string, from: number, to: number): string {
	const sliced = to === ROW_END && from === 0 ? text : cellSlice(text, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
	return sliced.replace(/ +$/u, "");
}

export function selectedText(range: SelectionRange, rows: TextRows): string {
	const first = rows.blockIds.indexOf(range.start.blockId);
	const last = rows.blockIds.indexOf(range.end.blockId);
	if (first < 0 || last < 0 || last < first) return "";
	const lines: string[] = [];
	for (let index = first; index <= last; index += 1) {
		const blockId = rows.blockIds[index]!;
		const fromRow = index === first ? range.start.row : 0;
		let toRow = index === last ? range.end.row : rows.rowCount(blockId) - 1;
		if (index === last && range.end.cell === 0 && toRow > fromRow) toRow -= 1;
		for (let row = fromRow; row <= toRow; row += 1) {
			const from = index === first && row === range.start.row ? range.start.cell : 0;
			const to = index === last && row === range.end.row ? range.end.cell : ROW_END;
			lines.push(cut(rows.rowText(blockId, row), from, to));
		}
	}
	return lines.join("\n");
}
```

- [ ] **Step 4: Run to see it pass.** Expected: PASS. If the "excludes a last row" case yields a trailing newline, the `toRow -= 1` guard is the fix, not a trim.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/renderer-dom/src/selection-text.ts packages/terminal/ts/renderer-dom/src/selection-text.test.ts
git commit -m "feat(terminal): copy text from the snapshot the way Warp's selection_to_string does"
```

---

### Task 6: Renderer owns the selection

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/index.ts`
- Delete: `packages/terminal/ts/renderer-dom/src/selection.ts`, `packages/terminal/ts/renderer-dom/src/selection.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.ts`, `styles.css`, `styles-parity.test.ts`
- Test: `packages/terminal/ts/renderer-dom/src/terminal-selection.test.ts` (rewrite)

**Interfaces:**
- Produces on `DomBlockRenderer`:

```ts
pointAt(x: number, y: number): SelectionPoint | null
selectionBegin(point: SelectionPoint, kind: SelectionKind): void
selectionUpdate(point: SelectionPoint): void
selectionClear(): void
hasSelection(): boolean
selectedText(): string | null
onSelectionChange(listener: () => void): () => void
```
- `index.ts` exports `type SelectionPoint, type SelectionKind` from `./selection-model.js` and drops the `selection.js` line.
- Alt screen block id: `export const ALT_BLOCK_ID = "alt"`.

- [ ] **Step 1: Rewrite the failing test**

Replace `terminal-selection.test.ts` with:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type FontConfig, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };
const CELL_W = 8.4;
const CELL_H = 16.8;

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function layoutRows(host: HTMLElement): HTMLElement[] {
	const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
		for (const run of row.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
			run.getBoundingClientRect = () => ({ left: 0, right: 200, width: 200, top: index * CELL_H, bottom: (index + 1) * CELL_H, height: CELL_H, x: 0, y: index * CELL_H, toJSON: () => ({}) }) as DOMRect;
		}
	});
	return rows;
}

function mountWith(input: string): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	return { core, host, renderer };
}

describe("the terminal selection", () => {
	it("paints rows from the model: first row to the edge, middle whole, last to its cell", () => {
		const { host, renderer } = mountWith("alpha\r\nbeta\r\ngamma");
		const rows = layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(CELL_W * 2 + 1, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3 + 1, CELL_H * 2.5)!);
		expect(rows[0]!.style.backgroundImage).toContain(`transparent ${CELL_W * 2}px`);
		expect(rows[0]!.style.backgroundImage).toContain("600px");
		expect(rows[1]!.style.backgroundImage).toContain("transparent 0px");
		expect(rows[2]!.style.backgroundImage).toContain(`${CELL_W * 3}px, transparent`);
		expect(renderer.selectedText()).toBe("pha\nbeta\ngam");
	});

	it("survives a repaint that rebuilds every row", () => {
		const { core, host, renderer } = mountWith("alpha\r\nbeta\r\ngamma\r\n");
		layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 4, CELL_H * 1.5)!);
		expect(renderer.hasSelection()).toBe(true);
		for (let tick = 0; tick < 20; tick += 1) feed(core, `\x1b[2K\r✻ Baking for ${tick}s`);
		const rows = layoutRows(host);
		expect(renderer.hasSelection()).toBe(true);
		expect(renderer.selectedText()).toBe("alpha\nbeta");
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
	});

	it("tints a painted run's background instead of hiding under it", () => {
		const band = "\x1b[48;5;237m\x1b[38;5;231m> hi\x1b[0m";
		const { host, renderer } = mountWith(`alpha\r\n${band}\r\ngamma`);
		const rows = layoutRows(host);
		const run = rows[1]!.querySelector<HTMLElement>("[data-terminal-run]")!;
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(0, CELL_H * 2.5)!);
		expect(run.style.backgroundImage).toContain("var(--terminal-selection)");
		expect(run.style.backgroundImage).toContain("200px");
		renderer.selectionClear();
		expect(run.style.backgroundImage).toBe("");
		expect(rows[1]!.style.backgroundImage).toBe("");
	});

	it("selects a word on a double click and a line on a triple click", () => {
		const { host, renderer } = mountWith("see src/row-builder.ts now");
		layoutRows(host);
		const point = renderer.pointAt(CELL_W * 8, CELL_H * 0.5)!;
		renderer.selectionBegin(point, "word");
		expect(renderer.selectedText()).toBe("src/row-builder.ts");
		renderer.selectionBegin(point, "line");
		expect(renderer.selectedText()).toBe("see src/row-builder.ts now");
	});

	it("drops the selection when its block leaves the snapshot", () => {
		const { core, host, renderer } = mountWith("\x1b]133;A\x07\x1b]133;C\x07one\r\n\x1b]133;D;0\x07");
		layoutRows(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, CELL_H * 0.5)!);
		expect(renderer.hasSelection()).toBe(true);
		for (let i = 0; i < 400; i += 1) feed(core, `\x1b]133;A\x07\x1b]133;C\x07row ${i}\r\n\x1b]133;D;0\x07`);
		expect(renderer.hasSelection()).toBe(false);
	});

	it("notifies listeners when the selection changes", () => {
		const { host, renderer } = mountWith("alpha");
		layoutRows(host);
		let calls = 0;
		const off = renderer.onSelectionChange(() => { calls += 1; });
		renderer.selectionBegin(renderer.pointAt(0, 1)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3, 1)!);
		renderer.selectionClear();
		off();
		renderer.selectionClear();
		expect(calls).toBe(3);
	});
});
```

The "drops the selection" case relies on `scrollback: 100` trimming the first block; if the block survives 400 more blocks, raise the count or lower scrollback, and check `decodeBlocks(core.snapshot())` no longer contains its id.

- [ ] **Step 2: Run to see it fail.** `npx vitest run src/terminal-selection.test.ts`. Expected: FAIL, `pointAt is not a function`.

- [ ] **Step 3: Implement in `dom-block-renderer.ts`**

Imports: replace the `selection-fill` import with `import { fillGradient, runFill } from "./selection-fill.js";`, delete the `selection.js` import, add:

```ts
import { pointAtFromRows, rowFillSpan, type RowBox } from "./selection-geometry.js";
import { resolveRange, type SelectionKind, type SelectionPoint, type SelectionRange, type SelectionState } from "./selection-model.js";
import { selectedText, type TextRows } from "./selection-text.js";
```

Add `export const ALT_BLOCK_ID = "alt";` after the constants.

Fields: remove `selectionUnsubscribe`; add

```ts
private selection: SelectionState | null = null;
private readonly selectionListeners = new Set<() => void>();
```

In `mount`, delete the `selectionchange` listener block (lines 103-106). In `dispose`, delete the `selectionUnsubscribe` line and add `this.selection = null;`.

Replace `getSelectionRange` with:

```ts
pointAt(x: number, y: number): SelectionPoint | null {
	const { cellWidth, cellHeight } = this.cellMetrics();
	return pointAtFromRows(this.rowBoxes(), x, y, cellWidth, cellHeight);
}

selectionBegin(point: SelectionPoint, kind: SelectionKind): void {
	this.selection = { head: point, tail: point, kind };
	this.selectionChanged();
}

selectionUpdate(point: SelectionPoint): void {
	if (!this.selection) return;
	this.selection = { ...this.selection, tail: point };
	this.selectionChanged();
}

selectionClear(): void {
	if (!this.selection) return;
	this.selection = null;
	this.selectionChanged();
}

hasSelection(): boolean {
	return this.selectionRange() !== null;
}

selectedText(): string | null {
	const range = this.selectionRange();
	if (!range) return null;
	return selectedText(range, this.textRows());
}

onSelectionChange(listener: () => void): () => void {
	this.selectionListeners.add(listener);
	return () => {
		this.selectionListeners.delete(listener);
	};
}

private selectionChanged(): void {
	this.paintSelectionFill();
	for (const listener of [...this.selectionListeners]) listener();
}

private blockOrder(): (blockId: string) => number {
	const index = new Map<string, number>();
	this.latestBlocks.forEach((block, position) => index.set(block.id, position));
	return (blockId) => (blockId === ALT_BLOCK_ID ? 0 : (index.get(blockId) ?? -1));
}

private textRows(): TextRows {
	const snapshot = this.latestSnapshot;
	const alt = this.core?.snapshot().altScreen ?? null;
	if (alt) {
		return {
			blockIds: [ALT_BLOCK_ID],
			rowCount: () => alt.rows,
			rowText: (_id, row) => this.rowString(alt.content, alt.rowRanges, row),
		};
	}
	const blocks = this.latestBlocks;
	const byId = new Map(blocks.map((block) => [block.id, block] as const));
	return {
		blockIds: blocks.map((block) => block.id),
		rowCount: (id) => byId.get(id)?.rowCount ?? 0,
		rowText: (id, row) => {
			const block = byId.get(id);
			if (!block || !snapshot) return "";
			return this.rowString(snapshot.content, snapshot.rows, block.firstRow + row);
		},
	};
}

private rowString(content: Uint8Array, rows: Uint32Array, row: number): string {
	const start = rows[row * 2] ?? 0;
	const end = rows[row * 2 + 1] ?? start;
	if (end <= start) return "";
	return this.decoder.decode(content.subarray(start, end));
}

private selectionRange(): SelectionRange | null {
	const selection = this.selection;
	if (!selection) return null;
	const order = this.blockOrder();
	if (order(selection.head.blockId) < 0 || order(selection.tail.blockId) < 0) return null;
	const rows = this.textRows();
	return resolveRange(selection, order, (id, row) => rows.rowText(id, row));
}

private rowBoxes(): RowBox[] {
	const boxes: RowBox[] = [];
	const alt = this.altRoot && !this.altRoot.hidden ? this.altRoot : null;
	if (alt) {
		const rows = alt.querySelectorAll<HTMLElement>("[data-terminal-row]");
		rows.forEach((row) => {
			const rect = row.getBoundingClientRect();
			boxes.push({ blockId: ALT_BLOCK_ID, row: Number(row.dataset.terminalRow), rowCount: rows.length, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width });
		});
		return boxes;
	}
	const byId = new Map(this.filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of this.blockElements) {
		const rowCount = byId.get(id)?.rowCount ?? 0;
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			const rect = row.getBoundingClientRect();
			boxes.push({ blockId: id, row: Number(row.dataset.terminalRow), rowCount, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width });
		}
	}
	return boxes;
}
```

Replace `paintSelectionFill` with:

```ts
private paintSelectionFill(): void {
	for (const node of this.filledRows) node.style.backgroundImage = "";
	this.filledRows = [];
	const range = this.selectionRange();
	if (!range) return;
	const order = this.blockOrder();
	const { cellWidth } = this.cellMetrics();
	const colour = "var(--terminal-selection)";
	const rows = this.altRoot && !this.altRoot.hidden
		? [...this.altRoot.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => [ALT_BLOCK_ID, row] as const)
		: [...this.blockElements].flatMap(([id, section]) => [...section.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => [id, row] as const));
	const rowCounts = new Map(this.filteredBlocks.map((block) => [block.id, block.rowCount] as const));
	for (const [blockId, row] of rows) {
		const rect = row.getBoundingClientRect();
		const box: RowBox = { blockId, row: Number(row.dataset.terminalRow), rowCount: rowCounts.get(blockId) ?? 0, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width };
		const span = rowFillSpan(range, box, order, cellWidth);
		if (!span) continue;
		row.style.backgroundImage = fillGradient(span, colour);
		this.filledRows.push(row);
		for (const run of row.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
			if (run.style.backgroundColor === "") continue;
			const runSpan = runFill(run.getBoundingClientRect(), rect.left, span);
			if (!runSpan) continue;
			run.style.backgroundImage = fillGradient(runSpan, colour);
			this.filledRows.push(run);
		}
	}
}
```

In `repaint`: in the alt branch, after `this.wasAltActive = true;` add `this.selection = null;`; in the non-alt branch where `this.wasAltActive = false;` is set, wrap: `if (this.wasAltActive) this.selection = null;` before it. After `this.latestBlocks = blocks;` add:

```ts
if (this.selection && this.blockOrder()(this.selection.head.blockId) < 0) this.selection = null;
if (this.selection && this.blockOrder()(this.selection.tail.blockId) < 0) this.selection = null;
```

Keep the existing `this.paintSelectionFill();` call near the end of `repaint`, and add one in the alt branch after `renderAltSurface(...)`. `clearBlockSelection` becomes `this.selectionClear()` at its call site and the method is deleted.

`index.ts`: replace the `selection.js` export line with `export { ALT_BLOCK_ID } from "./dom-block-renderer.js"; export type { SelectionKind, SelectionPoint } from "./selection-model.js";`. Delete `selection.ts` and `selection.test.ts`.

Styles: in both `styles.ts` and `styles.css`, the rule

```css
.terminal-block,
.terminal-alt-surface {
	-webkit-user-select: text;
	user-select: text;
	cursor: default;
}
```

becomes `-webkit-user-select: none; user-select: none; cursor: default;`, and the `::selection` rule block (`.terminal-block ::selection` … `background-color: transparent;`) is deleted along with its comment. In `styles-parity.test.ts` replace "keeps the transcript selectable whatever the host does to the body" and "leaves the selection for the renderer to paint" with one test:

```ts
it("owns the selection itself, so the browser paints none", () => {
	const block = terminalStyles.slice(terminalStyles.indexOf(".terminal-block,"), terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block,")));
	expect(block).toContain("user-select: none");
	expect(terminalStyles).not.toContain("::selection");
});
```

- [ ] **Step 4: Run the suite.** `npx vitest run` in renderer-dom. Expected: all PASS. `host-styling.test.ts` or others asserting `user-select: text` must be updated to `none`.

- [ ] **Step 5: Commit**

```bash
git add -A packages/terminal/ts/renderer-dom/src
git commit -m "feat(terminal): the renderer owns the selection in grid coordinates"
```

---

### Task 7: Gesture state

**Files:**
- Create: `packages/terminal/ts/react/src/selection-gesture.ts`
- Test: `packages/terminal/ts/react/src/selection-gesture.test.ts`

**Interfaces:**
- Produces:

```ts
export const DRAG_THRESHOLD_PX = 0.5;
export function exceedsDragThreshold(origin: { x: number; y: number }, x: number, y: number): boolean;
export function kindForClickCount(count: number): SelectionKind;
export function autoScrollRows(y: number, top: number, bottom: number): number;
export function isCopyChord(event: { key: string; metaKey: boolean; ctrlKey: boolean; shiftKey: boolean; altKey: boolean }, mac: boolean): boolean;
```

`autoScrollRows` is Warp's `POLYNOMIAL_SCROLLING` (`block_list_element.rs:140-167`, `overshoot ** 1.5 / 100`), negative above the top, positive below the bottom with `BOTTOM_VERTICAL_MARGIN = 10`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { autoScrollRows, exceedsDragThreshold, isCopyChord, kindForClickCount } from "./selection-gesture";

describe("exceedsDragThreshold", () => {
	it("ignores jitter under half a pixel, Warp's MIN_DELTA_FOR_TEXT_SELECTION", () => {
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10.4, 10.4)).toBe(false);
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10.6, 10)).toBe(true);
		expect(exceedsDragThreshold({ x: 10, y: 10 }, 10, 9.4)).toBe(true);
	});
});

describe("kindForClickCount", () => {
	it("maps clicks to Warp's SelectionType::from_click_count", () => {
		expect(kindForClickCount(1)).toBe("simple");
		expect(kindForClickCount(2)).toBe("word");
		expect(kindForClickCount(3)).toBe("line");
		expect(kindForClickCount(4)).toBe("line");
	});
});

describe("autoScrollRows", () => {
	it("is zero inside the list", () => {
		expect(autoScrollRows(50, 0, 100)).toBe(0);
	});
	it("scrolls up past the top and down past the bottom margin with Warp's curve", () => {
		expect(autoScrollRows(-100, 0, 400)).toBeCloseTo(-10, 5);
		expect(autoScrollRows(500, 0, 400)).toBeCloseTo(Math.pow(110, 1.5) / 100, 5);
	});
});

describe("isCopyChord", () => {
	it("is cmd-c on mac and ctrl-shift-c elsewhere", () => {
		expect(isCopyChord({ key: "c", metaKey: true, ctrlKey: false, shiftKey: false, altKey: false }, true)).toBe(true);
		expect(isCopyChord({ key: "c", metaKey: false, ctrlKey: true, shiftKey: false, altKey: false }, true)).toBe(false);
		expect(isCopyChord({ key: "C", metaKey: false, ctrlKey: true, shiftKey: true, altKey: false }, false)).toBe(true);
		expect(isCopyChord({ key: "c", metaKey: false, ctrlKey: true, shiftKey: false, altKey: false }, false)).toBe(false);
	});
});
```

- [ ] **Step 2: Run to see it fail.** `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run src/selection-gesture.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**

```ts
import type { SelectionKind } from "@operator/terminal-renderer-dom";

export const DRAG_THRESHOLD_PX = 0.5;
const BOTTOM_VERTICAL_MARGIN = 10;
const SELECTION_SCROLLING_ACCELERATION = 1.5;

export function exceedsDragThreshold(origin: { x: number; y: number }, x: number, y: number): boolean {
	return Math.abs(x - origin.x) > DRAG_THRESHOLD_PX || Math.abs(y - origin.y) > DRAG_THRESHOLD_PX;
}

export function kindForClickCount(count: number): SelectionKind {
	if (count >= 3) return "line";
	if (count === 2) return "word";
	return "simple";
}

function accelerated(delta: number): number {
	return Math.pow(delta, SELECTION_SCROLLING_ACCELERATION) / 100;
}

export function autoScrollRows(y: number, top: number, bottom: number): number {
	const floor = bottom - BOTTOM_VERTICAL_MARGIN;
	if (y < top) return -accelerated(top - y);
	if (y > floor) return accelerated(y - floor);
	return 0;
}

export function isCopyChord(
	event: { key: string; metaKey: boolean; ctrlKey: boolean; shiftKey: boolean; altKey: boolean },
	mac: boolean,
): boolean {
	if (event.key.toLowerCase() !== "c" || event.altKey) return false;
	if (mac) return event.metaKey && !event.ctrlKey && !event.shiftKey;
	return event.ctrlKey && event.shiftKey && !event.metaKey;
}
```

- [ ] **Step 4: Run to see it pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/react/src/selection-gesture.ts packages/terminal/ts/react/src/selection-gesture.test.ts
git commit -m "feat(terminal): selection gesture rules from Warp"
```

---

### Task 8: Wire the gestures and copy into the surface

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (mouse effect at lines 262-417, `focusEditorFromHost` at 436-444, resize `apply` at 184-207)
- Test: `packages/terminal/ts/react/src/TerminalSurface.mouse.test.tsx`

**Interfaces:**
- Consumes: renderer API from Task 6, helpers from Task 7.

- [ ] **Step 1: Write the failing tests** (append to `TerminalSurface.mouse.test.tsx`)

```ts
function layoutRows(container: HTMLElement): HTMLElement[] {
	const rows = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * cellHeight, bottom: (index + 1) * cellHeight, height: cellHeight, x: 0, y: index * cellHeight, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mouse(target: EventTarget, type: string, x: number, y: number, init: MouseEventInit = {}): void {
	target.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true, cancelable: true, ...init }));
}

describe("TerminalSurface selection", () => {
	beforeAll(loadWasm);
	afterEach(() => cleanup());

	it("selects with a drag, keeps it through output, and copies with the platform chord", async () => {
		const writeClipboard = vi.fn(async () => {});
		const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
		const { container, core } = renderSurface({ host });
		act(() => { feed(core, "alpha\r\nbeta\r\ngamma\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 4, cellHeight * 1.5);
		mouse(window, "mouseup", cellWidth * 4, cellHeight * 1.5);
		act(() => { feed(core, "spinner\r\n"); });
		await flushRepaint();
		layoutRows(container);
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
		expect(writeClipboard).toHaveBeenCalledWith("alpha\nbeta");
	});

	it("does not start a selection under the drag threshold and clears on a plain click", async () => {
		const { container, core } = renderSurface();
		act(() => { feed(core, "alpha\r\nbeta\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 1.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 1.5);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		mouse(rows[1]!, "mousedown", 10, cellHeight * 1.5, { detail: 1 });
		mouse(window, "mousemove", 10.2, cellHeight * 1.5);
		mouse(window, "mouseup", 10.2, cellHeight * 1.5);
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("selects a word on double click and clears when the user types", async () => {
		const { container, core } = renderSurface();
		act(() => { feed(core, "see src/row-builder.ts now\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", cellWidth * 8, cellHeight * 0.5, { detail: 2 });
		mouse(window, "mouseup", cellWidth * 8, cellHeight * 0.5);
		expect(rows[0]!.style.backgroundImage).toContain(`transparent ${cellWidth * 4}px`);
		const editorHost = container.querySelector(".terminal-editor-host") as HTMLElement;
		editorHost.dispatchEvent(new KeyboardEvent("keydown", { key: "x", bubbles: true }));
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("leaves the drag to a mouse-reporting app unless shift is held", async () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => { feed(core, "\x1b[?1000h\x1b[?1006halpha\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, 1);
		mouse(window, "mouseup", cellWidth * 3, 1);
		expect(onSendRaw).toHaveBeenCalled();
		expect(rows[0]!.style.backgroundImage).toBe("");
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 3, 1, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 3, 1, { shiftKey: true });
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
	});
});
```

`renderSurface` must accept `host` in its overrides: add `host?: HostCapabilities` to the overrides type and pass `host={overrides.host}` in `surfaceWith` (import the type from `@operator/terminal-core`).

- [ ] **Step 2: Run to see it fail.** `npx vitest run src/TerminalSurface.mouse.test.tsx`. Expected: the four new tests FAIL.

- [ ] **Step 3: Implement in `TerminalSurface.tsx`**

Import `import { autoScrollRows, exceedsDragThreshold, isCopyChord, kindForClickCount } from "./selection-gesture.js";`.

Inside the mouse effect (the one starting `useLayoutEffect(() => { const blockHost = hostRef.current; ... let dragButton ...`), add after `let dragButton: 0 | 1 | 2 | null = null;`:

```ts
let pressOrigin: { x: number; y: number } | null = null;
let pressPoint: import("@operator/terminal-renderer-dom").SelectionPoint | null = null;
let pressKind: import("@operator/terminal-renderer-dom").SelectionKind = "simple";
let dragging = false;
let autoScroll: number | null = null;
let lastPointer = { x: 0, y: 0 };
const renderer = () => rendererRef.current;
const stopAutoScroll = () => {
	if (autoScroll !== null) cancelAnimationFrame(autoScroll);
	autoScroll = null;
};
const extendTo = (x: number, y: number) => {
	const target = renderer();
	if (!target) return;
	const bounds = blockHost.getBoundingClientRect();
	const point = target.pointAt(Math.min(Math.max(x, bounds.left), bounds.right), Math.min(Math.max(y, bounds.top), bounds.bottom));
	if (point) target.selectionUpdate(point);
};
const autoScrollStep = () => {
	autoScroll = null;
	const bounds = blockHost.getBoundingClientRect();
	const rows = autoScrollRows(lastPointer.y, bounds.top, bounds.bottom);
	if (rows === 0 || !dragging) return;
	const cellHeight = renderer()?.measure().cellHeight ?? 0;
	blockHost.scrollTop += rows * cellHeight;
	extendTo(lastPointer.x, lastPointer.y);
	autoScroll = requestAnimationFrame(autoScrollStep);
};
const onWindowMouseMove = (event: MouseEvent) => {
	if (!pressOrigin || !pressPoint) return;
	lastPointer = { x: event.clientX, y: event.clientY };
	const target = renderer();
	if (!target) return;
	if (!dragging) {
		if (!exceedsDragThreshold(pressOrigin, event.clientX, event.clientY)) return;
		dragging = true;
		if (pressKind === "simple") target.selectionBegin(pressPoint, "simple");
	}
	extendTo(event.clientX, event.clientY);
	const bounds = blockHost.getBoundingClientRect();
	if (autoScrollRows(event.clientY, bounds.top, bounds.bottom) !== 0) {
		if (autoScroll === null && core.snapshot().altScreen === null) autoScroll = requestAnimationFrame(autoScrollStep);
	} else {
		stopAutoScroll();
	}
};
const onWindowMouseUp = () => {
	const target = renderer();
	if (target && pressOrigin && !dragging && pressKind === "simple") target.selectionClear();
	pressOrigin = null;
	pressPoint = null;
	dragging = false;
	stopAutoScroll();
	window.removeEventListener("mousemove", onWindowMouseMove);
	window.removeEventListener("mouseup", onWindowMouseUp);
};
```

In `onMouseDown`, after the report branch (`if (data === null) return;` currently returns when there is no report; restructure so a null report falls through to selection):

```ts
const onMouseDown = (event: MouseEvent) => {
	compositionRef.current?.focus();
	const button = buttonOf(event);
	if (button === null) return;
	const data = reportFor("press", button, event);
	if (data !== null) {
		event.preventDefault();
		dragButton = button;
		onSendRaw(data);
		return;
	}
	if (button !== 0) return;
	const target = renderer();
	if (!target) return;
	const point = target.pointAt(event.clientX, event.clientY);
	if (!point) return;
	event.preventDefault();
	pressOrigin = { x: event.clientX, y: event.clientY };
	pressPoint = point;
	pressKind = kindForClickCount(event.detail);
	dragging = false;
	if (pressKind !== "simple") target.selectionBegin(point, pressKind);
	window.addEventListener("mousemove", onWindowMouseMove);
	window.addEventListener("mouseup", onWindowMouseUp);
};
```

Add a copy handler bound to both hosts and a typing handler on the editor host:

```ts
const mac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/u.test(navigator.platform);
const onCopyKey = (event: KeyboardEvent) => {
	const target = renderer();
	if (!target || !isCopyChord(event, mac)) return;
	const text = target.selectedText();
	if (text === null) return;
	event.preventDefault();
	event.stopPropagation();
	void hostRef2.current?.writeClipboard(text);
};
const onEditorTyping = (event: KeyboardEvent) => {
	if (event.key === "Shift" || event.key === "Control" || event.key === "Alt" || event.key === "Meta") return;
	if (isCopyChord(event, mac)) return;
	renderer()?.selectionClear();
};
```

where `hostRef2` is a new `useRef(host)` kept current at the top of the component (`const hostCapsRef = useRef(host); hostCapsRef.current = host;`, name it `hostCapsRef` and use it in `onCopyKey`). Bind: `blockHost.addEventListener("keydown", onCopyKey); editorHost.addEventListener("keydown", onCopyKey); editorHost.addEventListener("keydown", onEditorTyping);` (`editorHost` is `editorHostRef.current`, read at the top of the effect next to `blockHost`; bail if null). Remove all three in the cleanup, plus `stopAutoScroll()` and the window listeners.

`focusEditorFromHost`: replace the `document.getSelection()` check with `if (rendererRef.current?.hasSelection()) return;`.

Resize `apply`: before `core.resize(columns, rows);` add `renderer.selectionClear();`.

Alt screen: `pointAt` already reads the alt root when it is visible; nothing extra. The existing alt `onKeyDown` must not swallow the copy chord: in it, add `if (isCopyChord(event, mac)) return;` before `encodeKey` (define `mac` once at module level: `const IS_MAC = typeof navigator !== "undefined" && /Mac|iPhone|iPad/u.test(navigator.platform);` and use it in both effects).

- [ ] **Step 4: Run the react suite.** `npx vitest run` in react. Expected: PASS. If the mouse-reporting test still paints a selection, the `data !== null` branch is not returning early; if the copy test gets `null`, `layoutRows` was not re-applied after the repaint (rows are rebuilt).

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.mouse.test.tsx packages/terminal/ts/react/src/surface-harness.tsx
git commit -m "feat(terminal): drag, word, line selection and copy driven by the surface"
```

---

### Task 9: Playwright regression check

**Files:**
- Create: `packages/terminal/bench/select.html`, `packages/terminal/bench/select-main.ts`, `packages/terminal/bench/selection-gate.mjs`
- Modify: `packages/terminal/package.json` (script `"bench:selection": "node ./bench/selection-gate.mjs"`)

- [ ] **Step 1: Write the page**

`select.html`:

```html
<!doctype html>
<html lang="en">
	<head>
		<meta charset="UTF-8" />
		<title>selection gate</title>
		<style>
			html, body, #root { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #0b0d10; }
		</style>
	</head>
	<body>
		<div id="root"></div>
		<script type="module" src="/select-main.ts"></script>
	</body>
</html>
```

`select-main.ts` mounts `TerminalSurface` through React (the bench already depends on react and `@vitejs/plugin-react`; check `bench/adapters/dom.ts` for how it mounts and mirror it), feeds forty turns of a Claude-Code-like transcript with a band, exposes `window.__gate = { startSpinner, stopSpinner, copied: string[] }` where `host.writeClipboard` pushes into `copied`, and sets `window.__gateReady = true` after the first paint.

- [ ] **Step 2: Write the gate**

`selection-gate.mjs`: start Vite with `bench/vite.config.ts`, open `/select.html`, wait for `__gateReady`, drag from (120,120) to (900,560) in 60 steps with the spinner running, release, wait 500 ms with the spinner still running, press `Meta+c`, then assert `copied[0].length > 100` and that `document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]').length > 5`. Print `PASS selection survived N repaints` or exit 1. Reuse the drag loop from the probe run on 2026-09-10 (scratchpad `drag-probe.mjs`).

- [ ] **Step 3: Run it.** `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && node ./bench/selection-gate.mjs`. Expected: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add packages/terminal/bench/select.html packages/terminal/bench/select-main.ts packages/terminal/bench/selection-gate.mjs packages/terminal/package.json
git commit -m "test(terminal): gate that a selection survives repaints"
```

---

### Task 10: Ship

**Files:**
- Modify: `packages/terminal/CHANGELOG.md` (Unreleased), `TERMINAL.md` (§4.13, and §1 renderer-dom line), `frontend` typecheck only.

- [ ] **Step 1: Build and verify everything**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
```

Expected: all green.

- [ ] **Step 2: Changelog entry** under "Selecting a painted band shows the selection.":

```
The selection lives in the renderer, not the browser.

- The transcript's selection was the browser's, anchored in text nodes that
  every repaint rebuilt, so new output collapsed it and a drag lurched to the
  block start. `renderer-dom` now owns the selection as grid points
  (block, row, column, half-cell side), paints it from geometry and copies it
  from the snapshot, the way Warp's `BlockListSelection` works. Double-click
  selects a word with Warp's boundary set, triple-click a line, a drag past
  the edge auto-scrolls with Warp's curve, and Cmd+C (Ctrl+Shift+C off macOS)
  copies. Typing, a plain click, a resize, or the block leaving scrollback
  clears it; output and scrolling do not.
```

- [ ] **Step 3: TERMINAL.md §4.13** with symptom (selection destroyed by repaints, measured 1356 → 0 chars), cause (browser selection in rebuilt nodes), now (model in `selection-model.ts`, geometry, text, gestures in `selection-gesture.ts`), guards (the tests above and `bench:selection`). Update §1's renderer-dom line to mention `selection-model`.

- [ ] **Step 4: Commit**

```bash
git add packages/terminal/CHANGELOG.md TERMINAL.md
git commit -m "docs(terminal): record the model-owned selection"
```

Then tell the user to restart the app (`npm run tauri:dev`); no daemon or wasm rebuild is needed.
