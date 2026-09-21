import { decodeBlocks, type TerminalCore } from "@operator/terminal-core";
import { DomBenchmarkRenderer } from "../adapters/dom";
import type { DomBlockRenderer } from "@operator/terminal-renderer-dom";

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
	feedNextSynced(limit: number): number;
	rowCount(): number;
	renderableRowCount(): number;
	paintCount(): number;
	addedNodes(): number;
	rowNodesAdded(): number;
	resetCounters(): void;
	longTasks(): number[];
	memoryBytes(): number;
	scrollHeight(): number;
	scrollTop(): number;
	setScrollTop(top: number): Promise<void>;
	paintAfter(action: () => void): Promise<void>;
	visibleRows(): Array<{ block: string; row: number }>;
	textHash(): string;
	modelHash(): string;
	core(): TerminalCore;
	extendSelectionByOneRow(): Promise<number>;
	mountPanes(count: number): Promise<void>;
	reopenFromReplay(frame: Uint8Array, chunks: Uint8Array[]): Promise<{ firstPaintMs: number; allRowsMs: number; rows: number }>;
	widthChange(cols: number): Promise<{ settleMs: number; before: number; after: number; staleRows: number }>;
	staleRowCount(): number;
	cellMetrics(): { cellWidth: number; cellHeight: number };
};

const host = document.getElementById("terminal");
if (!host) throw new Error("agent-session host is missing");
const params = new URLSearchParams(location.search);
const fixtureName = params.get("fixture") ?? "claude-spinner-10s";
const scrollback = Number(params.get("scrollback") ?? "200000");

