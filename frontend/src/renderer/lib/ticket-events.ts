import type { QueryClient } from "@tanstack/react-query";
import { getApiBaseUrl, hasTrustedApiBaseUrl, subscribeApiBaseUrl } from "./api-client";

const INVALIDATE_DEBOUNCE_MS = 150;
const SSE_RETRY_MS = 5_000;
const EVENTSOURCE_CLOSED = 2;

type TicketStream = {
	refs: number;
	disposed: boolean;
	source?: EventSource;
	sourceBaseUrl?: string;
	debounce?: ReturnType<typeof setTimeout>;
	retry?: ReturnType<typeof setTimeout>;
	disconnectBaseUrl: () => void;
	connect: () => void;
	dispose: () => void;
};

const streams = new Map<string, TicketStream>();

export function subscribeTicketChanges(projectId: string, queryClient: QueryClient): () => void {
	let stream = streams.get(projectId);
	if (!stream) {
		stream = createTicketStream(projectId, queryClient);
		streams.set(projectId, stream);
	}
	stream.refs += 1;
	return () => {
		const current = streams.get(projectId);
		if (!current) return;
		current.refs -= 1;
		if (current.refs > 0) return;
		current.dispose();
		streams.delete(projectId);
	};
}

function createTicketStream(projectId: string, queryClient: QueryClient): TicketStream {
	const stream = {} as TicketStream;
	const invalidate = () => {
		if (stream.debounce) clearTimeout(stream.debounce);
		stream.debounce = setTimeout(() => {
			void queryClient.invalidateQueries({ queryKey: ["tickets", projectId] });
		}, INVALIDATE_DEBOUNCE_MS);
	};
	const scheduleRetry = () => {
		if (stream.disposed || stream.retry) return;
		stream.retry = setTimeout(() => {
			stream.retry = undefined;
			stream.connect();
		}, SSE_RETRY_MS);
	};
	stream.refs = 0;
	stream.disposed = false;
	stream.connect = () => {
		if (stream.disposed || typeof EventSource === "undefined") return;
		if (!hasTrustedApiBaseUrl()) {
			stream.source?.close();
			stream.source = undefined;
			stream.sourceBaseUrl = undefined;
			return;
		}
		const baseUrl = getApiBaseUrl();
		if (stream.source && stream.sourceBaseUrl === baseUrl && stream.source.readyState !== EVENTSOURCE_CLOSED) return;
		stream.source?.close();
		stream.sourceBaseUrl = baseUrl;
		try {
			const source = new EventSource(
				`${baseUrl.replace(/\/+$/, "")}/api/v1/projects/${encodeURIComponent(projectId)}/tickets/events`,
			);
			stream.source = source;
			source.onopen = () => {
				if (!stream.disposed && stream.source === source) invalidate();
			};
			source.onerror = () => {
				if (!stream.disposed && stream.source === source && source.readyState === EVENTSOURCE_CLOSED) scheduleRetry();
			};
			source.addEventListener("tickets_changed", () => {
				if (!stream.disposed && stream.source === source) invalidate();
			});
		} catch {
			stream.source = undefined;
			scheduleRetry();
		}
	};
	stream.disconnectBaseUrl = subscribeApiBaseUrl(stream.connect);
	stream.dispose = () => {
		stream.disposed = true;
		if (stream.debounce) clearTimeout(stream.debounce);
		if (stream.retry) clearTimeout(stream.retry);
		stream.disconnectBaseUrl();
		stream.source?.close();
	};
	stream.connect();
	return stream;
}
