import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { operatorBridge } from "../../lib/bridge";
import { listPanes, tabKey, type Split, type TabRef } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { EMPTY_LAYOUT } from "../../lib/split-layout";
import type { WorkspaceSession, WorkspaceSummary } from "../../types/workspace";
import { SplitWorkspace } from "./SplitWorkspace";

const navigateMock = vi.hoisted(() => vi.fn());

vi.mock("@tanstack/react-router", () => ({
	useNavigate: () => navigateMock,
}));

vi.mock("../../lib/shell-context", () => ({
	useShell: () => ({ daemonStatus: { state: "ready" } }),
}));

function makeSession(id: string, workspaceId: string): WorkspaceSession {
	return {
		id,
		workspaceId,
		workspaceName: workspaceId,
		title: `session:${id}`,
		provider: "claude-code",
		branch: `opr/${id}`,
		status: "working",
		updatedAt: "2026-06-10T00:00:00Z",
		prs: [],
	} as unknown as WorkspaceSession;
}

const workspaces: WorkspaceSummary[] = [
	{
		id: "proj-1",
		name: "proj-1",
		path: "/p1",
		type: "main",
		sessions: [makeSession("a", "proj-1"), makeSession("b", "proj-1")],
	} as unknown as WorkspaceSummary,
	{
		id: "proj-2",
		name: "proj-2",
		path: "/p2",
		type: "main",
		sessions: [makeSession("c", "proj-2")],
	} as unknown as WorkspaceSummary,
];

vi.mock("../../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => ({ data: workspaces, isSuccess: true }),
}));

const { shellsState, reviewerState } = vi.hoisted(() => ({
	shellsState: { value: [] as { handleId: string; sessionId?: string; workingDir: string; title: string; createdAt: string }[] },
	reviewerState: { value: undefined as { handleId: string; harness: string } | undefined },
}));

const closeShell = vi.hoisted(() => vi.fn());

vi.mock("../../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({ data: shellsState.value, isSuccess: true }),
	useCloseShellTerminal: () => ({ mutate: closeShell }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
}));

vi.mock("../../hooks/useSessionReviewer", () => ({
	useSessionReviewer: () => reviewerState.value,
}));

vi.mock("./SplitPane", () => ({
	SplitPane: ({
		pane,
		focused,
		onFocus,
		onSelect,
		onClose,
		onClosePane,
	}: {
		pane: { id: string; tabs: TabRef[]; activeTab: number };
		focused: boolean;
		onFocus: () => void;
		onSelect: (tab: TabRef) => void;
		onClose: (tab: TabRef) => void;
		onClosePane: () => void;
	}) => (
		<div data-focused={focused} data-testid={`pane-${pane.id}`}>
			{pane.tabs.map((tab) => (
				<div key={tabKey(tab)}>
					<span>{tabKey(tab)}</span>
					<button aria-label={`select ${tabKey(tab)}`} onClick={() => onSelect(tab)} type="button" />
					<button aria-label={`close ${tabKey(tab)}`} onClick={() => onClose(tab)} type="button" />
				</div>
			))}
			<button onClick={onFocus} type="button">
				focus
			</button>
			<button onClick={onClosePane} type="button">
				close pane
			</button>
		</div>
	),
}));

const layoutChanged = vi.hoisted(() => ({ value: undefined as ((sizes: Record<string, number>) => void) | undefined }));

vi.mock("../ui/resizable", () => ({
	ResizablePanelGroup: ({
		children,
		onLayoutChanged,
	}: {
		children?: React.ReactNode;
		onLayoutChanged?: (sizes: Record<string, number>) => void;
	}) => {
		layoutChanged.value = onLayoutChanged;
		return <div>{children}</div>;
	},
	ResizablePanel: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizableHandle: () => <div />,
}));

function s(sessionId: string): TabRef {
	return { kind: "session", sessionId };
}

function paneContaining(text: string): HTMLElement {
	const panes = screen.getAllByTestId(/^pane-/);
	const found = panes.find((pane) => within(pane).queryByText(text));
	if (!found) throw new Error(`no pane contains ${text}`);
	return found;
}

function activeKey(): string {
	const layout = useSplitLayoutStore.getState().layout;
	const focused = listPanes(layout.root).find((candidate) => candidate.id === layout.focusedPaneId);
	if (!focused) throw new Error("no focused pane");
	return tabKey(focused.tabs[focused.activeTab]);
}

