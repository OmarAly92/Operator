import { CELL_SPAN_WORDS } from "./cell-spans.js";
import { detectsHighConfidenceInputPattern } from "./input-patterns.js";
import { callEach, throwFailures } from "./listener-failures.js";
import type { TerminalSnapshot } from "./types.js";

export type AgentActivityState = "active" | "pollingForIdle" | "idle" | "prompting";

export type AgentActivityListener = (state: AgentActivityState) => void;

export const ACTIVITY_POLLING_AFTER_MS = 500;

export const ACTIVITY_IDLE_AFTER_MS = 1500;

export type AgentActivitySource = Readonly<{
	liveOutputBytes(): number;
	cursorLine(): string;
	lineEditorOwnsLine?(): boolean;
	now(): number;
}>;

export class AgentActivityMonitor {
	private readonly source: AgentActivitySource;
	private readonly listeners = new Set<AgentActivityListener>();
	private lastOutputBytes = 0;
	private lastOutputAt = Number.NEGATIVE_INFINITY;
	private reported: AgentActivityState;
	private timer: ReturnType<typeof setTimeout> | null = null;
	private disposed = false;

	constructor(source: AgentActivitySource) {
		this.source = source;
		this.lastOutputBytes = source.liveOutputBytes();
		this.reported = this.evaluate(source.now());
	}

	state(): AgentActivityState {
		return this.evaluate(this.source.now());
	}

	onChange(listener: AgentActivityListener): () => void {
		this.listeners.add(listener);
		this.schedule();
		return () => {
			this.listeners.delete(listener);
			if (this.listeners.size === 0) this.cancel();
		};
	}

	observe(): void {
		if (this.disposed) return;
		const bytes = this.source.liveOutputBytes();
		if (bytes === this.lastOutputBytes) return;
		this.lastOutputBytes = bytes;
		this.lastOutputAt = this.source.now();
		this.publish("active");
	}

	dispose(): void {
		this.disposed = true;
		this.cancel();
		this.listeners.clear();
	}

	private evaluate(now: number): AgentActivityState {
		const quiet = now - this.lastOutputAt;
		if (quiet < ACTIVITY_POLLING_AFTER_MS) return "active";
		if (!this.source.lineEditorOwnsLine?.() && detectsHighConfidenceInputPattern(this.source.cursorLine())) return "prompting";
		return quiet < ACTIVITY_IDLE_AFTER_MS ? "pollingForIdle" : "idle";
	}

	private publish(state: AgentActivityState): void {
		const changed = state !== this.reported;
		this.reported = state;
		this.schedule();
		if (!changed) return;
		const failures: unknown[] = [];
		callEach(this.listeners, state, failures);
		throwFailures(failures, "agent activity listener failed");
	}

	private schedule(): void {
		this.cancel();
		if (this.disposed || this.listeners.size === 0) return;
		const now = this.source.now();
		const quiet = now - this.lastOutputAt;
		const due =
			this.evaluate(now) !== this.reported
				? 0
				: quiet < ACTIVITY_POLLING_AFTER_MS
					? ACTIVITY_POLLING_AFTER_MS - quiet
					: quiet < ACTIVITY_IDLE_AFTER_MS
						? ACTIVITY_IDLE_AFTER_MS - quiet
						: null;
		if (due === null) return;
		this.timer = setTimeout(() => {
			this.timer = null;
			if (this.disposed) return;
			this.publish(this.evaluate(this.source.now()));
		}, due);
	}

	private cancel(): void {
		if (this.timer === null) return;
		clearTimeout(this.timer);
		this.timer = null;
	}
}

export function cursorLineText(snapshot: TerminalSnapshot, decoder: TextDecoder): string {
	const alt = snapshot.altScreen;
	const content = alt ? alt.content : snapshot.content;
	const ranges = alt ? alt.rowRanges : snapshot.rows;
	const spanRanges = alt ? alt.spanRanges : snapshot.spanRanges;
	const cellSpans = alt ? alt.cellSpans : snapshot.cellSpans;
	const row = alt ? alt.cursorRow : snapshot.cursorRow;
	const column = alt ? alt.cursorColumn : snapshot.cursorColumn;
	const start = ranges[row * 2];
	const end = ranges[row * 2 + 1];
	const bytes = start === undefined || end === undefined || end <= start ? new Uint8Array(0) : content.subarray(start, end);
	const spanStart = spanRanges[row * 2] ?? 0;
	const spanEnd = spanRanges[row * 2 + 1] ?? spanStart;
	const width = cellWidth(bytes, cellSpans.subarray(spanStart * CELL_SPAN_WORDS, spanEnd * CELL_SPAN_WORDS));
	const text = decoder.decode(bytes);
	return width < column ? text + " ".repeat(column - width) : text;
}

function cellWidth(bytes: Uint8Array, spans: Uint32Array): number {
	let cells = 0;
	let next = 0;
	let skipTo = 0;
	for (let at = 0; at < bytes.length; at += 1) {
		if (at < skipTo || (bytes[at]! & 0xc0) === 0x80) continue;
		while (next * CELL_SPAN_WORDS < spans.length && spans[next * CELL_SPAN_WORDS]! < at) next += 1;
		if (next * CELL_SPAN_WORDS < spans.length && spans[next * CELL_SPAN_WORDS] === at) {
			skipTo = spans[next * CELL_SPAN_WORDS + 1]!;
			cells += spans[next * CELL_SPAN_WORDS + 2]!;
			next += 1;
		} else {
			cells += 1;
		}
	}
	return cells;
}
