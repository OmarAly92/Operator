// WebSocket client for the daemon's terminal multiplexer (`/mux`).
//
// The wire protocol mirrors backend/internal/terminal/protocol.go: a single
// JSON-framed socket tagged by channel ("ch"). Terminal payloads carry the PTY
// bytes base64-encoded in `data` because PTY output is arbitrary bytes that a
// raw JSON string cannot represent.
//
//   ch "terminal" — per-pane byte stream keyed by an opaque runtime handle id
//     client → open{id,cols,rows} | data{id,data} | resize{id,cols,rows,force?} | close{id}
//     server → opened{id} | data{id,data} | exited{id} | error{id?,error} | health{id,health}
//   ch "system"   — ping/pong liveness
//   ch "blocks"   — normalized session block events
//     client → subscribe{id} | unsubscribe{id}
//     server → block{id,block}
//
// The renderer connects directly to the loopback daemon (same host/port as the
// REST API, path `/mux`); it is not proxied through the shell.

import type { components } from "../../api/schema";

export type BlockEventView = components["schemas"]["BlockEventView"];

type ServerFrame = {
	ch: string;
	id?: string;
	type: string;
	data?: string;
	error?: string;
	health?: string;
	block?: unknown;
	blockType?: string;
	terminalBlock?: unknown;
};

export type TerminalBlockFrame = {
	sourceId: string;
	sessionId?: string;
	exitCode: number | null;
	startedAt: string;
	finishedAt: string;
};

// ---- pure framing helpers (unit-tested in terminal-mux.test.ts) ----

export function bytesToBase64(bytes: Uint8Array): string {
	let binary = "";
	const chunk = 0x8000;
	for (let i = 0; i < bytes.length; i += chunk) {
		binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
	}
	return btoa(binary);
}

export function base64ToBytes(b64: string): Uint8Array {
	const binary = atob(b64);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i += 1) {
		bytes[i] = binary.charCodeAt(i);
	}
	return bytes;
}

export function openFrame(id: string, cols: number, rows: number, history = false): string {
	return JSON.stringify({
		ch: "terminal",
		type: "open",
		id,
		cols,
		rows,
		...(history ? { history: true } : {}),
	});
}

export function dataFrame(id: string, bytes: Uint8Array): string {
	return JSON.stringify({ ch: "terminal", type: "data", id, data: bytesToBase64(bytes) });
}

export function resizeFrame(id: string, cols: number, rows: number, force = false): string {
	return JSON.stringify({
		ch: "terminal",
		type: "resize",
		id,
		cols,
		rows,
		...(force ? { force: true } : {}),
	});
}

export function closeFrame(id: string): string {
	return JSON.stringify({ ch: "terminal", type: "close", id });
}

export function ackFrame(id: string, bytes: number): string {
	return JSON.stringify({ ch: "terminal", type: "ack", id, bytes });
}

export function blocksSubscribeFrame(sessionId: string): string {
	return JSON.stringify({ ch: "blocks", type: "subscribe", id: sessionId });
}

export function blocksUnsubscribeFrame(sessionId: string): string {
	return JSON.stringify({ ch: "blocks", type: "unsubscribe", id: sessionId });
}

export function terminalBlocksSubscribeFrame(handleId: string): string {
	return JSON.stringify({ ch: "blocks", type: "subscribe", id: handleId, blockType: "terminal_block" });
}

export function terminalBlocksUnsubscribeFrame(handleId: string): string {
	return JSON.stringify({ ch: "blocks", type: "unsubscribe", id: handleId, blockType: "terminal_block" });
}

function pingFrame(): string {
	return JSON.stringify({ ch: "system", type: "ping" });
}

// Derive the ws(s)://.../mux URL from the REST API base. The mux is mounted at
// the router root (backend router.go), not under /api/v1.
export function muxUrlFromApiBase(apiBaseUrl: string): string {
	if (apiBaseUrl === "" && typeof window !== "undefined") {
		const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
		return `${protocol}//${window.location.host}/mux`;
	}

	// http://host → ws://host and https://host → wss://host (the trailing "s" is left
	// in place by the anchored replace). apiBaseUrl is the host root (e.g.
	// http://127.0.0.1:4317); strip any trailing slash before appending /mux.
	const ws = apiBaseUrl.replace(/^http/i, "ws");
	return `${ws.replace(/\/+$/, "")}/mux`;
}

