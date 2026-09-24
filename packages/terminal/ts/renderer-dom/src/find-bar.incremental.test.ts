import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	defaultStrings,
	initTerminalCore,
	type BlockRenderer,
	type FontConfig,
	type TerminalCore,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";
import { createFindBar, type FindBar, type FindBarHost } from "./find-bar";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const encoder = new TextEncoder();

function flushFrames(count: number = 8): Promise<void> {
	return new Promise((resolve) => {
		let remaining = count;
		const step = () => {
			remaining -= 1;
			if (remaining <= 0) {
				resolve();
				return;
			}
			requestAnimationFrame(step);
		};
		requestAnimationFrame(step);
	});
}

function feedBlock(core: TerminalCore, text: string): void {
	core.feed(encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07${text}\x1b]133;D;0\x07\r\n`));
}

type Mounted = {
	core: TerminalCore;
	host: HTMLElement;
	renderer: DomBlockRenderer;
	bar: FindBar;
	input: HTMLInputElement;
	count: HTMLElement;
	scrolled: ReturnType<typeof vi.fn>;
};

let mounted: Mounted | null = null;

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

afterEach(() => {
	mounted?.bar.dispose();
	mounted?.renderer.dispose();
	mounted = null;
	vi.restoreAllMocks();
});

function mount(lines: readonly string[]): Mounted {
	const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
	for (const line of lines) feedBlock(core, line);
	const host = document.createElement("div");
	Object.defineProperty(host, "clientHeight", { value: 800, configurable: true });
	Object.defineProperty(host, "scrollHeight", { value: 2000, configurable: true });
	Object.defineProperty(host, "scrollTop", { value: 1500, configurable: true, writable: true });
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	const scrolled = vi.fn();
	const barHost: FindBarHost = {
		scrollToBlock: () => undefined,
		scrollToRow: (row, align) => {
			scrolled(row, align);
			return true;
		},
		invalidate: (range) => renderer.invalidate(range),
		afterRepaint: (listener) => renderer.onPaint(listener),
	};
	const bar = createFindBar({ core, renderer: renderer as unknown as BlockRenderer, host: barHost, strings: defaultStrings });
	bar.mount(host);
	bar.open();
	const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
	const count = host.querySelector<HTMLElement>("[data-terminal-find-count]")!;
	mounted = { core, host, renderer, bar, input, count, scrolled };
	return mounted;
}

function type(input: HTMLInputElement, value: string): void {
	input.value = value;
	input.dispatchEvent(new Event("input", { bubbles: true }));
}

function press(input: HTMLInputElement, key: string, shiftKey: boolean = false): void {
	input.dispatchEvent(new KeyboardEvent("keydown", { key, shiftKey, bubbles: true, cancelable: true }));
}

const lines = (count: number): string[] => Array.from({ length: count }, (_, index) => `line ${index} of text`);

describe("find-bar while output streams", () => {
	it("a new match appears without retyping", async () => {
		const { core, input, count } = mount(lines(5));
		type(input, "needle");
		await flushFrames();
		expect(count.textContent).toBe("No matches");
		feedBlock(core, "a needle arrives");
		await flushFrames();
		expect(count.textContent).toBe("1 of 1");
		expect(input.value).toBe("needle");
	});

	it("does not rescan history on repaint", async () => {
		const { core, renderer, input } = mount(lines(200));
		const opened = vi.spyOn(core, "findOpen");
		const updates = vi.spyOn(core, "findUpdate");
		type(input, "line");
		await flushFrames();
		const id = opened.mock.results[0]!.value as number;
		const scanned = core.findHistoryBytesScanned(id);
		expect(scanned).toBeGreaterThan(0);
		const calls = updates.mock.calls.length;
		for (let repaint = 0; repaint < 3; repaint += 1) {
			renderer.invalidate({ start: 0, end: 1 });
			await flushFrames(4);
		}
		expect(updates.mock.calls.length).toBeGreaterThan(calls);
		expect(core.findHistoryBytesScanned(id)).toBe(scanned);
	});

	it("keeps the current hit anchored while output streams", async () => {
		const { core, host, input, count, scrolled } = mount(lines(5));
		type(input, "line");
		await flushFrames();
		expect(count.textContent).toBe("1 of 5");
		press(input, "Enter");
		press(input, "Enter");
		await flushFrames(2);
		expect(count.textContent).toBe("3 of 5");
		expect(scrolled).toHaveBeenLastCalledWith(2, "center");
		for (let index = 5; index < 8; index += 1) feedBlock(core, `line ${index} of text`);
		await flushFrames();
		expect(count.textContent).toBe("3 of 8");
		expect(host.querySelector<HTMLElement>("[data-terminal-find-row-active]")?.dataset.terminalRow).toBe("2");
		press(input, "Enter", true);
		await flushFrames(2);
		expect(count.textContent).toBe("2 of 8");
		expect(scrolled).toHaveBeenLastCalledWith(1, "center");
	});

	it("reads the query as a regular expression while the toggle is pressed", async () => {
		const { host, input, count } = mount(lines(5));
		const toggle = host.querySelector<HTMLButtonElement>("button[data-terminal-find-regex]")!;
		expect(toggle.getAttribute("aria-pressed")).toBe("false");
		type(input, "line [0-2] of");
		await flushFrames();
		expect(count.textContent).toBe("No matches");
		toggle.click();
		await flushFrames();
		expect(toggle.getAttribute("aria-pressed")).toBe("true");
		expect(count.textContent).toBe("1 of 3");
		type(input, "line [0-");
		await flushFrames();
		expect(input.getAttribute("aria-invalid")).toBe("true");
		expect(count.textContent).toBe("No matches");
		type(input, "line [4]");
		await flushFrames();
		expect(input.hasAttribute("aria-invalid")).toBe(false);
		expect(count.textContent).toBe("1 of 1");
	});

	it("ignores case for a query without capitals and not for one with a capital", async () => {
		const { input, count } = mount(["Error one", "error two"]);
		type(input, "error");
		await flushFrames();
		expect(count.textContent).toBe("1 of 2");
		type(input, "Error");
		await flushFrames();
		expect(count.textContent).toBe("1 of 1");
	});

	it("unregisters the repaint listener on close and re-registers cleanly on reopen", async () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		const offFns: Array<ReturnType<typeof vi.fn>> = [];
		const afterRepaint = vi.fn((_listener: () => void) => {
			const off = vi.fn();
			offFns.push(off);
			return off;
		});
		const barHost: FindBarHost = {
			scrollToBlock: () => undefined,
			invalidate: (range) => renderer.invalidate(range),
			afterRepaint,
		};
		const bar = createFindBar({ core, renderer: renderer as unknown as BlockRenderer, host: barHost, strings: defaultStrings });
		bar.mount(host);

		bar.open();
		expect(afterRepaint).toHaveBeenCalledTimes(1);

		bar.close();
		expect(offFns[0]).toHaveBeenCalledTimes(1);

		bar.open();
		expect(afterRepaint).toHaveBeenCalledTimes(2);

		bar.close();
		expect(offFns[1]).toHaveBeenCalledTimes(1);

		bar.dispose();
		renderer.dispose();
	});

	it("finds text in a session that has no block marks", async () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 5 });
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		for (let index = 0; index < 12; index += 1) core.feed(encoder.encode(`hello ${index}\r\n`));
		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: { scrollToBlock: () => undefined, invalidate: (range) => renderer.invalidate(range), afterRepaint: (listener) => renderer.onPaint(listener) },
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();
		const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		mounted = { core, host, renderer, bar, input, count: host.querySelector<HTMLElement>("[data-terminal-find-count]")!, scrolled: vi.fn() };
		type(input, "hello");
		await flushFrames();
		expect(mounted.count.textContent).toBe("1 of 12");
	});
});
