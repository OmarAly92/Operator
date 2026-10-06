import { decodeBlocks, type BlockId, type BlockState, type BlockView, type TerminalSnapshot } from "@operator/terminal-core";
import { documentHidden, finishedBlocks, rendererVisible, type BlockFinishedEvent } from "./block-finished.js";

export class FinishedBlockTracker {
	private blockStates = new Map<BlockId, BlockState>();
	private readonly blockFinishedListeners = new Set<(event: BlockFinishedEvent) => void>();

	onBlockFinished(listener: (event: BlockFinishedEvent) => void): () => void {
		this.blockFinishedListeners.add(listener);
		return () => {
			this.blockFinishedListeners.delete(listener);
		};
	}

	detect(snapshot: TerminalSnapshot, shownToUser: () => boolean): BlockView[] {
		if (snapshot.altScreen !== null) return [];
		const blocks = decodeBlocks(snapshot);
		const finished = finishedBlocks(this.blockStates, blocks);
		this.blockStates = new Map(blocks.map((block) => [block.id, block.state] as const));
		if (finished.length === 0) return blocks;
		const visible = shownToUser();
		for (const block of finished) {
			for (const listener of [...this.blockFinishedListeners]) {
				listener({ id: block.id, exitCode: block.exitCode, durationMs: block.durationMs, visible });
			}
		}
		return blocks;
	}

	reset(): void {
		this.blockStates = new Map();
		this.blockFinishedListeners.clear();
	}
}

export function shownToUser(hostVisible: boolean | null, container: HTMLElement | null): boolean {
	if (hostVisible !== null) return hostVisible && !documentHidden();
	return container !== null && rendererVisible(container);
}