type DataListener = (bytes: Uint8Array) => void;
type ExitListener = () => void;
type OpenedListener = () => void;
type ErrorListener = (message: string) => void;
export type TerminalHealth = "ok" | "hung";
type HealthListener = (health: TerminalHealth) => void;
type BlockListener = (block: BlockEventView) => void;
type TerminalBlockListener = (block: TerminalBlockFrame) => void;

export type MuxConnectionState = "open" | "closed";
type ConnectionListener = (state: MuxConnectionState) => void;

export type TerminalMux = {
	/** Open a PTY pane for the given runtime/session id at an initial size. */
	open: (id: string, cols: number, rows: number, history?: boolean) => void;
	/** Forward user-originated keyboard/paste data to the pane. */
	sendInput: (id: string, input: string) => void;
	/** Resize normally, or explicitly re-signal an unchanged grid for recovery. */
	resize: (id: string, cols: number, rows: number, force?: boolean) => void;
	close: (id: string) => void;
	ack: (id: string, bytes: number) => void;
	onData: (id: string, listener: DataListener) => () => void;
	onExit: (id: string, listener: ExitListener) => () => void;
	/** Server ack that the pane is attached; the output replay follows it. */
	onOpened: (id: string, listener: OpenedListener) => () => void;
	/**
	 * Server `error` frames. A frame carrying a pane id reaches that pane's
	 * listeners; an id-less frame is connection-scoped and reaches every error
	 * listener.
	 */
	onError: (id: string, listener: ErrorListener) => () => void;
	onHealth: (id: string, listener: HealthListener) => () => void;
	/** Ask the daemon to push this session's normalized block events. */
	subscribeBlocks: (sessionId: string) => void;
	/** Stop that push. The daemon drops the subscription; listeners are separate. */
	unsubscribeBlocks: (sessionId: string) => void;
	/** Server `block` frames for one session id. */
	onBlock: (sessionId: string, listener: BlockListener) => () => void;
	onTerminalBlock: (handleId: string, listener: TerminalBlockListener) => () => void;
	/** Socket-level state: "open" on connect, "closed" on close or socket error. */
	onConnectionChange: (listener: ConnectionListener) => () => void;
	/** Close the socket and drop all listeners. */
	dispose: () => void;
};

export type TerminalMuxPool = {
	/**
	 * Acquire an independently disposable attachment lease over the shared
	 * browser-to-daemon mux socket.
	 */
	acquire: () => TerminalMux;
	/** Release the current shared socket and every listener (the pool stays reusable). */
	dispose: () => void;
};

const PING_INTERVAL_MS = 20_000;

function subscribeById<T>(map: Map<string, Set<T>>, id: string, listener: T): () => void {
	const set = map.get(id) ?? new Set<T>();
	set.add(listener);
	map.set(id, set);
	return () => set.delete(listener);
}

/**
 * Create a mux client over a single WebSocket. Frames sent before the socket is
 * OPEN are queued and flushed on connect. There is no auto-reconnect at this
 * layer: a dropped socket is reported through onConnectionChange("closed") and
 * the owner (useTerminalSession) decides whether to build a fresh client.
 */
