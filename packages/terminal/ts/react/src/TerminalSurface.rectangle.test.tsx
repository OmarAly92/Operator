import { act, cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { cellHeight, cellWidth, feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

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

function drag(from: HTMLElement, x0: number, y0: number, x1: number, y1: number, init: MouseEventInit): void {
	mouse(from, "mousedown", x0, y0, { detail: 1, ...init });
	mouse(window, "mousemove", x1, y1, init);
	mouse(window, "mouseup", x1, y1, init);
}

async function mounted(text: string, onSendRaw = vi.fn()) {
	const writeClipboard = vi.fn(async (_text: string) => {});
	const host = { writeClipboard, readClipboard: async () => "", openLink: async () => {} };
	const { container, core } = renderSurface({ host, onSendRaw });
	act(() => { feed(core, text); });
	await flushRepaint();
	const rows = layoutRows(container);
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	const copy = () => {
		writeClipboard.mockClear();
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
		return writeClipboard.mock.lastCall?.[0];
	};
	return { rows, copy, onSendRaw };
}

const TEXT = "alpha beta\r\ngamma delta\r\nepsilon\r\n";

describe("Alt-drag", () => {
	const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
	beforeAll(async () => {
		await loadWasm();
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
	});
	afterEach(() => cleanup());
	afterAll(() => {
		if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
	});

	it("selects a rectangle and copies one slice per row", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		expect(copy()).toBe("lpha\namma\npsil");
		for (const row of rows.slice(0, 3)) expect(row.style.backgroundImage).toContain(`transparent ${cellWidth}px`);
	});

	it("takes Warp's Cmd+Option chord as a rectangle too", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true, metaKey: true });
		expect(copy()).toBe("lpha\namma\npsil");
	});

	it("needs Shift with Alt in a mouse-reporting program, and Alt wins over Shift", async () => {
		const { rows, copy, onSendRaw } = await mounted(`\x1b[?1000h\x1b[?1006h${TEXT}`);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		expect(onSendRaw).toHaveBeenCalled();
		onSendRaw.mockClear();
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true, shiftKey: true });
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(copy()).toBe("lpha\namma\npsil");
	});

	it("clears the selection on an Alt-click without a drag", async () => {
		const { rows, copy } = await mounted(TEXT);
		drag(rows[0]!, cellWidth + 1, cellHeight * 0.5, cellWidth * 5 - 1, cellHeight * 2.5, { altKey: true });
		mouse(rows[1]!, "mousedown", 1, cellHeight * 1.5, { detail: 1, altKey: true });
		mouse(window, "mouseup", 1, cellHeight * 1.5, { altKey: true });
		expect(copy()).toBeUndefined();
		expect(rows[0]!.style.backgroundImage).toBe("");
	});
});
