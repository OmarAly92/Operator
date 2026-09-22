import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactNode } from "react";

// Drives the real useWorkspaceQuery + SessionsBoard end to end for the two
// first-run states, mocking only the HTTP client, the router, and the native
// folder picker: an empty daemon shows the import chooser (no column shells), a
// fresh project shows the task invitation, and any session brings the columns back.
const { getMock, navigateMock, chooseDirectoryMock } = vi.hoisted(() => ({
	getMock: vi.fn(),
	navigateMock: vi.fn(),
	chooseDirectoryMock: vi.fn(),
}));

vi.mock("../../lib/api-client", () => ({
	apiClient: { GET: getMock, POST: vi.fn() },
	apiErrorMessage: (e: unknown) => (e instanceof Error ? e.message : "error"),
	hasTrustedApiBaseUrl: () => true,
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { app: { chooseDirectory: chooseDirectoryMock } },
}));

vi.mock("@tanstack/react-router", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-router")>();
	return { ...actual, useNavigate: () => navigateMock };
});

import { SessionsBoard } from "../../components/SessionsBoard";
import { ShellProvider, type ShellContextValue } from "../../lib/shell-context";
import { useUiStore } from "../../stores/ui-store";

type Project = { id: string; name: string; path: string };
type Session = Record<string, unknown>;

function respondWith(projects: Project[], sessions: Session[]) {
	getMock.mockImplementation(async (url: string) => {
		if (url === "/api/v1/projects") return { data: { projects }, error: undefined };
		if (url === "/api/v1/sessions") return { data: { sessions }, error: undefined };
		return { data: undefined, error: undefined };
	});
}

const project: Project = {
	id: "proj-1",
	name: "my-app",
	path: "/repo/my-app",
};

const workerSession: Session = {
	id: "sess-1",
	projectId: "proj-1",
	displayName: "fix the bug",
	harness: "claude-code",
	status: "working",
	isTerminated: false,
	updatedAt: "2026-07-04T10:00:00Z",
	prs: [],
};

const createProjectMock = vi.fn().mockResolvedValue(undefined);
const initializeProjectRepositoryMock = vi.fn().mockResolvedValue(undefined);

// Kept from the latest renderBoard call so tests can rerender with the same
// providers (e.g. simulating a projectId route-param change on a mounted board).
let lastQueryClient: QueryClient | null = null;
let lastShell: ShellContextValue | null = null;

function renderBoard(ui: ReactNode) {
	lastQueryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	lastShell = {
		daemonStatus: { state: "ready" } as ShellContextValue["daemonStatus"],
		workspaceStartupState: "ready",
		createProject: createProjectMock,
		initializeProjectRepository: initializeProjectRepositoryMock,
	};
	return render(
		<QueryClientProvider client={lastQueryClient}>
			<ShellProvider value={lastShell}>{ui}</ShellProvider>
		</QueryClientProvider>,
	);
}

// The kanban columns render as <section> elements; the empty states render none.
const columnCount = () => document.querySelectorAll("section").length;

beforeEach(() => {
	vi.clearAllMocks();
	createProjectMock.mockResolvedValue(undefined);
	initializeProjectRepositoryMock.mockResolvedValue(undefined);
	useUiStore.setState({
		settingsModal: null,
	});
});

