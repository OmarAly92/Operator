import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, createMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	createMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({
			createTicket: { mutateAsync: createMutateAsync, isPending: false },
		}),
	};
});

import { CreateTicketSheet } from "./CreateTicketSheet";

function renderSheet(projects: Array<{ id: string; name: string }>, defaultProjectId?: string) {
	const onOpenChange = vi.fn();
	render(
		<QueryClientProvider client={new QueryClient()}>
			<CreateTicketSheet open onOpenChange={onOpenChange} projects={projects} defaultProjectId={defaultProjectId} />
		</QueryClientProvider>,
	);
	return { onOpenChange };
}

beforeEach(() => {
	navigateMock.mockReset();
	createMutateAsync.mockReset();
});

describe("CreateTicketSheet", () => {
	it("creates the ticket for the only project and opens its page", async () => {
		createMutateAsync.mockResolvedValue({ ticket: { projectId: "p1", slug: "search-page", title: "Search page" }, warnings: [] });
		const { onOpenChange } = renderSheet([{ id: "p1", name: "app" }]);

		await userEvent.type(screen.getByLabelText("Title"), "Search page");
		await userEvent.type(screen.getByLabelText("Brief"), "Full text search");
		await userEvent.click(screen.getByRole("button", { name: "New ticket" }));

		await waitFor(() =>
			expect(createMutateAsync).toHaveBeenCalledWith({ projectId: "p1", title: "Search page", brief: "Full text search" }),
		);
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: {},
		});
	});

	it("keeps the submit disabled until a title is typed", async () => {
		renderSheet([{ id: "p1", name: "app" }]);
		expect(screen.getByRole("button", { name: "New ticket" })).toBeDisabled();
		await userEvent.type(screen.getByLabelText("Title"), "x");
		expect(screen.getByRole("button", { name: "New ticket" })).toBeEnabled();
	});

	it("shows the daemon's error with its request id and stays open", async () => {
		createMutateAsync.mockRejectedValue({
			error: "bad_request",
			code: "TICKET_UNSUPPORTED_PROJECT",
			message: "nope",
			requestId: "req-3",
		});
		const { onOpenChange } = renderSheet([{ id: "p1", name: "app" }]);

		await userEvent.type(screen.getByLabelText("Title"), "Search page");
		await userEvent.click(screen.getByRole("button", { name: "New ticket" }));

		expect(await screen.findByRole("alert")).toHaveTextContent(
			"Tickets need a single-repository project. · request req-3",
		);
		expect(onOpenChange).not.toHaveBeenCalledWith(false);
	});

	it("offers a project picker when several projects can hold tickets", () => {
		renderSheet(
			[
				{ id: "p1", name: "app" },
				{ id: "p2", name: "api" },
			],
			"p2",
		);
		expect(screen.getByLabelText("Project")).toHaveTextContent("api");
	});
});
