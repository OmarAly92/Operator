import { describe, expect, it } from "vitest";
import { logicalLineAt } from "./logical-lines";
import type { TextRows } from "./selection-text";
import {
	MAX_LINK_PATH_FRAGMENTS,
	cleanPath,
	createPathLookup,
	fileLinkCandidates,
	fragmentAt,
	isFileLinkSeparator,
	possibleFilePaths,
} from "./file-links";

describe("isFileLinkSeparator", () => {
	it("splits on Warp's ASCII set, box drawing, and non-ASCII whitespace or punctuation", () => {
		for (const c of [" ", "\t", "(", ")", ":", "\\", ",", '"', "'", "[", "]", "{", "}", "<", ">", ";", "|", "`", "=", "│", "├", "└", "─", "，", "：", "（", " ", "·"]) {
			expect(isFileLinkSeparator(c)).toBe(true);
		}
		for (const c of ["a", "/", ".", "-", "_", "~", "@", "#", "▝", "в", "é"]) {
			expect(isFileLinkSeparator(c)).toBe(false);
		}
	});
});

describe("cleanPath", () => {
	it("strips every trailing line-and-column form Warp recognises", () => {
		expect(cleanPath("a.ts")).toEqual({ path: "a.ts" });
		expect(cleanPath("a.ts:100")).toEqual({ path: "a.ts", line: 100 });
		expect(cleanPath("a.ts:100-200")).toEqual({ path: "a.ts", line: 100 });
		expect(cleanPath("a.ts:100:300")).toEqual({ path: "a.ts", line: 100, column: 300 });
		expect(cleanPath("a.ts[100, 300]")).toEqual({ path: "a.ts", line: 100, column: 300 });
		expect(cleanPath('a.py", line 100, column 300')).toEqual({ path: "a.py", line: 100, column: 300 });
		expect(cleanPath('a.py", line 100, in')).toEqual({ path: "a.py", line: 100 });
		expect(cleanPath("a.cs(100, 300)")).toEqual({ path: "a.cs", line: 100, column: 300 });
		expect(cleanPath("a.ts#L100")).toEqual({ path: "a.ts", line: 100 });
		expect(cleanPath("a.ts#L100:300")).toEqual({ path: "a.ts", line: 100, column: 300 });
	});
	it("only strips a form that runs to the end of the text", () => {
		expect(cleanPath("a.ts:100 b")).toEqual({ path: "a.ts:100 b" });
		expect(cleanPath("a.ts:x")).toEqual({ path: "a.ts:x" });
	});
});

describe("possibleFilePaths", () => {
	const range = (start: number, end: number) => ({ start, end });

	it("lists every fragment combination through the point, longest first, as Warp does", () => {
		const text = "file link: src/восиб,abcвосиб";
		const lefts = [["file link: ", 0], [" link: ", 4], ["link: ", 5], [": ", 9], [" ", 10], ["", 11]] as const;
		const rights = [["src/восиб,abcвосиб", 29], ["src/восиб,", 21], ["src/восиб", 20]] as const;
		const expected = lefts.flatMap(([left, start]) =>
			rights.map(([right, end]) => ({ path: { path: `${left}${right}` }, ...range(start, end) })),
		);
		expect(possibleFilePaths(text, 11)).toEqual(expected);
	});
	it("offers a lone dot", () => {
		expect(possibleFilePaths(".", 0)).toEqual([{ path: { path: "." }, ...range(0, 1) }]);
	});
	it("cleans the line number off a candidate but keeps it in the range", () => {
		expect(possibleFilePaths("восиб:100", 6)).toEqual([
			{ path: { path: "восиб", line: 100 }, ...range(0, 9) },
			{ path: { path: "", line: 100 }, ...range(5, 9) },
			{ path: { path: "100" }, ...range(6, 9) },
		]);
	});
	it("always includes the part of the hovered word left of the point", () => {
		const paths = possibleFilePaths("see src/a.ts now", 8);
		expect(paths.every((candidate) => candidate.start <= 4 && candidate.end >= 12)).toBe(true);
		expect(paths).toContainEqual({ path: { path: "src/a.ts" }, ...range(4, 12) });
	});
	it("finds the banner path Claude Code prints beside its mascot", () => {
		const text = "  ▝▝ ▝▝    ~/.operator/dev/data/worktrees/scratch/workers/scratch-24";
		const start = text.indexOf("~");
		expect(possibleFilePaths(text, start + 20)).toContainEqual({
			path: { path: "~/.operator/dev/data/worktrees/scratch/workers/scratch-24" },
			...range(start, text.length),
		});
	});
	it("keeps at most Warp's fragment budget on each side", () => {
		const text = "a ".repeat(300);
		expect(possibleFilePaths(text, 300).length).toBeLessThanOrEqual((MAX_LINK_PATH_FRAGMENTS + 1) * MAX_LINK_PATH_FRAGMENTS);
	});
});

