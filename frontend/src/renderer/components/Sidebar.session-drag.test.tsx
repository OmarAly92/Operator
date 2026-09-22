import { SidebarProvider } from "@/components/ui/sidebar";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";

vi.mock("motion/react", async (importOriginal) => {
	const actual = await importOriginal<typeof import("motion/react")>();
	return {
		...actual,
		AnimatePresence: ({ children }: { children: React.ReactNode }) => children,
	};
});
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AppDndProvider } from "./dnd/AppDndProvider";
import { Sidebar } from "./Sidebar";
import { agentsQueryKey } from "../hooks/useAgentsQuery";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";

const { navigateMock, mockParams } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	mockParams: { projectId: undefined as string | undefined, sessionId: undefined as string | undefined },
}));

vi.mock("../hooks/useMobileTunnelStatus", () => ({ useMobileTunnelStatus: () => undefined }));

vi.mock("@tanstack/react-router", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-router")>();
	return {
		...actual,
		useNavigate: () => navigateMock,
		useParams: () => ({ ...mockParams }),
		useRouterState: ({ select }: { select: (state: { location: { pathname: string } }) => unknown }) =>
			select({ location: { pathname: "/" } }),
	};
});

vi.mock("../lib/api-client", () => ({
	apiClient: { GET: vi.fn().mockResolvedValue({ data: {}, error: undefined }), POST: vi.fn() },
	apiErrorMessage: () => "Request failed",
}));

const workspace: WorkspaceSummary = {
	id: "proj-1",
	name: "Project One",
	path: "/repo/project-one",
	sessions: [],
};

const session: WorkspaceSession = {
	id: "proj-1-1",
	workspaceId: "proj-1",
	workspaceName: "Project One",
	title: "fix login",
	provider: "claude-code",
	branch: "session/proj-1-1",
	status: "working",
	updatedAt: "2026-06-30T00:00:00Z",
	prs: [],
};

beforeEach(() => {
	window.localStorage.clear();
	navigateMock.mockReset();
	mockParams.projectId = undefined;
	mockParams.sessionId = undefined;
});

function renderSidebarInDndProvider() {
	mockParams.projectId = "proj-1";
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
	queryClient.setQueryData(agentsQueryKey, {
		supported: [{ id: "claude-code", label: "Claude Code" }],
		installed: [{ id: "claude-code", label: "Claude Code" }],
		authorized: [{ id: "claude-code", label: "Claude Code", authStatus: "authorized" }],
	});
	render(
		<QueryClientProvider client={queryClient}>
			<AppDndProvider>
				<SidebarProvider defaultOpen>
					<Sidebar
						onCreateProject={vi.fn().mockResolvedValue(undefined)}
						onInitializeProject={vi.fn().mockResolvedValue(undefined)}
						onRemoveProject={vi.fn().mockResolvedValue(undefined)}
						workspaces={[{ ...workspace, sessions: [session] }]}
					/>
				</SidebarProvider>
			</AppDndProvider>
		</QueryClientProvider>,
	);
}

describe("SessionRow as a split drag source", () => {
	it("keeps the open button clickable inside AppDndProvider", async () => {
		renderSidebarInDndProvider();
		const openButton = await screen.findByLabelText(`Open ${session.title}`);
		await userEvent.click(openButton);
		expect(navigateMock).toHaveBeenCalled();
	});
});
