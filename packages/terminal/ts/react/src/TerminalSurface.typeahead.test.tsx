import { act, cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { feed, loadWasm, renderSurface } from "./surface-harness";

const READY = "\x1b]7000;v=1;input-ready=1\x07";
const RELEASED = "\x1b]7000;v=1;input-released=1\x07";
const report = (text: string) => `\x1b]7000;v=1;typeahead=${encodeURIComponent(text)}\x07`;

function pasteOn(target: HTMLElement, text: string): void {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: { types: ["text/plain"], getData: () => text, files: [] },
	});
	target.dispatchEvent(event);
}

function editorLines(container: HTMLElement): string[] {
	return [...container.querySelectorAll(".terminal-editor-line")].map((line) => line.textContent?.replace(/ /g, "") ?? "");
}

describe("typing ahead as a full-screen program exits", () => {
	beforeAll(loadWasm);
	afterEach(() => cleanup());

	it("moves keys sent to the alternate screen into the input box when the shell reports them", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, READY + RELEASED + "\x1b[?1049h");
		});
		const host = container.querySelector(".terminal-host") as HTMLElement;
		for (const key of ["q", "l", "s"]) host.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
		act(() => {
			feed(core, "\x1b[?1049l" + READY + report("ls"));
		});
		expect(editorLines(container)).toEqual(["ls"]);
		expect(onSendRaw.mock.calls.map(([data]) => data).join("")).toBe("qls\x15");
	});

	it("moves text pasted into the alternate screen into the input box when the shell reports it", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, READY + RELEASED + "\x1b[?1049h");
		});
		pasteOn(container.querySelector(".terminal-host") as HTMLElement, "pwd");
		act(() => {
			feed(core, "\x1b[?1049l" + READY + report("pwd"));
		});
		expect(editorLines(container)).toEqual(["pwd"]);
		expect(onSendRaw.mock.calls.map(([data]) => data).join("")).toBe("pwd\x15");
	});

	it("leaves a report alone when nothing was typed into the alternate screen", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, READY + RELEASED + "\x1b[?1049h");
		});
		act(() => {
			feed(core, "\x1b[?1049l" + READY + report("echo from-elsewhere"));
		});
		expect(editorLines(container)).toEqual([""]);
		expect(onSendRaw).not.toHaveBeenCalled();
	});
});
