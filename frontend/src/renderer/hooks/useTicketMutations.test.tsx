import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { appI18n } from "../i18n";

const { postMock, putMock } = vi.hoisted(() => ({ postMock: vi.fn(), putMock: vi.fn() }));

vi.mock("../lib/api-client", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../lib/api-client")>();
	return {
		...actual,
		apiClient: { POST: (...args: unknown[]) => postMock(...args), PUT: (...args: unknown[]) => putMock(...args), GET: vi.fn() },
	};
});

import { assignBlockedWarnings, planParam, staleModifiedAt, ticketErrorMessage, useTicketMutations } from "./useTicketMutations";

function wrapper(queryClient: QueryClient) {
	return ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
	);
}

beforeEach(() => {
	postMock.mockReset();
	putMock.mockReset();
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

	it("sends a dry run to the bare plan route and returns the warnings", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({ data: { warnings: ["ticket_repo_dirty"] } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const response = await act(() =>
			result.current.assignPlan.mutateAsync({ projectId: "p1", slug: "t", plan: "plans/01-daemon.md", dryRun: true }),
		);

		expect(response.warnings).toEqual(["ticket_repo_dirty"]);
		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
			params: { path: { id: "p1", slug: "t", plan: "01-daemon.md" }, query: { dryRun: true } },
			body: { harness: undefined, model: undefined, claudeAccountId: undefined, extra: undefined, force: undefined },
		});
	});

	it("kills the live session before a forced assign when asked to", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValueOnce({ data: {} }).mockResolvedValueOnce({ data: { warnings: ["plan_assigned"], session: { id: "s-2", projectId: "p1" } } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const response = await act(() =>
			result.current.assignPlan.mutateAsync({
				projectId: "p1",
				slug: "t",
				plan: "plans/01-daemon.md",
				force: true,
				terminateSessionId: "s-1",
				harness: "claude-code",
				model: "claude-haiku-4-5-20251001",
			}),
		);

		expect(response.session?.id).toBe("s-2");
		expect(postMock).toHaveBeenNthCalledWith(1, "/api/v1/sessions/{sessionId}/kill", { params: { path: { sessionId: "s-1" } } });
		expect(postMock).toHaveBeenNthCalledWith(2, "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
			params: { path: { id: "p1", slug: "t", plan: "01-daemon.md" }, query: {} },
			body: { harness: "claude-code", model: "claude-haiku-4-5-20251001", claudeAccountId: undefined, extra: undefined, force: true },
		});
	});

	it("saves a file with ifUnmodifiedSince and primes the file query", async () => {
		const queryClient = new QueryClient();
		const saved = { path: "spec.md", content: "# Spec", modifiedAt: "2026-09-18T11:00:00Z" };
		putMock.mockResolvedValue({ data: saved });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await act(() =>
			result.current.saveTicketFile.mutateAsync({
				projectId: "p1",
				slug: "t",
				path: "spec.md",
				content: "# Spec",
				ifUnmodifiedSince: "2026-09-18T10:00:00Z",
			}),
		);

		expect(putMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/file", {
			params: { path: { id: "p1", slug: "t" }, query: { path: "spec.md" } },
			body: { content: "# Spec", ifUnmodifiedSince: "2026-09-18T10:00:00Z" },
		});
		expect(queryClient.getQueryData(["tickets", "p1", "t", "file", "spec.md"])).toEqual(saved);
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

describe("error details", () => {
	it("reads the blocked warnings and the stale timestamp from the envelope", () => {
		expect(
			assignBlockedWarnings({ error: "conflict", code: "TICKET_ASSIGN_BLOCKED", message: "x", details: { warnings: ["plan_assigned"] } }),
		).toEqual(["plan_assigned"]);
		expect(assignBlockedWarnings({ error: "conflict", code: "TICKET_NOT_FOUND", message: "x" })).toEqual([]);
		expect(
			staleModifiedAt({ error: "conflict", code: "TICKET_FILE_STALE", message: "x", details: { modifiedAt: "2026-09-18T11:00:00Z" } }),
		).toBe("2026-09-18T11:00:00Z");
		expect(staleModifiedAt({ error: "conflict", code: "TICKET_FILE_NOT_FOUND", message: "x" })).toBeUndefined();
	});
});
