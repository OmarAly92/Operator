import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, assignMutateAsync, fetchTicketMock } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	assignMutateAsync: vi.fn(),
	fetchTicketMock: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketsQuery", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketsQuery")>();
	return { ...actual, fetchTicket: (...args: [string, string]) => fetchTicketMock(...args) };
});

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({ assignPlan: { mutateAsync: assignMutateAsync, isPending: false } }),
	};
});

vi.mock("../../hooks/useAgentsQuery", () => ({
	agentsQueryKey: ["agents"],
	agentsQueryOptions: {
		queryKey: ["agents"],
		queryFn: async () => ({
			supported: [{ id: "claude-code", label: "Claude Code" }],
			installed: [{ id: "claude-code", label: "Claude Code" }],
			authorized: [{ id: "claude-code", label: "Claude Code" }],
		}),
	},
	refreshAgentsIfStale: async () => undefined,
}));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => ({ data: [], isError: false, isLoading: false }) };
});

vi.mock("../TaskModelPicker", () => ({
	TaskModelPicker: ({ id, value, onModelChange }: { id: string; value: string; onModelChange: (v: string) => void }) => (
		<input id={id} aria-label="Model" value={value} onChange={(event) => onModelChange(event.target.value)} />
	),
}));

import { AssignPlanSheet } from "./AssignPlanSheet";

const ticket = { projectId: "p1", slug: "search-page", title: "Search page", projectName: "app" };
const todoPlan = { file: "plans/01-index.md", title: "Index", status: "todo" as const };
const livePlan = { file: "plans/01-index.md", title: "Index", status: "working" as const, sessionId: "s-old" };

function dryRunThen(warnings: string[], result: unknown = { warnings, session: { id: "s-new", projectId: "p1" } }) {
	assignMutateAsync.mockImplementation(async (input: { dryRun?: boolean }) => {
		if (input.dryRun) return { warnings };
		if (result instanceof Error || (typeof result === "object" && result !== null && "code" in result)) throw result;
		return result;
	});
}

function renderSheet(plan: typeof todoPlan | typeof livePlan, onOpenChange = vi.fn()) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<AssignPlanSheet open onOpenChange={onOpenChange} ticket={ticket} plan={plan} />
		</QueryClientProvider>,
	);
	return onOpenChange;
}

beforeEach(() => {
	navigateMock.mockReset();
	assignMutateAsync.mockReset();
	fetchTicketMock.mockReset().mockResolvedValue({
		projectId: "p1",
		slug: "search-page",
		title: "Search page",
		status: "in_progress",
		files: [],
		plans: [{ file: "plans/01-index.md", order: 1, title: "Index", status: "working", sessionId: "s-old" }],
	});
});

