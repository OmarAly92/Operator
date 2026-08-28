import { compareMatchScores, matchRanges, scoreMatch, type MatchRange, type MatchScore } from "./text-match";
import { blockDisplay, type SessionBlock } from "./session-block";

export type BlockMatch = { blockId: string; field: "displayName" | "summary"; score: MatchScore; ranges: MatchRange[] };
export type FilterResult = { blocks: SessionBlock[]; matchIds: ReadonlySet<string>; hiddenCount: number };
export const FIND_CONTEXT_BLOCKS = 1;

export function blockSearchFields(block: SessionBlock): string[] {
	const display = blockDisplay(block);
	return [display.displayName, display.summary];
}

function matchBlock(block: SessionBlock, query: string): BlockMatch | null {
	const fields = blockSearchFields(block);
	let best: BlockMatch | null = null;
	for (const [index, field] of fields.entries()) {
		const score = scoreMatch(query, field, { subsequence: false });
		if (score === null) continue;
		const candidate: BlockMatch = {
			blockId: block.id,
			field: index === 0 ? "displayName" : "summary",
			score,
			ranges: matchRanges(query, field, score),
		};
		if (best === null || compareMatchScores(candidate.score, best.score) < 0) best = candidate;
	}
	return best;
}

export function findBlockMatches(blocks: readonly SessionBlock[], query: string): BlockMatch[] {
	if (!query.trim()) return [];
	const matches: BlockMatch[] = [];
	const visit = (block: SessionBlock): void => {
		const match = matchBlock(block, query);
		if (match) matches.push(match);
		for (const child of block.children ?? []) visit(child);
	};
	for (const block of blocks) visit(block);
	return matches;
}

export function filterBlocks(blocks: readonly SessionBlock[], query: string, contextBlocks: number): FilterResult {
	if (!query.trim()) return { blocks: blocks as SessionBlock[], matchIds: new Set(), hiddenCount: 0 };
	const matches = findBlockMatches(blocks, query);
	const matchIds = new Set(matches.map((match) => match.blockId));
	const topLevelIndex = new Map<string, number>();
	const indexBlock = (block: SessionBlock, index: number): void => {
		topLevelIndex.set(block.id, index);
		for (const child of block.children ?? []) indexBlock(child, index);
	};
	blocks.forEach(indexBlock);
	const keep = new Set<number>();
	const context = Math.max(contextBlocks, 0);
	for (const match of matches) {
		const index = topLevelIndex.get(match.blockId);
		if (index === undefined) continue;
		for (let candidate = Math.max(0, index - context); candidate <= Math.min(blocks.length - 1, index + context); candidate += 1) keep.add(candidate);
	}
	const filtered = blocks.filter((_, index) => keep.has(index));
	return { blocks: filtered, matchIds, hiddenCount: blocks.length - filtered.length };
}

export function nextMatchId(matches: readonly BlockMatch[], currentId: string | undefined, forward: boolean): string | undefined {
	if (matches.length === 0) return undefined;
	const currentIndex = currentId === undefined ? -1 : matches.findIndex((match) => match.blockId === currentId);
	if (currentIndex === -1) return forward ? matches[0]!.blockId : matches[matches.length - 1]!.blockId;
	return matches[(currentIndex + (forward ? 1 : -1) + matches.length) % matches.length]!.blockId;
}
