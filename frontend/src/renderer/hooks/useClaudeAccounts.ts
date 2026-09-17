import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { TFunction } from "i18next";
import { useCallback } from "react";
import type { components } from "../../api/schema";
import { apiClient, hasTrustedApiBaseUrl } from "../lib/api-client";
import { paneGridBody } from "../lib/pane-grid";
import { shellTerminalsQueryKey, toShellTerminal, type ShellTerminal } from "./useShellTerminals";
import type { WorkspaceSession } from "../types/workspace";

export type ClaudeAccount = components["schemas"]["ClaudeAccountView"];

export const claudeAccountsQueryKey = ["claude-accounts"] as const;

async function fetchClaudeAccounts(refresh: boolean): Promise<ClaudeAccount[]> {
	if (!hasTrustedApiBaseUrl()) return [];
	const { data, error } = await apiClient.GET("/api/v1/claude-accounts", {
		params: { query: refresh ? { refresh: 1 } : {} },
	});
	if (error) throw error;
	return data?.accounts ?? [];
}

export function claudeAccountSlug(label: string): string {
	return label
		.trim()
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "");
}

export function claudeAccountLabelForSession(
	session: Pick<WorkspaceSession, "provider" | "claudeAccountId">,
	accounts: readonly ClaudeAccount[] | undefined,
): string | undefined {
	if (session.provider !== "claude-code") return undefined;
	const id = session.claudeAccountId?.trim() || "default";
	const known = accounts?.find((account) => account.id === id)?.label.trim();
	if (known) return known;
	return id.charAt(0).toUpperCase() + id.slice(1);
}

export function sharedClaudeLogins(accounts: readonly ClaudeAccount[]): Map<string, string[]> {
	const byLogin = new Map<string, ClaudeAccount[]>();
	for (const account of accounts) {
		const email = account.status?.reportedEmail?.trim().toLowerCase();
		if (!email) continue;
		const key = `${email}\u0000${account.status?.reportedOrgId ?? ""}`;
		byLogin.set(key, [...(byLogin.get(key) ?? []), account]);
	}
	const shared = new Map<string, string[]>();
	for (const group of byLogin.values()) {
		if (group.length < 2) continue;
		for (const account of group) {
			shared.set(
				account.id,
				group.filter((other) => other.id !== account.id).map((other) => other.label),
			);
		}
	}
	return shared;
}

const PLAN_KEYS = {
	max: "settings.claudeAccounts.plan.max",
	pro: "settings.claudeAccounts.plan.pro",
	notLoggedIn: "settings.claudeAccounts.plan.notLoggedIn",
	unknown: "settings.claudeAccounts.plan.unknown",
} as const;

export function claudeAccountPlanLabel(account: ClaudeAccount, t: TFunction): string {
	const loggedIn = account.status?.loggedIn;
	if (loggedIn === false) return t(PLAN_KEYS.notLoggedIn);
	if (loggedIn !== true) return t(PLAN_KEYS.unknown);
	const plan = account.status?.subscriptionType ?? "";
	if (plan === "max" || plan === "pro") return t(PLAN_KEYS[plan]);
	return plan || t(PLAN_KEYS.unknown);
}

export function useClaudeAccounts() {
	return useQuery({
		queryKey: claudeAccountsQueryKey,
		queryFn: () => fetchClaudeAccounts(false),
		retry: 1,
		refetchOnWindowFocus: true,
	});
}

export function useRefreshClaudeAccounts() {
	const queryClient = useQueryClient();
	return useCallback(
		() =>
			queryClient
				.fetchQuery({ queryKey: claudeAccountsQueryKey, queryFn: () => fetchClaudeAccounts(true), staleTime: 0 })
				.catch(() => undefined),
		[queryClient],
	);
}

function useInvalidatingMutation<TInput, TOutput>(fn: (input: TInput) => Promise<TOutput>) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSettled: () => {
			void queryClient.invalidateQueries({ queryKey: claudeAccountsQueryKey });
		},
	});
}

export function useCreateClaudeAccount() {
	return useInvalidatingMutation(async (label: string) => {
		const { data, error } = await apiClient.POST("/api/v1/claude-accounts", { body: { label } });
		if (error) throw error;
		if (!data) throw new Error("Daemon returned no account");
		return data.account;
	});
}

export function useRenameClaudeAccount() {
	return useInvalidatingMutation(async ({ id, label }: { id: string; label: string }) => {
		const { data, error } = await apiClient.PATCH("/api/v1/claude-accounts/{accountId}", {
			params: { path: { accountId: id } },
			body: { label },
		});
		if (error) throw error;
		return data?.account;
	});
}

export function useDeleteClaudeAccount() {
	return useInvalidatingMutation(async (id: string) => {
		const { error } = await apiClient.DELETE("/api/v1/claude-accounts/{accountId}", {
			params: { path: { accountId: id } },
		});
		if (error) throw error;
	});
}

export function usePreferClaudeAccount() {
	return useInvalidatingMutation(async (id: string) => {
		const { error } = await apiClient.POST("/api/v1/claude-accounts/{accountId}/prefer", {
			params: { path: { accountId: id } },
		});
		if (error) throw error;
	});
}

export function preferredClaudeAccountId(accounts: ClaudeAccount[] | undefined): string {
	return accounts?.find((account) => account.isPreferred)?.id ?? "default";
}

export function useRelinkClaudeAccount() {
	return useInvalidatingMutation(async (id: string) => {
		const { error } = await apiClient.POST("/api/v1/claude-accounts/{accountId}/relink", {
			params: { path: { accountId: id } },
		});
		if (error) throw error;
	});
}

export function useClaudeAccountLogin() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (id: string): Promise<ShellTerminal> => {
			const { data, error } = await apiClient.POST("/api/v1/claude-accounts/{accountId}/login", {
				params: { path: { accountId: id } },
				body: { ...paneGridBody() },
			});
			if (error) throw error;
			if (!data) throw new Error("Daemon returned no terminal");
			return toShellTerminal(data.shellTerminal);
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: shellTerminalsQueryKey });
			void queryClient.invalidateQueries({ queryKey: claudeAccountsQueryKey });
		},
	});
}
