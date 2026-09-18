import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useUiStore } from "../stores/ui-store";
import type { SessionActivityState, WorkspaceSession, WorkspaceSummary } from "../types/workspace";
import { ShellTopbar } from "./ShellTopbar";

const { navigateMock, paramsMock, postMock, spawnMock, useClaudeAccountsMock, useWorkspaceQueryMock } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	paramsMock: { projectId: undefined as string | undefined, sessionId: undefined as string | undefined },
	postMock: vi.fn(),
	spawnMock: vi.fn(),
	useClaudeAccountsMock: vi.fn(),
	useWorkspaceQueryMock: vi.fn(),
}));

vi.mock("@tanstack/react-router", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-router")>();
	return {
		...actual,
		useNavigate: () => navigateMock,
		useParams: () => paramsMock,
	};
});

vi.mock("../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => useWorkspaceQueryMock(),
	workspaceQueryKey: ["workspaces"],
}));

vi.mock("../lib/api-client", () => ({
	apiClient: {
		POST: postMock,
	},
	apiErrorMessage: (error: unknown, fallback = "Request failed") => {
		if (error instanceof Error) return error.message;
		if (typeof error === "object" && error !== null && "message" in error) {
			return String((error as { message: unknown }).message);
		}
		return fallback;
	},
}));

vi.mock("../lib/spawn-orchestrator", () => ({ spawnOrchestrator: spawnMock }));
vi.mock("../lib/telemetry", () => ({
	addRendererExceptionStep: vi.fn(),
	captureRendererEvent: vi.fn(),
	captureRendererException: vi.fn(),
}));
vi.mock("../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => useClaudeAccountsMock() };
});
vi.mock("./NewTaskDialog", () => ({ NewTaskDialog: () => null }));
vi.mock("./NotificationCenter", () => ({ NotificationCenter: () => null }));

const worker: WorkspaceSession = {
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
};

const secondWorker: WorkspaceSession = {
	...worker,
	id: "sess-2",
	title: "do the other thing",
	branch: "opr/sess-2",
};

const orchestrator: WorkspaceSession = {
	id: "orch-1",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "orchestrator",
	provider: "claude-code",
	kind: "orchestrator",
	branch: "main",
	status: "working",
	updatedAt: "2026-06-10T00:00:00Z",
	prs: [],
};

function sessionWith(overrides: Partial<WorkspaceSession> = {}): WorkspaceSession {
	return {
		...worker,
		activity: { state: "active", lastActivityAt: "2026-06-10T00:00:00Z" },
		...overrides,
	};
}

function renderTopbar(session: WorkspaceSession, embedded = false) {
	return renderTopbarSessions([session], session.id, embedded);
}

function renderTopbarSessions(sessions: WorkspaceSession[], sessionId: string, embedded = false) {
	const data: WorkspaceSummary[] = [
		{
			id: sessions[0].workspaceId,
			name: sessions[0].workspaceName,
			path: "/repo/my-app",
			orchestratorAgent: "claude-code",
			sessions,
		},
	];
	useWorkspaceQueryMock.mockReturnValue({ data, isError: false, isLoading: false });
	paramsMock.projectId = sessions[0].workspaceId;
	paramsMock.sessionId = sessionId;
	const queryClient = new QueryClient();
	const topbar = () => (
		<QueryClientProvider client={queryClient}>
			<ShellTopbar embedded={embedded} />
		</QueryClientProvider>
	);
	const result = render(topbar());
	return { ...result, queryClient, rerenderTopbar: () => result.rerender(topbar()) };
}

beforeEach(() => {
	navigateMock.mockReset();
	paramsMock.projectId = undefined;
	paramsMock.sessionId = undefined;
	postMock.mockReset();
	postMock.mockResolvedValue({ data: { ok: true, sessionId: "sess-1" }, error: undefined });
	useWorkspaceQueryMock.mockReset();
	useWorkspaceQueryMock.mockReturnValue({ data: [], isError: false, isLoading: false });
	useClaudeAccountsMock.mockReset();
	useClaudeAccountsMock.mockReturnValue({ data: [], isError: false, isLoading: false });
	useUiStore.setState({ inspectorSessions: {}, settingsModal: null });
});

