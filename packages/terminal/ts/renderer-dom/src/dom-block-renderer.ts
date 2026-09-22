import {
	decodeBlocks,
	defaultStrings,
	validateRowRange,
	type BlockId,
	type BlockRenderer,
	type BlockView,
	type FontConfig,
	type RowRange,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { renderAltSurface } from "./alt-surface.js";
import { populateBlock, reconcileChildren, ROW_GENERATION_ATTR } from "./block-body.js";
import { createCursorElement, cursorPaintFor, primaryCursorPlacement, PLAIN_CURSOR_PAINT, type CursorPlacement } from "./cursor.js";
import { ElementPool } from "./element-pool.js";
import { bindActionEvents } from "./action-events.js";
import { applyFilter, type BlockFilter } from "./block-filter.js";
import { mountBlockNavFromRenderer, type BlockNavHandle } from "./block-nav.js";
import { mountJumpToBottom, type JumpToBottom } from "./jump-to-bottom.js";
import { createPinnedHeaderElement, updatePinnedHeader } from "./pinned-header.js";
import { DEFAULT_FEATURES, resolveFeatures, sameFeatures, type RendererFeatures } from "./features.js";
import { defaultFont } from "./default-font.js";
import { ensureMeasureHost, HIDDEN_MEASURE_ID, listenScroll } from "./host-dom.js";
import { createDomMeasurer, WidthCache } from "./width-cache.js";
import { BLOCK_PADDING_X_PX, BLOCK_PADDING_TOP_LINES, BLOCK_COMMAND_GAP_LINES, blockPaddingY } from "./block-metrics.js";
import { blockIsBlank, trimTrailingBlankRows } from "./block-rows.js";
import { paintedRowOrigin, type RowOrigin } from "./row-geometry.js";
import { pointAtFromRows } from "./selection-geometry.js";
import { type SelectionKind, type SelectionPoint, type SelectionState } from "./selection-model.js";
import { selectedText } from "./selection-text.js";
import {
	renderedRows,
	resolveSelectionView,
	selectionFills,
	snapshotTextRows,
	type RenderedRow,
	type SelectionView,
} from "./selection-view.js";
import { styleVarEntries, styleVarsString } from "./style-vars.js";
import { terminalStylesForDocument } from "./styles.js";
import { warpDarkTheme } from "./theme-warp.js";
import { anchorAt, computeWindow, rowTop } from "./viewport.js";

const CLASS_BLOCK = "terminal-block";
const CLASS_LEADING_SPACER = "terminal-spacer";
const CLASS_TRAILING_SPACER = "terminal-spacer";
const OVERSCAN_ROWS = 6;
const STICK_THRESHOLD_PX = 4;

function overscrolled(container: HTMLElement): boolean {
	return container.scrollTop < 0 || container.scrollTop > container.scrollHeight - container.clientHeight;
}
const PAINT_INTERVAL_MS = 1000 / 60;
const POOL_CAPACITY_FACTOR = 3;
const POOL_DIRTY_CAP = 4096;
const FRAME_EPSILON_MS = 0.25;
export { ALT_BLOCK_ID } from "./selection-view.js";

export type ScrollAnchor = Readonly<{ stableRow: number; offsetPx: number }>;

export class DomBlockRenderer implements BlockRenderer {
	private container: HTMLElement | null = null;
	private core: TerminalCore | null = null;
	private list: HTMLElement | null = null;
	private altRoot: HTMLElement | null = null;
	private leadingSpacer: HTMLElement | null = null;
	private trailingSpacer: HTMLElement | null = null;
	private theme: TerminalTheme = warpDarkTheme;
	private font: FontConfig = defaultFont();
	private unsubscribe: (() => void) | null = null;
	private scrollUnsubscribe: (() => void) | null = null;
	private measureHost: HTMLElement | null = null;
	private measureNode: HTMLElement | null = null;
	private readonly blockElements: Map<BlockId, HTMLElement> = new Map();
	private rafHandle: number | null = null;
	private readonly paintListeners = new Set<() => void>();
	private knownBlockId: BlockId | null = null;
	private stickToBottom = true;
	private lastClientHeight = 0;
	private lastPaintAt: number | null = null;
	private wasAltActive = false;
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });
	private filteredBlocks: readonly BlockView[] = [];
	private currentFilter: BlockFilter | null = null;
	private pinnedHeader: HTMLElement | null = null;
	private blockNav: BlockNavHandle | null = null;
	private jumpToBottom: JumpToBottom | null = null;
	private filled: Map<HTMLElement, string> = new Map();
	private selection: SelectionState | null = null;
	private readonly selectionListeners = new Set<() => void>();
	private metricsCache: { cellWidth: number; cellHeight: number } | null = null;
	private widths: WidthCache | null = null;
	private dprQuery: MediaQueryList | null = null;
	private readonly onDprChange = () => this.invalidateMetrics();
	private anchor: ScrollAnchor | null = null;
	private paintedFirstStableRow = 0;
	private rowEventsUnsubscribe: (() => void) | null = null;
	private readonly pool = new ElementPool();
	private readonly pooledDirty = new Map<BlockId, Set<number> | null>();
	private cursorElement: HTMLElement | null = null;
	private fullSince = 0;
	private rebuildAll = false;
	private activeFeatures: RendererFeatures = DEFAULT_FEATURES;
	private focused = true;

	mount(container: HTMLElement, core: TerminalCore): void {
		this.dispose();
		this.container = container;
		this.core = core;
		ensurePackageStyleTag();
		container.style.position = "relative";
		applyScrollOverflow(container);
		container.style.contain = "strict";
		const list = document.createElement("div");
		list.className = "terminal-list";
		list.setAttribute("data-testid", "terminal-block-list");
		list.style.position = "relative";
		const leading = document.createElement("div");
		leading.className = CLASS_LEADING_SPACER;
		const trailing = document.createElement("div");
		trailing.className = CLASS_TRAILING_SPACER;
		list.append(leading, trailing);
		container.append(list);
		this.list = list;
		this.leadingSpacer = leading;
		this.trailingSpacer = trailing;
		const pinned = createPinnedHeaderElement();
		container.insertBefore(pinned, list);
		this.pinnedHeader = pinned;
		this.measureHost = ensureMeasureHost();
		this.measureNode = this.measureHost.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		this.scrollUnsubscribe = listenScroll(container, () => {
			this.updateStickiness();
			if (!this.stickToBottom) this.captureAnchor();
			this.scheduleRepaint();
		});
		this.rowEventsUnsubscribe = core.onRowEvents((event) => this.remapAnchor(event.remap));
		this.unsubscribe = core.onChange(() => this.scheduleRepaint());
		this.blockNav = mountBlockNavFromRenderer({ container, getBlocks: () => this.filteredBlocks, scrollToBlock: (id, align) => this.scrollToBlock(id, align), isAltScreenActive: () => core.snapshot().altScreen !== null });
		bindActionEvents(container, { setBlockBookmarked: (id, b) => core.setBlockBookmarked(id, b), getBlockBookmarked: (id) => core.blockBookmarked(id), setFilter: (f) => this.setFilter(f), scrollToBlock: (id, a) => this.scrollToBlock(id, a), scheduleRepaint: () => this.scheduleRepaint() });
		this.jumpToBottom = mountJumpToBottom({ container, getBlocks: () => this.filteredBlocks, getCellHeight: () => this.measure().cellHeight, getStickToBottom: () => this.stickToBottom, scrollToLatest: () => this.scrollToLatest(), isAltScreenActive: () => core.snapshot().altScreen !== null, strings: defaultStrings });
		this.jumpToBottom.mount();
		this.repaint();
	}

	setTheme(theme: TerminalTheme): void {
		this.theme = theme;
		this.applyStyleVars();
		this.invalidateMetrics();
	}

	setFont(font: FontConfig): void {
		this.font = font;
		this.applyStyleVars();
		this.rebuildAll = true;
		this.invalidateMetrics();
	}

	setFeatures(partial: Partial<RendererFeatures>): void {
		const next = resolveFeatures({ ...this.activeFeatures, ...partial });
		if (sameFeatures(next, this.activeFeatures)) return;
		this.activeFeatures = next;
		this.rebuildAll = true;
		this.scheduleRepaint();
	}

	features(): RendererFeatures {
		return this.activeFeatures;
	}

	setFocused(focused: boolean): void {
		if (this.focused === focused) return;
		this.focused = focused;
		if (this.activeFeatures.cursorHollowUnfocused) this.scheduleRepaint();
	}

	setFilter(filter: BlockFilter | null): void {
		this.currentFilter = filter, this.scheduleRepaint();
	}

	invalidate(range: RowRange): void {
		validateRowRange(range);
		this.scheduleRepaint();
	}

	measure(): { cellWidth: number; cellHeight: number } {
		if (this.metricsCache) return this.metricsCache;
		const host = this.measureHost ?? ensureMeasureHost();
		const node = this.measureNode ?? host.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		if (!node) {
			return { cellWidth: 0, cellHeight: 0 };
		}
		this.applyFontToMeasureNode(node);
		const rect = node.getBoundingClientRect();
		const cellWidth = rect.width > 0 ? rect.width : this.font.sizePx * 0.6;
		const cellHeight =
			rect.height > 0 ? rect.height : this.font.lineHeight * this.font.sizePx;
		this.metricsCache = { cellWidth, cellHeight };
		if (!this.widths) {
			this.widths = new WidthCache(createDomMeasurer(node));
		}
		this.watchDevicePixelRatio();
		return this.metricsCache;
	}

	private invalidateMetrics(): void {
		this.metricsCache = null;
		this.widths?.clear();
		this.scheduleRepaint();
	}

	// xterm.js src/browser/renderer/dom/DomRenderer.ts:330-334 (handleDevicePixelRatioChange)
	private watchDevicePixelRatio(): void {
		if (typeof matchMedia !== "function") return;
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`);
		this.dprQuery.addEventListener("change", this.onDprChange);
	}

	// The space a block reserves around its rows. A grid sized to the host rather
	// than to this is told it has more columns than a row can actually show, so
	// full-width lines overflow and the pane grows a horizontal scrollbar.
	blockContentInset(): { x: number; y: number } {
		const { cellHeight } = this.measure();
		const rowHeight = cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx;
		return { x: BLOCK_PADDING_X_PX * 2, y: blockPaddingY(rowHeight) };
	}

	rowOrigin(row: number): RowOrigin | null {
		return paintedRowOrigin(
			this.filteredBlocks,
			this.blockElements,
			row,
			this.cellMetrics().cellHeight,
			this.paintedFirstStableRow,
		);
	}

	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void {
		if (this.knownBlockId !== null && id !== this.knownBlockId) {
			throw new Error(`unknown block id ${id}`);
		}
		const element = this.blockElements.get(id);
		if (!element) {
			throw new Error("renderer is not mounted");
		}
		element.scrollIntoView({ block: align, inline: "nearest" });
	}

	scrollToLatest(): void {
		const c = this.container;
		if (!c) return;
		this.stickToBottom = true;
		this.anchor = null;
		const target = c.scrollHeight - c.clientHeight;
		if (target > 0) c.scrollTop = target;
		this.scheduleRepaint();
	}

	scrollAnchor(): ScrollAnchor | null {
		return this.stickToBottom ? null : this.anchor;
	}

	private layout(): { rowHeight: number; headerHeight: number; paddingY: number } {
		const { cellHeight } = this.measure();
		const rowHeight = cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx;
		return {
			rowHeight,
			headerHeight: rowHeight * (2 + BLOCK_COMMAND_GAP_LINES),
			paddingY: blockPaddingY(rowHeight) + 1,
		};
	}

	private flatRowFor(anchor: ScrollAnchor | null): number {
		if (!anchor) return 0;
		return Math.max(0, anchor.stableRow - this.paintedFirstStableRow);
	}

	private visibleRowCapacity(): number {
		const container = this.container;
		const { rowHeight } = this.layout();
		if (!container || rowHeight <= 0) return 0;
		return Math.ceil(container.clientHeight / rowHeight);
	}

	private captureAnchor(): void {
		const container = this.container;
		if (!container) return;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const anchor = anchorAt(this.filteredBlocks, container.scrollTop, rowHeight, headerHeight, paddingY);
		this.anchor = anchor
			? { stableRow: this.paintedFirstStableRow + anchor.flatRow, offsetPx: anchor.offsetPx }
			: null;
	}

	private remapAnchor(remap: ReadonlyArray<readonly [number, number]> | null): void {
		if (!remap || !this.anchor) return;
		let low = 0;
		let high = remap.length - 1;
		while (low <= high) {
			const mid = (low + high) >> 1;
			const [from, to] = remap[mid]!;
			if (from === this.anchor.stableRow) {
				this.anchor = { stableRow: to, offsetPx: this.anchor.offsetPx };
				return;
			}
			if (from < this.anchor.stableRow) low = mid + 1;
			else high = mid - 1;
		}
	}

	private anchoredScrollTop(firstStableRow: number, fallback: number): number {
		const anchor = this.anchor;
		if (!anchor) return fallback;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const flat = Math.max(0, anchor.stableRow - firstStableRow);
		if (flat === 0 && anchor.stableRow < firstStableRow) {
			this.anchor = { stableRow: firstStableRow, offsetPx: anchor.offsetPx };
		}
		const top = rowTop(this.filteredBlocks, flat, rowHeight, headerHeight, paddingY);
		return top === null ? fallback : Math.max(0, top + anchor.offsetPx);
	}

	pointAt(x: number, y: number): SelectionPoint | null {
		const { cellWidth, cellHeight } = this.cellMetrics();
		const boxes = this.renderedRows().map((row) => row.box);
		return pointAtFromRows(boxes, x, y, cellWidth, cellHeight);
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
		return this.selectionView() !== null;
	}

	selectedText(): string | null {
		const view = this.selectionView();
		return view ? selectedText(view.range, view.rows) : null;
	}

	onSelectionChange(listener: () => void): () => void {
		this.selectionListeners.add(listener);
		return () => {
			this.selectionListeners.delete(listener);
		};
	}

	private selectionChanged(): void {
		this.paintSelectionFill();
		this.notifySelectionListeners();
	}

	private notifySelectionListeners(): void {
		for (const listener of [...this.selectionListeners]) listener();
	}

	private dropSelection(): void {
		if (!this.selection) return;
		this.selection = null;
		this.notifySelectionListeners();
	}

	private selectionView(): SelectionView | null {
		const selection = this.selection;
		const core = this.core;
		if (!selection || !core) return null;
		return resolveSelectionView(selection, snapshotTextRows(core.snapshot(), this.currentFilter, this.decoder));
	}

	dispose(): void {
		this.jumpToBottom?.dispose(), (this.jumpToBottom = null);
		this.blockNav?.dispose(), (this.blockNav = null);
		if (this.unsubscribe) this.unsubscribe(), (this.unsubscribe = null);
		if (this.scrollUnsubscribe) this.scrollUnsubscribe(), (this.scrollUnsubscribe = null);
		if (this.rowEventsUnsubscribe) this.rowEventsUnsubscribe(), (this.rowEventsUnsubscribe = null);
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		this.paintListeners.clear();
		if (this.container) {
			this.container.replaceChildren();
			this.container.style.removeProperty("position");
			this.container.style.removeProperty("overflow");
			this.container.style.removeProperty("overflow-x");
			this.container.style.removeProperty("overflow-y");
			this.container.style.removeProperty("overscroll-behavior-y");
			this.container.style.removeProperty("contain");
		}
		this.container = null;
		this.core = null;
		this.list = null;
		this.altRoot = null;
		this.leadingSpacer = null;
		this.trailingSpacer = null;
		this.filled = new Map();
		this.pinnedHeader = null;
		this.blockElements.clear();
		this.pool.clear();
		this.pooledDirty.clear();
		this.cursorElement?.remove();
		this.cursorElement = null;
		this.fullSince = 0;
		this.rebuildAll = false;
		this.measureNode = null;
		this.knownBlockId = null;
		this.stickToBottom = true;
		this.anchor = null;
		this.paintedFirstStableRow = 0;
		this.lastClientHeight = 0;
		this.lastPaintAt = null;
		this.wasAltActive = false;
		this.selection = null;
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = null;
		this.metricsCache = null;
		this.widths = null;
	}

	/// Notifies when a repaint has actually landed in the DOM.
	///
	/// The bench harness needs this to time the same work xterm's `onRender`
	/// covers. Without it a caller can only wait for a bare animation frame,
	/// which fires whether or not anything painted.
	onPaint(listener: () => void): () => void {
		this.paintListeners.add(listener);
		return () => {
			this.paintListeners.delete(listener);
		};
	}

	private notifyPainted(): void {
		for (const listener of [...this.paintListeners]) {
			listener();
		}
	}

	private scheduleRepaint(): void {
		if (this.rafHandle !== null) return;
		if (typeof requestAnimationFrame !== "function") {
			this.repaint();
			return;
		}
		this.rafHandle = requestAnimationFrame((timestamp) => this.repaintOnFrame(timestamp));
	}

	private repaintOnFrame(timestamp: number): void {
		if (
			this.lastPaintAt !== null &&
			timestamp - this.lastPaintAt + FRAME_EPSILON_MS < PAINT_INTERVAL_MS
		) {
			this.rafHandle = requestAnimationFrame((nextTimestamp) =>
				this.repaintOnFrame(nextTimestamp),
			);
			return;
		}
		this.core?.drain();
		this.core?.tick(performance.now());
		this.rafHandle = null;
		this.repaint(timestamp);
	}

	private applyStyleVars(): void {
		const style = styleVarsString(this.theme, this.font);
		// The host gets them too, so the surface behind and between the blocks can
		// paint the theme's own background. Without this the gaps between blocks
		// fall through to whatever the embedding app painted, which seams against
		// the blocks whenever the terminal's palette is not the app's.
		//
		// Set them one at a time rather than replacing the style attribute: the
		// container is the one element mount() also styles, and overwriting the
		// attribute drops position/overflow/contain, which stops it being a
		// scroll container at all.
		if (this.container) {
			const target = this.container.style;
			for (const [name, value] of styleVarEntries(this.theme, this.font)) {
				target.setProperty(name, value);
			}
		}
		for (const element of this.blockElements.values()) {
			element.setAttribute("style", style);
		}
		if (this.altRoot) {
			this.altRoot.setAttribute("style", style);
		}
	}

	private applyFontToMeasureNode(node: HTMLElement): void {
		node.style.display = "inline-block";
		node.style.fontFamily = this.font.family;
		node.style.fontSize = `${this.font.sizePx}px`;
		node.style.fontWeight = String(this.font.weight);
		node.style.letterSpacing = `${this.font.letterSpacingPx}px`;
		node.style.lineHeight = `${this.font.lineHeight * this.font.sizePx}px`;
		node.style.fontVariantLigatures = this.font.ligatures ? "common-ligatures" : "none";
	}

	private repaint(paintedAt?: number): void {
		const core = this.core;
		const container = this.container;
		const list = this.list;
		const leading = this.leadingSpacer;
		const trailing = this.trailingSpacer;
		if (!core || !container || !list || !leading || !trailing) {
			return;
		}
		const anchor = this.scrollAnchor();
		const firstRow = Math.max(0, this.flatRowFor(anchor) - OVERSCAN_ROWS);
		core.setExportWindow(firstRow, firstRow + this.visibleRowCapacity() + 2 * OVERSCAN_ROWS);
		const snapshot = core.snapshot();

		const alt = snapshot.altScreen;
		if (alt) {
			if (!this.wasAltActive) {
				this.dropSelection();
				this.wasAltActive = true;
			}
			container.style.overflow = "hidden";
			container.scrollTop = 0;
			const altRoot = this.ensureAltRoot(container);
			altRoot.setAttribute("style", styleVarsString(this.theme, this.font));
			altRoot.hidden = false;
			if (this.list) this.list.hidden = true;
			if (this.pinnedHeader) this.pinnedHeader.hidden = true;
			renderAltSurface(alt, this.altRoot!, this.decoder, this.cellMetrics(), this.activeFeatures, this.widths);
			this.paintSelectionFill();
			if (paintedAt !== undefined) this.lastPaintAt = paintedAt;
			this.notifyPainted();
			core.takeDirty();
			this.rescheduleIfPending(core);
			return;
		}
		if (this.altRoot) {
			this.altRoot.hidden = true;
		}
		if (this.list) this.list.hidden = false;
		applyScrollOverflow(container);
		if (this.wasAltActive) this.dropSelection();
		this.wasAltActive = false;

		const blocks = decodeBlocks(snapshot);
		if (blocks.length > 0) {
			this.knownBlockId = blocks[0]!.id;
		}
		if (this.selection) {
			const ids = new Set(blocks.map((block) => block.id));
			if (!ids.has(this.selection.head.blockId) || !ids.has(this.selection.tail.blockId)) this.dropSelection();
		}
		const cursor: CursorPlacement | null = primaryCursorPlacement(snapshot);
		const cursorPaint = cursor
			? cursorPaintFor({ source: snapshot, row: cursor.row, column: cursor.column, theme: this.theme, features: this.activeFeatures, focused: this.focused, decoder: this.decoder })
			: PLAIN_CURSOR_PAINT;
		const dirty = core.takeDirty();
		if (dirty.full || this.rebuildAll) {
			this.fullSince = snapshot.generation;
			this.pool.clear();
			this.pooledDirty.clear();
			if (this.rebuildAll) this.blockElements.clear();
			this.rebuildAll = false;
		}
		for (const [id, away] of this.pooledDirty) {
			if (away === null) continue;
			if (away.size + dirty.rows.size > POOL_DIRTY_CAP) {
				this.pooledDirty.set(id, null);
				continue;
			}
			for (const stableRow of dirty.rows) away.add(stableRow);
		}
		const firstScreenStable = snapshot.firstStableRow + snapshot.historyRows;
		const pooledThisPaint = new Map<BlockId, Set<number> | null>();
		const freshFor = (blockId: BlockId) => (stableRow: number, node: HTMLElement): boolean => {
			const built = Number(node.getAttribute(ROW_GENERATION_ATTR));
			if (!Number.isFinite(built) || built < this.fullSince) return false;
			if (dirty.rows.has(stableRow)) return false;
			if (!pooledThisPaint.has(blockId)) return true;
			const away = pooledThisPaint.get(blockId);
			if (!away || away.has(stableRow)) return false;
			return stableRow < firstScreenStable;
		};
		const cursorElement = this.cursorElement ?? (this.cursorElement = createCursorElement(0, 0));
		let cursorPlaced = false;
		this.filteredBlocks = applyFilter(blocks, this.currentFilter)
			.filter((block) => !(
				snapshot.lineEditorState === 1 &&
				block === blocks.at(-1) &&
				block.source !== "synthetic" &&
				block.state === "running" &&
				block.command === "" &&
				blockIsBlank(snapshot, block)
			))
			.map((block) => trimTrailingBlankRows(snapshot, block));
		const { cellWidth } = this.measure();
		this.paintedFirstStableRow = snapshot.firstStableRow;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const previousScrollTop = container.scrollTop;
		const scrollTop = this.stickToBottom
			? Number.MAX_SAFE_INTEGER
			: this.anchoredScrollTop(snapshot.firstStableRow, previousScrollTop);
		const viewportHeight = container.clientHeight || 1;
		this.lastClientHeight = container.clientHeight;
		const windowResult = computeWindow({
			blocks: this.filteredBlocks,
			scrollTop,
			viewportHeight,
			rowHeight,
			headerHeight,
			overscanRows: OVERSCAN_ROWS,
			blockPaddingY: paddingY,
		});

		leading.style.height = `${windowResult.leadingSpacer}px`;
		trailing.style.height = `${windowResult.trailingSpacer}px`;
		if (this.blockNav) this.blockNav.setPinnedIndex(windowResult.pinnedBlockIndex);


		const visibleIds = new Set<BlockId>();
		if (windowResult.firstBlock <= windowResult.lastBlock) {
			for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
				const block = this.filteredBlocks[i]!;
				visibleIds.add(block.id);
				const { element, pooled, away } = this.ensureBlockElement(block);
				if (pooled) pooledThisPaint.set(block.id, away);
				const rowWindow = windowResult.rowWindows.get(i) ?? null;
				const placed = populateBlock(element, {
					block,
					snapshot,
					rowWindow,
					rowHeight,
					cellWidth,
					cursor,
					cursorElement,
					cursorPaint,
					decoder: this.decoder,
					firstStableRow: snapshot.firstStableRow,
					generation: snapshot.generation,
					rowIsFresh: freshFor(block.id),
					features: this.activeFeatures,
					widths: this.widths,
				});
				if (placed.cursorPlaced) cursorPlaced = true;
			}
		}
		if (!cursorPlaced) cursorElement.remove();

		const orderedVisible: HTMLElement[] = [];
		for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
			const block = this.filteredBlocks[i]!;
			const element = this.blockElements.get(block.id);
			if (element) orderedVisible.push(element);
		}
		reconcileChildren(list, [leading, ...orderedVisible, trailing]);
		if (this.pinnedHeader) {
			const first = orderedVisible[0];
			const scrolledPastHeader = first && first.getBoundingClientRect().top + rowHeight * (BLOCK_PADDING_TOP_LINES + 2) + 1 < container.getBoundingClientRect().top;
			updatePinnedHeader(this.pinnedHeader, this.filteredBlocks, scrolledPastHeader ? windowResult.firstBlock : -1, defaultStrings);
		}

		const capacity = POOL_CAPACITY_FACTOR * Math.max(1, orderedVisible.length);
		for (const [id, element] of this.blockElements) {
			if (!visibleIds.has(id)) {
				this.pool.put(id, element, capacity);
				this.pooledDirty.set(id, dirty.rows.size > POOL_DIRTY_CAP ? null : new Set(dirty.rows));
				this.blockElements.delete(id);
			}
		}
		for (const id of [...this.pooledDirty.keys()]) {
			if (!this.pool.has(id)) this.pooledDirty.delete(id);
		}
		if (this.stickToBottom) {
			this.applyStickiness();
		} else if (!overscrolled(container) && Math.abs(container.scrollTop - scrollTop) > 0.5) {
			container.scrollTop = scrollTop;
		}
		this.paintSelectionFill();
		if (paintedAt !== undefined) this.lastPaintAt = paintedAt;
		this.notifyPainted();
		this.rescheduleIfPending(core);
	}

	private rescheduleIfPending(core: TerminalCore): void {
		if (core.hasBacklog() || core.synchronizedOutput()) this.scheduleRepaint();
	}

	private paintSelectionFill(): void {
		const view = this.selectionView();
		const next = view ? selectionFills(view, this.renderedRows(), this.cellMetrics().cellWidth) : new Map<HTMLElement, string>();
		for (const element of this.filled.keys()) {
			if (!next.has(element)) element.style.backgroundImage = "";
		}
		for (const [element, image] of next) {
			if (this.filled.get(element) !== image) element.style.backgroundImage = image;
		}
		this.filled = next;
	}

	private renderedRows(): RenderedRow[] {
		return renderedRows(this.altRoot, this.filteredBlocks, this.blockElements, this.paintedFirstStableRow);
	}

	private updateStickiness(): void {
		const container = this.container;
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

	private applyStickiness(): void {
		const container = this.container;
		if (!container || !this.stickToBottom) return;
		const target = container.scrollHeight - container.clientHeight;
		if (target <= 0) return;
		if (container.scrollTop < target - 0.5) {
			container.scrollTop = target;
		}
	}

	private ensureBlockElement(block: BlockView): { element: HTMLElement; pooled: boolean; away: Set<number> | null } {
		const existing = this.blockElements.get(block.id);
		if (existing) return { element: existing, pooled: false, away: null };
		const pooled = this.pool.take(block.id);
		if (pooled) {
			const away = this.pooledDirty.get(block.id) ?? null;
			this.pooledDirty.delete(block.id);
			pooled.setAttribute("style", styleVarsString(this.theme, this.font));
			this.blockElements.set(block.id, pooled);
			return { element: pooled, pooled: true, away };
		}
		const section = document.createElement("section");
		section.className = CLASS_BLOCK;
		section.dataset.terminalBlockId = block.id;
		section.setAttribute("style", styleVarsString(this.theme, this.font));
		this.blockElements.set(block.id, section);
		return { element: section, pooled: false, away: null };
	}

	private cellMetrics(): { cellWidth: number; cellHeight: number } {
		const { cellWidth, cellHeight } = this.measure();
		return { cellWidth: cellWidth > 0 ? cellWidth : this.font.sizePx * 0.6, cellHeight: cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx };
	}

	private ensureAltRoot(container: HTMLElement): HTMLElement {
		if (this.altRoot) return this.altRoot;
		const root = document.createElement("div");
		root.setAttribute("data-terminal-alt-surface", "");
		root.classList.add("terminal-alt-surface");
		root.setAttribute("style", styleVarsString(this.theme, this.font));
		container.append(root);
		this.altRoot = root;
		return root;
	}
}

function applyScrollOverflow(container: HTMLElement): void {
	container.style.overflowX = "hidden";
	container.style.overflowY = "auto";
	container.style.setProperty("overscroll-behavior-y", "none");
}

function ensurePackageStyleTag(): HTMLStyleElement {
	const existing = document.head.querySelector<HTMLStyleElement>("style[data-terminal-package]");
	if (existing) {
		// Refresh rather than skip: under HMR the module re-evaluates with new CSS
		// while the previous version's tag survives, leaving current markup styled
		// by a stale stylesheet.
		const current = terminalStylesForDocument();
		if (existing.textContent !== current) existing.textContent = current;
		return existing;
	}
	const tag = document.createElement("style");
	tag.setAttribute("data-terminal-package", "renderer-dom");
	tag.textContent = terminalStylesForDocument();
	document.head.append(tag);
	return tag;
}
