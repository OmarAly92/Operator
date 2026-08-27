# Desktop Block Viewport Implementation Plan (Plan 4b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the desktop block list scroll correctly and cheaply over a long session — a windowed DOM, measured heights that correct their estimates without moving the view, anchored appends and prepends, sticky block headers with the tall-block exception, and block-boundary navigation.

**Architecture:** `BlocksView` currently puts every block in the DOM and chases the tail by assigning `scrollTop = scrollHeight` in a layout effect. This plan moves the list into `@tanstack/react-virtual` — already a dependency of this workspace, already used by `SessionFilesView` — with `anchorTo: "end"` and `followOnAppend: true`, which are that library's own implementations of the two anchoring requirements and are measurably correct here. Everything derived from scroll position — which block is under the top edge, whether the view is pinned, where a navigation jump lands — is read from the **virtualizer's numeric model**, never from `getBoundingClientRect`. That is what makes the behaviour both testable under jsdom and free of forced reflows during scroll.

**Tech Stack:** React 19, TypeScript, Vite, Vitest + `@testing-library/react`, `@tanstack/react-virtual` (`^3.14.9`, resolving to `virtual-core` 3.17.7 in `frontend/package-lock.json`), Tailwind v4, shadcn `components/ui/*`, `react-i18next`.

**Spec:** `docs/superpowers/specs/2026-08-27-session-blocks-design.md` — the "Viewport" section, and spec sequencing step 6. This plan is **4b**; `2026-08-27-mobile-block-viewport.md` is 4a. They share a requirements list and no code.

## Global Constraints

- **No code comments.** The user's global instruction is "don't make comments". Everything an implementer needs is in this plan; do not carry it into the source, not even to justify a subtle line.
- **No new dependencies.** `@tanstack/react-virtual` is already in `frontend/package.json` at `^3.14.9` and installed. Do not add, upgrade, or pin anything.
- **The renderer clones the agent-orchestrator web app** in looks and design (see `CLAUDE.md` and `DESIGN.md`). Build new UI from shadcn primitives in `components/ui/*` where one fits; the nav controls below use the existing `Button`.
- **No hardcoded display text.** `src/renderer/i18n/renderer-coverage.test.ts` parses every non-test `.tsx` under `src/renderer` and fails on English string literals in JSX text, and in the `alt`, `aria-label`, `placeholder` and `title` attributes. Every new string is an i18n key.
- **Every new key goes into all eight locale files** — `en`, `zh-CN`, `ja`, `ko`, `es`, `fr`, `de`, `pt-BR`. `i18n/instance.test.ts` fails if any locale is missing a key, has an empty value, or has a different set of `{{placeholders}}` than English.
- **Gates:** `npm run frontend:typecheck` from the repo root, and `npm --prefix frontend run test` (vitest). Both must pass at the end of every task before its commit. There is no root alias for the test command.
- Do not touch `backend/`, `packages/mobile/`, or the OpenAPI contract. This plan is renderer-only.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `frontend/src/renderer/test/virtual-layout.ts` | **Create.** Test-only jsdom layout harness. jsdom has no layout engine, so a virtualizer sees a zero-height everything and renders nothing; this gives elements real sizes and makes programmatic scrolling behave like a browser's. |
| `frontend/src/renderer/lib/block-viewport.ts` | **Create.** Pure viewport arithmetic: which item spans the top edge, sticky eligibility, boundary stepping, pinned test. No React, no DOM. |
| `frontend/src/renderer/components/blocks/BlockList.tsx` | **Create.** Owns the scroll element, the virtualizer, the sticky state, and the nav controls. |
| `frontend/src/renderer/components/blocks/BlocksView.tsx` | **Modify.** Keeps every notice/error/empty branch, moves the "load older" control above the scroller, and delegates the list to `BlockList`. |
| `frontend/src/renderer/components/blocks/BlockCard.tsx` | **Modify.** Extract `BlockCardHeader` so the sticky overlay renders the identical header, and wrap `BlockCard` in `memo`. |
| `frontend/src/renderer/components/CenterPane.tsx` | **Modify.** Pass `sessionId` through to `BlocksView`. |
| `frontend/src/renderer/i18n/*.json` (8 files) | **Modify.** Three new keys. |
| `frontend/src/renderer/lib/block-viewport.test.ts` | **Create.** Unit tests for the pure logic. |
| `frontend/src/renderer/components/blocks/BlockList.test.tsx` | **Create.** Windowing, anchoring, sticky headers, navigation, scroll cost. |
| `frontend/src/renderer/components/blocks/BlocksView.test.tsx` | **Modify.** Existing suite; installs the harness and gains a `sessionId` prop. |

### What is NOT in this plan

Cross-block **selection and find** are spec step 8 / plan 6. **Block actions** (copy, re-run, collapse, filter) are also plan 6. Do not build them, and do not leave hooks for them.

---

## Facts established by running the real thing

Every one of these was measured in this repository against the installed `virtual-core` 3.17.7 before the plan was written. Several of them contradict the obvious guess, and two of them silently make a naive test pass for the wrong reason. Do not re-derive them; do re-run them if something surprises you.

1. **`virtual-core` 3.17.7 ships the two anchoring behaviours as options.** `anchorTo: "end"` re-pins the item under the current offset whenever the list's edge keys change, which is prepend anchoring. `followOnAppend: true` scrolls to the end on an append **only when `isAtEnd`**, which is pinned-tail follow. Both are in `VirtualizerOptions` in the installed `.d.ts`. Hand-rolling either is strictly worse.
2. **jsdom implements no `Element.prototype.scrollTo`,** and `virtual-core` calls it through optional chaining (`scrollElement?.scrollTo?.(…)`). Without a polyfill every programmatic scroll is a **silent no-op** — no error, no warning.
3. **jsdom's `scrollHeight` is always `0`, and `getMaxScrollOffset()` is computed from it** (`scrollElement.scrollHeight - clientHeight`, `virtual-core` index.js:931). Unmocked, `getMaxScrollOffset()` returns a negative number, `getOffsetForAlignment` clamps every scroll target to `0`, and — worse — `isAtEnd()` returns `true` at every offset. A "does not follow when scrolled up" test **passes for the wrong reason** without this mock. This was found only by instrumenting the library.
4. **`scrollHeight` must report the sizer's height, not the true content height.** In a browser they are the same number: the sizer div is the scroll content. A harness that returns the sum of real heights instead makes the virtualizer aim past its own coordinate space.
5. **A programmatic scroll must dispatch its `scroll` event asynchronously.** Dispatching synchronously from inside the polyfill lands in the middle of `virtual-core`'s own update and produces `flushSync was called from inside a lifecycle method`. A `queueMicrotask` dispatch is both warning-free and closer to what a browser does. Without any dispatch the virtualizer never learns it moved, and the landing sequence in fact 6 cannot converge.
6. **Landing on the newest block takes more than one scroll.** Items that have never rendered keep their estimate, so `getTotalSize()` at mount is short of the truth; scrolling to it renders and measures more, which grows it again. An effect with **no dependency array** that re-scrolls while pinned converges — it is the desktop twin of the mobile plan's one-jump-per-frame loop. A single `useLayoutEffect` on mount lands at `scrollTop = -600` because the virtualizer has no measurements yet.
7. **`scrollToIndex` silently does nothing for an index outside `measurementsCache`.** `getOffsetForIndex` returns `undefined` and `scrollToIndex` returns without scrolling. Use `scrollToOffset` for "go to the end"; keep `scrollToIndex` for the adjacent blocks that navigation actually targets.
8. **Under the harness, a 300-block list mounts 9 rows** and holds an anchored prepend to a delta of exactly `0`.

