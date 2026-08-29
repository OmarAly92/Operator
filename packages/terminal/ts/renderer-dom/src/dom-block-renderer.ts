import {
	validateRowRange,
	type BlockId,
	type BlockRenderer,
	type FontConfig,
	type RowRange,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { styleCodeToCssVar } from "./style-code.js";
import { terminalStyles } from "./styles.js";

const SYNTHETIC_BLOCK_ID: BlockId = "synthetic-0";
const CLASS_BLOCK = "terminal-block";
const CLASS_ROW = "terminal-row";
const CLASS_RUN = "terminal-run";
const HIDDEN_MEASURE_ID = "terminal-m-measure";

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
	private block: HTMLElement | null = null;
	private theme: TerminalTheme = warpDarkTheme;
	private font: FontConfig = defaultFont();
	private unsubscribe: (() => void) | null = null;
	private measureHost: HTMLElement | null = null;
	private measureNode: HTMLElement | null = null;
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });

	mount(container: HTMLElement, core: TerminalCore): void {
		this.dispose();
		this.container = container;
		this.core = core;
		ensurePackageStyleTag();
		this.block = document.createElement("section");
		this.block.dataset.terminalBlockId = SYNTHETIC_BLOCK_ID;
		this.block.className = CLASS_BLOCK;
		this.applyStyleVars();
		container.append(this.block);
		this.measureHost = ensureMeasureHost();
		this.measureNode = this.measureHost.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		this.unsubscribe = core.onChange(() => this.repaint());
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

	invalidate(range: RowRange): void {
		validateRowRange(range);
		this.repaint();
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
		if (id !== SYNTHETIC_BLOCK_ID) {
			throw new Error(`unknown block id ${id}`);
		}
		const target = this.block;
		if (!target) {
			throw new Error(`renderer is not mounted`);
		}
		target.scrollIntoView({ block: align, inline: "nearest" });
	}

	dispose(): void {
		if (this.unsubscribe) {
			this.unsubscribe();
			this.unsubscribe = null;
		}
		if (this.container) {
			this.container.replaceChildren();
		}
		this.container = null;
		this.core = null;
		this.block = null;
		this.measureNode = null;
	}

	private applyStyleVars(): void {
		const block = this.block;
		if (!block) {
			return;
		}
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
		block.setAttribute("style", entries.join("; "));
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
		const block = this.block;
		if (!core || !block) {
			return;
		}
		const snapshot = core.snapshot();
		const { content, rows, runRanges, stylePairs } = snapshot;
		const decoder = this.decoder;
		const fragment = document.createDocumentFragment();
		for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 2) {
			const rowContentStart = rows[rowIndex] ?? 0;
			const rowContentEnd = rows[rowIndex + 1] ?? rowContentStart;
			const rowLength = rowContentEnd - rowContentStart;
			const pairStart = runRanges[rowIndex] ?? 0;
			const pairEnd = runRanges[rowIndex + 1] ?? pairStart;
			const rowNode = document.createElement("div");
			rowNode.dataset.terminalRow = String(rowIndex / 2);
			rowNode.className = CLASS_ROW;
			let rowCursor = 0;
			for (let pairIndex = pairStart; pairIndex < pairEnd; pairIndex += 1) {
				const elementIndex = pairIndex * 2;
				const pairRunEnd = stylePairs[elementIndex] ?? rowCursor;
				const styleCode = stylePairs[elementIndex + 1] ?? 255;
				const slice = content.subarray(rowContentStart + rowCursor, rowContentStart + pairRunEnd);
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
		block.replaceChildren(fragment);
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
