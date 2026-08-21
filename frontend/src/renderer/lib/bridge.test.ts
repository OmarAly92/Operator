import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@tauri-apps/api/core", () => ({
	invoke: (...args: unknown[]) => (globalThis as { __tauriInvoke?: (...args: unknown[]) => unknown }).__tauriInvoke?.(...(args as [])),
}));

vi.mock("@tauri-apps/api/event", () => ({
	listen: (...args: unknown[]) => (globalThis as { __tauriListen?: (...args: unknown[]) => unknown }).__tauriListen?.(...(args as [])),
}));

type Invoke = (command: string, payload?: unknown) => Promise<unknown>;
type Listen = (event: string, handler: (event: { payload: unknown }) => void) => () => void;

function setWindowOperator(value: unknown): void {
	(window as { operator?: unknown }).operator = value;
}

function setTauriInternals(present: boolean): void {
	const holder = globalThis as { __TAURI_INTERNALS__?: unknown };
	if (present) holder.__TAURI_INTERNALS__ = { transformCallback: () => 1 };
	else delete holder.__TAURI_INTERNALS__;
}

async function importBridge() {
	vi.resetModules();
	return import("./bridge");
}

describe("shell selection", () => {
	beforeEach(() => {
		setWindowOperator(undefined);
		setTauriInternals(false);
	});

	afterEach(() => {
		setWindowOperator(undefined);
		setTauriInternals(false);
		vi.unstubAllEnvs();
	});

	it("selects the Tauri bridge when __TAURI_INTERNALS__ is present without Electron preload", async () => {
		setTauriInternals(true);
		const invokeStub = vi.fn<Invoke>().mockResolvedValue({ state: "stopped" });
		const listenStub = vi.fn<Listen>().mockReturnValue(() => undefined);
		(globalThis as { __tauriInvoke?: unknown }).__tauriInvoke = invokeStub;
		(globalThis as { __tauriListen?: unknown }).__tauriListen = listenStub;
		const { selectShellBridgeForTest } = await importBridge();
		const bridge = await selectShellBridgeForTest();
		expect(await bridge.daemon.getStatus()).toMatchObject({ state: "stopped" });
		expect(invokeStub).toHaveBeenCalledWith("daemon_status", undefined);
		expect("browser" in bridge).toBe(false);
	});

	it("prefers the Electron bridge when both shells coexist", async () => {
		const electronBridge = { daemon: { getStatus: async () => ({ state: "ready" }) } };
		setWindowOperator(electronBridge);
		setTauriInternals(true);
		const { operatorBridge } = await importBridge();
		expect(await operatorBridge.daemon.getStatus()).toEqual({ state: "ready" });
	});

	it("falls back to the browser preview bridge under VITE_NO_ELECTRON=1", async () => {
		vi.stubEnv("VITE_NO_ELECTRON", "1");
		const { operatorBridge } = await importBridge();
		expect(await operatorBridge.daemon.getStatus()).toMatchObject({ state: "stopped" });
	});
});

describe("createTauriBridge", async () => {
	const invoke = vi.fn<Invoke>();
	const listen = vi.fn<Listen>();

	async function create() {
		(globalThis as { __tauriInvoke?: unknown }).__tauriInvoke = invoke;
		(globalThis as { __tauriListen?: unknown }).__tauriListen = listen;
		const module = await import("./tauri-bridge");
		return module.createTauriBridge({ invoke, listen });
	}

	beforeEach(() => {
		invoke.mockReset();
		listen.mockReset().mockReturnValue(() => undefined);
	});

	it("maps daemon status commands onto the shared DaemonStatus shape", async () => {
		const status = { state: "ready", port: 3001, pid: 42 };
		invoke.mockResolvedValue(status);
		const bridge = await create();
		expect(await bridge.daemon.getStatus()).toEqual(status);
		expect(invoke).toHaveBeenCalledWith("daemon_status");
	});

	it("subscribes and unsubscribes daemon status exactly once per listener", async () => {
		const unsubscribe = vi.fn();
		const wrappedHandlers: Array<(event: { payload: unknown }) => void> = [];
		listen.mockImplementation((_event: string, wrapped: (event: { payload: unknown }) => void) => {
			wrappedHandlers.push(wrapped);
			return unsubscribe;
		});
		const bridge = await create();
		const received: unknown[] = [];
		let active = true;
		const stop = bridge.daemon.onStatus((status) => {
			if (active) received.push(status);
		});
		expect(wrappedHandlers).toHaveLength(1);
		wrappedHandlers[0]({ payload: { state: "starting" } });
		stop();
		active = false;
		unsubscribe();
		wrappedHandlers[0]({ payload: { state: "ready" } });
		expect(received).toEqual([{ state: "starting" }]);
	});

	it("exposes no browser namespace on the Tauri bridge", async () => {
		const bridge = await create();
		expect("browser" in bridge).toBe(false);
	});
});