---

### Task 1: The jsdom layout harness

Every later task's tests depend on this, and facts 2–5 above are why it looks the way it does. Building it first, with its own test, means a later failure is a product failure rather than an argument about the environment.

**Files:**
- Create: `frontend/src/renderer/test/virtual-layout.ts`
- Test: `frontend/src/renderer/test/virtual-layout.test.tsx`

**Interfaces:**
- Produces: `VIRTUAL_VIEWPORT_HEIGHT` (`600`), `type VirtualLayoutOptions = { heights: () => readonly number[]; viewportHeight?: number }`, and `installVirtualLayout(options): () => void` returning a teardown. Tasks 2–6 call it from `beforeEach` and its teardown from `afterEach`.
- Requires of its callers: the scroll container carries `data-block-scroll`, the sizer div carries `data-block-sizer` with an inline pixel `height`, and each row carries `data-index`. `BlockList` in Task 2 provides all three.

- [ ] **Step 1: Write the harness**

Create `frontend/src/renderer/test/virtual-layout.ts`:

```ts
import { vi } from "vitest";

export const VIRTUAL_VIEWPORT_HEIGHT = 600;

export type VirtualLayoutOptions = {
	heights: () => readonly number[];
	viewportHeight?: number;
};

function indexOf(element: HTMLElement): number | undefined {
	const raw = element.getAttribute("data-index");
	if (raw === null) return undefined;
	const index = Number(raw);
	return Number.isFinite(index) ? index : undefined;
}

export function installVirtualLayout(options: VirtualLayoutOptions): () => void {
	const viewportHeight = options.viewportHeight ?? VIRTUAL_VIEWPORT_HEIGHT;
	const heightAt = (index: number) => options.heights()[index] ?? 0;

	const sizeOf = function (this: HTMLElement) {
		const index = indexOf(this);
		return index === undefined ? viewportHeight : heightAt(index);
	};

	vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
		const height = sizeOf.call(this);
		return {
			top: 0,
			bottom: height,
			left: 0,
			right: 800,
			width: 800,
			height,
			x: 0,
			y: 0,
			toJSON() {
				return this;
			},
		} as DOMRect;
	});
	vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockImplementation(sizeOf);
	vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(sizeOf);
	vi.spyOn(Element.prototype, "scrollHeight", "get").mockImplementation(function (this: Element) {
		if (!this.hasAttribute("data-block-scroll")) return sizeOf.call(this as HTMLElement);
		const sizer = this.querySelector<HTMLElement>("[data-block-sizer]");
		const styled = sizer === null ? Number.NaN : Number.parseFloat(sizer.style.height);
		return Number.isFinite(styled) ? styled : 0;
	});

	const proto = Element.prototype as unknown as Record<string, unknown>;
	const hadScrollTo = "scrollTo" in proto;
	proto.scrollTo = function (this: Element, arg: unknown) {
		if (typeof arg !== "object" || arg === null || !("top" in arg)) return;
		const top = (arg as { top?: number }).top;
		if (typeof top !== "number") return;
		const next = Math.max(0, top);
		if (this.scrollTop === next) return;
		this.scrollTop = next;
		const target = this;
		queueMicrotask(() => target.dispatchEvent(new Event("scroll")));
	};

	return () => {
		vi.restoreAllMocks();
		if (!hadScrollTo) delete proto.scrollTo;
	};
}
```

`measureElement` reads `offsetHeight` by default, which is why the row heights must come back from that getter and not only from the rect.

- [ ] **Step 2: Write a test that proves the harness drives a real virtualizer**

Create `frontend/src/renderer/test/virtual-layout.test.tsx`:

