import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";
import type { BlockFinishedEvent } from "./block-finished";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "bench", "agent-session", "fixtures", "claude-spinner-10s", "recording");

const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
	document.body.replaceChildren();
});

function text(value: string): Uint8Array {
	return new TextEncoder().encode(value);
}

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
}

function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

function parkingLot(): HTMLElement {
	const lot = document.createElement("div");
	lot.setAttribute("aria-hidden", "true");
	lot.style.visibility = "hidden";
	document.body.append(lot);
	return lot;
}

function park(container: HTMLElement, lot: HTMLElement): void {
	container.setAttribute("inert", "");
	container.setAttribute("aria-hidden", "true");
	container.style.pointerEvents = "none";
	container.style.visibility = "hidden";
	lot.append(container);
}

function mounted(columns = 40): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer; events: BlockFinishedEvent[] } {
	const core = createTerminalCore({ columns, scrollback: 1000, rows: 5 });
	const host = scrollable();
	document.body.append(host);
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	const events: BlockFinishedEvent[] = [];
	renderer.onBlockFinished((event) => events.push(event));
	return { core, host, renderer, events };
}

const OPEN_BLOCK = "\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n";
const CLOSE_BLOCK = "\x1b]133;D;0\x07";

describe("block-finished detection", () => {
	it("reports a block that finishes in a parked container as not visible", async () => {
		const { core, host, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		park(host, parkingLot());
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 0, visible: false });
		renderer.dispose();
	});

	it("reports a block that finishes under the alternate screen once the primary screen returns, not before", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(`${CLOSE_BLOCK}\x1b[?1049h`));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(0);
		core.feed(text("\x1b[?1049l"));
		await flushRepaint();
		expect(events).toHaveLength(1);
		renderer.dispose();
	});

	it("never reports a block whose close arrives inside the alternate screen", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(`\x1b[?1049h${CLOSE_BLOCK}`));
		await flushRepaint();
		await flushRepaint();
		core.feed(text("\x1b[?1049l"));
		await flushRepaint();
		expect(events).toHaveLength(0);
		renderer.dispose();
	});

	it("reports each finished block once", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		core.feed(text("more\r\n"));
		await flushRepaint();
		expect(events).toHaveLength(1);
		renderer.dispose();
	});
});

function setDocumentVisibility(state: DocumentVisibilityState): void {
	Object.defineProperty(document, "visibilityState", { configurable: true, get: () => state });
	document.dispatchEvent(new Event("visibilitychange"));
}

describe("visibility seam", () => {
	afterEach(() => setDocumentVisibility("visible"));

	it("reports the host's fact instead of guessing from the DOM", async () => {
		const { core, renderer, events } = mounted();
		renderer.setVisible(true);
		expect(renderer.visibility()).toBe(true);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: true });
		renderer.dispose();
	});

	it("reports not visible when the host says so even if the DOM looks visible", async () => {
		const { core, host, renderer, events } = mounted();
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		renderer.setVisible(false);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: false });
		renderer.dispose();
	});

	it("falls back to the DOM when the host sets nothing", async () => {
		const { core, host, renderer, events } = mounted();
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		renderer.setVisible(true);
		renderer.setVisible(null);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: true });
		renderer.dispose();
	});

	it("reports not visible while the document is hidden, whatever the host says", async () => {
		const { core, renderer, events } = mounted();
		renderer.setVisible(true);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		setDocumentVisibility("hidden");
		core.feed(text(CLOSE_BLOCK));
		(renderer as unknown as { detectFinishedBlocks(s: unknown): unknown }).detectFinishedBlocks(core.snapshot());
		expect(events.at(-1)).toMatchObject({ visible: false });
		renderer.dispose();
	});
});

function observeMutations(root: HTMLElement): () => number {
	let count = 0;
	const observer = new MutationObserver((records) => {
		count += records.length;
	});
	observer.observe(root, { childList: true, subtree: true, attributes: true, characterData: true });
	return () => {
		count += observer.takeRecords().length;
		observer.disconnect();
		return count;
	};
}

async function spinnerChunks(): Promise<Uint8Array[]> {
	const bytes = new Uint8Array(await readFile(fixture));
	const chunks: Uint8Array[] = [];
	for (let at = 0; at < bytes.length; at += 4096) chunks.push(bytes.subarray(at, Math.min(bytes.length, at + 4096)));
	return chunks;
}

function rowTexts(host: HTMLElement): string[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => row.textContent ?? "");
}

