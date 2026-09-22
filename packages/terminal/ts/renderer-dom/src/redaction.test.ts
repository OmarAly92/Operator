import { describe, expect, it } from "vitest";
import { compileSecretPatterns, maskedTextRows, redactionMatches, REDACTION_MASK, secretRanges } from "./redaction";
import { logicalLineAt } from "./logical-lines";
import { selectedText, type TextRows } from "./selection-text";
import { ROW_END } from "./selection-model";

const patterns = compileSecretPatterns([
	{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b" },
	{ source: "bearer\\s+[A-Za-z0-9._-]{16,}", flags: "i" },
]);

const HAN = "漢";

function rowsOf(...texts: string[]): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => texts.length,
		rowText: (_id, row) => texts[row] ?? "",
		rowSpans: () => [],
		rowWrapped: () => false,
	};
}

describe("compileSecretPatterns", () => {
	it("adds the global flag, keeps the caller's own and drops a pattern that does not compile", () => {
		const compiled = compileSecretPatterns([{ source: "a" }, { source: "b", flags: "i" }, { source: "(" }]);
		expect(compiled.map((regex) => [regex.source, regex.flags])).toEqual([["a", "g"], ["b", "gi"]]);
	});
});

describe("secretRanges", () => {
	it("covers each match, keeps a leading capture group visible and merges overlaps", () => {
		expect(secretRanges("use ghp_ABCDEFGHIJKLMNOPQRSTU now", patterns)).toEqual([{ start: 4, end: 29 }]);
		const bearer = compileSecretPatterns([{ source: "(Bearer )[A-Za-z0-9._-]{16,}" }]);
		expect(secretRanges("h: Bearer abcdefghijklmnopqrst", bearer)).toEqual([{ start: 10, end: 30 }]);
		const overlapping = compileSecretPatterns([{ source: "abcdef" }, { source: "cdefgh" }]);
		expect(secretRanges("xxabcdefghxx", overlapping)).toEqual([{ start: 2, end: 10 }]);
	});
	it("finds nothing in clean text and with no patterns", () => {
		expect(secretRanges("nothing here", patterns)).toEqual([]);
		expect(secretRanges("ghp_ABCDEFGHIJKLMNOPQRSTU", [])).toEqual([]);
	});
});

describe("maskedTextRows", () => {
	it("replaces every secret cell with the mask, cell for cell", () => {
		const masked = maskedTextRows(rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now"), patterns, new Set());
		expect(masked.rowText("b", 0)).toBe(`use ${REDACTION_MASK.repeat(25)} now`);
		expect(masked.rowText("b", 0)).toHaveLength(33);
	});
	it("copies masked, so the token never reaches the clipboard", () => {
		const masked = maskedTextRows(rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now"), patterns, new Set());
		const text = selectedText({ start: { blockId: "b", row: 0, cell: 0 }, end: { blockId: "b", row: 0, cell: ROW_END } }, masked);
		expect(text).toBe(`use ${REDACTION_MASK.repeat(25)} now`);
		expect(text).not.toContain("ghp_");
	});
	it("masks a secret split across a soft wrap, on both rows", () => {
		const wrapped: TextRows = { ...rowsOf("head ghp_ABCDEFGHIJ", "KLMNOPQRSTU tail"), rowWrapped: (_id, row) => row === 0 };
		const masked = maskedTextRows(wrapped, patterns, new Set());
		expect(masked.rowText("b", 0)).toBe(`head ${REDACTION_MASK.repeat(14)}`);
		expect(masked.rowText("b", 1)).toBe(`${REDACTION_MASK.repeat(11)} tail`);
	});
	it("shifts a wide cluster after a non-ascii secret by the byte delta the mask introduced", () => {
		const passwordPattern = compileSecretPatterns([{ source: '(password:\\s*)[^\\s"\']{8,}' }]);
		const text = `password: пароль12345 ${HAN}tail`;
		const rows: TextRows = {
			blockIds: ["b"],
			firstRow: () => 0,
			rowCount: () => 1,
			rowText: () => text,
			rowSpans: () => [28, 31, 2],
			rowWrapped: () => false,
		};
		const masked = maskedTextRows(rows, passwordPattern, new Set());
		expect(masked.rowText("b", 0)).toBe(`password: ${REDACTION_MASK.repeat(11)} ${HAN}tail`);
		expect(Array.from(masked.rowSpans("b", 0))).toEqual([22, 25, 2]);
		const copied = selectedText(
			{ start: { blockId: "b", row: 0, cell: 0 }, end: { blockId: "b", row: 0, cell: ROW_END } },
			masked,
		);
		expect(copied.endsWith(`${HAN}tail`)).toBe(true);
	});
	it("leaves a revealed match alone and passes every other member through", () => {
		const rows = rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now");
		const line = logicalLineAt(rows, "b", 0)!;
		const key = redactionMatches(line, patterns)[0]!.key;
		const masked = maskedTextRows(rows, patterns, new Set([key]));
		expect(masked.rowText("b", 0)).toBe("use ghp_ABCDEFGHIJKLMNOPQRSTU now");
		expect(masked.blockIds).toEqual(["b"]);
		expect(masked.rowWrapped("b", 0)).toBe(false);
	});
});

describe("redactionMatches", () => {
	it("returns one stable key and range per secret on the line", () => {
		const line = logicalLineAt(rowsOf("a ghp_ABCDEFGHIJKLMNOPQRSTU b"), "b", 0)!;
		const matches = redactionMatches(line, patterns);
		expect(matches).toHaveLength(1);
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 2, endRow: 0, endCell: 27 });
		expect(redactionMatches(line, patterns)[0]!.key).toBe(matches[0]!.key);
	});
});
