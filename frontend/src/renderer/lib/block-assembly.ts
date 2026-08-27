import type { BlockKind, BlockStatus, SessionBlock } from "./session-block";
import type { BlockEventView } from "./terminal-mux";

const CORRELATED_KINDS = new Set(["tool_complete", "permission_request", "permission_replied"]);

export function assembleBlocks(events: Iterable<BlockEventView>): SessionBlock[] {
	const ordered = [...events]
		.filter((event) => Number.isFinite(event.seq))
		.sort((left, right) => left.seq - right.seq);

	const blocks: SessionBlock[] = [];
	const indexById = new Map<string, number>();
	const consumed = new Set<number>();

	for (const event of ordered) {
		const seq = event.seq;
		if (consumed.has(seq)) continue;
		consumed.add(seq);

		const key = correlationKey(event);
		const text = event.text ?? "";

		switch (event.kind) {
			case "idle_prompt":
				break;

			case "session_start":
				append(blocks, indexById, create(event, key, "notice", "ok", "Session started", text));
				break;

			case "prompt_submit":
				append(blocks, indexById, create(event, key, "prompt", "running", "Prompt", text));
				break;

			case "tool_complete": {
				const status: BlockStatus = (event.errorType ?? "") !== "" ? "failed" : "ok";
				const body = join([event.toolInput ?? "", text], "\n\n");
				const at = key === undefined ? undefined : indexById.get(`src-${key}`);
				if (at !== undefined) {
					blocks[at] = {
						...blocks[at],
						status,
						body,
						lastSeq: seq,
						errorType: event.errorType,
						truncatedLines: event.truncatedLines ?? 0,
						redacted: isRedacted(event),
					};
				} else {
					append(blocks, indexById, create(event, key, "tool", status, event.toolName ?? "Tool", body));
				}
				break;
			}

			case "permission_request": {
				const detail = (event.toolInput ?? "") !== "" ? (event.toolInput as string) : text;
				const body = join([event.toolName ?? "", detail], "\n");
				append(blocks, indexById, create(event, key, "permission", "blocked", "Permission requested", body));
				break;
			}

			case "permission_replied": {
				const at = key === undefined ? undefined : indexById.get(`src-${key}`);
				if (at !== undefined) blocks[at] = { ...blocks[at], status: "ok", lastSeq: seq };
				break;
			}

			case "question_asked":
				append(blocks, indexById, create(event, key, "notice", "blocked", "Waiting on you", text));
				break;

			case "stop":
			case "stop_failure": {
				const failed = event.kind === "stop_failure";
				const at = lastRunningPrompt(blocks);
				if (at !== undefined) {
					blocks[at] = { ...blocks[at], status: failed ? "failed" : "ok", lastSeq: seq };
				}
				if (text !== "") {
					append(
						blocks,
						indexById,
						create(event, key, "assistant", failed ? "failed" : "ok", "Assistant", text),
					);
				}
				break;
			}

			default: {
				const raw = event.rawEvent ?? "";
				append(blocks, indexById, create(event, key, "notice", "ok", raw !== "" ? raw : "Event", text));
			}
		}
	}

	return blocks;
}

export function resolveStranded(blocks: SessionBlock[], reason: string): SessionBlock[] {
	return blocks.map((block) =>
		block.status === "running" || block.status === "blocked"
			? { ...block, status: "failed" as BlockStatus, body: reason }
			: block,
	);
}

function join(parts: string[], separator: string): string {
	return parts.filter((part) => part !== "").join(separator);
}

function correlationKey(event: BlockEventView): string | undefined {
	const source = event.sourceId ?? "";
	if (source !== "") return source;
	const toolUse = event.toolUseId ?? "";
	return toolUse !== "" ? toolUse : undefined;
}

function isRedacted(event: BlockEventView): boolean {
	return (event.redactedSpans ?? []).length > 0;
}

function create(
	event: BlockEventView,
	key: string | undefined,
	kind: BlockKind,
	status: BlockStatus,
	title: string,
	body: string,
): SessionBlock {
	const correlated = key !== undefined && CORRELATED_KINDS.has(event.kind);
	return {
		id: correlated ? `src-${key}` : `seq-${event.seq}`,
		firstSeq: event.seq,
		lastSeq: event.seq,
		kind,
		status,
		title,
		body,
		toolName: event.toolName,
		errorType: event.errorType,
		truncatedLines: event.truncatedLines ?? 0,
		redacted: isRedacted(event),
		createdAt: event.createdAt,
	};
}

function append(blocks: SessionBlock[], indexById: Map<string, number>, block: SessionBlock): void {
	indexById.set(block.id, blocks.length);
	blocks.push(block);
}

function lastRunningPrompt(blocks: SessionBlock[]): number | undefined {
	for (let index = blocks.length - 1; index >= 0; index -= 1) {
		if (blocks[index].kind === "prompt" && blocks[index].status === "running") return index;
	}
	return undefined;
}
