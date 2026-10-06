import type { BlockView } from "@operator/terminal-core";
import { HistoryModel, type CommandHistorySource } from "./history.js";

const LOCAL_LIMIT = 2000;

export class EditorHistory {
	private readonly model = new HistoryModel();
	private readonly local = new Map<string, string>();
	private source: CommandHistorySource | null = null;
	private unsubscribe: (() => void) | null = null;
	private walking = false;

	constructor(private readonly changed: () => void) {}

	setSource(source: CommandHistorySource | null): void {
		if (source === this.source) return;
		this.unsubscribe?.();
		this.unsubscribe = null;
		this.source = source;
		this.model.setShared(source?.entries() ?? []);
		if (!source) return;
		this.unsubscribe = source.subscribe(() => {
			if (this.source !== source) return;
			this.model.setShared(source.entries());
			this.changed();
		});
	}

	ingest(blocks: readonly BlockView[]): void {
		let changed = false;
		for (const block of blocks) {
			if (block.command.length === 0 || this.local.get(block.id) === block.command) continue;
			this.local.set(block.id, block.command);
			changed = true;
		}
		if (!changed) return;
		for (const id of this.local.keys()) {
			if (this.local.size <= LOCAL_LIMIT) break;
			this.local.delete(id);
		}
		this.model.setLocal([...this.local.values()]);
	}

	recall(text: string, direction: -1 | 1): string | null {
		if (!this.walking) {
			this.walking = true;
			this.model.startRecall(text);
			this.source?.refresh?.();
		}
		return this.model.step(direction);
	}

	endWalk(): void {
		if (!this.walking) return;
		this.walking = false;
		this.model.endRecall();
	}

	suggest(prefix: string): string | null {
		return this.model.suggest(prefix);
	}

	entries(): readonly string[] {
		return this.model.entries();
	}

	reset(): void {
		this.endWalk();
		this.local.clear();
		this.model.setLocal([]);
	}

	dispose(): void {
		this.setSource(null);
		this.reset();
	}
}