describe("ShellTopbar status pill", () => {
	it("renders only session actions when embedded in the terminal bar", () => {
		useUiStore.setState({ inspectorSessions: { "sess-1": { isOpen: true, view: "summary" } } });
		renderTopbar(sessionWith(), true);

		expect(screen.queryByText("opr/sess-1")).not.toBeInTheDocument();
		expect(screen.queryByText("Working")).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Kill session" })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Open orchestrator" })).not.toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Close inspector panel" })).toBeInTheDocument();
	});

	it.each([
		["active", "Working"],
		["idle", "Idle"],
		["waiting_input", "Input Needed"],
		["exited", "Exited"],
	] as const)("renders %s activity as %s", (state: SessionActivityState, label) => {
		renderTopbar(sessionWith({ activity: { state, lastActivityAt: "2026-06-10T00:00:00Z" } }));

		expect(screen.getByText(label)).toBeInTheDocument();
	});

	it.each([
		["ci_failed", "idle", "Idle", "CI failed"],
		["mergeable", "active", "Working", "Ready"],
		["merged", "exited", "Exited", "Done"],
		["changes_requested", "waiting_input", "Input Needed", "Needs input"],
	] as const)("ignores derived %s topbar status in favor of activity", (status, state, label, hidden) => {
		renderTopbar(
			sessionWith({
				status,
				activity: { state, lastActivityAt: "2026-06-10T00:00:00Z" },
			}),
		);

		expect(screen.getByText(label)).toBeInTheDocument();
		expect(screen.queryByText(hidden)).not.toBeInTheDocument();
	});

	it("uses a compact unknown state when activity is missing or unknown", () => {
		const first = renderTopbar(sessionWith({ activity: undefined }));
		expect(screen.getByText("Unknown")).toBeInTheDocument();

		first.unmount();
		renderTopbar(sessionWith({ activity: { state: "unknown", lastActivityAt: "" } }));
		expect(screen.getByText("Unknown")).toBeInTheDocument();
	});

	it("does not synthesize branch text for branchless sessions", () => {
		renderTopbar(sessionWith({ branch: undefined }));

		expect(screen.queryByText("session/sess-1")).not.toBeInTheDocument();
		expect(screen.getByText("Working")).toBeInTheDocument();
	});

	it("shows the planning ticket badge beside the branch", async () => {
		renderTopbar(sessionWith({ ticket: { slug: "search-page", role: "planning" } }));

		const badge = screen.getByRole("button", { name: "Open ticket search-page · plan" });
		expect(badge).toHaveTextContent("search-page · plan");
		await userEvent.click(badge);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "proj-1", slug: "search-page" },
			search: { file: undefined },
		});
	});
});

describe("ShellTopbar orchestrator actions", () => {
	it.each([
		["active", "Working", "bg-status-working", true],
		["waiting_input", "Input Needed", "bg-status-needs-you", false],
	] as const)("shows %s orchestrator activity on the project board", (state, label, tone, pulses) => {
		renderTopbarSessions(
			[
				{
					...orchestrator,
					activity: { state, lastActivityAt: "2026-06-10T00:00:00Z" },
				},
			],
			"",
		);

		const button = screen.getByRole("button", { name: `Orchestrator, ${label}` });
		const indicator = button.querySelector("span.size-dot-sm") as HTMLElement;
		expect(indicator).toHaveAttribute("aria-hidden", "true");
		expect(indicator).toHaveClass(tone);
		expect(indicator).toHaveClass(pulses ? "animate-status-pulse" : "size-dot-sm");
		if (!pulses) expect(indicator).not.toHaveClass("animate-status-pulse");
	});

	it("renders no project name or New task action on the embedded orchestrator topbar", () => {
		renderTopbar(orchestrator, true);

		expect(screen.queryByText("Kanban")).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Open Kanban" })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "New task" })).not.toBeInTheDocument();
	});

	it("opens the board from the project-name crumb on the full orchestrator topbar", async () => {
		renderTopbar(orchestrator);

		expect(screen.queryByRole("button", { name: "New task" })).not.toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Open Kanban" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId",
			params: { projectId: "proj-1" },
		});
	});

	it("opens project settings instead of spawning when no orchestrator agent is configured", async () => {
		useWorkspaceQueryMock.mockReturnValue({
			data: [
				{
					id: "proj-1",
					name: "my-app",
					path: "/repo/my-app",
					sessions: [worker],
				},
			],
			isError: false,
			isLoading: false,
		});
		paramsMock.projectId = "proj-1";
		paramsMock.sessionId = undefined;
		render(
			<QueryClientProvider client={new QueryClient()}>
				<ShellTopbar />
			</QueryClientProvider>,
		);

		await userEvent.click(screen.getByRole("button", { name: "Spawn Orchestrator" }));

		expect(useUiStore.getState().settingsModal).toEqual({ scope: "project", projectId: "proj-1" });
		expect(navigateMock).not.toHaveBeenCalled();
		expect(spawnMock).not.toHaveBeenCalled();
	});
});

