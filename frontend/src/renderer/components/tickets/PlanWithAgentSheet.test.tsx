import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, planMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	planMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({ planTicket: { mutateAsync: planMutateAsync, isPending: false } }),
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

import { PlanWithAgentSheet } from "./PlanWithAgentSheet";

beforeEach(() => {
	navigateMock.mockReset();
	planMutateAsync.mockReset();
});

describe("PlanWithAgentSheet", () => {
	it("starts the planning session with the chosen role fields and opens it", async () => {
		planMutateAsync.mockResolvedValue({ id: "s-plan", projectId: "p1" });
		const onOpenChange = vi.fn();
		render(
			<QueryClientProvider client={new QueryClient()}>
				<PlanWithAgentSheet
					open
					onOpenChange={onOpenChange}
					ticket={{ projectId: "p1", slug: "search-page", title: "Search page" }}
				/>
			</QueryClientProvider>,
		);

		await userEvent.type(screen.getByLabelText("Model"), "claude-opus-5");
		await userEvent.type(screen.getByLabelText("Extra instructions"), "Keep it small");
		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		await waitFor(() =>
			expect(planMutateAsync).toHaveBeenCalledWith({
				projectId: "p1",
				slug: "search-page",
				harness: "",
				model: "claude-opus-5",
				claudeAccountId: "",
				extra: "Keep it small",
			}),
		);
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-plan" },
		});
	});

	it("reports a running planning session instead of closing", async () => {
		planMutateAsync.mockRejectedValue({
			error: "conflict",
			code: "TICKET_PLANNING_ACTIVE",
			message: "running",
			requestId: "req-9",
		});
		render(
			<QueryClientProvider client={new QueryClient()}>
				<PlanWithAgentSheet
					open
					onOpenChange={vi.fn()}
					ticket={{ projectId: "p1", slug: "search-page", title: "Search page" }}
				/>
			</QueryClientProvider>,
		);

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		expect(await screen.findByRole("alert")).toHaveTextContent(
			"This ticket already has a running planning session. · request req-9",
		);
		expect(navigateMock).not.toHaveBeenCalled();
	});
});
