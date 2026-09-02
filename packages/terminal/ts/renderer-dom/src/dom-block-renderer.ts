import {
	decodeBlocks,
	defaultStrings,
	validateRowRange,
	type BlockId,
	type BlockRenderer,
	type BlockView,
	type FontConfig,
	type HostCapabilities,
	type RowRange,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { renderAltSurface } from "./alt-surface.js";
import { renderBlockActions, type BlockTextSource } from "./block-actions.js";
import { bindActionEvents } from "./action-events.js";
import { renderBlockHeader } from "./block-header.js";
import { applyFilter, type BlockFilter } from "./block-filter.js";
import { mountBlockNavFromRenderer, type BlockNavHandle } from "./block-nav.js";
import { mountJumpToBottom, type JumpToBottom } from "./jump-to-bottom.js";
import { createPinnedHeaderElement, updatePinnedHeader } from "./pinned-header.js";
import { buildRowNode, type RowSource } from "./row-builder.js";
import { selectionToBlockRange } from "./selection.js";
import { ensureMeasureHost, HIDDEN_MEASURE_ID, listenScroll } from "./host-dom.js";
import { blockPaddingY } from "./block-metrics.js";
import { styleVarEntries, styleVarsString } from "./style-vars.js";
import { terminalStylesForDocument } from "./styles.js";
import { warpDarkTheme } from "./theme-warp.js";
import { computeWindow, type RowWindow } from "./viewport.js";

const CLASS_BLOCK = "terminal-block";
const CLASS_LEADING_SPACER = "terminal-spacer";
const CLASS_TRAILING_SPACER = "terminal-spacer";
const DEFAULT_HEADER_HEIGHT = 24;
const OVERSCAN_ROWS = 6;
const STICK_THRESHOLD_PX = 4;
const PAINT_INTERVAL_MS = 1000 / 60;
const FRAME_EPSILON_MS = 0.25;

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
	private host: HostCapabilities | null = null;
	private latestSnapshot: {
		content: Uint8Array;
		rows: Uint32Array;
		runRanges: Uint32Array;
		stylePairs: Uint32Array;
	} | null = null;
	private latestBlocks: readonly BlockView[] = [];
	private filteredBlocks: readonly BlockView[] = [];
	private currentFilter: BlockFilter | null = null;
	private pinnedHeader: HTMLElement | null = null;
	private blockNav: BlockNavHandle | null = null;
	private jumpToBottom: JumpToBottom | null = null;

	mount(container: HTMLElement, core: TerminalCore): void {
		this.dispose();
		this.container = container;
		this.core = core;
		ensurePackageStyleTag();
		container.style.position = "relative";
		container.style.overflow = "auto";
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
			this.scheduleRepaint();
		});
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
	}

	setFont(font: FontConfig): void {
		this.font = font;
		this.applyStyleVars();
	}

	setFilter(filter: BlockFilter | null): void {
		this.currentFilter = filter, this.scheduleRepaint();
	}

	setHostCapabilities(host: HostCapabilities | null): void {
		this.host = host;
		this.scheduleRepaint();
	}

	invalidate(range: RowRange): void {
		validateRowRange(range);
		this.scheduleRepaint();
	}

	measure(): { cellWidth: number; cellHeight: number } {
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
		return { cellWidth, cellHeight };
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
		const target = c.scrollHeight - c.clientHeight;
		if (target > 0) c.scrollTop = target;
		this.scheduleRepaint();
	}

	getSelectionRange(): import("./selection.js").BlockRange | null {
		const root = this.container;
		if (!root) return null;
		const doc = root.ownerDocument ?? (typeof document !== "undefined" ? document : null);
		if (!doc) return null;
		const selection = doc.getSelection ? doc.getSelection() : null;
		if (!selection) return null;
		return selectionToBlockRange(root, selection);
	}

	dispose(): void {
		this.jumpToBottom?.dispose(), (this.jumpToBottom = null);
		this.blockNav?.dispose(), (this.blockNav = null);
		if (this.unsubscribe) this.unsubscribe(), (this.unsubscribe = null);
		if (this.scrollUnsubscribe) this.scrollUnsubscribe(), (this.scrollUnsubscribe = null);
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		this.paintListeners.clear();
		if (this.container) {
			this.container.replaceChildren();
			this.container.style.removeProperty("position");
			this.container.style.removeProperty("overflow");
			this.container.style.removeProperty("contain");
		}
		this.container = null;
		this.core = null;
		this.list = null;
		this.altRoot = null;
		this.leadingSpacer = null;
		this.trailingSpacer = null;
		this.pinnedHeader = null;
		this.blockElements.clear();
		this.measureNode = null;
		this.knownBlockId = null;
		this.stickToBottom = true;
		this.lastClientHeight = 0;
		this.lastPaintAt = null;
		this.wasAltActive = false;
		this.host = null;
		this.latestSnapshot = null;
		this.latestBlocks = [];
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
		const snapshot = core.snapshot();

		const alt = snapshot.altScreen;
		if (alt) {
			if (!this.wasAltActive) {
				this.clearBlockSelection();
				this.wasAltActive = true;
			}
			container.style.overflow = "hidden";
			container.scrollTop = 0;
			const altRoot = this.ensureAltRoot(container);
			altRoot.setAttribute("style", styleVarsString(this.theme, this.font));
			altRoot.hidden = false;
			if (this.list) this.list.hidden = true;
			if (this.pinnedHeader) this.pinnedHeader.hidden = true;
			renderAltSurface(alt, this.altRoot!, this.decoder, this.cellMetrics());
			if (paintedAt !== undefined) this.lastPaintAt = paintedAt;
			this.notifyPainted();
			return;
		}
		if (this.altRoot) {
			this.altRoot.hidden = true;
		}
		if (this.list) this.list.hidden = false;
		container.style.overflow = "auto";
		this.wasAltActive = false;

		const blocks = decodeBlocks(snapshot);
		if (blocks.length > 0) {
			this.knownBlockId = blocks[0]!.id;
		}
		this.latestSnapshot = {
			content: snapshot.content,
			rows: snapshot.rows,
			runRanges: snapshot.runRanges,
			stylePairs: snapshot.stylePairs,
		};
		this.latestBlocks = blocks;
		this.filteredBlocks = applyFilter(blocks, this.currentFilter);
		const { cellHeight } = this.measure();
		const rowHeight = cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx;
		const anchorScrollTop = container.scrollTop;
		const scrollTop = this.stickToBottom ? Number.MAX_SAFE_INTEGER : anchorScrollTop;
		const viewportHeight = container.clientHeight || 1;
		this.lastClientHeight = container.clientHeight;
		const windowResult = computeWindow({
			blocks: this.filteredBlocks,
			scrollTop,
			viewportHeight,
			rowHeight,
			headerHeight: DEFAULT_HEADER_HEIGHT,
			overscanRows: OVERSCAN_ROWS,
			blockPaddingY: blockPaddingY(rowHeight),
		});

		leading.style.height = `${windowResult.leadingSpacer}px`;
		trailing.style.height = `${windowResult.trailingSpacer}px`;
		if (this.blockNav) this.blockNav.setPinnedIndex(windowResult.pinnedBlockIndex);
		if (this.pinnedHeader) updatePinnedHeader(this.pinnedHeader, this.filteredBlocks, windowResult.pinnedBlockIndex, defaultStrings);

		const textSource: BlockTextSource = this.buildTextSource();
		const visibleIds = new Set<BlockId>();
		if (windowResult.firstBlock <= windowResult.lastBlock) {
			for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
				const block = this.filteredBlocks[i]!;
				visibleIds.add(block.id);
				const element = this.ensureBlockElement(block);
				const rowWindow = windowResult.rowWindows.get(i) ?? null;
				populateBlock(
					element,
					block,
					snapshot,
					rowWindow,
					rowHeight,
					this.decoder,
					this.host,
					textSource,
				);
			}
		}

		const orderedVisible: HTMLElement[] = [];
		for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
			const block = this.filteredBlocks[i]!;
			const element = this.blockElements.get(block.id);
			if (element) orderedVisible.push(element);
		}
		const fragment = document.createDocumentFragment();
		fragment.append(leading, ...orderedVisible, trailing);
		list.replaceChildren(fragment);

		for (const [id, element] of this.blockElements) {
			if (!visibleIds.has(id)) {
				element.replaceChildren();
				this.blockElements.delete(id);
			}
		}
		if (this.stickToBottom) {
			this.applyStickiness();
		} else if (Math.abs(container.scrollTop - anchorScrollTop) > 0.5) {
			container.scrollTop = anchorScrollTop;
		}
		if (paintedAt !== undefined) this.lastPaintAt = paintedAt;
		this.notifyPainted();
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
	}

	private applyStickiness(): void {
		const container = this.container;
		if (!container || !this.stickToBottom) return;
		const target = container.scrollHeight - container.clientHeight;
		if (target <= 0) return;
		if (Math.abs(container.scrollTop - target) > 0.5) {
			container.scrollTop = target;
		}
	}

	private buildTextSource(): BlockTextSource {
		const snapshot = this.latestSnapshot;
		const blocks = this.latestBlocks;
		const decoder = this.decoder;
		const blockById = new Map(blocks.map((b) => [b.id, b] as const));
		return {
			command: (id) => blockById.get(id)?.command ?? "",
			output: (id) => {
				const block = blockById.get(id);
				if (!block || !snapshot) return "";
				return readBlockOutput(block, snapshot, decoder);
			},
		};
	}

	private ensureBlockElement(block: BlockView): HTMLElement {
		const existing = this.blockElements.get(block.id);
		if (existing) return existing;
		const section = document.createElement("section");
		section.className = CLASS_BLOCK;
		section.dataset.terminalBlockId = block.id;
		section.setAttribute("style", styleVarsString(this.theme, this.font));
		this.blockElements.set(block.id, section);
		return section;
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

	private clearBlockSelection(): void {
		const root = this.container;
		if (!root) return;
		const doc = root.ownerDocument ?? (typeof document !== "undefined" ? document : null);
		if (!doc) return;
		const selection = doc.getSelection ? doc.getSelection() : null;
		if (!selection) return;
		if (selection.rangeCount === 0) return;
		selection.removeAllRanges();
	}
}

