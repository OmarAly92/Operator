import { describe, expect, it } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { renderPromptRow } from "./prompt-row";

describe("renderPromptRow", () => {
	it("shows cwd and branch from mark data", () => {
		const row = renderPromptRow(
			{
				cwd: "/Users/x/src/app",
				gitBranch: "main",
				lastExitCode: 0,
				lastDurationMs: 120,
				state: "owned",
			},
			defaultStrings,
		);
		expect(row.textContent).toContain("app");
		expect(row.textContent).toContain("main");
	});

	it("marks a failing previous command without inventing an exit code", () => {
		const row = renderPromptRow(
			{ cwd: "/", gitBranch: "", lastExitCode: 1, lastDurationMs: null, state: "owned" },
			defaultStrings,
		);
		expect(row.dataset.lastExit).toBe("1");
		const none = renderPromptRow(
			{ cwd: "/", gitBranch: "", lastExitCode: null, lastDurationMs: null, state: "owned" },
			defaultStrings,
		);
		expect(none.dataset.lastExit).toBeUndefined();
	});

	it("says the shell owns the line when state is not owned", () => {
		const row = renderPromptRow(
			{ cwd: "/", gitBranch: "", lastExitCode: null, lastDurationMs: null, state: "unknown" },
			defaultStrings,
		);
		expect(row.dataset.state).toBe("unknown");
	});

	it("does not invent a cwd before the shell reports one", () => {
		const row = renderPromptRow(
			{ cwd: "", gitBranch: "", lastExitCode: null, lastDurationMs: null, state: "unknown" },
			defaultStrings,
		);
		expect(row.querySelector(".terminal-editor-prompt-cwd")?.textContent).toBe("");
	});
});
