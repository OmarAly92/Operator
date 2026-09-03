import { cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

beforeAll(loadWasm);

describe("TerminalSurface onPaint", () => {
	afterEach(() => {
		cleanup();
	});

	it("notifies the host when the renderer paints", async () => {
		const onPaint = vi.fn();
		const { core } = renderSurface({ onPaint });
		feed(core, "hello\r\n");
		await flushRepaint();
		expect(onPaint).toHaveBeenCalled();
	});

	it("swaps the callback without remounting the renderer", async () => {
		const first = vi.fn();
		const { core, host, rerenderWithPaint } = renderSurface({ onPaint: first });
		feed(core, "one\r\n");
		await flushRepaint();
		expect(first).toHaveBeenCalled();
		const blockListBefore = host.querySelector("[data-testid='terminal-block-list']");
		const second = vi.fn();
		rerenderWithPaint(second);
		first.mockClear();
		feed(core, "two\r\n");
		await flushRepaint();
		expect(second).toHaveBeenCalled();
		expect(first).not.toHaveBeenCalled();
		expect(host.querySelector("[data-testid='terminal-block-list']")).toBe(blockListBefore);
	});

	it("stops notifying after unmount", async () => {
		const onPaint = vi.fn();
		const { core, unmount } = renderSurface({ onPaint });
		feed(core, "before\r\n");
		await flushRepaint();
		onPaint.mockClear();
		unmount();
		feed(core, "after\r\n");
		await flushRepaint();
		expect(onPaint).not.toHaveBeenCalled();
	});
});
