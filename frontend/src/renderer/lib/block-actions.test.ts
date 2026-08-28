import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { blockActionsFor, blockCopyText, blocksToText, type BlockActionContext } from "./block-actions";
import type { BlockDetail, SessionBlock } from "./session-block";

type FixtureBlock = Omit<SessionBlock, "firstSeq" | "lastSeq" | "truncatedLines" | "redacted"> & Partial<Pick<SessionBlock, "firstSeq" | "lastSeq" | "truncatedLines" | "redacted">>;
type Fixture = { actions: { name: string; block: FixtureBlock; context: Partial<BlockActionContext>; expect: unknown[] }[]; copyText: { name: string; block: FixtureBlock; expect: string }[]; selectionText: { name: string; blocks: FixtureBlock[]; expect: string }[] };
const fixture = JSON.parse(readFileSync(path.resolve(process.cwd(), "../testdata/blocks/block_actions.json"), "utf8")) as Fixture;

function blockFromFixture(block: FixtureBlock): SessionBlock {
	return {
		...block,
		firstSeq: block.firstSeq ?? 1,
		lastSeq: block.lastSeq ?? 1,
		body: block.body ?? "",
		truncatedLines: block.truncatedLines ?? 0,
		redacted: block.redacted ?? false,
		detail: block.detail as BlockDetail | undefined,
	};
}

describe("shared block action fixture", () => {
	for (const item of fixture.actions) {
		it(item.name, () => {
			expect(blockActionsFor(blockFromFixture(item.block), {
				mode: item.context.mode ?? "tui",
				capabilities: item.context.capabilities ?? [],
				canSend: item.context.canSend ?? false,
				turnInFlight: item.context.turnInFlight ?? false,
				rollbackableTurnIds: item.context.rollbackableTurnIds ?? [],
			})).toEqual(item.expect);
		});
	}
	for (const item of fixture.copyText) it(item.name, () => expect(blockCopyText(blockFromFixture(item.block))).toBe(item.expect));
	for (const item of fixture.selectionText) it(item.name, () => expect(blocksToText(item.blocks.map(blockFromFixture))).toBe(item.expect));
});
