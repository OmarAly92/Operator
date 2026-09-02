import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const theme: TerminalTheme = warpDarkTheme;

async function loadedCore(): Promise<TerminalCore> {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
	return createTerminalCore({ columns: 16, scrollback: 100 });
}

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

describe("host element styling", () => {
	it("keeps the container a scroll container after the theme and font are applied", async () => {
		const core = await loadedCore();
		feed(core, "one\r\ntwo\r\n");
		const renderer = new DomBlockRenderer();
		const container = document.createElement("div");
		renderer.mount(container, core);
		expect(container.style.overflow).toBe("auto");
		expect(container.style.position).toBe("relative");
		expect(container.style.contain).toBe("strict");

		renderer.setTheme(theme);
		renderer.setFont(font);

		expect(container.style.overflow).toBe("auto");
		expect(container.style.position).toBe("relative");
		expect(container.style.contain).toBe("strict");
		expect(container.style.getPropertyValue("--terminal-background")).toBe(theme.background);
		renderer.dispose();
	});
});
