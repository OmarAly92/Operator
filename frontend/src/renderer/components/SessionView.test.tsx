import { StrictMode, type ReactNode, type Ref } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render as rtlRender, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi, type Mock } from "vitest";
import { SessionView } from "./SessionView";
import { useUiStore } from "../stores/ui-store";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";

const navigateMock = vi.hoisted(() => vi.fn());
const nativeFullScreenMock = vi.hoisted(() => vi.fn(() => false));
const interfaceTransitionMock = vi.hoisted(() => ({
	start: vi.fn(),
	resetStartError: vi.fn(),
	cancel: vi.fn(),
}));
const interfaceTransitionState = vi.hoisted(() => ({
	status: undefined as
		| { supported: boolean; targetMode?: "chat" | "tui"; reason?: string }
		| undefined,
}));
const reviewGetMock = vi.hoisted(() => vi.fn());

vi.mock("@tanstack/react-router", () => ({
	useNavigate: () => navigateMock,
}));

vi.mock("../lib/platform", () => ({
	// Exercise the macOS shell layout without changing the existing Ctrl-based
	// shortcut assertions in this suite.
	hidesShellTopbar: () => true,
	isMacPlatform: () => false,
}));
vi.mock("../hooks/useWindowFullScreen", () => ({
	useWindowFullScreen: () => nativeFullScreenMock(),
}));
vi.mock("../hooks/useSessionInterfaceTransition", () => ({
	interfaceTransitionIsActive: () => false,
	useSessionInterfaceTransition: () => ({
		status: interfaceTransitionState.status,
		transition: undefined,
		isLoading: false,
		statusError: undefined,
		start: interfaceTransitionMock.start,
		starting: false,
		startError: undefined,
		resetStartError: interfaceTransitionMock.resetStartError,
		cancel: interfaceTransitionMock.cancel,
		cancelling: false,
		cancelError: undefined,
	}),
}));

vi.mock("../lib/api-client", () => ({
	apiClient: {
		GET: reviewGetMock,
	},
	apiErrorMessage: (_error: unknown, fallback: string) => fallback,
}));

type FakePanelHandle = {
	collapse: Mock;
	expand: Mock;
	getSize: Mock;
	isCollapsed: Mock;
	resize: Mock;
};

type PanelEntry = {
	handle: FakePanelHandle;
	onResize?: (size: { asPercentage: number; inPixels: number }) => void;
};

const { workspaces, workspaceQueryState, panels } = vi.hoisted(() => {
	const worker = {
		id: "sess-1",
		workspaceId: "proj-1",
		workspaceName: "my-app",
		title: "do the thing",
		provider: "claude-code",
		kind: "worker",
		branch: "opr/sess-1",
		status: "working",
		updatedAt: "2026-06-10T00:00:00Z",
		prs: [],
	} satisfies WorkspaceSession;
	const secondWorker = {
		...worker,
		id: "sess-2",
		title: "do the other thing",
		branch: "opr/sess-2",
	} satisfies WorkspaceSession;
	const orchestrator = {
		...worker,
		id: "sess-orch",
		kind: "orchestrator",
		title: "orchestrate",
	} satisfies WorkspaceSession;
	const crossProjectWorker = {
		...worker,
		id: "sess-cross-project",
		workspaceId: "proj-2",
		workspaceName: "other-app",
		title: "cross-project task",
		branch: "opr/cross-project",
	} satisfies WorkspaceSession;
	const workspaces: WorkspaceSummary[] = [
		{ id: "proj-1", name: "my-app", path: "/p", type: "main", sessions: [worker, secondWorker, orchestrator] },
		{ id: "proj-2", name: "other-app", path: "/q", type: "main", sessions: [crossProjectWorker] },
	];
	const workspaceQueryState: { data: WorkspaceSummary[] | undefined; isLoading: boolean } = {
		data: workspaces,
		isLoading: false,
	};
	return { workspaces, workspaceQueryState, panels: new Map<string, PanelEntry>() };
});

