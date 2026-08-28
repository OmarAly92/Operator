import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { continuesResponse, continuesTurn, groupBlocksByTurn } from "./block-turns";
import type { SessionBlock } from "./session-block";

type ExpectedGroup = {
	ids: string[];
	turnId?: string;
	startedAt?: string;
	completedAt: string | null;
	durationMs: number | null;
	running: boolean;
};

type FixtureStream = {
	blocks: SessionBlock[];
	strictBoundaries: boolean[];
	responseGroups: ExpectedGroup[];
};

const fixtureDirectory = path.resolve(process.cwd(), "../testdata/blocks");

describe("shared turn grouping fixture", () => {
	it("keeps canonical boundaries strict while displaying system-injected ACP work with its response", () => {
		const raw = readFileSync(path.join(fixtureDirectory, "acp_turn_grouping.json"), "utf8");
		const fixture = JSON.parse(raw) as { acp: FixtureStream; hooks: FixtureStream };

		for (const stream of [fixture.acp, fixture.hooks]) {
			for (let index = 1; index < stream.blocks.length; index += 1) {
				expect(continuesTurn(stream.blocks[index - 1]!, stream.blocks[index]!)).toBe(
					!stream.strictBoundaries[index - 1],
				);
			}

			const groups = groupBlocksByTurn(stream.blocks);
			expect(groups).toHaveLength(stream.responseGroups.length);
			groups.forEach((group, index) => {
				const expected = stream.responseGroups[index]!;
				expect(group.blocks.map((block) => block.id)).toEqual(expected.ids);
				expect(group.turnId).toBe(expected.turnId);
				expect(group.startedAt).toBe(expected.startedAt);
				expect(group.completedAt ?? null).toBe(expected.completedAt);
				expect(group.durationMs ?? null).toBe(expected.durationMs);
				expect(group.running).toBe(expected.running);
			});
		}

		expect(continuesResponse(fixture.acp.blocks[1]!, fixture.acp.blocks[2]!)).toBe(true);
	});
});
