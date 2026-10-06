import type { SecretPattern } from "@operator/terminal-core";
import { paintBoxes, rangeBoxes, type DecorationBox } from "./decorations.js";
import { collectHintMatches, HintSession, type HintEvent, type HintMatch } from "./hint-mode.js";
import type { HintRule } from "./hint-rules.js";
import { DEFAULT_LINK_PROVIDERS, type DetectedLink, type LinkProvider } from "./link-providers.js";
import { Linkifier } from "./linkifier.js";
import { logicalLineAt, rangeContains, type LogicalLineView } from "./logical-lines.js";
import { compileSecretPatterns, maskedTextRows, redactionMatches } from "./redaction.js";
import { decorationLayer } from "./renderer-chrome.js";
import type { SelectionPoint } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";
import type { RenderedRow } from "./selection-view.js";

type CellMetrics = { cellWidth: number; cellHeight: number };

export type RendererOverlaysDeps = Readonly<{
	container: () => HTMLElement | null;
	painting: () => boolean;
	rawTextRows: () => TextRows;
	renderedRows: () => RenderedRow[];
	cellMetrics: () => CellMetrics;
}>;

export class RendererOverlays {
	decorationLayer: HTMLElement | null = null;
	private linkProviders: readonly LinkProvider[] = DEFAULT_LINK_PROVIDERS;
	private readonly linkifier = new Linkifier({
		rows: () => this.textRows(),
		providers: () => this.linkProviders,
		onChange: () => this.linkChanged(),
	});
	private readonly linkHoverListeners = new Set<(link: DetectedLink | null) => void>();
	private hint: HintSession | null = null;
	private secretRegexes: RegExp[] = [];
	private revealedSecrets = new Set<string>();
	private revealedAt = -1;

	constructor(private readonly deps: RendererOverlaysDeps) {}

	textRows(): TextRows {
		return maskedTextRows(this.deps.rawTextRows(), this.secretRegexes, this.revealedSecrets);
	}

	hover(point: SelectionPoint | null): void {
		this.linkifier.hover(point);
	}

	hoveredLink(): DetectedLink | null {
		return this.linkifier.current();
	}

	onLinkHover(listener: (link: DetectedLink | null) => void): () => void {
		this.linkHoverListeners.add(listener);
		return () => {
			this.linkHoverListeners.delete(listener);
		};
	}

	setLinkProviders(providers: readonly LinkProvider[]): void {
		this.linkProviders = providers;
		this.linkifier.invalidate();
	}

	refreshLinks(): void {
		this.linkifier.refresh();
	}

	hintBegin(rules: readonly HintRule[]): number {
		const lines = renderedLogicalLines(this.textRows(), this.deps.renderedRows());
		const matches = collectHintMatches(lines, rules);
		this.hint = matches.length > 0 ? new HintSession(matches) : null;
		this.paintHints();
		return matches.length;
	}

	hintType(character: string): HintEvent | null {
		const session = this.hint;
		if (!session) return null;
		const match = session.type(character);
		if (!match) {
			this.paintHints();
			return null;
		}
		this.hintCancel();
		return { ruleId: match.ruleId, text: match.text, path: match.path, line: match.line };
	}

	hintBackspace(): void {
		this.hint?.backspace();
		this.paintHints();
	}

	hintCancel(): void {
		this.hint = null;
		this.paintHints();
	}

	hintActive(): boolean {
		return this.hint !== null;
	}

	setSecretPatterns(patterns: readonly SecretPattern[]): void {
		this.secretRegexes = compileSecretPatterns(patterns);
		this.revealedSecrets.clear();
	}

	hasSecrets(): boolean {
		return this.secretRegexes.length > 0;
	}

	revealSecretAt(point: SelectionPoint, generation: () => number | undefined): boolean {
		const line = logicalLineAt(this.deps.rawTextRows(), point.blockId, point.row);
		if (!line) return false;
		for (const match of redactionMatches(line, this.secretRegexes)) {
			if (!rangeContains(match.range, point.row, point.column)) continue;
			this.revealedSecrets.add(match.key);
			this.revealedAt = generation() ?? this.revealedAt;
			return true;
		}
		return false;
	}

	noteGeneration(generation: number): void {
		if (this.revealedAt !== generation) {
			this.revealedSecrets.clear();
			this.revealedAt = generation;
		}
	}

	layer(name: string): HTMLElement | null {
		return decorationLayer(this.decorationLayer, name);
	}

