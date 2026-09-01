import type {
	BlockId,
	BlockView,
	HostCapabilities,
	TerminalStrings,
} from "@operator/terminal-core";

const CLASS_ACTIONS = "terminal-block-actions";

export type BlockTextSource = Readonly<{
	command(id: BlockId): string;
	output(id: BlockId): string;
}>;

export const RERUN_EVENT = "terminal-block-rerun";
export const BOOKMARK_EVENT = "terminal-block-bookmark";
export const FILTER_COMMAND_EVENT = "terminal-block-filter-command";
export const JUMP_EVENT = "terminal-block-jump";

type Action = "copy-command" | "copy-output" | "share-output" | "bookmark" | "filter-to-command" | "jump" | "rerun";

function actionsFor(block: BlockView): readonly Action[] {
	if (block.source === "synthetic") {
		return ["copy-output"] as const;
	}
	return ["copy-command", "copy-output", "share-output", "bookmark", "filter-to-command", "jump", "rerun"] as const;
}

function ariaFor(action: Action, strings: TerminalStrings): string {
	switch (action) {
		case "copy-command":
			return strings.copyCommand;
		case "copy-output":
			return strings.copyOutput;
		case "share-output":
			return strings.shareOutput;
		case "bookmark":
			return strings.bookmark;
		case "filter-to-command":
			return strings.filterToCommand;
		case "jump":
			return strings.jump;
		case "rerun":
			return strings.rerunCommand;
	}
}

function makeButton(
	action: Action,
	label: string,
	host: HostCapabilities,
	block: BlockView,
	text: BlockTextSource,
): HTMLButtonElement {
	const button = document.createElement("button");
	button.type = "button";
	button.dataset.action = action;
	button.setAttribute("aria-label", label);
	button.className = `terminal-block-action terminal-block-action-${action}`;
	button.textContent = label;
	button.addEventListener("click", (event) => {
		event.preventDefault();
		event.stopPropagation();
		runAction(action, button, host, block, text);
	});
	return button;
}

export function runAction(
	action: Action,
	button: HTMLElement,
	host: HostCapabilities,
	block: BlockView,
	text: BlockTextSource,
): void {
	switch (action) {
		case "rerun":
			button.dispatchEvent(
				new CustomEvent(RERUN_EVENT, { detail: { blockId: block.id }, bubbles: true }),
			);
			return;
		case "bookmark":
			button.dispatchEvent(
				new CustomEvent(BOOKMARK_EVENT, { detail: { blockId: block.id }, bubbles: true }),
			);
			return;
		case "filter-to-command":
			button.dispatchEvent(
				new CustomEvent(FILTER_COMMAND_EVENT, { detail: { blockId: block.id, command: block.command }, bubbles: true }),
			);
			return;
		case "jump":
			button.dispatchEvent(
				new CustomEvent(JUMP_EVENT, { detail: { blockId: block.id }, bubbles: true }),
			);
			return;
		case "copy-command":
			void host.writeClipboard(text.command(block.id));
			return;
		case "copy-output":
			void host.writeClipboard(text.output(block.id));
			return;
		case "share-output":
			void host.writeClipboard(text.output(block.id));
			return;
	}
}

export function renderBlockActions(
	block: BlockView,
	host: HostCapabilities,
	strings: TerminalStrings,
	text: BlockTextSource,
): HTMLElement {
	const container = document.createElement("div");
	container.className = CLASS_ACTIONS;
	container.dataset.terminalBlockActions = block.id;
	for (const action of actionsFor(block)) {
		container.append(makeButton(action, ariaFor(action, strings), host, block, text));
	}
	return container;
}

export function actionLabels(block: BlockView, strings: TerminalStrings): string[] {
	return actionsFor(block).map((action) => ariaFor(action, strings));
}