// The terminal and inspector body pull in xterm/SSE machinery irrelevant to
// the split under test. (ShellTopbar is shell-owned on Win/Linux; when the
// platform hides the shell topbar, SessionView mounts it in-panel.)
vi.mock("./ShellTopbar", () => ({ ShellTopbar: () => null }));
vi.mock("./CenterPane", () => ({
	SessionBlocksPane: ({ headerActions }: { headerActions?: ReactNode }) => (
		<div data-testid="blocks-pane">
			blocks pane
			{headerActions}
		</div>
	),
	CenterPane: ({
		session,
		onSelectSessionTerminal,
		onSelectReviewerTerminal,
		topbarActions,
		reviewerTerminal,
		terminalTarget,
	}: {
		session?: WorkspaceSession;
		onSelectSessionTerminal?: () => void;
		onSelectReviewerTerminal?: (target: { handleId: string; harness: string }) => void;
		topbarActions?: ReactNode;
		reviewerTerminal?: { handleId: string; harness: string };
		terminalTarget?: { kind: string; handleId?: string };
	}) => (
		<div data-testid="terminal-pane">
			terminal center
			{topbarActions}
			<div data-testid="terminal-target">
				{terminalTarget?.kind === "shell" ? terminalTarget.handleId : (terminalTarget?.kind ?? "worker")}
			</div>
			<div data-testid="session-tab">{session?.title ?? ""}</div>
			<div data-testid="reviewer-harness">{reviewerTerminal?.harness ?? ""}</div>
			{reviewerTerminal ? (
				<button type="button" onClick={() => onSelectReviewerTerminal?.(reviewerTerminal)}>
					select reviewer tab
				</button>
			) : null}
			<button type="button" onClick={() => onSelectSessionTerminal?.()}>
				select agent tab
			</button>
		</div>
	),
}));
const { externalPreviewOptions, externalPreviewState } = vi.hoisted(() => ({
	externalPreviewOptions: {
		current: undefined as
			| {
					sessionId?: string;
					previewUrl?: string;
					previewRevision?: number;
					previewOpenedRevision?: number;
					terminated?: boolean;
			  }
			| undefined,
	},
	externalPreviewState: { error: "" },
}));
vi.mock("../hooks/useExternalPreview", () => ({
	useExternalPreview: (options: {
		sessionId?: string;
		previewUrl?: string;
		previewRevision?: number;
		previewOpenedRevision?: number;
		terminated?: boolean;
	}) => {
		externalPreviewOptions.current = options;
		return {
			error: externalPreviewState.error,
			retry: vi.fn(),
			reopen: vi.fn(async () => undefined),
		};
	},
}));
vi.mock("./SessionFilesView", () => ({
	SessionFilesView: ({
		isMaximized,
		onToggleMaximized,
	}: {
		isMaximized?: boolean;
		onToggleMaximized?: (next: boolean) => void;
	}) => (
		<button type="button" onClick={() => onToggleMaximized?.(!isMaximized)}>
			{isMaximized ? "files center" : "files rail"}
		</button>
	),
}));
vi.mock("./SessionInspector", () => ({
	SessionInspector: ({
		filesView,
		onOpenFiles,
		view,
	}: {
		filesView?: ReactNode;
		onOpenFiles?: () => void;
		view?: string;
	}) => (
		<div>
			<div data-view={view}>inspector view</div>
			<button type="button" onClick={onOpenFiles}>
				open files
			</button>
			{view === "files" ? filesView : null}
		</div>
	),
}));
vi.mock("../lib/shell-context", () => ({
	useShell: () => ({ daemonStatus: { state: "ready" } }),
}));
vi.mock("../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => ({
		data: workspaceQueryState.data,
		isLoading: workspaceQueryState.isLoading,
	}),
}));
vi.mock("../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [
			{
				handleId: "shell-in-session",
				sessionId: "sess-1",
				workingDir: "/tmp",
				title: "shell",
				createdAt: new Date().toISOString(),
				durableBlocks: true,
			},
		],
		isSuccess: true,
	}),
	useOpenShellTerminal: () => ({ mutate: vi.fn() }),
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
	shellTerminalsQueryKey: ["shell-terminals"],
}));

