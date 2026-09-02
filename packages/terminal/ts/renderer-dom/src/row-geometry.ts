import type { BlockId, BlockView } from "@operator/terminal-core";

export type RowOrigin = Readonly<{ left: number; top: number }>;

export function paintedRowOrigin(
	blocks: readonly BlockView[],
	elements: ReadonlyMap<BlockId, HTMLElement>,
	row: number,
	cellHeight: number,
): RowOrigin | null {
	if (blocks.length === 0 || cellHeight <= 0) return null;
	const block =
		blocks.find((candidate) => row < candidate.firstRow + candidate.rowCount) ??
		blocks[blocks.length - 1]!;
	const section = elements.get(block.id);
	if (!section) return null;
	const target = row - block.firstRow;
	let anchor: HTMLElement | null = null;
	let anchorLabel = 0;
	let anchorDistance = Number.POSITIVE_INFINITY;
	for (const node of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
		const label = Number(node.dataset.terminalRow);
		if (!Number.isFinite(label)) continue;
		const distance = Math.abs(label - target);
		if (distance < anchorDistance) {
			anchorDistance = distance;
			anchorLabel = label;
			anchor = node;
		}
	}
	if (!anchor) return null;
	const rect = anchor.getBoundingClientRect();
	return { left: rect.left, top: rect.top + (target - anchorLabel) * cellHeight };
}
