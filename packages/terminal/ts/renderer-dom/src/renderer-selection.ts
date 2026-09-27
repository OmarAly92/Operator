import type { BlockView, RowEvent } from "@operator/terminal-core";
import { anchorOf, followAnchor, followPoint, pointOf, rowsKeepTheirShape, type LineAnchor } from "./selection-anchor.js";
import type { SelectionKind, SelectionPoint, SelectionState } from "./selection-model.js";
import { selectedText, type TextRows } from "./selection-text.js";
import { ALT_BLOCK_ID, resolveSelectionView, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	repaint: () => void;
}>;

type Anchors = Readonly<{ head: LineAnchor | null; tail: LineAnchor | null }>;

function reflowed(anchor: LineAnchor, event: RowEvent): LineAnchor | null {
	return event.remapEnd && anchor.lineRow >= event.remapEnd[0] ? null : followAnchor(anchor, event);
}

export class RendererSelection {
	private selection: SelectionState | null = null;
	private anchors: Anchors | null = null;
	private anchoredFor: SelectionState | null = null;
	private moved = false;
	private caret: SelectionPoint | null = null;
	private caretAnchor: LineAnchor | null = null;
	private readonly selectionListeners = new Set<() => void>();

	constructor(private readonly deps: RendererSelectionDeps) {}

	begin(point: SelectionPoint, kind: SelectionKind): void {
		this.placeCaret(point);
		this.set({ head: point, tail: point, kind });
	}

	update(point: SelectionPoint, extendFromCaret = false): void {
		if (this.selection) {
			const current = this.moved && this.deps.hasCore() ? (this.settle(this.deps.textRows()) ?? this.selection) : this.selection;
			this.set({ ...current, tail: point });
			return;
		}
		if (!extendFromCaret) return;
		const head = this.currentCaret();
		if (head) this.set({ head, tail: point, kind: "simple" });
		else this.placeCaret(point);
	}

	clear(caret?: SelectionPoint): void {
		if (caret) this.placeCaret(caret);
		if (!this.selection) return;
		this.forget();
		this.changed();
	}

	followRows(event: RowEvent): void {
		if (!event.remap && !event.remapEnd) return;
		if (this.caret) this.caret = followPoint(this.caret, event);
		if (this.caretAnchor) this.caretAnchor = reflowed(this.caretAnchor, event);
		const selection = this.selection;
		if (!selection) return;
		if (selection.kind === "rectangle" && selection.head.blockId !== ALT_BLOCK_ID) {
			if (!rowsKeepTheirShape(Math.min(selection.head.row, selection.tail.row), Math.max(selection.head.row, selection.tail.row), event)) {
				this.drop();
				return;
			}
		}
		this.selection = { ...selection, head: followPoint(selection.head, event), tail: followPoint(selection.tail, event) };
		if (this.anchors && this.anchoredFor === selection) {
			this.anchors = {
				head: this.anchors.head && reflowed(this.anchors.head, event),
				tail: this.anchors.tail && reflowed(this.anchors.tail, event),
			};
			this.anchoredFor = this.selection;
			this.moved = true;
			return;
		}
		this.anchors = null;
		this.anchoredFor = null;
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
		this.forget();
		this.notifyListeners();
	}

	dropUnlessShown(blocks: readonly BlockView[]): void {
		if (this.selection) {
			const ids = new Set(blocks.map((block) => block.id));
			if (!ids.has(this.selection.head.blockId) || !ids.has(this.selection.tail.blockId)) this.drop();
		}
	}

	view(): SelectionView | null {
		if (!this.selection || !this.deps.hasCore()) return null;
		const rows = this.deps.textRows();
		const selection = this.settle(rows);
		return selection ? resolveSelectionView(selection, rows) : null;
	}

	reset(): void {
		this.forget();
		this.caret = null;
		this.caretAnchor = null;
	}

	private set(selection: SelectionState): void {
		this.selection = selection;
		this.anchors = null;
		this.anchoredFor = null;
		this.moved = false;
		this.changed();
	}

	private placeCaret(point: SelectionPoint): void {
		this.caret = point;
		this.caretAnchor = this.deps.hasCore() ? anchorOf(point, this.deps.textRows()) : null;
	}

	private currentCaret(): SelectionPoint | null {
		if (!this.caret || !this.deps.hasCore()) return null;
		const rows = this.deps.textRows();
		const caret = (this.caretAnchor && pointOf(this.caretAnchor, rows)) ?? this.caret;
		return rows.blockIds.includes(caret.blockId) ? caret : null;
	}

	private settle(rows: TextRows): SelectionState | null {
		const selection = this.selection;
		if (!selection) return null;
		if (this.moved && this.anchors) {
			this.moved = false;
			const head = (this.anchors.head && pointOf(this.anchors.head, rows)) ?? selection.head;
			const tail = (this.anchors.tail && pointOf(this.anchors.tail, rows)) ?? selection.tail;
			this.selection = { ...selection, head, tail };
			this.anchoredFor = this.selection;
			return this.selection;
		}
		if (this.anchoredFor !== selection) {
			this.anchors = selection.kind === "rectangle" ? null : { head: anchorOf(selection.head, rows), tail: anchorOf(selection.tail, rows) };
			this.anchoredFor = selection;
		}
		return selection;
	}

	private forget(): void {
		this.selection = null;
		this.anchors = null;
		this.anchoredFor = null;
		this.moved = false;
	}

	private changed(): void {
		this.deps.repaint();
		this.notifyListeners();
	}

	private notifyListeners(): void {
		for (const listener of [...this.selectionListeners]) listener();
	}
}
