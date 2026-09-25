import { detectsHighConfidenceInputPattern } from "./input-patterns.js";
import type { TerminalSnapshot } from "./types.js";

export type AgentActivityState = "active" | "pollingForIdle" | "idle" | "prompting";

export type AgentActivityListener = (state: AgentActivityState) => void;

export const ACTIVITY_POLLING_AFTER_MS = 500;

export const ACTIVITY_IDLE_AFTER_MS = 1500;

export type AgentActivitySource = Readonly<{
	liveOutputBytes(): number;
	cursorLine(): string;
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
		this.reported = this.evaluate(this.source.now());
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
		this.report("active");
		this.schedule();
	}

	dispose(): void {
		this.disposed = true;
		this.cancel();
		this.listeners.clear();
	}

	private evaluate(now: number): AgentActivityState {
		const quiet = now - this.lastOutputAt;
		if (quiet < ACTIVITY_POLLING_AFTER_MS) return "active";
		if (detectsHighConfidenceInputPattern(this.source.cursorLine())) return "prompting";
		return quiet < ACTIVITY_IDLE_AFTER_MS ? "pollingForIdle" : "idle";
	}

	private report(state: AgentActivityState): void {
		if (state === this.reported) return;
		this.reported = state;
		for (const listener of [...this.listeners]) listener(state);
	}

	private schedule(): void {
		if (this.disposed || this.timer !== null || this.listeners.size === 0) return;
		const now = this.source.now();
		const quiet = now - this.lastOutputAt;
		const due =
			quiet < ACTIVITY_POLLING_AFTER_MS
				? ACTIVITY_POLLING_AFTER_MS - quiet
				: quiet < ACTIVITY_IDLE_AFTER_MS
					? ACTIVITY_IDLE_AFTER_MS - quiet
					: null;
		if (due === null) return;
		this.timer = setTimeout(() => {
			this.timer = null;
			if (this.disposed) return;
			this.report(this.evaluate(this.source.now()));
			this.schedule();
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
	const row = alt ? alt.cursorRow : snapshot.cursorRow;
	const column = alt ? alt.cursorColumn : snapshot.cursorColumn;
	const start = ranges[row * 2];
	const end = ranges[row * 2 + 1];
	const text = start === undefined || end === undefined || end <= start ? "" : decoder.decode(content.subarray(start, end));
	const width = [...text].length;
	return width < column ? text + " ".repeat(column - width) : text;
}
