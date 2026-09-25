import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	connectProgramFeed,
	PROGRAM_FEED_RETRY_BASE_MS,
	programToast,
	programToastHandle,
	type ProgramNotificationEvent,
} from "./program-feed";
import type { MuxConnectionState, ProgramNotification, TerminalMux } from "./terminal-mux";

type FakeProgramMux = {
	mux: TerminalMux;
	disposed: boolean;
	titleListeners: Set<(handleId: string, title: string) => void>;
	noteListeners: Set<(handleId: string, note: ProgramNotification) => void>;
	connection: Set<(state: MuxConnectionState) => void>;
};

function fakeMux(): FakeProgramMux {
	const fake: FakeProgramMux = {
		disposed: false,
		titleListeners: new Set(),
		noteListeners: new Set(),
		connection: new Set(),
		mux: {} as TerminalMux,
	};
	fake.mux = {
		open: () => undefined,
		sendInput: () => undefined,
		resize: () => undefined,
		close: () => undefined,
		ack: () => undefined,
		requestOlder: () => undefined,
		onData: () => () => undefined,
		onExit: () => () => undefined,
		onOpened: () => () => undefined,
		onError: () => () => undefined,
		onHealth: () => () => undefined,
		subscribeBlocks: () => undefined,
		unsubscribeBlocks: () => undefined,
		onBlock: () => () => undefined,
		onTerminalBlock: () => () => undefined,
		onProgramTitle: (listener) => {
			fake.titleListeners.add(listener);
			return () => fake.titleListeners.delete(listener);
		},
		onProgramNotification: (listener) => {
			fake.noteListeners.add(listener);
			return () => fake.noteListeners.delete(listener);
		},
		onConnectionChange: (listener) => {
			fake.connection.add(listener);
			return () => fake.connection.delete(listener);
		},
		dispose: () => {
			fake.disposed = true;
		},
	};
	return fake;
}

function handlers() {
	return { onTitle: vi.fn(), onNotification: vi.fn(), onReset: vi.fn() };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("connectProgramFeed", () => {
	it("forwards titles and notifications with their terminal id", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		muxes[0].titleListeners.forEach((listener) => listener("h1", "Number list"));
		muxes[0].noteListeners.forEach((listener) => listener("h1", { title: "", body: "hello" }));
		expect(h.onTitle).toHaveBeenCalledWith("h1", "Number list");
		expect(h.onNotification).toHaveBeenCalledWith({ handleId: "h1", title: "", body: "hello" });
		stop();
	});

	it("resets and reconnects with backoff after the socket closes", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		muxes[0].connection.forEach((listener) => listener("closed"));
		expect(h.onReset).toHaveBeenCalledTimes(1);
		expect(muxes[0].disposed).toBe(true);
		expect(muxes[0].titleListeners.size).toBe(0);
		expect(muxes).toHaveLength(1);
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(2);
		muxes[1].connection.forEach((listener) => listener("closed"));
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(2);
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(3);
		stop();
	});

	it("releases every listener, disposes the socket and cancels a pending retry when stopped", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		const first = muxes[0];
		stop();
		expect(first.disposed).toBe(true);
		expect(first.titleListeners.size).toBe(0);
		expect(first.noteListeners.size).toBe(0);
		expect(first.connection.size).toBe(0);
		expect(h.onReset).toHaveBeenCalledTimes(1);

		const again = handlers();
		const stopAgain = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, again);
		muxes[1].connection.forEach((listener) => listener("closed"));
		stopAgain();
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS * 60);
		expect(muxes).toHaveLength(2);
	});
});

describe("program toasts", () => {
	const event = (overrides: Partial<ProgramNotificationEvent> = {}): ProgramNotificationEvent => ({
		handleId: "h1",
		title: "",
		body: "hello",
		...overrides,
	});

	it("uses the program's title, else the fallback, and drops an empty body", () => {
		expect(programToast(event({ title: "Build" }), "fix the tests", 1)).toEqual({ id: "program:h1:1", title: "Build", body: "hello", type: "program" });
		expect(programToast(event(), "fix the tests", 2)).toEqual({ id: "program:h1:2", title: "fix the tests", body: "hello", type: "program" });
		expect(programToast(event({ title: "Done", body: "  " }), "x", 3)).toEqual({ id: "program:h1:3", title: "Done", type: "program" });
	});

	it("reads the terminal id back out of a program toast id only", () => {
		expect(programToastHandle("program:h1:7")).toBe("h1");
		expect(programToastHandle("program:shellterm-ab:cd:2")).toBe("shellterm-ab:cd");
		expect(programToastHandle("ntf_1")).toBeNull();
		expect(programToastHandle("program:")).toBeNull();
	});
});
