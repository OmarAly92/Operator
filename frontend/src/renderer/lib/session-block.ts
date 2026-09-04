export type BlockKind = "prompt" | "assistant" | "reasoning" | "tool" | "todo" | "compaction" | "permission" | "notice";

export type BlockStatus = "running" | "ok" | "failed" | "blocked";

export type BlockDetail =
	| { type: "shell"; command?: string; output?: string; exitCode?: number }
	| { type: "file_change"; files?: BlockFileChange[]; truncated?: boolean }
	| { type: "plan"; steps?: BlockPlanStep[] }
	| { type: "mcp_tool"; server?: string; tool?: string; args?: unknown; result?: string }
	| { type: "usage"; contextUsed?: number; contextWindow?: number; inputTokens?: number; outputTokens?: number }
	| { type: "compaction"; trigger?: "auto" | "manual"; preTokens?: number }
	| { type: "unknown"; raw: unknown };

export type BlockFileChange = {
	path?: string;
	oldPath?: string;
	status?: string;
	additions?: number;
	deletions?: number;
};

export type BlockPlanStep = {
	text?: string;
	status?: string;
};

export type BlockDisplay = {
	displayName: string;
	summary: string;
	errorText?: string;
};

export type SessionBlock = {
	id: string;
	firstSeq: number;
	lastSeq: number;
	kind: BlockKind;
	status: BlockStatus;
	turnId?: string;
	title: string;
	body: string;
	detail?: BlockDetail;
	toolName?: string;
	errorType?: string;
	truncatedLines: number;
	redacted: boolean;
	createdAt?: string;
	children?: SessionBlock[];
};

export function blockDisplay(block: SessionBlock): BlockDisplay {
	const detail = block.detail;
	if (detail === undefined) return { displayName: block.title, summary: block.body };

	switch (detail.type) {
		case "shell":
			return {
				displayName: "Shell",
				summary: [detail.command, detail.output].filter((part): part is string => part !== undefined && part !== "").join("\n\n"),
				errorText: detail.exitCode === undefined || detail.exitCode === 0 ? undefined : `Exit code ${detail.exitCode}`,
			};
		case "file_change":
			return { displayName: "File change", summary: `${detail.files?.length ?? 0} ${(detail.files?.length ?? 0) === 1 ? "file" : "files"} changed` };
		case "plan":
			return { displayName: "Plan", summary: `${detail.steps?.length ?? 0} ${(detail.steps?.length ?? 0) === 1 ? "step" : "steps"}` };
		case "mcp_tool":
			return { displayName: `${detail.server ?? ""}/${detail.tool ?? ""}`, summary: detail.result ?? "" };
		case "usage":
			return { displayName: "Usage", summary: `${detail.contextUsed ?? ""} / ${detail.contextWindow ?? ""} context` };
		case "compaction":
			return { displayName: "Compaction", summary: `${detail.trigger ?? ""} at ${detail.preTokens ?? ""} tokens` };
		case "unknown":
			return { displayName: block.title, summary: block.body === "" ? JSON.stringify(detail.raw) ?? "" : block.body };
		default:
			return assertNever(detail);
	}
}

function assertNever(value: never): never {
	throw new Error(`Unexpected block detail: ${JSON.stringify(value)}`);
}

// Mirrors backend/internal/adapters/agent/blockdispatch/dispatch.go's Mappers.
// A harness with no mapper there produces no block events, so the session opens
// Raw and the toggle says so rather than showing an empty list. There is no
// runtime handshake that discovers this set.
export const BLOCK_HARNESSES: ReadonlySet<string> = new Set(["claude-code", "grok", "codex"]);
