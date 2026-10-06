import { useQuery } from "@tanstack/react-query";
import type { components } from "../../api/schema";
import { apiClient, apiErrorMessage } from "../lib/api-client";

export type ProjectBranches = components["schemas"]["ProjectBranches"];
export type ProjectBranch = components["schemas"]["ProjectBranch"];

export const projectBranchesQueryKey = (projectId: string) => ["project-branches", projectId] as const;

export function useProjectBranches(projectId: string | undefined, enabled: boolean) {
	return useQuery({
		queryKey: projectBranchesQueryKey(projectId ?? ""),
		enabled: Boolean(projectId) && enabled,
		refetchOnMount: "always",
		queryFn: async (): Promise<ProjectBranches> => {
			const { data, error } = await apiClient.GET("/api/v1/projects/{id}/branches", {
				params: { path: { id: projectId as string } },
			});
			if (error) throw new Error(apiErrorMessage(error));
			return { current: data?.current ?? "", branches: data?.branches ?? [] };
		},
	});
}
