import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	decodeBlocks,
	defaultStrings,
	initTerminalCore,
	type BlockRenderer,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";
import { createFindBar, type FindBarHost } from "./find-bar";

const wasmPath = join(
	dirname(fileURLToPath(import.meta.url)),
	"..",
	"..",
	"core",
	"wasm",
	"vt_core_bg.wasm",
);

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const theme: TerminalTheme = warpDarkTheme;

function flushFrames(count: number = 4): Promise<void> {
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

function feedBlocks(core: TerminalCore, count: number): void {
	const encoder = new TextEncoder();
	for (let index = 0; index < count; index += 1) {
		core.feed(
			encoder.encode(
				`\x1b]133;A\x07\x1b]133;C\x07line ${index} of text\x1b]133;D;0\x07\r\n`,
			),
		);
	}
}

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

afterEach(() => {
	vi.restoreAllMocks();
});

function makeMountedCore(
	scrollback: number = 1000,
): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 40, scrollback, rows: 1 });
	feedBlocks(core, 5);
	const host = document.createElement("div");
	Object.defineProperty(host, "clientHeight", { value: 800, configurable: true });
	Object.defineProperty(host, "scrollHeight", { value: 2000, configurable: true });
	Object.defineProperty(host, "scrollTop", { value: 1500, configurable: true, writable: true });
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	return { core, host, renderer };
}

function scrollbar(
	core: TerminalCore,
	renderer: DomBlockRenderer,
): { scrollToBlock: ReturnType<typeof vi.fn> } {
	const spy = vi.fn((_id: import("@operator/terminal-core").BlockId, _align: "start" | "center" | "end") => {
		void _id;
		void _align;
	});
	renderer.scrollToBlock = spy;
	void core;
	void renderer;
	return { scrollToBlock: spy };
}

function makeBarHost(
	renderer: DomBlockRenderer,
): FindBarHost {
	return {
		scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
		invalidate: (range) => renderer.invalidate(range),
		afterRepaint: (listener) => renderer.onPaint(listener),
	};
}

