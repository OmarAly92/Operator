import type { ProgramNotification, TerminalMux } from "./terminal-mux";

export const PROGRAM_FEED_RETRY_BASE_MS = 1_000;
export const PROGRAM_FEED_RETRY_MAX_MS = 30_000;
export const PROGRAM_TOAST_PREFIX = "program:";

export type ProgramNotificationEvent = Readonly<{ handleId: string } & ProgramNotification>;

export type ProgramFeedHandlers = Readonly<{
	onTitle: (handleId: string, title: string) => void;
	onNotification: (event: ProgramNotificationEvent) => void;
	onReset: () => void;
}>;

export type ProgramToast = Readonly<{ id: string; title: string; body?: string; type: "program" }>;

export function connectProgramFeed(createMux: () => TerminalMux, handlers: ProgramFeedHandlers): () => void {
	let disposed = false;
	let attempts = 0;
	let retryTimer: ReturnType<typeof setTimeout> | undefined;
	let current: { mux: TerminalMux; release: Array<() => void> } | null = null;

	const teardown = () => {
		const active = current;
		if (!active) return;
		current = null;
		for (const release of active.release) release();
		active.mux.dispose();
	};

	const connect = () => {
		if (disposed) return;
		const mux = createMux();
		const release: Array<() => void> = [];
		current = { mux, release };
		const offTitle = mux.onProgramTitle?.((handleId, title) => handlers.onTitle(handleId, title));
		if (offTitle) release.push(offTitle);
		const offNotification = mux.onProgramNotification?.((handleId, notification) =>
			handlers.onNotification({ handleId, ...notification }),
		);
		if (offNotification) release.push(offNotification);
		release.push(
			mux.onConnectionChange((state) => {
				if (state === "open") {
					attempts = 0;
					return;
				}
				if (current?.mux !== mux) return;
				teardown();
				handlers.onReset();
				const delay = Math.min(PROGRAM_FEED_RETRY_BASE_MS * 2 ** attempts, PROGRAM_FEED_RETRY_MAX_MS);
				attempts += 1;
				retryTimer = setTimeout(() => {
					retryTimer = undefined;
					connect();
				}, delay);
			}),
		);
	};

	connect();
	return () => {
		disposed = true;
		if (retryTimer) clearTimeout(retryTimer);
		retryTimer = undefined;
		teardown();
		handlers.onReset();
	};
}

export function programToast(event: ProgramNotificationEvent, fallbackTitle: string, sequence: number): ProgramToast {
	const title = event.title.trim() || fallbackTitle;
	const body = event.body.trim();
	return {
		id: `${PROGRAM_TOAST_PREFIX}${event.handleId}:${sequence}`,
		title,
		...(body ? { body } : {}),
		type: "program",
	};
}

export function programToastHandle(id: string): string | null {
	if (!id.startsWith(PROGRAM_TOAST_PREFIX)) return null;
	const rest = id.slice(PROGRAM_TOAST_PREFIX.length);
	const cut = rest.lastIndexOf(":");
	return cut > 0 ? rest.slice(0, cut) : null;
}
