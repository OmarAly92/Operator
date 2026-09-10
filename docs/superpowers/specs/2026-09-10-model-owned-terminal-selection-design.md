# Model-owned terminal selection

**Date:** 2026-09-10
**Scope:** `packages/terminal` (`ts/renderer-dom`, `ts/react`), `frontend/src/renderer/components/BlockTerminal.tsx`
**Reference:** Warp, `app/src/terminal/model/blocks/selection.rs`, `app/src/terminal/block_list_element.rs`, `app/src/terminal/grid_renderer.rs`, `crates/warp_terminal/src/model/grid/grid_handler.rs`

## Problem

The transcript's selection is the browser's. Its anchor and focus are text nodes
inside rows that `populateBlock` rebuilds from scratch on every repaint, and a
repaint is scheduled on every scroll event and every byte of output. When the
row holding an end is replaced, the DOM moves that end to the parent element at
offset 0: mid-drag the highlight lurches to the start of the block, and after the
drag the next output tick collapses the selection entirely. Under Claude Code's
spinner any selection is gone within about 100 ms, and a copy afterwards gets
nothing. Measured in the bench harness: 1356 selected characters idle, 0 with a
spinner writing every 100 ms.

Warp does not have this problem because its selection is a `(head, tail)` pair of
grid anchors in the model, painted from geometry every frame, independent of what
was rendered.

## Design

### Selection model (`renderer-dom/src/selection-model.ts`)

A pure module. A `SelectionPoint` is

```
{ blockId: BlockId; row: number; column: number; side: "left" | "right" }
```

`row` is the offset inside the block, so a point survives scrollback trimming,
which renumbers blocks but not rows within them. `side` is Warp's half-cell
(`runtime.rs::get_mouse_side`): a pointer in the right half of a cell lands on
the cell's right edge. The model holds `{ head, tail, kind }` with
`kind: "simple" | "word" | "line"`, and resolves to an ordered range with Warp's
`range_simple` correction (`crates/warp_terminal/src/model/selection.rs:571`):
an end on the left side of its cell excludes that cell, a start on the right
side excludes its cell. Word and line kinds expand both ends over the row's text
(`words.ts`). A range whose start and end resolve to the same point is empty and
counts as no selection.

The alt screen uses the same shape with `blockId` set to the alt surface's
sentinel id and `row` as the screen row.

### Geometry (`renderer-dom/src/selection-geometry.ts`)

`pointAt(x, y)`: the row under the pointer is found from the rendered rows, not
a text hit test. Take the row element whose vertical span contains `y`; if none
does (the pointer is over a spacer, a header, block padding, or outside the
list), take the nearest rendered row of the nearest block and add
`floor((y - rowTop) / cellHeight)` to its label, clamped to the block's row
count. The column is `floor((x - rowContentLeft) / cellWidth)` clamped to
`[0, columns - 1]`, with `side` from the half-cell remainder. Block ids come
from `data-terminal-block-id`, row labels from `data-terminal-row`.

Fill spans: for each rendered row in the ordered range, rows strictly between
the ends fill edge to edge, the first row from `column * cellWidth` to the edge,
the last row from the edge to its column. This is `calculate_background_bounds`.
The existing `rowFill`, `runFill` and `fillGradient` in `selection-fill.ts` are
reused; `selectionRowFills` stops reading the DOM range and reads the model.

### Text (`renderer-dom/src/selection-text.ts`, `cell-width.ts`)

`selectedText(model, snapshot, blocks, decoder)` decodes each selected row's
bytes and cuts it by cell column. `cell-width.ts` maps a code point to 0, 1 or 2
cells (combining marks and zero-width joiners 0; East Asian Wide and Fullwidth
ranges and emoji presentation 2), mirroring what vt-core's `unicode-width` does.
Rules from `grid_handler.rs::line_to_string` and
`blocks/selection.rs::selection_to_string`:

- Rows are joined with `\n`. A blank row inside the selection is an empty line.
- Trailing spaces on a row are dropped. Warp drops never-written cells and keeps
  printed spaces; the snapshot cannot tell the two apart, so the trim is the
  closest match and what xterm.js does.
- A selection spanning several blocks joins their texts with exactly one `\n`.
- One trailing newline is trimmed.
- Soft-wrapped rows copy as separate lines. The snapshot does not export the
  `wrapped` flag; joining them is the known gap in TERMINAL.md §5, unchanged.

