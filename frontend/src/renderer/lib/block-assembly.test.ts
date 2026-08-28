import { describe, expect, it } from "vitest";
import { assembleBlocks, resolveStranded } from "./block-assembly";
import { blocksCoverHarness } from "./session-block";
import type { BlockEventView } from "./terminal-mux";

function event(seq: number, kind: string, extra: Partial<BlockEventView> = {}): BlockEventView {
	return {
		seq,
		sessionId: "s-1",
		kind,
		createdAt: "2026-08-27T10:00:00Z",
		...extra,
	};
}

describe("assembleBlocks", () => {
	it("leaves a prompt running until its stop arrives", () => {
		expect(assembleBlocks([event(1, "prompt_submit", { text: "go" })])[0].status).toBe("running");

		const closed = assembleBlocks([
			event(1, "prompt_submit", { text: "go" }),
			event(2, "stop", { text: "done" }),
		]);
		expect(closed[0].status).toBe("ok");
		expect(closed[1]).toMatchObject({ kind: "assistant", body: "done", status: "ok" });
	});

	it("adds empty turn ids and unknown details without changing hook fields", () => {
		const block = assembleBlocks([event(1, "tool_complete", { toolName: "Bash", text: "ok" })])[0];

		expect(block).toMatchObject({
			id: "seq-1",
			kind: "tool",
			status: "ok",
			title: "Bash",
			body: "ok",
			turnId: undefined,
			detail: { type: "unknown", raw: "ok" },
		});
	});

	it("fails the open prompt and the assistant block on stop_failure", () => {
		const blocks = assembleBlocks([
			event(1, "prompt_submit", { text: "go" }),
			event(2, "stop_failure", { text: "crashed" }),
		]);
		expect(blocks.map((block) => block.status)).toEqual(["failed", "failed"]);
	});

	it("resolves the prompt without adding a block when stop carries no text", () => {
		const blocks = assembleBlocks([
			event(1, "prompt_submit", { text: "go" }),
			event(2, "stop"),
		]);
		expect(blocks).toHaveLength(1);
		expect(blocks[0].status).toBe("ok");
	});

	it("records assistant text even when no prompt is open", () => {
		expect(assembleBlocks([event(1, "stop", { text: "orphan" })])[0]).toMatchObject({
			kind: "assistant",
			body: "orphan",
		});
	});

	it("resolves only the most recent open prompt", () => {
		const blocks = assembleBlocks([
			event(1, "prompt_submit", { text: "first" }),
			event(2, "prompt_submit", { text: "second" }),
			event(3, "stop", { text: "done" }),
		]);
		expect(blocks[0].status).toBe("running");
		expect(blocks[1].status).toBe("ok");
	});

	it("correlates on sourceId instead of creating a twin", () => {
		const blocks = assembleBlocks([
			event(1, "permission_request", { sourceId: "k", toolName: "Bash", toolInput: "rm -rf" }),
			event(2, "permission_replied", { sourceId: "k" }),
		]);
		expect(blocks).toHaveLength(1);
		expect(blocks[0]).toMatchObject({ id: "src-k", status: "ok" });
	});

	it("falls back to toolUseId as the correlation key", () => {
		const blocks = assembleBlocks([
			event(1, "tool_complete", { toolUseId: "tu-2", toolName: "Bash", text: "a" }),
			event(2, "tool_complete", { toolUseId: "tu-2", toolName: "Bash", text: "b" }),
		]);
		expect(blocks).toHaveLength(1);
		expect(blocks[0]).toMatchObject({ body: "b", lastSeq: 2 });
	});

	it("gives uncorrelated events their own blocks", () => {
		const blocks = assembleBlocks([
			event(1, "tool_complete", { toolName: "Bash", text: "a" }),
			event(2, "tool_complete", { toolName: "Bash", text: "b" }),
		]);
		expect(blocks.map((block) => block.id)).toEqual(["seq-1", "seq-2"]);
	});

	it("drops idle_prompt entirely", () => {
		expect(assembleBlocks([event(1, "idle_prompt")])).toEqual([]);
	});

	it("drops a permission_replied with nothing to reply to", () => {
		expect(assembleBlocks([event(1, "permission_replied", { sourceId: "ghost" })])).toEqual([]);
	});

	it("blocks the session on a question rather than reading as a benign notice", () => {
		const blocks = assembleBlocks([event(1, "question_asked", { text: "Which branch?" })]);
		expect(blocks[0]).toMatchObject({
			kind: "notice",
			status: "blocked",
			title: "Waiting on you",
			body: "Which branch?",
		});
	});

	it("degrades an unknown kind to a notice titled by its raw event", () => {
		expect(assembleBlocks([event(1, "unknown", { rawEvent: "future-hook", text: "b" })])[0]).toMatchObject({
			kind: "notice",
			title: "future-hook",
			body: "b",
		});
		expect(assembleBlocks([event(2, "unknown")])[0].title).toBe("Event");
	});

	it("is order-independent and drops duplicate seqs", () => {
		const ordered = assembleBlocks([
			event(1, "prompt_submit", { text: "go" }),
			event(2, "tool_complete", { sourceId: "k", toolName: "Bash", text: "out" }),
			event(3, "stop", { text: "done" }),
		]);
		const shuffled = assembleBlocks([
			event(3, "stop", { text: "done" }),
			event(2, "tool_complete", { sourceId: "k", toolName: "Bash", text: "out" }),
			event(2, "tool_complete", { sourceId: "k", toolName: "Bash", text: "out" }),
			event(1, "prompt_submit", { text: "go" }),
		]);
		expect(shuffled).toEqual(ordered);
	});

	it("makes a tool block fail only when errorType is set", () => {
		expect(assembleBlocks([event(1, "tool_complete", { toolName: "Bash", text: "ok" })])[0].status).toBe("ok");
		const failed = assembleBlocks([
			event(1, "tool_complete", { toolName: "Bash", text: "no such file", errorType: "tool_failed" }),
		]);
		expect(failed[0]).toMatchObject({ status: "failed", errorType: "tool_failed" });
	});

	it("flips an already-ok correlated block when the failure arrives", () => {
		const blocks = assembleBlocks([
			event(1, "permission_request", { sourceId: "k", toolName: "Bash", toolInput: "rm -rf /" }),
			event(2, "permission_replied", { sourceId: "k" }),
			event(3, "tool_complete", { sourceId: "k", toolName: "Bash", text: "denied", errorType: "tool_failed" }),
		]);
		expect(blocks).toHaveLength(1);
		expect(blocks[0].status).toBe("failed");
	});

	it("shows what ran before what came back", () => {
		expect(
			assembleBlocks([event(1, "tool_complete", { toolName: "Bash", toolInput: '{"command":"ls"}', text: "a.txt" })])[0].body,
		).toBe('{"command":"ls"}\n\na.txt');
		expect(assembleBlocks([event(2, "tool_complete", { toolName: "Bash", text: "a.txt" })])[0].body).toBe("a.txt");
	});

	it("names the tool and its input on a permission block", () => {
		expect(
			assembleBlocks([event(1, "permission_request", { sourceId: "p", toolName: "Bash", toolInput: "git push -f" })])[0].body,
		).toBe("Bash\ngit push -f");
		expect(
			assembleBlocks([event(2, "permission_request", { sourceId: "q", toolName: "Bash", text: "wants to run" })])[0].body,
		).toBe("Bash\nwants to run");
	});

	it("carries truncation and redaction through", () => {
		const blocks = assembleBlocks([
			event(1, "tool_complete", {
				sourceId: "k",
				toolName: "Read",
				text: "k=[redacted]",
				truncatedLines: 900,
				redactedSpans: [{ start: 2, end: 12 }],
			}),
		]);
		expect(blocks[0]).toMatchObject({ truncatedLines: 900, redacted: true });
	});

	it("leaves multi-byte text untouched", () => {
		expect(assembleBlocks([event(1, "stop", { text: "héllo → 世界 🎉" })])[0].body).toBe("héllo → 世界 🎉");
	});

	it("treats the tool input as opaque text", () => {
		expect(
			assembleBlocks([event(1, "tool_complete", { toolName: "Write", toolInput: '{"a":"[... truncated by Operator ...]' })])[0].body,
		).toContain("truncated by Operator");
	});
});

