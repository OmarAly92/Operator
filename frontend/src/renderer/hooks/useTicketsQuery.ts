import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import type { components } from "../../api/schema";
import { apiClient } from "../lib/api-client";
import { subscribeTicketChanges } from "../lib/ticket-events";
import type { TicketView, TicketWithProject } from "../lib/ticket-presentation";

export type TicketFile = components["schemas"]["TicketFileResponse"];
export type TicketProject = { id: string; name: string };

export const ticketsQueryRoot = ["tickets"] as const;
export const ticketsQueryKey = (projectId: string) => [...ticketsQueryRoot, projectId] as const;
export const ticketQueryKey = (projectId: string, slug: string) => [...ticketsQueryRoot, projectId, slug] as const;
export const ticketFileQueryKey = (projectId: string, slug: string, path: string) =>
	[...ticketsQueryRoot, projectId, slug, "file", path] as const;

const TICKETS_REFETCH_MS = 30_000;

async function fetchTickets(projectId: string): Promise<TicketView[]> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets", {
		params: { path: { id: projectId } },
	});
	if (error) throw error;
	return data?.tickets ?? [];
}

async function fetchTicket(projectId: string, slug: string): Promise<TicketView> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets/{slug}", {
		params: { path: { id: projectId, slug } },
	});
	if (error || !data) throw error ?? new Error("Ticket response was empty");
	return data.ticket;
}

async function fetchTicketFile(projectId: string, slug: string, path: string): Promise<TicketFile> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets/{slug}/file", {
		params: { path: { id: projectId, slug }, query: { path } },
	});
	if (error || !data) throw error ?? new Error("Ticket file response was empty");
	return data;
}

function useTicketChangeSubscription(projectIds: readonly string[]): void {
	const queryClient = useQueryClient();
	const idsKey = projectIds.join("\n");
	useEffect(() => {
		const unsubscribes = idsKey
			.split("\n")
			.filter((id) => id !== "")
			.map((id) => subscribeTicketChanges(id, queryClient));
		return () => {
			for (const unsubscribe of unsubscribes) unsubscribe();
		};
	}, [idsKey, queryClient]);
}

export function useTicketsQuery(projects: readonly TicketProject[]): {
	tickets: TicketWithProject[];
	isError: boolean;
	isSuccess: boolean;
} {
	useTicketChangeSubscription(projects.map((project) => project.id));
	const results = useQueries({
		queries: projects.map((project) => ({
			queryKey: ticketsQueryKey(project.id),
			queryFn: () => fetchTickets(project.id),
			retry: 1,
			refetchInterval: TICKETS_REFETCH_MS,
		})),
	});
	const tickets = results.flatMap((result, index) =>
		(result.data ?? []).map((ticket) => ({ ...ticket, projectName: projects[index]?.name ?? "" })),
	);
	return {
		tickets,
		isError: results.some((result) => result.isError),
		isSuccess: results.every((result) => result.isSuccess),
	};
}

export function useTicketQuery(projectId: string, slug: string) {
	useTicketChangeSubscription([projectId]);
	return useQuery({
		queryKey: ticketQueryKey(projectId, slug),
		queryFn: () => fetchTicket(projectId, slug),
		retry: 1,
		refetchInterval: TICKETS_REFETCH_MS,
	});
}

export function useTicketFileQuery(projectId: string, slug: string, path: string | undefined) {
	return useQuery({
		queryKey: ticketFileQueryKey(projectId, slug, path ?? ""),
		queryFn: () => fetchTicketFile(projectId, slug, path ?? ""),
		enabled: path !== undefined && path !== "",
		retry: 1,
	});
}
