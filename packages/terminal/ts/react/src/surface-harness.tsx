import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { render, screen } from "@testing-library/react";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { TerminalSurface, warpDarkTheme } from "./index";

const wasmPath = join(
	dirname(fileURLToPath(import.meta.url)),
	"..",
	"..",
	"core",
	"wasm",
	"vt_core_bg.wasm",
);

export const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

export const theme: TerminalTheme = warpDarkTheme;
export const ignoreSend = () => undefined;
export const ignoreRaw = () => undefined;

export async function loadWasm(): Promise<void> {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
}

export function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

export function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => resolve());
	});
}

export function renderSurface(
	overrides: {
		onGeometry?: (columns: number, rows: number) => void;
		onSend?: (text: string) => void;
		onSendRaw?: (data: string) => void;
	} = {},
) {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const result = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			onSend={overrides.onSend ?? ignoreSend}
			onSendRaw={overrides.onSendRaw ?? ignoreRaw}
			onGeometry={overrides.onGeometry}
		/>,
	);
	const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
	const surface = host.parentElement as HTMLElement;
	return { core, host, surface, ...result };
}

export function setHostSize(host: HTMLElement, width: number, height: number): void {
	Object.defineProperty(host, "clientWidth", { value: width, configurable: true });
	Object.defineProperty(host, "clientHeight", { value: height, configurable: true });
	host.dispatchEvent(new Event("resize"));
}
