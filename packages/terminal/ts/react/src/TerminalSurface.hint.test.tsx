import { act, cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

function key(target: EventTarget, init: KeyboardEventInit): KeyboardEvent {
	const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init });
	target.dispatchEvent(event);
	return event;
}

describe("TerminalSurface hint mode", () => {
	beforeAll(loadWasm);
	afterEach(() => cleanup());

	it("enters on the chord, emits onHint for a typed label, and sends nothing to the pty", async () => {
		const onSendRaw = vi.fn();
		const onHint = vi.fn();
		const { container, core } = renderSurface({ onSendRaw, onHint });
		act(() => { feed(core, "see https://x.y/a now\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const chord = key(surface, { key: " ", code: "Space", ctrlKey: true, shiftKey: true });
		expect(chord.defaultPrevented).toBe(true);
		const typed = key(surface, { key: "a" });
		expect(typed.defaultPrevented).toBe(true);
		expect(onHint).toHaveBeenCalledWith({ ruleId: "url", text: "https://x.y/a" });
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("escape cancels and the next key reaches the pty again", async () => {
		const onSendRaw = vi.fn();
		const onHint = vi.fn();
		const { container, core } = renderSurface({ onSendRaw, onHint });
		act(() => { feed(core, "\x1b[?1049hsee https://x.y/a now\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		key(surface, { key: " ", code: "Space", ctrlKey: true, shiftKey: true });
		onSendRaw.mockClear();
		key(surface, { key: "Escape" });
		expect(onHint).not.toHaveBeenCalled();
		expect(onSendRaw).not.toHaveBeenCalled();
		key(surface, { key: "x" });
		expect(onSendRaw).toHaveBeenCalledWith("x");
	});

	it("leaves plain Ctrl+Space alone so readline still gets its NUL", async () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => { feed(core, "\x1b[?1049hidle\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		key(surface, { key: " ", code: "Space", ctrlKey: true });
		expect(onSendRaw).toHaveBeenCalledWith("\x00");
	});
});
