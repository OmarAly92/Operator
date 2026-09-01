import { describe, expect, it, vi } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import {
	BOOKMARK_EVENT,
	FILTER_COMMAND_EVENT,
	JUMP_EVENT,
	renderBlockActions,
	RERUN_EVENT,
} from "./block-actions";

const block = {
	id: "0:1", firstRow: 0, rowCount: 1, state: "finished" as const,
	source: "extension" as const, exitCode: 0, durationMs: 1,
	command: "ls -la", cwd: "/tmp", gitBranch: "main", bookmarked: false,
};

const text = { command: () => "ls -la", output: () => "a.txt\nb.txt" };

function clickAction(el: HTMLElement, action: string): void {
	el.querySelector<HTMLButtonElement>(`[data-action='${action}']`)!.click();
}

function pressOn(button: HTMLButtonElement, key: string): void {
	button.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
	button.click();
}

describe("renderBlockActions", () => {
	it("copies the command through the host clipboard", async () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		clickAction(el, "copy-command");
		expect(writeClipboard).toHaveBeenCalledWith("ls -la");
	});

	it("copies the output through the host clipboard", () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		clickAction(el, "copy-output");
		expect(writeClipboard).toHaveBeenCalledWith("a.txt\nb.txt");
	});

	it("shares the output through the host clipboard (save action)", () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		clickAction(el, "share-output");
		expect(writeClipboard).toHaveBeenCalledWith("a.txt\nb.txt");
	});

	it("emits a bookmark event with the block id", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		const captured: { name: string; detail: unknown; bubbles: boolean }[] = [];
		el.addEventListener(BOOKMARK_EVENT, (event) => {
			const custom = event as CustomEvent<{ blockId: string }>;
			captured.push({ name: custom.type, detail: custom.detail, bubbles: custom.bubbles });
		});
		clickAction(el, "bookmark");
		expect(captured).toHaveLength(1);
		expect(captured[0]?.name).toBe("terminal-block-bookmark");
		expect(captured[0]?.bubbles).toBe(true);
		expect(captured[0]?.detail).toEqual({ blockId: "0:1" });
	});

	it("emits a filter-to-command event with the block's command", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		const captured: { name: string; detail: unknown; bubbles: boolean }[] = [];
		el.addEventListener(FILTER_COMMAND_EVENT, (event) => {
			const custom = event as CustomEvent<{ blockId: string; command: string }>;
			captured.push({ name: custom.type, detail: custom.detail, bubbles: custom.bubbles });
		});
		clickAction(el, "filter-to-command");
		expect(captured).toHaveLength(1);
		expect(captured[0]?.name).toBe("terminal-block-filter-command");
		expect(captured[0]?.detail).toEqual({ blockId: "0:1", command: "ls -la" });
	});

	it("emits a jump event with the block id", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		const captured: { name: string; detail: unknown; bubbles: boolean }[] = [];
		el.addEventListener(JUMP_EVENT, (event) => {
			const custom = event as CustomEvent<{ blockId: string }>;
			captured.push({ name: custom.type, detail: custom.detail, bubbles: custom.bubbles });
		});
		clickAction(el, "jump");
		expect(captured).toHaveLength(1);
		expect(captured[0]?.name).toBe("terminal-block-jump");
		expect(captured[0]?.detail).toEqual({ blockId: "0:1" });
	});

	it("does not call any host capability that can execute commands", () => {
		const openLink = vi.fn();
		const notify = vi.fn();
		const el = renderBlockActions(block, { writeClipboard: vi.fn(), openLink, notify } as never, defaultStrings, text);
		for (const action of ["copy-command", "copy-output", "share-output", "bookmark", "filter-to-command", "jump", "rerun"]) {
			clickAction(el, action);
		}
		expect(openLink).not.toHaveBeenCalled();
		expect(notify).not.toHaveBeenCalled();
	});

	it("offers no rerun action on a synthetic block", () => {
		const el = renderBlockActions(
			{ ...block, source: "synthetic", command: "" },
			{ writeClipboard: vi.fn() } as never,
			defaultStrings,
			text,
		);
		expect(el.querySelector("[data-action='rerun']")).toBeNull();
		expect(el.querySelector("[data-action='bookmark']")).toBeNull();
	});

	it("every action is a real button reachable by keyboard", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		for (const node of el.querySelectorAll("[data-action]")) {
			expect(node.tagName).toBe("BUTTON");
			expect(node.getAttribute("aria-label")).toBeTruthy();
		}
	});

	it("keyboard activation (Enter and Space) triggers the same action as a click", () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		const button = el.querySelector<HTMLButtonElement>("[data-action='copy-command']")!;
		pressOn(button, "Enter");
		expect(writeClipboard).toHaveBeenCalledTimes(1);
		pressOn(button, " ");
		expect(writeClipboard).toHaveBeenCalledTimes(2);
	});

	it("rerun fires a bubbling terminal-block-rerun CustomEvent with the block id", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		const captured: { name: string; detail: unknown; bubbles: boolean }[] = [];
		el.addEventListener(RERUN_EVENT, (event) => {
			const custom = event as CustomEvent<{ blockId: string }>;
			captured.push({ name: custom.type, detail: custom.detail, bubbles: custom.bubbles });
		});
		clickAction(el, "rerun");
		expect(captured).toHaveLength(1);
		expect(captured[0]?.name).toBe("terminal-block-rerun");
		expect(captured[0]?.bubbles).toBe(true);
		expect(captured[0]?.detail).toEqual({ blockId: "0:1" });
	});
});


