import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
	ACTIVITY_IDLE_AFTER_MS,
	ACTIVITY_POLLING_AFTER_MS,
	AgentActivityMonitor,
	createTerminalCore,
	cursorLineText,
	detectsHighConfidenceInputPattern,
	initTerminalCore,
	type AgentActivityState,
	type TerminalCore,
} from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

beforeEach(() => {
	vi.useFakeTimers({ now: 1_000_000 });
});

afterEach(() => {
	vi.useRealTimers();
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const FRAME_MS = 100;
const ESU = encoder.encode("\x1b[?2026l");
const TITLE = encoder.encode("\x1b]0;");

type Size = { offset: number; cols: number; rows: number };

async function fixture(name: string): Promise<{ recording: Uint8Array; sizes: Size[] }> {
	const dir = new URL(`../../../bench/agent-session/fixtures/${name}/`, import.meta.url);
	const recording = new Uint8Array(await readFile(fileURLToPath(new URL("recording", dir))));
	const sizes = JSON.parse(await readFile(fileURLToPath(new URL("size.json", dir)), "utf8")) as Size[];
	return { recording, sizes };
}

function endsAfter(recording: Uint8Array, needle: Uint8Array, before: boolean): number[] {
	const ends: number[] = [];
	outer: for (let index = 0; index + needle.length <= recording.length; index += 1) {
		for (let k = 0; k < needle.length; k += 1) if (recording[index + k] !== needle[k]) continue outer;
		const end = before ? index : index + needle.length;
		if (end > 0) ends.push(end);
	}
	return ends;
}

function frameEnds(recording: Uint8Array): number[] {
	const synced = endsAfter(recording, ESU, false);
	const ends = synced.length > 0 ? synced : endsAfter(recording, TITLE, true);
	if (ends.at(-1) !== recording.length) ends.push(recording.length);
	return ends;
}

function fakeSource(line = "") {
	let bytes = 0;
	const source = {
		cursorLine: vi.fn(() => line),
		liveOutputBytes: () => bytes,
		now: () => Date.now(),
		setLine: (next: string) => {
			line = next;
		},
		write: (count: number) => {
			bytes += count;
		},
	};
	return source;
}

describe("detectsHighConfidenceInputPattern", () => {
	it.each([
		"Overwrite existing file? (y/n) ",
		"Continue? [Y/n] ",
		"Proceed (yes/no) ",
		"Ok to proceed? (y) ",
		"package name: (demo) ",
		"(END)",
		"[sudo] password for dev:",
		"Press any key to continue",
		"? Pick a color ❯ ",
	])("matches %j", (line) => {
		expect(detectsHighConfidenceInputPattern(line)).toBe(true);
	});

	it.each([
		"❯ ",
		"❯ ",
		"$ ",
		"➜  repo git:(main) ",
		"Last Command: ",
		"✻ Baked for 11s · done 6:13 PM",
		"  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
	])("does not match %j", (line) => {
		expect(detectsHighConfidenceInputPattern(line)).toBe(false);
	});
});

describe("AgentActivityMonitor", () => {
	it("starts idle before any output", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		expect(monitor.state()).toBe("idle");
	});

	it("goes active on output, polling for idle after 500 ms, idle after 1500 ms", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: Array<[AgentActivityState, number]> = [];
		const start = Date.now();
		monitor.onChange((state) => seen.push([state, Date.now() - start]));
		source.write(10);
		monitor.observe();
		vi.advanceTimersByTime(5_000);
		expect(seen).toEqual([
			["active", 0],
			["pollingForIdle", ACTIVITY_POLLING_AFTER_MS],
			["idle", ACTIVITY_IDLE_AFTER_MS],
		]);
		expect(vi.getTimerCount()).toBe(0);
	});

	it("stays active while output keeps arriving within the polling window", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		for (let frame = 0; frame < 50; frame += 1) {
			source.write(1);
			monitor.observe();
			vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS - 1);
		}
		expect(seen).toEqual(["active"]);
		expect(monitor.state()).toBe("active");
	});

	it("never reports idle while output arrives once a second, as a hidden window drains it", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		for (let second = 0; second < 30; second += 1) {
			source.write(1);
			monitor.observe();
			vi.advanceTimersByTime(1_000);
		}
		expect(seen).not.toContain("idle");
		expect(seen.filter((state) => state === "pollingForIdle")).toHaveLength(30);
	});

	it("reports prompting once quiet when the cursor line asks a question, and goes active on the answer", () => {
		const source = fakeSource("Overwrite? (y/n) ");
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		source.write(5);
		monitor.observe();
		vi.advanceTimersByTime(3_000);
		expect(seen).toEqual(["active", "prompting"]);
		source.setLine("Overwrite? (y/n) y");
		source.write(1);
		monitor.observe();
		vi.advanceTimersByTime(3_000);
		expect(seen).toEqual(["active", "prompting", "active", "pollingForIdle", "idle"]);
	});

	it("never reads the cursor line while output is active", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		source.write(1);
		monitor.observe();
		source.cursorLine.mockClear();
		expect(monitor.state()).toBe("active");
		expect(source.cursorLine).not.toHaveBeenCalled();
	});

	it("keeps no timer without a listener, and the last teardown cancels it", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		source.write(1);
		monitor.observe();
		expect(vi.getTimerCount()).toBe(0);
		const first = vi.fn();
		const second = vi.fn();
		const stopFirst = monitor.onChange(first);
		const stopSecond = monitor.onChange(second);
		expect(vi.getTimerCount()).toBe(1);
		stopFirst();
		expect(vi.getTimerCount()).toBe(1);
		stopSecond();
		expect(vi.getTimerCount()).toBe(0);
		vi.advanceTimersByTime(5_000);
		expect(first).not.toHaveBeenCalled();
		expect(second).not.toHaveBeenCalled();
	});

	it("dispose cancels the timer and silences every listener", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const listener = vi.fn();
		monitor.onChange(listener);
		source.write(1);
		monitor.observe();
		listener.mockClear();
		monitor.dispose();
		expect(vi.getTimerCount()).toBe(0);
		source.write(1);
		monitor.observe();
		vi.advanceTimersByTime(5_000);
		expect(listener).not.toHaveBeenCalled();
	});
});

