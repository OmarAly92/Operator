import type { BlockId, BlockView } from "@operator/terminal-core";

export type BlockFilter = Readonly<{
	state?: "running" | "finished" | "abandoned";
	exitCodeNonZero?: boolean;
	source?: "osc133" | "extension" | "synthetic";
	bookmarked?: boolean;
	command?: string;
}>;

export function applyFilter(
	blocks: readonly BlockView[],
	filter: BlockFilter | null,
): BlockView[] {
	if (filter === null) return blocks.slice();
	const result: BlockView[] = [];
	for (const block of blocks) {
		if (filter.state !== undefined && block.state !== filter.state) continue;
		if (filter.exitCodeNonZero === true) {
			if (block.exitCode === null || block.exitCode === 0) continue;
		}
		if (filter.source !== undefined && block.source !== filter.source) continue;
		if (filter.bookmarked !== undefined && block.bookmarked !== filter.bookmarked) continue;
		if (filter.command !== undefined && block.command !== filter.command) continue;
		result.push(block);
	}
	return result;
}

export function filterByFailed(blocks: readonly BlockView[]): BlockView[] {
	return blocks.filter(
		(block) => block.state === "finished" && block.exitCode !== null && block.exitCode !== 0,
	);
}

export function extractBlockIds(blocks: readonly BlockView[]): BlockId[] {
	return blocks.map((block) => block.id);
}