### Renderer API (`DomBlockRenderer`)

Replaces `getSelectionRange` and `selectionToBlockRange`:

```
pointAt(x: number, y: number): SelectionPoint | null
selectionBegin(point: SelectionPoint, kind: SelectionKind): void
selectionUpdate(point: SelectionPoint): void
selectionClear(): void
hasSelection(): boolean
selectedText(): string | null
onSelectionChange(listener: () => void): () => void
```

`paintSelectionFill` runs after every repaint and on every model change, reading
the model. Runs with a background keep their clipped tint. The browser selection
is turned off on `.terminal-block` and `.terminal-alt-surface`
(`user-select: none`) so the two cannot disagree; the line editor keeps its own.

The renderer drops the selection when its head or tail block is no longer in the
snapshot (trimmed out of scrollback), when the column or row count changes
(Warp `blocks.rs:2299`), and when the alt screen is entered or left.

### Gestures (`react/src/TerminalSurface.tsx`, `react/src/selection-gesture.ts`)

`selection-gesture.ts` is a pure state machine tested without a DOM:

- `mousedown` (button 0, not consumed by mouse reporting): remember the origin
  and the click count from `event.detail`. Nothing is selected yet.
- `mousemove` while pressed: until the pointer has moved more than 0.5 px on
  either axis nothing happens (`MIN_DELTA_FOR_TEXT_SELECTION`). On the first
  move past it, `selectionBegin(originPoint, kind)`; every move after,
  `selectionUpdate(pointAt(x, y))`. Moves are listened to on `window` so the
  drag continues outside the host.
- Click count 2 selects a word and 3 a line at `mousedown`, immediately, then
  the drag extends by whole words or lines.
- `mouseup`: if no drag happened and the click count is 1, `selectionClear()`.
- Auto-scroll: while pressed and the pointer is above or below the block list,
  a `requestAnimationFrame` loop scrolls the container by
  `overshoot ** 1.5 / 100` rows per frame (Warp's `POLYNOMIAL_SCROLLING`) and
  re-issues `selectionUpdate` at the pointer's clamped position. The loop stops
  on `mouseup` or when the pointer is back inside.
- Mouse reporting: when the app has SGR mouse tracking on and Shift is not held,
  the existing report path runs and no selection starts. Shift forces selection.
- Alt screen: same gestures over the alt surface. No auto-scroll.

Copy: a `keydown` listener on the surface host and the line editor host: Cmd+C on
macOS, Ctrl+Shift+C elsewhere, when `hasSelection()`, calls
`host.writeClipboard(selectedText())` and prevents the default. With no
selection the key is left alone. Ctrl+C on macOS clears the selection and is
otherwise unchanged.

Clearing: typing into the line editor clears the selection (`LineEditor`'s
input path calls `selectionClear()` through a callback). `focusEditorFromHost`
checks `hasSelection()` instead of the document selection.

### Host (`BlockTerminal.tsx`)

No new capability. Copy goes through the existing `writeClipboard`.

## Testing

- `selection-model.test.ts`: ordering, side correction, word and line expansion,
  empty selection.
- `selection-geometry.test.ts`: pointer to point over rows, spacers and padding
  with stubbed rects; fill spans for first, middle, last and single rows.
- `selection-text.test.ts`: the copy rules above against a fed core, including
  a band, blank rows, wide characters and a two-block span.
- `cell-width.test.ts`: ASCII 1, CJK 2, combining 0, emoji 2.
- `words.test.ts`: Warp's boundary set and allowlist.
- `selection-gesture.test.ts`: threshold, click count, clear on plain click,
  auto-scroll delta.
- `TerminalSurface.mouse.test.tsx`: drag produces a selection, Cmd+C copies
  through the host, typing clears, mouse reporting wins without Shift.
- `bench/selection-survives-repaint.mjs` (Playwright): a selection survives 20
  repaints with a spinner writing every 100 ms. Run by hand like the other
  bench scripts; it is the regression check for the original bug.

## Out of scope

Warp's smart-select regex tier (URL, email, path matching on double-click),
rectangular selection, keyboard-extended selection, joining soft-wrapped rows on
copy, and the pointing-hand cursor over links.