// jsdom has no layout engine, so the real react-resizable-panels would never
// produce meaningful sizes — record the props SessionView passes and expose a
// fake imperative handle per panel instead.
vi.mock("./ui/resizable", () => ({
	ResizablePanelGroup: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
	ResizableHandle: ({ elementRef }: { elementRef?: Ref<HTMLDivElement | null> }) => (
		<div
			data-separator="inactive"
			data-testid="resize-handle"
			ref={(el) => {
				if (elementRef && typeof elementRef === "object") {
					(elementRef as { current: HTMLDivElement | null }).current = el;
				}
			}}
		/>
	),
	ResizablePanel: ({
		children,
		id,
		defaultSize,
		minSize,
		maxSize,
		collapsible,
		panelRef,
		onResize,
		style: _style,
		...rest
	}: {
		children?: ReactNode;
		id: string;
		defaultSize?: number | string;
		minSize?: number | string;
		maxSize?: number | string;
		collapsible?: boolean;
		panelRef?: Ref<FakePanelHandle | null>;
		onResize?: (size: { asPercentage: number; inPixels: number }) => void;
		style?: React.CSSProperties;
	}) => {
		let entry = panels.get(id);
		if (!entry) {
			entry = {
				handle: {
					collapse: vi.fn(),
					expand: vi.fn(),
					getSize: vi.fn(() => ({ asPercentage: 28, inPixels: 280 })),
					isCollapsed: vi.fn(() => false),
					resize: vi.fn(),
				},
			};
			panels.set(id, entry);
		}
		entry.onResize = onResize;
		if (panelRef && typeof panelRef === "object") {
			(panelRef as { current: FakePanelHandle | null }).current = entry.handle;
		}
		return (
			<div data-testid={`panel-${id}`} data-collapsible={collapsible ? "true" : undefined} {...rest}>
				<span data-testid={`panel-${id}-sizes`}>
					{JSON.stringify([defaultSize, minSize, maxSize].filter((s) => s !== undefined))}
				</span>
				{children}
			</div>
		);
	},
}));

function panelSizes(id: string): unknown[] {
	return JSON.parse(screen.getByTestId(`panel-${id}-sizes`).textContent ?? "[]") as unknown[];
}

function workerSession(sessionId: string): WorkspaceSession {
	const session = workspaces[0].sessions.find((item) => item.id === sessionId);
	if (!session) throw new Error(`missing test session ${sessionId}`);
	return session;
}

function inspectorOpen(sessionId: string): boolean {
	return useUiStore.getState().inspectorSessions[sessionId]?.isOpen ?? true;
}

function inspectorViewMarker(): HTMLElement | null {
	return document.querySelector<HTMLElement>("[data-view]");
}

function render(ui: ReactNode) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return {
		...rtlRender(ui, {
			wrapper: ({ children }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
		}),
		client,
	};
}

