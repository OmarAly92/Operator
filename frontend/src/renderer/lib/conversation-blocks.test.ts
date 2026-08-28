import { describe, expect, it } from "vitest";
import { blocksFromConversation } from "./conversation-blocks";
import type {
	BlockDetail,
	BlockStatus,
	SessionBlock,
} from "./session-block";
import type {
	ConversationActivity,
	ConversationItem,
	ConversationMessage,
	ConversationSnapshot,
} from "../types/conversation";

function message(
	id: string,
	sequence: number,
	role: "user" | "assistant",
	text: string,
	extras: Partial<ConversationMessage> = {},
): ConversationMessage {
	return {
		kind: "message",
		id,
		turnId: "t-1",
		sequence,
		revision: 0,
		role,
		origin: role === "user" ? "human" : "provider",
		text,
		streaming: false,
		createdAt: `2026-08-28T10:00:0${sequence}Z`,
		...extras,
	};
}

function activity(
	id: string,
	sequence: number,
	activityKind: string,
	status: string,
	extras: Partial<ConversationActivity> = {},
): ConversationActivity {
	return {
		kind: "activity",
		id,
		turnId: "t-1",
		sequence,
		revision: 0,
		activityKind: activityKind as ConversationActivity["activityKind"],
		status: status as ConversationActivity["status"],
		summary: "",
		createdAt: `2026-08-28T10:00:0${sequence}Z`,
		...extras,
	};
}

function snapshot(items: ConversationItem[], extras: Partial<ConversationSnapshot> = {}): ConversationSnapshot {
	return {
		conversationId: "c-1",
		sessionId: "s-1",
		harness: "claude-code",
		mode: "chat",
		controller: { state: "ready" },
		turns: [],
		items,
		latestSequence: items.length,
		oldestSequence: 1,
		hasMoreBefore: false,
		settings: {},
		...extras,
	};
}

describe("blocksFromConversation — mapping table", () => {
	it("message role user maps to prompt", () => {
		const blocks = blocksFromConversation(
			snapshot([message("m-1", 1, "user", "hi")]),
		);
		expect(blocks).toHaveLength(1);
		expect(blocks[0]).toMatchObject({
			id: "m-1",
			kind: "prompt",
			title: "Prompt",
			body: "hi",
			status: "ok",
		});
	});

	it("message role assistant maps to assistant with status running when streaming", () => {
		const blocks = blocksFromConversation(
			snapshot([message("m-1", 1, "assistant", "hello", { streaming: true })]),
		);
		expect(blocks[0]?.status).toBe<BlockStatus>("running");
	});

	it("message role assistant maps to assistant with status ok when settled", () => {
		const blocks = blocksFromConversation(
			snapshot([message("m-1", 1, "assistant", "hello")]),
		);
		expect(blocks[0]?.status).toBe<BlockStatus>("ok");
	});

	it("activity reasoning maps to reasoning with body from detail.text", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "reasoning", "completed", {
					detail: { text: "considering" },
				}),
			]),
		);
		expect(blocks[0]).toMatchObject({
			kind: "reasoning",
			body: "considering",
			title: "Reasoning",
		});
	});

	it("activity command maps to tool with shell detail and body from output", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "command", "completed", {
					summary: "ls",
					detail: { command: "ls", output: "file.txt", exitCode: 0 },
				}),
			]),
		);
		expect(blocks[0]).toMatchObject({
			kind: "tool",
			title: "Shell",
			body: "file.txt",
			detail: { type: "shell", command: "ls", output: "file.txt", exitCode: 0 },
		});
	});

	it("activity file_change maps to tool with file_change detail", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "file_change", "completed", {
					summary: "edit",
					detail: {
						files: [{ path: "a.ts", status: "modified", additions: 1, deletions: 0 }],
					},
				}),
			]),
		);
		const detail = blocks[0]?.detail as BlockDetail;
		expect(blocks[0]?.kind).toBe("tool");
		expect(blocks[0]?.title).toBe("File change");
		expect(detail.type).toBe("file_change");
	});

	it("activity mcp_tool maps to tool with mcp_tool detail and server/tool title", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "mcp_tool", "completed", {
					summary: "subagent",
					detail: { server: "agent", toolName: "subagent", arguments: { task: "x" }, result: "ok" },
				}),
			]),
		);
		expect(blocks[0]).toMatchObject({
			kind: "tool",
			title: "agent/subagent",
			body: "ok",
			detail: { type: "mcp_tool", server: "agent", tool: "subagent" },
		});
	});

	it("activity plan maps to todo with plan detail", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "plan", "completed", {
					detail: { steps: [{ text: "step 1", status: "pending" }] },
				}),
			]),
		);
		expect(blocks[0]).toMatchObject({
			kind: "todo",
			title: "Plan",
		});
		expect(blocks[0]?.detail).toEqual({ type: "plan", steps: [{ text: "step 1", status: "pending" }] });
	});

	it("activity approval maps to permission with status blocked until resolved", () => {
		const blocked = blocksFromConversation(
			snapshot([activity("a-1", 1, "approval", "pending", { summary: "Run command?" })]),
		);
		expect(blocked[0]).toMatchObject({ kind: "permission", status: "blocked", title: "Run command?" });

		const resolved = blocksFromConversation(
			snapshot([activity("a-1", 1, "approval", "resolved", { summary: "Run command?" })]),
		);
		expect(resolved[0]?.status).toBe<BlockStatus>("ok");
	});

	it("activity user_input maps to permission with distinct title", () => {
		const blocks = blocksFromConversation(
			snapshot([activity("a-1", 1, "user_input", "pending", { summary: "Pick one" })]),
		);
		expect(blocks[0]).toMatchObject({
			kind: "permission",
			status: "blocked",
			title: "Pick one",
		});

		const noSummary = blocksFromConversation(
			snapshot([activity("a-1", 1, "user_input", "pending")]),
		);
		expect(noSummary[0]?.title).toBe("Input requested");
	});

	it("activity auto_review maps to notice", () => {
		const blocks = blocksFromConversation(
			snapshot([activity("a-1", 1, "auto_review", "completed", { summary: "decided" })]),
		);
		expect(blocks[0]).toMatchObject({ kind: "notice", title: "decided", body: "decided" });
	});

	it("activity usage maps to notice with usage detail", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "usage", "completed", {
					detail: { inputTokens: 10, outputTokens: 5 },
				}),
			]),
		);
		expect(blocks[0]?.kind).toBe("notice");
		expect(blocks[0]?.body).toBe("");
		expect(blocks[0]?.detail).toEqual({
			type: "usage",
			inputTokens: 10,
			outputTokens: 5,
		});
	});

	it("activity error maps to notice with status failed", () => {
		const blocks = blocksFromConversation(
			snapshot([activity("a-1", 1, "error", "failed", { summary: "crash" })]),
		);
		expect(blocks[0]).toMatchObject({ kind: "notice", status: "failed", body: "crash" });
	});

	it("activity system maps to notice", () => {
		const blocks = blocksFromConversation(
			snapshot([activity("a-1", 1, "system", "completed", { summary: "info" })]),
		);
		expect(blocks[0]).toMatchObject({ kind: "notice", body: "info" });
	});

	it("snapshot compactedAt produces a compaction block", () => {
		const blocks = blocksFromConversation(
			snapshot(
				[
					message("m-1", 1, "user", "x", { createdAt: "2026-08-28T09:00:00Z" }),
					message("m-2", 2, "assistant", "y", { createdAt: "2026-08-28T10:00:00Z" }),
				],
				{ compactedAt: "2026-08-28T09:30:00Z" },
			),
		);
		const compaction = blocks.find((b) => b.kind === "compaction");
		expect(compaction).toBeDefined();
		expect(compaction?.id).toBe("compaction-1");
		expect(compaction?.title).toBe("Compaction");
		expect(compaction?.detail).toEqual({ type: "compaction", trigger: "auto" });
	});
});

