import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

export const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

export const theme: TerminalTheme = warpDarkTheme;

export async function loadedCore(): Promise<TerminalCore> {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
	return createTerminalCore({ columns: 16, scrollback: 100 });
}

export function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

export function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
	});
}

// jsdom lays nothing out, so a decoration box over a zero-width row collapses
// to nothing. Only rows get a rect here; the measure node keeps jsdom's own.
export function stubRowLayout(): void {
	const original = HTMLElement.prototype.getBoundingClientRect;
	vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
		if (!this.hasAttribute("data-terminal-row")) return original.call(this);
		const row = Number(this.dataset.terminalRow);
		const top = row * 20;
		return { x: 0, y: top, left: 0, top, right: 200, bottom: top + 20, width: 200, height: 20, toJSON: () => ({}) } as DOMRect;
	});
}

export function mountWith(input: string): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer } {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	return { core, host, renderer };
}
