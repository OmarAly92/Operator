import { describe, expect, it } from "vitest";
import { createPathProvider, hyperlinkProvider, urlProvider } from "./link-providers";
import { logicalLineAt } from "./logical-lines";
import type { TextRows } from "./selection-text";

function lineOf(text: string, links: number[] = [], uri: string | null = null) {
	const rows: TextRows = {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => 1,
		rowText: () => text,
		rowSpans: () => [],
		rowWrapped: () => false,
		rowLinkRuns: () => links,
		linkUri: () => uri,
	};
	return logicalLineAt(rows, "b", 0)!;
}

describe("hyperlinkProvider", () => {
	it("turns contiguous runs of one link id into one link with its uri", async () => {
		const line = lineOf("see here now", [4, 6, 3, 6, 8, 3], "https://h");
		expect(await hyperlinkProvider(line)).toEqual([
			{ kind: "hyperlink", text: "here", uri: "https://h", range: { blockId: "b", startRow: 0, startCell: 4, endRow: 0, endCell: 8 } },
		]);
	});
	it("drops a run whose id the registry cannot resolve", async () => {
		expect(await hyperlinkProvider(lineOf("x", [0, 1, 9], null))).toEqual([]);
	});
});

describe("urlProvider", () => {
	it("matches xterm.js's strict url grammar and stops before trailing punctuation", async () => {
		const links = await urlProvider(lineOf("go to https://x.y/a?b=c, then (https://z.w/p) done"));
		expect(links.map((link) => link.uri)).toEqual(["https://x.y/a?b=c", "https://z.w/p"]);
		expect(links[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 6, endRow: 0, endCell: 23 });
	});
	it("finds nothing in plain text", async () => {
		expect(await urlProvider(lineOf("no links here"))).toEqual([]);
	});
});

describe("createPathProvider", () => {
	it("asks the host for each candidate and keeps only the ones that resolve, with row and column", async () => {
		const asked: string[] = [];
		const provider = createPathProvider(async (path, cwd) => {
			asked.push(`${cwd}:${path}`);
			return path.endsWith(".ts") ? `/abs/${path}` : null;
		}, () => "/work", "posix");
		const links = await provider(lineOf("edit src/a.ts:42:7 or lib/b.go:9"));
		expect(asked).toEqual(["/work:src/a.ts", "/work:lib/b.go"]);
		expect(links).toEqual([
			{ kind: "path", text: "src/a.ts:42:7", path: "/abs/src/a.ts", line: 42, column: 7, range: { blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 18 } },
		]);
	});
	it("does not hand a url to the host and caches an answer per path and cwd", async () => {
		let calls = 0;
		const provider = createPathProvider(async () => { calls += 1; return "/x"; }, () => "", "posix");
		expect(await provider(lineOf("https://x.y/a"))).toEqual([]);
		await provider(lineOf("./same"));
		await provider(lineOf("./same"));
		expect(calls).toBe(1);
	});
});
