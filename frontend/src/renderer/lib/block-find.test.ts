import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { blockSearchFields, filterBlocks, findBlockMatches, nextMatchId } from "./block-find";
import type { BlockDetail, SessionBlock } from "./session-block";

type FixtureBlock = Omit<SessionBlock, "firstSeq" | "lastSeq" | "truncatedLines" | "redacted"> & Partial<Pick<SessionBlock, "firstSeq" | "lastSeq" | "truncatedLines" | "redacted">>;
type Fixture = { matches: { name: string; query: string; blocks: FixtureBlock[]; expect: unknown[] }[]; filter: { name: string; query: string; contextBlocks: number; blocks: FixtureBlock[]; expectIds: string[]; matchIds: string[]; hiddenCount: number }[]; navigation: { name: string; ids: string[]; currentId?: string; forward: boolean; expect: string }[] };
const fixture = JSON.parse(readFileSync(path.resolve(process.cwd(), "../testdata/blocks/block_find.json"), "utf8")) as Fixture;

function blockFromFixture(block: FixtureBlock): SessionBlock {
	return { ...block, firstSeq: block.firstSeq ?? 1, lastSeq: block.lastSeq ?? 1, body: block.body ?? "", truncatedLines: block.truncatedLines ?? 0, redacted: block.redacted ?? false, detail: block.detail as BlockDetail | undefined, children: block.children?.map(blockFromFixture) };
}

describe("shared block find fixture", () => {
	for (const item of fixture.matches) it(item.name, () => expect(findBlockMatches(item.blocks.map(blockFromFixture), item.query)).toEqual(item.expect));
	for (const item of fixture.filter) {
		it(item.name, () => {
			const result = filterBlocks(item.blocks.map(blockFromFixture), item.query, item.contextBlocks);
			expect(result.blocks.map((block) => block.id)).toEqual(item.expectIds);
			expect([...result.matchIds]).toEqual(item.matchIds);
			expect(result.hiddenCount).toBe(item.hiddenCount);
		});
	}
	for (const item of fixture.navigation) {
		it(item.name, () => {
			const matches = item.ids.map((blockId) => ({ blockId, field: "displayName" as const, score: { tier: 0, offset: 0 }, ranges: [] }));
			expect(nextMatchId(matches, item.currentId, item.forward)).toBe(item.expect);
		});
	}
	it("empty query preserves the input list", () => {
		const blocks = [blockFromFixture({ id: "empty", kind: "notice", status: "ok", title: "Notice", body: "text" })];
		expect(findBlockMatches(blocks, " ")).toEqual([]);
		const result = filterBlocks(blocks, " ", 0);
		expect(result.blocks).toBe(blocks);
		expect(result.matchIds).toEqual(new Set());
		expect(result.hiddenCount).toBe(0);
	});
	it("search fields use the display rather than raw block data", () => {
		const block = blockFromFixture({ id: "shell", kind: "tool", status: "ok", title: "Tool", body: "ignored", detail: { type: "shell", command: "pwd", output: "root" } });
		expect(blockSearchFields(block)).toEqual(["Shell", "pwd\n\nroot"]);
	});
});
