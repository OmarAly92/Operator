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
import { renderBlockActions, type BlockTextSource } from "./block-actions.js";
import { renderBlockHeader } from "./block-header.js";
import { selectionToBlockRange } from "./selection.js";
import { styleCodeToCssVar } from "./style-code.js";
import { terminalStyles } from "./styles.js";
import { computeWindow, type RowWindow } from "./viewport.js";

const CLASS_BLOCK = "terminal-block";
const CLASS_ROW = "terminal-row";
const CLASS_RUN = "terminal-run";
const CLASS_LEADING_SPACER = "terminal-spacer";
const CLASS_TRAILING_SPACER = "terminal-spacer";
const HIDDEN_MEASURE_ID = "terminal-m-measure";
const DEFAULT_HEADER_HEIGHT = 24;
const OVERSCAN_ROWS = 6;
const STICK_THRESHOLD_PX = 4;
const FRAME_MS = 4;

export const warpDarkTheme: TerminalTheme = {
	ansi: [
		"#616161", "#ff8272", "#b4fa72", "#fefdc2",
		"#a5d5fe", "#ff8ffd", "#d0d1fe", "#f1f1f1",
		"#8e8e8e", "#ffc4bd", "#d6fcb9", "#fefdd5",
		"#c1e3fe", "#ffb1fe", "#e5e6fe", "#feffff",
	],
	foreground: "#ffffff",
	background: "#000000",
	cursor: "#00c2ff",
	selection: "rgb(0 194 255 / 0.35)",
	blockBackground: "#000000",
	blockBorder: "#616161",
	blockHeaderForeground: "#f1f1f1",
};

export class DomBlockRenderer implements BlockRenderer {
	private container: HTMLElement | null = null;
	private core: TerminalCore | null = null;
	private list: HTMLElement | null = null;
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
	private lastPaintAt = Number.NEGATIVE_INFINITY;
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });
	private host: HostCapabilities | null = null;
	private latestSnapshot: {
		content: Uint8Array;
		rows: Uint32Array;
		runRanges: Uint32Array;
		stylePairs: Uint32Array;
	} | null = null;
	private latestBlocks: readonly BlockView[] = [];

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
		this.measureHost = ensureMeasureHost();
		this.measureNode = this.measureHost.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		this.scrollUnsubscribe = listenScroll(container, () => {
			this.updateStickiness();
			this.scheduleRepaint();
		});
		this.unsubscribe = core.onChange(() => this.scheduleRepaint());
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
		if (this.unsubscribe) {
			this.unsubscribe();
			this.unsubscribe = null;
		}
		if (this.scrollUnsubscribe) {
			this.scrollUnsubscribe();
			this.scrollUnsubscribe = null;
		}
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") {
			cancelAnimationFrame(this.rafHandle);
		}
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
		this.leadingSpacer = null;
		this.trailingSpacer = null;
		this.blockElements.clear();
		this.measureNode = null;
		this.knownBlockId = null;
		this.stickToBottom = true;
		this.lastPaintAt = Number.NEGATIVE_INFINITY;
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
		if (this.now() - this.lastPaintAt >= FRAME_MS) {
			this.repaint();
			return;
		}
		this.rafHandle = requestAnimationFrame(() => {
			this.rafHandle = null;
			this.repaint();
		});
	}

	private now(): number {
		return typeof performance === "object" && typeof performance.now === "function"
			? performance.now()
			: 0;
	}

	private applyStyleVars(): void {
		const style = this.styleVarsString();
		for (const element of this.blockElements.values()) {
			element.setAttribute("style", style);
		}
	}

	private styleVarsString(): string {
		const entries: string[] = [];
		this.theme.ansi.forEach((color, index) => {
			entries.push(`--terminal-ansi-${index}: ${color}`);
		});
		entries.push(`--terminal-foreground: ${this.theme.foreground}`);
		entries.push(`--terminal-background: ${this.theme.background}`);
		entries.push(`--terminal-cursor: ${this.theme.cursor}`);
		entries.push(`--terminal-selection: ${this.theme.selection}`);
		entries.push(`--terminal-block-background: ${this.theme.blockBackground}`);
		entries.push(`--terminal-block-border: ${this.theme.blockBorder}`);
		entries.push(`--terminal-block-header-foreground: ${this.theme.blockHeaderForeground}`);
		entries.push(`--terminal-font-family: ${this.font.family}`);
		entries.push(`--terminal-font-size: ${this.font.sizePx}px`);
		entries.push(`--terminal-font-weight: ${this.font.weight}`);
		entries.push(`--terminal-letter-spacing: ${this.font.letterSpacingPx}px`);
		entries.push(`--terminal-line-height: ${this.font.lineHeight * this.font.sizePx}px`);
		entries.push(
			`--terminal-ligatures: ${this.font.ligatures ? "common-ligatures" : "none"}`,
		);
		return entries.join("; ");
	}

	private applyFontToMeasureNode(node: HTMLElement): void {
		node.style.fontFamily = this.font.family;
		node.style.fontSize = `${this.font.sizePx}px`;
		node.style.fontWeight = String(this.font.weight);
		node.style.letterSpacing = `${this.font.letterSpacingPx}px`;
		node.style.lineHeight = `${this.font.lineHeight * this.font.sizePx}px`;
		node.style.fontVariantLigatures = this.font.ligatures ? "common-ligatures" : "none";
	}

	private repaint(): void {
		const core = this.core;
		const container = this.container;
		const list = this.list;
		const leading = this.leadingSpacer;
		const trailing = this.trailingSpacer;
		if (!core || !container || !list || !leading || !trailing) {
			return;
		}
		const snapshot = core.snapshot();

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
		const { cellHeight } = this.measure();
		const rowHeight = cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx;
		const anchorScrollTop = container.scrollTop;
		const scrollTop = this.stickToBottom ? Number.MAX_SAFE_INTEGER : anchorScrollTop;
		const viewportHeight = container.clientHeight || 1;
		const windowResult = computeWindow({
			blocks,
			scrollTop,
			viewportHeight,
			rowHeight,
			headerHeight: DEFAULT_HEADER_HEIGHT,
			overscanRows: OVERSCAN_ROWS,
		});

		leading.style.height = `${windowResult.leadingSpacer}px`;
		trailing.style.height = `${windowResult.trailingSpacer}px`;

		const textSource: BlockTextSource = this.buildTextSource();
		const visibleIds = new Set<BlockId>();
		if (windowResult.firstBlock <= windowResult.lastBlock) {
			for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
				const block = blocks[i]!;
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
			const block = blocks[i]!;
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
		this.lastPaintAt = this.now();
		this.notifyPainted();
	}

	private updateStickiness(): void {
		const container = this.container;
		if (!container) return;
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
		const blockById = new Map<BlockId, BlockView>();
		for (const block of blocks) {
			blockById.set(block.id, block);
		}
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
		section.setAttribute("style", this.styleVarsString());
		this.blockElements.set(block.id, section);
		return section;
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
		return existing;
	}
	const tag = document.createElement("style");
	tag.setAttribute("data-terminal-package", "renderer-dom");
	tag.textContent = terminalStyles;
	document.head.append(tag);
	return tag;
}

