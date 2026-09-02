import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
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

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function mountWith(input: string): { core: TerminalCore; host: HTMLElement } {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	feed(core, input);
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	return { core, host };
}

describe("the terminal selection", () => {
	it("paints each selected row itself and clears it when the selection goes", () => {
		const { host } = mountWith("alpha\r\nbeta\r\ngamma");
		const rows = [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")];
		rows.forEach((row, index) => {
			row.getBoundingClientRect = () =>
				({ left: 0, right: 600, top: index * 17, bottom: index * 17 + 17 }) as DOMRect;
		});
		const selection = {
			isCollapsed: false,
			rangeCount: 1,
			getRangeAt: () => ({ intersectsNode: () => true, getClientRects: () => [] }),
		};
		const realGetSelection = document.getSelection;
		document.getSelection = () => selection as unknown as Selection;
		document.dispatchEvent(new Event("selectionchange"));

		// The row between the ends of the selection is filled whole -- Warp runs it
		// to the end of the row, where the browser would stop at the last glyph.
		expect(rows[1]!.style.backgroundImage).toContain("var(--terminal-selection)");
		expect(rows[1]!.style.backgroundImage).toContain("600px");
		expect(rows[0]!.style.backgroundImage).toBe("");

		selection.isCollapsed = true;
		document.dispatchEvent(new Event("selectionchange"));
		expect(rows[1]!.style.backgroundImage).toBe("");
		document.getSelection = realGetSelection;
	});
});
