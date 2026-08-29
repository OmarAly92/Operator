import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	validateRowRange,
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

beforeAll(async () => {
	await loadedCore();
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

describe("DomBlockRenderer", () => {
	it("renders one block, one row node per row, and one span per style run", () => {
		const { host } = mountWith("[31mred[0m café\r\nplain");

		expect(host.querySelectorAll('[data-terminal-block-id="synthetic-0"]')).toHaveLength(1);
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
		expect(host.querySelectorAll("[data-terminal-run]")).toHaveLength(3);
		expect(host.textContent).toBe("red caféplain");
	});

	it("paints run spans with the correct CSS variable for each style code", () => {
		const { host } = mountWith("[31mred[0m café\r\nplain");
		const runs = host.querySelectorAll("[data-terminal-run]");

		expect(runs).toHaveLength(3);
		expect(runs[0]?.getAttribute("style")).toContain("color: var(--terminal-ansi-1)");
		expect(runs[1]?.getAttribute("style")).toContain("color: var(--terminal-foreground)");
		expect(runs[2]?.getAttribute("style")).toContain("color: var(--terminal-foreground)");
	});

	it("rebuilds the block when the core fires an onChange after a feed", () => {
		const { core, host } = mountWith("alpha");
		expect(host.textContent).toBe("alpha");

		feed(core, "\r\nbeta");
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
		expect(host.textContent).toBe("alphabeta");
	});

	it("writes the theme as CSS variables on the host without remounting", () => {
		const { host, renderer } = mountWith("alpha");
		const beforeBlock = host.querySelector('[data-terminal-block-id="synthetic-0"]');

		const newTheme: TerminalTheme = { ...theme, foreground: "#abcdef" };
		renderer.setTheme(newTheme);
		const afterBlock = host.querySelector('[data-terminal-block-id="synthetic-0"]');
		expect(afterBlock).toBe(beforeBlock);
		expect(afterBlock?.getAttribute("style") ?? "").toContain("--terminal-foreground: #abcdef");
	});

	it("exposes theme and font as CSS variables that the host can override", () => {
		const { host } = mountWith("alpha");
		const block = host.querySelector('[data-terminal-block-id="synthetic-0"]') as HTMLElement;
		const styleAttr = block.getAttribute("style") ?? "";
		expect(styleAttr).toContain("--terminal-foreground:");
		expect(styleAttr).toContain("--terminal-ansi-0:");
		expect(styleAttr).toContain("--terminal-ansi-15:");
		expect(styleAttr).toContain("--terminal-font-family:");
		expect(styleAttr).toContain("--terminal-font-size:");
	});

	it("accepts a half-open invalidation range covering the second row", () => {
		const { renderer } = mountWith("row0\r\nrow1\r\nrow2");
		expect(() => renderer.invalidate({ start: 1, end: 2 })).not.toThrow();
	});

	it("rejects an invalid row range with end < start", () => {
		const { renderer } = mountWith("row0");
		expect(() => renderer.invalidate({ start: 3, end: 1 })).toThrow();
	});

	it("rejects an invalid row range with non-finite values", () => {
		const { renderer } = mountWith("row0");
		expect(() => renderer.invalidate({ start: Number.NaN, end: 1 })).toThrow();
	});

	it("accepts validateRowRange's happy path and rejects bad input", () => {
		expect(() => validateRowRange({ start: 0, end: 0 })).not.toThrow();
		expect(() => validateRowRange({ start: -1, end: 1 })).toThrow();
		expect(() => validateRowRange({ start: 0, end: -1 })).toThrow();
	});

	it("scrolls to the synthetic block by id", () => {
		const { host, renderer } = mountWith("alpha\r\nbeta");
		const block = host.querySelector('[data-terminal-block-id="synthetic-0"]') as HTMLElement;
		block.scrollIntoView = () => undefined;
		expect(() => renderer.scrollToBlock("synthetic-0", "start")).not.toThrow();
	});

	it("rejects an unknown block id with a thrown error", () => {
		const { renderer } = mountWith("alpha");
		expect(() => renderer.scrollToBlock("missing", "start")).toThrow();
	});

	it("measures one hidden M using the configured font and returns finite cell metrics", () => {
		const { renderer } = mountWith("alpha");
		const metrics = renderer.measure();
		expect(Number.isFinite(metrics.cellWidth)).toBe(true);
		expect(Number.isFinite(metrics.cellHeight)).toBe(true);
		expect(metrics.cellWidth).toBeGreaterThan(0);
		expect(metrics.cellHeight).toBeGreaterThan(0);
	});

	it("unsubscribes from the core and removes all rendered DOM on dispose", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "alpha");
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setTheme(theme);
		renderer.setFont(font);
		expect(host.querySelectorAll('[data-terminal-block-id="synthetic-0"]')).toHaveLength(1);

		renderer.dispose();
		expect(host.querySelectorAll('[data-terminal-block-id="synthetic-0"]')).toHaveLength(0);
		expect(host.children).toHaveLength(0);

		feed(core, "beta");
		expect(host.querySelectorAll('[data-terminal-block-id="synthetic-0"]')).toHaveLength(0);
	});
});
