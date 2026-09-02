import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, render } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
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

describe("pasting into the alternate screen", () => {
	it("sends the paste to the child, bracketed when it asked for brackets", () => {
		const onSendRaw = vi.fn();
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive
				onSend={() => undefined}
				onSendRaw={onSendRaw}
			/>,
		);
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		expect(pasteOn(surface, "one\ntwo").defaultPrevented).toBe(true);
		expect(onSendRaw).toHaveBeenNthCalledWith(1, "one\rtwo");
		act(() => {
			feed(core, "\x1b[?2004h");
		});
		pasteOn(surface, "one\ntwo");
		expect(onSendRaw).toHaveBeenNthCalledWith(2, "\x1b[200~one\rtwo\x1b[201~");
	});
});
