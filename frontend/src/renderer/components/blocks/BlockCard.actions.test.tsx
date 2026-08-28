import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { BlockAction } from "../../lib/block-actions";
import type { SessionBlock } from "../../lib/session-block";
import { BlockCard } from "./BlockCard";

function block(): SessionBlock {
	return {
		id: "block-1",
		firstSeq: 1,
		lastSeq: 1,
		kind: "tool",
		status: "failed",
		title: "Shell",
		body: "command output",
		truncatedLines: 4,
		redacted: true,
		detail: { type: "shell", command: "false", output: "command output", exitCode: 1 },
		children: [
			{
				id: "child-1",
				firstSeq: 1,
				lastSeq: 1,
				kind: "notice",
				status: "ok",
				title: "Child",
				body: "child summary",
				truncatedLines: 0,
				redacted: false,
			},
		],
	};
}

afterEach(cleanup);

describe("BlockCard standard actions", () => {
	it("collapsing keeps the header and hides block content", () => {
		const onToggleCollapse = vi.fn();
		render(
			<BlockCard
				actions={[{ kind: "copy_block", payload: "Shell\ncommand output" }]}
				block={block()}
				collapsed
				onToggleCollapse={onToggleCollapse}
			/>,
		);

		expect(screen.getByRole("button", { name: /expand/i })).toHaveAttribute("aria-expanded", "false");
		expect(screen.getByText("Shell")).toBeInTheDocument();
		expect(screen.queryByText("command output")).not.toBeInTheDocument();
		expect(screen.queryByText("child summary")).not.toBeInTheDocument();
		expect(screen.queryByText("Exit code 1")).not.toBeInTheDocument();
		expect(screen.queryByText(/Secrets were redacted/)).not.toBeInTheDocument();
		expect(screen.queryByText(/more lines/)).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-actions")).not.toBeInTheDocument();

		fireEvent.click(screen.getByRole("button", { name: /expand/i }));
		expect(onToggleCollapse).toHaveBeenCalledWith("block-1");
	});

	it("renders standard actions in order and calls onAction with the selected action", () => {
		const item = block();
		const actions: BlockAction[] = [
			{ kind: "copy_block", payload: "Shell\ncommand output" },
			{ kind: "copy_output", payload: "command output" },
			{ kind: "rewind", turnId: "turn-1" },
		];
		const onAction = vi.fn();
		render(<BlockCard actions={actions} block={item} onAction={onAction} />);

		const buttons = screen.getAllByTestId(/block-action-/);
		expect(buttons.map((button) => button.getAttribute("data-testid"))).toEqual([
			"block-action-copy_block",
			"block-action-copy_output",
			"block-action-rewind",
		]);

		fireEvent.click(screen.getByTestId("block-action-copy_output"));
		expect(onAction).toHaveBeenCalledWith(item, actions[1]);
	});
});
