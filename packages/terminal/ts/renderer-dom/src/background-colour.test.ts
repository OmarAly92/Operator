import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { buildRowNode, type RowSource } from "./row-builder.js";

const ESC = "\x1b";

const wasmPath = join(
	dirname(fileURLToPath(import.meta.url)),
	"..",
	"..",
	"core",
	"wasm",
	"vt_core_bg.wasm",
);

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

function fed(text: string, columns = 40): TerminalCore {
	const core = createTerminalCore({ columns, scrollback: 100 });
	core.feed(new TextEncoder().encode(text));
	return core;
}

function firstRow(core: TerminalCore): HTMLElement {
	const snapshot = core.snapshot();
	const source: RowSource = {
		content: snapshot.content,
		rows: snapshot.rows,
		runRanges: snapshot.runRanges,
		stylePairs: snapshot.stylePairs,
	};
	return buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }));
}

function runs(row: HTMLElement): HTMLElement[] {
	return [...row.querySelectorAll<HTMLElement>("[data-terminal-run]")];
}

describe("background colours", () => {
	it("paints an indexed background on the run", () => {
		const row = firstRow(fed(`${ESC}[48;5;237mhi${ESC}[0m`));
		expect(runs(row)[0]!.style.backgroundColor).toBe("rgb(58, 58, 58)");
	});

	it("paints a truecolour background on the run", () => {
		const row = firstRow(fed(`${ESC}[48;2;55;55;55mhi${ESC}[0m`));
		expect(runs(row)[0]!.style.backgroundColor).toBe("rgb(55, 55, 55)");
	});

	it("paints an ansi background through the theme variable", () => {
		const row = firstRow(fed(`${ESC}[41mhi${ESC}[0m`));
		expect(runs(row)[0]!.style.backgroundColor).toBe("var(--terminal-ansi-1)");
	});

	it("leaves the default background unpainted so the terminal ground shows through", () => {
		const row = firstRow(fed("hi"));
		expect(runs(row)[0]!.style.backgroundColor).toBe("");
	});

	it("swaps the colours for reverse video", () => {
		const row = firstRow(fed(`${ESC}[31m${ESC}[7mhi${ESC}[0m`));
		const run = runs(row)[0]!;
		expect(run.style.color).toBe("var(--terminal-background)");
		expect(run.style.backgroundColor).toBe("var(--terminal-ansi-1)");
	});

	it("renders Claude Code's user-message band as one full-width painted run", () => {
		const columns = 40;
		const padding = " ".repeat(34);
		const band = `${ESC}[48;5;237m${ESC}[38;5;239m❯ ${ESC}[38;5;231mhi${ESC}[39m${padding}`;
		const row = firstRow(fed(band, columns));
		const all = runs(row);
		const painted = all.filter((run) => run.style.backgroundColor === "rgb(58, 58, 58)");
		expect(painted.length).toBe(all.length);
		expect(row.textContent).toBe(`❯ hi${padding}`);
		expect(row.textContent).toHaveLength(columns - 2);
	});
});
