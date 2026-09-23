import { useQuery } from "@tanstack/react-query";
import type { components } from "../../api/schema";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { nativeShellBridgePresent } from "../lib/bridge";
import { sessionIsActive, type WorkspaceSession } from "../types/workspace";

type ReviewsResponse = components["schemas"]["ListReviewsResponse"];
type ReviewerTerminalTarget = { handleId: string; harness: string };

function reviewerTerminalFromReviews(data?: ReviewsResponse): ReviewerTerminalTarget | undefined {
	const handleId = data?.reviewerHandleId?.trim();
	if (!handleId) return undefined;
	const latest = data?.reviews?.find((review) => review.latestRun)?.latestRun;
	return { handleId, harness: data?.reviewerHarness || latest?.harness || "codex" };
}

function useReviewsQuery(session: WorkspaceSession | undefined, enabled: boolean) {
	const sessionId = session?.id ?? "";
	return useQuery({
		queryKey: ["session-reviews", sessionId],
		enabled,
		refetchInterval: (current) => {
			const data = current.state.data as ReviewsResponse | undefined;
			return data?.reviews?.some((review) => review.status === "running") ? 2500 : false;
		},
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/sessions/{sessionId}/reviews", {
				params: { path: { sessionId } },
			});
			if (error) throw new Error(apiErrorMessage(error, "Unable to load reviews"));
			return data ?? ({ reviewerHandleId: "", reviews: [], runs: [] } satisfies ReviewsResponse);
		},
	});
}

export function useSessionReviewer(session?: WorkspaceSession): {
	reviewer: ReviewerTerminalTarget | undefined;
	settled: boolean;
} {
	const enabled = Boolean(nativeShellBridgePresent() && session && sessionIsActive(session) && session.prs.length > 0);
	const query = useReviewsQuery(session, enabled);
	const reviewer = session && sessionIsActive(session) ? reviewerTerminalFromReviews(query.data) : undefined;
	return { reviewer, settled: !enabled || query.isSuccess };
}
