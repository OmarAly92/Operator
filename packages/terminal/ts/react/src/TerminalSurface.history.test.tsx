import { cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import type { CommandHistoryEntry, CommandHistorySource, QuickFixRule } from "@operator/terminal-editor";
import { TerminalSurface } from "./index";
import { feed, font, ignoreRaw, loadWasm, theme } from "./surface-harness";

const READY = "\x1b]7000;v=1;input-ready=1\x07";

beforeAll(loadWasm);
afterEach(cleanup);

function source(entries: CommandHistoryEntry[]): CommandHistorySource & { listeners: Set<() => void> } {
	const listeners = new Set<() => void>();
	return {
		listeners,
		entries: () => entries,
		subscribe: (listener) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
	};
}

describe("TerminalSurface command history and quick fixes", () => {
	it("recalls a command from the host's shared history with ArrowUp", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		feed(core, READY);
		const onSend = vi.fn();
		const { container } = render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				onSend={onSend}
				onSendRaw={ignoreRaw}
				commandHistory={source([{ command: "make release", at: 1 }])}
			/>,
		);
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		fireEvent.keyDown(editor, { key: "ArrowUp" });
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(onSend).toHaveBeenCalledWith("make release");
	});

	it("moves its subscription to a new history source and drops it on unmount", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const first = source([]);
		const second = source([]);
		const surface = (history: CommandHistorySource) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={vi.fn()} onSendRaw={ignoreRaw} commandHistory={history} />
		);
		const { rerender, unmount } = render(surface(first));
		expect(first.listeners.size).toBe(1);
		rerender(surface(second));
		expect(first.listeners.size).toBe(0);
		expect(second.listeners.size).toBe(1);
		unmount();
		expect(second.listeners.size).toBe(0);
	});

	it("shows a host rule's fix above the input box after a failed command", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const rule: QuickFixRule = { id: "make-clean", commandLine: /^make$/, exit: "error", fix: () => "make clean" };
		const onSend = vi.fn();
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} quickFixRules={[rule]} />,
		);
		feed(core, `\x1b]133;A\x07\x1b]7000;v=1;cmd=make\x07\x1b]133;C\x07boom\r\n\x1b]133;D;2\x07${READY}`);
		const row = container.querySelector<HTMLElement>(".terminal-editor-quick-fix");
		expect(row?.dataset.quickFix).toBe("make-clean");
		fireEvent.click(row!.querySelector("button")!);
		expect(onSend).not.toHaveBeenCalled();
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(onSend).toHaveBeenCalledWith("make clean");
	});
});
