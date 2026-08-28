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
	ConversationTurn,
	FileChangeFile,
} from "../types/conversation";
import { fileChangeFiles } from "../types/conversation";

interface SourceRow {
	item: ConversationItem;
	turnId: string | undefined;
	sequence: number;
	createdAt: string | undefined;
	isRolledBack: boolean;
	rolledBackTurnId: string | undefined;
	rolledBackAt: string | undefined;
}

interface CompactionInsertion {
	compactedAt: string;
	insertAfterSequence: number;
	compactionSeq: number;
}

interface ActivityLookup {
	byId: Map<string, ConversationActivity>;
}

export function blocksFromConversation(snapshot: ConversationSnapshot): SessionBlock[] {
	const rolledBackTurnIds = new Set<string>();
	const rolledBackAtByTurnId = new Map<string, string>();
	for (const turn of snapshot.turns) {
		if (turn.rolledBack === true) {
			rolledBackTurnIds.add(turn.id);
			if (turn.completedAt) {
				rolledBackAtByTurnId.set(turn.id, turn.completedAt);
			} else if (turn.startedAt) {
				rolledBackAtByTurnId.set(turn.id, turn.startedAt);
			} else if (turn.requestedAt) {
				rolledBackAtByTurnId.set(turn.id, turn.requestedAt);
			}
		}
	}

	const activityLookup: ActivityLookup = { byId: new Map() };
	const rows: SourceRow[] = [];
	for (const item of snapshot.items) {
		const turnId = item.turnId;
		const isRolledBack = turnId !== undefined && rolledBackTurnIds.has(turnId);
		if (item.kind === "activity" && item.id !== undefined) {
			activityLookup.byId.set(item.id, item);
		}
		rows.push({
			item,
			turnId,
			sequence: item.sequence,
			createdAt: item.createdAt,
			isRolledBack,
			rolledBackTurnId: isRolledBack ? turnId : undefined,
			rolledBackAt: isRolledBack ? rolledBackAtByTurnId.get(turnId) : undefined,
		});
	}

	const filteredRows = rows.filter((row) => !row.isRolledBack);

	const sortedRows = [...filteredRows].sort((left, right) => left.sequence - right.sequence);

	const bestRowByIdSequence = new Map<string, SourceRow>();
	for (const row of sortedRows) {
		const id = row.item.id;
		if (id === undefined) continue;
		const key = `${id}-${row.sequence}`;
		const existing = bestRowByIdSequence.get(key);
		if (existing === undefined) {
			bestRowByIdSequence.set(key, row);
			continue;
		}
		const existingRevision = existing.item.revision ?? 0;
		const rowRevision = row.item.revision ?? 0;
		if (rowRevision > existingRevision) {
			bestRowByIdSequence.set(key, row);
		}
	}
	const dedupedRows = sortedRows.filter((row) => {
		const id = row.item.id;
		if (id === undefined) return true;
		const best = bestRowByIdSequence.get(`${id}-${row.sequence}`);
		return best === row;
	});

	const rolledBackNotices: SourceRow[] = [];
	for (const turn of snapshot.turns) {
		if (turn.rolledBack !== true) continue;
		const firstItem = snapshot.items.find(
			(item) => item.turnId === turn.id,
		);
		rolledBackNotices.push({
			item: firstItem ?? syntheticItemForTurn(turn),
			turnId: turn.id,
			sequence: firstItem?.sequence ?? Number.MAX_SAFE_INTEGER,
			createdAt:
				rolledBackAtByTurnId.get(turn.id) ?? turn.requestedAt ?? turn.startedAt,
			isRolledBack: false,
			rolledBackTurnId: turn.id,
			rolledBackAt: rolledBackAtByTurnId.get(turn.id),
		});
	}

	const merged = [...dedupedRows, ...rolledBackNotices].sort(
		(left, right) => left.sequence - right.sequence,
	);

	const blocks: SessionBlock[] = [];
	for (const row of merged) {
		if (row.rolledBackTurnId !== undefined) {
			blocks.push(
				buildRolledBackNotice(
					row.rolledBackTurnId,
					row.rolledBackAt,
					row.createdAt,
					row.turnId,
					row.sequence,
				),
			);
			continue;
		}
		blocks.push(rowToBlock(row.item, row.turnId, row.createdAt));
	}

	const nestedBlocks = applyNesting(blocks, activityLookup);

	const compactionInsertion = buildCompactionInsertion(snapshot, dedupedRows);
	if (compactionInsertion === null) return nestedBlocks;

	return insertCompaction(nestedBlocks, compactionInsertion);
}

