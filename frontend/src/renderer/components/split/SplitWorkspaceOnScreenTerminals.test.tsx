import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { terminalShownInAPane } from "../../lib/on-screen-terminals";
import { EMPTY_LAYOUT } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import type { WorkspaceSession, WorkspaceSummary } from "../../types/workspace";
import { SplitWorkspace } from "./SplitWorkspace";

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => vi.fn() }));
vi.mock("../../lib/shell-context", () => ({ useShell: () => ({ daemonStatus: { state: "ready" } }) }));
vi.mock("../../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [{ handleId: "shell-x", sessionId: "x", workingDir: "/p1", title: "zsh", createdAt: "now" }],
		isSuccess: true,
	}),
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useOpenShellTerminal: () => ({ mutate: vi.fn(), isPending: false }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
}));
vi.mock("../../hooks/useSessionReviewer", () => ({
	useSessionReviewer: () => ({ reviewer: undefined, settled: true }),
}));
vi.mock("./SplitPane", () => ({ SplitPane: () => <div /> }));
vi.mock("../ui/resizable", () => ({
	ResizablePanelGroup: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizablePanel: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizableHandle: () => <div />,
}));
vi.mock("../../lib/bridge", () => ({
	operatorBridge: {
		app: {
			onCloseShellTerminalShortcut: () => () => undefined,
			setCloseShellTerminalShortcutEnabled: () => undefined,
			onPreviousTabShortcut: () => () => undefined,
			onNextTabShortcut: () => () => undefined,
		},
	},
}));

function makeSession(id: string): WorkspaceSession {
	return {
		id,
		terminalHandleId: `handle-${id}`,
		workspaceId: "proj-1",
		workspaceName: "proj-1",
		title: `session:${id}`,
		provider: "claude-code",
		branch: `opr/${id}`,
		status: "working",
		updatedAt: "2026-06-10T00:00:00Z",
		prs: [],
	};
}

const workspaces: WorkspaceSummary[] = [
	{ id: "proj-1", name: "proj-1", path: "/p1", sessions: [makeSession("x"), makeSession("y")] },
];

vi.mock("../../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => ({ data: workspaces, isSuccess: true }),
}));

describe("SplitWorkspace on-screen terminals", () => {
	beforeEach(() => {
		useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT, dismissedReviewers: [] });
		window.localStorage.clear();
	});

	it("claims the terminal of every pane's active tab, not a background tab, and releases them on unmount", () => {
		useSplitLayoutStore.getState().openTab({ kind: "session", sessionId: "x" });
		const paneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane({ kind: "shell", handleId: "shell-x", sessionId: "x" }, paneId, "right");
		useSplitLayoutStore.getState().insertTabAfter({ kind: "session", sessionId: "y" }, { kind: "shell", handleId: "shell-x", sessionId: "x" });

		const { unmount } = render(
			<QueryClientProvider client={new QueryClient()}>
				<SplitWorkspace routeSessionId="x" />
			</QueryClientProvider>,
		);

		expect(terminalShownInAPane("handle-x")).toBe(true);
		expect(terminalShownInAPane("shell-x")).toBe(true);
		expect(terminalShownInAPane("handle-y")).toBe(false);
		unmount();
		expect(terminalShownInAPane("handle-x")).toBe(false);
		expect(terminalShownInAPane("shell-x")).toBe(false);
	});
});
