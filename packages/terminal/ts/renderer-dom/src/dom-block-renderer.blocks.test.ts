import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	decodeBlocks,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const theme: TerminalTheme = warpDarkTheme;

async function loadedCore(): Promise<TerminalCore> {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
	return createTerminalCore({ columns: 16, scrollback: 100 });
}

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
	});
}

beforeAll(async () => {
	await loadedCore();
});

afterEach(() => {
	vi.restoreAllMocks();
});

function mountWith(input: string): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	return { core, host, renderer };
}

function feedOsc133Block(core: TerminalCore, command: string, lines: number, exitCode = 0): void {
	const start = `\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=${command}\x07\x1b]133;C\x07`;
	const body = Array.from({ length: lines }, (_unused, index) => `line-${index + 1}`).join("\n");
	const end = `\x1b]133;D;${exitCode}\x07`;
	core.feed(new TextEncoder().encode(`${start}${body}${end}`));
}

describe("pinned command header", () => {
	const APP_FONT = {
		family: "ui-monospace, monospace",
		sizePx: 14,
		lineHeight: 1.2,
		weight: 400,
		letterSpacingPx: 0,
		ligatures: false,
	};

	function mountTall(): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
		const core = createTerminalCore({ columns: 20, scrollback: 1000 });
		feedOsc133Block(core, "tall-cmd", 200);
		const host = document.createElement("div");
		Object.defineProperty(host, "clientHeight", { value: 100, configurable: true });
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setTheme(theme);
		renderer.setFont(APP_FONT);
		return { core, host, renderer };
	}

	it("hides when the block list is synthetic (no osc133 markers)", async () => {
		const { host, renderer } = mountWith("plain text");
		await flushRepaint();
		const pinned = host.querySelector('[data-testid="terminal-pinned-header"]') as HTMLElement;
		expect(pinned).not.toBeNull();
		expect(pinned.hidden).toBe(true);
		renderer.dispose();
	});

	it("pins the command once its original header has scrolled out of view", async () => {
		vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
			return { top: this.classList.contains("terminal-block") ? -200 : 0, left: 0, right: 0, bottom: 0, width: 0, height: 0, x: 0, y: 0, toJSON: () => ({}) };
		});
		const { host, renderer } = mountTall();
		await flushRepaint();
		const pinned = host.querySelector('[data-testid="terminal-pinned-header"]') as HTMLElement;
		expect(pinned).not.toBeNull();
		expect(pinned.hidden).toBe(false);
		expect(pinned.textContent).toContain("tall-cmd");
		const block = host.querySelector('[data-terminal-block-id="0:0"]');
		const perBlockHeader = block?.querySelector(".terminal-block-header");
		expect(perBlockHeader).not.toBeNull();
		expect(pinned).not.toBe(perBlockHeader);
		renderer.dispose();
	});

	it("does not duplicate an unscrolled header or show it over the alternate screen", async () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		feedOsc133Block(core, "pre-alt", 2);
		const host = document.createElement("div");
		Object.defineProperty(host, "clientHeight", { value: 100, configurable: true });
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setTheme(theme);
		renderer.setFont(APP_FONT);
		await flushRepaint();
		const pinned = host.querySelector('[data-testid="terminal-pinned-header"]') as HTMLElement;
		expect(pinned.hidden).toBe(true);
		core.feed(new TextEncoder().encode("\x1b[?1049h"));
		await flushRepaint();
		expect(pinned.hidden).toBe(true);
		renderer.dispose();
	});
});

function feedOsc133BlockWithExit(
	core: TerminalCore,
	command: string,
	lines: number,
	exitCode: number,
): void {
	const start = `\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=${command}\x07\x1b]133;C\x07`;
	const body = Array.from({ length: lines }, (_unused, i) => `line-${i + 1}`).join("\n");
	const end = `\x1b]133;D;${exitCode}\x07`;
	core.feed(new TextEncoder().encode(`${start}${body}${end}`));
}

describe("block filter", () => {
	const APP_FONT = {
		family: "ui-monospace, monospace",
		sizePx: 14,
		lineHeight: 1.2,
		weight: 400,
		letterSpacingPx: 0,
		ligatures: false,
	};

	function mountWithFilter(): {
		core: TerminalCore;
		host: HTMLElement;
		renderer: DomBlockRenderer;
	} {
		const core = createTerminalCore({ columns: 20, scrollback: 1000 });
		feedOsc133BlockWithExit(core, "ok-cmd", 4, 0);
		feedOsc133BlockWithExit(core, "fail-cmd", 4, 1);
		feedOsc133BlockWithExit(core, "ok-2", 4, 0);
		const host = document.createElement("div");
		Object.defineProperty(host, "clientHeight", { value: 500, configurable: true });
		document.body.append(host);
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setTheme(theme);
		renderer.setFont(APP_FONT);
		return { core, host, renderer };
	}

	it("renders all blocks when no filter is set", async () => {
		const { host, renderer } = mountWithFilter();
		await flushRepaint();
		const sections = host.querySelectorAll('[data-terminal-block-id]');
		expect(sections.length).toBe(3);
		renderer.dispose();
	});

	it("renders only matching blocks when a filter is set", async () => {
		const { host, renderer } = mountWithFilter();
		renderer.setFilter({ exitCodeNonZero: true });
		await flushRepaint();
		const sections = host.querySelectorAll('[data-terminal-block-id]');
		expect(sections.length).toBe(1);
		const visible = sections[0] as HTMLElement;
		expect(visible.textContent).toContain("fail-cmd");
		renderer.dispose();
	});

	it("restores all blocks when the filter is cleared", async () => {
		const { host, renderer } = mountWithFilter();
		renderer.setFilter({ exitCodeNonZero: true });
		await flushRepaint();
		expect(host.querySelectorAll('[data-terminal-block-id]').length).toBe(1);
		renderer.setFilter(null);
		await flushRepaint();
		expect(host.querySelectorAll('[data-terminal-block-id]').length).toBe(3);
		renderer.dispose();
	});

	it("does not mutate the underlying block ids across a filter-and-clear cycle", async () => {
		const { core, host, renderer } = mountWithFilter();
		await flushRepaint();
		const beforeIds = Array.from(host.querySelectorAll('[data-terminal-block-id]'))
			.map((el) => (el as HTMLElement).dataset.terminalBlockId ?? "");
		renderer.setFilter({ exitCodeNonZero: true });
		await flushRepaint();
		renderer.setFilter(null);
		await flushRepaint();
		const afterIds = Array.from(host.querySelectorAll('[data-terminal-block-id]'))
			.map((el) => (el as HTMLElement).dataset.terminalBlockId ?? "");
		expect(afterIds).toEqual(beforeIds);
		const blocks = decodeBlocks(core.snapshot());
		expect(blocks.length).toBe(3);
		renderer.dispose();
	});
});
