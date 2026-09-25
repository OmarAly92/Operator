import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { compileMarkRegex, initTerminalCore, markRegexValid } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

describe("compileMarkRegex", () => {
	it("returns each match as a UTF-16 start and end", () => {
		const regex = compileMarkRegex("err(or)?")!;
		expect([...regex.ranges("é err, error")]).toEqual([2, 5, 7, 12]);
		regex.dispose();
	});

	it("returns null for a pattern the linear-time engine rejects", () => {
		expect(compileMarkRegex("(oops")).toBeNull();
		expect(compileMarkRegex("(?=x)")).toBeNull();
		expect(compileMarkRegex("")).toBeNull();
	});

	it("finishes a pattern that would hang a backtracking engine", () => {
		const regex = compileMarkRegex("(a+)+$")!;
		const started = performance.now();
		expect([...regex.ranges(`${"a".repeat(20_000)}!`)]).toEqual([]);
		expect(performance.now() - started).toBeLessThan(2000);
		regex.dispose();
	});

	it("can be disposed twice without throwing", () => {
		const regex = compileMarkRegex("x")!;
		regex.dispose();
		expect(() => regex.dispose()).not.toThrow();
		expect([...regex.ranges("x")]).toEqual([]);
	});
});

describe("markRegexValid", () => {
	it("answers with the same engine the renderer uses", () => {
		expect(markRegexValid("err(or)?")).toBe(true);
		expect(markRegexValid("(?=x)")).toBe(false);
		expect(markRegexValid("(oops")).toBe(false);
	});
});
