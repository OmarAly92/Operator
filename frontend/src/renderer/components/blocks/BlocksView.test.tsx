import { act, cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import type { BlockActionContext } from "../../lib/block-actions";
import { blocksToText } from "../../lib/block-actions";
import { operatorBridge } from "../../lib/bridge";
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
	vi.restoreAllMocks();
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

async function enterSelection(user: ReturnType<typeof userEvent.setup>) {
	const pane = screen.getByRole("log");
	pane.focus();
	await user.keyboard("{Control>}f{/Control}");
	await user.click(screen.getByRole("button", { name: "Select" }));
}

function selectionHeader(body: string) {
	const row = screen.getByText(body).closest("[data-block-id]") as HTMLElement | null;
	if (row === null) throw new Error(`Block row not found for ${body}`);
	return within(row).getByRole("button", { name: "Select" });
}

describe("BlocksView", () => {
	it("selects a contiguous range when shift-clicking block headers", async () => {
		const user = userEvent.setup();
		renderView({
			blocks: [
				block({ id: "seq-1", body: "first selected block" }),
				block({ id: "seq-2", body: "middle selected block" }),
				block({ id: "seq-3", body: "last selected block" }),
			],
		});
		await act(async () => {});

		await enterSelection(user);
		await user.click(selectionHeader("first selected block"));
		await user.keyboard("{Shift>}");
		await user.click(selectionHeader("last selected block"));
		await user.keyboard("{/Shift}");

		expect(screen.getByText("3 selected")).toBeInTheDocument();
		expect(screen.getAllByTestId("session-block-selected")).toHaveLength(3);
	});

	it("copies selected blocks in document order and leaves selection mode", async () => {
		const user = userEvent.setup();
		const blocks = [
			block({ id: "seq-1", body: "first copied block" }),
			block({ id: "seq-2", body: "middle copied block" }),
			block({ id: "seq-3", body: "last copied block" }),
		];
		let clipboardText = "";
		vi.spyOn(operatorBridge.clipboard, "writeText").mockImplementation(async (text) => {
			clipboardText = text;
		});
		vi.spyOn(operatorBridge.clipboard, "readText").mockImplementation(async () => clipboardText);
		renderView({ blocks });
		await act(async () => {});

		await enterSelection(user);
		await user.click(selectionHeader("last copied block"));
		await user.click(selectionHeader("first copied block"));
		await user.click(screen.getByRole("button", { name: "Copy" }));

		await waitFor(() => expect(operatorBridge.clipboard.writeText).toHaveBeenCalledWith(blocksToText([blocks[0]!, blocks[2]!])));
		expect(await operatorBridge.clipboard.readText()).toBe(blocksToText([blocks[0]!, blocks[2]! ]));
		expect(screen.queryByRole("button", { name: "Copy" })).not.toBeInTheDocument();
		expect(screen.queryByTestId("session-block-selected")).not.toBeInTheDocument();
	});

	it("clears block selection when cancelled or escaped", async () => {
		const user = userEvent.setup();
		renderView({ blocks: [block({ body: "selected block" })] });
		await act(async () => {});

		await enterSelection(user);
		await user.click(selectionHeader("selected block"));
		await user.click(screen.getByRole("button", { name: "Cancel" }));
		expect(screen.queryByTestId("session-block-selected")).not.toBeInTheDocument();

		await user.click(screen.getByRole("button", { name: "Select" }));
		await user.click(selectionHeader("selected block"));
		await user.keyboard("{Escape}");
		expect(screen.queryByTestId("session-block-selected")).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Copy" })).not.toBeInTheDocument();
	});

	it("clears block selection when the session changes", async () => {
		const user = userEvent.setup();
		const { rerender } = renderView({ blocks: [block({ body: "selected block" })] });
		await act(async () => {});

		await enterSelection(user);
		await user.click(selectionHeader("selected block"));
		expect(screen.getByTestId("session-block-selected")).toBeInTheDocument();

		rerender(
			<BlocksView
				actionContext={actionContext}
				blocks={[block({ id: "seq-2", body: "new session block" })]}
				error={undefined}
				harness="claude-code"
				hasOlder={false}
				isLoading={false}
				isLoadingOlder={false}
				onAction={vi.fn()}
				onLoadOlder={vi.fn()}
				onRetry={vi.fn()}
				sessionId="s-2"
				supported
			/>,
		);

		expect(screen.queryByTestId("session-block-selected")).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Copy" })).not.toBeInTheDocument();
	});
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

	it("finds blocks from the focused pane, navigates matches, filters, and clears on Escape", async () => {
		const user = userEvent.setup();
		renderView({
			blocks: [
				block({ id: "seq-1", title: "Build", body: "first deploy target" }),
				block({ id: "seq-2", title: "Test", body: "context before hidden block" }),
				block({ id: "seq-3", title: "Review", body: "no match here" }),
				block({ id: "seq-4", title: "Test", body: "context after hidden block" }),
				block({ id: "seq-5", title: "Deploy", body: "second deploy target" }),
			],
		});
		await act(async () => {});

		const pane = screen.getByRole("log");
		pane.focus();
		await user.keyboard("{Meta>}f{/Meta}");

		const input = screen.getByRole("textbox", { name: "Find in blocks" });
		await user.type(input, "deploy");
		expect(screen.getByText("1 / 2")).toBeInTheDocument();
		expect(screen.getAllByTestId("block-match-active")).toHaveLength(1);
		expect(screen.getAllByTestId("block-match-active")[0]).toHaveTextContent("deploy");

		await user.click(screen.getByRole("button", { name: "Next match" }));
		expect(screen.getByText("2 / 2")).toBeInTheDocument();
		expect(screen.getAllByTestId("block-match-active")[0]).toHaveTextContent("Deploy");
		await user.click(screen.getByRole("button", { name: "Next match" }));
		expect(screen.getByText("1 / 2")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Previous match" }));
		expect(screen.getByText("2 / 2")).toBeInTheDocument();

		await user.click(screen.getByRole("button", { name: "Filter results" }));
		expect(screen.getByText("1 block hidden")).toBeInTheDocument();
		expect(screen.queryByText("no match here")).not.toBeInTheDocument();

		await user.keyboard("{Escape}");
		expect(screen.queryByRole("textbox", { name: "Find in blocks" })).not.toBeInTheDocument();
		expect(screen.getByText("no match here")).toBeInTheDocument();
	});

	it("keeps the list visible when filtering has no block matches", async () => {
		const user = userEvent.setup();
		renderView({
			blocks: [
				block({ id: "seq-1", body: "first block" }),
				block({ id: "seq-2", body: "second block" }),
			],
		});
		await act(async () => {});

		const pane = screen.getByRole("log");
		pane.focus();
		await user.keyboard("{Control>}f{/Control}");
		await user.type(screen.getByRole("textbox", { name: "Find in blocks" }), "absent");
		await user.click(screen.getByRole("button", { name: "Filter results" }));

		expect(screen.getByText("No matches")).toBeInTheDocument();
		expect(screen.getByText("first block")).toBeInTheDocument();
		expect(screen.getByText("second block")).toBeInTheDocument();
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
