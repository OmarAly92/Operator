import type { SessionBlock } from "./session-block";

export type TurnGroup = {
	turnId?: string;
	blocks: SessionBlock[];
	startedAt?: string;
	completedAt?: string;
	durationMs?: number;
	running: boolean;
};

export function continuesTurn(previous: SessionBlock, current: SessionBlock): boolean {
	if (previous.turnId !== undefined && current.turnId !== undefined) {
		return previous.turnId === current.turnId;
	}
	return current.kind !== "prompt";
}

export function continuesResponse(_previous: SessionBlock, current: SessionBlock): boolean {
	return current.kind !== "prompt";
}

export function groupBlocksByTurn(blocks: readonly SessionBlock[]): TurnGroup[] {
	const groups: TurnGroup[] = [];
	for (const block of blocks) {
		const group = groups.at(-1);
		if (group !== undefined && continuesTurn(group.blocks.at(-1)!, block)) {
			group.blocks.push(block);
			continue;
		}
		groups.push({ turnId: block.turnId, blocks: [block], startedAt: block.createdAt, running: false });
	}

	return groups.map((group) => {
		const last = group.blocks.at(-1)!;
		const running = group.blocks.some(
			(block) => block.status === "running" || (block.children ?? []).some((child) => child.status === "running"),
		);
		const lastChildCreatedAt = group.blocks
			.flatMap((block) => (block.children ?? []).map((child) => child.createdAt))
			.filter((createdAt): createdAt is string => createdAt !== undefined)
			.reduce<string | undefined>(
				(latest, createdAt) => (latest === undefined || createdAt > latest ? createdAt : latest),
				undefined,
			);
		const completedAt =
			running
				? undefined
				: lastChildCreatedAt !== undefined && (last.createdAt === undefined || lastChildCreatedAt > last.createdAt)
					? lastChildCreatedAt
					: last.createdAt;
		return {
			...group,
			completedAt,
			durationMs: durationBetween(group.startedAt, completedAt),
			running,
		};
	});
}

function durationBetween(startedAt: string | undefined, completedAt: string | undefined): number | undefined {
	if (startedAt === undefined || completedAt === undefined) return undefined;
	const start = Date.parse(startedAt);
	const end = Date.parse(completedAt);
	if (Number.isNaN(start) || Number.isNaN(end)) return undefined;
	return Math.max(0, end - start);
}
