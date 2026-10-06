import type { BlockId, BlockView, DirtyRows, TerminalSnapshot } from "@operator/terminal-core";
import { populateBlock, ROW_GENERATION_ATTR, type BlockBodyInput } from "./block-body.js";
import { applyFilter, type BlockFilter } from "./block-filter.js";
import { blockIsBlank, trimTrailingBlankRows } from "./block-rows.js";
import { ElementPool } from "./element-pool.js";
import { createBlockSection } from "./renderer-chrome.js";
import type { WindowResult } from "./viewport.js";

const POOL_DIRTY_CAP = 4096;

export type BlockElementSlot = { element: HTMLElement; pooled: boolean; away: Set<number> | null };

export type WindowBody = Omit<BlockBodyInput, "block" | "rowWindow" | "rowIsFresh">;

export type PopulatedWindow = { visibleIds: Set<BlockId>; orderedVisible: HTMLElement[]; cursorPlaced: boolean };

export class BlockElementCache {
	readonly blockElements: Map<BlockId, HTMLElement> = new Map();
	fullSince = 0;
	private readonly pool = new ElementPool();
	private readonly pooledDirty = new Map<BlockId, Set<number> | null>();

	startPaint(dirty: DirtyRows, rebuildAll: boolean, generation: number): void {
		if (dirty.full || rebuildAll) {
			this.fullSince = generation;
			this.pool.clear();
			this.pooledDirty.clear();
			if (rebuildAll) this.blockElements.clear();
		}
		for (const [id, away] of this.pooledDirty) {
			if (away === null) continue;
			if (away.size + dirty.rows.size > POOL_DIRTY_CAP) {
				this.pooledDirty.set(id, null);
				continue;
			}
			for (const stableRow of dirty.rows) away.add(stableRow);
		}
	}

	freshness(
		dirtyRows: ReadonlySet<number>,
		pooledThisPaint: ReadonlyMap<BlockId, Set<number> | null>,
		firstScreenStable: number,
	): (blockId: BlockId) => (stableRow: number, node: HTMLElement) => boolean {
		return (blockId: BlockId) => (stableRow: number, node: HTMLElement): boolean => {
			const built = Number(node.getAttribute(ROW_GENERATION_ATTR));
			if (!Number.isFinite(built) || built < this.fullSince) return false;
			if (dirtyRows.has(stableRow)) return false;
			if (!pooledThisPaint.has(blockId)) return true;
			const away = pooledThisPaint.get(blockId);
			if (!away || away.has(stableRow)) return false;
			return stableRow < firstScreenStable;
		};
	}

	ensure(block: BlockView, style: () => string): BlockElementSlot {
		const existing = this.blockElements.get(block.id);
		if (existing) return { element: existing, pooled: false, away: null };
		const pooled = this.pool.take(block.id);
		if (pooled) {
			const away = this.pooledDirty.get(block.id) ?? null;
			this.pooledDirty.delete(block.id);
			pooled.setAttribute("style", style());
			this.blockElements.set(block.id, pooled);
			return { element: pooled, pooled: true, away };
		}
		const section = createBlockSection(block.id, style());
		this.blockElements.set(block.id, section);
		return { element: section, pooled: false, away: null };
	}

	populateWindow(
		blocks: readonly BlockView[],
		windowResult: WindowResult,
		freshFor: (blockId: BlockId) => (stableRow: number, node: HTMLElement) => boolean,
		pooledThisPaint: Map<BlockId, Set<number> | null>,
		style: () => string,
		body: WindowBody,
	): PopulatedWindow {
		let cursorPlaced = false;
		const visibleIds = new Set<BlockId>();
		if (windowResult.firstBlock <= windowResult.lastBlock) {
			for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
				const block = blocks[i]!;
				visibleIds.add(block.id);
				const { element, pooled, away } = this.ensure(block, style);
				if (pooled) pooledThisPaint.set(block.id, away);
				const rowWindow = windowResult.rowWindows.get(i) ?? null;
				const placed = populateBlock(element, { ...body, block, rowWindow, rowIsFresh: freshFor(block.id) });
				if (placed.cursorPlaced) cursorPlaced = true;
			}
		}
		const orderedVisible: HTMLElement[] = [];
		for (let i = windowResult.firstBlock; i <= windowResult.lastBlock; i += 1) {
			const block = blocks[i]!;
			const element = this.blockElements.get(block.id);
			if (element) orderedVisible.push(element);
		}
		return { visibleIds, orderedVisible, cursorPlaced };
	}

	poolHidden(visibleIds: ReadonlySet<BlockId>, dirtyRows: ReadonlySet<number>, capacity: number): void {
		for (const [id, element] of this.blockElements) {
			if (!visibleIds.has(id)) {
				this.pool.put(id, element, capacity);
				this.pooledDirty.set(id, dirtyRows.size > POOL_DIRTY_CAP ? null : new Set(dirtyRows));
				this.blockElements.delete(id);
			}
		}
		for (const id of [...this.pooledDirty.keys()]) {
			if (!this.pool.has(id)) this.pooledDirty.delete(id);
		}
	}

	scrollTo(id: BlockId, align: "start" | "center" | "end", knownBlockId: BlockId | null): void {
		if (knownBlockId !== null && id !== knownBlockId) {
			throw new Error(`unknown block id ${id}`);
		}
		const element = this.blockElements.get(id);
		if (!element) {
			throw new Error("renderer is not mounted");
		}
		element.scrollIntoView({ block: align, inline: "nearest" });
	}

	reset(): void {
		this.blockElements.clear();
		this.pool.clear();
		this.pooledDirty.clear();
		this.fullSince = 0;
	}
}

export function shownBlocks(snapshot: TerminalSnapshot, blocks: readonly BlockView[], filter: BlockFilter | null): BlockView[] {
	return applyFilter(blocks, filter)
		.filter((block) => !(
			snapshot.lineEditorState === 1 &&
			block === blocks.at(-1) &&
			block.source !== "synthetic" &&
			block.state === "running" &&
			block.command === "" &&
			blockIsBlank(snapshot, block)
		))
		.map((block) => trimTrailingBlankRows(snapshot, block));
}
