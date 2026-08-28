import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { assembleBlocks } from "./block-assembly";
import { blockDisplay, type BlockDetail, type SessionBlock } from "./session-block";
import type { BlockEventView } from "./terminal-mux";
import { blocksFromConversation } from "./conversation-blocks";
import type { ConversationSnapshot } from "../types/conversation";

const FIXTURES = [
	"assembly_turn",
	"assembly_permission",
	"assembly_out_of_order",
	"assembly_truncation",
	"assembly_tool_failure",
	"assembly_question",
] as const;

const ACP_FIXTURES = [
	"acp_stream_basic",
	"acp_stream_tool_failure",
	"acp_stream_compaction",
	"acp_stream_nested_subagent",
] as const;

type ExpectedBlock = {
	id: string;
	kind: string;
	status: string;
	title: string;
	body?: string;
	errorType?: string;
	truncatedLines?: number;
	redacted?: boolean;
};

type ExpectedAcpBlock = {
	id: string;
	kind: string;
	status: string;
	turnId?: string;
	title: string;
	body?: string;
	firstSeq?: number;
	lastSeq?: number;
	truncatedLines?: number;
	redacted?: boolean;
	detail?: BlockDetail;
	children?: ExpectedAcpBlock[];
};

type DetailFixture = {
	detail: BlockDetail;
	display: {
		displayName: string;
		summary: string;
		errorText?: string;
	};
};

const fixtureDirectory = path.resolve(process.cwd(), "../testdata/blocks");

describe("shared assembly fixtures", () => {
	for (const name of FIXTURES) {
		it(`${name} assembles as the shared fixture says`, () => {
			const raw = readFileSync(path.join(fixtureDirectory, `${name}.json`), "utf8");
			const fixture = JSON.parse(raw) as { records: BlockEventView[]; expected: ExpectedBlock[] };

			const blocks = assembleBlocks(fixture.records);

			expect(blocks).toHaveLength(fixture.expected.length);
			fixture.expected.forEach((want, index) => {
				const got = blocks[index];
				expect(got.id).toBe(want.id);
				expect(got.kind).toBe(want.kind);
				expect(got.status).toBe(want.status);
				expect(got.title).toBe(want.title);
				expect(got.body).toBe(want.body ?? "");
				expect(got.errorType ?? "").toBe(want.errorType ?? "");
				expect(got.truncatedLines).toBe(want.truncatedLines ?? 0);
				expect(got.redacted).toBe(want.redacted ?? false);
			});
		});
	}

	it("acp_detail_variants has a display for every detail variant", () => {
		const raw = readFileSync(path.join(fixtureDirectory, "acp_detail_variants.json"), "utf8");
		const fixture = JSON.parse(raw) as { details: DetailFixture[] };

		for (const item of fixture.details) {
			const block: SessionBlock = {
				id: "acp-detail",
				firstSeq: 1,
				lastSeq: 1,
				kind: "tool",
				status: "ok",
				title: "Tool",
				body: "",
				detail: item.detail,
				truncatedLines: 0,
				redacted: false,
			};

			const display = blockDisplay(block);
			expect(display.displayName).toBe(item.display.displayName);
			expect(display.summary).toBe(item.display.summary);
			expect(display.errorText).toBe(item.display.errorText);
		}
	});

	it("does not render a shell error when exit code is absent", () => {
		const display = blockDisplay({
			id: "shell-without-exit-code",
			firstSeq: 1,
			lastSeq: 1,
			kind: "tool",
			status: "ok",
			title: "Tool",
			body: "",
			detail: { type: "shell", command: "pwd" },
			truncatedLines: 0,
			redacted: false,
		});

		expect(display.errorText).toBeUndefined();
	});

	for (const name of ACP_FIXTURES) {
		it(`${name} assembles as the shared ACP fixture says`, () => {
			const raw = readFileSync(path.join(fixtureDirectory, `${name}.json`), "utf8");
			const fixture = JSON.parse(raw) as {
				snapshot: ConversationSnapshot;
				expected: ExpectedAcpBlock[];
			};

			const blocks = blocksFromConversation(fixture.snapshot);

			const assertBlock = (got: SessionBlock, want: ExpectedAcpBlock): void => {
				expect(got.id).toBe(want.id);
				expect(got.kind).toBe(want.kind);
				expect(got.status).toBe(want.status);
				expect(got.title).toBe(want.title);
				expect(got.body).toBe(want.body ?? "");
				expect(got.turnId).toBe(want.turnId);
				expect(got.firstSeq).toBe(want.firstSeq ?? want.lastSeq ?? got.firstSeq);
				expect(got.lastSeq).toBe(want.lastSeq ?? want.firstSeq ?? got.lastSeq);
				expect(got.truncatedLines).toBe(want.truncatedLines ?? 0);
				expect(got.redacted).toBe(want.redacted ?? false);
				expect(got.detail).toEqual(want.detail);
			};

			const assertChildren = (got: SessionBlock, want: ExpectedAcpBlock): void => {
				if (!want.children) {
					expect((got as SessionBlock & { children?: SessionBlock[] }).children ?? []).toEqual([]);
					return;
				}
				const gotChildren =
					(got as SessionBlock & { children?: SessionBlock[] }).children ?? [];
				expect(gotChildren).toHaveLength(want.children.length);
				for (let i = 0; i < want.children.length; i++) {
					assertBlock(gotChildren[i]!, want.children[i]!);
					assertChildren(gotChildren[i]!, want.children[i]!);
				}
			};

			expect(blocks).toHaveLength(fixture.expected.length);
			for (let i = 0; i < fixture.expected.length; i++) {
				const got = blocks[i]!;
				const want = fixture.expected[i]!;
				assertBlock(got, want);
				assertChildren(got, want);
			}
		});
	}
});
