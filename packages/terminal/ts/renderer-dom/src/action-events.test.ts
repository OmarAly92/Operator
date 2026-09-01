import { describe, expect, it } from "vitest";
import { bindActionEvents, type ActionEventSink } from "./action-events";
import { BOOKMARK_EVENT, FILTER_COMMAND_EVENT, JUMP_EVENT } from "./block-actions";

function makeSink(overrides: Partial<ActionEventSink> = {}): ActionEventSink & {
	calls: { name: keyof ActionEventSink; args: unknown[] }[];
} {
	const calls: { name: keyof ActionEventSink; args: unknown[] }[] = [];
	const wrap = <K extends keyof ActionEventSink>(name: K) => {
		const fn = (...args: unknown[]) => {
			calls.push({ name, args });
		};
		return fn as unknown as ActionEventSink[K];
	};
	const sink: ActionEventSink = {
		setBlockBookmarked: overrides.setBlockBookmarked ?? wrap("setBlockBookmarked"),
		getBlockBookmarked: overrides.getBlockBookmarked ?? wrap("getBlockBookmarked"),
		setFilter: overrides.setFilter ?? wrap("setFilter"),
		scrollToBlock: overrides.scrollToBlock ?? wrap("scrollToBlock"),
		scheduleRepaint: overrides.scheduleRepaint ?? wrap("scheduleRepaint"),
	};
	return Object.assign(sink, { calls });
}

function dispatch(target: HTMLElement, type: string, detail: unknown): void {
	target.dispatchEvent(new CustomEvent(type, { detail, bubbles: true, cancelable: true }));
}

describe("bindActionEvents", () => {
	it("toggles the bookmark when BOOKMARK_EVENT fires", () => {
		const target = document.createElement("div");
		const sink = makeSink({ getBlockBookmarked: () => false });
		bindActionEvents(target, sink);
		dispatch(target, BOOKMARK_EVENT, { blockId: "0:0" });
		expect(sink.calls.find((c) => c.name === "setBlockBookmarked")?.args).toEqual(["0:0", true]);
		expect(sink.calls.find((c) => c.name === "scheduleRepaint")).toBeDefined();
	});

	it("sets a filter to the block's command on FILTER_COMMAND_EVENT", () => {
		const target = document.createElement("div");
		const sink = makeSink();
		bindActionEvents(target, sink);
		dispatch(target, FILTER_COMMAND_EVENT, { blockId: "0:1", command: "ls" });
		expect(sink.calls.find((c) => c.name === "setFilter")?.args).toEqual([{ command: "ls" }]);
	});

	it("scrolls to the block on JUMP_EVENT", () => {
		const target = document.createElement("div");
		const sink = makeSink();
		bindActionEvents(target, sink);
		dispatch(target, JUMP_EVENT, { blockId: "0:2" });
		expect(sink.calls.find((c) => c.name === "scrollToBlock")?.args).toEqual(["0:2", "start"]);
	});

	it("ignores events with no block id", () => {
		const target = document.createElement("div");
		const sink = makeSink();
		bindActionEvents(target, sink);
		dispatch(target, BOOKMARK_EVENT, undefined);
		dispatch(target, JUMP_EVENT, undefined);
		dispatch(target, FILTER_COMMAND_EVENT, undefined);
		expect(sink.calls).toHaveLength(0);
	});
});
