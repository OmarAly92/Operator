import { callEach, throwFailures } from "./listener-failures.js";

export type AgentActivityState = "active" | "pollingForIdle" | "idle" | "prompting";

export type AgentActivityListener = (state: AgentActivityState) => void;

export const ACTIVITY_POLLING_AFTER_MS = 500;

export const ACTIVITY_IDLE_AFTER_MS = 1500;

export type AgentActivitySource = Readonly<{
	liveOutputBytes(): number;
	prompting(): boolean;
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
		if (this.source.prompting()) return "prompting";
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
