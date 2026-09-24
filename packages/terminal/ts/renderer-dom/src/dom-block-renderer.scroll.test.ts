import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, decodeBlocks } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { font, loadedCore, feed, flushRepaint, mountWith } from "./renderer-harness";

beforeAll(async () => {
	await loadedCore();
});

afterEach(() => {
	vi.restoreAllMocks();
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

describe("scrollToRow", () => {
	it("brings a far row into the rendered window and refuses a row it does not hold", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 500; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		expect(container.querySelector('[data-terminal-row="10"]')).toBeNull();
		expect(renderer.scrollToRow(10, "center")).toBe(true);
		await flushRepaint();
		expect(container.querySelector('[data-terminal-row="10"]')?.textContent).toBe("line 10");
		expect(renderer.scrollToRow(100_000, "center")).toBe(false);
		renderer.dispose();
	});
});
