import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiClient, apiErrorMessage, getApiBaseUrl } from "../lib/api-client";
import { assembleBlocks, resolveStranded } from "../lib/block-assembly";
import { usesPreviewWorkspaceData } from "../lib/preview-mode";
import { blocksCoverHarness, type SessionBlock } from "../lib/session-block";
import { createTerminalMux, muxUrlFromApiBase, type BlockEventView, type TerminalMux } from "../lib/terminal-mux";

export const sessionBlocksQueryKey = (sessionId: string) => ["session-blocks", sessionId] as const;

// The client holds a window, not the whole log. BLOCK_WINDOW is the live cap;
// paging back grows it by exactly what was fetched, up to BLOCK_MAX_WINDOW, so
// a fetched page can always be held rather than evicted the moment it lands.
export const BLOCK_WINDOW = 400;
export const BLOCK_PAGE = 100;
export const BLOCK_MAX_WINDOW = 1200;

const SESSION_ENDED_REASON = "Session ended before this finished";

export type UseSessionBlocksOptions = {
	enabled: boolean;
	harness?: string;
	sessionEnded?: boolean;
	/** Test seam: build the mux client. Defaults to a fresh socket against the current API base. */
	createMux?: () => TerminalMux;
};

export type SessionBlocksResult = {
	blocks: SessionBlock[];
	isLoading: boolean;
	isLoadingOlder: boolean;
	hasOlder: boolean;
	error?: string;
	loadOlder: () => void;
	refetch: () => void;
};

function defaultCreateMux(): TerminalMux {
	return createTerminalMux(muxUrlFromApiBase(getApiBaseUrl()));
}

async function fetchBlocks(
	sessionId: string,
	cursor: { afterSeq?: number; beforeSeq?: number; limit?: number },
): Promise<BlockEventView[]> {
	const { data, error } = await apiClient.GET("/api/v1/sessions/{sessionId}/blocks", {
		params: { path: { sessionId }, query: cursor },
	});
	if (error) throw new Error(apiErrorMessage(error, "Unable to load this session's blocks"));
	return data?.blocks ?? [];
}

export function useSessionBlocks(sessionId: string, options: UseSessionBlocksOptions): SessionBlocksResult {
	const queryClient = useQueryClient();
	const supported = options.enabled && sessionId !== "" && blocksCoverHarness(options.harness);

	const eventsRef = useRef(new Map<number, BlockEventView>());
	const capacityRef = useRef(BLOCK_WINDOW);
	const inFlightRef = useRef(false);

	const [revision, setRevision] = useState(0);
	const [isLoading, setIsLoading] = useState(false);
	const [isLoadingOlder, setIsLoadingOlder] = useState(false);
	const [hasOlder, setHasOlder] = useState(true);
	const [error, setError] = useState<string | undefined>(undefined);

	const merge = useCallback((records: BlockEventView[]) => {
		const events = eventsRef.current;
		for (const record of records) {
			if (!Number.isFinite(record.seq)) continue;
			events.set(record.seq, record);
		}
		while (events.size > capacityRef.current) {
			let oldest: number | undefined;
			for (const seq of events.keys()) {
				if (oldest === undefined || seq < oldest) oldest = seq;
			}
			if (oldest === undefined) break;
			events.delete(oldest);
		}
		setRevision((value) => value + 1);
	}, []);

	const refetch = useCallback(() => {
		if (!supported || usesPreviewWorkspaceData) return;
		const highest = [...eventsRef.current.keys()].reduce<number | undefined>(
			(max, seq) => (max === undefined || seq > max ? seq : max),
			undefined,
		);
		setIsLoading(true);
		void fetchBlocks(sessionId, highest === undefined ? {} : { afterSeq: highest })
			.then((records) => {
				setError(undefined);
				merge(records);
			})
			.catch((cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)))
			.finally(() => setIsLoading(false));
	}, [merge, sessionId, supported]);

	const loadOlder = useCallback(() => {
		if (!supported || usesPreviewWorkspaceData) return;
		if (inFlightRef.current || !hasOlder) return;
		const lowest = [...eventsRef.current.keys()].reduce<number | undefined>(
			(min, seq) => (min === undefined || seq < min ? seq : min),
			undefined,
		);
		if (lowest === undefined) return;

		const headroom = BLOCK_MAX_WINDOW - capacityRef.current;
		if (headroom <= 0) {
			setHasOlder(false);
			return;
		}

		inFlightRef.current = true;
		setIsLoadingOlder(true);
		void fetchBlocks(sessionId, { beforeSeq: lowest, limit: Math.min(BLOCK_PAGE, headroom) })
			.then((records) => {
				setError(undefined);
				if (records.length === 0) {
					setHasOlder(false);
					return;
				}
				capacityRef.current = Math.min(BLOCK_MAX_WINDOW, capacityRef.current + records.length);
				merge(records);
			})
			.catch((cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)))
			.finally(() => {
				inFlightRef.current = false;
				setIsLoadingOlder(false);
			});
	}, [hasOlder, merge, sessionId, supported]);

	const createMuxRef = useRef(options.createMux);
	createMuxRef.current = options.createMux;
	const queryClientRef = useRef(queryClient);
	queryClientRef.current = queryClient;
	useEffect(() => {
		if (!supported) return;
		const mux = (createMuxRef.current ?? defaultCreateMux)();
		const off = mux.onBlock(sessionId, (record) => merge([record]));
		mux.subscribeBlocks(sessionId);
		refetch();
		return () => {
			off();
			mux.unsubscribeBlocks(sessionId);
			mux.dispose();
			eventsRef.current = new Map();
			capacityRef.current = BLOCK_WINDOW;
			queryClientRef.current.removeQueries({ queryKey: sessionBlocksQueryKey(sessionId) });
		};
		// refetch is stable for a given session; re-running on its identity would
		// tear the socket down on every render.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [merge, sessionId, supported]);

	const blocks = useMemo(() => {
		void revision;
		const assembled = assembleBlocks(eventsRef.current.values());
		return options.sessionEnded ? resolveStranded(assembled, SESSION_ENDED_REASON) : assembled;
	}, [options.sessionEnded, revision]);

	return { blocks, isLoading, isLoadingOlder, hasOlder, error, loadOlder, refetch };
}
