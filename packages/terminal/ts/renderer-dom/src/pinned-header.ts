import type { BlockView, TerminalStrings } from "@operator/terminal-core";
import { blockHeaderStatus, renderBlockHeaderContent, statusLabel } from "./block-header.js";

const CLASS_PINNED = "terminal-pinned-header";

export function renderPinnedHeader(block: BlockView, strings: TerminalStrings): HTMLElement {
	const header = document.createElement("div");
	header.className = CLASS_PINNED;
	const status = blockHeaderStatus(block);
	header.dataset.blockStatus = status;
	header.dataset.terminalPinned = "true";
	if (status === "plain") {
		header.hidden = true;
		return header;
	}
	header.append(renderBlockHeaderContent(block, null));
	header.setAttribute("aria-label", statusLabel(status, strings));
	return header;
}

export function updatePinnedHeader(
	target: HTMLElement,
	blocks: readonly BlockView[],
	pinnedIndex: number,
	strings: TerminalStrings,
): void {
	if (pinnedIndex < 0 || pinnedIndex >= blocks.length) {
		target.hidden = true;
		return;
	}
	const block = blocks[pinnedIndex];
	if (!block || block.source === "synthetic") {
		target.hidden = true;
		return;
	}
	const next = renderPinnedHeader(block, strings);
	target.replaceChildren(...Array.from(next.children));
	target.dataset.blockStatus = next.dataset.blockStatus ?? "plain";
	target.setAttribute("aria-label", next.getAttribute("aria-label") ?? "");
	target.hidden = false;
}

export function createPinnedHeaderElement(): HTMLElement {
	const el = document.createElement("div");
	el.className = CLASS_PINNED;
	el.hidden = true;
	el.setAttribute("data-testid", "terminal-pinned-header");
	return el;
}
