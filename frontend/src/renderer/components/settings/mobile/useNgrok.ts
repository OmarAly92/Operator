import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { UseMutationResult } from "@tanstack/react-query";

import { apiClient, apiErrorMessage } from "../../../lib/api-client";
import { mobileStatusQueryKey } from "../../../lib/mobile-status";
import type { components } from "../../../../api/schema";

export type NgrokStatus = components["schemas"]["MobileNgrokStatus"];
export type NgrokAccount = components["schemas"]["MobileNgrokAccount"];
export type NgrokDiagnosis = components["schemas"]["MobileNgrokDiagnosis"];

export const ngrokStatusQueryKey = ["mobile-ngrok"] as const;
export const ngrokAccountQueryKey = ["mobile-ngrok-account"] as const;

export interface Ngrok {
	status: NgrokStatus | undefined;
	account: NgrokAccount | undefined;
	accountLoading: boolean;
	removeAuthtoken: UseMutationResult<unknown, Error, void>;
	setApiKey: UseMutationResult<unknown, Error, string>;
	removeApiKey: UseMutationResult<unknown, Error, void>;
	mintCredential: UseMutationResult<unknown, Error, void>;
	revokeCredential: UseMutationResult<unknown, Error, string>;
	setDomain: UseMutationResult<unknown, Error, string>;
	diagnose: UseMutationResult<NgrokDiagnosis, Error, void>;
}

export function useNgrok(active: boolean): Ngrok {
	const queryClient = useQueryClient();

	const statusQuery = useQuery({
		queryKey: ngrokStatusQueryKey,
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/mobile/tunnel/ngrok");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		enabled: active,
		refetchInterval: 2000,
	});

	const status = statusQuery.data;

	const accountQuery = useQuery({
		queryKey: ngrokAccountQueryKey,
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/mobile/tunnel/ngrok/account");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		enabled: active && Boolean(status?.apiKey?.present),
		refetchInterval: 30000,
	});

	const invalidate = () => {
		void queryClient.invalidateQueries({ queryKey: ngrokStatusQueryKey });
		void queryClient.invalidateQueries({ queryKey: ngrokAccountQueryKey });
		void queryClient.invalidateQueries({ queryKey: mobileStatusQueryKey });
	};

	const removeAuthtoken = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.DELETE("/api/v1/mobile/tunnel/authtoken");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const setApiKey = useMutation({
		mutationFn: async (key: string) => {
			const { data, error } = await apiClient.PUT("/api/v1/mobile/tunnel/ngrok/api-key", { body: { key } });
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const removeApiKey = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.DELETE("/api/v1/mobile/tunnel/ngrok/api-key");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const mintCredential = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/ngrok/account/credential");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const revokeCredential = useMutation({
		mutationFn: async (id: string) => {
			const { data, error } = await apiClient.DELETE("/api/v1/mobile/tunnel/ngrok/account/credential/{id}", {
				params: { path: { id } },
			});
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const setDomain = useMutation({
		mutationFn: async (domain: string) => {
			const { data, error } = await apiClient.PUT("/api/v1/mobile/tunnel/ngrok/domain", { body: { domain } });
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const diagnose = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/ngrok/diagnose");
			if (error) throw new Error(apiErrorMessage(error));
			return data as NgrokDiagnosis;
		},
		onSuccess: invalidate,
	});

	return {
		status,
		account: accountQuery.data,
		accountLoading: accountQuery.isLoading,
		removeAuthtoken,
		setApiKey,
		removeApiKey,
		mintCredential,
		revokeCredential,
		setDomain,
		diagnose,
	};
}
