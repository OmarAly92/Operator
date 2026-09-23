import { cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { TerminalSurface } from "./index";
import { feed, font, ignoreRaw, ignoreSend, loadWasm, theme } from "./surface-harness";

beforeAll(loadWasm);

describe("TerminalSurface onDraftChange", () => {
	afterEach(() => {
		cleanup();
	});

	it("tells the host what the editor holds unsent, and follows a swapped callback without remounting", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "\x1b]7000;v=1;input-ready=1\x07");
		const first = vi.fn();
		const surface = (onDraftChange: (draft: string) => void) => (
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
				onDraftChange={onDraftChange}
			/>
		);
		const { container, rerender } = render(surface(first));
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		fireEvent.keyDown(editor, { key: "l" });
		expect(first).toHaveBeenLastCalledWith("l");
		const second = vi.fn();
		rerender(surface(second));
		expect(container.querySelector(".terminal-editor")).toBe(editor);
		fireEvent.keyDown(editor, { key: "s" });
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(second.mock.calls).toEqual([["ls"], [""]]);
		expect(first).toHaveBeenCalledTimes(1);
	});
});
