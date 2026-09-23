import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiClient, apiErrorMessage } from "../lib/api-client";

export const phoneAlertsQueryKey = ["phone-alerts"] as const;

export function usePhoneAlerts() {
	return useQuery({
		queryKey: phoneAlertsQueryKey,
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/phone-alerts");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		refetchInterval: 15_000,
	});
}

export function useTestPhoneAlert() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/phone-alerts/test");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSettled: () => queryClient.invalidateQueries({ queryKey: phoneAlertsQueryKey }),
	});
}
