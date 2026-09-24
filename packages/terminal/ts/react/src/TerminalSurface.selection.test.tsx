import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, cleanup } from "@testing-library/react";
import type { PathCandidate } from "@operator/terminal-core";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { cellHeight, cellWidth, feed, flushRepaint, loadWasm, renderSurface, setHostSize } from "./surface-harness";

function layoutRows(container: HTMLElement): HTMLElement[] {
	const rows = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	rows.forEach((row, index) => {
		row.getBoundingClientRect = () => ({ left: 0, right: 600, width: 600, top: index * cellHeight, bottom: (index + 1) * cellHeight, height: cellHeight, x: 0, y: index * cellHeight, toJSON: () => ({}) }) as DOMRect;
	});
	return rows;
}

function mouse(target: EventTarget, type: string, x: number, y: number, init: MouseEventInit = {}): void {
	target.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true, cancelable: true, ...init }));
}

describe("TerminalSurface selection", () => {
	beforeAll(loadWasm);
	afterEach(() => cleanup());

	it("selects with a drag, keeps it through output, and copies with the platform chord", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const writeClipboard = vi.fn(async () => {});
			const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
			const { container, core } = renderSurface({ host });
			act(() => { feed(core, "alpha\r\nbeta\r\ngamma\r\n"); });
			await flushRepaint();
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			const rows = layoutRows(container);
			mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
			mouse(window, "mousemove", cellWidth * 4, cellHeight * 1.5);
			mouse(window, "mouseup", cellWidth * 4, cellHeight * 1.5);
			act(() => { feed(core, "spinner\r\n"); });
			await flushRepaint();
			layoutRows(container);
			surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
			expect(writeClipboard).toHaveBeenCalledWith("alpha\nbeta");
		} finally {
			if (originalPlatform) {
				Object.defineProperty(navigator, "platform", originalPlatform);
			}
		}
	});

	it("does not start a selection under the drag threshold and clears on a plain click", async () => {
		const { container, core } = renderSurface();
		act(() => { feed(core, "alpha\r\nbeta\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 1.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 1.5);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		mouse(rows[1]!, "mousedown", 10, cellHeight * 1.5, { detail: 1 });
		mouse(window, "mousemove", 10.2, cellHeight * 1.5);
		mouse(window, "mouseup", 10.2, cellHeight * 1.5);
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("selects a word on double click and clears when the user types", async () => {
		const { container, core } = renderSurface();
		act(() => { feed(core, "see src/row-builder.ts now\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", cellWidth * 8, cellHeight * 0.5, { detail: 2 });
		mouse(window, "mouseup", cellWidth * 8, cellHeight * 0.5);
		expect(rows[0]!.style.backgroundImage).toContain(`transparent ${cellWidth * 4}px`);
		const editorHost = container.querySelector(".terminal-editor-host") as HTMLElement;
		editorHost.dispatchEvent(new KeyboardEvent("keydown", { key: "x", bubbles: true }));
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("leaves the drag to a mouse-reporting app unless shift is held", async () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => { feed(core, "\x1b[?1000h\x1b[?1006halpha\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, 1);
		mouse(window, "mouseup", cellWidth * 3, 1);
		expect(onSendRaw).toHaveBeenCalled();
		expect(rows[0]!.style.backgroundImage).toBe("");
		mouse(rows[0]!, "mousedown", 0, 1, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 3, 1, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 3, 1, { shiftKey: true });
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
	});

	it("reaches the copy chord after a drag-select on a pane that was never focused", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const writeClipboard = vi.fn(async () => {});
			const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
			const { container, core } = renderSurface({ host });
			act(() => { feed(core, "alpha\r\nbeta\r\ngamma\r\n"); });
			await flushRepaint();
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			const rows = layoutRows(container);
			expect(document.activeElement).not.toBe(surface);
			mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
			mouse(window, "mousemove", cellWidth * 4, cellHeight * 1.5);
			mouse(window, "mouseup", cellWidth * 4, cellHeight * 1.5);
			surface.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
			const target = document.activeElement ?? document.body;
			target.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
			expect(writeClipboard).toHaveBeenCalledWith("alpha\nbeta");
		} finally {
			if (originalPlatform) {
				Object.defineProperty(navigator, "platform", originalPlatform);
			}
		}
	});

	it("keeps a selection across a same-geometry refit but clears it on a real resize", async () => {
		const { container, core, host, refit } = renderSurface();
		setHostSize(host, 1000, 500);
		act(() => { feed(core, "alpha\r\nbeta\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container);
		mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		refit(1);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		setHostSize(host, 300, 150);
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("leaves a mousedown on the block chrome to the chrome, the way Warp's chrome takes its own clicks", async () => {
		const { container, core } = renderSurface();
		act(() => { feed(core, "\x1b]133;A\x07\x1b]133;B\x07ls\x1b]133;C\x07alpha\r\n\x1b]133;D;0\x07"); });
		await flushRepaint();
		layoutRows(container);
		const header = container.querySelector(".terminal-block-header") as HTMLElement;
		const event = new MouseEvent("mousedown", { clientX: 1, clientY: 1, button: 0, bubbles: true, cancelable: true });
		header.dispatchEvent(event);
		expect(event.defaultPrevented).toBe(false);
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		const rows = [...container.querySelectorAll<HTMLElement>("[data-terminal-row]")];
		expect(rows.every((row) => row.style.backgroundImage === "")).toBe(true);
	});

	it("clears an alt-screen selection when a key goes to the program", async () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => { feed(core, "\x1b[?1049halpha beta\r\n"); });
		await flushRepaint();
		const rows = layoutRows(container.querySelector(".terminal-alt-surface") as HTMLElement);
		mouse(rows[0]!, "mousedown", 0, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 4, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 4, cellHeight * 0.5);
		expect(rows[0]!.style.backgroundImage).toContain("var(--terminal-selection)");
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "j", bubbles: true, cancelable: true }));
		expect(onSendRaw).toHaveBeenCalledWith("j");
		expect(rows[0]!.style.backgroundImage).toBe("");
	});

	it("underlines the link under the pointer and opens it only with the platform modifier", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const openLink = vi.fn(async () => {});
			const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink };
			const { container, core, host: blockHost, refit } = renderSurface({ host });
			setHostSize(blockHost, 1000, 500);
			refit(1);
			act(() => { feed(core, "see https://x.y/doc now\r\n"); });
			await flushRepaint();
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			const rows = layoutRows(container);
			mouse(rows[0]!, "mousemove", cellWidth * 6.5, cellHeight * 0.5);
			await new Promise((resolve) => setTimeout(resolve, 0));
			expect(surface.classList.contains("terminal-link-hover")).toBe(true);
			expect(container.querySelectorAll(".terminal-link-underline")).toHaveLength(1);
			mouse(rows[0]!, "mousedown", cellWidth * 6.5, cellHeight * 0.5, { detail: 1 });
			mouse(window, "mouseup", cellWidth * 6.5, cellHeight * 0.5);
			expect(openLink).not.toHaveBeenCalled();
			mouse(rows[0]!, "mousedown", cellWidth * 6.5, cellHeight * 0.5, { detail: 1, metaKey: true });
			mouse(window, "mouseup", cellWidth * 6.5, cellHeight * 0.5, { metaKey: true });
			expect(openLink).toHaveBeenCalledWith("https://x.y/doc");
			mouse(rows[0]!, "mousemove", cellWidth * 1.5, cellHeight * 0.5);
			await new Promise((resolve) => setTimeout(resolve, 0));
			expect(surface.classList.contains("terminal-link-hover")).toBe(false);
		} finally {
			if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
		}
	});

	it("underlines the ~/ working directory Claude Code's startup banner prints beside its mascot", async () => {
		const banner = await readFile(join(dirname(fileURLToPath(import.meta.url)), "__fixtures__", "claude-code-banner"));
		const asked: string[][] = [];
		const host = {
			writeClipboard: async () => {},
			readClipboard: async () => "",
			openLink: async () => {},
			resolveFirstPath: async (candidates: readonly PathCandidate[]) => {
				asked.push(candidates.map((candidate) => candidate.path));
				const index = candidates.findIndex((candidate) => candidate.allowDirectory && candidate.path === "~/development/AI");
				return index < 0 ? null : { index, path: "/Users/me/development/AI" };
			},
			openPath: async () => {},
		};
		const { container, core, host: blockHost, refit } = renderSurface({ host });
		setHostSize(blockHost, 1200, 800);
		refit(1);
		act(() => { core.feed(new Uint8Array(banner)); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const rows = layoutRows(container);
		const row = rows.findIndex((element) => element.textContent?.includes("~/development/AI"));
		expect(row).toBeGreaterThanOrEqual(0);
		expect(rows[row]!.textContent).toContain("▝▝");
		mouse(rows[row]!, "mousemove", cellWidth * 14.5, cellHeight * (row + 0.5));
		await new Promise((resolve) => setTimeout(resolve, 0));
		expect(asked).toHaveLength(1);
		expect(asked[0]![0]).toBe("~/development/AI");
		expect(surface.classList.contains("terminal-link-hover")).toBe(true);
		expect(container.querySelectorAll(".terminal-link-underline").length).toBeGreaterThan(0);
	});

	it("keeps the host's path provider when the renderer is rebuilt under it", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const openPath = vi.fn(async () => {});
			const host = {
				writeClipboard: async () => {},
				readClipboard: async () => "",
				openLink: async () => {},
				resolveFirstPath: async (candidates: readonly PathCandidate[]) => {
					const index = candidates.findIndex((candidate) => candidate.path === "src/a.ts");
					return index < 0 ? null : { index, path: `/abs/${candidates[index]!.path}` };
				},
				openPath,
			};
			const { container, core, host: blockHost, refit, rebuild } = renderSurface({ host });
			setHostSize(blockHost, 1000, 500);
			refit(1);
			act(() => { feed(core, "edit src/a.ts:42 now\r\n"); });
			await flushRepaint();
			act(() => { rebuild(); });
			await flushRepaint();
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			const rows = layoutRows(container);
			mouse(rows[0]!, "mousemove", cellWidth * 8.5, cellHeight * 0.5);
			await new Promise((resolve) => setTimeout(resolve, 0));
			expect(surface.classList.contains("terminal-link-hover")).toBe(true);
			mouse(rows[0]!, "mousedown", cellWidth * 8.5, cellHeight * 0.5, { detail: 1, metaKey: true });
			mouse(window, "mouseup", cellWidth * 8.5, cellHeight * 0.5, { metaKey: true });
			expect(openPath).toHaveBeenCalledWith("/abs/src/a.ts", 42, undefined);
		} finally {
			if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
		}
	});
});