describe("fileLinkCandidates", () => {
	it("tries punctuation-trimmed, raw, a/ b/ stripped, then @ stripped, per path in order", () => {
		expect(fileLinkCandidates([{ path: { path: "notes/README.md." }, start: 0, end: 16 }])).toEqual([
			{ path: "notes/README.md", allowDirectory: true, start: 0, end: 15 },
			{ path: "notes/README.md.", allowDirectory: true, start: 0, end: 16 },
		]);
		expect(fileLinkCandidates([{ path: { path: "a/src/x.ts", line: 3 }, start: 4, end: 16 }])).toEqual([
			{ path: "a/src/x.ts", line: 3, allowDirectory: false, start: 4, end: 16 },
			{ path: "src/x.ts", line: 3, allowDirectory: false, start: 6, end: 16 },
		]);
		expect(fileLinkCandidates([{ path: { path: "link@" }, start: 0, end: 5 }])).toEqual([
			{ path: "link@", allowDirectory: true, start: 0, end: 5 },
			{ path: "link", allowDirectory: true, start: 0, end: 4 },
		]);
	});
	it("keeps a period that is a path component", () => {
		for (const path of [".", "..", "foo/.", "foo/.."]) {
			expect(fileLinkCandidates([{ path: { path }, start: 0, end: path.length }])).toEqual([
				{ path, allowDirectory: true, start: 0, end: path.length },
			]);
		}
	});
	it("trims non-ASCII closing punctuation after a path", () => {
		expect(fileLinkCandidates([{ path: { path: "a.md，" }, start: 0, end: 5 }])[0]).toEqual({
			path: "a.md",
			allowDirectory: true,
			start: 0,
			end: 4,
		});
	});
});

describe("fragmentAt", () => {
	it("is the separator itself or the run of non-separators around the offset", () => {
		expect(fragmentAt("see src/a.ts now", 6)).toEqual({ start: 4, end: 12 });
		expect(fragmentAt("see src/a.ts now", 3)).toEqual({ start: 3, end: 4 });
		expect(fragmentAt("x", 0)).toEqual({ start: 0, end: 1 });
	});
});

function lineOf(text: string) {
	const rows: TextRows = {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => 1,
		rowText: () => text,
		rowSpans: () => [],
		rowWrapped: () => false,
	};
	return logicalLineAt(rows, "b", 0)!;
}

describe("createPathLookup", () => {
	it("asks the host once, in Warp's order, and links the first candidate it accepts", async () => {
		const asked: Array<{ cwd: string; paths: string[] }> = [];
		const lookup = createPathLookup(async (queries, cwd) => {
			asked.push({ cwd, paths: queries.map((query) => query.path) });
			const index = queries.findIndex((query) => query.path === "src/a.ts");
			return index < 0 ? null : { index, path: "/work/src/a.ts" };
		}, () => "/work");
		const link = await lookup(lineOf("edit src/a.ts:42:7 now"), 7);
		expect(asked).toHaveLength(1);
		expect(asked[0]!.cwd).toBe("/work");
		expect(asked[0]!.paths[0]).toBe("edit src/a.ts:42:7 now");
		expect(link).toEqual({
			kind: "path",
			text: "src/a.ts:42:7",
			path: "/work/src/a.ts",
			line: 42,
			column: 7,
			range: { blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 18 },
		});
	});
	it("tells the host a directory is acceptable only without a line", async () => {
		let queries: readonly { path: string; allowDirectory: boolean }[] = [];
		const lookup = createPathLookup(async (asked) => {
			queries = asked;
			return null;
		}, () => "");
		expect(await lookup(lineOf("dir:3"), 0)).toBeNull();
		expect(queries[0]).toEqual({ path: "dir", allowDirectory: false });
		expect(queries).toContainEqual({ path: "dir", allowDirectory: true });
	});
	it("links the banner path Claude Code prints beside its mascot", async () => {
		const text = "  ▝▝ ▝▝    ~/.operator/dev/data/worktrees/scratch/workers/scratch-24";
		const lookup = createPathLookup(async (queries) => {
			const index = queries.findIndex((query) => query.path === "~/.operator/dev/data/worktrees/scratch/workers/scratch-24");
			return index < 0 ? null : { index, path: "/Users/me/.operator/dev/data/worktrees/scratch/workers/scratch-24" };
		}, () => "");
		const link = await lookup(lineOf(text), text.indexOf("scratch-24"));
		expect(link?.path).toBe("/Users/me/.operator/dev/data/worktrees/scratch/workers/scratch-24");
		expect(link?.range).toEqual({ blockId: "b", startRow: 0, startCell: 11, endRow: 0, endCell: text.length });
	});
});