function ensureMeasureHost(): HTMLElement {
	const existing = document.getElementById("terminal-measure-host");
	if (existing) {
		return existing;
	}
	const host = document.createElement("div");
	host.id = "terminal-measure-host";
	host.style.position = "absolute";
	host.style.visibility = "hidden";
	host.style.pointerEvents = "none";
	host.style.left = "-9999px";
	host.style.top = "0";
	const node = document.createElement("span");
	node.id = HIDDEN_MEASURE_ID;
	node.textContent = "M";
	host.append(node);
	document.body.append(host);
	return host;
}

function listenScroll(target: EventTarget, listener: () => void): () => void {
	target.addEventListener("scroll", listener, { passive: true });
	return () => target.removeEventListener("scroll", listener);
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
	const { content, rows, runRanges, stylePairs } = snapshot;
	const blockFirstRow = block.firstRow;
	const firstRow = rowWindow ? rowWindow.firstRow : 0;
	const lastRow = rowWindow ? rowWindow.lastRow : block.rowCount - 1;
	if (rowWindow && firstRow > 0) {
		fragment.append(spacerOf(firstRow * rowHeight));
	}
	for (let rowOffset = firstRow; rowOffset <= lastRow; rowOffset += 1) {
		const snapshotRowIndex = blockFirstRow + rowOffset;
		const rowsBase = snapshotRowIndex * 2;
		const rowContentStart = rows[rowsBase] ?? 0;
		const rowContentEnd = rows[rowsBase + 1] ?? rowContentStart;
		const rowLength = rowContentEnd - rowContentStart;
		const pairStart = runRanges[rowsBase] ?? 0;
		const pairEnd = runRanges[rowsBase + 1] ?? pairStart;
		const rowNode = document.createElement("div");
		rowNode.dataset.terminalRow = String(rowOffset);
		rowNode.className = CLASS_ROW;
		let rowCursor = 0;
		for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
			const elementIndex = pairIndex * 2;
			const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
			const styleCode = stylePairs[elementIndex + 1] ?? 255;
			const slice = content.subarray(
				rowContentStart + rowCursor,
				rowContentStart + pairRunEnd,
			);
			const text = decoder.decode(slice);
			const run = document.createElement("span");
			run.dataset.terminalRun = String(pairIndex);
			run.className = CLASS_RUN;
			run.style.color = styleCodeToCssVar(styleCode);
			run.textContent = text;
			rowNode.append(run);
			rowCursor = pairRunEnd;
		}
		if (rowCursor < rowLength) {
			const tail = content.subarray(
				rowContentStart + rowCursor,
				rowContentStart + rowLength,
			);
			rowNode.append(document.createTextNode(decoder.decode(tail)));
		}
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