function defaultFont(): FontConfig {
	return {
		family: "ui-monospace, Menlo, Monaco, Consolas, monospace",
		sizePx: 14,
		lineHeight: 1.2,
		weight: 400,
		letterSpacingPx: 0,
		ligatures: false,
	};
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


function populateBlock(
	section: HTMLElement,
	block: BlockView,
	snapshot: {
		content: Uint8Array;
		rows: Uint32Array;
		runRanges: Uint32Array;
		stylePairs: Uint32Array;
	},
	rowWindow: RowWindow | null,
	rowHeight: number,
	decoder: TextDecoder,
	host: HostCapabilities | null,
	textSource: BlockTextSource,
): void {
	const fragment = document.createDocumentFragment();
	fragment.append(renderBlockHeader(block, defaultStrings));
	if (host) {
		fragment.append(renderBlockActions(block, host, defaultStrings, textSource));
	}
	const source: RowSource = snapshot;
	const blockFirstRow = block.firstRow;
	const firstRow = rowWindow ? rowWindow.firstRow : 0;
	const lastRow = rowWindow ? rowWindow.lastRow : block.rowCount - 1;
	if (rowWindow && firstRow > 0) {
		fragment.append(spacerOf(firstRow * rowHeight));
	}
	for (let rowOffset = firstRow; rowOffset <= lastRow; rowOffset += 1) {
		const rowNode = buildRowNode(source, blockFirstRow + rowOffset, rowOffset, decoder);
		fragment.append(rowNode);
	}
	if (rowWindow) {
		const trailingRows = block.rowCount - 1 - lastRow;
		if (trailingRows > 0) {
			fragment.append(spacerOf(trailingRows * rowHeight));
		}
	}
	section.replaceChildren(fragment);
}

function spacerOf(height: number): HTMLElement {
	const spacer = document.createElement("div");
	spacer.className = CLASS_LEADING_SPACER;
	spacer.dataset.terminalRowSpacer = "true";
	spacer.style.height = `${height}px`;
	return spacer;
}

function readBlockOutput(
	block: BlockView,
	snapshot: {
		content: Uint8Array;
		rows: Uint32Array;
	},
	decoder: TextDecoder,
): string {
	const lines: string[] = [];
	for (let rowOffset = 0; rowOffset < block.rowCount; rowOffset += 1) {
		const snapshotRowIndex = block.firstRow + rowOffset;
		const rowsBase = snapshotRowIndex * 2;
		const rowContentStart = snapshot.rows[rowsBase] ?? 0;
		const rowContentEnd = snapshot.rows[rowsBase + 1] ?? rowContentStart;
		const rowLength = rowContentEnd - rowContentStart;
		if (rowLength <= 0) {
			lines.push("");
			continue;
		}
		const slice = snapshot.content.subarray(rowContentStart, rowContentEnd);
		lines.push(decoder.decode(slice));
	}
	return lines.join("\n");
}
