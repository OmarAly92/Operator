import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { installVirtualLayout } from "../../test/virtual-layout";
import type { SessionBlock } from "../../lib/session-block";
import { BlockCard } from "./BlockCard";

function child(id: string, command: string, output: string): SessionBlock {
	return {
		id,
		firstSeq: 1,
		lastSeq: 1,
		kind: "tool",
		status: "ok",
		title: "Shell",
		body: output,
		truncatedLines: 0,
		redacted: false,
		detail: { type: "shell", command, output, exitCode: 0 },
	};
}

function parent(children: SessionBlock[]): SessionBlock {
	return {
		id: "a-parent",
		firstSeq: 2,
		lastSeq: 6,
		kind: "tool",
		status: "ok",
		title: "agent/subagent",
		body: "done",
		truncatedLines: 0,
		redacted: false,
		detail: { type: "mcp_tool", server: "agent", tool: "subagent", args: { task: "explore" }, result: "done" },
		children,
	};
}

let teardown: () => void;

describe("BlockCard children rendering", () => {
	beforeEach(() => {
		teardown = installVirtualLayout({ heights: () => [200] });
	});
	afterEach(() => {
		teardown();
		cleanup();
	});

	it("renders a child BlockCard with the child's summary when a parent has children", () => {
		const childBlock = child("a-child-1", "ls", "file.txt");
		render(<BlockCard block={parent([childBlock])} />);

		expect(screen.getByTestId("session-block-children")).toBeInTheDocument();
		const cards = screen.getAllByTestId("session-block");
		expect(cards).toHaveLength(2);
		expect(screen.getAllByText(/file\.txt/).length).toBeGreaterThan(0);
	});

	it("renders multiple child BlockCards in order", () => {
		const a = child("a-child-1", "ls", "file.txt");
		const b = child("a-child-2", "cat file.txt", "hello");
		render(<BlockCard block={parent([a, b])} />);

		const cards = screen.getAllByTestId("session-block");
		expect(cards).toHaveLength(3);
		expect(screen.getAllByText(/file\.txt/).length).toBeGreaterThan(0);
		expect(screen.getAllByText(/hello/).length).toBeGreaterThan(0);
	});

	it("does not render a children container when the parent has no children", () => {
		render(<BlockCard block={parent([])} />);

		expect(screen.queryByTestId("session-block-children")).not.toBeInTheDocument();
		expect(screen.getAllByTestId("session-block")).toHaveLength(1);
	});
});