describe("paint gate", () => {
	it("keeps draining a hidden pane without touching its DOM", async () => {
		const { core, host, renderer } = mounted(120);
		core.feed(text("before\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		const generation = core.snapshot().generation;
		const stop = observeMutations(host);
		for (let index = 0; index < 20; index += 1) {
			core.enqueue(text(`line ${index}\r\n`));
			await flushRepaint();
		}
		expect(stop()).toBe(0);
		expect(core.hasBacklog()).toBe(false);
		expect(core.snapshot().generation).toBeGreaterThan(generation);
		renderer.dispose();
	});

	it("still reports a finished block from a hidden pane, as not visible", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 0, visible: false });
		renderer.dispose();
	});

	it("defers a block that finishes in a hidden pane under the alternate screen until the primary screen returns", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text(`${CLOSE_BLOCK}\x1b[?1049h`));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(0);
		core.enqueue(text("\x1b[?1049l"));
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ visible: false });
		renderer.dispose();
	});

	it("paints the current tail on the call that reveals it, stuck to the bottom", async () => {
		const { core, host, renderer } = mounted(120);
		core.feed(text("first screen\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		const hiddenRows = rowTexts(host);
		for (const chunk of await spinnerChunks()) {
			core.enqueue(chunk);
			await flushRepaint();
		}
		core.enqueue(text("\r\ntail marker\r\n"));
		await flushRepaint();
		expect(rowTexts(host)).toEqual(hiddenRows);
		renderer.setVisible(true);
		const shown = rowTexts(host);
		expect(shown.join("\n")).toContain("tail marker");
		expect(renderer.scrollAnchor()).toBeNull();
		renderer.dispose();
	});

	it("paints while the host says visible even when the container is hidden and inert", async () => {
		const { core, host, renderer } = mounted();
		host.setAttribute("inert", "");
		host.style.visibility = "hidden";
		renderer.setVisible(true);
		core.enqueue(text("preparing paint\r\n"));
		await flushRepaint();
		expect(rowTexts(host).join("\n")).toContain("preparing paint");
		renderer.dispose();
	});

	it("keeps the scroll anchor and the selection across park and reveal", async () => {
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) core.feed(text(`line ${i}\r\n`));
		const host = scrollable();
		document.body.append(host);
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		host.scrollTop = Math.round(rowHeight * 60);
		host.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: anchor.stableRow, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: anchor.stableRow, column: 4, side: "right" });
		const selected = renderer.selectedText();
		renderer.setVisible(false);
		for (let i = 100; i < 140; i += 1) {
			core.enqueue(text(`line ${i}\r\n`));
			await flushRepaint();
		}
		renderer.setVisible(true);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(host.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		expect(renderer.selectedText()).toBe(selected);
		renderer.dispose();
	});

	it("neither samples round trips nor paints predictions while hidden", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("$ "));
		await flushRepaint();
		renderer.setPredictiveEcho({ thresholdMs: 0 });
		renderer.noteRoundTrip(0, 50);
		expect(renderer.predictKey({ text: "a", ctrlKey: false, altKey: false, metaKey: false, isComposing: false }, performance.now())).toBe(true);
		const rtt = (renderer as unknown as { rtt: { median(): number | null } }).rtt;
		const medianBefore = rtt.median();
		renderer.noteSend(performance.now());
		renderer.setVisible(false);
		expect(renderer.predictionCount()).toBe(0);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		core.enqueue(text("a"));
		await flushRepaint();
		expect(rtt.median()).toBe(medianBefore);
		renderer.dispose();
	});

	it("paints once when hidden and shown again before any frame ran", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("steady\r\n"));
		await flushRepaint();
		const steadyRow = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].find((row) => row.textContent === "steady");
		expect(steadyRow).toBeDefined();
		renderer.setVisible(false);
		core.enqueue(text("late\r\n"));
		let paints = 0;
		const stop = renderer.onPaint(() => {
			paints += 1;
		});
		renderer.setVisible(true);
		stop();
		expect(paints).toBe(1);
		expect(rowTexts(host).join("\n")).toContain("late");
		expect((renderer as unknown as { catchUp: boolean }).catchUp).toBe(false);
		expect([...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].find((row) => row.textContent === "steady")).toBe(steadyRow);
		renderer.dispose();
	});

	it("reveals mid sync block with the last complete frame, not half of the next", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("frame one\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text("\x1b[?2026hhalf of frame two"));
		await flushRepaint();
		renderer.setVisible(true);
		const shown = rowTexts(host).join("\n");
		expect(shown).toContain("frame one");
		expect(shown).not.toContain("half of frame two");
		renderer.dispose();
	});
});