describe("ShellTopbar inspector state", () => {
	it("treats missing worker inspector state as closed", async () => {
		renderTopbarSessions([worker], "sess-1");

		const toggle = screen.getByRole("button", { name: "Open inspector panel" });
		expect(toggle).toHaveAttribute("aria-pressed", "false");

		await userEvent.click(toggle);

		expect(useUiStore.getState().inspectorSessions["sess-1"]).toEqual({ isOpen: true, view: "summary" });
	});

	it("routes aria-pressed to the current worker session", () => {
		useUiStore.setState({
			inspectorSessions: {
				"sess-1": { isOpen: true, view: "summary" },
				"sess-2": { isOpen: false, view: "summary" },
			},
		});
		const view = renderTopbarSessions([worker, secondWorker], "sess-1");

		expect(screen.getByRole("button", { name: "Close inspector panel" })).toHaveAttribute("aria-pressed", "true");

		paramsMock.sessionId = "sess-2";
		view.rerenderTopbar();

		expect(screen.getByRole("button", { name: "Open inspector panel" })).toHaveAttribute("aria-pressed", "false");
	});

	it("toggles only the current worker session", async () => {
		useUiStore.setState({
			inspectorSessions: {
				"sess-1": { isOpen: false, view: "summary" },
				"sess-2": { isOpen: true, view: "files" },
			},
		});
		renderTopbarSessions([worker, secondWorker], "sess-1");

		await userEvent.click(screen.getByRole("button", { name: "Open inspector panel" }));

		expect(useUiStore.getState().inspectorSessions["sess-1"]?.isOpen).toBe(true);
		expect(useUiStore.getState().inspectorSessions["sess-2"]).toEqual({ isOpen: true, view: "files" });
	});
});

describe("ShellTopbar Claude account", () => {
	const accounts = [
		{ id: "default", label: "Work", configDir: "/a", isDefault: true, isPreferred: false, sharedSetup: null, status: { loggedIn: true } },
		{ id: "personal", label: "Personal Pro", configDir: "/b", isDefault: false, isPreferred: false, sharedSetup: null, status: { loggedIn: true } },
	];

	it("names the session's Claude account before the inspector toggle", () => {
		useClaudeAccountsMock.mockReturnValue({ data: accounts, isError: false, isLoading: false });
		renderTopbar(sessionWith({ claudeAccountId: "personal" }));
		const chip = screen.getByText("Personal Pro");
		const toggle = screen.getByRole("button", { name: /inspector panel/ });
		expect(chip.compareDocumentPosition(toggle) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
	});

	it("shows the default account when the session names none", () => {
		useClaudeAccountsMock.mockReturnValue({ data: accounts, isError: false, isLoading: false });
		renderTopbar(sessionWith());
		expect(screen.getByText("Work")).toBeInTheDocument();
	});

	it("shows nothing for non-Claude sessions", () => {
		useClaudeAccountsMock.mockReturnValue({ data: accounts, isError: false, isLoading: false });
		renderTopbar(sessionWith({ provider: "codex", claudeAccountId: "personal" }));
		expect(screen.queryByText("Personal Pro")).not.toBeInTheDocument();
		expect(screen.queryByText("Work")).not.toBeInTheDocument();
	});
});

describe("ShellTopbar Claude account menu", () => {
	const accounts = [
		{ id: "default", label: "Work", configDir: "/a", isDefault: true, isPreferred: false, sharedSetup: null, status: { loggedIn: true } },
		{ id: "personal", label: "Personal Pro", configDir: "/b", isDefault: false, isPreferred: false, sharedSetup: null, status: { loggedIn: true } },
	];

	it("opens the account list from the chip and relaunches on the chosen account after confirming", async () => {
		useClaudeAccountsMock.mockReturnValue({ data: accounts, isError: false, isLoading: false });
		postMock.mockResolvedValue({ data: {}, error: undefined, response: { status: 200 } });
		renderTopbar(sessionWith({ claudeAccountId: "personal" }));
		await userEvent.click(screen.getByRole("button", { name: "Claude account: Personal Pro" }));
		expect(await screen.findByRole("menuitem", { name: "Personal Pro" })).toHaveAttribute("data-disabled");
		await userEvent.click(screen.getByRole("menuitem", { name: "Work" }));
		expect(postMock).not.toHaveBeenCalled();
		expect(screen.getByText("Switch to Work?")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Relaunch" }));
		await waitFor(() =>
			expect(postMock).toHaveBeenCalledWith("/api/v1/sessions/{sessionId}/relaunch-agent", {
				params: { path: { sessionId: "sess-1" } },
				body: { keepPrompt: false, claudeAccountId: "default" },
			}),
		);
	});

	it("keeps the chip inert for a terminated session", async () => {
		useClaudeAccountsMock.mockReturnValue({ data: accounts, isError: false, isLoading: false });
		renderTopbar(sessionWith({ claudeAccountId: "personal", isTerminated: true }));
		expect(screen.getByRole("button", { name: "Claude account: Personal Pro" })).toBeDisabled();
	});
});
