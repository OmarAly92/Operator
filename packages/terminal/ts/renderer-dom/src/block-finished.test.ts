import { describe, expect, it } from "vitest";
import type { BlockView } from "@operator/terminal-core";
import { finishedBlocks, rendererVisible } from "./block-finished";

function block(id: string, state: BlockView["state"]): BlockView {
	return { id, firstRow: 0, rowCount: 1, state, source: "osc133", exitCode: state === "finished" ? 0 : null, durationMs: state === "finished" ? 10 : null, startedAtMs: 1, finishedAtMs: state === "finished" ? 11 : null, command: "", cwd: "", gitBranch: "", bookmarked: false };
}

describe("finishedBlocks", () => {
	it("reports a block that was running last paint and is finished or abandoned now", () => {
		const previous = new Map([["a", "running" as const], ["b", "running" as const]]);
		const now = [block("a", "finished"), block("b", "abandoned"), block("c", "finished")];
		expect(finishedBlocks(previous, now).map((b) => b.id)).toEqual(["a", "b"]);
	});
	it("does not report a block first seen already finished, nor one still running", () => {
		expect(finishedBlocks(new Map(), [block("a", "finished")])).toEqual([]);
		expect(finishedBlocks(new Map([["a", "running" as const]]), [block("a", "running")])).toEqual([]);
	});
});

describe("rendererVisible", () => {
	it("is false for a detached or inert container and true for one in layout", () => {
		const detached = document.createElement("div");
		expect(rendererVisible(detached)).toBe(false);
		const parked = document.createElement("div");
		parked.setAttribute("inert", "");
		const inner = document.createElement("div");
		parked.append(inner);
		document.body.append(parked);
		expect(rendererVisible(inner)).toBe(false);
		const shown = document.createElement("div");
		document.body.append(shown);
		shown.getClientRects = () => [{}] as unknown as DOMRectList;
		expect(rendererVisible(shown)).toBe(true);
	});
});
