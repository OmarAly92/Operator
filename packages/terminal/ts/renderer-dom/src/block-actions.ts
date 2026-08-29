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

type Action = "copy-command" | "copy-output" | "rerun";

function actionsFor(block: BlockView): readonly Action[] {
	if (block.source === "synthetic") {
		return ["copy-output"] as const;
	}
	return ["copy-command", "copy-output", "rerun"] as const;
}

function ariaFor(action: Action, strings: TerminalStrings): string {
	switch (action) {
		case "copy-command":
			return strings.copyCommand;
		case "copy-output":
			return strings.copyOutput;
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
		if (action === "rerun") {
			button.dispatchEvent(
				new CustomEvent(RERUN_EVENT, {
					detail: { blockId: block.id },
					bubbles: true,
				}),
			);
			return;
		}
		const value = action === "copy-command" ? text.command(block.id) : text.output(block.id);
		void host.writeClipboard(value);
	});
	return button;
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