describe("SessionView", () => {
	beforeEach(() => {
		nativeFullScreenMock.mockReturnValue(false);
		window.localStorage.clear();
		for (const session of workspaces.flatMap((workspace) => workspace.sessions)) {
			delete session.previewUrl;
			delete session.previewRevision;
			delete session.previewOpenedRevision;
			delete session.isTerminated;
			session.status = "working";
			delete session.mode;
			session.prs = [];
		}
		workspaceQueryState.data = workspaces;
		workspaceQueryState.isLoading = false;
		useUiStore.setState({
			activeShellTerminalHandleId: null,
			inspectorSessions: {},
			visibleTerminalKindBySession: {},
		});
		panels.clear();
		externalPreviewOptions.current = undefined;
		externalPreviewState.error = "";
	navigateMock.mockReset();
	interfaceTransitionMock.start.mockReset();
		interfaceTransitionMock.resetStartError.mockReset();
		interfaceTransitionMock.cancel.mockReset();
		interfaceTransitionState.status = undefined;
		reviewGetMock.mockReset();
		reviewGetMock.mockResolvedValue({ data: { reviewerHandleId: "", reviews: [], runs: [] }, error: undefined });
	});

	it("renders no shell tab for a session-scoped shell", async () => {
		render(<SessionView sessionId="sess-1" />);
		expect(await screen.findByTestId("terminal-pane")).toBeInTheDocument();
		expect(screen.queryByRole("tab", { name: /shell/i })).not.toBeInTheDocument();
	});

	// The strip only ever shows the session on screen — pinning another session's
	// terminal as a tab (and the cross-project picker that did it) is gone (#3208).
	it("shows only the session on screen in the tab strip", () => {
		render(<SessionView sessionId="sess-1" />);

		expect(screen.getByTestId("session-tab")).toHaveTextContent("do the thing");
		expect(screen.getByTestId("session-tab")).not.toHaveTextContent("do the other thing");
		expect(screen.queryByRole("button", { name: /^Add / })).not.toBeInTheDocument();
	});

	it.each([
		["Terminal UI worker", "sess-1", "tui", "chat", "Switch to chat UI"],
		["Terminal UI orchestrator", "sess-orch", "tui", "chat", "Switch to chat UI"],
		["Chat worker", "sess-1", "chat", "tui", "Switch to terminal UI"],
		["Chat orchestrator", "sess-orch", "chat", "tui", "Switch to terminal UI"],
	] as const)("switches an idle %s directly with drain", (_label, sessionId, mode, targetMode, buttonName) => {
		interfaceTransitionState.status = { supported: true, targetMode };
		const session = workerSession(sessionId);
		session.mode = mode;
		session.status = "idle";
		session.activity = { state: "idle", lastActivityAt: "2026-08-06T00:00:00Z" };

		render(<SessionView sessionId={sessionId} />);

		fireEvent.click(screen.getByRole("button", { name: buttonName }));

		expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
		expect(interfaceTransitionMock.start).toHaveBeenCalledWith({ targetMode, policy: "drain" });
	});

	it("keeps the policy dialog closed when an idle direct switch fails", async () => {
		interfaceTransitionState.status = { supported: true, targetMode: "chat" };
		const session = workerSession("sess-1");
		session.status = "idle";
		session.activity = { state: "idle", lastActivityAt: "2026-08-06T00:00:00Z" };
		interfaceTransitionMock.start.mockRejectedValueOnce(new Error("switch failed"));

		render(<SessionView sessionId="sess-1" />);

		await act(async () => {
			fireEvent.click(screen.getByRole("button", { name: "Switch to chat UI" }));
		});

		expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
	});

	it.each([
		["working status", "sess-1", "tui", "chat", "Switch to chat UI", "working", "idle"],
		["needs-input status", "sess-orch", "tui", "chat", "Switch to chat UI", "needs_input", "idle"],
		["active activity", "sess-1", "chat", "tui", "Switch to terminal UI", "idle", "active"],
		["waiting-input activity", "sess-orch", "chat", "tui", "Switch to terminal UI", "idle", "waiting_input"],
		["blocked activity", "sess-1", "tui", "chat", "Switch to chat UI", "idle", "blocked"],
	] as const)("opens the switch policy dialog for %s", (_label, sessionId, mode, targetMode, buttonName, status, activityState) => {
		interfaceTransitionState.status = { supported: true, targetMode };
		const session = workerSession(sessionId);
		session.mode = mode;
		session.status = status;
		session.activity = { state: activityState, lastActivityAt: "2026-08-06T00:00:00Z" };

		render(<SessionView sessionId={sessionId} />);

		fireEvent.click(screen.getByRole("button", { name: buttonName }));

		expect(screen.getByRole("dialog")).toBeInTheDocument();
		expect(interfaceTransitionMock.start).not.toHaveBeenCalled();
	});

	it("checks only the selected session when deciding whether to show the policy dialog", () => {
		interfaceTransitionState.status = { supported: true, targetMode: "chat" };
		const selected = workerSession("sess-1");
		selected.status = "idle";
		selected.activity = { state: "idle", lastActivityAt: "2026-08-06T00:00:00Z" };
		const other = workerSession("sess-2");
		other.status = "working";
		other.activity = { state: "active", lastActivityAt: "2026-08-06T00:00:00Z" };

		render(<SessionView sessionId="sess-1" />);

		fireEvent.click(screen.getByRole("button", { name: "Switch to chat UI" }));

		expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
		expect(interfaceTransitionMock.start).toHaveBeenCalledWith({ targetMode: "chat", policy: "drain" });
	});

	it("uses the stored reviewer harness for the reviewer tab icon when no latest run is current", async () => {
		const worker = workerSession("sess-1");
		worker.prs = [
			{
				url: "https://github.com/acme/repo/pull/7",
				number: 7,
				state: "open",
				ci: "passing",
				review: "none",
				mergeability: "mergeable",
				reviewComments: false,
				updatedAt: "2026-06-15T00:00:00Z",
			},
		];
		reviewGetMock.mockResolvedValueOnce({
			data: { reviewerHandleId: "review-sess-1", reviewerHarness: "codex", reviews: [], runs: [] },
			error: undefined,
		});

		render(<SessionView sessionId="sess-1" />);

		await waitFor(() => expect(screen.getByTestId("reviewer-harness")).toHaveTextContent("codex"));
	});

	it("returns to the session terminal when the reviewer handle is cleared", async () => {
		const worker = workerSession("sess-1");
		worker.prs = [
			{
				url: "https://github.com/acme/repo/pull/7",
				number: 7,
				state: "open",
				ci: "passing",
				review: "none",
				mergeability: "mergeable",
				reviewComments: false,
				updatedAt: "2026-06-15T00:00:00Z",
			},
		];
		reviewGetMock.mockResolvedValueOnce({
			data: { reviewerHandleId: "review-sess-1", reviewerHarness: "codex", reviews: [] },
			error: undefined,
		});

		const view = render(<SessionView sessionId="sess-1" />);
		await screen.findByRole("button", { name: "select reviewer tab" });
		fireEvent.click(screen.getByRole("button", { name: "select reviewer tab" }));
		expect(screen.getByTestId("terminal-target")).toHaveTextContent("reviewer");

		act(() => {
			view.client.setQueryData(["session-reviews", "sess-1"], { reviewerHandleId: "", reviews: [] });
		});

		await waitFor(() => expect(screen.getByTestId("terminal-target")).toHaveTextContent("worker"));
		expect(screen.queryByRole("button", { name: "select reviewer tab" })).not.toBeInTheDocument();
	});

	it("restores the selected reviewer terminal when the session becomes active again", async () => {
		const worker = workerSession("sess-1");
		worker.prs = [
			{
				url: "https://github.com/acme/repo/pull/7",
				number: 7,
				state: "open",
				ci: "passing",
				review: "none",
				mergeability: "mergeable",
				reviewComments: false,
				updatedAt: "2026-06-15T00:00:00Z",
			},
		];
		reviewGetMock.mockResolvedValueOnce({
			data: { reviewerHandleId: "review-sess-1", reviewerHarness: "codex", reviews: [] },
			error: undefined,
		});

		const view = render(<SessionView sessionId="sess-1" />);
		await screen.findByRole("button", { name: "select reviewer tab" });
		fireEvent.click(screen.getByRole("button", { name: "select reviewer tab" }));
		expect(screen.getByTestId("terminal-target")).toHaveTextContent("reviewer");

		worker.status = "terminated";
		worker.isTerminated = true;
		view.rerender(<SessionView sessionId="sess-1" />);
		expect(screen.getByTestId("terminal-target")).toHaveTextContent("reviewer");
		expect(screen.queryByRole("button", { name: "select reviewer tab" })).not.toBeInTheDocument();

		worker.status = "working";
		worker.isTerminated = false;
		view.rerender(<SessionView sessionId="sess-1" />);

		await screen.findByRole("button", { name: "select reviewer tab" });
		expect(screen.getByTestId("terminal-target")).toHaveTextContent("reviewer");
	});

	// Regression: react-resizable-panels v4 treats bare numeric sizes as PIXELS
	// (numbers were percentages in the older API the shadcn examples use).
	// defaultSize={28}/maxSize={45} clamped the inspector rail to a 45px sliver.
	// Every size must be an explicit percentage string.
	it("sizes the terminal/inspector split in percentages, not pixels", () => {
		render(<SessionView sessionId="sess-1" />);

		for (const panelId of ["terminal", "inspector"]) {
			const sizes = panelSizes(panelId);
			expect(sizes.length).toBeGreaterThan(0);
			for (const size of sizes) {
				expect(size, `${panelId} size ${String(size)} must be a percentage string`).toMatch(/^\d+(\.\d+)?%$/);
			}
		}
	});

	it("opens the Summary inspector alongside the terminal by default", () => {
		render(<SessionView sessionId="sess-1" />);

		expect(screen.getByText("terminal center")).toBeInTheDocument();
		expect(panelSizes("inspector")[0]).toBe("30%");
		// Open panels are non-collapsible so a drag clamps at minSize instead of
		// snapping the rail away; only the closed panel is collapsible.
		expect(screen.getByTestId("panel-inspector")).not.toHaveAttribute("data-collapsible");
		expect(screen.getByTestId("resize-handle")).toBeInTheDocument();
		expect(screen.getByTestId("panel-inspector")).not.toHaveAttribute("inert");
		expect(inspectorViewMarker()).toHaveAttribute("data-view", "summary");
	});

	it("keeps every embedded browser surface absent from the session view", () => {
		const worker = workerSession("sess-1");
		worker.previewUrl = "http://localhost:5173/";
		worker.previewRevision = 1;
		render(<SessionView sessionId="sess-1" />);

		expect(screen.queryByTestId("browser-panel")).not.toBeInTheDocument();
		expect(screen.queryByTestId("browser-toolbar")).not.toBeInTheDocument();
		expect(screen.queryByTestId("browser-viewport")).not.toBeInTheDocument();
		expect(document.querySelector(".browser-popout-overlay")).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /pop browser|browser center/i })).not.toBeInTheDocument();
		expect(screen.queryByRole("tablist", { name: /browser/i })).not.toBeInTheDocument();
	});

	it("feeds the session's preview facts into external preview handling", () => {
		const worker = workerSession("sess-1");
		worker.previewUrl = "http://localhost:5173/";
		worker.previewRevision = 4;
		worker.previewOpenedRevision = 3;

		render(<SessionView sessionId="sess-1" />);

		expect(externalPreviewOptions.current).toMatchObject({
			sessionId: "sess-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 4,
			previewOpenedRevision: 3,
			terminated: false,
		});
	});

	it("treats a merged terminated session as terminated for external preview", () => {
		const worker = workerSession("sess-1");
		worker.status = "merged";
		worker.isTerminated = true;

		render(<SessionView sessionId="sess-1" />);

		expect(externalPreviewOptions.current).toMatchObject({ sessionId: "sess-1", terminated: true });
	});

	it("mounts the inspector open by default", () => {
		render(<SessionView sessionId="sess-1" />);

		expect(panelSizes("inspector")[0]).toMatch(/^[1-9]\d*(\.\d+)?%$/);
		const pane = screen.getByTestId("panel-inspector");
		expect(pane).not.toHaveAttribute("inert");
		expect(pane).toHaveAttribute("aria-hidden", "false");
		expect(panels.get("inspector")!.handle.expand).not.toHaveBeenCalled();
	});

	it("mounts collapsed and inert when the store says closed", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", false));
		render(<SessionView sessionId="sess-1" />);

		expect(panelSizes("inspector")[0]).toBe("0%");
		const pane = screen.getByTestId("panel-inspector");
		expect(pane).toHaveAttribute("inert");
		expect(pane).toHaveAttribute("aria-hidden", "true");
		// Collapsed panels stay collapsible so the 0% size is a valid rrp state
		// (and the separator can drag the rail back open).
		expect(pane).toHaveAttribute("data-collapsible", "true");
		expect(panels.get("inspector")!.handle.collapse).not.toHaveBeenCalled();
	});

	it("keeps StrictMode mount imperative-free and collapses on the first user toggle", () => {
		render(
			<StrictMode>
				<SessionView sessionId="sess-1" />
			</StrictMode>,
		);
		const handle = panels.get("inspector")!.handle;

		expect(handle.expand).not.toHaveBeenCalled();
		expect(handle.collapse).not.toHaveBeenCalled();

		fireEvent.keyDown(window, { key: "B", ctrlKey: true, shiftKey: true });

		expect(inspectorOpen("sess-1")).toBe(false);
		expect(handle.collapse).toHaveBeenCalledTimes(1);
		expect(handle.expand).not.toHaveBeenCalled();
	});

	it("keeps StrictMode mount imperative-free and expands on the first user toggle", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", false));
		render(
			<StrictMode>
				<SessionView sessionId="sess-1" />
			</StrictMode>,
		);
		const handle = panels.get("inspector")!.handle;

		expect(handle.resize).not.toHaveBeenCalled();
		expect(handle.collapse).not.toHaveBeenCalled();

		fireEvent.keyDown(window, { key: "B", ctrlKey: true, shiftKey: true });

		expect(inspectorOpen("sess-1")).toBe(true);
		// Opening resizes to the persisted split rather than expand(): the open
		// panel re-registers as non-collapsible, and rrp's expand() no-ops on a
		// non-collapsible panel.
		expect(handle.resize).toHaveBeenCalledWith("30%");
		expect(handle.collapse).not.toHaveBeenCalled();
	});

	it("toggles the inspector with mod+shift+B through the imperative panel API", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);
		const handle = panels.get("inspector")!.handle;

		fireEvent.keyDown(window, { key: "B", ctrlKey: true, shiftKey: true });
		expect(inspectorOpen("sess-1")).toBe(false);
		expect(handle.collapse).toHaveBeenCalledTimes(1);

		fireEvent.keyDown(window, { key: "B", ctrlKey: true, shiftKey: true });
		expect(inspectorOpen("sess-1")).toBe(true);
		expect(handle.resize).toHaveBeenCalledWith("30%");

		// Plain ⌘B belongs to the sidebar — the inspector must not react.
		fireEvent.keyDown(window, { key: "b", metaKey: true });
		expect(inspectorOpen("sess-1")).toBe(true);
	});

	it("persists drag resizes and never closes the store from a drag", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);
		const entry = panels.get("inspector")!;
		// rrp marks the separator active for the duration of a pointer drag.
		screen.getByTestId("resize-handle").setAttribute("data-separator", "active");

		// Dragging persists the width.
		act(() => entry.onResize?.({ asPercentage: 31.5, inPixels: 400 }));
		expect(inspectorOpen("sess-1")).toBe(true);
		expect(window.localStorage.getItem("opr.inspector.split")).toBe("31.5");

		// A drag can never auto-collapse the rail: even if a 0-size frame arrives
		// mid-drag, the store stays open — collapse belongs to the explicit
		// controls (topbar button / ⌘⇧B) only.
		act(() => entry.onResize?.({ asPercentage: 0, inPixels: 0 }));
		expect(inspectorOpen("sess-1")).toBe(true);
		expect(window.localStorage.getItem("opr.inspector.split")).toBe("31.5");
	});

	it("reopens the store when a drag pulls the collapsed rail back open", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", false));
		render(<SessionView sessionId="sess-1" />);
		const entry = panels.get("inspector")!;
		screen.getByTestId("resize-handle").setAttribute("data-separator", "active");

		act(() => entry.onResize?.({ asPercentage: 25, inPixels: 320 }));

		expect(useUiStore.getState().inspectorSessions["sess-1"]).toMatchObject({ isOpen: true });
		expect(window.localStorage.getItem("opr.inspector.split")).toBe("25");
	});

	// Regression: rrp v4 reports observed DOM sizes, so the flex-grow
	// transition animating an imperative collapse fires onResize with transient
	// non-zero sizes. Mirroring those into the store re-opened the panel
	// mid-animation — the topbar toggle looked dead and a mount-time 0-size
	// event flipped a fresh profile to collapsed. Only drag events (separator
	// active) may write back.
	it("ignores onResize churn while the separator is not being dragged", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);
		const entry = panels.get("inspector")!;

		// Mount-time/layout event at 0% must not collapse the store…
		act(() => entry.onResize?.({ asPercentage: 0, inPixels: 0 }));
		expect(inspectorOpen("sess-1")).toBe(true);

		// …and a mid-collapse transition frame must not re-open or persist.
		act(() => useUiStore.getState().toggleInspector("sess-1"));
		act(() => entry.onResize?.({ asPercentage: 12.4, inPixels: 160 }));
		expect(inspectorOpen("sess-1")).toBe(false);
		expect(window.localStorage.getItem("opr.inspector.split")).toBeNull();
	});

	it("restores the persisted split width", () => {
		window.localStorage.setItem("opr.inspector.split", "40");
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);
		expect(panelSizes("inspector")[0]).toBe("40%");
	});

	// Regression: rrp only derives a panel's constraints one commit after it
	// registers into a live group. Driving the imperative API in the commit
	// where the inspector mounts (orchestrator → worker navigation; SessionView
	// itself stays mounted) threw "Panel constraints not found for Panel
	// inspector" and unwound the route to the error boundary. The panel must
	// mount already in sync via defaultSize instead.
	it("mounts the inspector in sync when navigating from an orchestrator session, without the imperative API", () => {
		const { rerender } = render(<SessionView sessionId="sess-orch" />);
		expect(screen.queryByTestId("panel-inspector")).not.toBeInTheDocument();

		// Already-open worker state — the panel that mounts later must pick this
		// up from defaultSize alone.
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		rerender(<SessionView sessionId="sess-1" />);

		expect(panelSizes("inspector")[0]).toMatch(/^[1-9]\d*(\.\d+)?%$/);
		const handle = panels.get("inspector")!.handle;
		expect(handle.expand).not.toHaveBeenCalled();
		expect(handle.collapse).not.toHaveBeenCalled();
		expect(handle.resize).not.toHaveBeenCalled();
	});

	it("expands on the first toggle after a closed worker inspector remounts", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", false));
		const { rerender } = render(<SessionView sessionId="sess-1" />);
		const handle = panels.get("inspector")!.handle;

		act(() => useUiStore.getState().setInspectorOpen("sess-2", false));
		rerender(<SessionView sessionId="sess-orch" />);
		expect(screen.queryByTestId("panel-inspector")).not.toBeInTheDocument();

		act(() => useUiStore.getState().setInspectorOpen("sess-2", false));
		rerender(<SessionView sessionId="sess-2" />);
		expect(panelSizes("inspector")[0]).toBe("0%");
		expect(handle.collapse).not.toHaveBeenCalled();

		fireEvent.keyDown(window, { key: "B", ctrlKey: true, shiftKey: true });

		expect(inspectorOpen("sess-2")).toBe(true);
		expect(handle.resize).toHaveBeenCalledWith("30%");
	});

	it("renders no inspector panel or handle for orchestrator sessions", () => {
		render(<SessionView sessionId="sess-orch" />);

		expect(screen.queryByTestId("panel-inspector")).not.toBeInTheDocument();
		expect(screen.queryByTestId("resize-handle")).not.toBeInTheDocument();

		// The shortcut is inactive without an inspector.
		fireEvent.keyDown(window, { key: "B", metaKey: true, shiftKey: true });
		expect(useUiStore.getState().inspectorSessions["sess-orch"]).toBeUndefined();
	});

	it("opens the files view in the inspector rail first", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);

		fireEvent.click(screen.getByRole("button", { name: "open files" }));

		expect(
			within(screen.getByTestId("panel-inspector")).getByRole("button", { name: "files rail" }),
		).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "files center" })).not.toBeInTheDocument();
		expect(screen.getByText("terminal center")).toBeInTheDocument();
	});

	it("maximizes files over the whole app window and returns to the rail", () => {
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);

		fireEvent.click(screen.getByRole("button", { name: "open files" }));
		fireEvent.click(within(screen.getByTestId("panel-inspector")).getByRole("button", { name: "files rail" }));

		expect(screen.getByRole("button", { name: "files center" })).toBeInTheDocument();
		const overlay = document.querySelector(".files-popout-overlay");
		expect(overlay).toHaveClass("files-popout-overlay--mac-windowed");
		expect(overlay?.parentElement).toBe(document.body);
		expect(screen.getByText("terminal center")).toBeInTheDocument();

		fireEvent.click(screen.getByRole("button", { name: "files center" }));
		expect(screen.queryByRole("button", { name: "files center" })).not.toBeInTheDocument();
		expect(
			within(screen.getByTestId("panel-inspector")).getByRole("button", { name: "files rail" }),
		).toBeInTheDocument();
		expect(screen.getByText("terminal center")).toBeInTheDocument();
	});

	it("does not reserve the traffic-light band for maximized files during native macOS fullscreen", () => {
		nativeFullScreenMock.mockReturnValue(true);
		act(() => useUiStore.getState().setInspectorOpen("sess-1", true));
		render(<SessionView sessionId="sess-1" />);

		fireEvent.click(screen.getByRole("button", { name: "open files" }));
		fireEvent.click(within(screen.getByTestId("panel-inspector")).getByRole("button", { name: "files rail" }));

		expect(document.querySelector(".files-popout-overlay")).not.toHaveClass("files-popout-overlay--mac-windowed");
	});

	it("does not auto-open a terminated session's stale preview through the external opener", () => {
		const worker = workerSession("sess-1");
		worker.status = "merged";
		worker.isTerminated = true;
		worker.previewUrl = "http://localhost:5173/";
		worker.previewRevision = 1;

		render(<SessionView sessionId="sess-1" />);

		expect(externalPreviewOptions.current).toMatchObject({ sessionId: "sess-1", terminated: true });
	});
});

