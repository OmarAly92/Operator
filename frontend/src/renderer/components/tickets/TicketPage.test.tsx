import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { TooltipProvider } from "../ui/tooltip";

const { navigateMock, ticketQueryMock, ticketFileQueryMock, workspaceQueryMock, mutationsMock, requestAssignMock } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	ticketQueryMock: vi.fn(),
	ticketFileQueryMock: vi.fn(),
	workspaceQueryMock: vi.fn(),
	mutationsMock: vi.fn(),
	requestAssignMock: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));
vi.mock("../../hooks/useTicketsQuery", () => ({
	useTicketQuery: ticketQueryMock,
	useTicketFileQuery: ticketFileQueryMock,
}));
vi.mock("../../hooks/useWorkspaceQuery", () => ({
	workspaceQueryKey: ["workspaces"],
	useWorkspaceQuery: workspaceQueryMock,
}));
vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return { ...actual, useTicketMutations: () => mutationsMock() };
});
vi.mock("./PlanWithAgentSheet", () => ({ PlanWithAgentSheet: () => null }));
vi.mock("./ReviewPlanSheet", () => ({ ReviewPlanSheet: () => null }));
vi.mock("./MergeConfirmDialog", () => ({ MergeConfirmDialog: () => null }));
vi.mock("./TicketDndProvider", () => ({
	useTicketDrag: () => ({ active: null, requestAssign: requestAssignMock }),
	usePlanDraggable: () => ({
		attributes: {},
		listeners: {},
		setNodeRef: () => undefined,
		setActivatorNodeRef: () => undefined,
		isDragging: false,
	}),
}));

import { TicketPage } from "./TicketPage";

const ticket = {
	projectId: "p1",
	slug: "search-page",
	title: "Search page",
	brief: "Full text search",
	status: "in_progress" as const,
	planningSessionId: "s-plan",
	plans: [
		{ file: "plans/01-index.md", order: 1, title: "Index", status: "merged" as const, sessionId: "s-1" },
		{
			file: "plans/02-ui.md",
			order: 2,
			title: "UI",
			status: "working" as const,
			sessionId: "s-2",
			kickoffFile: "plans/02-ui.kickoff.md",
		},
	],
	files: ["ticket.md", "spec.md", "plans/01-index.md", "plans/02-ui.md", "plans/02-ui.kickoff.md"],
};

function renderPage(file?: string) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>
				<TicketPage projectId="p1" slug="search-page" file={file} />
			</TooltipProvider>
		</QueryClientProvider>,
	);
}

beforeEach(() => {
	navigateMock.mockReset();
	ticketQueryMock.mockReset().mockReturnValue({ data: ticket, isError: false, isSuccess: true });
	ticketFileQueryMock.mockReset().mockReturnValue({
		data: { path: "spec.md", content: '---\ntitle: "Search page"\n---\n\n# Spec\n\nSearch **everything**.', modifiedAt: "2026-09-18T10:00:00Z" },
		isError: false,
	});
	workspaceQueryMock.mockReset().mockReturnValue({
		data: [
			{
				id: "p1",
				name: "app",
				kind: "single_repo",
				path: "/tmp/app",
				sessions: [
					{ id: "s-plan", workspaceId: "p1", workspaceName: "app", title: "plan", provider: "claude-code", status: "idle", updatedAt: "2026-09-18T10:00:00Z", prs: [], activity: { state: "idle", lastActivityAt: "2026-09-18T10:00:00Z" } },
					{ id: "s-2", workspaceId: "p1", workspaceName: "app", title: "ui", provider: "claude-code", status: "working", updatedAt: "2026-09-18T10:00:00Z", prs: [], activity: { state: "active", lastActivityAt: "2026-09-18T10:00:00Z" } },
				],
			},
		],
		isError: false,
		isSuccess: true,
	});
	mutationsMock.mockReset().mockReturnValue({
		markPlanDone: { mutateAsync: vi.fn(), isPending: false },
		setArchived: { mutateAsync: vi.fn(), isPending: false },
	});
	requestAssignMock.mockReset();
});

describe("TicketPage", () => {
	it("lists the docs, the plans with their kickoff files and the planning session", () => {
		renderPage("spec.md");
		const files = screen.getByRole("navigation", { name: "Ticket files" });
		expect(within(files).getByRole("button", { name: "ticket.md" })).toBeInTheDocument();
		expect(within(files).getByRole("button", { name: "spec.md" })).toHaveAttribute("aria-current", "true");
		expect(within(files).getByText("01")).toBeInTheDocument();
		expect(within(files).getByText("Index")).toBeInTheDocument();
		expect(within(files).getByRole("button", { name: "Kickoff prompt" })).toBeInTheDocument();
		expect(within(files).getByText("Merged")).toBeInTheDocument();
		expect(within(files).getByText("Working")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Open planning session" })).toBeInTheDocument();
		expect(screen.getByText("1/2 merged")).toBeInTheDocument();
	});

	it("previews the selected file with its frontmatter above the body", () => {
		renderPage("spec.md");
		expect(ticketFileQueryMock).toHaveBeenCalledWith("p1", "search-page", "spec.md");
		expect(screen.getByRole("heading", { name: "Spec" })).toBeInTheDocument();
		expect(screen.getByText("everything")).toBeInTheDocument();
		expect(screen.getByText("title")).toBeInTheDocument();
		expect(screen.getByText("Search page", { selector: "dd" })).toBeInTheDocument();
	});

	it("defaults to spec.md and navigates when another file is picked", async () => {
		renderPage(undefined);
		expect(ticketFileQueryMock).toHaveBeenCalledWith("p1", "search-page", "spec.md");
		await userEvent.click(screen.getByRole("button", { name: "ticket.md" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: { file: "ticket.md" },
			replace: true,
		});
	});

	it("opens the implementing session from its plan row", async () => {
		renderPage("spec.md");
		await userEvent.click(screen.getByRole("button", { name: "Open the session for UI" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-2" },
		});
	});

	it("shows a warning banner above an unreadable ticket", () => {
		ticketQueryMock.mockReturnValue({
			data: { ...ticket, status: "draft", plans: [], warning: "ticket.md: malformed frontmatter" },
			isError: false,
			isSuccess: true,
		});
		renderPage("ticket.md");
		const banners = screen.getAllByRole("status");
		expect(banners).toHaveLength(2);
		for (const banner of banners) expect(banner).toHaveTextContent("ticket.md: malformed frontmatter");
	});

	it("offers Assign on a todo plan from the file list", async () => {
		ticketQueryMock.mockReturnValue({
			data: { ...ticket, plans: [...ticket.plans, { file: "plans/03-docs.md", order: 3, title: "Docs", status: "todo" as const }] },
			isError: false,
			isSuccess: true,
		});
		renderPage();
		await userEvent.click(screen.getByRole("button", { name: "Assign" }));
		expect(requestAssignMock).toHaveBeenCalledWith(
			expect.objectContaining({ slug: "search-page", projectName: "app" }),
			expect.objectContaining({ file: "plans/03-docs.md" }),
		);
	});
});