export function createTerminalMux(url: string, WebSocketImpl: typeof WebSocket = WebSocket): TerminalMux {
	const socket = new WebSocketImpl(url);
	const encoder = new TextEncoder();
	const queue: string[] = [];
	const dataListeners = new Map<string, Set<DataListener>>();
	const exitListeners = new Map<string, Set<ExitListener>>();
	const openedListeners = new Map<string, Set<OpenedListener>>();
	const errorListeners = new Map<string, Set<ErrorListener>>();
	const healthListeners = new Map<string, Set<HealthListener>>();
	const blockListeners = new Map<string, Set<BlockListener>>();
	const terminalBlockListeners = new Map<string, Set<TerminalBlockListener>>();
	const connectionListeners = new Set<ConnectionListener>();
	let connectionState: MuxConnectionState | undefined;
	let pingTimer: ReturnType<typeof setInterval> | undefined;
	let disposed = false;

	// Dedupes transitions: a socket "error" event is typically followed by
	// "close", and only the first should notify.
	const setConnectionState = (next: MuxConnectionState) => {
		if (disposed || connectionState === next) return;
		connectionState = next;
		connectionListeners.forEach((listener) => listener(next));
	};

	const flush = () => {
		while (queue.length > 0) {
			const frame = queue.shift();
			if (frame !== undefined) socket.send(frame);
		}
	};

	const send = (frame: string) => {
		if (disposed) return;
		if (socket.readyState === WebSocketImpl.OPEN) {
			socket.send(frame);
		} else {
			queue.push(frame);
		}
	};

	socket.addEventListener("open", () => {
		if (disposed) return;
		flush();
		pingTimer = setInterval(() => send(pingFrame()), PING_INTERVAL_MS);
		setConnectionState("open");
	});

	socket.addEventListener("close", () => {
		setConnectionState("closed");
	});
	socket.addEventListener("error", () => {
		setConnectionState("closed");
	});

	socket.addEventListener("message", (event: MessageEvent) => {
		if (typeof event.data !== "string") return;
		let frame: ServerFrame;
		try {
			frame = JSON.parse(event.data) as ServerFrame;
		} catch {
			return;
		}
		if (frame.ch === "blocks") {
			if (frame.type !== "block" || frame.id === undefined) return;
			if (frame.blockType === "terminal_block") {
				const terminalBlock = frame.terminalBlock;
				if (typeof terminalBlock !== "object" || terminalBlock === null) return;
				terminalBlockListeners.get(frame.id)?.forEach((listener) => listener(terminalBlock as TerminalBlockFrame));
				return;
			}
			const block = frame.block;
			if (typeof block !== "object" || block === null) return;
			blockListeners.get(frame.id)?.forEach((listener) => listener(block as BlockEventView));
			return;
		}
		if (frame.ch !== "terminal") return;
		if (frame.type === "error") {
			const message = frame.error ?? "unknown terminal error";
			if (frame.id !== undefined) {
				errorListeners.get(frame.id)?.forEach((listener) => listener(message));
			} else {
				errorListeners.forEach((set) => set.forEach((listener) => listener(message)));
			}
			return;
		}
		if (frame.id === undefined) return;
		if (frame.type === "data" && frame.data) {
			dataListeners.get(frame.id)?.forEach((listener) => listener(base64ToBytes(frame.data as string)));
		} else if (frame.type === "exited") {
			exitListeners.get(frame.id)?.forEach((listener) => listener());
		} else if (frame.type === "opened") {
			openedListeners.get(frame.id)?.forEach((listener) => listener());
		} else if (frame.type === "health") {
			const health: TerminalHealth = frame.health === "hung" ? "hung" : "ok";
			healthListeners.get(frame.id)?.forEach((listener) => listener(health));
		}
	});

	const dispose = () => {
		if (disposed) return;
		disposed = true;
		if (pingTimer) clearInterval(pingTimer);
		dataListeners.clear();
		exitListeners.clear();
		openedListeners.clear();
		errorListeners.clear();
		healthListeners.clear();
		blockListeners.clear();
		terminalBlockListeners.clear();
		connectionListeners.clear();
		try {
			socket.close();
		} catch {
			// socket may already be closing; ignore.
		}
	};

	return {
		open: (id, cols, rows, history) => {
			send(openFrame(id, cols, rows, history));
		},
		sendInput: (id, input) => {
			const bytes = encoder.encode(input);
			send(dataFrame(id, bytes));
		},
		resize: (id, cols, rows, force) => {
			send(resizeFrame(id, cols, rows, force));
		},
		close: (id) => {
			send(closeFrame(id));
		},
		ack: (id, bytes) => {
			send(ackFrame(id, bytes));
		},
		onData: (id, listener) => subscribeById(dataListeners, id, listener),
		onExit: (id, listener) => subscribeById(exitListeners, id, listener),
		onOpened: (id, listener) => subscribeById(openedListeners, id, listener),
		onError: (id, listener) => subscribeById(errorListeners, id, listener),
		onHealth: (id, listener) => subscribeById(healthListeners, id, listener),
		subscribeBlocks: (sessionId) => {
			send(blocksSubscribeFrame(sessionId));
		},
		unsubscribeBlocks: (sessionId) => {
			send(blocksUnsubscribeFrame(sessionId));
		},
		onBlock: (sessionId, listener) => subscribeById(blockListeners, sessionId, listener),
		onTerminalBlock: (handleId, listener) => {
			const set = terminalBlockListeners.get(handleId) ?? new Set<TerminalBlockListener>();
			if (set.size === 0) send(terminalBlocksSubscribeFrame(handleId));
			set.add(listener);
			terminalBlockListeners.set(handleId, set);
			return () => {
				if (!set.delete(listener) || set.size > 0) return;
				if (terminalBlockListeners.get(handleId) === set) terminalBlockListeners.delete(handleId);
				send(terminalBlocksUnsubscribeFrame(handleId));
			};
		},
		onConnectionChange: (listener) => {
			connectionListeners.add(listener);
			return () => connectionListeners.delete(listener);
		},
		dispose,
	};
}

