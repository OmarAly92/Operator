import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
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

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
	});
}

function mountWith(input: string): { core: TerminalCore; host: HTMLElement } {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	return { core, host };
}

describe("the terminal cursor", () => {
	it("draws on the row the core's cursor sits on", () => {
		const { host } = mountWith("alpha\r\n> hi");
		const cursor = host.querySelector("[data-terminal-cursor-cell]");
		expect(cursor).not.toBeNull();
		expect(cursor?.closest("[data-terminal-row]")?.getAttribute("data-terminal-row")).toBe("1");
		expect(cursor?.getAttribute("data-column")).toBe("4");
	});

	it("leaves the caret to the line editor while it owns the line", () => {
		const { host } = mountWith("alpha\r\n\x1b]7000;v=1;input-ready=1\x07");
		expect(host.querySelector("[data-terminal-cursor-cell]")).toBeNull();
	});

	it("comes back on the child's own prompt when it takes the line", async () => {
		const { core, host } = mountWith("alpha\r\n\x1b]7000;v=1;input-ready=1\x07");
		expect(host.querySelector("[data-terminal-cursor-cell]")).toBeNull();
		feed(core, "\x1b]7000;v=1;input-released=1\x07> ");
		await flushRepaint();
		const cursor = host.querySelector("[data-terminal-cursor-cell]");
		expect(cursor?.closest("[data-terminal-row]")?.getAttribute("data-terminal-row")).toBe("1");
		expect(cursor?.getAttribute("data-column")).toBe("2");
	});

	// A block stops at its last row with content, so a cursor parked on the blank
	// row below -- where a reflowing resize leaves it -- has no row to sit on. It
	// reappears as soon as the program writes there, which is the only moment the
	// user is looking for it.
	it("waits for the row it sits on to have content", () => {
		const { host } = mountWith("alpha\r\n");
		expect(host.querySelector("[data-terminal-cursor-cell]")).toBeNull();
	});
});