describe("AssignPlanSheet", () => {
	it("dry-runs on open, shows the read-only rows and each warning, then forces and navigates", async () => {
		dryRunThen(["ticket_repo_dirty", "plan_order"]);
		renderSheet(todoPlan);

		expect(screen.getByText("Checking…")).toBeInTheDocument();
		expect(await screen.findByText("The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.")).toBeInTheDocument();
		expect(screen.getByText("An earlier plan in this ticket is not merged or done yet.")).toBeInTheDocument();
		expect(screen.getByText("opr/search-page-01")).toBeInTheDocument();
		expect(screen.getByText("01 Index")).toBeInTheDocument();
		expect(screen.getByText("app")).toBeInTheDocument();
		expect(assignMutateAsync).toHaveBeenCalledWith({ projectId: "p1", slug: "search-page", plan: "plans/01-index.md", dryRun: true });

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		await waitFor(() => expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-new" },
		}));
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ plan: "plans/01-index.md", force: true, terminateSessionId: undefined }),
		);
	});

	it("does not force when the dry run is clean", async () => {
		dryRunThen([]);
		renderSheet(todoPlan);
		const start = await screen.findByRole("button", { name: "Start" });
		await waitFor(() => expect(start).toBeEnabled());

		await userEvent.click(start);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(assignMutateAsync).toHaveBeenLastCalledWith(expect.objectContaining({ force: undefined }));
	});

	it("turns Start into Terminate and start for a live plan and kills that session first", async () => {
		dryRunThen(["plan_assigned"]);
		renderSheet(livePlan);

		const button = await screen.findByRole("button", { name: "Terminate and start" });
		await userEvent.click(button);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(fetchTicketMock).toHaveBeenCalledWith("p1", "search-page");
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ force: true, terminateSessionId: "s-old" }),
		);
	});

	it("terminates the session that is actually live, not the stale prop, when the plan became assigned after the sheet opened", async () => {
		dryRunThen([], { error: "conflict", code: "TICKET_ASSIGN_BLOCKED", message: "Assignment needs confirmation", details: { warnings: ["plan_assigned"] } });
		fetchTicketMock.mockResolvedValue({
			projectId: "p1",
			slug: "search-page",
			title: "Search page",
			status: "in_progress",
			files: [],
			plans: [{ file: "plans/01-index.md", order: 1, title: "Index", status: "working", sessionId: "s-fresh" }],
		});
		renderSheet(todoPlan);
		await waitFor(() => expect(screen.getByRole("button", { name: "Start" })).toBeEnabled());

		await userEvent.click(screen.getByRole("button", { name: "Start" }));
		const button = await screen.findByRole("button", { name: "Terminate and start" });
		assignMutateAsync.mockImplementation(async (input: { dryRun?: boolean }) => {
			if (input.dryRun) return { warnings: ["plan_assigned"] };
			return { warnings: ["plan_assigned"], session: { id: "s-new", projectId: "p1" } };
		});
		await userEvent.click(button);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(fetchTicketMock).toHaveBeenCalledWith("p1", "search-page");
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ force: true, terminateSessionId: "s-fresh" }),
		);
	});

	it("falls back to the plan prop's session id when the fresh ticket fetch fails", async () => {
		dryRunThen(["plan_assigned"]);
		fetchTicketMock.mockRejectedValue(new Error("network down"));
		renderSheet(livePlan);

		const button = await screen.findByRole("button", { name: "Terminate and start" });
		await userEvent.click(button);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ force: true, terminateSessionId: "s-old" }),
		);
	});

	it("submits on Enter and cancels on Escape without spawning", async () => {
		dryRunThen([]);
		const onOpenChange = renderSheet(todoPlan);
		await waitFor(() => expect(screen.getByRole("button", { name: "Start" })).toBeEnabled());

		await userEvent.keyboard("{Escape}");
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(assignMutateAsync).toHaveBeenCalledTimes(1);

		await userEvent.click(screen.getByLabelText("Model"));
		await userEvent.keyboard("{Enter}");
		await waitFor(() => expect(assignMutateAsync).toHaveBeenCalledTimes(3));
		expect(assignMutateAsync.mock.calls[1]?.[0]).toMatchObject({ dryRun: true });
		expect(assignMutateAsync.mock.calls[2]?.[0]).not.toHaveProperty("dryRun");
	});

	it("re-checks the warnings on Start and stops when a new one appeared, instead of forcing past it", async () => {
		let dryRuns = 0;
		assignMutateAsync.mockImplementation(async (input: { dryRun?: boolean }) => {
			if (input.dryRun) {
				dryRuns += 1;
				return { warnings: dryRuns === 1 ? ["ticket_repo_dirty"] : ["ticket_repo_dirty", "plan_assigned"] };
			}
			return { warnings: [], session: { id: "s-new", projectId: "p1" } };
		});
		renderSheet(todoPlan);
		await screen.findByText("The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.");

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		expect(await screen.findByRole("button", { name: "Terminate and start" })).toBeEnabled();
		expect(screen.getByText("This plan already has a live session. Starting again terminates it first.")).toBeInTheDocument();
		expect(screen.getByRole("alert")).toHaveTextContent("The assignment needs confirmation.");
		expect(navigateMock).not.toHaveBeenCalled();
		expect(assignMutateAsync.mock.calls.every((call) => (call[0] as { dryRun?: boolean }).dryRun)).toBe(true);
	});

	it("adopts the daemon's warnings when a submit comes back blocked", async () => {
		dryRunThen([], { error: "conflict", code: "TICKET_ASSIGN_BLOCKED", message: "Assignment needs confirmation", details: { warnings: ["planning_active"] } });
		renderSheet(todoPlan);
		await waitFor(() => expect(screen.getByRole("button", { name: "Start" })).toBeEnabled());

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		expect(await screen.findByText("The planning session is still running.")).toBeInTheDocument();
		expect(screen.getByRole("alert")).toHaveTextContent("The assignment needs confirmation.");
		expect(navigateMock).not.toHaveBeenCalled();
	});
});