describe("global board first launch", () => {
	it("shows the startup loader instead of import while the daemon is booting", async () => {
		respondWith([], []);
		lastQueryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		lastShell = {
			daemonStatus: { state: "starting" } as ShellContextValue["daemonStatus"],
			workspaceStartupState: "loading",
			createProject: createProjectMock,
			initializeProjectRepository: initializeProjectRepositoryMock,
		};
		render(
			<QueryClientProvider client={lastQueryClient}>
				<ShellProvider value={lastShell}>
					<SessionsBoard />
				</ShellProvider>
			</QueryClientProvider>,
		);

		expect(await screen.findByTestId("daemon-startup-loader")).toHaveClass("opr-startup-screen");
		expect(screen.getByRole("status", { name: "Operator is starting" })).toBeInTheDocument();
		expect(screen.getByText("Operator")).toBeInTheDocument();
		expect(screen.getByText("Starting local services")).toHaveAttribute("aria-hidden", "true");
		expect(screen.queryByText("Import to Operator")).not.toBeInTheDocument();
		expect(columnCount()).toBe(0);
	});

	it("shows the import chooser instead of empty columns when no projects exist", async () => {
		respondWith([], []);
		renderBoard(<SessionsBoard />);

		expect(await screen.findByText("Import to Operator")).toBeInTheDocument();
		expect(screen.getByText("What are you importing?")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Workspace" })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Project" })).toBeInTheDocument();
		expect(columnCount()).toBe(0);
		// The welcome carries its own orientation — no dangling "Board" header.
		expect(screen.queryByText("Board")).not.toBeInTheDocument();
	});

	it("opens the native folder picker from the Project card", async () => {
		respondWith([], []);
		chooseDirectoryMock.mockResolvedValue(null);
		renderBoard(<SessionsBoard />);

		await userEvent.click(await screen.findByRole("button", { name: "Project" }));
		expect(chooseDirectoryMock).toHaveBeenCalledTimes(1);
		expect(chooseDirectoryMock).toHaveBeenCalledWith("Choose a project repository");
	});

	it("opens the native folder picker from the Workspace card", async () => {
		respondWith([], []);
		chooseDirectoryMock.mockResolvedValue(null);
		renderBoard(<SessionsBoard />);

		await userEvent.click(await screen.findByRole("button", { name: "Workspace" }));
		expect(chooseDirectoryMock).toHaveBeenCalledTimes(1);
		expect(chooseDirectoryMock).toHaveBeenCalledWith("Choose a workspace folder");
	});

	it("shows a visible error when the folder picker fails", async () => {
		respondWith([], []);
		chooseDirectoryMock.mockRejectedValue(new Error("dialog unavailable"));
		renderBoard(<SessionsBoard />);

		await userEvent.click(await screen.findByRole("button", { name: "Project" }));
		const messages = await screen.findAllByText("dialog unavailable");
		expect(messages.some((el) => !el.classList.contains("sr-only"))).toBe(true);
	});

	it("keeps the columns once a project exists", async () => {
		respondWith([project], [workerSession]);
		renderBoard(<SessionsBoard />);

		expect(await screen.findByText("fix the bug")).toBeInTheDocument();
		expect(screen.queryByText("Import to Operator")).not.toBeInTheDocument();
		expect(columnCount()).toBe(5);
	});

	it("keeps populated columns visible after the daemon reports a startup failure", async () => {
		respondWith([project], [workerSession]);
		lastQueryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		lastShell = {
			daemonStatus: { state: "stopped", code: "exited" } as ShellContextValue["daemonStatus"],
			workspaceStartupState: "loading",
			createProject: createProjectMock,
			initializeProjectRepository: initializeProjectRepositoryMock,
		};
		render(
			<QueryClientProvider client={lastQueryClient}>
				<ShellProvider value={lastShell}>
					<SessionsBoard />
				</ShellProvider>
			</QueryClientProvider>,
		);

		expect(await screen.findByText("fix the bug")).toBeInTheDocument();
		expect(screen.queryByTestId("daemon-startup-loader")).not.toBeInTheDocument();
		expect(columnCount()).toBe(5);
	});
});

describe("project board with no sessions", () => {
	it("shows the task invitation instead of empty columns", async () => {
		respondWith([project], []);
		renderBoard(<SessionsBoard projectId="proj-1" />);

		expect(await screen.findByText("No worker sessions yet")).toBeInTheDocument();
		expect(screen.getAllByRole("button", { name: "New task" }).length).toBeGreaterThan(0);
		expect(screen.queryByText("Import to Operator")).not.toBeInTheDocument();
		expect(columnCount()).toBe(0);
	});

	it("keeps the columns once the project has a session", async () => {
		respondWith([project], [workerSession]);
		renderBoard(<SessionsBoard projectId="proj-1" />);

		expect(await screen.findByText("fix the bug")).toBeInTheDocument();
		expect(screen.queryByText("No worker sessions yet")).not.toBeInTheDocument();
		expect(columnCount()).toBe(5);
	});
});