```tsx
import { useVirtualizer } from "@tanstack/react-virtual";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useRef, useState } from "react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { installVirtualLayout, VIRTUAL_VIEWPORT_HEIGHT } from "./virtual-layout";

const heightOf = (label: string) => 60 + (Number(label.replace(/\D/g, "")) % 5) * 40;
let currentItems: string[] = [];

function List({ items }: { items: string[] }) {
	const ref = useRef<HTMLDivElement | null>(null);
	const pinned = useRef(true);
	const virtualizer = useVirtualizer({
		count: items.length,
		getScrollElement: () => ref.current,
		estimateSize: () => 96,
		getItemKey: (index) => items[index],
		anchorTo: "end",
		followOnAppend: true,
		overscan: 4,
	});
	return (
		<div
			data-block-scroll
			data-testid="scroll"
			onScroll={(event) => {
				const node = event.currentTarget;
				pinned.current = node.scrollTop >= virtualizer.getTotalSize() - node.clientHeight - 24;
			}}
			ref={ref}
			style={{ overflowY: "auto" }}
		>
			<div data-block-sizer style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
				{virtualizer.getVirtualItems().map((row) => (
					<div
						data-index={row.index}
						data-start={row.start}
						data-testid="row"
						key={row.key}
						ref={virtualizer.measureElement}
					>
						{items[row.index]}
					</div>
				))}
			</div>
		</div>
	);
}

function Harness() {
	const [items, setItems] = useState(() => Array.from({ length: 300 }, (_, index) => `b-${index}`));
	currentItems = items;
	return (
		<>
			<button
				onClick={() => setItems((prev) => [...Array.from({ length: 40 }, (_, i) => `old-${i}`), ...prev])}
				type="button"
			>
				prepend
			</button>
			<button onClick={() => setItems((prev) => [...prev, `new-${prev.length}`])} type="button">
				append
			</button>
			<List items={items} />
		</>
	);
}

describe("installVirtualLayout", () => {
	let teardown: () => void;
	beforeEach(() => {
		teardown = installVirtualLayout({ heights: () => currentItems.map(heightOf) });
	});
	afterEach(() => teardown());

	it("gives rows their real measured height", async () => {
		render(<Harness />);
		await act(async () => {});
		const row = screen.getAllByTestId("row")[0];
		expect(row.getBoundingClientRect().height).toBe(heightOf(row.textContent ?? ""));
	});

	it("reports the sizer height as the scroll height", async () => {
		render(<Harness />);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		const sizer = node.querySelector<HTMLElement>("[data-block-sizer]");
		expect(node.scrollHeight).toBe(Number.parseFloat(sizer?.style.height ?? "0"));
		expect(node.scrollHeight).toBeGreaterThan(VIRTUAL_VIEWPORT_HEIGHT);
	});

	it("makes a programmatic scroll move the element and notify the virtualizer", async () => {
		render(<Harness />);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		expect(node.scrollTop).toBeGreaterThan(0);
	});

	it("windows a long list", async () => {
		render(<Harness />);
		await act(async () => {});
		const rows = screen.getAllByTestId("row").length;
		expect(rows).toBeGreaterThan(0);
		expect(rows).toBeLessThan(30);
	});

	it("holds an anchored prepend to a zero delta", async () => {
		render(<Harness />);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		act(() => {
			node.scrollTop = 1000;
			fireEvent.scroll(node);
		});
		const anchor = screen.getAllByTestId("row").find((row) => {
			const start = Number(row.dataset.start);
			return start <= node.scrollTop && start + heightOf(row.textContent ?? "") > node.scrollTop;
		});
		expect(anchor).toBeDefined();
		const label = anchor?.textContent ?? "";
		const before = Number(anchor?.dataset.start) - node.scrollTop;
		act(() => screen.getByText("prepend").click());
		expect(Number(screen.getByText(label).dataset.start) - node.scrollTop).toBe(before);
	});

	it("restores Element.prototype.scrollTo on teardown", async () => {
		render(<Harness />);
		await act(async () => {});
		teardown();
		expect("scrollTo" in Element.prototype).toBe(false);
		teardown = installVirtualLayout({ heights: () => currentItems.map(heightOf) });
		await waitFor(() => expect("scrollTo" in Element.prototype).toBe(true));
	});
});
```

`await act(async () => {})` immediately after `render` is required in **every** test in this plan that uses the harness. The scroll event is dispatched on a microtask (fact 5), so without it the flush happens outside `act` and React logs a warning even though the assertions pass.

- [ ] **Step 3: Run it**

```bash
npm --prefix frontend run test -- src/renderer/test/virtual-layout.test.tsx
```

Expected: 6 passing, and **no** `not wrapped in act(...)` warnings in the output. Warnings here mean an `await act(async () => {})` is missing.

- [ ] **Step 4: Typecheck and commit**

```bash
npm run frontend:typecheck
git add frontend/src/renderer/test/virtual-layout.ts frontend/src/renderer/test/virtual-layout.test.tsx
git commit -m "test(desktop): add a jsdom layout harness for virtualized lists"
```

---

### Task 2: Pure viewport arithmetic

**Files:**
- Create: `frontend/src/renderer/lib/block-viewport.ts`
- Test: `frontend/src/renderer/lib/block-viewport.test.ts`

**Interfaces:**
- Consumes: nothing. Deliberately React-free and DOM-free.
- Produces: `PINNED_SLACK_PX`, `ESTIMATED_BLOCK_HEIGHT`, `BLOCK_OVERSCAN`, `type TopItem = { index: number; start: number; size: number }`, and `topItemFor`, `headerSticks`, `isPinned`, `nextBoundary`, `previousBoundary`, `previousTarget`. Tasks 3–6 call all of them.

- [ ] **Step 1: Write the failing test**

Create `frontend/src/renderer/lib/block-viewport.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	headerSticks,
	isPinned,
	nextBoundary,
	previousBoundary,
	previousTarget,
	topItemFor,
} from "./block-viewport";

const items = [
	{ index: 0, start: 0, size: 100 },
	{ index: 1, start: 100, size: 250 },
	{ index: 2, start: 350, size: 80 },
];

describe("topItemFor", () => {
	it("finds the item spanning the top edge", () => {
		expect(topItemFor(items, 0)?.index).toBe(0);
		expect(topItemFor(items, 99)?.index).toBe(0);
		expect(topItemFor(items, 100)?.index).toBe(1);
		expect(topItemFor(items, 349)?.index).toBe(1);
		expect(topItemFor(items, 350)?.index).toBe(2);
	});

	it("returns nothing past the end of what is rendered", () => {
		expect(topItemFor(items, 430)).toBeUndefined();
	});

	it("returns nothing for an empty window", () => {
		expect(topItemFor([], 0)).toBeUndefined();
	});
});

describe("headerSticks", () => {
	it("sticks for a block shorter than the viewport", () => {
		expect(headerSticks(200, 600)).toBe(true);
	});

	it("sticks for a block exactly as tall as the viewport", () => {
		expect(headerSticks(600, 600)).toBe(true);
	});

	it("does not stick for a block taller than the viewport", () => {
		expect(headerSticks(900, 600)).toBe(false);
	});

	it("does not stick when the viewport has no height yet", () => {
		expect(headerSticks(100, 0)).toBe(false);
	});
});

describe("isPinned", () => {
	it("is pinned at the tail and inside the slack", () => {
		expect(isPinned(400, 1000, 600)).toBe(true);
		expect(isPinned(380, 1000, 600)).toBe(true);
	});

	it("is not pinned once clear of the slack", () => {
		expect(isPinned(300, 1000, 600)).toBe(false);
	});

	it("a list shorter than its viewport is pinned", () => {
		expect(isPinned(0, 200, 600)).toBe(true);
	});
});

describe("boundaries", () => {
	it("steps forward and stops at the last block", () => {
		expect(nextBoundary(0, 3)).toBe(1);
		expect(nextBoundary(2, 3)).toBeUndefined();
	});

	it("steps forward from nothing to the first block", () => {
		expect(nextBoundary(undefined, 3)).toBe(0);
	});

	it("steps back and stops at the first block", () => {
		expect(previousBoundary(2, 3)).toBe(1);
		expect(previousBoundary(0, 3)).toBeUndefined();
	});

	it("has no boundary in an empty list", () => {
		expect(nextBoundary(undefined, 0)).toBeUndefined();
		expect(previousBoundary(0, 0)).toBeUndefined();
	});
});

describe("previousTarget", () => {
	it("returns to the start of a partly scrolled block first", () => {
		expect(previousTarget({ index: 1, start: 100, size: 250 }, 180, 3)).toBe(1);
	});

	it("steps to the block before once already at a boundary", () => {
		expect(previousTarget({ index: 1, start: 100, size: 250 }, 100, 3)).toBe(0);
	});

	it("has nowhere to go from the first block's start", () => {
		expect(previousTarget({ index: 0, start: 0, size: 100 }, 0, 3)).toBeUndefined();
	});

	it("has nowhere to go with no top item", () => {
		expect(previousTarget(undefined, 0, 3)).toBeUndefined();
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
npm --prefix frontend run test -- src/renderer/lib/block-viewport.test.ts
```

