import { act, cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import { feed, loadWasm, renderSurface } from "./surface-harness";

const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");

function setPlatform(value: string): void {
	Object.defineProperty(navigator, "platform", { value, configurable: true });
}

function restorePlatform(): void {
	if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
	else delete (navigator as { platform?: string }).platform;
}

function press(target: Element, init: KeyboardEventInit): KeyboardEvent {
	const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init });
	act(() => {
		target.dispatchEvent(event);
	});
	return event;
}

function editorOf(container: HTMLElement): HTMLElement {
	return container.querySelector(".terminal-editor") as HTMLElement;
}

function findInput(container: HTMLElement): HTMLInputElement | null {
	return container.querySelector<HTMLInputElement>("input[data-terminal-find-input]");
}

describe("TerminalSurface find shortcut", () => {
	beforeAll(loadWasm);

	afterEach(() => {
		cleanup();
		restorePlatform();
	});

	it("opens find with Cmd+F on macOS without the key reaching the editor or the pty", () => {
		setPlatform("MacIntel");
		const onSend = vi.fn();
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSend, onSendRaw });
		const editor = editorOf(container);
		editor.focus();
		const event = press(editor, { key: "f", code: "KeyF", metaKey: true });
		expect(event.defaultPrevented).toBe(true);
		expect(findInput(container)).not.toBeNull();
		expect(document.activeElement).toBe(findInput(container));
		expect(onSend).not.toHaveBeenCalled();
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("still opens find with Cmd+F after the surface rebuilds its renderer", () => {
		setPlatform("MacIntel");
		const { container, rebuild } = renderSurface();
		rebuild();
		const editor = editorOf(container);
		editor.focus();
		const event = press(editor, { key: "f", code: "KeyF", metaKey: true });
		expect(event.defaultPrevented).toBe(true);
		expect(findInput(container)).not.toBeNull();
		expect(document.activeElement).toBe(findInput(container));
	});

	it("leaves Ctrl+F to the shell on macOS", () => {
		setPlatform("MacIntel");
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const editor = editorOf(container);
		editor.focus();
		press(editor, { key: "f", code: "KeyF", ctrlKey: true });
		expect(findInput(container)).toBeNull();
		expect(onSendRaw).toHaveBeenCalledWith("\x06");
	});

	it("opens find with Ctrl+Shift+F elsewhere and leaves Ctrl+F to the shell", () => {
		setPlatform("Linux x86_64");
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const editor = editorOf(container);
		editor.focus();
		press(editor, { key: "f", code: "KeyF", ctrlKey: true });
		expect(findInput(container)).toBeNull();
		expect(onSendRaw).toHaveBeenCalledWith("\x06");
		onSendRaw.mockClear();
		const event = press(editor, { key: "F", code: "KeyF", ctrlKey: true, shiftKey: true });
		expect(event.defaultPrevented).toBe(true);
		expect(findInput(container)).not.toBeNull();
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("does not send the find chord to a full-screen program", () => {
		setPlatform("MacIntel");
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const composition = container.querySelector("[data-terminal-input]") as HTMLElement;
		const event = press(composition, { key: "f", code: "KeyF", metaKey: true });
		expect(event.defaultPrevented).toBe(true);
		expect(onSendRaw).not.toHaveBeenCalled();
	});
});

describe("TerminalSurface find shortcut with several panes", () => {
	beforeAll(loadWasm);

	afterEach(() => {
		cleanup();
		restorePlatform();
	});

	it("opens find only in the pane that has focus", () => {
		setPlatform("MacIntel");
		const first = renderSurface();
		const second = renderSurface();
		const editor = editorOf(first.container);
		editor.focus();
		press(editor, { key: "f", code: "KeyF", metaKey: true });
		expect(findInput(first.container)).not.toBeNull();
		expect(findInput(second.container)).toBeNull();
		expect(document.activeElement).toBe(findInput(first.container));
	});

	it("leaves Cmd+F alone while focus is outside every terminal", () => {
		setPlatform("MacIntel");
		const { container } = renderSurface();
		const field = document.createElement("input");
		document.body.append(field);
		field.focus();
		const event = press(field, { key: "f", code: "KeyF", metaKey: true });
		expect(event.defaultPrevented).toBe(false);
		expect(findInput(container)).toBeNull();
		expect(document.activeElement).toBe(field);
		field.remove();
	});

	it("hands focus back to the editor on Escape after Cmd+F is pressed again in the open bar", () => {
		setPlatform("MacIntel");
		const { container } = renderSurface();
		const editor = editorOf(container);
		editor.focus();
		press(editor, { key: "f", code: "KeyF", metaKey: true });
		press(findInput(container)!, { key: "f", code: "KeyF", metaKey: true });
		press(findInput(container)!, { key: "Escape" });
		expect(findInput(container)).toBeNull();
		expect(editor.contains(document.activeElement)).toBe(true);
	});
});

describe("TerminalSurface find current match", () => {
	beforeAll(loadWasm);

	afterEach(() => {
		cleanup();
		restorePlatform();
		vi.restoreAllMocks();
	});

	it("starts at the newest match at or above the renderer's bottom visible row", async () => {
		setPlatform("MacIntel");
		vi.spyOn(DomBlockRenderer.prototype, "bottomVisibleRow").mockReturnValue(2);
		const { container, core } = renderSurface();
		act(() => {
			feed(core, "hit 0\r\nhit 1\r\nhit 2\r\nhit 3\r\n");
		});
		const editor = editorOf(container);
		editor.focus();
		press(editor, { key: "f", code: "KeyF", metaKey: true });
		const input = findInput(container)!;
		await act(async () => {
			input.value = "hit";
			input.dispatchEvent(new Event("input", { bubbles: true }));
			await new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
		});
		expect(container.querySelector("[data-terminal-find-count]")?.textContent).toBe("3 of 4");
	});
});

describe("TerminalSurface find bar focus", () => {
	beforeAll(loadWasm);

	afterEach(() => {
		cleanup();
		restorePlatform();
	});

	function openFind(container: HTMLElement): HTMLInputElement {
		setPlatform("MacIntel");
		press(editorOf(container), { key: "f", code: "KeyF", metaKey: true });
		return findInput(container)!;
	}

	it("keeps focus in the find input when it is clicked", () => {
		const { container } = renderSurface();
		const input = openFind(container);
		editorOf(container).focus();
		act(() => {
			input.dispatchEvent(new MouseEvent("mousedown", { button: 0, bubbles: true, cancelable: true }));
			input.focus();
			input.dispatchEvent(new MouseEvent("mouseup", { button: 0, bubbles: true, cancelable: true }));
			input.click();
		});
		expect(document.activeElement).toBe(input);
	});

	it("keeps focus in the find input when the regex toggle is clicked", () => {
		const { container } = renderSurface();
		const input = openFind(container);
		const toggle = container.querySelector<HTMLButtonElement>("[data-terminal-find-regex]")!;
		act(() => {
			toggle.click();
		});
		expect(toggle.getAttribute("aria-pressed")).toBe("true");
		expect(document.activeElement).toBe(input);
	});

	it("still hands a click on the transcript to the editor", () => {
		const { container, host } = renderSurface();
		openFind(container);
		act(() => {
			host.click();
		});
		expect(editorOf(container).contains(document.activeElement)).toBe(true);
	});

	it("keeps typing in the find input out of a full-screen program", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		setPlatform("MacIntel");
		const composition = container.querySelector("[data-terminal-input]") as HTMLElement;
		press(composition, { key: "f", code: "KeyF", metaKey: true });
		const input = findInput(container)!;
		const event = press(input, { key: "a", code: "KeyA" });
		expect(event.defaultPrevented).toBe(false);
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("does not report a press on the find bar to a program tracking the mouse", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		const input = openFind(container);
		act(() => {
			feed(core, "\x1b[?1006h\x1b[?1000h");
		});
		const down = new MouseEvent("mousedown", { button: 0, bubbles: true, cancelable: true });
		const up = new MouseEvent("mouseup", { button: 0, bubbles: true, cancelable: true });
		act(() => {
			input.dispatchEvent(down);
			input.dispatchEvent(up);
		});
		expect(down.defaultPrevented).toBe(false);
		expect(onSendRaw).not.toHaveBeenCalled();
	});
});
