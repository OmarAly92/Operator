import { callEach, throwFailures } from "./listener-failures.js";

export type AgentState = "working" | "waiting" | "idle" | "done";

export type AgentEvent = Readonly<{ state: AgentState; detail: string }>;

export type AgentEventListener = (event: AgentEvent) => void;

export type AgentEventSource = {
	program_generation(): number;
	take_agent_events(): string[];
};

const STATES: ReadonlySet<string> = new Set<AgentState>(["working", "waiting", "idle", "done"]);

export class AgentEvents {
	private readonly source: AgentEventSource;
	private readonly listeners = new Set<AgentEventListener>();
	private generation = 0;

	constructor(source: AgentEventSource) {
		this.source = source;
	}

	onEvent(listener: AgentEventListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	poll(): void {
		const generation = this.source.program_generation();
		if (generation === this.generation) return;
		this.generation = generation;
		const flat = this.source.take_agent_events();
		const failures: unknown[] = [];
		for (let index = 0; index + 1 < flat.length; index += 2) {
			const state = flat[index]!;
			if (!STATES.has(state)) continue;
			callEach(this.listeners, { state: state as AgentState, detail: flat[index + 1]! }, failures);
		}
		throwFailures(failures, "agent event listener failed");
	}

	dispose(): void {
		this.listeners.clear();
	}
}
