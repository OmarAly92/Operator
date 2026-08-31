import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import type { components } from "../../api/schema";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { base64ToBytes } from "../lib/terminal-mux";
import type { TerminalTarget } from "../types/terminal";
import { shellTerminalsQueryKey, type ShellTerminal } from "./useShellTerminals";

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
	const queryClient = useQueryClient();
	const isShell = target?.kind === "shell";
	const handleId = isShell ? target.handleId : undefined;

	const query = useQuery({
		queryKey: shellTerminalBlocksQueryKey(handleId ?? ""),
		queryFn: () => fetchShellTerminalBlocks(handleId as string),
		enabled: isShell,
		retry: 1,
		staleTime: Number.POSITIVE_INFINITY,
		gcTime: 0,
	});

	const durableBlocks = useMemo(() => {
		if (!isShell || !handleId) return true;
		const shells = queryClient.getQueryData<ShellTerminal[]>(shellTerminalsQueryKey);
		const shell = shells?.find((entry) => entry.handleId === handleId);
		return shell?.durableBlocks ?? true;
	}, [handleId, isShell, queryClient, query.dataUpdatedAt]);

	return {
		blocks: query.data ?? EMPTY,
		isLoading: isShell && query.isLoading,
		error: query.error ? apiErrorMessage(query.error, "Unable to load this shell's block history") : undefined,
		durableBlocks,
	};
}
