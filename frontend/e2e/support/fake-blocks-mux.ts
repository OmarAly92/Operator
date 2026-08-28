import type { Page } from "@playwright/test";

export type FakeBlocksMuxStats = {
	closes: Record<string, number>;
	emit: Record<string, number>;
	opens: Record<string, number>;
	sockets: number;
	subscriptions: Record<string, number>;
	unsubscribes: Record<string, number>;
};

export type FakeBlocksMuxController = {
	emit: (sessionId: string, record: unknown) => void;
	stats: () => FakeBlocksMuxStats;
};

export type InstallFakeBlocksMuxOptions = {
	virtualizationThreshold?: number;
};

declare global {
	interface Window {
		__aoFakeBlocksMux?: FakeBlocksMuxController;
		__OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD?: number;
	}
}

export async function installFakeBlocksMux(
	page: Page,
	options: InstallFakeBlocksMuxOptions = {},
): Promise<void> {
	const threshold = options.virtualizationThreshold;
	await page.addInitScript((threshold) => {
		if (typeof threshold === "number" && Number.isFinite(threshold)) {
			(globalThis as unknown as { __OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD: number })
				.__OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD = threshold;
		}

		type Listener = (event: Event) => void;
		type ClientFrame = {
			ch: string;
			id?: string;
			type: string;
		};

		const sockets: FakeWebSocket[] = [];
		const opens: Record<string, number> = {};
		const closes: Record<string, number> = {};
		const subscriptions: Record<string, number> = {};
		const unsubscribes: Record<string, number> = {};
		const emits: Record<string, number> = {};

		const isBlocksMux = (url: string): boolean => {
			try {
				return new URL(url, window.location.href).pathname === "/mux";
			} catch {
				return false;
			}
		};

		class FakeWebSocket {
			static readonly CLOSED = 3;
			static readonly CLOSING = 2;
			static readonly CONNECTING = 0;
			static readonly OPEN = 1;

			readonly url: string;
			readyState = FakeWebSocket.CONNECTING;
			private readonly subscriptions = new Set<string>();
			private readonly listeners = new Map<string, Set<Listener>>();

			constructor(url: string | URL) {
				this.url = String(url);
				sockets.push(this);
				queueMicrotask(() => {
					if (this.readyState !== FakeWebSocket.CONNECTING) return;
					this.readyState = FakeWebSocket.OPEN;
					this.dispatch("open", new Event("open"));
				});
			}

			addEventListener(type: string, listener: EventListenerOrEventListenerObject): void {
				const callback: Listener =
					typeof listener === "function" ? listener : (event) => listener.handleEvent(event);
				const set = this.listeners.get(type) ?? new Set<Listener>();
				set.add(callback);
				this.listeners.set(type, set);
			}

			removeEventListener(type: string, listener: EventListenerOrEventListenerObject): void {
				if (typeof listener !== "function") return;
				this.listeners.get(type)?.delete(listener);
			}

			send(raw: string): void {
				let frame: ClientFrame;
				try {
					frame = JSON.parse(raw) as ClientFrame;
				} catch {
					return;
				}
				if (frame.ch !== "blocks" || typeof frame.id !== "string") return;
				const sessionId = frame.id;
				if (frame.type === "subscribe") {
					this.subscriptions.add(sessionId);
					opens[sessionId] = (opens[sessionId] ?? 0) + 1;
					subscriptions[sessionId] = (subscriptions[sessionId] ?? 0) + 1;
					return;
				}
				if (frame.type === "unsubscribe") {
					this.subscriptions.delete(sessionId);
					unsubscribes[sessionId] = (unsubscribes[sessionId] ?? 0) + 1;
					closes[sessionId] = (closes[sessionId] ?? 0) + 1;
				}
			}

			close(): void {
				if (this.readyState >= FakeWebSocket.CLOSING) return;
				this.readyState = FakeWebSocket.CLOSED;
				for (const sessionId of this.subscriptions) {
					closes[sessionId] = (closes[sessionId] ?? 0) + 1;
				}
				this.subscriptions.clear();
				this.dispatch("close", new CloseEvent("close"));
			}

			emit(sessionId: string, record: unknown): void {
				if (this.readyState !== FakeWebSocket.OPEN || !this.subscriptions.has(sessionId)) return;
				emits[sessionId] = (emits[sessionId] ?? 0) + 1;
				this.message({ ch: "blocks", id: sessionId, type: "block", block: record });
			}

			private message(frame: Record<string, unknown>): void {
				this.dispatch("message", new MessageEvent("message", { data: JSON.stringify(frame) }));
			}

			private dispatch(type: string, event: Event): void {
				for (const listener of this.listeners.get(type) ?? []) listener(event);
			}
		}

		(window as unknown as { WebSocket: typeof WebSocket }).WebSocket =
			FakeWebSocket as unknown as typeof WebSocket;
		window.__aoFakeBlocksMux = {
			emit: (sessionId, record) => {
				for (const socket of sockets) {
					if (!isBlocksMux(socket.url)) continue;
					socket.emit(sessionId, record);
				}
			},
			stats: () => ({
				closes: structuredClone(closes),
				emit: structuredClone(emits),
				opens: structuredClone(opens),
				sockets: sockets.filter(
					(socket) => isBlocksMux(socket.url) && socket.readyState < FakeWebSocket.CLOSED,
				).length,
				subscriptions: structuredClone(subscriptions),
				unsubscribes: structuredClone(unsubscribes),
			}),
		};
	}, threshold);
}
