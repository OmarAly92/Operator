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

describe("IME composition on the surface", () => {
	it("sends the composed text once, from the settled textarea, in the alternate screen", () => {
		vi.useFakeTimers();
		const onSendRaw = vi.fn();
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive onSend={() => undefined} onSendRaw={onSendRaw} />,
		);
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const input = container.querySelector<HTMLTextAreaElement>(".terminal-host [data-terminal-input]")!;
		act(() => {
			input.dispatchEvent(new CompositionEvent("compositionstart"));
			input.value = "に";
			input.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
			input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", keyCode: 229, bubbles: true }));
		});
		expect(onSendRaw).not.toHaveBeenCalled();
		act(() => {
			input.value = "日本";
			input.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
			vi.runAllTimers();
		});
		expect(onSendRaw).toHaveBeenCalledTimes(1);
		expect(onSendRaw).toHaveBeenCalledWith("日本");
		expect(container.querySelector(".terminal-host .terminal-composition-view")).not.toBeNull();
		vi.useRealTimers();
	});

	it("gives the normal-buffer editor an anchor on the transcript cursor", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
		);
		act(() => {
			feed(core, "> hi");
		});
		const input = container.querySelector<HTMLTextAreaElement>(".terminal-editor [data-terminal-input]")!;
		act(() => {
			input.dispatchEvent(new CompositionEvent("compositionstart"));
			input.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		});
		const view = container.querySelector<HTMLElement>(".terminal-editor .terminal-composition-view")!;
		expect(view.classList.contains("active")).toBe(true);
		expect(container.querySelector("[data-terminal-cursor-cell]")).not.toBeNull();
	});
});
