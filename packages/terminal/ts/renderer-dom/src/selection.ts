import type { BlockId } from "@operator/terminal-core";

const BLOCK_ATTR = "data-terminal-block-id";
const BLOCK_SELECTOR = `[${BLOCK_ATTR}]`;

export type BlockRange = Readonly<{
	startBlock: BlockId;
	endBlock: BlockId;
}>;

function findBlockAncestor(node: Node | null, root: HTMLElement): BlockId | null {
	let current: Node | null = node;
	while (current) {
		if (current instanceof HTMLElement && current.hasAttribute(BLOCK_ATTR)) {
			const id = current.dataset.terminalBlockId;
			if (id && (current === root || root.contains(current))) {
				return id;
			}
			return null;
		}
		if (current === root) break;
		current = current.parentNode;
	}
	return null;
}

function positionInDocument(root: HTMLElement, id: BlockId): number {
	const element = root.querySelector(`${BLOCK_SELECTOR}[data-terminal-block-id="${cssEscape(id)}"]`);
	if (!element) return -1;
	let position = 0;
	let node: Node | null = element.previousSibling;
	while (node) {
		if (node instanceof HTMLElement && node.hasAttribute(BLOCK_ATTR)) {
			position += 1;
		}
		node = node.previousSibling;
	}
	return position;
}

function cssEscape(value: string): string {
	if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
		return CSS.escape(value);
	}
	return value.replace(/(["\\])/g, "\\$1");
}

export function selectionToBlockRange(
	root: HTMLElement,
	selection: Selection,
): BlockRange | null {
	if (!selection || selection.rangeCount === 0) return null;
	if (selection.isCollapsed) return null;
	const range = selection.getRangeAt(0);
	if (range.collapsed) return null;
	if (!root.contains(range.startContainer) || !root.contains(range.endContainer)) {
		return null;
	}
	const startBlock = findBlockAncestor(selection.anchorNode, root);
	const endBlock = findBlockAncestor(selection.focusNode, root);
	if (!startBlock || !endBlock) return null;
	const startPos = positionInDocument(root, startBlock);
	const endPos = positionInDocument(root, endBlock);
	if (startPos < 0 || endPos < 0) return null;
	if (startPos <= endPos) {
		return { startBlock, endBlock };
	}
	return { startBlock: endBlock, endBlock: startBlock };
}
