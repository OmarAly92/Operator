import { blockDisplay, type SessionBlock } from "./session-block";

export type BlockActionKind = "copy_block" | "copy_command" | "copy_output" | "rerun" | "rewind";

export type BlockActionContext = {
	mode: "tui" | "chat";
	capabilities: readonly string[];
	canSend: boolean;
	turnInFlight: boolean;
	rollbackableTurnIds: readonly string[];
};

export type BlockAction = { kind: BlockActionKind; payload?: string; turnId?: string };

export function blockActionsFor(block: SessionBlock, ctx: BlockActionContext): BlockAction[] {
	const actions: BlockAction[] = [{ kind: "copy_block", payload: blockCopyText(block) }];
	if (block.detail?.type === "shell" && block.detail.command) actions.push({ kind: "copy_command", payload: block.detail.command });
	if (block.detail?.type === "shell" && block.detail.output) actions.push({ kind: "copy_output", payload: block.detail.output });
	else if (block.kind === "tool" && block.body) actions.push({ kind: "copy_output", payload: block.body });
	if (ctx.canSend && block.kind === "prompt" && block.body && !ctx.turnInFlight) actions.push({ kind: "rerun", payload: block.body });
	if (ctx.mode === "chat" && ctx.capabilities.includes("rollback") && !ctx.turnInFlight && block.turnId && ctx.rollbackableTurnIds.includes(block.turnId)) {
		actions.push({ kind: "rewind", turnId: block.turnId });
	}
	return actions;
}

export function blockCopyText(block: SessionBlock): string {
	const display = blockDisplay(block);
	const rendered = [display.displayName, display.summary, display.errorText].filter((part): part is string => part !== undefined && part !== "").join("\n").trimEnd();
	const children = block.children ?? [];
	if (children.length === 0) return rendered;
	return [rendered, ...children.map((child) => blockCopyText(child).split("\n").map((line) => `  ${line}`).join("\n"))].join("\n\n");
}

export function blocksToText(blocks: readonly SessionBlock[]): string {
	return blocks.map(blockCopyText).join("\n\n");
}
