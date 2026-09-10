import { describe, expect, it } from "vitest";
import { buildRowNode, type RowSource } from "./row-builder.js";

function sourceOf(text: string, indent: number): RowSource {
	const content = new TextEncoder().encode(text);
	return {
		content,
		rows: new Uint32Array([0, content.length]),
		rowIndents: new Uint16Array([indent]),
		runRanges: new Uint32Array([0, 0]),
		stylePairs: new Uint32Array(),
	};
}

describe("row indent", () => {
	const decoder = new TextDecoder("utf-8", { fatal: true });

	it("pads a continuation row by its indent in cells", () => {
		const row = buildRowNode(sourceOf("wrapped text", 4), 0, 0, decoder, 8);
		expect(row.style.paddingLeft).toBe("32px");
		expect(row.textContent).toBe("wrapped text");
	});

	it("leaves a row with no indent flush", () => {
		const row = buildRowNode(sourceOf("first row", 0), 0, 0, decoder, 8);
		expect(row.style.paddingLeft).toBe("");
	});

	it("needs a cell width to pad", () => {
		const row = buildRowNode(sourceOf("wrapped text", 4), 0, 0, decoder);
		expect(row.style.paddingLeft).toBe("");
	});
});
