import { describe, expect, it } from "vitest";
import type { PathCandidate, ResolvedPath } from "@operator/terminal-core";
import { createPathProvider, DEFAULT_LINK_PROVIDERS, hyperlinkProvider, urlProvider } from "./link-providers";
import { mergeLinks } from "./linkifier";
import { MAX_PATH_CANDIDATES } from "./path-candidates";
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
		expect(await hyperlinkProvider(line, 5)).toEqual([
			{ kind: "hyperlink", text: "here", uri: "https://h", range: { blockId: "b", startRow: 0, startCell: 4, endRow: 0, endCell: 8 } },
		]);
	});
	it("drops a run whose id the registry cannot resolve", async () => {
		expect(await hyperlinkProvider(lineOf("x", [0, 1, 9], null), 0)).toEqual([]);
	});
});

describe("urlProvider", () => {
	it("matches xterm.js's strict url grammar and stops before trailing punctuation", async () => {
		const links = await urlProvider(lineOf("go to https://x.y/a?b=c, then (https://z.w/p) done"), 0);
		expect(links.map((link) => link.uri)).toEqual(["https://x.y/a?b=c", "https://z.w/p"]);
		expect(links[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 6, endRow: 0, endCell: 23 });
	});
	it("finds nothing in plain text", async () => {
		expect(await urlProvider(lineOf("no links here"), 0)).toEqual([]);
	});
});

function fakeDisk(files: string[], directories: string[] = [], home = "/home/me") {
	const calls: PathCandidate[][] = [];
	const resolveFirstPath = async (candidates: readonly PathCandidate[], cwd: string): Promise<ResolvedPath | null> => {
		calls.push([...candidates]);
		for (const [index, candidate] of candidates.entries()) {
			const raw = candidate.path;
			const joined = raw === "~" ? home : raw.startsWith("~/") ? `${home}${raw.slice(1)}` : raw.startsWith("/") ? raw : `${cwd}/${raw}`;
			const absolute = joined.replace(/\/+$/u, "");
			if (files.includes(absolute) || (candidate.allowDirectory && directories.includes(absolute))) return { index, path: absolute };
		}
		return null;
	};
	return { calls, files, resolveFirstPath, provider: createPathProvider(resolveFirstPath, () => "/w") };
}

function hover(text: string, needle: string) {
	const offset = text.indexOf(needle);
	if (offset < 0) throw new Error(`${needle} not in ${text}`);
	return [lineOf(text), offset] as const;
}

