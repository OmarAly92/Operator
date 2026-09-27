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

function click(target: EventTarget, x: number, y: number, init: MouseEventInit = {}): void {
	mouse(target, "mousedown", x, y, { detail: 1, ...init });
	mouse(window, "mouseup", x, y, init);
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
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "c", metaKey: true, bubbles: true, cancelable: true }));
		return writeClipboard.mock.lastCall?.[0];
	};
	return { rows, copy, onSendRaw };
}

describe("Shift+click", () => {
	const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
	beforeAll(async () => {
		await loadWasm();
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
	});
	afterEach(() => cleanup());
	afterAll(() => {
		if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
	});

	it("extends a dragged selection from its anchor to the clicked cell", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		click(rows[2]!, cellWidth * 4 + 1, cellHeight * 2.5, { shiftKey: true });
		expect(copy()).toBe("alpha\nbeta\ngamm");
	});

	it("selects from the last plain click when there is no selection", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		click(rows[0]!, cellWidth * 2 + 1, cellHeight * 0.5);
		click(rows[1]!, cellWidth * 3 - 1, cellHeight * 1.5, { shiftKey: true });
		expect(copy()).toBe("pha\nbet");
	});

	it("keeps extending while a Shift press is dragged", async () => {
		const { rows, copy } = await mounted("alpha\r\nbeta\r\ngamma\r\n");
		click(rows[0]!, 1, cellHeight * 0.5);
		mouse(rows[1]!, "mousedown", cellWidth + 1, cellHeight * 1.5, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 2 + 1, cellHeight * 2.5, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 2 + 1, cellHeight * 2.5, { shiftKey: true });
		expect(copy()).toBe("alpha\nbeta\nga");
	});

	it("does not extend on a Shift double-click", async () => {
		const { rows, copy } = await mounted("alpha beta\r\ngamma delta\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1 });
		mouse(window, "mousemove", cellWidth * 3, cellHeight * 0.5);
		mouse(window, "mouseup", cellWidth * 3, cellHeight * 0.5);
		click(rows[1]!, cellWidth * 7 + 1, cellHeight * 1.5, { shiftKey: true, detail: 2 });
		expect(copy()).toBe("delta");
	});

	it("extends inside a mouse-reporting program instead of reporting the click", async () => {
		const { rows, copy, onSendRaw } = await mounted("\x1b[?1000h\x1b[?1006halpha\r\nbeta\r\n");
		mouse(rows[0]!, "mousedown", 1, cellHeight * 0.5, { detail: 1, shiftKey: true });
		mouse(window, "mousemove", cellWidth * 2, cellHeight * 0.5, { shiftKey: true });
		mouse(window, "mouseup", cellWidth * 2, cellHeight * 0.5, { shiftKey: true });
		onSendRaw.mockClear();
		click(rows[1]!, cellWidth * 3 + 1, cellHeight * 1.5, { shiftKey: true });
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(copy()).toBe("alpha\nbet");
	});
});
