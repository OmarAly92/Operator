import { useQuery } from "@tanstack/react-query";
import type { components } from "../../api/schema";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { base64ToBytes } from "../lib/terminal-mux";
import type { TerminalTarget } from "../types/terminal";
import { shellTerminalsQueryOptions } from "./useShellTerminals";

type TerminalBlockView = components["schemas"]["TerminalBlockView"];

export type ShellHistoryBlock = {
	sourceId: string;
	rawOutput: Uint8Array;
	exitCode: number | null;
	truncatedLines: number;
	truncatedBytes: number;
};

export type ShellTerminalBlocksResult = {
	blocks: ShellHistoryBlock[];
	isLoading: boolean;
	error?: string;
	durableBlocks: boolean;
};

export const shellTerminalBlocksQueryKey = (handleId: string) =>
	["shell-terminal-blocks", handleId] as const;

const EMPTY: ShellHistoryBlock[] = [];
const HISTORY_LIMIT = 100;

function toHistoryBlock(view: TerminalBlockView): ShellHistoryBlock {
	return {
		sourceId: view.sourceId,
		rawOutput: base64ToBytes(view.rawOutput),
		exitCode: view.exitCode,
		truncatedLines: view.truncatedLines,
		truncatedBytes: view.truncatedBytes,
	};
}

async function fetchShellTerminalBlocks(handleId: string): Promise<ShellHistoryBlock[]> {
	const { data, error } = await apiClient.GET("/api/v1/shell-terminals/{handleId}/blocks", {
		params: { path: { handleId }, query: { limit: HISTORY_LIMIT } },
	});
	if (error) throw new Error(apiErrorMessage(error, "Unable to load this shell's block history"));
	return (data ?? []).map(toHistoryBlock);
}

export function useShellTerminalBlocks(target: TerminalTarget | undefined): ShellTerminalBlocksResult {
	const isShell = target?.kind === "shell";
	const handleId = isShell ? target.handleId : undefined;
	const shellsQuery = useQuery({ ...shellTerminalsQueryOptions, enabled: false });

	const query = useQuery({
		queryKey: shellTerminalBlocksQueryKey(handleId ?? ""),
		queryFn: () => fetchShellTerminalBlocks(handleId as string),
		enabled: isShell,
		retry: false,
		staleTime: Number.POSITIVE_INFINITY,
		gcTime: 0,
	});

	const shell = isShell && handleId ? shellsQuery.data?.find((entry) => entry.handleId === handleId) : undefined;
	const durableBlocks = shell?.durableBlocks ?? true;

	return {
		blocks: query.data ?? EMPTY,
		isLoading: isShell && query.isLoading,
		error: query.error ? apiErrorMessage(query.error, "Unable to load this shell's block history") : undefined,
		durableBlocks,
	};
}
