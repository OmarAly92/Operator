import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, defaultStrings, initTerminalCore, type BlockRenderer, type FontConfig } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { createFindBar, type FindBar } from "./find-bar";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };

let cleanup: (() => void) | null = null;

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

afterEach(() => {
	cleanup?.();
	cleanup = null;
});

function frames(count: number): Promise<void> {
	return new Promise((resolve) => {
		let remaining = count;
		const step = () => {
			remaining -= 1;
			if (remaining <= 0) resolve();
			else requestAnimationFrame(step);
		};
		requestAnimationFrame(step);
	});
}

describe("find-bar first pick over a history longer than one scan step", () => {
	it("makes the match nearest the bottom of the view current and leaves the view at the bottom", async () => {
		const total = 40_000;
		const core = createTerminalCore({ columns: 60, limits: { rows: 100_000, bytes: 0xffff_ffff }, rows: 4 });
		const text: string[] = [];
		for (let i = 0; i < total; i += 1) text.push(i === 50 || i === total - 5 ? `needle row ${i} padding padding` : `line ${i} padding padding padding`);
		core.feed(new TextEncoder().encode(`${text.join("\r\n")}\r\n`));
		const container = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		Object.defineProperty(container, "clientHeight", { value: 200, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: rowHeight * total + 40, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		renderer.scrollToLatest();
		await frames(3);
		const bottom = container.scrollTop;
		const bar: FindBar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: {
				scrollToBlock: () => undefined,
				scrollToRow: (row, align) => renderer.scrollToRow(row, align),
				bottomVisibleRow: () => renderer.bottomVisibleRow(),
				invalidate: (range) => renderer.invalidate(range),
				afterRepaint: (listener) => renderer.onPaint(listener),
				highlightFind: (find) => renderer.setFindHighlights(find),
			},
			strings: defaultStrings,
		});
		cleanup = () => {
			bar.dispose();
			renderer.dispose();
		};
		bar.mount(container);
		bar.open();
		const input = container.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		input.value = "needle";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await frames(12);
		expect(container.querySelector("[data-terminal-find-count]")?.textContent).toBe("2 of 2");
		expect(container.scrollTop).toBe(bottom);
		expect(renderer.scrollAnchor()).toBeNull();
	});
});
