import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
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

function renderView(props: Partial<Parameters<typeof BlocksView>[0]> = {}) {
	return render(
		<BlocksView
			blocks={[]}
			error={undefined}
			harness="claude-code"
			hasOlder={false}
			isLoading={false}
			isLoadingOlder={false}
			onLoadOlder={vi.fn()}
			onRetry={vi.fn()}
			supported
			{...props}
		/>,
	);
}

describe("BlocksView", () => {
	it("renders one card per block", () => {
		renderView({
			blocks: [
				block({ id: "seq-1", kind: "prompt", title: "Prompt", body: "run the tests" }),
				block({ id: "src-tu-1", title: "Bash", body: "ok 42 tests" }),
			],
		});

		expect(screen.getAllByTestId("session-block")).toHaveLength(2);
		expect(screen.getByText("run the tests")).toBeInTheDocument();
		expect(screen.getByText("ok 42 tests")).toBeInTheDocument();
	});

	it("localizes a generated title but passes a tool name through", () => {
		renderView({ blocks: [block({ kind: "prompt", title: "Prompt" }), block({ id: "seq-2", title: "Bash" })] });

		expect(screen.getByText("Prompt")).toBeInTheDocument();
		expect(screen.getByText("Bash")).toBeInTheDocument();
	});

	it("wraps a long body instead of clipping it to one line", () => {
		const long = Array.from({ length: 40 }, () => "wrapping").join(" ");
		renderView({ blocks: [block({ body: long })] });

		expect(screen.getByText(long)).toHaveClass("whitespace-pre-wrap");
	});

	it("says how much was dropped rather than dropping it silently", () => {
		renderView({ blocks: [block({ truncatedLines: 4212 })] });

		expect(screen.getByText(/4212/)).toBeInTheDocument();
		expect(screen.getByText(/truncated/i)).toBeInTheDocument();
	});

	it("marks a block that had secrets removed", () => {
		renderView({ blocks: [block({ redacted: true })] });

		expect(screen.getByText(/redacted/i)).toBeInTheDocument();
	});

	it("shows a permission request as blocked and names the tool", () => {
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

		expect(screen.getByText("Permission requested")).toBeInTheDocument();
		expect(screen.getByText(/git branch -D feat\/x/)).toBeInTheDocument();
	});

	it("shows a question as waiting on the user", () => {
		renderView({
			blocks: [block({ kind: "notice", status: "blocked", title: "Waiting on you", body: "Which branch?" })],
		});

		expect(screen.getByText("Waiting on you")).toBeInTheDocument();
	});

	it("marks a failed tool as failed", () => {
		renderView({ blocks: [block({ status: "failed", errorType: "tool_failed", body: "no such table" })] });

		expect(screen.getByTestId("block-status-dot")).toHaveAttribute("data-status", "failed");
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

		await userEvent.click(screen.getByRole("button", { name: /load older/i }));
		expect(onLoadOlder).toHaveBeenCalledTimes(1);

		rerender(
			<BlocksView
				blocks={[block()]}
				error={undefined}
				harness="claude-code"
				hasOlder={false}
				isLoading={false}
				isLoadingOlder={false}
				onLoadOlder={onLoadOlder}
				onRetry={vi.fn()}
				supported
			/>,
		);
		expect(screen.queryByRole("button", { name: /load older/i })).not.toBeInTheDocument();
	});

	it("shows progress instead of the control while paging back", () => {
		renderView({ blocks: [block()], hasOlder: true, isLoadingOlder: true });

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
});
