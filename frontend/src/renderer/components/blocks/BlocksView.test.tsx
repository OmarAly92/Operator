import { act, cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import type { BlockActionContext } from "../../lib/block-actions";
import { installVirtualLayout } from "../../test/virtual-layout";
import { BlocksView } from "./BlocksView";

function block(overrides: Partial<SessionBlock> = {}): SessionBlock {
	return {
		id: "seq-1",
		firstSeq: 1,
		lastSeq: 1,
		kind: "tool",
		status: "ok",
		title: "Bash",
		body: "ok",
		truncatedLines: 0,
		redacted: false,
		...overrides,
	};
}

let teardown: () => void;
let currentBlocks: SessionBlock[] = [];
const actionContext: BlockActionContext = {
	mode: "tui",
	capabilities: [],
	canSend: true,
	turnInFlight: false,
	rollbackableTurnIds: [],
};

beforeEach(() => {
	teardown = installVirtualLayout({ heights: () => currentBlocks.map(() => 80) });
});
afterEach(() => {
	teardown();
	cleanup();
});

function renderView(props: Partial<Parameters<typeof BlocksView>[0]> = {}) {
	currentBlocks = props.blocks ?? [];
	return render(
		<BlocksView
			blocks={[]}
			actionContext={actionContext}
			error={undefined}
			harness="claude-code"
			hasOlder={false}
			isLoading={false}
			isLoadingOlder={false}
			onLoadOlder={vi.fn()}
			onAction={vi.fn()}
			onRetry={vi.fn()}
			sessionId="s-1"
			supported
			{...props}
		/>,
	);
}

describe("BlocksView", () => {
	it("renders one card per block", async () => {
		renderView({
			blocks: [
				block({ id: "seq-1", kind: "prompt", title: "Prompt", body: "run the tests" }),
				block({ id: "src-tu-1", title: "Bash", body: "ok 42 tests" }),
			],
		});
		await act(async () => {});

		expect(screen.getAllByTestId("session-block")).toHaveLength(2);
		expect(screen.getByText("run the tests")).toBeInTheDocument();
		expect(screen.getByText("ok 42 tests")).toBeInTheDocument();
	});

	it("lets a user collapse and expand nested blocks with their standard actions", async () => {
		const nested = block({ id: "child-1", body: "nested output" });
		const parent = block({ id: "parent-1", body: "parent output", children: [nested] });
		renderView({ blocks: [parent] });
		await act(async () => {});

		expect(screen.getByText("nested output")).toBeInTheDocument();
		expect(screen.getAllByTestId("block-action-copy_block")).toHaveLength(2);

		await userEvent.click(screen.getAllByRole("button", { name: "Collapse" })[1]!);
		expect(screen.queryByText("nested output")).not.toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: "Expand" }));
		expect(screen.getByText("nested output")).toBeInTheDocument();
	});

	it("localizes a generated title but passes a tool name through", async () => {
		renderView({ blocks: [block({ kind: "prompt", title: "Prompt" }), block({ id: "seq-2", title: "Bash" })] });
		await act(async () => {});

		expect(screen.getAllByText("Prompt").length).toBeGreaterThan(0);
		expect(screen.getAllByText("Bash").length).toBeGreaterThan(0);
	});

	it("uses the detail display name for a tool header", async () => {
		renderView({
			blocks: [
				block({
					title: "Tool",
					detail: { type: "shell", command: "pwd", output: "/tmp", exitCode: 0 },
				}),
			],
		});
		await act(async () => {});

		expect(screen.getAllByText("Shell")).toHaveLength(2);
	});

	it("wraps a long body instead of clipping it to one line", async () => {
		const long = Array.from({ length: 40 }, () => "wrapping").join(" ");
		renderView({ blocks: [block({ body: long })] });
		await act(async () => {});

		expect(screen.getByText(long)).toHaveClass("whitespace-pre-wrap");
	});

	it("says how much was dropped rather than dropping it silently", async () => {
		renderView({ blocks: [block({ truncatedLines: 4212 })] });
		await act(async () => {});

		expect(screen.getByText(/4212/)).toBeInTheDocument();
		expect(screen.getByText(/truncated/i)).toBeInTheDocument();
	});

	it("marks a block that had secrets removed", async () => {
		renderView({ blocks: [block({ redacted: true })] });
		await act(async () => {});

		expect(screen.getByText(/redacted/i)).toBeInTheDocument();
	});

	it("shows a permission request as blocked and names the tool", async () => {
		renderView({
			blocks: [
				block({
					id: "src-pr-1",
					kind: "permission",
					status: "blocked",
					title: "Permission requested",
					body: "Bash\ngit branch -D feat/x",
				}),
			],
		});
		await act(async () => {});

		expect(screen.getAllByText("Permission requested").length).toBeGreaterThan(0);
		expect(screen.getByText(/git branch -D feat\/x/)).toBeInTheDocument();
	});

	it("shows a question as waiting on the user", async () => {
		renderView({
			blocks: [block({ kind: "notice", status: "blocked", title: "Waiting on you", body: "Which branch?" })],
		});
		await act(async () => {});

		expect(screen.getAllByText("Waiting on you").length).toBeGreaterThan(0);
	});

	it("marks a failed tool as failed", async () => {
		renderView({ blocks: [block({ status: "failed", errorType: "tool_failed", body: "no such table" })] });
		await act(async () => {});

		expect(screen.getAllByTestId("block-status-dot")[0]).toHaveAttribute("data-status", "failed");
	});

	it("says blocks are unavailable for an uncovered harness", () => {
		renderView({ supported: false, harness: "aider" });

		expect(screen.getByText(/aider/)).toBeInTheDocument();
		expect(screen.queryByTestId("session-block")).not.toBeInTheDocument();
	});

	it("says a covered but empty session is empty rather than showing nothing", () => {
		renderView();

		expect(screen.getByText(/No blocks yet/i)).toBeInTheDocument();
	});

	it("offers to load older blocks only when there are some", async () => {
		const onLoadOlder = vi.fn();
		const { rerender } = renderView({ blocks: [block()], hasOlder: true, onLoadOlder });
		await act(async () => {});

		await userEvent.click(screen.getByRole("button", { name: /load older/i }));
		expect(onLoadOlder).toHaveBeenCalledTimes(1);

		rerender(
			<BlocksView
				actionContext={actionContext}
				blocks={[block()]}
				error={undefined}
				harness="claude-code"
				hasOlder={false}
				isLoading={false}
				isLoadingOlder={false}
				onLoadOlder={onLoadOlder}
				onAction={vi.fn()}
				onRetry={vi.fn()}
				sessionId="s-1"
				supported
			/>,
		);
		expect(screen.queryByRole("button", { name: /load older/i })).not.toBeInTheDocument();
	});

	it("shows progress instead of the control while paging back", async () => {
		renderView({ blocks: [block()], hasOlder: true, isLoadingOlder: true });
		await act(async () => {});

		expect(screen.queryByRole("button", { name: /load older/i })).not.toBeInTheDocument();
		expect(screen.getByText(/loading older/i)).toBeInTheDocument();
	});

	it("surfaces a load failure and offers a retry", async () => {
		const onRetry = vi.fn();
		renderView({ error: "offline", onRetry });

		expect(screen.getByText(/offline/)).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: /retry/i }));
		expect(onRetry).toHaveBeenCalledTimes(1);
	});

	it("renders the unavailable reason as a non-error notice without a retry button", () => {
		renderView({
			unavailable: { code: "SESSION_MODE_MISMATCH", message: "This session is a terminal session." },
		});

		expect(screen.getByText(/This session is a terminal session\./)).toBeInTheDocument();
		expect(screen.getByText(/SESSION_MODE_MISMATCH/)).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /retry/i })).not.toBeInTheDocument();
		expect(screen.queryByTestId("session-block")).not.toBeInTheDocument();
	});
});