function insertCompaction(
	blocks: SessionBlock[],
	insertion: CompactionInsertion,
): SessionBlock[] {
	const result: SessionBlock[] = [];
	let inserted = false;
	for (const block of blocks) {
		if (!inserted && block.firstSeq > insertion.insertAfterSequence) {
			result.push(
				buildCompactionBlock(insertion.compactedAt, insertion.compactionSeq),
			);
			inserted = true;
		}
		if (block.firstSeq > insertion.insertAfterSequence) {
			result.push(shiftBlock(block, 1));
		} else {
			result.push(block);
		}
	}
	if (!inserted) {
		result.push(buildCompactionBlock(insertion.compactedAt, insertion.compactionSeq));
	}
	return result;
}

function shiftBlock(block: SessionBlock, delta: number): SessionBlock {
	return {
		...block,
		firstSeq: block.firstSeq + delta,
		lastSeq: block.lastSeq + delta,
		children: block.children?.map((child) => shiftBlock(child, delta)),
	};
}

function rowToBlock(
	item: ConversationItem,
	turnId: string | undefined,
	createdAt: string | undefined,
): SessionBlock {
	if (item.kind === "message") {
		return messageToBlock(item, turnId, createdAt);
	}
	return activityToBlock(item, turnId, createdAt);
}

function messageToBlock(
	message: ConversationMessage,
	turnId: string | undefined,
	createdAt: string | undefined,
): SessionBlock {
	if (message.role === "user") {
		return {
			id: message.id,
			firstSeq: message.sequence,
			lastSeq: message.sequence,
			kind: "prompt",
			status: "ok",
			turnId,
			title: "Prompt",
			body: message.text ?? "",
			truncatedLines: 0,
			redacted: false,
			createdAt,
		};
	}
	const status: BlockStatus = message.streaming === true ? "running" : "ok";
	return {
		id: message.id,
		firstSeq: message.sequence,
		lastSeq: message.sequence,
		kind: "assistant",
		status,
		turnId,
		title: "Assistant",
		body: message.text ?? "",
		truncatedLines: 0,
		redacted: false,
		createdAt,
	};
}

