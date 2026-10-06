import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, render } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
} from "@operator/terminal-core";
import { TerminalSurface, warpDarkTheme } from "./index";

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};
const theme = warpDarkTheme;

const feed = (core: TerminalCore, text: string) => core.feed(new TextEncoder().encode(text));
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

type Confirm = NonNullable<HostCapabilities["confirmPaste"]>;

beforeAll(async () => {
	const bytes = await readFile(
		join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"),
	);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function pasteOn(surface: HTMLElement, text: string): Event {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: { types: ["text/plain"], getData: () => text, files: [] },
	});
	surface.dispatchEvent(event);
	return event;
}

function hostWith(confirmPaste: Confirm): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		confirmPaste,
	};
}

function mountAlt(host?: HostCapabilities) {
	const onSendRaw = vi.fn();
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const { container } = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive
			host={host}
			onSend={() => undefined}
			onSendRaw={onSendRaw}
		/>,
	);
	act(() => {
		feed(core, "\x1b[?1049h");
	});
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	return { core, surface, onSendRaw };
}

function mountPrimary(host: HostCapabilities) {
	const onSendRaw = vi.fn();
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	const { container } = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			host={host}
			onSend={() => undefined}
			onSendRaw={onSendRaw}
		/>,
	);
	act(() => {
		feed(core, "\x1b]7000;v=1;input-released=1\x07");
	});
	const editor = container.querySelector(".terminal-editor") as HTMLElement;
	return { core, editor, onSendRaw };
}

const pastedCalls = (onSendRaw: ReturnType<typeof vi.fn>, marker: string) =>
	onSendRaw.mock.calls.filter(([data]) => typeof data === "string" && data.includes(marker));

describe("pasting into the alternate screen", () => {
	it("sends the paste to the child, bracketed when it asked for brackets", () => {
		const { core, surface, onSendRaw } = mountAlt();
		expect(pasteOn(surface, "one\ntwo").defaultPrevented).toBe(true);
		expect(onSendRaw).toHaveBeenNthCalledWith(1, "one\rtwo");
		act(() => {
			feed(core, "\x1b[?2004h");
		});
		pasteOn(surface, "one\ntwo");
		expect(onSendRaw).toHaveBeenNthCalledWith(2, "\x1b[200~one\rtwo\x1b[201~");
	});

	it("asks the host first and sends nothing when the paste is declined", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { surface, onSendRaw } = mountAlt(hostWith(confirm));
		pasteOn(surface, "one\ntwo");
		await settle();
		expect(confirm).toHaveBeenCalledWith("one\ntwo", "newline");
		expect(pastedCalls(onSendRaw, "one")).toEqual([]);
	});

	it("sends the exact bytes once when the host confirms", async () => {
		const confirm = vi.fn<Confirm>(async () => true);
		const { surface, onSendRaw } = mountAlt(hostWith(confirm));
		pasteOn(surface, "one\ntwo");
		await settle();
		expect(pastedCalls(onSendRaw, "one")).toEqual([["one\rtwo"]]);
	});

	it("never asks inside bracketed paste and strips ESC and ^C", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { core, surface, onSendRaw } = mountAlt(hostWith(confirm));
		act(() => {
			feed(core, "\x1b[?2004h");
		});
		pasteOn(surface, "a\x1bb\x03c");
		await settle();
		expect(confirm).not.toHaveBeenCalled();
		expect(pastedCalls(onSendRaw, "abc")).toEqual([["\x1b[200~abc\x1b[201~"]]);
	});
});

describe("pasting on the primary screen while a child owns the line", () => {
	it("asks the host first and sends nothing when the paste is declined", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { editor, onSendRaw } = mountPrimary(hostWith(confirm));
		pasteOn(editor, "rm -rf ~\n");
		await settle();
		expect(confirm).toHaveBeenCalledWith("rm -rf ~\n", "newline");
		expect(pastedCalls(onSendRaw, "rm -rf")).toEqual([]);
	});

	it("sends the exact bytes once when the host confirms", async () => {
		const confirm = vi.fn<Confirm>(async () => true);
		const { editor, onSendRaw } = mountPrimary(hostWith(confirm));
		pasteOn(editor, "one\ntwo");
		await settle();
		expect(pastedCalls(onSendRaw, "one")).toEqual([["one\rtwo"]]);
	});
});