describe("blocksFromConversation — six rules", () => {
	it("rule 1: block id and sequence come from the item, never minted", () => {
		const blocks = blocksFromConversation(
			snapshot([message("m-1", 5, "user", "hi")]),
		);
		expect(blocks[0]).toMatchObject({ id: "m-1", firstSeq: 5, lastSeq: 5 });
	});

	it("rule 2: revision does not change the block's sequence", () => {
		const blocks = blocksFromConversation(
			snapshot([
				message("m-1", 1, "assistant", "draft", { revision: 0 }),
				message("m-1", 1, "assistant", "final", { revision: 3 }),
			]),
		);
		expect(blocks).toHaveLength(2);
		expect(blocks[0]?.firstSeq).toBe(1);
		expect(blocks[1]?.firstSeq).toBe(1);
	});

	it("rule 3: empty settled text on an assistant produces body '' (pinned)", () => {
		const blocks = blocksFromConversation(
			snapshot([message("m-1", 1, "assistant", "")]),
		);
		expect(blocks[0]?.body).toBe("");
	});

	it("rule 4: command output and reasoning text are kept separate", () => {
		const blocks = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "reasoning", "completed", {
					detail: { text: "I think" },
				}),
				activity("a-2", 2, "command", "completed", {
					summary: "pwd",
					detail: { command: "pwd", output: "/home", exitCode: 0 },
				}),
			]),
		);
		const reasoning = blocks.find((b) => b.kind === "reasoning");
		const tool = blocks.find((b) => b.kind === "tool");
		expect(reasoning?.body).toBe("I think");
		expect(tool?.body).toBe("/home");
		expect(reasoning?.body).not.toBe(tool?.body);
	});

	it("rule 5: outputTruncated and textTruncated map to truncatedLines", () => {
		const truncatedCommand = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "command", "completed", {
					detail: { command: "ls", output: "x", outputTruncated: true },
				}),
			]),
		);
		expect(truncatedCommand[0]?.truncatedLines).toBe(1);

		const truncatedReasoning = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "reasoning", "completed", {
					detail: { text: "x", textTruncated: true },
				}),
			]),
		);
		expect(truncatedReasoning[0]?.truncatedLines).toBe(1);

		const normalCommand = blocksFromConversation(
			snapshot([
				activity("a-1", 1, "command", "completed", {
					detail: { command: "ls", output: "x" },
				}),
			]),
		);
		expect(normalCommand[0]?.truncatedLines).toBe(0);
	});

	it("rule 6: rolled-back turn is excluded but countable as a notice", () => {
		const blocks = blocksFromConversation({
			...snapshot([
				message("m-1", 1, "user", "x", { turnId: "t-rolled" }),
				activity("a-1", 2, "command", "completed", {
					turnId: "t-rolled",
					detail: { command: "x", output: "y", exitCode: 0 },
				}),
				message("m-2", 3, "user", "fresh"),
			]),
			turns: [
				{
					id: "t-rolled",
					state: "completed",
					rolledBack: true,
					requestedAt: "2026-08-28T10:00:00Z",
				},
				{ id: "t-fresh", state: "completed", requestedAt: "2026-08-28T11:00:00Z" },
			],
		});

		const rolledBack = blocks.find((b) => b.id === "rolled-back-t-rolled");
		expect(rolledBack).toBeDefined();
		expect(rolledBack?.kind).toBe("notice");
		expect(rolledBack?.body).toBe("Rolled back: t-rolled");
		expect(blocks.find((b) => b.id === "m-1")).toBeUndefined();
		expect(blocks.find((b) => b.id === "a-1")).toBeUndefined();
		expect(blocks.find((b) => b.id === "m-2")).toBeDefined();
	});
});

