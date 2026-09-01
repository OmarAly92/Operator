import { describe, expect, it } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { renderBlockHeader } from "./block-header";

const base = {
	id: "0:1",
	firstRow: 0,
	rowCount: 2,
	source: "extension" as const,
	command: "git status",
	cwd: "/Users/me/project",
	gitBranch: "main",
	bookmarked: false,
};

describe("renderBlockHeader", () => {
	it("shows the command, cwd and branch", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 1200 },
			defaultStrings,
		);
		expect(el.textContent).toContain("git status");
		expect(el.textContent).toContain("main");
	});

	it("marks a non-zero exit as failed and shows the code", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 127, durationMs: 5 },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("failed");
		expect(el.textContent).toContain("127");
	});

	it("marks exit zero as succeeded", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 5 },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("succeeded");
	});

	it("marks a running block as running and shows no exit code", () => {
		const el = renderBlockHeader(
			{ ...base, state: "running", exitCode: null, durationMs: null },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("running");
		expect(el.textContent).not.toContain("null");
	});

	it("marks an abandoned block distinctly from a failed one", () => {
		const el = renderBlockHeader(
			{ ...base, state: "abandoned", exitCode: null, durationMs: null },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("abandoned");
	});

	it("renders a synthetic block without a header chrome row", () => {
		const el = renderBlockHeader(
			{ ...base, source: "synthetic", state: "running", exitCode: null, durationMs: null, command: "" },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("plain");
	});

	it("escapes command text rather than interpreting it as markup", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 1, command: "<img src=x onerror=1>" },
			defaultStrings,
		);
		expect(el.querySelector("img")).toBeNull();
		expect(el.textContent).toContain("<img");
	});

	it("formats sub-second and multi-second durations differently", () => {
		const fast = renderBlockHeader({ ...base, state: "finished", exitCode: 0, durationMs: 42 }, defaultStrings);
		const slow = renderBlockHeader({ ...base, state: "finished", exitCode: 0, durationMs: 92_000 }, defaultStrings);
		expect(fast.textContent).toContain("42ms");
		expect(slow.textContent).toContain("1m");
	});
});
