import { describe, expect, it } from "vitest";
import { EditorBuffer } from "./buffer";

describe("EditorBuffer", () => {
	it("inserts at the cursor and advances it", () => {
		const buffer = new EditorBuffer();
		buffer.insert("git");
		buffer.insert(" log");
		expect(buffer.text).toBe("git log");
		expect(buffer.cursor).toBe(7);
	});

	it("deletes backward one code point, not one UTF-16 unit", () => {
		const buffer = new EditorBuffer();
		buffer.insert("ok🚀");
		buffer.deleteBackward();
		expect(buffer.text).toBe("ok");
	});

	it("deletes a word back to the previous boundary", () => {
		const buffer = new EditorBuffer();
		buffer.insert("git commit --amend");
		buffer.deleteWordBackward();
		expect(buffer.text).toBe("git commit ");
	});

	it("deletes back to the start of the line the cursor is on", () => {
		const buffer = new EditorBuffer();
		buffer.setText("git commit --amend", 11);
		buffer.deleteToLineStart();
		expect(buffer.text).toBe("--amend");
		expect(buffer.cursor).toBe(0);
	});

	it("keeps the lines above the one it kills", () => {
		const buffer = new EditorBuffer();
		buffer.setText("one\ntwo three", 11);
		buffer.deleteToLineStart();
		expect(buffer.text).toBe("one\nee");
		expect(buffer.cursor).toBe(4);
	});

	it("deletes forward to the end of the line only", () => {
		const buffer = new EditorBuffer();
		buffer.setText("one two\nthree", 3);
		buffer.deleteToLineEnd();
		expect(buffer.text).toBe("one\nthree");
		expect(buffer.cursor).toBe(3);
	});

	it("treats a newline as a line break for line motion", () => {
		const buffer = new EditorBuffer();
		buffer.setText("one\ntwo\nthree", 9);
		expect(buffer.cursorLineColumn()).toEqual({ line: 2, column: 1 });
		buffer.moveLine(-1);
		expect(buffer.cursorLineColumn().line).toBe(1);
	});

	it("clamps a cursor moved past either end instead of going negative", () => {
		const buffer = new EditorBuffer();
		buffer.setText("abc");
		buffer.moveBy(-99);
		expect(buffer.cursor).toBe(0);
		buffer.moveBy(99);
		expect(buffer.cursor).toBe(3);
	});

	it("reports lines for a multi-line command", () => {
		const buffer = new EditorBuffer();
		buffer.setText("for f in *; do\n  echo $f\ndone");
		expect(buffer.lines()).toEqual(["for f in *; do", "  echo $f", "done"]);
	});
});
