import { useMutation, useQueryClient, type QueryClient } from "@tanstack/react-query";
import type { TFunction } from "i18next";
import type { components } from "../../api/schema";
import type { MessageKey } from "../i18n";
import { apiClient, apiErrorCode, apiErrorMessage, apiErrorRequestId } from "../lib/api-client";
import { ticketFileQueryKey, ticketsQueryRoot, type TicketFile } from "./useTicketsQuery";
import { workspaceQueryKey } from "./useWorkspaceQuery";

type SessionView = components["schemas"]["ControllersSessionView"];
type TicketView = components["schemas"]["TicketView"];
type CreateTicketResponse = components["schemas"]["CreateTicketResponse"];
type ReviewPlanResponse = components["schemas"]["ReviewPlanResponse"];
type AssignPlanResponse = components["schemas"]["AssignPlanResponse"];

export type TicketRef = { projectId: string; slug: string };
export type PlanRef = TicketRef & { plan: string };
export type TicketRoleInput = { harness?: string; model?: string; claudeAccountId?: string; extra?: string };
export type CreateTicketInput = { projectId: string; title: string; brief: string };
export type PlanTicketInput = TicketRef & TicketRoleInput;
export type ReviewPlanInput = PlanRef & TicketRoleInput & { reviewer: "planner" | "new" };
export type SetArchivedInput = TicketRef & { archived: boolean };
export type AssignPlanInput = PlanRef &
	TicketRoleInput & { dryRun?: boolean; force?: boolean; terminateSessionId?: string };
export type SaveTicketFileInput = TicketRef & { path: string; content: string; ifUnmodifiedSince?: string };

const ticketErrorKeys: Record<string, MessageKey> = {
	TICKET_ASSIGN_BLOCKED: "tickets.error.TICKET_ASSIGN_BLOCKED",
	TICKET_FILE_NOT_FOUND: "tickets.error.TICKET_FILE_NOT_FOUND",
	TICKET_FILE_STALE: "tickets.error.TICKET_FILE_STALE",
	TICKET_MERGE_APPROVED: "tickets.error.TICKET_MERGE_APPROVED",
	TICKET_NOT_FOUND: "tickets.error.TICKET_NOT_FOUND",
	TICKET_NOT_MERGE_READY: "tickets.error.TICKET_NOT_MERGE_READY",
	TICKET_PATH_OUTSIDE: "tickets.error.TICKET_PATH_OUTSIDE",
	TICKET_PLAN_NOT_FOUND: "tickets.error.TICKET_PLAN_NOT_FOUND",
	TICKET_PLAN_UNASSIGNED: "tickets.error.TICKET_PLAN_UNASSIGNED",
	TICKET_PLANNING_ACTIVE: "tickets.error.TICKET_PLANNING_ACTIVE",
	TICKET_REVIEWER_INVALID: "tickets.error.TICKET_REVIEWER_INVALID",
	TICKET_UNSUPPORTED_PROJECT: "tickets.error.TICKET_UNSUPPORTED_PROJECT",
};

export function ticketErrorMessage(error: unknown, t: TFunction, fallbackKey: MessageKey): string {
	const code = apiErrorCode(error);
	const known = code ? ticketErrorKeys[code] : undefined;
	const message = known ? t(known) : apiErrorMessage(error, t(fallbackKey));
	const requestId = apiErrorRequestId(error);
	return requestId ? `${message} · ${t("tickets.requestId", { requestId })}` : message;
}

export function apiErrorDetails(error: unknown): Record<string, unknown> | undefined {
	if (typeof error !== "object" || error === null) return undefined;
	const details = (error as { details?: unknown }).details;
	return typeof details === "object" && details !== null ? (details as Record<string, unknown>) : undefined;
}

export function assignBlockedWarnings(error: unknown): string[] {
	if (apiErrorCode(error) !== "TICKET_ASSIGN_BLOCKED") return [];
	const warnings = apiErrorDetails(error)?.warnings;
	return Array.isArray(warnings) ? warnings.filter((item): item is string => typeof item === "string") : [];
}

export function staleModifiedAt(error: unknown): string | undefined {
	if (apiErrorCode(error) !== "TICKET_FILE_STALE") return undefined;
	const modifiedAt = apiErrorDetails(error)?.modifiedAt;
	return typeof modifiedAt === "string" ? modifiedAt : undefined;
}

