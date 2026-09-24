import type { FontConfig } from "@operator/terminal-core";
import { BLOCK_COMMAND_GAP_LINES, blockPaddingY } from "./block-metrics.js";
import { ensureMeasureHost, HIDDEN_MEASURE_ID } from "./host-dom.js";
import { createDomMeasurer, WidthCache } from "./width-cache.js";

export type CellSize = { cellWidth: number; cellHeight: number };

export class CellMeasurer {
	widths: WidthCache | null = null;
	private measureHost: HTMLElement | null = null;
	private measureNode: HTMLElement | null = null;
	private metricsCache: CellSize | null = null;
	private dprQuery: MediaQueryList | null = null;

	constructor(private readonly onDprChange: () => void) {}

	attach(): void {
		this.measureHost = ensureMeasureHost();
		this.measureNode = this.measureHost.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
	}

	measure(font: FontConfig): CellSize {
		if (this.metricsCache) return this.metricsCache;
		const host = this.measureHost ?? ensureMeasureHost();
		const node = this.measureNode ?? host.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		if (!node) {
			return { cellWidth: 0, cellHeight: 0 };
		}
		applyFontToMeasureNode(node, font);
		const rect = node.getBoundingClientRect();
		const cellWidth = rect.width > 0 ? rect.width : font.sizePx * 0.6;
		const cellHeight =
			rect.height > 0 ? rect.height : font.lineHeight * font.sizePx;
		this.metricsCache = { cellWidth, cellHeight };
		if (!this.widths) {
			this.widths = new WidthCache(createDomMeasurer(node));
		}
		this.watchDevicePixelRatio();
		return this.metricsCache;
	}

	invalidate(): void {
		this.metricsCache = null;
		this.widths?.clear();
	}

	reset(): void {
		this.measureNode = null;
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = null;
		this.metricsCache = null;
		this.widths = null;
	}

	// xterm.js src/browser/renderer/dom/DomRenderer.ts:330-334 (handleDevicePixelRatioChange)
	private watchDevicePixelRatio(): void {
		if (typeof matchMedia !== "function") return;
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`);
		this.dprQuery.addEventListener("change", this.onDprChange);
	}
}

function applyFontToMeasureNode(node: HTMLElement, font: FontConfig): void {
	node.style.display = "inline-block";
	node.style.fontFamily = font.family;
	node.style.fontSize = `${font.sizePx}px`;
	node.style.fontWeight = String(font.weight);
	node.style.letterSpacing = `${font.letterSpacingPx}px`;
	node.style.lineHeight = `${font.lineHeight * font.sizePx}px`;
	node.style.fontVariantLigatures = font.ligatures ? "common-ligatures" : "none";
}

export function rowHeightFor(cellHeight: number, font: FontConfig): number {
	return cellHeight > 0 ? cellHeight : font.lineHeight * font.sizePx;
}

export function blockLayout(cellHeight: number, font: FontConfig): { rowHeight: number; headerHeight: number; paddingY: number } {
	const rowHeight = rowHeightFor(cellHeight, font);
	return {
		rowHeight,
		headerHeight: rowHeight * (2 + BLOCK_COMMAND_GAP_LINES),
		paddingY: blockPaddingY(rowHeight) + 1,
	};
}

export function cellMetricsFor(size: CellSize, font: FontConfig): CellSize {
	const { cellWidth, cellHeight } = size;
	return { cellWidth: cellWidth > 0 ? cellWidth : font.sizePx * 0.6, cellHeight: cellHeight > 0 ? cellHeight : font.lineHeight * font.sizePx };
}