Expected: `Failed to resolve import "./block-viewport"`.

- [ ] **Step 3: Write the implementation**

Create `frontend/src/renderer/lib/block-viewport.ts`:

```ts
export const PINNED_SLACK_PX = 24;

export const ESTIMATED_BLOCK_HEIGHT = 96;

export const BLOCK_OVERSCAN = 6;

export type TopItem = { index: number; start: number; size: number };

export function topItemFor(items: readonly TopItem[], scrollTop: number): TopItem | undefined {
	return items.find((item) => item.start <= scrollTop && item.start + item.size > scrollTop);
}

export function headerSticks(blockHeight: number, viewportHeight: number): boolean {
	return viewportHeight > 0 && blockHeight <= viewportHeight;
}

export function isPinned(scrollTop: number, totalSize: number, viewportHeight: number): boolean {
	return scrollTop >= totalSize - viewportHeight - PINNED_SLACK_PX;
}

export function nextBoundary(current: number | undefined, count: number): number | undefined {
	if (count === 0) return undefined;
	if (current === undefined) return 0;
	const next = current + 1;
	return next >= count ? undefined : next;
}

export function previousBoundary(current: number | undefined, count: number): number | undefined {
	if (count === 0 || current === undefined) return undefined;
	const previous = current - 1;
	return previous < 0 ? undefined : previous;
}

export function previousTarget(
	top: TopItem | undefined,
	scrollTop: number,
	count: number,
): number | undefined {
	if (top === undefined) return undefined;
	if (scrollTop - top.start > 1) return top.index;
	return previousBoundary(top.index, count);
}
```

- [ ] **Step 4: Run the gates and commit**

```bash
npm --prefix frontend run test -- src/renderer/lib/block-viewport.test.ts
npm run frontend:typecheck
git add frontend/src/renderer/lib/block-viewport.ts frontend/src/renderer/lib/block-viewport.test.ts
git commit -m "feat(desktop): add pure block viewport arithmetic"
```

---

### Task 3: The virtualized list, anchored at both ends

**Files:**
- Modify: `frontend/src/renderer/components/blocks/BlockCard.tsx`
- Create: `frontend/src/renderer/components/blocks/BlockList.tsx`
- Modify: `frontend/src/renderer/components/blocks/BlocksView.tsx`
- Modify: `frontend/src/renderer/components/CenterPane.tsx`
- Modify: `frontend/src/renderer/components/blocks/BlocksView.test.tsx`
- Test: `frontend/src/renderer/components/blocks/BlockList.test.tsx`

**Interfaces:**
- Consumes: `ESTIMATED_BLOCK_HEIGHT`, `BLOCK_OVERSCAN`, `isPinned`, `topItemFor` (Task 2); `installVirtualLayout` (Task 1); `SessionBlock` from `lib/session-block`.
- Produces: `function BlockList({ sessionId, blocks }: { sessionId: string; blocks: SessionBlock[] })`; `BlocksViewProps` gains `sessionId: string`; `BlockCard` becomes a `memo` component and `BlockCardHeader` is exported. Tasks 4–6 extend `BlockList`.

**Why the "load older" control moves above the scroller.** Inside the scroller it sits between the scroll origin and the virtualizer's coordinate origin, so every offset the virtualizer computes would be short by that control's height — the bug `SessionFilesView` pays for with a `scrollMargin` and a `ResizeObserver`. There is no reason to import that here: the control is a single affordance, it is more useful permanently visible than buried at the top of a long scroll, and moving it out deletes an entire class of off-by-a-header errors. This is a deliberate divergence from plan 4a, where a sliver above the centre costs nothing.

**Why there is no rendering threshold.** `SessionFilesView` virtualizes only above 150 rows and renders plainly below. Copying that here would mean two code paths for scroll position, sticky headers and navigation, and the previous three plans in this series each shipped a defect that lived in exactly that kind of seam. One path, always virtualized, with the existing tests updated to install the harness.

- [ ] **Step 1: Write the failing test**

Create `frontend/src/renderer/components/blocks/BlockList.test.tsx`:

```tsx
import { act, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import { installVirtualLayout } from "../../test/virtual-layout";
import { BlockList } from "./BlockList";

function block(seq: number, lines = 1): SessionBlock {
	return {
		id: `seq-${seq}`,
		firstSeq: seq,
		lastSeq: seq,
		kind: "tool",
		status: "ok",
		title: `Bash ${seq}`,
		body: Array.from({ length: lines }, (_, line) => `line ${line} of block ${seq}`).join("\n"),
		truncatedLines: 0,
		redacted: false,
	};
}

function range(from: number, to: number, lines?: (seq: number) => number): SessionBlock[] {
	const out: SessionBlock[] = [];
	for (let seq = from; seq <= to; seq += 1) out.push(block(seq, lines?.(seq) ?? 1));
	return out;
}

const heightOfBlock = (item: SessionBlock) => 40 + item.body.split("\n").length * 20;

let current: SessionBlock[] = [];

const byId = (id: string | undefined) => current.find((item) => item.id === id) ?? current[0];

function Harness({ initial, sessionId = "s-1" }: { initial: SessionBlock[]; sessionId?: string }) {
	const [blocks, setBlocks] = useState(initial);
	const [session, setSession] = useState(sessionId);
	current = blocks;
	return (
		<>
			<button onClick={() => setBlocks((prev) => [...range(1, 40), ...prev])} type="button">prepend</button>
			<button onClick={() => setBlocks((prev) => [...prev, block(9999, 2)])} type="button">append</button>
			<button
				onClick={() => {
					setSession("s-2");
					setBlocks(range(500, 505));
				}}
				type="button"
			>
				switch
			</button>
			<div style={{ height: 600 }}>
				<BlockList blocks={blocks} sessionId={session} />
			</div>
		</>
	);
}

async function mount(initial: SessionBlock[]) {
	current = initial;
	render(<Harness initial={initial} />);
	await act(async () => {});
}

describe("BlockList", () => {
	let teardown: () => void;
	beforeEach(() => {
		teardown = installVirtualLayout({ heights: () => current.map(heightOfBlock) });
	});
	afterEach(() => teardown());

	it("renders one card per block for a short session", async () => {
		await mount(range(1, 3));

		expect(screen.getAllByTestId("session-block")).toHaveLength(3);
		expect(screen.getByText("Bash 1")).toBeInTheDocument();
		expect(screen.getByText("Bash 3")).toBeInTheDocument();
	});

	it("mounts a small window of a long session", async () => {
		await mount(range(1, 800, (seq) => 1 + (seq % 5)));

		const mounted = screen.getAllByTestId("session-block").length;
		expect(mounted).toBeGreaterThan(0);
		expect(mounted).toBeLessThan(30);
	});

	it("opens at the newest block", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		expect(screen.getByText("Bash 300")).toBeInTheDocument();
		expect(screen.queryByText("Bash 1")).not.toBeInTheDocument();
	});

	it("follows a block appended while pinned", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		await act(async () => screen.getByText("append").click());

		expect(screen.getByText("Bash 9999")).toBeInTheDocument();
	});

	it("does not follow a block appended while scrolled up", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 1000;
			fireEvent.scroll(node);
		});

		await act(async () => screen.getByText("append").click());

		expect(screen.queryByText("Bash 9999")).not.toBeInTheDocument();
		expect(node.scrollTop).toBe(1000);
	});

	it("does not move the block being read when older blocks arrive", async () => {
		await mount(range(100, 400, (seq) => 1 + (seq % 5)));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 2000;
			fireEvent.scroll(node);
		});
		const anchor = [...document.querySelectorAll<HTMLElement>("[data-block-id]")].find((row) => {
			const start = Number(row.dataset.blockStart);
			return start <= node.scrollTop && start + heightOfBlock(byId(row.dataset.blockId)) > node.scrollTop;
		});
		expect(anchor).toBeDefined();
		const id = anchor?.dataset.blockId ?? "";
		const before = Number(anchor?.dataset.blockStart) - node.scrollTop;

		await act(async () => screen.getByText("prepend").click());

		const after = document.querySelector<HTMLElement>(`[data-block-id="${id}"]`);
		expect(after).not.toBeNull();
		expect(Number(after?.dataset.blockStart) - node.scrollTop).toBe(before);
	});

	it("opens the next session at its own newest block", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		await act(async () => screen.getByText("switch").click());

		expect(screen.getByText("Bash 505")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks/BlockList.test.tsx
```

