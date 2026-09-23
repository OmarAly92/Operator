import { BLOCK_NOTIFY_AFTER_MS } from "./retained-terminal";
import type { TerminalBlockFrame } from "./terminal-mux";

export function shellBlockNotification(block: TerminalBlockFrame, sessionId: string): { id: string; exitCode: number | null; durationMs: number } | null {
	const durationMs = Date.parse(block.finishedAt) - Date.parse(block.startedAt);
	if (!Number.isFinite(durationMs) || durationMs < BLOCK_NOTIFY_AFTER_MS) return null;
	return { id: `block-finished:${sessionId}:${block.sourceId}`, exitCode: block.exitCode, durationMs };
}
