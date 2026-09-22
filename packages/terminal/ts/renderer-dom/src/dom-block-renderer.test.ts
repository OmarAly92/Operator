import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	decodeBlocks,
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

describe("DomBlockRenderer", () => {
	it("keeps background output visible while the editor owns the prompt", () => {
		const { host } = mountWith("\x1b]133;A\x07\x1b]7000;v=1;cwd=/tmp;input-ready=1\x07job finished\r\n");
		expect(host.querySelector("[data-terminal-row]")?.textContent).toBe("job finished");
	});

	it("shows the next command only after the editor releases the empty shell prompt", async () => {
		const { core, host } = mountWith("\x1b]133;A\x07\x1b]7000;v=1;cwd=/tmp\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07");
		expect(host.querySelectorAll("[data-terminal-block-id]")).toHaveLength(0);
		feed(core, "\x1b]7000;v=1;cmd=sleep%201;input-released=1\x07\x1b]133;C\x07");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-block-id]")).toHaveLength(1);
		expect(host.querySelector(".terminal-block-command")?.textContent).toBe("sleep 1");
	});


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

	it("drains enqueued bytes on the next frame and keeps going until the backlog is empty", async () => {
		const { core, host } = mountWith("alpha");
		let text = "";
		for (let index = 0; index < 20000; index += 1) text += `\r\nline ${index}`;
		core.enqueue(new TextEncoder().encode(text));
		expect(host.textContent).toBe("alpha");
		for (let frames = 0; frames < 200 && core.hasBacklog(); frames += 1) await flushRepaint();
		expect(core.hasBacklog()).toBe(false);
		expect(new TextDecoder().decode(core.snapshot().content).endsWith("line 19999")).toBe(true);
	});

	it("keeps draining enqueued bytes on the alternate screen until the backlog is empty", async () => {
		const { core, host } = mountWith("[?1049halpha");
		expect(host.querySelector("[data-terminal-alt-surface]")).not.toBeNull();
		let text = "";
		for (let index = 0; index < 400000; index += 1) text += `\r\nline ${index}`;
		core.enqueue(new TextEncoder().encode(text));
		expect(core.hasBacklog()).toBe(true);
		await flushRepaint();
		expect(core.hasBacklog()).toBe(true);
		for (let frames = 0; frames < 60 && core.hasBacklog(); frames += 1) await flushRepaint();
		expect(core.hasBacklog()).toBe(false);
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

	it("keeps a redrawing program inside one screen of rows", () => {
		const core = createTerminalCore({ columns: 80, rows: 24, scrollback: 100 });
		const encoder = new TextEncoder();
		for (let frame = 0; frame < 40; frame += 1) {
			core.feed(encoder.encode("\x1b[Hstatus line\x1b[K"));
		}
		expect(core.snapshot().rows.length / 2).toBeLessThanOrEqual(24);
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

	it("aligns an idle surface repaint to the next animation frame", async () => {
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

		expect(paintedSynchronously).toBe(false);
		await flushRepaint();
		expect(paintedSynchronously).toBe(true);
		off();
		renderer.dispose();
	});

	it("coalesces high-refresh callbacks to at most 60 paints per second", () => {
		let nextHandle = 1;
		const callbacks = new Map<number, FrameRequestCallback>();
		vi.spyOn(globalThis, "requestAnimationFrame").mockImplementation((callback) => {
			const handle = nextHandle;
			nextHandle += 1;
			callbacks.set(handle, callback);
			return handle;
		});
		vi.spyOn(globalThis, "cancelAnimationFrame").mockImplementation((handle) => {
			callbacks.delete(handle);
		});
		const runNextFrame = (timestamp: number) => {
			const entry = callbacks.entries().next().value as
				| [number, FrameRequestCallback]
				| undefined;
			if (!entry) throw new Error("animation frame was not scheduled");
			callbacks.delete(entry[0]);
			entry[1](timestamp);
		};

		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		const container = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		let paints = 0;
		const off = renderer.onPaint(() => {
			paints += 1;
		});

		feed(core, "a");
		feed(core, "b");
		feed(core, "c");
		expect(callbacks).toHaveLength(1);
		expect(paints).toBe(0);
		runNextFrame(108);
		expect(paints).toBe(1);

		feed(core, "d");
		runNextFrame(116);
		expect(paints).toBe(1);
		runNextFrame(125);
		expect(paints).toBe(2);
		off();
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

	it("does not paint a half frame", async () => {
		const { core, host } = mountWith("alpha");
		feed(core, "\x1b[?2026h\r\nbeta");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(1);
		expect(host.textContent).toBe("alpha");
		feed(core, "\x1b[?2026l");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
		expect(host.textContent).toBe("alphabeta");
	});

	it("paints a buffered frame once the deadline passes without more bytes", async () => {
		const { core, host } = mountWith("alpha");
		feed(core, "\x1b[?2026h\r\nbeta");
		await flushRepaint();
		expect(host.textContent).toBe("alpha");
		await new Promise((resolve) => setTimeout(resolve, 180));
		await flushRepaint();
		expect(host.textContent).toBe("alphabeta");
	});

	it("fires onBlockFinished once when a running block finishes, with the pane's visibility", async () => {
		const { core, host, renderer } = mountWith("\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n");
		document.body.append(host);
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		const events: unknown[] = [];
		renderer.onBlockFinished((event) => events.push(event));
		await flushRepaint();
		feed(core, "\x1b]133;D;3\x07");
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 3, visible: true });
		expect((events[0] as { durationMs: number | null }).durationMs).not.toBeNull();
		renderer.dispose();
		host.remove();
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

describe("alternate surface styling", () => {
	const APP_FONT = {
		family: "ui-monospace, monospace",
		sizePx: 12,
		lineHeight: 1.35,
		weight: 400,
		letterSpacingPx: 0,
		ligatures: false,
	};

	it("draws with the current font, not the default captured when it was created", async () => {
		// The host feeds buffered bytes before mounting, so the first repaint is
		// already an alt-screen paint and creates the surface before setFont ever
		// runs. Snapshotting the vars there pinned the surface to the 14px
		// default while geometry was measured at the app's 12px, so every row
		// rendered wider than the box that sized it.
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "\u001b[?1049hhello");
		const host = document.createElement("div");
		document.body.append(host);
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(APP_FONT);
		await flushRepaint();
		const surface = host.querySelector("[data-terminal-alt-surface]") as HTMLElement;
		expect(surface.getAttribute("style")).toContain("--terminal-font-size: 12px");
		expect(surface.getAttribute("style")).not.toContain("--terminal-font-size: 14px");
		renderer.dispose();
		host.remove();
	});

	it("renders bold and dim runs", async () => {
		const { host, renderer } = mountWith("\u001b[1mB\u001b[22m\u001b[2mD");
		await flushRepaint();
		const runs = [...host.querySelectorAll("[data-terminal-run]")] as HTMLElement[];
		const bold = runs.find((run) => run.textContent === "B");
		const dim = runs.find((run) => run.textContent === "D");
		expect(bold?.style.fontWeight).toBe("700");
		expect(dim?.style.opacity).toBe("0.55");
		expect(dim?.style.fontWeight).not.toBe("700");
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

	it("measure() reads layout once until the font changes", () => {
		const { renderer } = mountWith("alpha");
		const spy = vi.spyOn(HTMLElement.prototype, "getBoundingClientRect");
		renderer.measure();
		renderer.measure();
		renderer.blockContentInset();
		const measureNode = document.getElementById("terminal-m-measure")!;
		const measureCalls = () => spy.mock.contexts.filter((context) => context === measureNode).length;
		expect(measureCalls()).toBe(1);
		renderer.setFont({ ...font, sizePx: 16 });
		renderer.measure();
		renderer.measure();
		expect(measureCalls()).toBe(2);
		renderer.setTheme({ ...theme, foreground: "#ffffff" });
		renderer.measure();
		expect(measureCalls()).toBe(3);
	});
});

function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

describe("scroll anchor", () => {
	it("keeps the text under the top edge when rows are trimmed above the viewport", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 150, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		expect(renderer.scrollAnchor()).toBeNull();
		container.scrollTop = Math.round(rowHeight * 80);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		expect(anchor.stableRow).toBeGreaterThan(70);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		const before = container.scrollTop;
		for (let i = 100; i < 200; i += 1) feed(core, `line ${i}\r\n`);
		await flushRepaint();
		const trimmed = core.snapshot().firstStableRow;
		expect(trimmed).toBeGreaterThan(0);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(container.scrollTop).toBeCloseTo(before - trimmed * rowHeight, 3);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		renderer.dispose();
	});

	it("keeps it across a rewrap", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `${"x".repeat(25)} ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 60);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const textBefore = container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)!.textContent!.trim();
		core.resize(40, 2);
		await flushRepaint();
		const after = renderer.scrollAnchor()!;
		expect(after.stableRow).toBeLessThanOrEqual(anchor.stableRow);
		const textAfter = container.querySelector(`[data-terminal-row="${after.stableRow}"]`)!.textContent!;
		expect(textAfter).toContain(textBefore);
		renderer.dispose();
	});

	it("clamps a trimmed anchor to the first row", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 60, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 50; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		container.scrollTop = Math.round(renderer.measure().cellHeight * 5);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		for (let i = 50; i < 200; i += 1) feed(core, `line ${i}\r\n`);
		await flushRepaint();
		const first = core.snapshot().firstStableRow;
		expect(first).toBeGreaterThan(anchor.stableRow);
		expect(renderer.scrollAnchor()!.stableRow).toBe(first);
		renderer.dispose();
	});

	it("keeps the row under the top edge when a cold range rewraps", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 }, rows: 24 });
		for (let i = 0; i < 3000; i += 1) feed(core, `the quick brown fox jumps over the lazy dog ${i}\r\n`);
		core.resize(20, 24);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 10);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor();
		expect(anchor).not.toBeNull();
		const rowElement = container.querySelector<HTMLElement>(`[data-terminal-row="${anchor!.stableRow}"]`);
		expect(rowElement).toBeTruthy();
		expect(rowElement!.textContent!.length).toBeLessThanOrEqual(20);
		renderer.dispose();
	});

	it("keeps the anchor stable across a repeated repaint of an already-rewrapped cold range", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 }, rows: 24 });
		for (let i = 0; i < 3000; i += 1) feed(core, `the quick brown fox jumps over the lazy dog ${i}\r\n`);
		core.resize(20, 24);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 10);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const before = renderer.scrollAnchor()!;
		expect(before).not.toBeNull();
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const after = renderer.scrollAnchor()!;
		expect(after.stableRow).toBe(before.stableRow);
		renderer.dispose();
	});
});

describe("row pool", () => {
	const rowNode = (host: HTMLElement, stableRow: number): HTMLElement =>
		host.querySelector<HTMLElement>(`[data-terminal-row="${stableRow}"]`)!;

	it("row elements are reused across paints", async () => {
		const { core, host } = mountWith("one\r\ntwo\r\nthree");
		await flushRepaint();
		const first = rowNode(host, 0);
		const third = rowNode(host, 2);
		feed(core, "!");
		await flushRepaint();
		expect(rowNode(host, 0)).toBe(first);
		expect(rowNode(host, 2)).not.toBe(third);
		expect(rowNode(host, 2).textContent).toBe("three!");
	});

	it("an unchanged row is not rebuilt when another row changed", async () => {
		const { core, host } = mountWith("one\r\ntwo\r\nthree");
		await flushRepaint();
		const records: MutationRecord[] = [];
		const observer = new MutationObserver((batch) => records.push(...batch));
		observer.observe(host, { childList: true, subtree: true });
		observer.takeRecords();
		feed(core, "\x1b[2;1HTWO");
		await flushRepaint();
		records.push(...observer.takeRecords());
		const added = records
			.flatMap((record) => [...record.addedNodes])
			.filter((node): node is HTMLElement => node instanceof HTMLElement);
		observer.disconnect();
		expect(added.filter((node) => node.classList.contains("terminal-row")).map((node) => node.dataset.terminalRow)).toEqual(["1", "2"]);
		expect(added).toHaveLength(2);
		expect(added.every((node) => node.classList.contains("terminal-row") || node.classList.contains("terminal-run") || node.hasAttribute("data-terminal-cursor-cell"))).toBe(true);
		expect(rowNode(host, 1).textContent).toBe("TWO");
	});

	it("moves the cursor element instead of recreating it", async () => {
		const { core, host } = mountWith("one\r\ntwo");
		await flushRepaint();
		const cursor = host.querySelector<HTMLElement>("[data-terminal-cursor-cell]")!;
		expect(cursor.parentElement).toBe(rowNode(host, 1));
		feed(core, "\r\nthree");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-cursor-cell]")).toHaveLength(1);
		expect(host.querySelector("[data-terminal-cursor-cell]")).toBe(cursor);
		expect(cursor.parentElement).toBe(rowNode(host, 2));
	});

	it("a block scrolled out and back in keeps its nodes", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 16, scrollback: 1000, rows: 2 });
		for (const name of ["a", "b", "c"]) {
			feed(core, "\x1b]133;A\x07\x1b]133;C\x07");
			for (let i = 0; i < 40; i += 1) feed(core, `${name}${i}\r\n`);
			feed(core, "\x1b]133;D;0\x07");
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		const snapshot = core.snapshot();
		const last = decodeBlocks(snapshot).at(-1)!;
		const stable = snapshot.firstStableRow + last.firstRow + 30;
		const section = container.querySelector<HTMLElement>(`[data-terminal-block-id="${last.id}"]`)!;
		const row = rowNode(container, stable);
		expect(row).toBeTruthy();
		container.scrollTop = 0;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.querySelector(`[data-terminal-block-id="${last.id}"]`)).toBeNull();
		container.scrollTop = 99_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.querySelector(`[data-terminal-block-id="${last.id}"]`)).toBe(section);
		expect(rowNode(container, stable)).toBe(row);
		renderer.dispose();
	});
	it("clamps the scroller at its edges the way Warp's block list does", async () => {
		const { host, renderer } = mountWith("one\r\ntwo");
		await flushRepaint();
		expect(host.style.getPropertyValue("overscroll-behavior-y")).toBe("none");
		renderer.dispose();
	});
	it("does not fight an elastic overscroll past either edge", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 99_900, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 16, scrollback: 1000, rows: 2 });
		for (let i = 0; i < 200; i += 1) feed(core, `row${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		container.scrollTop = 99_930;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.scrollTop).toBe(99_930);
		container.scrollTop = 99_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		container.scrollTop = -30;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.scrollTop).toBe(-30);
		renderer.dispose();
	});
	it("repaints a row that was rewritten and then scrolled into history", async () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100, rows: 2 });
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		feed(core, "boot\r\nprogress 50%");
		await flushRepaint();
		const stable = Number(host.querySelector<HTMLElement>("[data-terminal-row]:last-of-type")?.dataset.terminalRow);
		expect(rowNode(host, stable).textContent).toBe("progress 50%");
		feed(core, "\rdone\x1b[K\r\ntail1\r\ntail2");
		await flushRepaint();
		expect(rowNode(host, stable).textContent).toBe("done");
		renderer.dispose();
	});
	it("rebuilds rows after a second font change at the same generation", async () => {
		const { host, renderer } = mountWith("one\r\ntwo");
		await flushRepaint();
		const first = rowNode(host, 0);
		renderer.setFont({ ...font, sizePx: 28 });
		await flushRepaint();
		expect(rowNode(host, 0)).not.toBe(first);
	});
	it("rebuilds a row dirtied while its block was pooled", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 16, scrollback: 1000, rows: 2 });
		for (const name of ["a", "b"]) {
			feed(core, "\x1b]133;A\x07\x1b]133;C\x07");
			for (let i = 0; i < 40; i += 1) feed(core, `${name}${i}\r\n`);
			feed(core, "\x1b]133;D;0\x07");
		}
		feed(core, "\x1b]133;A\x07\x1b]133;C\x07");
		for (let i = 0; i < 40; i += 1) feed(core, `c${i}\r\n`);
		feed(core, "progress 50%");
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		container.scrollTop = 99_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const progress = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")].find((node) => node.textContent === "progress 50%")!;
		expect(progress).toBeTruthy();
		const stable = Number(progress.dataset.terminalRow);
		const blockId = progress.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		container.scrollTop = 0;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.querySelector(`[data-terminal-block-id="${blockId}"]`)).toBeNull();
		feed(core, "\rdone\x1b[K\r\ntail1\r\ntail2");
		await flushRepaint();
		container.scrollTop = 99_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(rowNode(container, stable).textContent).toBe("done");
		renderer.dispose();
	});
});