function activityToBlock(
	activity: ConversationActivity,
	turnId: string | undefined,
	createdAt: string | undefined,
): SessionBlock {
	const kind = activity.activityKind;
	const status = mapActivityStatus(activity);
	const truncatedLines = truncatedLinesFor(activity);

	switch (kind) {
		case "reasoning": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "reasoning",
				status,
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Reasoning",
				body: activity.detail?.text ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "command": {
			const detail = buildShellDetail(activity);
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "tool",
				status,
				turnId,
				title: "Shell",
				body: activity.detail?.output !== undefined ? String(activity.detail.output) : "",
				detail,
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "file_change": {
			const detail = buildFileChangeDetail(activity);
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "tool",
				status,
				turnId,
				title: "File change",
				body: fileChangeBody(activity),
				detail,
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "mcp_tool": {
			const detail = buildMcpToolDetail(activity);
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "tool",
				status,
				turnId,
				title: mcpToolTitle(activity),
				body: mcpToolBody(activity),
				detail,
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "plan": {
			const detail = buildPlanDetail(activity);
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "todo",
				status,
				turnId,
				title: "Plan",
				body: planBody(activity),
				detail,
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "approval": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "permission",
				status: mapApprovalStatus(activity),
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Approval",
				body: activity.summary ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "user_input": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "permission",
				status: mapUserInputStatus(activity),
				turnId,
				title:
					activity.summary && activity.summary !== "" ? activity.summary : "Input requested",
				body: activity.summary ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "auto_review": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "notice",
				status: "ok",
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Notice",
				body: activity.summary ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "usage": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "notice",
				status: "ok",
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Notice",
				body: "",
				detail: buildUsageDetail(activity),
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "error": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "notice",
				status: "failed",
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Notice",
				body: activity.summary ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		case "system": {
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "notice",
				status: status === "failed" ? "failed" : "ok",
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Notice",
				body: activity.summary ?? "",
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}

		default: {
			const unknownDetail: BlockDetail = { type: "unknown", raw: activity };
			return {
				id: activity.id,
				firstSeq: activity.sequence,
				lastSeq: activity.sequence,
				kind: "notice",
				status: "ok",
				turnId,
				title: activity.summary && activity.summary !== "" ? activity.summary : "Notice",
				body: activity.summary ?? "",
				detail: unknownDetail,
				truncatedLines,
				redacted: false,
				createdAt,
			};
		}
	}
}

function mapActivityStatus(activity: ConversationActivity): BlockStatus {
	const status = activity.status;
	if (status === "running" || status === "pending") return "running";
	if (status === "failed" || status === "cancelled") return "failed";
	return "ok";
}

function mapApprovalStatus(activity: ConversationActivity): BlockStatus {
	const status = activity.status;
	if (status === "resolved") return "ok";
	if (status === "failed" || status === "cancelled") return "failed";
	return "blocked";
}

function mapUserInputStatus(activity: ConversationActivity): BlockStatus {
	const status = activity.status;
	if (status === "resolved") return "ok";
	if (status === "failed" || status === "cancelled") return "failed";
	return "blocked";
}

function truncatedLinesFor(activity: ConversationActivity): number {
	const detail = activity.detail;
	if (detail === undefined) return 0;
	if (detail.outputTruncated === true) return 1;
	if (detail.textTruncated === true) return 1;
	return 0;
}

function buildShellDetail(activity: ConversationActivity): BlockDetail {
	const detail = activity.detail ?? {};
	return {
		type: "shell",
		command: detail.command,
		output: detail.output === undefined ? undefined : String(detail.output),
		exitCode: detail.exitCode,
	};
}

function buildFileChangeDetail(activity: ConversationActivity): BlockDetail {
	const detail = activity.detail ?? {};
	const files = fileChangeFiles(activity).map((file) => fileToBlockFile(file));
	return { type: "file_change", files, truncated: detail.patchOutputTruncated === true };
}

function fileChangeBody(activity: ConversationActivity): string {
	const files = fileChangeFiles(activity);
	if (files.length === 0) return "";
	return `${files.length} file${files.length === 1 ? "" : "s"} changed`;
}

function fileToBlockFile(file: FileChangeFile): {
	path?: string;
	oldPath?: string;
	status?: string;
	additions?: number;
	deletions?: number;
} {
	return {
		path: file.path,
		oldPath: file.oldPath,
		status: file.status,
		additions: file.additions,
		deletions: file.deletions,
	};
}

function buildMcpToolDetail(activity: ConversationActivity): BlockDetail {
	const detail = activity.detail ?? {};
	return {
		type: "mcp_tool",
		server: detail.server,
		tool: detail.toolName,
		args: detail.arguments,
		result:
			detail.result === undefined || detail.result === null
				? undefined
				: String(detail.result),
	};
}

function mcpToolTitle(activity: ConversationActivity): string {
	const server = activity.detail?.server ?? "";
	const tool = activity.detail?.toolName ?? "";
	return `${server}/${tool}`;
}

function mcpToolBody(activity: ConversationActivity): string {
	const result = activity.detail?.result;
	if (result === undefined || result === null) return "";
	if (typeof result === "string") return result;
	try {
		return JSON.stringify(result);
	} catch {
		return String(result);
	}
}

function buildPlanDetail(activity: ConversationActivity): BlockDetail {
	const steps = activity.detail?.steps;
	return {
		type: "plan",
		steps:
			steps === undefined
				? undefined
				: steps.map((step) => ({ text: step.text, status: step.status })),
	};
}

function planBody(activity: ConversationActivity): string {
	const steps = activity.detail?.steps ?? [];
	return `${steps.length} step${steps.length === 1 ? "" : "s"}`;
}

function buildUsageDetail(activity: ConversationActivity): BlockDetail {
	const detail = activity.detail ?? {};
	return {
		type: "usage",
		inputTokens: detail.inputTokens,
		outputTokens: detail.outputTokens,
	};
}

function buildCompactionInsertion(
	snapshot: ConversationSnapshot,
	rows: SourceRow[],
): CompactionInsertion | null {
	const compactedAt = snapshot.compactedAt;
	if (compactedAt === undefined || compactedAt === "") return null;

	let insertAfterSequence = -1;
	for (const row of rows) {
		if (row.createdAt !== undefined && row.createdAt <= compactedAt) {
			insertAfterSequence = row.sequence;
		}
	}
	return { compactedAt, insertAfterSequence, compactionSeq: insertAfterSequence + 1 };
}

function buildCompactionBlock(
	compactedAt: string,
	compactionSeq: number,
): SessionBlock {
	return {
		id: "compaction-1",
		firstSeq: compactionSeq,
		lastSeq: compactionSeq,
		kind: "compaction",
		status: "ok",
		title: "Compaction",
		body: "",
		detail: { type: "compaction", trigger: "auto" },
		truncatedLines: 0,
		redacted: false,
		createdAt: compactedAt,
	};
}

function applyNesting(blocks: SessionBlock[], lookup: ActivityLookup): SessionBlock[] {
	const blockByActivityId = new Map<string, SessionBlock>();
	for (const block of blocks) blockByActivityId.set(block.id, block);

	const mcpParentBlocks = new Map<string, SessionBlock>();
	for (const block of blocks) {
		const activity = lookup.byId.get(block.id);
		if (activity === undefined) continue;
		if (activity.activityKind !== "mcp_tool") continue;
		if (activity.providerItemId !== undefined && activity.providerItemId !== "") {
			mcpParentBlocks.set(activity.providerItemId, block);
		}
	}

	if (mcpParentBlocks.size === 0) return blocks;

	const childIdsByParentId = new Map<string, string[]>();
	for (const block of blocks) {
		const activity = lookup.byId.get(block.id);
		if (activity === undefined) continue;
		const parentProviderItemId = activity.detail?.parentProviderItemId;
		if (parentProviderItemId === undefined || parentProviderItemId === "") continue;
		let currentParent: string | undefined = parentProviderItemId;
		const visited = new Set<string>();
		while (currentParent !== undefined) {
			if (visited.has(currentParent)) break;
			visited.add(currentParent);
			const mcpParent = mcpParentBlocks.get(currentParent);
			if (mcpParent !== undefined) {
				const list = childIdsByParentId.get(mcpParent.id) ?? [];
				if (!list.includes(block.id)) list.push(block.id);
				childIdsByParentId.set(mcpParent.id, list);
				break;
			}
			const childBlock = blockByActivityId.get(currentParent);
			if (childBlock === undefined) break;
			const childActivity = lookup.byId.get(childBlock.id);
			if (childActivity === undefined) break;
			const next = childActivity.detail?.parentProviderItemId;
			if (next === undefined || next === "") break;
			currentParent = next;
		}
	}

	if (childIdsByParentId.size === 0) return blocks;

	const flat: SessionBlock[] = [];
	const emittedAsChild = new Set<string>();
	for (const block of blocks) {
		const childIds = childIdsByParentId.get(block.id);
		if (childIds === undefined) {
			if (!emittedAsChild.has(block.id)) flat.push(block);
			continue;
		}
		const flattened: SessionBlock[] = [];
		for (const childId of childIds) {
			const childBlock = blockByActivityId.get(childId);
			if (childBlock === undefined) continue;
			if (emittedAsChild.has(childId)) continue;
			emittedAsChild.add(childId);
			flattened.push(childBlock);
		}
		const lastChildSeq = flattened[flattened.length - 1]?.lastSeq ?? block.lastSeq;
		flat.push({
			...block,
			children: flattened,
			lastSeq: lastChildSeq,
		});
	}

	return flat;
}

function buildRolledBackNotice(
	turnId: string,
	rolledBackAt: string | undefined,
	createdAt: string | undefined,
	turnIdForBlock: string | undefined,
	rowSequence: number,
): SessionBlock {
	return {
		id: `rolled-back-${turnId}`,
		firstSeq: rowSequence,
		lastSeq: rowSequence,
		kind: "notice",
		status: "ok",
		turnId: turnIdForBlock,
		title: "Rolled back",
		body: `Rolled back: ${turnId}`,
		truncatedLines: 0,
		redacted: false,
		createdAt: createdAt ?? rolledBackAt,
	};
}

function syntheticItemForTurn(turn: ConversationTurn): ConversationItem {
	const timestamp = turn.startedAt ?? turn.requestedAt ?? turn.completedAt ?? "";
	return {
		kind: "activity",
		id: `rolled-back-${turn.id}`,
		turnId: turn.id,
		sequence: Number.MAX_SAFE_INTEGER,
		revision: 0,
		activityKind: "system",
		status: "completed",
		summary: "",
		detail: {},
		createdAt: timestamp,
	};
}
