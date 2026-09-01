import type { BlockId } from "@operator/terminal-core";
import { BOOKMARK_EVENT, FILTER_COMMAND_EVENT, JUMP_EVENT } from "./block-actions.js";

export type ActionEventSink = Readonly<{
	setBlockBookmarked(id: BlockId, bookmarked: boolean): void;
	getBlockBookmarked(id: BlockId): boolean;
	setFilter(filter: { command: string }): void;
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	scheduleRepaint(): void;
}>;

export function bindActionEvents(target: HTMLElement, sink: ActionEventSink): void {
	target.addEventListener(BOOKMARK_EVENT, (event) => {
		const id = (event as CustomEvent<{ blockId: BlockId }>).detail?.blockId;
		if (id) { sink.setBlockBookmarked(id, !sink.getBlockBookmarked(id)); sink.scheduleRepaint(); }
	});
	target.addEventListener(FILTER_COMMAND_EVENT, (event) => {
		const detail = (event as CustomEvent<{ blockId: BlockId; command: string }>).detail;
		if (detail?.blockId) sink.setFilter({ command: detail.command });
	});
	target.addEventListener(JUMP_EVENT, (event) => {
		const id = (event as CustomEvent<{ blockId: BlockId }>).detail?.blockId;
		if (id) sink.scrollToBlock(id, "start");
	});
}