function captureShortcut(name: "onCloseShellTerminalShortcut" | "onNextTabShortcut" | "onPreviousTabShortcut"): () => void {
	let captured: () => void = () => undefined;
	vi.spyOn(operatorBridge.app, name).mockImplementation((listener: () => void) => {
		captured = listener;
		return () => undefined;
	});
	return () => captured();
}

describe("SplitWorkspace", () => {
	beforeEach(() => {
		useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT });
		window.localStorage.clear();
		navigateMock.mockReset();
		closeShell.mockReset();
		shellsState.value = [];
		reviewerState.value = undefined;
		vi.spyOn(operatorBridge.app, "setCloseShellTerminalShortcutEnabled").mockImplementation(() => undefined);
	});

	it("opens the routed session and renders one pane", () => {
		render(<SplitWorkspace routeSessionId="a" />);
		expect(screen.getAllByTestId(/^pane-/)).toHaveLength(1);
		expect(screen.getByText("session:a")).toBeInTheDocument();
	});

	it("renders every pane of a split and navigates when another pane is focused", () => {
		useSplitLayoutStore.getState().openTab(s("a"));
		useSplitLayoutStore.getState().openTab(s("c"));
		const paneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane(s("c"), paneId, "right");
		useSplitLayoutStore.getState().focusTab(s("a"));
		render(<SplitWorkspace routeSessionId="a" />);
		expect(screen.getAllByTestId(/^pane-/)).toHaveLength(2);
		fireEvent.click(within(paneContaining("session:c")).getByRole("button", { name: "focus" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "proj-2", sessionId: "c" },
		});
	});

	it("does not bounce the route back to a restored focus on mount", () => {
		useSplitLayoutStore.getState().openTab(s("b"));
		render(<SplitWorkspace routeSessionId="a" />);
		expect(navigateMock).not.toHaveBeenCalled();
		expect(useSplitLayoutStore.getState().layout.focusedPaneId).not.toBeNull();
		expect(screen.getByText(/session:a/)).toBeInTheDocument();
	});

	it("closes the focused tab with Cmd+W, a shell by closing the shell, and leaves for the kanban when empty", () => {
		shellsState.value = [{ handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "t" }];
		const fire = captureShortcut("onCloseShellTerminalShortcut");
		render(<SplitWorkspace routeSessionId="a" />);
		useSplitLayoutStore.getState().focusTab({ kind: "shell", handleId: "h1", sessionId: "a" });
		act(() => fire());
		expect(closeShell).toHaveBeenCalledWith("h1");
		act(() => fire());
		expect(useSplitLayoutStore.getState().layout.root).toBeNull();
		expect(navigateMock).toHaveBeenLastCalledWith({ to: "/projects/$projectId", params: { projectId: "proj-1" }, replace: true });
	});

	it("cycles tabs of the focused pane with the tab shortcuts", () => {
		const next = captureShortcut("onNextTabShortcut");
		useSplitLayoutStore.getState().openTab(s("b"));
		render(<SplitWorkspace routeSessionId="a" />);
		act(() => next());
		expect(activeKey()).toBe("session:b");
	});

	it("adopts a session's shells and reviewer beside it", () => {
		shellsState.value = [{ handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "t" }];
		reviewerState.value = { handleId: "r1", harness: "codex" };
		render(<SplitWorkspace routeSessionId="a" />);
		expect(listPanes(useSplitLayoutStore.getState().layout.root)[0].tabs.map(tabKey)).toEqual([
			"session:a",
			"shell:h1",
			"reviewer:r1",
		]);
	});

	it("prunes tabs whose session disappeared", () => {
		useSplitLayoutStore.getState().openTab(s("gone"));
		render(<SplitWorkspace routeSessionId="a" />);
		expect(listPanes(useSplitLayoutStore.getState().layout.root).flatMap((pane) => pane.tabs.map(tabKey))).toEqual(["session:a"]);
	});

	it("writes divider moves back to the layout", () => {
		useSplitLayoutStore.getState().openTab(s("a"));
		useSplitLayoutStore.getState().openTab(s("b"));
		useSplitLayoutStore.getState().splitPane(s("b"), useSplitLayoutStore.getState().layout.focusedPaneId as string, "right");
		render(<SplitWorkspace routeSessionId="a" />);
		const split = useSplitLayoutStore.getState().layout.root as Split;
		act(() => layoutChanged.value?.({ [split.children[0].id]: 30, [split.children[1].id]: 70 }));
		expect((useSplitLayoutStore.getState().layout.root as Split).sizes).toEqual([30, 70]);
	});
});
