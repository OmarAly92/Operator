export type BlockKind = "prompt" | "assistant" | "tool" | "permission" | "notice";

export type BlockStatus = "running" | "ok" | "failed" | "blocked";

export type SessionBlock = {
	id: string;
	firstSeq: number;
	lastSeq: number;
	kind: BlockKind;
	status: BlockStatus;
	title: string;
	body: string;
	toolName?: string;
	errorType?: string;
	truncatedLines: number;
	redacted: boolean;
	createdAt?: string;
};

// Mirrors backend/internal/adapters/agent/blockdispatch/dispatch.go's Mappers.
// A harness with no mapper there produces no block events, so the session opens
// Raw and the toggle says so rather than showing an empty list. There is no
// runtime handshake that discovers this set.
export const BLOCK_HARNESSES: ReadonlySet<string> = new Set(["claude-code", "grok", "codex"]);

export function blocksCoverHarness(harness: string | undefined): boolean {
	return harness !== undefined && BLOCK_HARNESSES.has(harness);
}
