import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { MAX_PATH_CANDIDATES, PATH_BREAK_GLYPHS, pathCandidatesAt, type PathSpan } from "./path-candidates";

function at(text: string, needle: string, within = 0): PathSpan[] {
	const offset = text.indexOf(needle);
	if (offset < 0) throw new Error(`${needle} not in ${text}`);
	return pathCandidatesAt(text, offset + within);
}

function paths(spans: readonly PathSpan[]): string[] {
	return spans.map((span) => span.path);
}

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "bench", "agent-session", "fixtures");

describe("pathCandidatesAt", () => {
	it("offers the spans through the hovered cell, longest first", () => {
		expect(paths(at("open My Docs/a.md now", "Docs"))).toEqual([
			"open My Docs/a.md now",
			"open My Docs/a.md",
			"My Docs/a.md now",
			"Docs/a.md now",
			"My Docs/a.md",
			"Docs/a.md",
		]);
	});

	it("breaks spans at quotes, backticks, brackets, <>, |, ;, comma, = and Claude Code's glyphs", () => {
		for (const separator of [..."\"'`()[]{}<>|;,=", ...PATH_BREAK_GLYPHS]) {
			const text = `x${separator}src/a.ts${separator}y`;
			expect(paths(at(text, "src/a.ts")), JSON.stringify(separator)).toEqual(["src/a.ts"]);
		}
		expect(paths(at("⏺ Read(src/a.ts)", "src"))).toEqual(["src/a.ts"]);
		expect(paths(at("  ⎿  src/a.ts", "src"))).toEqual(["src/a.ts"]);
		expect(pathCandidatesAt("x│y", 1)).toEqual([]);
	});

	it("takes its glyph set from the characters Claude Code draws in the recorded sessions", () => {
		const drawn = new Set<string>();
		for (const name of ["claude-spinner-10s", "claude-long-50k"]) {
			for (const character of readFileSync(join(fixtures, name, "recording"), "utf8")) {
				if (character.codePointAt(0)! > 0x7f && !/[\p{L}\p{N}\s]/u.test(character)) drawn.add(character);
			}
		}
		for (const glyph of drawn) expect(PATH_BREAK_GLYPHS, glyph).toContain(glyph);
		for (const glyph of ["│", "├", "└", "─", "⎿", "⏺"]) expect(PATH_BREAK_GLYPHS).toContain(glyph);
	});

	it("keeps spaces inside a span only as a candidate, never as the only reading", () => {
		const spans = at("see a.md", "a.md");
		expect(paths(spans)).toEqual(["see a.md", "a.md"]);
		expect(spans[1]).toMatchObject({ start: 4, end: 8 });
	});

	it("strips a trailing line and column suffix with the VS Code grammar and carries it on the span", () => {
		expect(at("at src/a.ts:12 now", "src").find((span) => span.path === "src/a.ts")).toMatchObject({ line: 12, start: 3, end: 14 });
		expect(at("at src/a.ts:12:3", "src").find((span) => span.path === "src/a.ts")).toMatchObject({ line: 12, column: 3, end: 16 });
		expect(at("src/a.ts(12,3)", "src")[0]).toMatchObject({ path: "src/a.ts", line: 12, column: 3, start: 0, end: 14 });
		expect(at('File "src/a.py", line 12, in main', "src")[0]).toMatchObject({ path: "src/a.py", line: 12, start: 6, end: 24 });
		expect(at("src/a.ts#339.12", "src")[0]).toMatchObject({ path: "src/a.ts", line: 339, column: 12 });
		expect(at("src/a.ts#L12", "src")[0]).toMatchObject({ path: "src/a.ts", line: 12, end: 12 });
		expect(at("src/a.ts#L12C4", "src")[0]).toMatchObject({ path: "src/a.ts", line: 12, column: 4 });
	});

	it("drops trailing sentence punctuation but keeps .., ./ and extensions", () => {
		expect(paths(at("Edited src/a.ts.", "src"))).toEqual(["Edited src/a.ts", "src/a.ts"]);
		expect(paths(at("see src/a.ts, then", "src"))).toEqual(["see src/a.ts", "src/a.ts"]);
		expect(paths(at("read src/a.ts: done", "src"))).toContain("src/a.ts");
		expect(paths(at("wow src/a.ts!?", "src"))).toContain("src/a.ts");
		expect(paths(at("(see src/a.ts)", "src"))).toEqual(["see src/a.ts", "src/a.ts"]);
		expect(paths(at("cd ..", ".."))).toEqual(["cd ..", ".."]);
		expect(paths(at("cd ../", ".."))).toContain("../");
		expect(paths(at("run ./x.sh", "./"))).toContain("./x.sh");
		expect(paths(at("open archive.tar.gz", "archive"))).toContain("archive.tar.gz");
	});

	it("also offers a/ and b/ diff paths without the prefix", () => {
		const spans = at("--- a/src/a.ts", "src");
		expect(paths(spans)).toEqual(["--- a/src/a.ts", "a/src/a.ts", "src/a.ts"]);
		expect(spans[2]).toMatchObject({ start: 6, end: 14 });
		expect(paths(at("+++ b/src/a.ts", "src"))).toContain("src/a.ts");
	});

	it("lets a directory match only a path-like span without a line suffix", () => {
		const allow = (text: string, needle: string, path: string) => at(text, needle).find((span) => span.path === path)?.allowDirectory;
		expect(allow("ls docs", "docs", "docs")).toBe(false);
		expect(allow("in backend now", "backend", "backend")).toBe(false);
		expect(allow("ls docs/", "docs", "docs/")).toBe(true);
		expect(allow("cd ~", "~", "~")).toBe(true);
		expect(allow("cd ~/x", "~", "~/x")).toBe(true);
		expect(allow("cd .hidden", ".hidden", ".hidden")).toBe(true);
		expect(allow("at src/lib:12", "src", "src/lib")).toBe(false);
	});

	it("never offers more than the cap, even over the busiest recorded Claude Code line", async () => {
		const wasm = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"));
		await initTerminalCore(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength) as ArrayBuffer);
		const core = createTerminalCore({ columns: 120, scrollback: 200_000 });
		core.resize(120, 40);
		core.feed(new Uint8Array(readFileSync(join(fixtures, "claude-long-50k", "recording"))));
		const lines = core.logicalLines({ start: 0, end: Number.MAX_SAFE_INTEGER });
		const busiest = lines.reduce((best, line) => (line.text.split(/\s+/).length > best.text.split(/\s+/).length ? line : best));
		expect(busiest.text.split(/\s+/).length).toBeGreaterThan(20);
		let most = 0;
		for (let offset = 0; offset < busiest.text.length; offset += 1) most = Math.max(most, pathCandidatesAt(busiest.text, offset).length);
		expect(most).toBeGreaterThan(0);
		expect(most).toBeLessThanOrEqual(MAX_PATH_CANDIDATES);
		const words = Array.from({ length: 30 }, (_, index) => `a/w${index}`).join(" ");
		expect(pathCandidatesAt(words, words.indexOf("a/w15") + 2).length).toBeLessThanOrEqual(MAX_PATH_CANDIDATES);
	});
});