Expected: `Failed to resolve import "./BlockList"`.

- [ ] **Step 3: Extract the card header and memoize the card**

In `frontend/src/renderer/components/blocks/BlockCard.tsx`, replace the exported function with a memoized one and lift the header row out. Keep `KIND_KEY` and `blockTitleKey` exactly as they are:

```tsx
import { memo } from "react";
import { useTranslation } from "react-i18next";
import type { BlockKind, SessionBlock } from "../../lib/session-block";
import { BlockStatusDot } from "./BlockStatusDot";
import type { MessageKey } from "../../i18n/messages";

export function BlockCardHeader({ block }: { block: SessionBlock }) {
	const { t } = useTranslation();
	const titleKey = blockTitleKey(block);

	return (
		<div className="flex items-center gap-2 border-border border-b px-3 py-2">
			<BlockStatusDot status={block.status} />
			<span className="flex-1 truncate font-medium text-foreground text-xs">
				{titleKey ? t(titleKey) : block.title}
			</span>
			<span className="text-[10px] text-muted-foreground">{t(KIND_KEY[block.kind])}</span>
		</div>
	);
}

export const BlockCard = memo(function BlockCard({ block }: { block: SessionBlock }) {
	const { t } = useTranslation();

	return (
		<div className="mx-3 my-1 rounded-md border border-border bg-card" data-testid="session-block">
			<BlockCardHeader block={block} />
			{block.body === "" ? null : (
				<p className="whitespace-pre-wrap break-words px-3 py-2 font-mono text-muted-foreground text-xs">
					{block.body}
				</p>
			)}
			{block.redacted ? (
				<p className="px-3 pb-1.5 text-[10px] text-warning">{t("blocks.redacted")}</p>
			) : null}
			{block.truncatedLines > 0 ? (
				<p className="px-3 pb-2 text-[10px] text-muted-foreground">
					{t("blocks.truncated", { count: block.truncatedLines })}
				</p>
			) : null}
		</div>
	);
});
```

`memo` is what keeps a scroll that changes only the sticky index from re-rendering every mounted card; Task 6 pins that.

- [ ] **Step 4: Write `BlockList`**

Create `frontend/src/renderer/components/blocks/BlockList.tsx`:

```tsx
import { useVirtualizer } from "@tanstack/react-virtual";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	BLOCK_OVERSCAN,
	ESTIMATED_BLOCK_HEIGHT,
	isPinned,
	topItemFor,
} from "../../lib/block-viewport";
import type { SessionBlock } from "../../lib/session-block";
import { BlockCard } from "./BlockCard";

export function BlockList({ blocks, sessionId }: { blocks: SessionBlock[]; sessionId: string }) {
	const { t } = useTranslation();
	const scrollRef = useRef<HTMLDivElement | null>(null);
	const pinnedRef = useRef(true);
	const [pinned, setPinned] = useState(true);

	const virtualizer = useVirtualizer({
		count: blocks.length,
		getScrollElement: () => scrollRef.current,
		estimateSize: () => ESTIMATED_BLOCK_HEIGHT,
		getItemKey: (index) => blocks[index]?.id ?? index,
		anchorTo: "end",
		followOnAppend: true,
		overscan: BLOCK_OVERSCAN,
	});

	const sync = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const next = isPinned(node.scrollTop, virtualizer.getTotalSize(), node.clientHeight);
		pinnedRef.current = next;
		setPinned(next);
	}, [virtualizer]);

	useEffect(() => {
		pinnedRef.current = true;
		setPinned(true);
	}, [sessionId]);

	useEffect(() => {
		if (!pinnedRef.current || blocks.length === 0) return;
		virtualizer.scrollToOffset(virtualizer.getTotalSize(), { align: "start" });
	});

	const items = virtualizer.getVirtualItems();
	const scrollTop = scrollRef.current?.scrollTop ?? 0;
	void topItemFor(items, scrollTop);
	void pinned;

	return (
		<div className="relative h-full min-h-0">
			<div
				aria-label={t("blocks.panelAria")}
				className="h-full min-h-0 overflow-y-auto py-1.5"
				data-block-scroll
				onScroll={sync}
				ref={scrollRef}
				role="log"
			>
				<div
					data-block-sizer
					style={{ height: virtualizer.getTotalSize(), position: "relative", width: "100%" }}
				>
					{items.map((row) => {
						const item = blocks[row.index];
						if (item === undefined) return null;
						return (
							<div
								data-block-id={item.id}
								data-block-start={row.start}
								data-index={row.index}
								key={row.key}
								ref={virtualizer.measureElement}
								style={{
									left: 0,
									position: "absolute",
									top: 0,
									transform: `translateY(${row.start}px)`,
									width: "100%",
								}}
							>
								<BlockCard block={item} />
							</div>
						);
					})}
				</div>
			</div>
		</div>
	);
}
```

