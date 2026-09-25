import type { BlockView } from "@operator/terminal-core";
import type { SelectionKind, SelectionPoint, SelectionState } from "./selection-model.js";
import { selectedText, type TextRows } from "./selection-text.js";
import { resolveSelectionView, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	repaint: () => void;
}>;

export class RendererSelection {
	private selection: SelectionState | null = null;
	private readonly selectionListeners = new Set<() => void>();

	constructor(private readonly deps: RendererSelectionDeps) {}

	begin(point: SelectionPoint, kind: SelectionKind): void {
		this.selection = { head: point, tail: point, kind };
		this.changed();
	}

	update(point: SelectionPoint): void {
		if (!this.selection) return;
		this.selection = { ...this.selection, tail: point };
		this.changed();
	}

	clear(): void {
		if (!this.selection) return;
		this.selection = null;
		this.changed();
	}

	text(): string | null {
		const view = this.view();
		return view ? selectedText(view.range, view.rows) : null;
	}

	onChange(listener: () => void): () => void {
		this.selectionListeners.add(listener);
		return () => {
			this.selectionListeners.delete(listener);
		};
	}

	drop(): void {
		if (!this.selection) return;
		this.selection = null;
		this.notifyListeners();
	}

	dropUnlessShown(blocks: readonly BlockView[]): void {
		if (this.selection) {
			const ids = new Set(blocks.map((block) => block.id));
			if (!ids.has(this.selection.head.blockId) || !ids.has(this.selection.tail.blockId)) this.drop();
		}
	}

	view(): SelectionView | null {
		const selection = this.selection;
		if (!selection || !this.deps.hasCore()) return null;
		return resolveSelectionView(selection, this.deps.textRows());
	}

	reset(): void {
		this.selection = null;
	}

	private changed(): void {
		this.deps.repaint();
		this.notifyListeners();
	}

	private notifyListeners(): void {
		for (const listener of [...this.selectionListeners]) listener();
	}
}
