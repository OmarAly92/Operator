import { describe, expect, it, vi } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { renderBlockActions, RERUN_EVENT } from "./block-actions";

const block = {
	id: "0:1", firstRow: 0, rowCount: 1, state: "finished" as const,
	source: "extension" as const, exitCode: 0, durationMs: 1,
	command: "ls -la", cwd: "/tmp", gitBranch: "main",
};

const text = { command: () => "ls -la", output: () => "a.txt\nb.txt" };

describe("renderBlockActions", () => {
	it("copies the command through the host clipboard", async () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		el.querySelector<HTMLButtonElement>("[data-action='copy-command']")!.click();
		expect(writeClipboard).toHaveBeenCalledWith("ls -la");
	});

	it("copies the output through the host clipboard", () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		el.querySelector<HTMLButtonElement>("[data-action='copy-output']")!.click();
		expect(writeClipboard).toHaveBeenCalledWith("a.txt\nb.txt");
	});

	it("offers no rerun action on a synthetic block", () => {
		const el = renderBlockActions(
			{ ...block, source: "synthetic", command: "" },
			{ writeClipboard: vi.fn() } as never,
			defaultStrings,
			text,
		);
		expect(el.querySelector("[data-action='rerun']")).toBeNull();
	});

	it("every action is a real button reachable by keyboard", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		for (const node of el.querySelectorAll("[data-action]")) {
			expect(node.tagName).toBe("BUTTON");
			expect(node.getAttribute("aria-label")).toBeTruthy();
		}
	});

	it("rerun fires a bubbling terminal-block-rerun CustomEvent with the block id", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		const captured: { name: string; detail: unknown; bubbles: boolean }[] = [];
		el.addEventListener(RERUN_EVENT, (event) => {
			const custom = event as CustomEvent<{ blockId: string }>;
			captured.push({ name: custom.type, detail: custom.detail, bubbles: custom.bubbles });
		});
		el.querySelector<HTMLButtonElement>("[data-action='rerun']")!.click();
		expect(captured).toHaveLength(1);
		expect(captured[0]?.name).toBe("terminal-block-rerun");
		expect(captured[0]?.bubbles).toBe(true);
		expect(captured[0]?.detail).toEqual({ blockId: "0:1" });
	});
});

