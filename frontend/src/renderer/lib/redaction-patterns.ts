import type { SecretPattern } from "@operator/terminal-core";
import { apiClient, apiErrorMessage } from "./api-client";

export const redactionPatternsQueryKey = ["redaction", "patterns"] as const;

/**
 * The daemon's own built-in secret shapes. The desktop terminal paints bytes
 * straight off the PTY, which the daemon's redaction never sees, so the shapes
 * travel to the client and the renderer masks exactly what the daemon does.
 */
export async function fetchRedactionPatterns(): Promise<SecretPattern[]> {
	const { data, error } = await apiClient.GET("/api/v1/redaction/patterns", {});
	if (error) throw new Error(apiErrorMessage(error));
	return (data?.patterns ?? []).map((pattern) => ({ source: pattern.source, flags: pattern.flags }));
}
