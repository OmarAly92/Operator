import { act, cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { TerminalSurface } from "./index";
import { feed, font, ignoreSend, loadWasm, theme } from "./surface-harness";

beforeAll(loadWasm);
afterEach(cleanup);

function mount() {
	const onSendRaw = vi.fn();
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const { container } = render(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={onSendRaw} />,
	);
	return { core, container, onSendRaw };
}

describe("Command+Left and Command+Right", () => {
	it("move a running program's input to the line start and end", () => {
		const { container, onSendRaw } = mount();
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;

		fireEvent.keyDown(editor, { key: "ArrowLeft", metaKey: true });
		fireEvent.keyDown(editor, { key: "ArrowRight", metaKey: true });

		expect(onSendRaw.mock.calls).toEqual([["\x01"], ["\x05"]]);
	});

	it("stay with the application on the alternate screen", () => {
		const { core, container, onSendRaw } = mount();
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const input = container.querySelector<HTMLElement>(".terminal-host [data-terminal-input]")!;

		fireEvent.keyDown(input, { key: "ArrowLeft", metaKey: true });
		fireEvent.keyDown(input, { key: "Backspace", metaKey: true });
		fireEvent.keyDown(input, { key: "ArrowLeft" });

		expect(onSendRaw.mock.calls).toEqual([["\x1b[D"]]);
	});
});
