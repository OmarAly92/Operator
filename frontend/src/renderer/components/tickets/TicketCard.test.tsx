import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkspaceSession } from "../../types/workspace";
import type { TicketWithProject } from "../../lib/ticket-presentation";
import { TooltipProvider } from "../ui/tooltip";

const { navigateMock, approveMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	approveMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));
vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({
			approveMerge: { mutateAsync: approveMutateAsync, isPending: false },
			planTicket: { mutateAsync: vi.fn(), isPending: false },
			reviewPlan: { mutateAsync: vi.fn(), isPending: false },
		}),
	};
});
vi.mock("./PlanWithAgentSheet", () => ({
	PlanWithAgentSheet: ({ open }: { open: boolean }) => (open ? <div data-testid="plan-sheet" /> : null),
}));
vi.mock("./ReviewPlanSheet", () => ({
	ReviewPlanSheet: ({ open }: { open: boolean }) => (open ? <div data-testid="review-sheet" /> : null),
}));

import { TicketCard } from "./TicketCard";

function ticket(overrides: Partial<TicketWithProject>): TicketWithProject {
	return {
		projectId: "p1",
		projectName: "app",
		slug: "search-page",
		title: "Search page",
		status: "draft",
		plans: [],
		files: ["ticket.md", "spec.md"],
		...overrides,
	};
}

function session(overrides: Partial<WorkspaceSession> & Pick<WorkspaceSession, "id">): WorkspaceSession {
	return {
		workspaceId: "p1",
		workspaceName: "app",
		title: overrides.id,
		provider: "claude-code",
		status: "working",
		updatedAt: "2026-09-18T10:00:00Z",
		prs: [],
		activity: { state: "active", lastActivityAt: "2026-09-18T10:00:00Z" },
		...overrides,
	};
}

function renderCard(data: TicketWithProject, sessions: WorkspaceSession[] = []) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>
				<TicketCard ticket={data} sessionsById={new Map(sessions.map((item) => [item.id, item]))} />
			</TooltipProvider>
		</QueryClientProvider>,
	);
}

beforeEach(() => {
	navigateMock.mockReset();
	approveMutateAsync.mockReset();
});

describe("TicketCard", () => {
	it("renders a draft with Plan with agent and opens the ticket page from the body", async () => {
		renderCard(ticket({}));
		expect(screen.getByText("Draft")).toBeInTheDocument();
		expect(screen.getByText("app")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Plan with agent" }));
		expect(screen.getByTestId("plan-sheet")).toBeInTheDocument();
		await userEvent.click(screen.getByTestId("ticket-card"));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: {},
		});
	});

	it("shows the planning session's activity and an Open planning session action", async () => {
		renderCard(ticket({ status: "planning", planningSessionId: "s-plan" }), [
			session({ id: "s-plan", status: "working" }),
		]);
		expect(screen.getByText("Planning")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Open planning session" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-plan" },
		});
	});

	it("lists plans in order with their status and opens a plan's session", async () => {
		renderCard(
			ticket({
				status: "in_progress",
				plans: [
					{ file: "plans/02-ui.md", order: 2, title: "UI", status: "working", sessionId: "s-2" },
					{ file: "plans/01-index.md", order: 1, title: "Index", status: "merged", sessionId: "s-1" },
				],
			}),
			[session({ id: "s-2" })],
		);
		const rows = screen.getAllByTestId("ticket-plan-row");
		expect(rows.map((row) => row.getAttribute("data-plan-file"))).toEqual(["plans/01-index.md", "plans/02-ui.md"]);
		expect(screen.getByText("1/2 merged")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Open the session for UI" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-2" },
		});
	});

	it("offers Review on an assigned plan", async () => {
		renderCard(
			ticket({
				status: "in_progress",
				plans: [{ file: "plans/01-index.md", order: 1, title: "Index", status: "in_review", sessionId: "s-1" }],
			}),
		);
		await userEvent.click(screen.getByRole("button", { name: "Review" }));
		expect(screen.getByTestId("review-sheet")).toBeInTheDocument();
	});

	it("asks for the user's confirmation and approves the merge", async () => {
		approveMutateAsync.mockResolvedValue({});
		renderCard(
			ticket({
				status: "awaiting_merge",
				plans: [
					{
						file: "plans/01-index.md",
						order: 1,
						title: "Index",
						status: "awaiting_merge",
						sessionId: "s-1",
						reviewerSessionId: "s-plan",
						mergeSummary: "All gates green, 12 files.",
					},
				],
			}),
		);
		expect(screen.getByText("Waiting for your confirmation")).toBeInTheDocument();
		expect(screen.getByText("All gates green, 12 files.")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Merge" }));
		const dialog = await screen.findByRole("dialog");
		expect(within(dialog).getByText("All gates green, 12 files.")).toBeInTheDocument();
		await userEvent.click(within(dialog).getByRole("button", { name: "Merge" }));
		await waitFor(() =>
			expect(approveMutateAsync).toHaveBeenCalledWith({ projectId: "p1", slug: "search-page", plan: "plans/01-index.md" }),
		);
	});

	it("flags an unreadable ticket", () => {
		renderCard(ticket({ warning: "ticket.md: malformed frontmatter" }));
		expect(screen.getByRole("status")).toHaveTextContent("ticket.md: malformed frontmatter");
	});
});