export function planParam(file: string): string {
	return file.startsWith("plans/") ? file.slice("plans/".length) : file;
}

function roleBody(input: TicketRoleInput) {
	return {
		harness: input.harness || undefined,
		model: input.model || undefined,
		claudeAccountId: input.claudeAccountId || undefined,
		extra: input.extra || undefined,
	};
}

function unwrap<T>(result: { data?: T; error?: unknown }): T {
	if (result.error) throw result.error;
	if (result.data === undefined) throw new Error("Empty response");
	return result.data;
}

function invalidateTickets(queryClient: QueryClient): void {
	void queryClient.invalidateQueries({ queryKey: ticketsQueryRoot });
	void queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
}

export function useTicketMutations() {
	const queryClient = useQueryClient();
	const onSettled = () => invalidateTickets(queryClient);

	const createTicket = useMutation({
		mutationFn: async (input: CreateTicketInput): Promise<CreateTicketResponse> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets", {
					params: { path: { id: input.projectId } },
					body: { title: input.title, brief: input.brief },
				}),
			),
		onSettled,
	});

	const planTicket = useMutation({
		mutationFn: async (input: PlanTicketInput): Promise<SessionView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plan", {
					params: { path: { id: input.projectId, slug: input.slug } },
					body: roleBody(input),
				}),
			),
		onSettled,
	});

	const reviewPlan = useMutation({
		mutationFn: async (input: ReviewPlanInput): Promise<ReviewPlanResponse> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", {
					params: { path: { id: input.projectId, slug: input.slug, plan: planParam(input.plan) } },
					body: { reviewer: input.reviewer, ...roleBody(input) },
				}),
			),
		onSettled,
	});

	const approveMerge = useMutation({
		mutationFn: async (input: PlanRef): Promise<TicketView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge", {
					params: { path: { id: input.projectId, slug: input.slug, plan: planParam(input.plan) } },
				}),
			).ticket,
		onSettled,
	});

	const markPlanDone = useMutation({
		mutationFn: async (input: PlanRef): Promise<TicketView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done", {
					params: { path: { id: input.projectId, slug: input.slug, plan: planParam(input.plan) } },
				}),
			).ticket,
		onSettled,
	});

	const setArchived = useMutation({
		mutationFn: async (input: SetArchivedInput): Promise<TicketView> => {
			const params = { path: { id: input.projectId, slug: input.slug } };
			const result = input.archived
				? await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/archive", { params })
				: await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/unarchive", { params });
			return unwrap(result).ticket;
		},
		onSettled,
	});

	const assignPlan = useMutation({
		mutationFn: async (input: AssignPlanInput): Promise<AssignPlanResponse> => {
			if (input.terminateSessionId) {
				const killed = await apiClient.POST("/api/v1/sessions/{sessionId}/kill", {
					params: { path: { sessionId: input.terminateSessionId } },
				});
				if (killed.error) throw killed.error;
			}
			return unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
					params: {
						path: { id: input.projectId, slug: input.slug, plan: planParam(input.plan) },
						query: input.dryRun ? { dryRun: true } : {},
					},
					body: { ...roleBody(input), force: input.force || undefined },
				}),
			);
		},
		onSettled: (_data, _error, input) => {
			if (!input.dryRun) invalidateTickets(queryClient);
		},
	});

	const saveTicketFile = useMutation({
		mutationFn: async (input: SaveTicketFileInput): Promise<TicketFile> =>
			unwrap(
				await apiClient.PUT("/api/v1/projects/{id}/tickets/{slug}/file", {
					params: { path: { id: input.projectId, slug: input.slug }, query: { path: input.path } },
					body: { content: input.content, ifUnmodifiedSince: input.ifUnmodifiedSince },
				}),
			),
		onSuccess: (file, input) => {
			queryClient.setQueryData(ticketFileQueryKey(input.projectId, input.slug, input.path), file);
			invalidateTickets(queryClient);
		},
	});

	return { createTicket, planTicket, reviewPlan, approveMerge, markPlanDone, setArchived, assignPlan, saveTicketFile };
}