	paintDecorations(): void {
		const layer = this.layer("links");
		const container = this.deps.container();
		if (!layer || !container) return;
		const link = this.linkifier.current();
		const boxes = link ? rangeBoxes(link.range, this.deps.renderedRows(), this.deps.cellMetrics().cellWidth, container) : [];
		paintBoxes(layer, "terminal-link-underline", boxes);
	}

	paintHints(): void {
		const matchLayer = this.layer("hints");
		const labelLayer = this.layer("labels");
		const container = this.deps.container();
		if (!matchLayer || !labelLayer || !container) return;
		const entries = this.hint?.labelled() ?? [];
		paintHintLayers(matchLayer, labelLayer, container, entries, this.deps.renderedRows, this.deps.cellMetrics);
	}

	paintRedactions(): void {
		const layer = this.layer("redactions");
		const container = this.deps.container();
		if (!layer || !container) return;
		paintRedactionLayer(layer, container, this.secretRegexes, this.revealedSecrets, this.deps.rawTextRows, this.deps.renderedRows, this.deps.cellMetrics);
	}

	dispose(): void {
		this.linkifier.dispose();
		this.hint = null;
		this.secretRegexes = [];
		this.revealedSecrets.clear();
		this.decorationLayer = null;
		this.linkHoverListeners.clear();
	}

	private linkChanged(): void {
		const link = this.linkifier.current();
		this.deps.container()?.classList.toggle("terminal-link-hover", link !== null);
		if (this.deps.painting()) this.paintDecorations();
		for (const listener of [...this.linkHoverListeners]) listener(link);
	}
}

export function renderedLogicalLines(rows: TextRows, rendered: readonly RenderedRow[]): LogicalLineView[] {
	const seen = new Set<string>();
	const lines: LogicalLineView[] = [];
	for (const { box } of rendered) {
		const line = logicalLineAt(rows, box.blockId, box.row);
		if (!line) continue;
		const key = `${line.blockId}:${line.firstRow}`;
		if (seen.has(key)) continue;
		seen.add(key);
		lines.push(line);
	}
	return lines;
}

export function paintHintLayers(
	matchLayer: HTMLElement,
	labelLayer: HTMLElement,
	container: HTMLElement,
	entries: readonly { label: string; match: HintMatch }[],
	renderedRows: () => RenderedRow[],
	cellMetrics: () => CellMetrics,
): void {
	const matchBoxes: DecorationBox[] = [];
	const labelBoxes: DecorationBox[] = [];
	const labels: string[] = [];
	if (entries.length > 0) {
		const rows = renderedRows();
		const { cellWidth, cellHeight } = cellMetrics();
		for (const entry of entries) {
			const boxes = rangeBoxes(entry.match.range, rows, cellWidth, container);
			if (boxes.length === 0) continue;
			matchBoxes.push(...boxes);
			labelBoxes.push({ ...boxes[0]!, width: Math.max(entry.label.length, 1) * cellWidth, height: cellHeight });
			labels.push(entry.label);
		}
	}
	paintBoxes(matchLayer, "terminal-hint-match", matchBoxes);
	paintBoxes(labelLayer, "terminal-hint-label", labelBoxes, labels);
}

export function paintRedactionLayer(
	layer: HTMLElement,
	container: HTMLElement,
	secretRegexes: readonly RegExp[],
	revealedSecrets: ReadonlySet<string>,
	rawTextRows: () => TextRows,
	renderedRows: () => RenderedRow[],
	cellMetrics: () => CellMetrics,
): void {
	if (secretRegexes.length === 0) {
		paintBoxes(layer, "terminal-redaction", []);
		return;
	}
	const rows = rawTextRows();
	const seen = new Set<string>();
	const boxes: DecorationBox[] = [];
	const rendered = renderedRows();
	const { cellWidth } = cellMetrics();
	for (const { box } of rendered) {
		const line = logicalLineAt(rows, box.blockId, box.row);
		if (!line) continue;
		const key = `${line.blockId}:${line.firstRow}`;
		if (seen.has(key)) continue;
		seen.add(key);
		for (const match of redactionMatches(line, secretRegexes)) {
			if (revealedSecrets.has(match.key)) continue;
			boxes.push(...rangeBoxes(match.range, rendered, cellWidth, container));
		}
	}
	paintBoxes(layer, "terminal-redaction", boxes);
}