describe("createPathProvider", () => {
	it("asks the host once, with every span through the hovered cell longest first, and links the first that exists", async () => {
		const disk = fakeDisk(["/w/Docs/a.md", "/w/My Docs/a.md"]);
		const links = await disk.provider(...hover("open My Docs/a.md now", "Docs"));
		expect(disk.calls).toHaveLength(1);
		expect(disk.calls[0]!.map((candidate) => candidate.path)).toEqual([
			"open My Docs/a.md now",
			"open My Docs/a.md",
			"My Docs/a.md now",
			"Docs/a.md now",
			"My Docs/a.md",
			"Docs/a.md",
		]);
		expect(links).toEqual([
			{ kind: "path", text: "My Docs/a.md", path: "/w/My Docs/a.md", range: { blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 17 } },
		]);
	});

	it("breaks spans at quotes, brackets and Claude Code's tree glyphs", async () => {
		const disk = fakeDisk(["/w/src/a.ts"]);
		expect((await disk.provider(...hover("  ⎿  Read(src/a.ts)", "src")))[0]?.text).toBe("src/a.ts");
		expect(disk.calls[0]!.map((candidate) => candidate.path)).toEqual(["src/a.ts"]);
	});

	it("links a span with spaces only when that whole span exists", async () => {
		const disk = fakeDisk(["/w/a.md"]);
		const links = await disk.provider(...hover("see a.md", "a.md"));
		expect(links.map((link) => [link.text, link.range.startCell, link.range.endCell])).toEqual([["a.md", 4, 8]]);
	});

	it("carries a VS Code line and column suffix to the link and underlines it with the path", async () => {
		const disk = fakeDisk(["/w/src/a.ts", "/w/src/a.py"]);
		expect(await disk.provider(...hover("at src/a.ts:12:3 now", "a.ts"))).toMatchObject([{ text: "src/a.ts:12:3", path: "/w/src/a.ts", line: 12, column: 3 }]);
		expect(await disk.provider(...hover("src/a.ts(12,3)", "src"))).toMatchObject([{ text: "src/a.ts(12,3)", line: 12, column: 3 }]);
		expect(await disk.provider(...hover('File "src/a.py", line 12, in main', "src"))).toMatchObject([{ text: 'src/a.py", line 12', line: 12 }]);
		expect(await disk.provider(...hover("src/a.ts#L12", "src"))).toMatchObject([{ text: "src/a.ts#L12", line: 12 }]);
	});

	it("leaves trailing sentence punctuation out of the link", async () => {
		const disk = fakeDisk(["/w/src/a.ts", "/w/.."]);
		expect((await disk.provider(...hover("I edited src/a.ts.", "src")))[0]?.text).toBe("src/a.ts");
		expect((await disk.provider(...hover("see src/a.ts:", "src")))[0]?.text).toBe("src/a.ts");
		expect(await disk.provider(lineOf("I edited src/a.ts."), 17)).toEqual([]);
	});

	it("tries a/ and b/ diff paths without the prefix and sends ~ paths for the host to expand", async () => {
		const disk = fakeDisk(["/w/src/a.ts", "/home/me/notes.md"]);
		expect(await disk.provider(...hover("--- a/src/a.ts", "src"))).toMatchObject([{ text: "src/a.ts", path: "/w/src/a.ts" }]);
		expect(await disk.provider(...hover("+++ b/src/a.ts", "src"))).toMatchObject([{ text: "src/a.ts", path: "/w/src/a.ts" }]);
		expect(await disk.provider(...hover("cat ~/notes.md", "notes"))).toMatchObject([{ text: "~/notes.md", path: "/home/me/notes.md" }]);
	});

	it("links a directory only without a line suffix and only when the text looks like a path", async () => {
		const disk = fakeDisk([], ["/w/docs", "/w/src", "/w/backend", "/home/me", "/w/.git"]);
		expect(await disk.provider(...hover("see docs for more", "docs"))).toEqual([]);
		expect(await disk.provider(...hover("src", "src"))).toEqual([]);
		expect(await disk.provider(...hover("in backend", "backend"))).toEqual([]);
		expect(await disk.provider(...hover("at src:12", "src"))).toEqual([]);
		expect((await disk.provider(...hover("ls docs/", "docs")))[0]?.path).toBe("/w/docs");
		expect((await disk.provider(...hover("cd ~", "~")))[0]?.path).toBe("/home/me");
		expect((await disk.provider(...hover("ls .git", ".git")))[0]?.path).toBe("/w/.git");
	});

	it("gives an OSC 8 hyperlink precedence over a url, and a url over a path, without asking the host under either", async () => {
		const disk = fakeDisk(["/w/x.y/a"]);
		const text = "open https://x.y/a now";
		const offset = text.indexOf("x.y");
		expect(await disk.provider(lineOf(text), offset)).toEqual([]);
		expect(await disk.provider(lineOf("see src/a now", [4, 9, 1], "https://h"), 5)).toEqual([]);
		expect(disk.calls).toHaveLength(0);
		const providers = [...DEFAULT_LINK_PROVIDERS, disk.provider];
		expect(providers.slice(0, 2)).toEqual([hyperlinkProvider, urlProvider]);
		const line = lineOf("x.y/a", [0, 5, 1], "https://h");
		const merged = mergeLinks(await Promise.all([hyperlinkProvider, urlProvider, async () => [{ kind: "path" as const, text: "x.y/a", path: "/w/x.y/a", range: line.rangeOf(0, 5) }]].map((provider) => provider(line, 1))));
		expect(merged.map((link) => link.kind)).toEqual(["hyperlink"]);
	});

	it("caches only a found path, keyed by the line's text, so a repaint keeps it and a missing file is asked again", async () => {
		const disk = fakeDisk([]);
		const [line, offset] = hover("edit src/a.ts now", "src");
		expect(await disk.provider(line, offset)).toEqual([]);
		expect(await disk.provider(line, offset)).toEqual([]);
		expect(disk.calls).toHaveLength(2);
		disk.files.push("/w/src/a.ts");
		expect((await disk.provider(line, offset))[0]?.path).toBe("/w/src/a.ts");
		expect(disk.calls).toHaveLength(3);
		const [repainted] = hover("edit src/a.ts now", "src");
		expect((await disk.provider(repainted, offset + 5))[0]?.text).toBe("src/a.ts");
		expect(disk.calls).toHaveLength(3);
	});

	it("never sends the host more than the cap on one hover", async () => {
		const disk = fakeDisk([]);
		const text = Array.from({ length: 40 }, (_, index) => `a/w${index}`).join(" ");
		await disk.provider(lineOf(text), text.indexOf("a/w20") + 3);
		expect(disk.calls[0]!.length).toBeGreaterThan(0);
		expect(disk.calls[0]!.length).toBeLessThanOrEqual(MAX_PATH_CANDIDATES);
	});
});
