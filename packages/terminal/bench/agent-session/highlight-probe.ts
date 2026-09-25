import { defaultStrings, type BlockRenderer, type TerminalCore } from "@operator/terminal-core";
import { createFindBar, type DomBlockRenderer, type FindBar, type SelectionPoint } from "@operator/terminal-renderer-dom";

export type HighlightProbe = {
	selectCells(fromRow: number, fromCell: number, toRow: number, toCell: number): Promise<void>;
	selectionClear(): Promise<void>;
	findShow(query: string, steps: number): Promise<string>;
	findHide(): Promise<void>;
};

function frame(): Promise<void> {
	return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

async function frames(count: number): Promise<void> {
	for (let index = 0; index < count; index += 1) await frame();
}

export function highlightProbe(host: HTMLElement, core: TerminalCore, renderer: DomBlockRenderer): HighlightProbe {
	let bar: FindBar | null = null;
	const point = (row: number, cell: number): SelectionPoint => {
		const node = host.querySelector<HTMLElement>(`[data-terminal-row="${core.snapshot().firstStableRow + row}"]`);
		if (!node) throw new Error(`row ${row} is not rendered`);
		const rect = node.getBoundingClientRect();
		const { cellWidth, cellHeight } = renderer.measure();
		const found = renderer.pointAt(rect.left + (cell + 0.25) * cellWidth, rect.top + cellHeight / 2);
		if (!found) throw new Error(`no cell at ${row}:${cell}`);
		return found;
	};
	return {
		async selectCells(fromRow, fromCell, toRow, toCell) {
			renderer.selectionBegin(point(fromRow, fromCell), "simple");
			renderer.selectionUpdate(point(toRow, toCell));
			await frames(2);
		},
		async selectionClear() {
			renderer.selectionClear();
			await frames(2);
		},
		async findShow(query, steps) {
			if (!bar) {
				bar = createFindBar({
					core,
					renderer: renderer as unknown as BlockRenderer,
					host: {
						scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
						scrollToRow: (row, align) => renderer.scrollToRow(row, align),
						invalidate: (range) => renderer.invalidate(range),
						afterRepaint: (listener) => renderer.onPaint(listener),
						highlightFind: (find) => renderer.setFindHighlights(find),
					},
					strings: defaultStrings,
				});
				bar.mount(host);
			}
			bar.open();
			const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]");
			if (!input) throw new Error("the find bar has no input");
			input.value = query;
			input.dispatchEvent(new Event("input", { bubbles: true }));
			await frames(8);
			for (let step = 0; step < steps; step += 1) {
				input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
				await frames(4);
			}
			input.blur();
			await frames(2);
			return host.querySelector("[data-terminal-find-count]")?.textContent ?? "";
		},
		async findHide() {
			bar?.close();
			await frames(2);
		},
	};
}
