import type { BlockView } from "@operator/terminal-core";
import { anchorAt, computeWindow, rowTop, type WindowResult } from "./viewport.js";

const STICK_THRESHOLD_PX = 4;

export type ScrollAnchor = Readonly<{ stableRow: number; offsetPx: number }>;

export type ScrollLayout = { rowHeight: number; headerHeight: number; paddingY: number };

export type ScrollTrackerDeps = Readonly<{
	container: () => HTMLElement | null;
	blocks: () => readonly BlockView[];
	layout: () => ScrollLayout;
	paintedFirstStableRow: () => number;
}>;

export class ScrollTracker {
	stickToBottom = true;
	lastClientHeight = 0;
	private anchor: ScrollAnchor | null = null;

	constructor(private readonly deps: ScrollTrackerDeps) {}

	scrollAnchor(): ScrollAnchor | null {
		return this.stickToBottom ? null : this.anchor;
	}

	stickToLatest(container: HTMLElement): void {
		this.stickToBottom = true;
		this.anchor = null;
		const target = container.scrollHeight - container.clientHeight;
		if (target > 0) container.scrollTop = target;
	}

	visibleRowCapacity(): number {
		const container = this.deps.container();
		const { rowHeight } = this.deps.layout();
		if (!container || rowHeight <= 0) return 0;
		return Math.ceil(container.clientHeight / rowHeight);
	}

	frame(container: HTMLElement, firstStableRow: number, layout: ScrollLayout, overscanRows: number): { scrollTop: number; windowResult: WindowResult } {
		const { rowHeight, headerHeight, paddingY } = layout;
		const previousScrollTop = container.scrollTop;
		const scrollTop = this.stickToBottom
			? Number.MAX_SAFE_INTEGER
			: this.anchoredScrollTop(firstStableRow, previousScrollTop);
		const viewportHeight = container.clientHeight || 1;
		this.lastClientHeight = container.clientHeight;
		const windowResult = computeWindow({
			blocks: this.deps.blocks(),
			scrollTop,
			viewportHeight,
			rowHeight,
			headerHeight,
			overscanRows,
			blockPaddingY: paddingY,
		});
		return { scrollTop, windowResult };
	}

	settle(container: HTMLElement, scrollTop: number): void {
		if (this.stickToBottom) {
			this.applyStickiness();
		} else if (!overscrolled(container) && Math.abs(container.scrollTop - scrollTop) > 0.5) {
			container.scrollTop = scrollTop;
		}
	}

	flatRowFor(anchor: ScrollAnchor | null): number {
		if (!anchor) return 0;
		return Math.max(0, anchor.stableRow - this.deps.paintedFirstStableRow());
	}

	captureAnchor(): void {
		const container = this.deps.container();
		if (!container) return;
		const { rowHeight, headerHeight, paddingY } = this.deps.layout();
		const anchor = anchorAt(this.deps.blocks(), container.scrollTop, rowHeight, headerHeight, paddingY);
		this.anchor = anchor
			? { stableRow: this.deps.paintedFirstStableRow() + anchor.flatRow, offsetPx: anchor.offsetPx }
			: null;
	}

	remapAnchor(remap: ReadonlyArray<readonly [number, number]> | null): void {
		if (!remap || !this.anchor) return;
		this.anchor = remapScrollAnchor(this.anchor, remap);
	}

	anchoredScrollTop(firstStableRow: number, fallback: number): number {
		const anchor = this.anchor;
		if (!anchor) return fallback;
		const { rowHeight, headerHeight, paddingY } = this.deps.layout();
		const flat = Math.max(0, anchor.stableRow - firstStableRow);
		if (flat === 0 && anchor.stableRow < firstStableRow) {
			this.anchor = { stableRow: firstStableRow, offsetPx: anchor.offsetPx };
		}
		const top = rowTop(this.deps.blocks(), flat, rowHeight, headerHeight, paddingY);
		return top === null ? fallback : Math.max(0, top + anchor.offsetPx);
	}

	scrollToRow(row: number, align: "start" | "center" | "end"): boolean {
		const container = this.deps.container();
		const flat = row - this.deps.paintedFirstStableRow();
		if (!container || flat < 0) return false;
		const { rowHeight, headerHeight, paddingY } = this.deps.layout();
		const top = rowTop(this.deps.blocks(), flat, rowHeight, headerHeight, paddingY);
		if (top === null) return false;
		const room = Math.max(0, container.clientHeight - rowHeight);
		const offset = align === "start" ? 0 : align === "end" ? room : room / 2;
		this.stickToBottom = false;
		container.scrollTop = Math.max(0, top - offset);
		this.captureAnchor();
		return true;
	}

	updateStickiness(): void {
		const container = this.deps.container();
		if (!container) return;
		// A viewport that changed height moves the bottom out from under a pinned
		// terminal. The scroll event that follows belongs to the layout, not to
		// the user, and reading it as a deliberate scroll leaves the terminal
		// stranded a few rows short of the bottom for the rest of the session.
		if (container.clientHeight !== this.lastClientHeight) {
			this.lastClientHeight = container.clientHeight;
			if (this.stickToBottom) {
				this.applyStickiness();
				return;
			}
		}
		const distance = container.scrollHeight - container.scrollTop - container.clientHeight;
		this.stickToBottom = distance <= STICK_THRESHOLD_PX;
		if (this.stickToBottom) this.anchor = null;
	}

	applyStickiness(): void {
		const container = this.deps.container();
		if (!container || !this.stickToBottom) return;
		const target = container.scrollHeight - container.clientHeight;
		if (target <= 0) return;
		if (container.scrollTop < target - 0.5) {
			container.scrollTop = target;
		}
	}

	reset(): void {
		this.stickToBottom = true;
		this.anchor = null;
		this.lastClientHeight = 0;
	}
}

function remapScrollAnchor(anchor: ScrollAnchor, remap: ReadonlyArray<readonly [number, number]>): ScrollAnchor {
	let low = 0;
	let high = remap.length - 1;
	while (low <= high) {
		const mid = (low + high) >> 1;
		const [from, to] = remap[mid]!;
		if (from === anchor.stableRow) {
			return { stableRow: to, offsetPx: anchor.offsetPx };
		}
		if (from < anchor.stableRow) low = mid + 1;
		else high = mid - 1;
	}
	return anchor;
}

function overscrolled(container: HTMLElement): boolean {
	return container.scrollTop < 0 || container.scrollTop > container.scrollHeight - container.clientHeight;
}
