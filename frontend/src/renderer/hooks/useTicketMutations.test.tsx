import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { appI18n } from "../i18n";

const { postMock } = vi.hoisted(() => ({ postMock: vi.fn() }));

vi.mock("../lib/api-client", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../lib/api-client")>();
	return { ...actual, apiClient: { POST: (...args: unknown[]) => postMock(...args), GET: vi.fn() } };
});

import { planParam, ticketErrorMessage, useTicketMutations } from "./useTicketMutations";

function wrapper(queryClient: QueryClient) {
	return ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
	);
}

beforeEach(() => {
	postMock.mockReset();
});

describe("useTicketMutations", () => {
	it("creates a ticket and invalidates the ticket and workspace queries", async () => {
		const queryClient = new QueryClient();
		const invalidate = vi.spyOn(queryClient, "invalidateQueries");
		postMock.mockResolvedValue({
			data: { ticket: { projectId: "p1", slug: "new-thing", title: "New thing", status: "draft", plans: [], files: [] }, warnings: [] },
		});
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const created = await act(() =>
			result.current.createTicket.mutateAsync({ projectId: "p1", title: "New thing", brief: "Because" }),
		);

		expect(created.ticket.slug).toBe("new-thing");
		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets", {
			params: { path: { id: "p1" } },
			body: { title: "New thing", brief: "Because" },
		});
		await waitFor(() => expect(invalidate).toHaveBeenCalledWith({ queryKey: ["tickets"] }));
		expect(invalidate).toHaveBeenCalledWith({ queryKey: ["workspaces"] });
	});

	it("sends the reviewer choice and role fields to the review route", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({ data: { session: { id: "s-9", projectId: "p1" }, spawned: true } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await act(() =>
			result.current.reviewPlan.mutateAsync({
				projectId: "p1",
				slug: "t",
				plan: "plans/01-daemon.md",
				reviewer: "new",
				harness: "claude-code",
				model: "claude-opus-5",
				claudeAccountId: "",
				extra: "",
			}),
		);

		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", {
			params: { path: { id: "p1", slug: "t", plan: "01-daemon.md" } },
			body: { reviewer: "new", harness: "claude-code", model: "claude-opus-5", claudeAccountId: undefined, extra: undefined },
		});
	});

	it("rejects with the daemon envelope so callers can branch on the code", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({
			error: { error: "conflict", code: "TICKET_NOT_MERGE_READY", message: "not ready", requestId: "req-1" },
		});
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await expect(
			act(() => result.current.approveMerge.mutateAsync({ projectId: "p1", slug: "t", plan: "plans/01-daemon.md" })),
		).rejects.toMatchObject({ code: "TICKET_NOT_MERGE_READY" });
	});
});

describe("ticketErrorMessage", () => {
	it("maps known codes to copy and keeps the request id", () => {
		const message = ticketErrorMessage(
			{ error: "conflict", code: "TICKET_MERGE_APPROVED", message: "already", requestId: "req-7" },
			appI18n.t,
			"tickets.mergeFailed",
		);
		expect(message).toBe("This merge was already approved. · request req-7");
	});

	it("falls back to the envelope message for unknown codes", () => {
		const message = ticketErrorMessage(
			{ error: "internal", code: "SOMETHING_ELSE", message: "boom", requestId: "req-8" },
			appI18n.t,
			"tickets.mergeFailed",
		);
		expect(message).toBe("boom (SOMETHING_ELSE) · request req-8");
	});

	it("uses the fallback copy when there is no envelope", () => {
		expect(ticketErrorMessage(undefined, appI18n.t, "tickets.mergeFailed")).toBe("Could not approve the merge");
	});
});

describe("planParam", () => {
	it("sends the bare plan file name the daemon route expects", () => {
		expect(planParam("plans/01-daemon.md")).toBe("01-daemon.md");
		expect(planParam("01-daemon.md")).toBe("01-daemon.md");
	});
});
