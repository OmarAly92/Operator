import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import { installVirtualLayout } from "../../test/virtual-layout";
import { BlockList } from "./BlockList";

function permission(id: string, status: "blocked" | "ok" = "blocked"): SessionBlock {
	return {
		id,
		firstSeq: 1,
		lastSeq: 1,
		kind: "permission",
		status,
		title: "Permission requested",
		body: "Bash\ngit branch -D feat/x",
		truncatedLines: 0,
		redacted: false,
	};
}

function prompt(id: string, turnId?: string): SessionBlock {
	return {
		id,
		firstSeq: 1,
		lastSeq: 1,
		kind: "prompt",
		status: "ok",
		turnId,
		title: "Prompt",
		body: "run the tests",
		truncatedLines: 0,
		redacted: false,
	};
}

function assistant(id: string, turnId?: string): SessionBlock {
	return {
		id,
		firstSeq: 2,
		lastSeq: 2,
		kind: "assistant",
		status: "ok",
		turnId,
		title: "Assistant",
		body: "all green",
		truncatedLines: 0,
		redacted: false,
	};
}

let teardown: () => void;
let currentBlocks: SessionBlock[] = [];

beforeEach(() => {
	teardown = installVirtualLayout({ heights: () => currentBlocks.map(() => 80) });
});
afterEach(() => {
	teardown();
	cleanup();
});

function renderList(props: Partial<Parameters<typeof BlockList>[0]> & { blocks: SessionBlock[] }) {
	currentBlocks = props.blocks;
	return render(<BlockList sessionId="s-1" {...props} />);
}

describe("BlockList capability-gated actions", () => {
	it("renders approve and deny buttons on a blocked approval permission block", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "approval"]]),
			onApprove: vi.fn(),
			onDecline: vi.fn(),
		});

		expect(screen.getByTestId("block-approve")).toBeInTheDocument();
		expect(screen.getByTestId("block-decline")).toBeInTheDocument();
	});

	it("hides approve and deny buttons when permissionKind is not approval", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "user_input"]]),
			onApprove: vi.fn(),
			onDecline: vi.fn(),
		});

		expect(screen.queryByTestId("block-approve")).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-decline")).not.toBeInTheDocument();
	});

	it("renders the answer button on a user_input permission block", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "user_input"]]),
			onAnswer: vi.fn(),
		});

		expect(screen.getByTestId("block-answer")).toBeInTheDocument();
	});

	it("hides the answer button when permissionKind is not user_input", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "approval"]]),
			onAnswer: vi.fn(),
		});

		expect(screen.queryByTestId("block-answer")).not.toBeInTheDocument();
	});

	it("hides approve/deny when onApprove and onDecline are not provided (capability absent)", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "approval"]]),
		});

		expect(screen.queryByTestId("block-approve")).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-decline")).not.toBeInTheDocument();
	});

	it("hides the answer button when onAnswer is not provided (capability absent)", () => {
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "user_input"]]),
		});

		expect(screen.queryByTestId("block-answer")).not.toBeInTheDocument();
	});

	it("calls onApprove with the request id and the approve decision when clicked", () => {
		const onApprove = vi.fn();
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "approval"]]),
			onApprove,
		});

		fireEvent.click(screen.getByTestId("block-approve"));
		expect(onApprove).toHaveBeenCalledWith("req-1", "approve");
	});

	it("calls onDecline with the decline decision when clicked", () => {
		const onDecline = vi.fn();
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "approval"]]),
			onDecline,
		});

		fireEvent.click(screen.getByTestId("block-decline"));
		expect(onDecline).toHaveBeenCalledWith("req-1", "decline");
	});

	it("calls onAnswer with the request id when clicked", () => {
		const onAnswer = vi.fn();
		renderList({
			blocks: [permission("req-1")],
			permissionKinds: new Map([["req-1", "user_input"]]),
			onAnswer,
		});

		fireEvent.click(screen.getByTestId("block-answer"));
		expect(onAnswer).toHaveBeenCalledWith("req-1");
	});

	it("does not render action buttons when the permission block is not blocked", () => {
		renderList({
			blocks: [permission("req-1", "ok")],
			permissionKinds: new Map([["req-1", "approval"]]),
			onApprove: vi.fn(),
			onDecline: vi.fn(),
			onAnswer: vi.fn(),
		});

		expect(screen.queryByTestId("block-approve")).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-decline")).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-answer")).not.toBeInTheDocument();
	});
});

describe("BlockList rollback gating", () => {
	it("renders a rollback button when canRollbackTurn returns true", () => {
		renderList({
			blocks: [prompt("p-1", "t-1"), assistant("a-1", "t-1")],
			canRollbackTurn: () => true,
			onRollbackTurn: vi.fn(),
		});

		expect(screen.getAllByTestId("turn-rollback").length).toBeGreaterThan(0);
	});

	it("does not render a rollback button when canRollbackTurn returns false", () => {
		renderList({
			blocks: [prompt("p-1", "t-1"), assistant("a-1", "t-1")],
			canRollbackTurn: () => false,
			onRollbackTurn: vi.fn(),
		});

		expect(screen.queryByTestId("turn-rollback")).not.toBeInTheDocument();
	});

	it("does not render a rollback button when onRollbackTurn is not provided", () => {
		renderList({
			blocks: [prompt("p-1", "t-1"), assistant("a-1", "t-1")],
			canRollbackTurn: () => true,
		});

		expect(screen.queryByTestId("turn-rollback")).not.toBeInTheDocument();
	});

	it("calls onRollbackTurn with the turn id when the rollback button is clicked", () => {
		const onRollbackTurn = vi.fn();
		renderList({
			blocks: [prompt("p-1", "t-1"), assistant("a-1", "t-1")],
			canRollbackTurn: () => true,
			onRollbackTurn,
		});

		const buttons = screen.getAllByTestId("turn-rollback");
		fireEvent.click(buttons[0]!);
		expect(onRollbackTurn).toHaveBeenCalledWith("t-1");
	});
});