describe("TerminalCore agent activity", () => {
	function core(columns = 120, rows = 40): TerminalCore {
		const target = createTerminalCore({ columns, rows, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		target.setAgentTuiMode(true);
		return target;
	}

	it("counts live output only: the replay frame, a history chunk and an older answer stay idle", () => {
		const target = core(80, 24);
		const seen: AgentActivityState[] = [];
		target.onAgentActivity((state) => seen.push(state));
		target.feed(encoder.encode("\x1b]7000;v=1;origin=1000\x1b\\frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=998,2\x1b\\one\r\ntwo\r\n"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=996,2;cols=80\x1b\\three\r\nfour\r\n\x1b]7000;v=1;older=996\x1b\\"));
		expect(target.snapshot().firstStableRow).toBe(996);
		expect(seen).toEqual([]);
		expect(target.agentActivity()).toBe("idle");
		target.feed(encoder.encode("live"));
		expect(seen).toEqual(["active"]);
		target.dispose();
	});

	it("stops reporting after the listener's teardown and after dispose", () => {
		const target = core(80, 24);
		const listener = vi.fn();
		const stop = target.onAgentActivity(listener);
		target.feed(encoder.encode("a"));
		expect(listener).toHaveBeenCalledTimes(1);
		stop();
		vi.advanceTimersByTime(5_000);
		expect(listener).toHaveBeenCalledTimes(1);
		const kept = vi.fn();
		target.onAgentActivity(kept);
		target.feed(encoder.encode("b"));
		kept.mockClear();
		target.dispose();
		expect(vi.getTimerCount()).toBe(0);
		vi.advanceTimersByTime(5_000);
		target.feed(encoder.encode("c"));
		expect(kept).not.toHaveBeenCalled();
	});

	it("reports prompting for a y/n question at the cursor", () => {
		const target = core(80, 24);
		target.feed(encoder.encode("Overwrite greet.py? (y/n) "));
		vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS);
		expect(target.agentActivity()).toBe("prompting");
		target.dispose();
	});

	it.each([
		["claude-spinner-10s", 120],
		["claude-markdown-reply", 157],
		["claude-long-50k", 1048],
	] as const)(
		"%s: active for all %i frames at a 100 ms cadence, idle 1500 ms after the last byte, never prompting",
		async (name, frames) => {
			const { recording, sizes } = await fixture(name);
			const target = core(sizes[0]!.cols, sizes[0]!.rows);
			const start = Date.now();
			const seen: Array<[AgentActivityState, number]> = [];
			target.onAgentActivity((state) => seen.push([state, Date.now() - start]));
			let fed = 0;
			let prompts = 0;
			let nextSize = 1;
			const ends = frameEnds(recording);
			for (const end of ends) {
				while (nextSize < sizes.length && sizes[nextSize]!.offset <= end) {
					const size = sizes[nextSize]!;
					target.feed(recording.subarray(fed, size.offset));
					fed = size.offset;
					target.resize(size.cols, size.rows);
					nextSize += 1;
				}
				target.feed(recording.subarray(fed, end));
				fed = end;
				if (detectsHighConfidenceInputPattern(cursorLineText(target.snapshot(), decoder))) prompts += 1;
				vi.advanceTimersByTime(FRAME_MS);
			}
			const last = (ends.length - 1) * FRAME_MS;
			vi.advanceTimersByTime(ACTIVITY_IDLE_AFTER_MS);
			expect(ends).toHaveLength(frames);
			expect(prompts).toBe(0);
			expect(seen).toEqual([
				["active", 0],
				["pollingForIdle", last + ACTIVITY_POLLING_AFTER_MS],
				["idle", last + ACTIVITY_IDLE_AFTER_MS],
			]);
			target.dispose();
		},
	);
});