describe("resolveStranded", () => {
	it("turns running and blocked into failed with the stated reason", () => {
		const blocks = assembleBlocks([
			event(1, "prompt_submit", { text: "go" }),
			event(2, "permission_request", { sourceId: "k", toolName: "Bash" }),
			event(3, "tool_complete", { sourceId: "done", toolName: "Bash", text: "fine" }),
		]);
		const resolved = resolveStranded(blocks, "Session ended");
		expect(resolved.map((block) => block.status)).toEqual(["failed", "failed", "ok"]);
		expect(resolved[0].body).toBe("Session ended");
		expect(resolved[2].body).toBe("fine");
	});

	it("resolves an unanswered question", () => {
		const blocks = assembleBlocks([event(1, "question_asked", { text: "Which branch?" })]);
		expect(resolveStranded(blocks, "Session ended")[0].status).toBe("failed");
	});

	it("changes nothing when nothing is stranded", () => {
		const blocks = assembleBlocks([event(1, "stop", { text: "done" })]);
		expect(resolveStranded(blocks, "Session ended")).toEqual(blocks);
	});
});

describe("blocksCoverHarness", () => {
	it("covers the harnesses with registered mappers and nothing else", () => {
		expect(["claude-code", "grok", "codex"].every(blocksCoverHarness)).toBe(true);
		expect(blocksCoverHarness("aider")).toBe(false);
		expect(blocksCoverHarness(undefined)).toBe(false);
		expect(blocksCoverHarness("")).toBe(false);
	});
});