const fixtureDir = params.get("dir") === "probes" ? "probes" : "fixtures";
const [recordingResponse, sizesResponse] = await Promise.all([
	fetch(`/agent-session/${fixtureDir}/${fixtureName}/recording`),
	fetch(`/agent-session/${fixtureDir}/${fixtureName}/size.json`),
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
const domRenderer = (renderer as unknown as { renderer: DomBlockRenderer }).renderer;
domRenderer.onPaint(() => {
	paints += 1;
});
new MutationObserver((records) => {
	for (const record of records) {
		for (const node of record.addedNodes) {
			addedNodes += node instanceof Element ? 1 + node.querySelectorAll("*").length : 1;
		}
	}
}).observe(host, { childList: true, subtree: true });

let rowNodesAdded = 0;
new MutationObserver((records) => {
	for (const record of records) {
		for (const node of record.addedNodes) {
			if (node instanceof HTMLElement && node.classList.contains("terminal-row")) rowNodesAdded += 1;
		}
	}
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

function renderableRowCount(): number {
	const snapshot = core.snapshot();
	const blank = (row: number): boolean => {
		const start = snapshot.rows[row * 2] ?? 0;
		const end = snapshot.rows[row * 2 + 1] ?? 0;
		for (let index = start; index < end; index += 1) if (snapshot.content[index] !== 0x20) return false;
		return true;
	};
	let total = 0;
	for (const block of decodeBlocks(snapshot)) {
		let count = block.rowCount;
		while (count > 1 && blank(block.firstRow + count - 1)) count -= 1;
		total += count;
	}
	return total;
}

function rowCount(): number {
	return core.snapshot().rows.length / 2;
}

async function nextFrame(): Promise<void> {
	await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
}

const PAINT_WAIT_FRAMES = 600;

async function paintAfter(action: () => void): Promise<void> {
	const before = paints;
	action();
	for (let frame = 0; paints === before; frame += 1) {
		if (frame >= PAINT_WAIT_FRAMES) throw new Error(`no paint landed within ${PAINT_WAIT_FRAMES} frames of the action`);
		await nextFrame();
	}
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

function feedNextSynced(limit: number): number {
	const end = Math.min(recording.length, fed + limit);
	if (end <= fed) return 0;
	applyResizesUpTo(fed);
	const chunk = recording.subarray(fed, end);
	const before = performance.now();
	core.feed(chunk);
	core.snapshot();
	const cost = performance.now() - before;
	fed = end;
	return cost;
}

const extraPanes: DomBenchmarkRenderer[] = [];

async function mountPanes(count: number): Promise<void> {
	for (let index = 0; index < count; index += 1) {
		const paneHost = document.createElement("div");
		paneHost.style.width = "800px";
		paneHost.style.height = "300px";
		document.body.append(paneHost);
		const pane = new DomBenchmarkRenderer();
		await pane.mount(paneHost, { columns: sizes[0].cols, rows: sizes[0].rows, scrollback });
		(pane.getCoreForBench() as TerminalCore).setAgentTuiMode(true);
		extraPanes.push(pane);
	}
}

async function reopenFromReplay(frame: Uint8Array, chunks: Uint8Array[]): Promise<{ firstPaintMs: number; allRowsMs: number; rows: number }> {
	paints = 0;
	addedNodes = 0;
	rowNodesAdded = 0;
	longTasks.length = 0;
	const start = performance.now();
	core.feed(frame);
	while (paints === 0) await nextFrame();
	const firstPaintMs = performance.now() - start;
	const allStart = performance.now();
	const paintsBeforeHistory = paints;
	for (const chunk of chunks) core.feed(chunk);
	while (paints === paintsBeforeHistory) await nextFrame();
	const allRowsMs = performance.now() - allStart;
	return { firstPaintMs, allRowsMs, rows: rowCount() };
}

async function widthChange(cols: number): Promise<{ settleMs: number; before: number; after: number; staleRows: number }> {
	const before = visibleRows()[0]?.row ?? -1;
	const currentRows = nextResize > 0 ? sizes[nextResize - 1]!.rows : sizes[0]!.rows;
	const start = performance.now();
	await paintAfter(() => core.resize(cols, currentRows));
	const settleMs = performance.now() - start;
	const after = visibleRows()[0]?.row ?? -1;
	const staleRows = core.staleRowCount();
	return { settleMs, before, after, staleRows };
}

function staleRowCount(): number {
	return core.staleRowCount();
}

async function extendSelectionByOneRow(): Promise<number> {
	const rows = [...host!.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	if (rows.length < 4) throw new Error("need at least four rendered rows");
	const at = (row: HTMLElement) => {
		const rect = row.getBoundingClientRect();
		return { x: rect.left + 4, y: rect.top + rect.height / 2 };
	};
	const first = domRenderer.pointAt(at(rows[0]!).x, at(rows[0]!).y);
	const second = domRenderer.pointAt(at(rows[1]!).x, at(rows[1]!).y);
	const third = domRenderer.pointAt(at(rows[2]!).x, at(rows[2]!).y);
	if (!first || !second || !third) throw new Error("rows have no selection point");
	domRenderer.selectionBegin(first, "simple");
	domRenderer.selectionUpdate(second);
	await nextFrame();
	const mutated = new Set<Node>();
	const observer = new MutationObserver((records) => {
		for (const record of records) {
			const target = record.target;
			if (target instanceof HTMLElement && target.classList.contains("terminal-row")) mutated.add(target);
		}
	});
	observer.observe(host!, { attributes: true, attributeFilter: ["style"], subtree: true });
	domRenderer.selectionUpdate(third);
	await nextFrame();
	for (const record of observer.takeRecords()) {
		if (record.target instanceof HTMLElement && record.target.classList.contains("terminal-row")) mutated.add(record.target);
	}
	observer.disconnect();
	domRenderer.selectionClear();
	return mutated.size;
}

async function feedFrames(count: number, intervalMs: number): Promise<void> {
	const ends = frameEnds().filter((end) => end > fed).slice(0, count);
	for (const end of ends) {
		const start = fed;
		feedChunk(start, end);
		for (const pane of extraPanes) (pane.getCoreForBench() as TerminalCore).feed(recording.subarray(start, end));
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
	feedNextSynced,
	rowCount,
	renderableRowCount,
	paintCount: () => paints,
	addedNodes: () => addedNodes,
	rowNodesAdded: () => rowNodesAdded,
	resetCounters: () => {
		paints = 0;
		addedNodes = 0;
		rowNodesAdded = 0;
		longTasks.length = 0;
	},
	longTasks: () => [...longTasks],
	memoryBytes: () => core.snapshot().content.buffer.byteLength,
	scrollHeight: () => scroller.scrollHeight,
	scrollTop: () => scroller.scrollTop,
	setScrollTop: async (top: number) => {
		await paintAfter(() => {
			scroller.scrollTop = top;
			scroller.dispatchEvent(new Event("scroll"));
		});
	},
	paintAfter,
	visibleRows,
	textHash,
	modelHash,
	core: () => core,
	extendSelectionByOneRow,
	mountPanes,
	reopenFromReplay,
	widthChange,
	staleRowCount,
	cellMetrics: () => domRenderer.measure(),
	blocks: () => decodeBlocks(core.snapshot()).length,
} as AgentSession & { blocks(): number };
window.__agentSessionReady = true;
