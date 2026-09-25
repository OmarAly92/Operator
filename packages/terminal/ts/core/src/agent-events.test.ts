import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { AgentEvents, createTerminalCore, initTerminalCore, type AgentEvent } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

type VectorCase = { name: string; input: string; events: AgentEvent[] };

async function vectorCases(): Promise<VectorCase[]> {
	const raw = await readFile(fileURLToPath(new URL("../../../protocol/agent-vectors/agent-state.json", import.meta.url)), "utf8");
	return (JSON.parse(raw) as { cases: VectorCase[] }).cases;
}

function core() {
	return createTerminalCore({ columns: 80, rows: 24, limits: { rows: 1000, bytes: 1 << 20 } });
}

function collect(target: ReturnType<typeof core>): AgentEvent[] {
	const events: AgentEvent[] = [];
	target.onAgentEvent((event) => events.push(event));
	return events;
}

describe("AgentEvents", () => {
	it("reads nothing while the program generation is unchanged", () => {
		const source = { program_generation: vi.fn(() => 0), take_agent_events: vi.fn(() => [] as string[]) };
		new AgentEvents(source).poll();
		expect(source.take_agent_events).not.toHaveBeenCalled();
	});

	it("emits each state and detail pair once and skips a state it does not know", () => {
		let generation = 0;
		let pending: string[] = [];
		const source = {
			program_generation: () => generation,
			take_agent_events: () => {
				const taken = pending;
				pending = [];
				return taken;
			},
		};
		const events = new AgentEvents(source);
		const seen: AgentEvent[] = [];
		events.onEvent((event) => seen.push(event));
		generation = 1;
		pending = ["working", "Read", "paused", "", "done", ""];
		events.poll();
		events.poll();
		expect(seen).toEqual([
			{ state: "working", detail: "Read" },
			{ state: "done", detail: "" },
		]);
	});

	it("stops delivering to a listener after its teardown and after dispose", () => {
		let generation = 0;
		const source = { program_generation: () => generation, take_agent_events: () => ["idle", ""] };
		const events = new AgentEvents(source);
		const first = vi.fn();
		const second = vi.fn();
		const stop = events.onEvent(first);
		events.onEvent(second);
		stop();
		generation = 1;
		events.poll();
		expect(first).not.toHaveBeenCalled();
		expect(second).toHaveBeenCalledTimes(1);
		events.dispose();
		generation = 2;
		events.poll();
		expect(second).toHaveBeenCalledTimes(1);
	});
});

describe("TerminalCore.onAgentEvent", () => {
	it("yields every vector case's events, whole and split byte by byte", async () => {
		const cases = await vectorCases();
		expect(cases.length).toBeGreaterThanOrEqual(20);
		for (const vector of cases) {
			const whole = core();
			const wholeEvents = collect(whole);
			whole.feed(encoder.encode(vector.input));
			expect(wholeEvents, vector.name).toEqual(vector.events);
			whole.dispose();
			const split = core();
			const splitEvents = collect(split);
			for (const byte of encoder.encode(vector.input)) split.feed(Uint8Array.of(byte));
			expect(splitEvents, vector.name).toEqual(vector.events);
			split.dispose();
		}
	});

	it("delivers events parsed from the backlog by drain", () => {
		const target = core();
		const events = collect(target);
		target.enqueue(encoder.encode("\x1b]777;agent-state;v=1;state=waiting;detail=Allow%20Bash%3F\x07"));
		expect(events).toEqual([]);
		target.drain();
		expect(events).toEqual([{ state: "waiting", detail: "Allow Bash?" }]);
		target.dispose();
	});

	it("delivers an event held in a sync block when tick passes its deadline", () => {
		const target = core();
		const events = collect(target);
		target.feed(encoder.encode("\x1b[?2026h\x1b]777;agent-state;v=1;state=working\x07"));
		expect(events).toEqual([]);
		target.tick(Date.now() + 1_000);
		expect(events).toEqual([{ state: "working", detail: "" }]);
		target.dispose();
	});

	it("does not replay an event to a listener that subscribes after it", () => {
		const target = core();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=done\x07"));
		const late = collect(target);
		target.feed(encoder.encode("plain output"));
		expect(late).toEqual([]);
		target.dispose();
	});

	it("stops delivering after the listener's teardown and after dispose", () => {
		const target = core();
		const listener = vi.fn();
		const stop = target.onAgentEvent(listener);
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=working\x07"));
		stop();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=done\x07"));
		expect(listener).toHaveBeenCalledTimes(1);
		const kept = vi.fn();
		target.onAgentEvent(kept);
		target.dispose();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=idle\x07"));
		expect(kept).not.toHaveBeenCalled();
	});

	it("never fires for the replay frame, a history chunk or an older answer", () => {
		const target = core();
		const events = collect(target);
		target.feed(encoder.encode("\x1b]7000;v=1;origin=1000\x1b\\frame\x1b]777;agent-state;v=1;state=working\x07\r\n"));
		target.feed(encoder.encode("\x1b]7000;v=1;ready=1\x1b\\"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=998,2\x1b\\\x1b]777;agent-state;v=1;state=waiting\x07one\r\ntwo\r\n"));
		const answer = encoder.encode(
			"\x1b]7000;v=1;history=996,2;cols=80\x1b\\\x1b]777;agent-state;v=1;state=done\x07three\r\nfour\r\n\x1b]7000;v=1;older=996\x1b\\",
		);
		for (const byte of answer) target.feed(Uint8Array.of(byte));
		expect(target.snapshot().firstStableRow).toBe(996);
		expect(events).toEqual([]);
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=idle\x07"));
		expect(events).toEqual([{ state: "idle", detail: "" }]);
		target.dispose();
	});

	it("keeps only the newest sixteen events of a flood fed in one call", () => {
		const target = core();
		const events = collect(target);
		let flood = "";
		for (let index = 0; index < 1_000; index += 1) flood += `\x1b]777;agent-state;v=1;state=working;detail=${index}\x07`;
		target.feed(encoder.encode(flood));
		expect(events).toHaveLength(16);
		expect(events[0]).toEqual({ state: "working", detail: "984" });
		expect(events.at(-1)).toEqual({ state: "working", detail: "999" });
		target.dispose();
	});
});