The two `void` lines are placeholders for Tasks 4 and 5 and exist only so the imports and the derived values are in place; **delete them** as those tasks consume the values. `data-block-id` and `data-block-start` are what the anchoring test reads, and they stay — they are the only cheap way to assert a position without re-deriving the virtualizer's arithmetic in a test.

The effect with no dependency array is fact 6: it re-scrolls while pinned on every render, so the landing converges as estimates are replaced by measurements, and it becomes a no-op the moment the target stops moving because the harness and the browser both skip a `scrollTo` to the offset already in place.

- [ ] **Step 5: Rewire `BlocksView`**

In `frontend/src/renderer/components/blocks/BlocksView.tsx`: delete `PINNED_SLACK_PX`, `scrollRef`, `pinnedRef`, both effects and the `useEffect`/`useLayoutEffect` imports; add `sessionId` to the props; move the older control above the scroller; delegate the list.

```tsx
import { useTranslation } from "react-i18next";
import type { SessionBlock } from "../../lib/session-block";
import { Button } from "../ui/button";
import { BlockList } from "./BlockList";

export type BlocksViewProps = {
	blocks: SessionBlock[];
	isLoading: boolean;
	isLoadingOlder: boolean;
	hasOlder: boolean;
	error?: string;
	harness?: string;
	sessionId: string;
	supported: boolean;
	onLoadOlder: () => void;
	onRetry: () => void;
};

export function BlocksView({
	blocks,
	isLoading,
	isLoadingOlder,
	hasOlder,
	error,
	harness,
	sessionId,
	supported,
	onLoadOlder,
	onRetry,
}: BlocksViewProps) {
	const { t } = useTranslation();

	if (!supported) {
		return <Notice text={t("blocks.unavailable", { harness: harness ?? "" })} />;
	}

	if (error !== undefined && blocks.length === 0) {
		return (
			<div className="flex h-full flex-col items-center justify-center gap-2 px-8 text-center">
				<p className="text-destructive text-xs">{error}</p>
				<Button onClick={onRetry} size="sm" variant="outline">
					{t("blocks.retry")}
				</Button>
			</div>
		);
	}

	if (blocks.length === 0) {
		return <Notice text={isLoading ? t("blocks.loading") : t("blocks.empty")} />;
	}

	return (
		<div className="flex h-full min-h-0 flex-col">
			{isLoadingOlder ? (
				<p className="py-2 text-center text-[11px] text-muted-foreground">{t("blocks.loadingOlder")}</p>
			) : hasOlder ? (
				<div className="flex justify-center py-1.5">
					<Button onClick={onLoadOlder} size="sm" variant="ghost">
						{t("blocks.loadOlder")}
					</Button>
				</div>
			) : null}
			<div className="min-h-0 flex-1">
				<BlockList blocks={blocks} sessionId={sessionId} />
			</div>
		</div>
	);
}

function Notice({ text }: { text: string }) {
	return (
		<div className="flex h-full items-center justify-center px-8">
			<p className="text-center text-muted-foreground text-xs">{text}</p>
		</div>
	);
}
```

- [ ] **Step 6: Pass `sessionId` from `CenterPane`**

In `frontend/src/renderer/components/CenterPane.tsx`, inside `SessionBlocksPane`, add one prop to the `BlocksView` element, keeping the alphabetical ordering the file uses:

```tsx
			onRetry={blocks.refetch}
			sessionId={sessionId}
			supported={blocksCoverHarness(harness)}
```

- [ ] **Step 7: Update the existing `BlocksView` suite**

`BlocksView.test.tsx` now renders a virtualizer, so it needs the harness and the new prop. Add to the top:

```tsx
import { act } from "@testing-library/react";
import { afterEach, beforeEach } from "vitest";
import { installVirtualLayout } from "../../test/virtual-layout";
```

Give `renderView` the prop and a harness, and make each test that renders blocks `async` with `await act(async () => {})` after `renderView`:

```tsx
let currentBlocks: SessionBlock[] = [];

beforeEach(() => {
	teardown = installVirtualLayout({ heights: () => currentBlocks.map(() => 80) });
});
afterEach(() => teardown());

function renderView(props: Partial<Parameters<typeof BlocksView>[0]> = {}) {
	currentBlocks = props.blocks ?? [];
	return render(
		<BlocksView
			blocks={[]}
			error={undefined}
			harness="claude-code"
			hasOlder={false}
			isLoading={false}
			isLoadingOlder={false}
			onLoadOlder={vi.fn()}
			onRetry={vi.fn()}
			sessionId="s-1"
			supported
			{...props}
		/>,
	);
}
```

Declare `let teardown: () => void;` beside it. Then run the suite and fix each failure individually — the notice, error and empty tests need no change because they never reach the list.

- [ ] **Step 8: Run the gates**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks src/renderer/components/CenterPane.test.tsx
npm run frontend:typecheck
```

Expected: green. `CenterPane.test.tsx` mocks `useSessionBlocks` to return `blocks: []`, which takes the notice path and never mounts a virtualizer, so it needs no harness.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/renderer/components frontend/src/renderer/lib
git commit -m "feat(desktop): virtualize the block list and anchor both ends"
```

---

### Task 4: Sticky block headers, with the tall-block exception

**Files:**
- Modify: `frontend/src/renderer/components/blocks/BlockList.tsx`
- Test: `frontend/src/renderer/components/blocks/BlockList.test.tsx`

**Interfaces:**
- Consumes: `topItemFor`, `headerSticks` (Task 2); `BlockCardHeader` (Task 3).
- Produces: the sticky overlay inside `BlockList`. Task 5 reuses the `stickyIndex` state for navigation.

**Why the state is a single number.** React bails out of a re-render when `setState` is called with the same primitive. Storing the sticky **index** — one number, or `null` — means a scroll that stays inside one block sets the same value and costs nothing, while a scroll that crosses a boundary re-renders exactly the overlay. Storing an object, or two pieces of state, gives that property up. The tall-block exception is folded into the same number: `null` means no pinned header, whether because nothing spans the top edge or because what does is taller than the viewport.

**Why the exception is `height <= viewportHeight`.** Straight from the spec, which cites Warp's `block_list_element.rs:135`: sticky headers are "disabled when the block is taller than the viewport … without the exception a tall block traps its own header".

- [ ] **Step 1: Write the failing tests**