describe("find-bar", () => {
	let unmount: (() => void) | null = null;
	beforeEach(() => {
		unmount = null;
	});
	afterEach(() => {
		unmount?.();
		unmount = null;
	});

	it("opens, types a query, marks rendered rows for matches, and updates the count", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();

		const input = host.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		);
		expect(input).not.toBeNull();
		input!.focus();
		input!.value = "line 0";
		input!.dispatchEvent(new Event("input", { bubbles: true }));

		await flushFrames(8);

		const count = host.querySelector<HTMLElement>("[data-terminal-find-count]");
		expect(count).not.toBeNull();
		expect(count!.textContent).toMatch(/1/);
		expect(count!.textContent).toMatch(/of/);

		const blockZero = host.querySelector<HTMLElement>(
			'[data-terminal-block-id="0:0"]',
		);
		const matchedRow = blockZero?.querySelector<HTMLElement>(
			'[data-terminal-row="0"]',
		);
		expect(matchedRow?.classList.contains("terminal-find-row-match")).toBe(true);

		const blockOne = host.querySelector<HTMLElement>(
			'[data-terminal-block-id="0:1"]',
		);
		const unmatchedRow = blockOne?.querySelector<HTMLElement>(
			'[data-terminal-row="0"]',
		);
		expect(unmatchedRow?.classList.contains("terminal-find-row-match")).toBe(
			false,
		);

		bar.dispose();
	});

	it("Enter walks to the next match and calls scrollToBlock on the renderer", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();
		const { scrollToBlock } = scrollbar(core, renderer);

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();

		const input = host.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		)!;
		input.focus();
		input.value = "line";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(8);

		input.dispatchEvent(
			new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }),
		);
		await flushFrames(2);

		expect(scrollToBlock).toHaveBeenCalled();
		const calls = scrollToBlock.mock.calls;
		const lastCall = calls[calls.length - 1]!;
		const blocks = decodeBlocks(core.snapshot());
		const knownIds = new Set(blocks.map((b) => b.id));
		expect(knownIds.has(lastCall[0] as string)).toBe(true);
		expect(lastCall[1]).toBe("center");

		bar.dispose();
	});

	it("Shift+Enter walks to the previous match", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();
		const { scrollToBlock } = scrollbar(core, renderer);

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();

		const input = host.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		)!;
		input.focus();
		input.value = "line";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(8);

		const before = scrollToBlock.mock.calls.length;
		input.dispatchEvent(
			new KeyboardEvent("keydown", {
				key: "Enter",
				shiftKey: true,
				bubbles: true,
				cancelable: true,
			}),
		);
		await flushFrames(2);

		expect(scrollToBlock.mock.calls.length).toBeGreaterThan(before);
		bar.dispose();
	});

	it("Escape closes the bar, removes highlight, and restores prior focus", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();

		const trigger = document.createElement("button");
		trigger.textContent = "open-find";
		document.body.append(trigger);
		trigger.focus();
		trigger.remove();

		const outside = document.createElement("input");
		document.body.append(outside);
		outside.focus();

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();

		const input = host.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		)!;
		input.focus();
		input.value = "line 0";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(8);

		const before = host.querySelector('[data-terminal-find-bar]');
		expect(before).not.toBeNull();
		const blockZero = host.querySelector<HTMLElement>(
			'[data-terminal-block-id="0:0"]',
		);
		expect(
			blockZero?.querySelector('[data-terminal-row="0"]')?.classList.contains(
				"terminal-find-row-match",
			),
		).toBe(true);

		input.dispatchEvent(
			new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }),
		);
		await flushFrames(2);

		expect(host.querySelector('[data-terminal-find-bar]')).toBeNull();
		expect(
			blockZero?.querySelector('[data-terminal-row="0"]')?.classList.contains(
				"terminal-find-row-match",
			),
		).toBe(false);

		expect(document.activeElement).toBe(outside);
		outside.remove();
		bar.dispose();
	});

	it("counts matches in blocks that are not currently rendered (below the fold)", async () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100_000, rows: 1 });
		const encoder = new TextEncoder();
		for (let index = 0; index < 600; index += 1) {
			core.feed(
				encoder.encode(
					`\x1b]133;A\x07\x1b]133;C\x07line ${index} of text\x1b]133;D;0\x07\r\n`,
				),
			);
		}
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 80, configurable: true });
		document.body.append(container);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setTheme(theme);
		renderer.setFont(font);
		unmount = () => {
			renderer.dispose();
			container.remove();
		};

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(container);
		bar.open();

		const input = container.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		)!;
		input.focus();
		input.value = "line 500";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(12);

		const count = container.querySelector<HTMLElement>(
			"[data-terminal-find-count]",
		);
		expect(count?.textContent).toMatch(/1/);

		const allBlocks = decodeBlocks(core.snapshot());
		const targetBlock = allBlocks.find((b) => b.firstRow === 500);
		expect(targetBlock).toBeDefined();
		const targetId = targetBlock!.id;
		const visibleBlockIds = new Set(
			Array.from(
				container.querySelectorAll<HTMLElement>("[data-terminal-block-id]"),
			).map((node) => node.dataset.terminalBlockId),
		);
		expect(visibleBlockIds.has(targetId)).toBe(false);

		const { scrollToBlock } = scrollbar(core, renderer);
		input.dispatchEvent(
			new KeyboardEvent("keydown", {
				key: "Enter",
				bubbles: true,
				cancelable: true,
			}),
		);
		await flushFrames(8);

		expect(scrollToBlock).toHaveBeenCalled();
		const calledIds = scrollToBlock.mock.calls.map((call) => call[0] as string);
		expect(calledIds).toContain(targetId);

		bar.dispose();
	});

	it("typing cancels the in-flight session and opens a fresh one", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();

		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: makeBarHost(renderer),
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();

		const input = host.querySelector<HTMLInputElement>(
			'input[data-terminal-find-input]',
		)!;
		input.focus();
		input.value = "line";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(4);

		input.value = "of text";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(8);

		const count = host.querySelector<HTMLElement>("[data-terminal-find-count]");
		expect(count?.textContent).toMatch(/5/);

		bar.dispose();
	});
});
