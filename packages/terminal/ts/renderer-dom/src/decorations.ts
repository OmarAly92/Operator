import type { LinkRange } from "./logical-lines.js";
import type { RenderedRow } from "./selection-view.js";

export type DecorationBox = Readonly<{ left: number; top: number; width: number; height: number }>;

export function rangeBoxes(range: LinkRange, rows: readonly RenderedRow[], cellWidth: number, container: HTMLElement): DecorationBox[] {
	const origin = container.getBoundingClientRect();
	const boxes: DecorationBox[] = [];
	for (const { box } of rows) {
		if (box.blockId !== range.blockId || box.row < range.startRow || box.row > range.endRow) continue;
		const left = box.row === range.startRow ? Math.min(range.startCell * cellWidth, box.width) : 0;
		const right = box.row === range.endRow ? Math.min(range.endCell * cellWidth, box.width) : box.width;
		if (right - left <= 0.5) continue;
		boxes.push({
			left: box.left + left - origin.left + container.scrollLeft,
			top: box.top - origin.top + container.scrollTop,
			width: right - left,
			height: box.bottom - box.top,
		});
	}
	return boxes;
}

export function paintBoxes(layer: HTMLElement, className: string, boxes: readonly DecorationBox[], labels?: readonly string[]): void {
	while (layer.children.length > boxes.length) layer.lastElementChild!.remove();
	for (let index = 0; index < boxes.length; index += 1) {
		let node = layer.children[index] as HTMLElement | undefined;
		if (!node) {
			node = document.createElement("div");
			layer.append(node);
		}
		node.className = className;
		const box = boxes[index]!;
		node.style.left = `${box.left}px`;
		node.style.top = `${box.top}px`;
		node.style.width = `${box.width}px`;
		node.style.height = `${box.height}px`;
		node.textContent = labels?.[index] ?? "";
	}
}