describe("blocksFromConversation — nesting", () => {
	function parentSnapshot(): ConversationSnapshot {
		return snapshot([
			message("m-1", 1, "user", "go"),
			activity("a-parent", 2, "mcp_tool", "completed", {
				providerItemId: "parent-1",
				detail: { server: "agent", toolName: "subagent", arguments: { task: "x" }, result: "done" },
			}),
			activity("a-child-1", 3, "command", "completed", {
				detail: { command: "ls", output: "out", exitCode: 0, parentProviderItemId: "parent-1" },
			}),
			message("m-2", 4, "assistant", "done"),
		]);
	}

	it("one level: child appears in parent.children", () => {
		const blocks = blocksFromConversation(parentSnapshot());
		const parent = blocks.find((b) => b.id === "a-parent");
		expect(parent).toBeDefined();
		expect(parent?.children).toBeDefined();
		expect(parent?.children).toHaveLength(1);
		expect(parent?.children?.[0]?.id).toBe("a-child-1");
	});

	it("flattened grandchild: grandchild whose parent is a child lands in parent.children after the children", () => {
		const blocks = blocksFromConversation(
			snapshot([
				message("m-1", 1, "user", "go"),
				activity("a-parent", 2, "mcp_tool", "completed", {
					providerItemId: "parent-1",
					detail: { server: "agent", toolName: "subagent", result: "done" },
				}),
				activity("a-child-1", 3, "command", "completed", {
					detail: { command: "ls", output: "out", exitCode: 0, parentProviderItemId: "parent-1" },
				}),
				activity("a-grandchild", 4, "command", "completed", {
					detail: { command: "wc", output: "1", exitCode: 0, parentProviderItemId: "a-child-1" },
				}),
				message("m-2", 5, "assistant", "done"),
			]),
		);
		const parent = blocks.find((b) => b.id === "a-parent") as SessionBlock;
		expect(parent.children).toBeDefined();
		expect(parent.children?.map((c) => c.id)).toEqual(["a-child-1", "a-grandchild"]);
	});

	it("terminated cycle: a node whose parent is its own descendant is included once", () => {
		const blocks = blocksFromConversation(
			snapshot([
				message("m-1", 1, "user", "go"),
				activity("a-parent", 2, "mcp_tool", "completed", {
					providerItemId: "parent-1",
					detail: { server: "agent", toolName: "subagent", result: "done" },
				}),
				activity("a-child-1", 3, "command", "completed", {
					detail: { command: "ls", output: "out", exitCode: 0, parentProviderItemId: "parent-1" },
				}),
				activity("a-cycle", 4, "command", "completed", {
					detail: { command: "echo", output: "x", exitCode: 0, parentProviderItemId: "a-child-1" },
				}),
				activity("a-back", 5, "command", "completed", {
					detail: { command: "tail", output: "y", exitCode: 0, parentProviderItemId: "a-cycle" },
				}),
				message("m-2", 6, "assistant", "done"),
			]),
		);
		const parent = blocks.find((b) => b.id === "a-parent") as SessionBlock;
		expect(parent.children?.map((c) => c.id)).toEqual(["a-child-1", "a-cycle", "a-back"]);
	});
});
