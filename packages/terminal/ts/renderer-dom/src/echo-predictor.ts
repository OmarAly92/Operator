import { CELL_SPAN_WORDS, type TerminalSnapshot } from "@operator/terminal-core";
import { cellString } from "./clusters.js";
import { CURSOR_ATTR, primaryCursorPlacement } from "./cursor.js";
import { paintBoxes } from "./decorations.js";
import { PREDICTION_TTL_MS, PredictionState, type CursorPoint, type KeyDescriptor, type Prediction } from "./prediction.js";
import type { RttMeter } from "./rtt.js";

export type EchoPredictorHost = Readonly<{
	painting: () => boolean;
	cursorPoint: () => CursorPoint | null;
	rowCellsAt: (row: number) => string;
	layer: () => HTMLElement | null;
	container: () => HTMLElement | null;
	altShowing: () => boolean;
	cellMetrics: () => { cellWidth: number; cellHeight: number };
}>;

export class EchoPredictor {
	private readonly predictions = new PredictionState();
	private predictionTimer: ReturnType<typeof setTimeout> | null = null;
	private sentCursor: CursorPoint | null = null;

	constructor(
		private readonly rtt: RttMeter,
		private readonly host: EchoPredictorHost,
	) {}

	noteSend(nowMs: number): void {
		if (!this.host.painting()) return;
		if (this.rtt.sent(nowMs)) this.sentCursor = this.host.cursorPoint() ?? { row: -1, column: -1 };
	}

	noteReceived(nowMs: number): void {
		if (!this.host.painting()) return;
		const before = this.sentCursor;
		if (before === null) return;
		const after = this.host.cursorPoint();
		if (after === null || (after.row === before.row && after.column === before.column)) return;
		this.sentCursor = null;
		this.rtt.received(nowMs);
	}

	predictKey(key: KeyDescriptor, nowMs: number, echoThresholdMs: number | null): boolean {
		if (echoThresholdMs === null || !this.rtt.shouldPredict(echoThresholdMs)) return false;
		this.reconcile();
		const cursor = this.host.cursorPoint();
		if (cursor === null) return false;
		if (!this.predictions.register(key, cursor, nowMs)) return false;
		this.armExpiry(performance.now());
		this.paint();
		return true;
	}

	clear(): void {
		this.predictions.clear();
		this.armExpiry(performance.now());
		this.paint();
	}

	pending(): readonly Prediction[] {
		return this.predictions.pending();
	}

	reconcile(): void {
		if (!this.host.painting()) return;
		const now = performance.now();
		const cursor = this.host.cursorPoint();
		if (cursor !== null) {
			const cells = this.predictions.pending().length > 0 ? this.host.rowCellsAt(cursor.row) : "";
			this.predictions.reconcile(cursor, cells, now, this.ttlMs());
		} else {
			this.predictions.expire(now, this.ttlMs());
		}
		this.armExpiry(now);
		this.paint();
	}

	dropWhileHidden(hostVisible: boolean | null, clear: () => void): void {
		if (hostVisible !== false) return;
		if (this.sentCursor !== null) {
			this.sentCursor = null;
			this.rtt.cancel();
		}
		if (this.predictions.pending().length > 0) clear();
	}

	cancelTimer(): void {
		if (this.predictionTimer !== null) clearTimeout(this.predictionTimer), (this.predictionTimer = null);
	}

	private paint(): void {
		const layer = this.host.layer();
		const container = this.host.container();
		if (!layer || !container) return;
		paintPredictionLayer(layer, container, this.predictions.pending(), this.host.cursorPoint, this.host.altShowing, this.host.cellMetrics);
	}

	private ttlMs(): number {
		return Math.max(PREDICTION_TTL_MS, 2 * (this.rtt.median() ?? 0));
	}

	private armExpiry(nowMs: number): void {
		if (this.predictionTimer !== null) clearTimeout(this.predictionTimer), (this.predictionTimer = null);
		const oldest = this.predictions.pending()[0];
		if (oldest === undefined) return;
		const delay = Math.max(0, oldest.sentAtMs + this.ttlMs() - nowMs) + 1;
		this.predictionTimer = setTimeout(() => {
			this.predictionTimer = null;
			this.reconcile();
		}, delay);
	}
}

export function snapshotCursorPoint(snapshot: TerminalSnapshot): CursorPoint | null {
	const alt = snapshot.altScreen;
	if (alt) {
		if (!alt.cursorVisible) return null;
		return { row: alt.cursorRow, column: alt.cursorColumn };
	}
	return primaryCursorPlacement(snapshot);
}

export function snapshotRowCells(snapshot: TerminalSnapshot, row: number, decoder: TextDecoder): string {
	const alt = snapshot.altScreen;
	const content = alt ? alt.content : snapshot.content;
	const rows = alt ? alt.rowRanges : snapshot.rows;
	const spanRanges = alt ? alt.spanRanges : snapshot.spanRanges;
	const cellSpans = alt ? alt.cellSpans : snapshot.cellSpans;
	const start = rows[row * 2] ?? 0;
	const end = rows[row * 2 + 1] ?? start;
	const text = end > start ? decoder.decode(content.subarray(start, end)) : "";
	const spanStart = spanRanges[row * 2] ?? 0;
	const spanEnd = spanRanges[row * 2 + 1] ?? spanStart;
	return cellString(text, cellSpans.subarray(spanStart * CELL_SPAN_WORDS, spanEnd * CELL_SPAN_WORDS));
}

function paintPredictionLayer(
	layer: HTMLElement,
	container: HTMLElement,
	pending: readonly Prediction[],
	cursorPoint: () => CursorPoint | null,
	altShowing: () => boolean,
	cell: () => { cellWidth: number; cellHeight: number },
): void {
	const cursor = pending.length === 0 ? null : cursorPoint();
	if (cursor === null) {
		paintBoxes(layer, "terminal-prediction", []);
		return;
	}
	const anchor = altShowing()
		? container.querySelector<HTMLElement>("[data-terminal-cursor]")
		: container.querySelector<HTMLElement>(`[${CURSOR_ATTR}]`);
	if (!anchor) {
		paintBoxes(layer, "terminal-prediction", []);
		return;
	}
	const { cellWidth, cellHeight } = cell();
	const origin = container.getBoundingClientRect();
	const box = anchor.getBoundingClientRect();
	const boxes = pending.map((prediction) => ({
		left: box.left - origin.left + container.scrollLeft + (prediction.at.column - cursor.column) * cellWidth,
		top: box.top - origin.top + container.scrollTop,
		width: cellWidth,
		height: cellHeight,
	}));
	paintBoxes(layer, "terminal-prediction", boxes, pending.map((prediction) => prediction.text));
}
