import { describe, expect, it } from "vitest";
import { hyperlinkProvider, urlProvider } from "./link-providers";
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
