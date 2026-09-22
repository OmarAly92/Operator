import type { BlockId, BlockState, BlockView } from "@operator/terminal-core";

export type BlockFinishedEvent = Readonly<{ id: BlockId; exitCode: number | null; durationMs: number | null; visible: boolean }>;

export function finishedBlocks(previous: ReadonlyMap<BlockId, BlockState>, blocks: readonly BlockView[]): BlockView[] {
	return blocks.filter((block) => previous.get(block.id) === "running" && block.state !== "running");
}

export function rendererVisible(container: HTMLElement): boolean {
	if (!container.isConnected || container.closest("[inert]") !== null) return false;
	if (typeof document !== "undefined" && document.visibilityState === "hidden") return false;
	return container.getClientRects().length > 0;
}
