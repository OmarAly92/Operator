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