/**
 * Share the mux transport without sharing attachment ownership.
 *
 * The daemon protocol already multiplexes frames by terminal id. A lease keeps
 * listener and cleanup ownership local to one useTerminalSession instance while
 * avoiding one WebSocket and ping timer per retained xterm. The last lease
 * closes the underlying client. A socket-level failure retires that client so
 * reconnecting leases converge on one replacement socket.
 */
export function createTerminalMuxPool(createMux: () => TerminalMux): TerminalMuxPool {
	type Connection = {
		closed: boolean;
		disposed: boolean;
		mux: TerminalMux;
		refs: number;
		unsubscribeState: () => void;
	};

	const connections = new Set<Connection>();
	let current: Connection | null = null;

	const disposeConnection = (connection: Connection) => {
		if (connection.disposed) return;
		connection.disposed = true;
		connection.closed = true;
		if (current === connection) current = null;
		connections.delete(connection);
		connection.unsubscribeState();
		connection.mux.dispose();
	};

	const newConnection = (): Connection => {
		const mux = createMux();
		const connection: Connection = {
			closed: false,
			disposed: false,
			mux,
			refs: 0,
			unsubscribeState: () => undefined,
		};
		connection.unsubscribeState = mux.onConnectionChange((state) => {
			if (state !== "closed") return;
			connection.closed = true;
			if (current === connection) current = null;
			if (connection.refs === 0) disposeConnection(connection);
		});
		connections.add(connection);
		current = connection;
		return connection;
	};

	const acquire = (): TerminalMux => {
		const connection = current && !current.closed && !current.disposed ? current : newConnection();
		connection.refs += 1;
		let released = false;
		const subscriptions = new Set<() => void>();

		const subscribe = (register: () => () => void): (() => void) => {
			if (released || connection.closed || connection.disposed) return () => undefined;
			const unsubscribe = register();
			let subscribed = true;
			const dispose = () => {
				if (!subscribed) return;
				subscribed = false;
				subscriptions.delete(dispose);
				unsubscribe();
			};
			subscriptions.add(dispose);
			return dispose;
		};

		const dispose = () => {
			if (released) return;
			released = true;
			for (const unsubscribe of [...subscriptions]) unsubscribe();
			connection.refs -= 1;
			if (connection.refs === 0) disposeConnection(connection);
		};

		return {
			open: (id, cols, rows, history) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.open(id, cols, rows, history);
			},
			sendInput: (id, input) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.sendInput(id, input);
			},
			resize: (id, cols, rows, force) => {
				if (!released && !connection.closed && !connection.disposed) {
					connection.mux.resize(id, cols, rows, force);
				}
			},
			close: (id) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.close(id);
			},
			ack: (id, bytes) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.ack(id, bytes);
			},
			onData: (id, listener) => subscribe(() => connection.mux.onData(id, listener)),
			onExit: (id, listener) => subscribe(() => connection.mux.onExit(id, listener)),
			onOpened: (id, listener) => subscribe(() => connection.mux.onOpened(id, listener)),
			onError: (id, listener) => subscribe(() => connection.mux.onError(id, listener)),
			onHealth: (id, listener) => subscribe(() => connection.mux.onHealth(id, listener)),
			subscribeBlocks: (sessionId) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.subscribeBlocks(sessionId);
			},
			unsubscribeBlocks: (sessionId) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.unsubscribeBlocks(sessionId);
			},
			onBlock: (sessionId, listener) => subscribe(() => connection.mux.onBlock(sessionId, listener)),
			onTerminalBlock: (handleId, listener) => subscribe(() => connection.mux.onTerminalBlock(handleId, listener)),
			onConnectionChange: (listener) => subscribe(() => connection.mux.onConnectionChange(listener)),
			dispose,
		};
	};

	return {
		acquire,
		dispose: () => {
			current = null;
			for (const connection of [...connections]) disposeConnection(connection);
		},
	};
}
