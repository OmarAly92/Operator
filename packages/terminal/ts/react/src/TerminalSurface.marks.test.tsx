import { act, cleanup, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer, type MarkRule } from "@operator/terminal-renderer-dom";
import { TerminalSurface } from "./index";
import { feed, font, ignoreRaw, loadWasm, theme } from "./surface-harness";

const ERROR_MARK: MarkRule = { pattern: "error", regex: false, colour: "rgba(255, 0, 0, 0.4)" };

function flushFrames(count = 6): Promise<void> {
	return new Promise((resolve) => {
		let remaining = count;
		const step = () => {
			remaining -= 1;
			if (remaining <= 0) resolve();
			else requestAnimationFrame(step);
		};
		requestAnimationFrame(step);
	});
}

describe("TerminalSurface marks", () => {
	beforeAll(loadWasm);
	afterEach(() => {
		cleanup();
		vi.restoreAllMocks();
	});

	it("passes the marks prop to the renderer and an empty list when there is none", () => {
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { rerender } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} />);
		expect(setMarks).toHaveBeenLastCalledWith([]);
		rerender(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />);
		expect(setMarks).toHaveBeenLastCalledWith([ERROR_MARK]);
	});

	it("does not recompile marks for a new array with the same rules", () => {
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const onSend = () => undefined;
		const { rerender } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />);
		setMarks.mockClear();
		rerender(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[{ ...ERROR_MARK }]} />);
		expect(setMarks).not.toHaveBeenCalled();
	});

	it("keeps the marks on a renderer the surface rebuilds for a new onSend", () => {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const surfaceWith = (onSend: () => void) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />
		);
		const { rerender } = render(surfaceWith(() => undefined));
		const first = mount.mock.contexts.at(-1);
		setMarks.mockClear();
		rerender(surfaceWith(() => undefined));
		const rebuilt = mount.mock.contexts.at(-1);
		expect(rebuilt).not.toBe(first);
		expect(setMarks).toHaveBeenLastCalledWith([ERROR_MARK]);
		expect(setMarks.mock.contexts.at(-1)).toBe(rebuilt);
	});

	it("routes the find bar's hits into the renderer's highlights and clears them when the surface unmounts", async () => {
		const setFindHighlights = vi.spyOn(DomBlockRenderer.prototype, "setFindHighlights");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "one\r\nerror\r\n");
		const { container, unmount } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} />);
		await act(async () => {
			document.dispatchEvent(new KeyboardEvent("keydown", { key: "F", code: "KeyF", ctrlKey: true, shiftKey: true, bubbles: true }));
		});
		const input = container.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		await act(async () => {
			input.value = "error";
			input.dispatchEvent(new Event("input", { bubbles: true }));
			await flushFrames();
		});
		expect(setFindHighlights).toHaveBeenLastCalledWith({ rows: new Set([1]), current: { row: 1, endRow: 1 } });
		unmount();
		expect(setFindHighlights).toHaveBeenLastCalledWith(null);
	});
});
