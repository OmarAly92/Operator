import { describe, expect, it } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { createPinnedHeaderElement, renderPinnedHeader, updatePinnedHeader } from "./pinned-header";

const baseBlock = {
	id: "0:1",
	firstRow: 0,
	rowCount: 2,
	source: "extension" as const,
	command: "git status",
	cwd: "/Users/me/project",
	gitBranch: "main",
	bookmarked: false,
};

describe("renderPinnedHeader", () => {
	it("renders the command text inside the pinned header", () => {
		const el = renderPinnedHeader(
			{ ...baseBlock, state: "finished", exitCode: 0, durationMs: 1200 },
			defaultStrings,
		);
		expect(el.textContent).toContain("git status");
		expect(el.textContent).toContain("main");
		expect(el.classList.contains("terminal-pinned-header")).toBe(true);
		expect(el.dataset.terminalPinned).toBe("true");
	});

	it("hides itself when the block is plain", () => {
		const el = renderPinnedHeader(
			{ ...baseBlock, source: "synthetic", state: "finished", exitCode: 0, durationMs: null },
			defaultStrings,
		);
		expect(el.hidden).toBe(true);
	});

	it("uses the right status aria-label, not always 'Running'", () => {
		const succeeded = renderPinnedHeader(
			{ ...baseBlock, state: "finished", exitCode: 0, durationMs: 100 },
			defaultStrings,
		);
		expect(succeeded.getAttribute("aria-label")).toBe(defaultStrings.blockSucceeded);
		const failed = renderPinnedHeader(
			{ ...baseBlock, state: "finished", exitCode: 2, durationMs: 100 },
			defaultStrings,
		);
		expect(failed.getAttribute("aria-label")).toBe(defaultStrings.blockFailed);
	});
});

describe("updatePinnedHeader", () => {
	it("hides when pinnedIndex is -1", () => {
		const target = createPinnedHeaderElement();
		updatePinnedHeader(target, [], -1, defaultStrings);
		expect(target.hidden).toBe(true);
	});

	it("hides when the pinned block is synthetic", () => {
		const target = createPinnedHeaderElement();
		const synthetic = {
			...baseBlock,
			id: "0:2",
			source: "synthetic" as const,
			state: "finished" as const,
			exitCode: 0,
			durationMs: null,
		};
		updatePinnedHeader(target, [synthetic], 0, defaultStrings);
		expect(target.hidden).toBe(true);
	});

	it("shows the pinned block's command when the index points at it", () => {
		const target = createPinnedHeaderElement();
		const tall = { ...baseBlock, id: "0:1", state: "finished" as const, exitCode: 0, durationMs: 100 };
		const next = { ...baseBlock, id: "0:2", command: "ls", state: "finished" as const, exitCode: 0, durationMs: 100 };
		updatePinnedHeader(target, [tall, next], 0, defaultStrings);
		expect(target.hidden).toBe(false);
		expect(target.textContent).toContain("git status");
		expect(target.textContent).not.toContain("ls");
	});

	it("hands over to the next block's command after the index moves", () => {
		const target = createPinnedHeaderElement();
		const tall = { ...baseBlock, id: "0:1", state: "finished" as const, exitCode: 0, durationMs: 100 };
		const next = { ...baseBlock, id: "0:2", command: "ls", state: "finished" as const, exitCode: 0, durationMs: 100 };
		updatePinnedHeader(target, [tall, next], 0, defaultStrings);
		expect(target.textContent).toContain("git status");
		updatePinnedHeader(target, [tall, next], 1, defaultStrings);
		expect(target.textContent).toContain("ls");
		expect(target.textContent).not.toContain("git status");
	});
});

describe("createPinnedHeaderElement", () => {
	it("returns an element with the pinned class and data-testid, hidden by default", () => {
		const el = createPinnedHeaderElement();
		expect(el.classList.contains("terminal-pinned-header")).toBe(true);
		expect(el.getAttribute("data-testid")).toBe("terminal-pinned-header");
		expect(el.hidden).toBe(true);
	});
});
