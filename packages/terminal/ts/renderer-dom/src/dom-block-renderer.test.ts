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

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => resolve());
	});
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

		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(1);
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

	it("rebuilds the block when the core fires an onChange after a feed", async () => {
		const { core, host } = mountWith("alpha");
		expect(host.textContent).toBe("alpha");

		feed(core, "\r\nbeta");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
		expect(host.textContent).toBe("alphabeta");
	});

	it("writes the theme as CSS variables on the host without remounting", () => {
		const { host, renderer } = mountWith("alpha");
		const beforeBlock = host.querySelector('[data-terminal-block-id="0:0"]');

		const newTheme: TerminalTheme = { ...theme, foreground: "#abcdef" };
		renderer.setTheme(newTheme);
		const afterBlock = host.querySelector('[data-terminal-block-id="0:0"]');
		expect(afterBlock).toBe(beforeBlock);
		expect(afterBlock?.getAttribute("style") ?? "").toContain("--terminal-foreground: #abcdef");
	});

	it("exposes theme and font as CSS variables that the host can override", () => {
		const { host } = mountWith("alpha");
		const block = host.querySelector('[data-terminal-block-id="0:0"]') as HTMLElement;
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
		const block = host.querySelector('[data-terminal-block-id="0:0"]') as HTMLElement;
		block.scrollIntoView = () => undefined;
		expect(() => renderer.scrollToBlock("0:0", "start")).not.toThrow();
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
		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(1);

		renderer.dispose();
		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(0);
		expect(host.children).toHaveLength(0);

		feed(core, "beta");
		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(0);
	});

	it("renders only the visible slice of a tall block", () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		const core = createTerminalCore({ columns: 20, scrollback: 100_000 });
		for (let i = 0; i < 5_000; i += 1) {
			core.feed(new TextEncoder().encode(`line ${i}\n`));
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		const rows = container.querySelectorAll("[data-terminal-row]");
		expect(rows.length).toBeLessThan(60);
		expect(rows.length).toBeGreaterThan(0);
		renderer.dispose();
	});

	it("renders a block header inside each block with a data-block-status", () => {
		const { host } = mountWith("alpha\r\nbeta");
		const block = host.querySelector('[data-terminal-block-id="0:0"]') as HTMLElement;
		const header = block.querySelector(".terminal-block-header");
		expect(header).not.toBeNull();
		expect(header?.getAttribute("data-block-status")).toBe("plain");
	});

	it("opens at the tail and reaches earlier rows when scrolled up", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: 84_000, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 20, scrollback: 100_000 });
		for (let i = 0; i < 5_000; i += 1) {
			core.feed(new TextEncoder().encode(`line ${i}\n`));
		}
		const realSnapshot = core.snapshot.bind(core);
		const stableSnapshot = realSnapshot();
		core.snapshot = () => stableSnapshot;
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		const firstRowOffset = (): number => {
			const row = container.querySelector("[data-terminal-row]");
			return Number((row as HTMLElement | null)?.dataset.terminalRow ?? "-1");
		};

		const atTail = firstRowOffset();
		expect(atTail).toBeGreaterThan(4_900);

		container.scrollTop = 0;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();

		expect(firstRowOffset()).toBe(0);

		container.scrollTop = 83_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();

		expect(firstRowOffset()).toBeGreaterThan(4_900);
		renderer.dispose();
	});

	it("paints an idle surface synchronously instead of waiting out a frame", async () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 200, configurable: true });
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		await new Promise((resolve) => setTimeout(resolve, 12));

		let paintedSynchronously = false;
		const off = renderer.onPaint(() => {
			paintedSynchronously = true;
		});
		feed(core, "x");
		off();

		// A keystroke echoed into a quiet terminal must not wait for the next
		// animation frame; that cost the passthrough input-latency gate a full
		// frame and put it at twice xterm's p95.
		expect(paintedSynchronously).toBe(true);
		renderer.dispose();
	});

	it("still coalesces a burst rather than painting once per chunk", async () => {
		const core = createTerminalCore({ columns: 20, scrollback: 1000 });
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 200, configurable: true });
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		let paints = 0;
		const off = renderer.onPaint(() => {
			paints += 1;
		});
		for (let i = 0; i < 50; i += 1) feed(core, `line ${i}\n`);
		off();

		expect(paints).toBeLessThan(50);
		renderer.dispose();
	});

	it("reserves the height of the rows it did not render, so the scrollbar spans the block", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 20, scrollback: 100_000 });
		for (let i = 0; i < 5_000; i += 1) {
			core.feed(new TextEncoder().encode(`line ${i}\n`));
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		const spacers = Array.from(
			container.querySelectorAll<HTMLElement>("[data-terminal-row-spacer]"),
		);
		const reserved = spacers.reduce(
			(sum, spacer) => sum + Number.parseFloat(spacer.style.height || "0"),
			0,
		);
		const rendered = container.querySelectorAll("[data-terminal-row]").length;
		expect(rendered).toBeLessThan(200);
		expect(reserved).toBeGreaterThan(4_000 * 16);
		renderer.dispose();
	});
});

describe("extended colour", () => {
	it("paints truecolour and 256-colour runs instead of falling back to the foreground", async () => {
		const { host, renderer } = mountWith("\u001b[38;2;205;214;244mA\u001b[38;5;196mB");
		await flushRepaint();
		const colours = [...host.querySelectorAll("[data-terminal-run]")].map(
			(run) => (run as HTMLElement).style.color,
		);
		expect(colours).toContain("rgb(205, 214, 244)");
		expect(colours).toContain("rgb(255, 0, 0)");
		expect(colours).not.toContain("var(--terminal-foreground)");
		renderer.dispose();
	});
});

describe("measure", () => {
	it("measures the row box the css renders, not the glyph em box", () => {
		const { renderer } = mountWith("hello");
		const font = {
			family: "ui-monospace, monospace",
			sizePx: 12,
			lineHeight: 1.35,
			weight: 400,
			letterSpacingPx: 0,
			ligatures: false,
		};
		renderer.setFont(font);
		renderer.measure();
		const node = document.getElementById("terminal-m-measure") as HTMLElement;
		// An inline span's bounding box is the font's em box and ignores
		// line-height, so measuring one reports a shorter row than the css
		// actually paints and the pty is told it has more rows than fit.
		expect(node.style.display).toBe("inline-block");
		expect(node.style.lineHeight).toBe(`${font.lineHeight * font.sizePx}px`);
		renderer.dispose();
	});
});
