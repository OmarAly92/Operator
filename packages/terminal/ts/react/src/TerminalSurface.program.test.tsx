import { cleanup, render, within } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import { POINTER_SHAPE_PROPERTY, TerminalSurface } from "./index";
import { feed, font, ignoreRaw, ignoreSend, loadWasm, setHostSize, theme } from "./surface-harness";

beforeAll(loadWasm);
afterEach(cleanup);

function mount(onTitle?: (title: string) => void, onGeometry?: (columns: number, rows: number, cell?: { width: number; height: number }) => void) {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const result = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			onSend={ignoreSend}
			onSendRaw={ignoreRaw}
			onTitle={onTitle}
			onGeometry={onGeometry}
		/>,
	);
	const host = within(result.container).getByTestId("terminal-block-list").parentElement as HTMLElement;
	const surface = host.parentElement as HTMLElement;
	return { core, host, surface, ...result };
}

describe("TerminalSurface program messages", () => {
	it("applies the program's pointer shape to the surface and clears it on reset", () => {
		const { core, surface } = mount();
		feed(core, "\x1b]22;pointer\x07");
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("pointer");
		feed(core, "\x1b]22;\x07");
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("");
	});

	it("tells the host each new title", () => {
		const onTitle = vi.fn();
		const { core } = mount(onTitle);
		feed(core, "\x1b]0;◐ Working\x07");
		feed(core, "\x1b]0;◐ Working\x07");
		feed(core, "\x1b]2;done\x07");
		expect(onTitle.mock.calls).toEqual([["◐ Working"], ["done"]]);
	});

	it("stops listening to the core once unmounted", () => {
		const onTitle = vi.fn();
		const { core, surface, unmount } = mount(onTitle);
		feed(core, "\x1b]22;wait\x07");
		unmount();
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("");
		feed(core, "\x1b]2;after\x07");
		expect(onTitle).not.toHaveBeenCalled();
	});

	it("reports the measured cell size with the grid", () => {
		const measure = vi.spyOn(DomBlockRenderer.prototype, "measure").mockReturnValue({ cellWidth: 8, cellHeight: 16 });
		const onGeometry = vi.fn();
		const { host } = mount(undefined, onGeometry);
		setHostSize(host, 816, 416);
		expect(onGeometry).toHaveBeenLastCalledWith(98, 23, { width: 8, height: 16 });
		measure.mockRestore();
	});
});
