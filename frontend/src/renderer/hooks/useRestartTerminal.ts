import { useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { paneGridBody } from "../lib/pane-grid";
import { workspaceQueryKey } from "./useWorkspaceQuery";

export type RestartTerminalResult = { status: "success" } | { status: "error"; message: string };

export function useRestartTerminal(): (sessionId: string) => Promise<RestartTerminalResult> {
	const queryClient = useQueryClient();

	return useCallback(
		async (sessionId: string) => {
			try {
				const { error } = await apiClient.POST("/api/v1/sessions/{sessionId}/restart-terminal", {
					params: { path: { sessionId } },
					body: paneGridBody(),
				});
				if (error) {
					return { status: "error", message: apiErrorMessage(error, "Unable to restart terminal") };
				}
				await queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
				return { status: "success" };
			} catch (err) {
				return {
					status: "error",
					message: err instanceof Error ? err.message : "Unable to restart terminal",
				};
			}
		},
		[queryClient],
	);
}
