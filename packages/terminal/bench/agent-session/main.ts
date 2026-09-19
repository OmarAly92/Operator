import { decodeBlocks, type TerminalCore } from "@operator/terminal-core";
import { DomBenchmarkRenderer } from "../adapters/dom";

type SizeEntry = { offset: number; cols: number; rows: number };

declare global {
	interface Window {
		__agentSession: AgentSession;
		__agentSessionReady: boolean;
	}
}

type AgentSession = {
	fixture: { name: string; sizes: SizeEntry[]; bytes: number };
	fed: number;
	feedAll(): Promise<void>;
	feedUntilRows(target: number): Promise<number>;
	feedNext(limit: number): number;
	feedChunk(start: number, end: number): number;
	feedFrames(count: number, intervalMs: number): Promise<void>;
	rowCount(): number;
	paintCount(): number;
	addedNodes(): number;
	resetCounters(): void;
	longTasks(): number[];
	memoryBytes(): number;
	scrollHeight(): number;
	scrollTop(): number;
	setScrollTop(top: number): Promise<void>;
	visibleRows(): Array<{ block: string; row: number }>;
	textHash(): string;
	modelHash(): string;
	core(): TerminalCore;
};

const host = document.getElementById("terminal");
if (!host) throw new Error("agent-session host is missing");
const params = new URLSearchParams(location.search);
const fixtureName = params.get("fixture") ?? "claude-spinner-10s";
const scrollback = Number(params.get("scrollback") ?? "200000");

const [recordingResponse, sizesResponse] = await Promise.all([
	fetch(`/agent-session/fixtures/${fixtureName}/recording`),
	fetch(`/agent-session/fixtures/${fixtureName}/size.json`),
]);
if (!recordingResponse.ok || !sizesResponse.ok) throw new Error(`fixture ${fixtureName} is missing`);
const recording = new Uint8Array(await recordingResponse.arrayBuffer());
const sizes = (await sizesResponse.json()) as SizeEntry[];

const renderer = new DomBenchmarkRenderer();
await renderer.mount(host, { columns: sizes[0].cols, rows: sizes[0].rows, scrollback });
const core = renderer.getCoreForBench() as TerminalCore;
core.setAgentTuiMode(true);

let paints = 0;
let addedNodes = 0;
let fed = 0;
let nextResize = 1;
const longTasks: number[] = [];
const domRenderer = (renderer as unknown as { renderer: { onPaint(listener: () => void): () => void } }).renderer;
domRenderer.onPaint(() => {
	paints += 1;
});
new MutationObserver((records) => {
	for (const record of records) addedNodes += record.addedNodes.length;
}).observe(host, { childList: true, subtree: true });
if (typeof PerformanceObserver === "function") {
	try {
		new PerformanceObserver((list) => {
			for (const entry of list.getEntries()) longTasks.push(entry.duration);
		}).observe({ entryTypes: ["longtask"] });
	} catch {}
}

function applyResizesUpTo(offset: number): void {
	while (nextResize < sizes.length && sizes[nextResize].offset <= offset) {
		const size = sizes[nextResize];
		core.resize(size.cols, size.rows);
		nextResize += 1;
	}
}

function feedChunk(start: number, end: number): number {
	applyResizesUpTo(start);
	const chunk = recording.subarray(start, end);
	const before = performance.now();
	core.feed(chunk);
	const cost = performance.now() - before;
	fed = Math.max(fed, end);
	return cost;
}

function feedNext(limit: number): number {
	const end = Math.min(recording.length, fed + limit);
	if (end <= fed) return 0;
	return feedChunk(fed, end);
}

function rowCount(): number {
	return core.snapshot().rows.length / 2;
}

async function nextFrame(): Promise<void> {
	await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
}

async function feedAll(): Promise<void> {
	while (fed < recording.length) {
		feedNext(64 * 1024);
		await nextFrame();
	}
	await renderer.waitForPaint().catch(() => undefined);
}

async function feedUntilRows(target: number): Promise<number> {
	while (fed < recording.length && rowCount() < target) {
		feedNext(64 * 1024);
		await nextFrame();
	}
	await renderer.waitForPaint().catch(() => undefined);
	return rowCount();
}

function frameEnds(): number[] {
	const esu = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c];
	const ends: number[] = [];
	for (let index = 0; index + esu.length <= recording.length; index += 1) {
		let match = true;
		for (let k = 0; k < esu.length; k += 1) {
			if (recording[index + k] !== esu[k]) {
				match = false;
				break;
			}
		}
		if (match) {
			ends.push(index + esu.length);
			index += esu.length - 1;
		}
	}
	return ends;
}

async function feedFrames(count: number, intervalMs: number): Promise<void> {
	const ends = frameEnds().filter((end) => end > fed).slice(0, count);
	for (const end of ends) {
		feedChunk(fed, end);
		await new Promise((resolve) => setTimeout(resolve, intervalMs));
	}
}

function visibleRows(): Array<{ block: string; row: number }> {
	const box = host!.getBoundingClientRect();
	const out: Array<{ block: string; row: number }> = [];
	for (const section of host!.querySelectorAll<HTMLElement>("[data-terminal-block-id]")) {
		const block = section.dataset.terminalBlockId ?? "";
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			const rect = row.getBoundingClientRect();
			if (rect.bottom >= box.top && rect.top <= box.bottom) out.push({ block, row: Number(row.dataset.terminalRow) });
		}
	}
	return out;
}

function fnv(text: string): string {
	let hash = 2166136261;
	for (const ch of text) {
		hash ^= ch.codePointAt(0)!;
		hash = Math.imul(hash, 16777619) >>> 0;
	}
	return hash.toString(16);
}

function textHash(): string {
	const rows = [...host!.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => row.textContent ?? "");
	return fnv(rows.join("\n"));
}

function modelHash(): string {
	const snapshot = core.snapshot();
	const decoder = new TextDecoder();
	let text = `${snapshot.cursorRow}:${snapshot.cursorColumn}\n`;
	for (let index = 0; index < snapshot.rows.length; index += 2) {
		text += `${decoder.decode(snapshot.content.subarray(snapshot.rows[index]!, snapshot.rows[index + 1]!))}\n`;
	}
	return fnv(text);
}

const scroller = host.querySelector<HTMLElement>(".terminal-host") ?? host;

window.__agentSession = {
	fixture: { name: fixtureName, sizes, bytes: recording.length },
	get fed() {
		return fed;
	},
	feedAll,
	feedUntilRows,
	feedNext,
	feedChunk,
	feedFrames,
	rowCount,
	paintCount: () => paints,
	addedNodes: () => addedNodes,
	resetCounters: () => {
		paints = 0;
		addedNodes = 0;
		longTasks.length = 0;
	},
	longTasks: () => [...longTasks],
	memoryBytes: () => core.snapshot().content.buffer.byteLength,
	scrollHeight: () => scroller.scrollHeight,
	scrollTop: () => scroller.scrollTop,
	setScrollTop: async (top: number) => {
		scroller.scrollTop = top;
		scroller.dispatchEvent(new Event("scroll"));
		await nextFrame();
		await nextFrame();
	},
	visibleRows,
	textHash,
	modelHash,
	core: () => core,
	blocks: () => decodeBlocks(core.snapshot()).length,
} as AgentSession & { blocks(): number };
window.__agentSessionReady = true;
