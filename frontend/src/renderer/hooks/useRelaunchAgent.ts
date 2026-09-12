import { useMutation, useMutationState, useQueryClient } from "@tanstack/react-query";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { workspaceQueryKey } from "./useWorkspaceQuery";

export type RelaunchAgentInput = {
	sessionId: string;
	/** Re-deliver the session's saved task prompt into the new conversation. */
	keepPrompt: boolean;
};

export const relaunchAgentMutationKey = ["relaunch-agent"] as const;

export function useRelaunchAgentPending(sessionId: string): boolean {
	const pending = useMutationState<boolean>({
		filters: { mutationKey: relaunchAgentMutationKey, status: "pending" },
		select: (mutation) =>
			(mutation.state.variables as RelaunchAgentInput | undefined)?.sessionId === sessionId,
	});
	return pending.some(Boolean);
}

export function useRelaunchAgent() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationKey: relaunchAgentMutationKey,
		mutationFn: async ({ sessionId, keepPrompt }: RelaunchAgentInput) => {
			const { data, error, response } = await apiClient.POST(
				"/api/v1/sessions/{sessionId}/relaunch-agent",
				{
					params: { path: { sessionId } },
					body: { keepPrompt },
				},
			);
			if (error) {
				const fallback = response
					? `Failed to relaunch agent (${response.status})`
					: "Failed to relaunch agent";
				throw new Error(apiErrorMessage(error, fallback));
			}
			return data;
		},
		// The daemon replaces the agent process either way; a failure after the
		// kill still changes the session projection, so refresh regardless.
		onSettled: async () => {
			await queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
		},
	});
}
