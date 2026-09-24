import {
	defaultStrings,
	validateRowRange,
	type BlockId,
	type BlockRenderer,
	type BlockView,
	type FontConfig,
	type RowRange,
	type SecretPattern,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { renderAltSurface } from "./alt-surface.js";
import { documentHidden, type BlockFinishedEvent } from "./block-finished.js";
import { reconcileChildren } from "./block-body.js";
import { FinishedBlockTracker, shownToUser } from "./finished-block-tracker.js";
import { BlockElementCache, shownBlocks } from "./block-element-cache.js";
import { blockLayout, CellMeasurer, cellMetricsFor, rowHeightFor } from "./cell-measurer.js";
import { createCursorElement, cursorPaintFor, primaryCursorPlacement, PLAIN_CURSOR_PAINT, type CursorPlacement } from "./cursor.js";
import { type KeyDescriptor } from "./prediction.js";
import { EchoPredictor, snapshotCursorPoint, snapshotRowCells } from "./echo-predictor.js";
import { RttMeter } from "./rtt.js";
import { type BlockFilter } from "./block-filter.js";
import { updatePinnedHeader } from "./pinned-header.js";
import { DEFAULT_FEATURES, resolveFeatures, sameFeatures, type RendererFeatures } from "./features.js";
import { defaultFont } from "./default-font.js";
import { BLOCK_PADDING_X_PX, BLOCK_PADDING_TOP_LINES, blockPaddingY } from "./block-metrics.js";
import { paintedRowOrigin, type RowOrigin } from "./row-geometry.js";
import { pointAtFromRows } from "./selection-geometry.js";
import { type SelectionKind, type SelectionPoint } from "./selection-model.js";
import { type TextRows } from "./selection-text.js";
import { type DetectedLink, type LinkProvider } from "./link-providers.js";
import { type HintEvent } from "./hint-mode.js";
import { DEFAULT_HINT_RULES, type HintRule } from "./hint-rules.js";
import { renderedRows, snapshotTextRows, type RenderedRow } from "./selection-view.js";
import { styleVarsString } from "./style-vars.js";
import { warpDarkTheme } from "./theme-warp.js";
import {
	applyStyleVars,
	createAltRoot,
	createRendererChrome,
	releaseContainer,
	showAltRoot,
	showBlockList,
	type RendererChrome,
} from "./renderer-chrome.js";
import { RendererOverlays } from "./renderer-overlays.js";
import { RendererSelection } from "./renderer-selection.js";
import { ScrollTracker, type ScrollAnchor } from "./scroll-tracker.js";
import { wireRenderer, type RendererWiring } from "./renderer-wiring.js";
import { ListenerSet } from "./listener-set.js";
import { tooSoonToPaint } from "./frame-budget.js";

const OVERSCAN_ROWS = 6;
export const HIDDEN_TICK_MS = 100;
export const HIDDEN_DRAIN_MS = 250;
const POOL_CAPACITY_FACTOR = 3;
export { ALT_BLOCK_ID } from "./selection-view.js";
export type { ScrollAnchor } from "./scroll-tracker.js";

export class DomBlockRenderer implements BlockRenderer {
	private container: HTMLElement | null = null;
	private core: TerminalCore | null = null;
	private chrome: RendererChrome | null = null;
	private altRoot: HTMLElement | null = null;
	private theme: TerminalTheme = warpDarkTheme;
	private font: FontConfig = defaultFont();
	private wiring: RendererWiring | null = null;
	private readonly elements = new BlockElementCache();
	private rafHandle: number | null = null;
	private readonly paintListeners = new ListenerSet();
	private knownBlockId: BlockId | null = null;
	private lastPaintAt: number | null = null;
	private wasAltActive = false;
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });
	private filteredBlocks: readonly BlockView[] = [];
	private currentFilter: BlockFilter | null = null;
	private readonly measurer = new CellMeasurer(() => this.invalidateMetrics());
	private paintedFirstStableRow = 0;
	private cursorElement: HTMLElement | null = null;
	private rebuildAll = false;
	private activeFeatures: RendererFeatures = DEFAULT_FEATURES;
	private focused = true;
	private hostVisible: boolean | null = null;
	private catchUp = false;
	private hiddenTimer: ReturnType<typeof setTimeout> | null = null;
	private readonly onVisibilityChange = () => {
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		if (this.hiddenTimer !== null) clearTimeout(this.hiddenTimer), (this.hiddenTimer = null);
		this.scheduleRepaint();
	};
	private readonly finished = new FinishedBlockTracker();
	private readonly scroll = new ScrollTracker({
		container: () => this.container,
		blocks: () => this.filteredBlocks,
		layout: () => this.layout(),
		paintedFirstStableRow: () => this.paintedFirstStableRow,
	});
	private readonly selection = new RendererSelection({
		hasCore: () => this.core !== null,
		textRows: () => this.overlays.textRows(),
		renderedRows: () => this.renderedRows(),
		cellWidth: () => this.cellMetrics().cellWidth,
	});
	private readonly overlays = new RendererOverlays({
		container: () => this.container,
		painting: () => this.painting(),
		rawTextRows: () => this.rawTextRows(),
		renderedRows: () => this.renderedRows(),
		cellMetrics: () => this.cellMetrics(),
	});
	private readonly rtt = new RttMeter();
	private readonly echo = new EchoPredictor(this.rtt, {
		painting: () => this.painting(),
		cursorPoint: () => (this.core ? snapshotCursorPoint(this.core.snapshot()) : null),
		rowCellsAt: (row) => snapshotRowCells(this.core!.snapshot(), row, this.decoder),
		layer: () => this.overlays.layer("predictions"),
		container: () => this.container,
		altShowing: () => this.core?.snapshot().altScreen != null && this.altRoot != null && !this.altRoot.hidden,
		cellMetrics: () => this.cellMetrics(),
	});
	private echoThresholdMs: number | null = null;

	mount(container: HTMLElement, core: TerminalCore): void {
		const visible = this.hostVisible;
		this.dispose();
		this.hostVisible = visible;
		this.container = container;
		this.core = core;
		const chrome = createRendererChrome(container, styleVarsString(this.theme, this.font));
		this.chrome = chrome;
		this.overlays.decorationLayer = chrome.decorations;
		this.measurer.attach();
		this.wiring = wireRenderer(container, core, {
			onScroll: () => {
				this.scroll.updateStickiness();
				if (!this.scroll.stickToBottom) this.scroll.captureAnchor();
				this.scheduleRepaint();
			},
			onRowRemap: (remap) => this.scroll.remapAnchor(remap),
			onChange: () => {
				this.echo.noteReceived(performance.now());
				this.scheduleRepaint();
			},
			onVisibilityChange: this.onVisibilityChange,
			getBlocks: () => this.filteredBlocks,
			scrollToBlock: (id, align) => this.scrollToBlock(id, align),
			setFilter: (f) => this.setFilter(f),
			scheduleRepaint: () => this.scheduleRepaint(),
			getCellHeight: () => this.measure().cellHeight,
			getStickToBottom: () => this.scroll.stickToBottom,
			scrollToLatest: () => this.scrollToLatest(),
		});
		if (this.painting()) this.repaint();
		else this.settleHidden(false);
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

	setVisible(visible: boolean | null): void {
		const wasPainting = this.painting();
		this.hostVisible = visible;
		if (!this.painting() || wasPainting) return;
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		this.core?.drain();
		this.core?.tick(Date.now());
		this.repaint(performance.now());
	}

	visibility(): boolean | null {
		return this.hostVisible;
	}

	setFilter(filter: BlockFilter | null): void {
		this.currentFilter = filter, this.scheduleRepaint();
	}

	invalidate(range: RowRange): void {
		validateRowRange(range);
		this.scheduleRepaint();
	}

	measure(): { cellWidth: number; cellHeight: number } {
		return this.measurer.measure(this.font);
	}

	private invalidateMetrics(): void {
		this.measurer.invalidate();
		this.scheduleRepaint();
	}

	// The space a block reserves around its rows. A grid sized to the host rather
	// than to this is told it has more columns than a row can actually show, so
	// full-width lines overflow and the pane grows a horizontal scrollbar.
	blockContentInset(): { x: number; y: number } {
		const rowHeight = rowHeightFor(this.measure().cellHeight, this.font);
		return { x: BLOCK_PADDING_X_PX * 2, y: blockPaddingY(rowHeight) };
	}

	rowOrigin(row: number): RowOrigin | null {
		return paintedRowOrigin(
			this.filteredBlocks,
			this.elements.blockElements,
			row,
			this.cellMetrics().cellHeight,
			this.paintedFirstStableRow,
		);
	}

	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void {
		this.elements.scrollTo(id, align, this.knownBlockId);
	}

	scrollToLatest(): void {
		const c = this.container;
		if (!c) return;
		this.scroll.stickToLatest(c);
		this.scheduleRepaint();
	}

	scrollAnchor(): ScrollAnchor | null {
		return this.scroll.scrollAnchor();
	}

	private layout(): { rowHeight: number; headerHeight: number; paddingY: number } {
		return blockLayout(this.measure().cellHeight, this.font);
	}

	pointAt(x: number, y: number): SelectionPoint | null {
		const { cellWidth, cellHeight } = this.cellMetrics();
		const boxes = this.renderedRows().map((row) => row.box);
		return pointAtFromRows(boxes, x, y, cellWidth, cellHeight);
	}

	selectionBegin(point: SelectionPoint, kind: SelectionKind): void {
		this.selection.begin(point, kind);
	}

	selectionUpdate(point: SelectionPoint): void {
		this.selection.update(point);
	}

	selectionClear(): void {
		this.selection.clear();
	}

	hasSelection(): boolean {
		return this.selection.view() !== null;
	}

	selectedText(): string | null {
		return this.selection.text();
	}

	onSelectionChange(listener: () => void): () => void {
		return this.selection.onChange(listener);
	}

	private rawTextRows(): TextRows {
		const core = this.core!;
		return snapshotTextRows(core.snapshot(), this.currentFilter, this.decoder, (id) => core.linkUri(id));
	}

	hoverAt(x: number, y: number): void {
		if (!this.core) return;
		this.overlays.hover(this.pointAt(x, y));
	}

	clearHover(): void {
		this.overlays.hover(null);
	}

	hoveredLink(): DetectedLink | null {
		return this.overlays.hoveredLink();
	}

	onLinkHover(listener: (link: DetectedLink | null) => void): () => void {
		return this.overlays.onLinkHover(listener);
	}

	setLinkProviders(providers: readonly LinkProvider[]): void {
		this.overlays.setLinkProviders(providers);
	}

	hintBegin(rules: readonly HintRule[] = DEFAULT_HINT_RULES): number {
		if (!this.core) return 0;
		return this.overlays.hintBegin(rules);
	}

	hintType(character: string): HintEvent | null {
		return this.overlays.hintType(character);
	}

	hintBackspace(): void {
		this.overlays.hintBackspace();
	}

	hintCancel(): void {
		this.overlays.hintCancel();
	}

	hintActive(): boolean {
		return this.overlays.hintActive();
	}

	setSecretPatterns(patterns: readonly SecretPattern[]): void {
		this.overlays.setSecretPatterns(patterns);
		this.scheduleRepaint();
	}

	revealSecretAt(x: number, y: number): void {
		if (!this.overlays.hasSecrets()) return;
		const point = this.pointAt(x, y);
		if (!point) return;
		if (this.overlays.revealSecretAt(point, () => this.core?.snapshot().generation)) this.scheduleRepaint();
	}

	setPredictiveEcho(config: { thresholdMs: number } | null): void {
		this.echoThresholdMs = config?.thresholdMs ?? null;
		if (this.echoThresholdMs === null) this.predictionsClear();
	}

	noteSend(nowMs: number): void {
		this.echo.noteSend(nowMs);
	}

	noteRoundTrip(sentMs: number, receivedMs: number): void {
		this.rtt.sent(sentMs);
		this.rtt.received(receivedMs);
	}

	predictKey(key: KeyDescriptor, nowMs: number): boolean {
		return this.echo.predictKey(key, nowMs, this.echoThresholdMs);
	}

	predictionsClear(): void {
		this.echo.clear();
	}

	predictionCount(): number {
		return this.echo.pending().length;
	}

	dispose(): void {
		document.removeEventListener("visibilitychange", this.onVisibilityChange);
		if (this.hiddenTimer !== null) clearTimeout(this.hiddenTimer), (this.hiddenTimer = null);
		this.hostVisible = null;
		this.catchUp = false;
		this.echo.cancelTimer();
		this.wiring?.teardown(), (this.wiring = null);
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		this.paintListeners.clear();
		this.finished.reset();
		this.overlays.dispose();
		if (this.container) releaseContainer(this.container);
		this.container = null;
		this.core = null;
		this.chrome = null;
		this.altRoot = null;
		this.elements.reset();
		this.cursorElement?.remove();
		this.cursorElement = null;
		this.rebuildAll = false;
		this.knownBlockId = null;
		this.scroll.reset();
		this.paintedFirstStableRow = 0;
		this.lastPaintAt = null;
		this.wasAltActive = false;
		this.selection.reset();
		this.measurer.reset();
	}

	/// Notifies when a repaint has actually landed in the DOM.
	///
	/// The bench harness needs this to time the same work xterm's `onRender`
	/// covers. Without it a caller can only wait for a bare animation frame,
	/// which fires whether or not anything painted.
	onPaint(listener: () => void): () => void {
		return this.paintListeners.add(listener);
	}

	onBlockFinished(listener: (event: BlockFinishedEvent) => void): () => void {
		return this.finished.onBlockFinished(listener);
	}

	private scheduleRepaint(): void {
		if (this.rafHandle !== null || this.hiddenTimer !== null) return;
		if (documentHidden()) {
			this.hiddenTimer = setTimeout(() => this.hiddenTick(), HIDDEN_TICK_MS);
			return;
		}
		if (typeof requestAnimationFrame !== "function") {
			if (this.painting()) this.repaint();
			else this.settleHidden(false);
			return;
		}
		this.rafHandle = requestAnimationFrame((timestamp) => this.repaintOnFrame(timestamp));
	}

	private hiddenTick(): void {
		this.hiddenTimer = null;
		const core = this.core;
		if (!core) return;
		core.drain(HIDDEN_DRAIN_MS);
		core.tick(Date.now());
		this.settleHidden();
	}

	private repaintOnFrame(timestamp: number): void {
		if (this.painting() && tooSoonToPaint(timestamp, this.lastPaintAt)) {
			this.rafHandle = requestAnimationFrame((nextTimestamp) =>
				this.repaintOnFrame(nextTimestamp),
			);
			return;
		}
		this.core?.drain();
		this.core?.tick(Date.now());
		this.rafHandle = null;
		if (!this.painting()) {
			this.settleHidden();
			return;
		}
		this.repaint(timestamp);
	}

	private painting(): boolean {
		return this.hostVisible !== false;
	}

	private settleHidden(reschedule = true): void {
		const core = this.core;
		if (!core || !this.container) return;
		this.echo.dropWhileHidden(this.hostVisible, () => this.predictionsClear());
		this.finished.detect(core.snapshot(), () => shownToUser(this.hostVisible, this.container));
		core.takeDirty();
		this.catchUp = true;
		if (reschedule) this.rescheduleIfPending(core);
	}

	private applyStyleVars(): void {
		const parts = { container: this.container, blockElements: this.elements.blockElements.values(), altRoot: this.altRoot, decorationLayer: this.overlays.decorationLayer };
		applyStyleVars(parts, this.theme, this.font);
	}

	private repaint(paintedAt?: number): void {
		if (this.catchUp) {
			this.rebuildAll = true;
			this.catchUp = false;
		}
		const core = this.core;
		const container = this.container;
		const chrome = this.chrome;
		if (!core || !container || !chrome) {
			return;
		}
		const { list, leading, trailing } = chrome;
		const anchor = this.scrollAnchor();
		const firstRow = Math.max(0, this.scroll.flatRowFor(anchor) - OVERSCAN_ROWS);
		core.setExportWindow(firstRow, firstRow + this.scroll.visibleRowCapacity() + 2 * OVERSCAN_ROWS);
		const snapshot = core.snapshot();
		this.overlays.noteGeneration(snapshot.generation);

		const alt = snapshot.altScreen;
		if (alt) {
			if (!this.wasAltActive) {
				this.selection.drop();
				this.wasAltActive = true;
			}
			showAltRoot(container, chrome, () => this.ensureAltRoot(container), styleVarsString(this.theme, this.font));
			renderAltSurface(alt, this.altRoot!, this.decoder, this.cellMetrics(), this.activeFeatures, this.measurer.widths);
			this.finishPaint(paintedAt);
			core.takeDirty();
			this.rescheduleIfPending(core);
			return;
		}
		showBlockList(container, chrome, this.altRoot);
		if (this.wasAltActive) this.selection.drop();
		this.wasAltActive = false;

		const blocks = this.finished.detect(snapshot, () => shownToUser(this.hostVisible, this.container));
		if (blocks.length > 0) {
			this.knownBlockId = blocks[0]!.id;
		}
		this.selection.dropUnlessShown(blocks);
		const cursor: CursorPlacement | null = primaryCursorPlacement(snapshot);
		const cursorPaint = cursor
			? cursorPaintFor({ source: snapshot, row: cursor.row, column: cursor.column, theme: this.theme, features: this.activeFeatures, focused: this.focused, decoder: this.decoder })
			: PLAIN_CURSOR_PAINT;
		const dirty = core.takeDirty();
		this.elements.startPaint(dirty, this.rebuildAll, snapshot.generation);
		this.rebuildAll = false;
		const firstScreenStable = snapshot.firstStableRow + snapshot.historyRows;
		const pooledThisPaint = new Map<BlockId, Set<number> | null>();
		const freshFor = this.elements.freshness(dirty.rows, pooledThisPaint, firstScreenStable);
		const cursorElement = this.cursorElement ?? (this.cursorElement = createCursorElement(0, 0));
		this.filteredBlocks = shownBlocks(snapshot, blocks, this.currentFilter);
		const { cellWidth } = this.measure();
		this.paintedFirstStableRow = snapshot.firstStableRow;
		const layout = this.layout();
		const { rowHeight } = layout;
		const { scrollTop, windowResult } = this.scroll.frame(container, snapshot.firstStableRow, layout, OVERSCAN_ROWS);

		leading.style.height = `${windowResult.leadingSpacer}px`;
		trailing.style.height = `${windowResult.trailingSpacer}px`;
		if (this.wiring) this.wiring.blockNav.setPinnedIndex(windowResult.pinnedBlockIndex);

		const body = { snapshot, rowHeight, cellWidth, cursor, cursorElement, cursorPaint, decoder: this.decoder, firstStableRow: snapshot.firstStableRow, generation: snapshot.generation, features: this.activeFeatures, widths: this.measurer.widths };
		const style = () => styleVarsString(this.theme, this.font);
		const { visibleIds, orderedVisible, cursorPlaced } = this.elements.populateWindow(this.filteredBlocks, windowResult, freshFor, pooledThisPaint, style, body);
		if (!cursorPlaced) cursorElement.remove();

		reconcileChildren(list, [leading, ...orderedVisible, trailing]);
		const first = orderedVisible[0];
		const scrolledPastHeader = first && first.getBoundingClientRect().top + rowHeight * (BLOCK_PADDING_TOP_LINES + 2) + 1 < container.getBoundingClientRect().top;
		updatePinnedHeader(chrome.pinned, this.filteredBlocks, scrolledPastHeader ? windowResult.firstBlock : -1, defaultStrings);

		const capacity = POOL_CAPACITY_FACTOR * Math.max(1, orderedVisible.length);
		this.elements.poolHidden(visibleIds, dirty.rows, capacity);
		this.scroll.settle(container, scrollTop);
		this.finishPaint(paintedAt);
		this.rescheduleIfPending(core);
	}

	private finishPaint(paintedAt: number | undefined): void {
		this.selection.paintFill();
		this.overlays.refreshLinks();
		this.overlays.paintDecorations();
		this.overlays.paintHints();
		this.overlays.paintRedactions();
		this.echo.reconcile();
		if (paintedAt !== undefined) this.lastPaintAt = paintedAt;
		this.paintListeners.emit();
	}

	private rescheduleIfPending(core: TerminalCore): void {
		if (core.hasBacklog() || core.synchronizedOutput()) this.scheduleRepaint();
	}

	private renderedRows(): RenderedRow[] {
		return renderedRows(this.altRoot, this.filteredBlocks, this.elements.blockElements, this.paintedFirstStableRow);
	}

	private cellMetrics(): { cellWidth: number; cellHeight: number } {
		return cellMetricsFor(this.measure(), this.font);
	}

	private ensureAltRoot(container: HTMLElement): HTMLElement {
		if (this.altRoot) return this.altRoot;
		const root = createAltRoot(container, styleVarsString(this.theme, this.font));
		this.altRoot = root;
		return root;
	}
}
