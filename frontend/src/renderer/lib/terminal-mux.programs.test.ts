import { afterEach, describe, expect, it } from "vitest";
import {
	appearanceFrame,
	createTerminalMux,
	createTerminalMuxPool,
	programsSubscribeFrame,
	programsUnsubscribeFrame,
} from "./terminal-mux";

class FakeSocket {
	static OPEN = 1;
	static instances: FakeSocket[] = [];
	readyState = 0;
	sent: string[] = [];
	private listeners: Record<string, ((ev: unknown) => void)[]> = {};
	constructor(public url: string) {
		FakeSocket.instances.push(this);
	}
	addEventListener(type: string, cb: (ev: unknown) => void) {
		(this.listeners[type] ??= []).push(cb);
	}
	send(frame: string) {
		this.sent.push(frame);
	}
	close() {}
	emitOpen() {
		this.readyState = FakeSocket.OPEN;
		this.listeners.open?.forEach((cb) => cb({}));
	}
	emitMessage(data: string) {
		this.listeners.message?.forEach((cb) => cb({ data }));
	}
	frames(): Array<Record<string, unknown>> {
		return this.sent.map((frame) => JSON.parse(frame) as Record<string, unknown>);
	}
}

const socketImpl = FakeSocket as unknown as typeof WebSocket;

afterEach(() => {
	FakeSocket.instances = [];
});

describe("program frames", () => {
	it("encodes an appearance frame for one terminal", () => {
		expect(
			JSON.parse(appearanceFrame("h1", { cellWidth: 16, cellHeight: 34, foreground: "#ffffff", background: "#1d2022" })),
		).toEqual({ ch: "terminal", type: "appearance", id: "h1", cellWidth: 16, cellHeight: 34, foreground: "#ffffff", background: "#1d2022" });
	});

	it("encodes the programs subscribe and unsubscribe frames", () => {
		expect(JSON.parse(programsSubscribeFrame())).toEqual({ ch: "programs", type: "subscribe" });
		expect(JSON.parse(programsUnsubscribeFrame())).toEqual({ ch: "programs", type: "unsubscribe" });
	});
});

describe("createTerminalMux programs channel", () => {
	it("subscribes once for the first listener and unsubscribes after the last", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const offTitle = mux.onProgramTitle!(() => undefined);
		const offNote = mux.onProgramNotification!(() => undefined);
		expect(socket.frames()).toEqual([{ ch: "programs", type: "subscribe" }]);
		offTitle();
		expect(socket.frames()).toHaveLength(1);
		offNote();
		offNote();
		expect(socket.frames()).toEqual([
			{ ch: "programs", type: "subscribe" },
			{ ch: "programs", type: "unsubscribe" },
		]);
	});

	it("routes title and notification frames with their terminal id", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const titles: Array<[string, string]> = [];
		const notes: Array<[string, { title: string; body: string }]> = [];
		mux.onProgramTitle!((id, title) => titles.push([id, title]));
		mux.onProgramNotification!((id, note) => notes.push([id, note]));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "Number list" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "notification", id: "h2", body: "hello" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", title: "no id" }));
		expect(titles).toEqual([
			["h1", "Number list"],
			["h1", ""],
		]);
		expect(notes).toEqual([["h2", { title: "", body: "hello" }]]);
	});

	it("sends an appearance frame for a terminal", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		mux.appearance!("h1", { cellWidth: 8, cellHeight: 17, foreground: "#ffffff", background: "#000000" });
		expect(socket.frames()).toEqual([
			{ ch: "terminal", type: "appearance", id: "h1", cellWidth: 8, cellHeight: 17, foreground: "#ffffff", background: "#000000" },
		]);
	});
});

describe("createTerminalMuxPool programs channel", () => {
	it("stops delivering program frames to a disposed lease and unsubscribes", () => {
		const pool = createTerminalMuxPool(() => createTerminalMux("ws://x/mux", socketImpl));
		const lease = pool.acquire();
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const titles: string[] = [];
		lease.onProgramTitle!((_id, title) => titles.push(title));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "one" }));
		lease.dispose();
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "two" }));
		expect(titles).toEqual(["one"]);
		pool.dispose();
	});
});