Append inside the `describe("BlockList", …)` block in `BlockList.test.tsx`:

```tsx
	it("pins the header of the block under the top edge", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");

		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});

		const header = await screen.findByTestId("sticky-block-header");
		expect(header).toHaveTextContent("Bash 1");
	});

	it("moves the pinned header on to the next block", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");

		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3)) + 5;
			fireEvent.scroll(node);
		});

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
	});

	it("does not pin the header of a block taller than the viewport", async () => {
		await mount([block(1, 1), block(2, 200), block(3, 1)]);
		const node = screen.getByRole("log");

		act(() => {
			node.scrollTop = heightOfBlock(block(1, 1)) + 200;
			fireEvent.scroll(node);
		});

		expect(screen.queryByTestId("sticky-block-header")).not.toBeInTheDocument();
	});

	it("pins a header even when the session is too short to scroll", async () => {
		await mount(range(1, 2));

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");
	});
```

The last case is deliberate rather than incidental. Two short blocks do not fill a 600px viewport, so `getMaxScrollOffset()` is negative, every scroll target clamps to `0`, and the top edge sits on the first block. The header still belongs there — a list that cannot scroll is exactly where a missing header would read as a bug.

- [ ] **Step 2: Run them and confirm they fail**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks/BlockList.test.tsx
```

Expected: `Unable to find an element by: [data-testid="sticky-block-header"]`.

- [ ] **Step 3: Implement**

In `BlockList.tsx`, add `headerSticks` to the `block-viewport` import and `BlockCardHeader` to the `BlockCard` import. Replace the `pinned` state block with:

```tsx
	const [pinned, setPinned] = useState(true);
	const [stickyIndex, setStickyIndex] = useState<number | null>(null);

	const sync = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const next = isPinned(node.scrollTop, virtualizer.getTotalSize(), node.clientHeight);
		pinnedRef.current = next;
		setPinned(next);

		const top = topItemFor(virtualizer.getVirtualItems(), node.scrollTop);
		setStickyIndex(
			top !== undefined && headerSticks(top.size, node.clientHeight) ? top.index : null,
		);
	}, [virtualizer]);
```

Reset it alongside pinned on a session change:

```tsx
	useEffect(() => {
		pinnedRef.current = true;
		setPinned(true);
		setStickyIndex(null);
	}, [sessionId]);
```

Re-run `sync` after the content itself changes, so a block arriving under the top edge updates the header with no scrolling:

```tsx
	useEffect(() => {
		sync();
	}, [sync, blocks]);
```

Delete `void topItemFor(items, scrollTop);` and the now-unused `scrollTop` line. Derive the sticky block and render the overlay as the last child of the outer `relative` div:

```tsx
	const stickyBlock = stickyIndex === null ? undefined : blocks[stickyIndex];

	return (
		<div className="relative h-full min-h-0">
			<div /* the scroller, unchanged */>…</div>
			{stickyBlock === undefined ? null : (
				<div className="pointer-events-none absolute inset-x-0 top-1.5 px-3">
					<div
						className="overflow-hidden rounded-t-md border border-border bg-card"
						data-testid="sticky-block-header"
					>
						<BlockCardHeader block={stickyBlock} />
					</div>
				</div>
			)}
		</div>
	);
```

`pointer-events-none` matters: the overlay covers the real card's own header, and without it the header would swallow clicks meant for the list.

- [ ] **Step 4: Run the gates and commit**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks
npm run frontend:typecheck
git add frontend/src/renderer/components/blocks
git commit -m "feat(desktop): pin the header of the block under the viewport top"
```

---

### Task 5: Block-boundary navigation and jump-to-latest

**Files:**
- Modify: `frontend/src/renderer/components/blocks/BlockList.tsx`
- Modify: all eight of `frontend/src/renderer/i18n/{en,zh-CN,ja,ko,es,fr,de,pt-BR}.json`
- Test: `frontend/src/renderer/components/blocks/BlockList.test.tsx`

**Interfaces:**
- Consumes: `nextBoundary`, `previousTarget` (Task 2); `stickyIndex`, `pinned` (Tasks 3–4).
- Produces: the nav controls inside `BlockList`, and the message keys `blocks.previousBlock`, `blocks.nextBlock`, `blocks.jumpToLatest`.

**Why `scrollToIndex` here but `scrollToOffset` for the tail.** Fact 7: `scrollToIndex` is a silent no-op for an index the virtualizer has no measurement for. Navigation only ever targets the block adjacent to the one under the top edge, which is always inside the rendered range plus overscan, so its measurement exists. "Go to the newest" targets the far end of the list, where it does not — hence the offset form.

- [ ] **Step 1: Add the keys to all eight locales**

`en.json`:

```json
	"blocks.jumpToLatest": "Jump to latest",
	"blocks.nextBlock": "Next block",
	"blocks.previousBlock": "Previous block",
```

`zh-CN.json`:

```json
	"blocks.jumpToLatest": "跳到最新",
	"blocks.nextBlock": "下一个区块",
	"blocks.previousBlock": "上一个区块",
```

`ja.json`:

```json
	"blocks.jumpToLatest": "最新へ移動",
	"blocks.nextBlock": "次のブロック",
	"blocks.previousBlock": "前のブロック",
```

`ko.json`:

```json
	"blocks.jumpToLatest": "최신으로 이동",
	"blocks.nextBlock": "다음 블록",
	"blocks.previousBlock": "이전 블록",
```

`es.json`:

```json
	"blocks.jumpToLatest": "Ir a lo más reciente",
	"blocks.nextBlock": "Bloque siguiente",
	"blocks.previousBlock": "Bloque anterior",
```

`fr.json`:

```json
	"blocks.jumpToLatest": "Aller au plus récent",
	"blocks.nextBlock": "Bloc suivant",
	"blocks.previousBlock": "Bloc précédent",
```

`de.json`:

```json
	"blocks.jumpToLatest": "Zum Neuesten springen",
	"blocks.nextBlock": "Nächster Block",
	"blocks.previousBlock": "Vorheriger Block",
```

`pt-BR.json`:

```json
	"blocks.jumpToLatest": "Ir para o mais recente",
	"blocks.nextBlock": "Próximo bloco",
	"blocks.previousBlock": "Bloco anterior",
```

Insert each into its file in the position the file's existing key ordering implies; these catalogues are sorted, and a mis-sorted key is a review comment rather than a test failure.

- [ ] **Step 2: Write the failing tests**

Append inside `describe("BlockList", …)`:

```tsx
	it("steps to the next block boundary", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");

		await act(async () => screen.getByRole("button", { name: "Next block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
	});

	it("steps back to the block before a boundary", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3));
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");

		await act(async () => screen.getByRole("button", { name: "Previous block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");
	});

	it("steps back to the top of a partly scrolled block first", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3)) + 20;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");

		await act(async () => screen.getByRole("button", { name: "Previous block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
		expect(node.scrollTop).toBe(heightOfBlock(block(1, 3)));
	});

	it("offers a way back to the newest block only once scrolled away", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));
		expect(screen.queryByRole("button", { name: "Jump to latest" })).not.toBeInTheDocument();

		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByRole("button", { name: "Jump to latest" })).toBeInTheDocument();

		await act(async () => screen.getByRole("button", { name: "Jump to latest" }).click());

		expect(screen.getByText("Bash 300")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Jump to latest" })).not.toBeInTheDocument();
	});
```

- [ ] **Step 3: Run them and confirm they fail**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks/BlockList.test.tsx
```

Expected: `Unable to find an accessible element with the role "button" and name "Next block"`.

- [ ] **Step 4: Implement**

Add `nextBoundary` and `previousTarget` to the `block-viewport` import, `ChevronDown`, `ChevronUp` and `ArrowDown` from `lucide-react`, and `Button` from `../ui/button`. Add three handlers above the return:

```tsx
	const goNext = useCallback(() => {
		const target = nextBoundary(stickyIndex ?? undefined, blocks.length);
		if (target === undefined) return;
		virtualizer.scrollToIndex(target, { align: "start" });
	}, [blocks.length, stickyIndex, virtualizer]);

	const goPrevious = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const top = topItemFor(virtualizer.getVirtualItems(), node.scrollTop);
		const target = previousTarget(top, node.scrollTop, blocks.length);
		if (target === undefined) return;
		virtualizer.scrollToIndex(target, { align: "start" });
	}, [blocks.length, virtualizer]);

	const goLatest = useCallback(() => {
		pinnedRef.current = true;
		setPinned(true);
		virtualizer.scrollToOffset(virtualizer.getTotalSize(), { align: "start" });
	}, [virtualizer]);
```

Render them as the last child of the outer `relative` div, after the sticky overlay:

```tsx
			<div className="absolute right-3 bottom-3 flex flex-col items-end gap-2">
				<div className="flex flex-col overflow-hidden rounded-md border border-border bg-card">
					<Button aria-label={t("blocks.previousBlock")} onClick={goPrevious} size="icon" variant="ghost">
						<ChevronUp className="size-4" />
					</Button>
					<Button aria-label={t("blocks.nextBlock")} onClick={goNext} size="icon" variant="ghost">
						<ChevronDown className="size-4" />
					</Button>
				</div>
				{pinned ? null : (
					<Button aria-label={t("blocks.jumpToLatest")} onClick={goLatest} size="sm" variant="default">
						<ArrowDown className="size-3.5" />
						{t("blocks.jumpToLatest")}
					</Button>
				)}
			</div>
```

Delete the `void pinned;` placeholder from Task 3.


- [ ] **Step 5: Run the gates and commit**

```bash
npm --prefix frontend run test -- src/renderer/components src/renderer/i18n
npm run frontend:typecheck
git add frontend/src/renderer/components/blocks frontend/src/renderer/i18n
git commit -m "feat(desktop): navigate block boundaries and return to the newest block"
```

`src/renderer/i18n/instance.test.ts` and `renderer-coverage.test.ts` both run in that command; a missing locale or a bare English literal fails there rather than in review.

---

### Task 6: Prove scrolling stays cheap

The spec calls frame-time profiling "part of the work, not an afterthought", and names the failure it is guarding against: parity is lost if the list re-renders during scroll. These are that obligation in a form CI can run.

**Files:**
- Test: `frontend/src/renderer/components/blocks/BlockList.test.tsx`

**Interfaces:**
- Consumes: everything from Tasks 1–5. Adds no production code unless an assertion fails.

- [ ] **Step 1: Write the tests**

Append inside `describe("BlockList", …)`:

```tsx
	it("keeps a small window mounted while scrolling a long session", async () => {
		await mount(range(1, 800, (seq) => 1 + (seq % 5)));
		const node = screen.getByRole("log");

		act(() => {
			node.scrollTop = Math.floor(node.scrollHeight / 2);
			fireEvent.scroll(node);
		});

		const mounted = screen.getAllByTestId("session-block").length;
		expect(mounted).toBeGreaterThan(0);
		expect(mounted).toBeLessThan(30);
	});

	it("does not remount cards while scrolling inside one block", async () => {
		await mount(range(1, 300, () => 6));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 2000;
			fireEvent.scroll(node);
		});
		const before = screen.getAllByTestId("session-block")[0];

		for (let step = 0; step < 10; step += 1) {
			act(() => {
				node.scrollTop += 2;
				fireEvent.scroll(node);
			});
		}

		expect(screen.getAllByTestId("session-block")[0]).toBe(before);
	});

	it("keeps the card memoized so a sticky change does not re-render the list", () => {
		expect((BlockCard as unknown as { $$typeof: symbol }).$$typeof).toBe(Symbol.for("react.memo"));
	});
```

Import `BlockCard` in the test file for the last case.

- [ ] **Step 2: Run them**

```bash
npm --prefix frontend run test -- src/renderer/components/blocks/BlockList.test.tsx
```

Expected: all three pass against the code from Tasks 3–5. **If one fails it is a real defect in this plan's own output, not a test to relax:**

- mounted count ≥ 30 → the virtualizer lost its scroll element, most often because `getScrollElement` was changed to something that returns `null` after the first render, or `count` was wired to something other than `blocks.length`.
- the first card is a different DOM node → React re-created the subtree, which means the sticky or pinned state is being set to a fresh object rather than a primitive, or `BlockCard` lost its `memo`.
- the `$$typeof` check fails → `memo` was dropped from `BlockCard` in Task 3.

- [ ] **Step 3: Run the full gates**

```bash
npm run frontend:typecheck
npm --prefix frontend run test
```

Expected: the whole renderer suite green.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/renderer/components/blocks
git commit -m "test(desktop): pin the scroll cost of the block viewport"
```

---

## Done means

- `npm run frontend:typecheck` is clean and `npm --prefix frontend run test` is green.
- Opening a covered `tui` session in Blocks lands on the newest block, not the oldest.
- "Load older blocks" sits above the list and adds a page without moving what is on screen.
- A block arriving while scrolled up does not move the view; one arriving while pinned is followed.
- The header of the block under the top edge is pinned there, unless that block is taller than the viewport.
- The chevrons step block by block and "Jump to latest" appears only when the view has left the tail.
- A session with hundreds of blocks keeps fewer than thirty cards in the DOM, at rest and mid-scroll.
- No file added or changed by this plan contains a comment, and no display string is hardcoded.
