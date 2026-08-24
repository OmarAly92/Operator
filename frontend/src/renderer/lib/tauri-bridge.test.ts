import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { TrayAttentionState } from "../../shared/tray";

const { getStub, patchStub, postStub, getApiBaseUrlMock, hasTrustedApiBaseUrlMock, subscribeApiBaseUrlMock } = vi.hoisted(() => ({
	getStub: vi.fn(),
	patchStub: vi.fn(),
	postStub: vi.fn(),
	getApiBaseUrlMock: vi.fn(() => "http://127.0.0.1:3001"),
	hasTrustedApiBaseUrlMock: vi.fn(() => true),
	subscribeApiBaseUrlMock: vi.fn(),
}));

vi.mock("./api-client", () => ({
	apiClient: { GET: getStub, PATCH: patchStub, POST: postStub },
	apiErrorMessage: (error: unknown) =>
		typeof error === "object" && error !== null && "message" in error
			? String((error as { message: unknown }).message)
			: "Request failed",
	getApiBaseUrl: getApiBaseUrlMock,
	hasTrustedApiBaseUrl: hasTrustedApiBaseUrlMock,
	subscribeApiBaseUrl: subscribeApiBaseUrlMock,
}));

import { createTauriBridge, encodeBase64, parseTelemetryBootstrap } from "./tauri-bridge";

function bridge() {
	return createTauriBridge({ invoke: vi.fn(), listen: vi.fn() });
}

describe("tauri-bridge local folder scans", () => {
	beforeEach(() => {
		getStub.mockReset();
		patchStub.mockReset();
		postStub.mockReset();
		getApiBaseUrlMock.mockReturnValue("http://127.0.0.1:3001");
		hasTrustedApiBaseUrlMock.mockReturnValue(true);
		subscribeApiBaseUrlMock.mockReset().mockReturnValue(() => undefined);
	});

	it("scans an import folder through the LAN-blocked dev route", async () => {
		postStub.mockResolvedValue({
			data: {
				path: "/repos",
				repos: [
					{
						name: "app",
						path: "/repos/app",
						relativePath: "app",
						branch: "main",
						remote: "https://example.com/app.git",
						hasRemote: true,
						status: "ok",
					},
				],
				setupWarning: "Selected folder is inside an existing Git repository at /repos.",
			},
		});

		const result = await bridge().app.scanImportFolder({ path: "/repos", mode: "workspace" });

		expect(postStub).toHaveBeenCalledWith("/api/v1/dev/import-scan", {
			body: { path: "/repos", mode: "workspace" },
		});
		expect(result.path).toBe("/repos");
		expect(result.setupWarning).toContain("existing Git repository");
		expect(result.repos[0]).toMatchObject({ name: "app", status: "ok", hasRemote: true });
	});

	it("omits setupWarning when the daemon reports none", async () => {
		postStub.mockResolvedValue({ data: { path: "/repos", repos: [] } });

		const result = await bridge().app.scanImportFolder({ path: "/repos", mode: "project" });

		expect("setupWarning" in result).toBe(false);
		expect(result.repos).toEqual([]);
	});

	it("surfaces scan failures as thrown errors", async () => {
		postStub.mockResolvedValue({ data: undefined, error: { message: "readdir failed" } });

		await expect(
			bridge().app.scanImportFolder({ path: "/repos", mode: "workspace" }),
		).rejects.toThrow("readdir failed");
	});

	it("checks the ancestor repository through its dev route", async () => {
		postStub.mockResolvedValue({ data: { setupWarning: "inside an existing repository" } });

		const warning = await bridge().app.checkAncestorRepo("/parent/inner");

		expect(postStub).toHaveBeenCalledWith("/api/v1/dev/ancestor-repository", {
			body: { path: "/parent/inner" },
		});
		expect(warning).toBe("inside an existing repository");
	});

	it("returns undefined when no ancestor repository exists", async () => {
		postStub.mockResolvedValue({ data: {} });

		expect(await bridge().app.checkAncestorRepo("/plain")).toBeUndefined();
	});
});

describe("tauri-bridge settings errors", () => {
	beforeEach(() => {
		getStub.mockReset().mockResolvedValue({ data: undefined, error: { message: "settings unavailable" } });
		patchStub.mockReset();
	});

	it("does not turn a failed settings read into local defaults", async () => {
		const tauri = bridge();

		await expect(tauri.appState.getMigration()).rejects.toThrow("settings unavailable");
		await expect(tauri.updateSettings.get()).rejects.toThrow("settings unavailable");
		await expect(tauri.uiSettings.get()).rejects.toThrow("settings unavailable");
		await expect(tauri.keybindings.get()).rejects.toThrow("settings unavailable");
	});
});

describe("tauri-bridge native shortcut registration", () => {
	const OVERRIDE = {
		"new-session": [{ key: "j", ctrl: false, meta: true, shift: false, alt: false }],
	};

	it("persists through Go before applying the saved bindings natively", async () => {
		const order: string[] = [];
		patchStub.mockImplementation(async () => {
			order.push("patch");
			return { data: { keybindings: OVERRIDE } };
		});
		const invoke = vi.fn(async (command: string) => {
			order.push(command);
			return null;
		});
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await tauri.keybindings.set(OVERRIDE);

		expect(patchStub).toHaveBeenCalledWith("/api/v1/settings/keybindings", {
			body: OVERRIDE,
		});
		expect(invoke).toHaveBeenCalledWith("keybindings_apply", { overrides: OVERRIDE });
		expect(order.indexOf("patch")).toBeLessThan(order.indexOf("keybindings_apply"));
	});

	it("never touches native registration when the Go write fails", async () => {
		patchStub.mockResolvedValue({ data: undefined, error: { message: "settings locked" } });
		const invoke = vi.fn(async () => null);
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await expect(tauri.keybindings.set({})).rejects.toThrow("settings locked");
		expect(invoke).not.toHaveBeenCalled();
	});

	it("applies overrides natively after loading them from Go", async () => {
		getStub.mockReset().mockResolvedValue({ data: { keybindings: OVERRIDE } });
		patchStub.mockReset();
		const invoke = vi.fn(async () => null);
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await expect(tauri.keybindings.get()).resolves.toEqual(OVERRIDE);
		expect(invoke).toHaveBeenCalledWith("keybindings_apply", { overrides: OVERRIDE });
	});

	it("survives a native registration failure after a successful Go write", async () => {
		patchStub.mockResolvedValue({ data: { keybindings: OVERRIDE } });
		const invoke = vi.fn().mockRejectedValue(new Error("plugin unavailable"));
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await expect(tauri.keybindings.set({})).resolves.toEqual(OVERRIDE);
		expect(invoke).toHaveBeenCalledWith("keybindings_apply", { overrides: OVERRIDE });
	});
});

describe("tauri-bridge subscriptions", () => {
	it("accepts an asynchronous listener registration without a disposer", async () => {
		const listen = vi.fn().mockResolvedValue(undefined);
		const tauri = createTauriBridge({ invoke: vi.fn(), listen });

		expect(() => tauri.daemon.onStatus(() => undefined)()).not.toThrow();
		await Promise.resolve();
		expect(listen).toHaveBeenCalledWith("daemon:status", expect.any(Function));
	});
});

describe("tauri-bridge native integrations", () => {
	type Invoke = (command: string, payload?: unknown) => Promise<unknown>;

	function bridgeWith(invoke: Invoke) {
		const listen = (): (() => void) => () => undefined;
		return createTauriBridge({ invoke, listen });
	}

	it("stages dropped files as base64 payloads and returns the staged path", async () => {
		const invoke = vi.fn().mockResolvedValue("/state/terminal-drops/1-abc-notes.txt");
		const tauri = bridgeWith(invoke);

		await expect(
			tauri.terminal.saveDroppedFile({ name: "notes.txt", bytes: new Uint8Array([104, 105, 0, 255]) }),
		).resolves.toBe("/state/terminal-drops/1-abc-notes.txt");
		expect(invoke).toHaveBeenCalledWith("stage_dropped_file", {
			name: "notes.txt",
			data: "aGkA/w==",
		});
	});

	it("encodes empty and large-ish byte arrays without mangling values", () => {
		expect(encodeBase64(new Uint8Array([]))).toBe("");

		const source = Array.from({ length: 0x8001 }, (_, i) => i % 256);
		const encoded = encodeBase64(new Uint8Array(source));
		const decoded = Array.from(atob(encoded), (char) => char.charCodeAt(0));
		expect(decoded).toEqual(source);
	});

	it("signals renderer readiness when subscribing to tray open-session events", async () => {
		const invoke = vi.fn(async (command: string) => {
			if (command === "tray_renderer_ready") throw new Error("no tray");
			return null;
		});
		const listen = vi.fn().mockReturnValue(() => undefined);
		const tauri = createTauriBridge({ invoke, listen });

		const dispose = tauri.tray.onOpenSession(() => undefined);

		await vi.waitFor(() => expect(invoke).toHaveBeenCalledWith("tray_renderer_ready"));
		expect(listen).toHaveBeenCalledWith("tray:open-session", expect.any(Function));
		dispose();
	});

	it("pushes attention state without awaiting the native update", async () => {
		const invoke = vi.fn<Invoke>(async () => null);
		const tauri = bridgeWith(invoke);
		const state: TrayAttentionState = {
			sessions: [
				{ projectId: "p1", projectName: "Alpha", sessionId: "s1", title: "t", zone: "merge" },
			],
		};

		expect(() => tauri.tray.setAttentionState(state)).not.toThrow();
		await vi.waitFor(() =>
			expect(invoke).toHaveBeenCalledWith("tray_attention_state", { attention: state }),
		);
	});

	it("keeps the tray locale in sync from ui settings reads and writes", async () => {
		getStub.mockReset().mockResolvedValue({ data: { ui: { locale: "de" } } });
		patchStub.mockReset().mockResolvedValue({ data: { ui: { locale: "fr" } } });
		const invoke = vi.fn(async () => null);
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await expect(tauri.uiSettings.get()).resolves.toEqual({ locale: "de" });
		await expect(tauri.uiSettings.set({ locale: "fr" })).resolves.toEqual({ locale: "fr" });
		await vi.waitFor(() => {
			expect(invoke).toHaveBeenNthCalledWith(1, "tray_set_locale", { locale: "de" });
			expect(invoke).toHaveBeenNthCalledWith(2, "tray_set_locale", { locale: "fr" });
		});
	});

	it("never fails a settings read when the tray locale push is rejected", async () => {
		getStub.mockReset().mockResolvedValue({ data: { ui: { locale: "ja" } } });
		const invoke = vi.fn(async (command: string) => {
			if (command === "tray_set_locale") throw new Error("tray unavailable");
			return null;
		});
		const tauri = createTauriBridge({ invoke, listen: vi.fn() });

		await expect(tauri.uiSettings.get()).resolves.toEqual({ locale: "ja" });
	});

	it("routes notifications through the shell commands with exact channels", async () => {
		const invoke = vi.fn(async () => null);
		const wrappedHandlers: Array<(event: { payload: unknown }) => void> = [];
		const listen = vi.fn((_event: string, handler: (event: { payload: unknown }) => void) => {
			wrappedHandlers.push(handler);
			return () => undefined;
		});
		const tauri = createTauriBridge({ invoke, listen });

		await tauri.notifications.show({ id: "n1", title: "Needs input", body: "hi", type: "needs_input" });
		expect(invoke).toHaveBeenCalledWith("notification_show", {
			notification: {
				id: "n1",
				title: "Needs input",
				body: "hi",
				type: "needs_input",
			},
		});

		await tauri.notifications.setBadge(3);
		await tauri.notifications.devBounce();
		expect(invoke).toHaveBeenCalledWith("notification_badge", { count: 3 });
		expect(invoke).toHaveBeenCalledWith("notification_dev_bounce");

		const seen: string[] = [];
		const stop = tauri.notifications.onClick((id) => seen.push(id));
		wrappedHandlers[0]({ payload: "n9" });
		stop();
		expect(seen).toEqual(["n9"]);
	});

	it("validates external URLs through the Electron allowlist on the Rust opener command", async () => {
		const invoke = vi.fn<Invoke>(async (_command, payload) => {
			const url = (payload as { url?: string })?.url;
			if (!url || !["https://example.com", "http://127.0.0.1:3001/x", "mailto:user@example.com"].includes(url)) {
				throw new Error("Unsupported external URL");
			}
			return null;
		});
		const tauri = bridgeWith(invoke);

		await expect(tauri.app.openExternal("https://example.com")).resolves.toBeUndefined();
		await expect(tauri.app.openExternal("mailto:user@example.com")).resolves.toBeUndefined();
		expect(invoke).toHaveBeenCalledWith("open_external", { url: "mailto:user@example.com" });
		await expect(tauri.app.openExternal("javascript:alert(1)")).rejects.toThrow(
			"Unsupported external URL",
		);
		await expect(tauri.app.openExternal("data:text/html,hi")).rejects.toThrow(
			"Unsupported external URL",
		);
		await expect(tauri.app.openExternal("file:///etc/passwd")).rejects.toThrow(
			"Unsupported external URL",
		);
		await expect(tauri.app.openExternal("slack://channel?id=1")).rejects.toThrow(
			"Unsupported external URL",
		);
	});

	it("passes the chooser title through and surfaces cancellation as null", async () => {
		const invoke = vi.fn<Invoke>(async (_command, payload) =>
			(payload as { title?: string })?.title ? "/repos/picked" : null,
		);
		const tauri = bridgeWith(invoke);

		await expect(tauri.app.chooseDirectory("Pick a workspace")).resolves.toBe("/repos/picked");
		expect(invoke).toHaveBeenCalledWith("choose_directory", { title: "Pick a workspace" });
		await expect(tauri.app.chooseDirectory()).resolves.toBeNull();
		expect(invoke).toHaveBeenLastCalledWith("choose_directory", { title: undefined });
	});
});

describe("tauri-bridge telemetry bootstrap", () => {
	beforeEach(() => {
		getApiBaseUrlMock.mockReturnValue("http://127.0.0.1:3001");
		hasTrustedApiBaseUrlMock.mockReturnValue(true);
		subscribeApiBaseUrlMock.mockReset().mockReturnValue(() => undefined);
	});

	afterEach(() => {
		vi.unstubAllGlobals();
		vi.useRealTimers();
	});

	it("fetches the loopback bootstrap from the trusted daemon base URL", async () => {
		const fetchStub = vi.fn().mockResolvedValue(
			new Response(JSON.stringify({ distinctId: "ins_daemon", appVersion: "0.11.3", platform: "darwin", disabledEvents: ["opr.v2.app.active"] }), {
				status: 200,
			}),
		);
		vi.stubGlobal("fetch", fetchStub);

		await expect(bridge().telemetry.getBootstrap()).resolves.toEqual({
			distinctId: "ins_daemon",
			appVersion: "0.11.3",
			platform: "darwin",
			disabledEvents: ["opr.v2.app.active"],
		});
		expect(fetchStub).toHaveBeenCalledWith(new URL("http://127.0.0.1:3001/internal/desktop/telemetry-bootstrap"));
	});

	it("degrades to a withheld bootstrap on any failure", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("null", { status: 200 })));
		await expect(bridge().telemetry.getBootstrap()).resolves.toBeNull();

		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("server exploded", { status: 500 })));
		await expect(bridge().telemetry.getBootstrap()).resolves.toBeNull();

		vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
		await expect(bridge().telemetry.getBootstrap()).resolves.toBeNull();
	});

	it("gives up when the daemon port never becomes trusted", async () => {
		hasTrustedApiBaseUrlMock.mockReturnValue(false);
		subscribeApiBaseUrlMock.mockImplementation(() => () => undefined);
		vi.useFakeTimers();

		const pending = bridge().telemetry.getBootstrap();
		const settled = await Promise.race([
			pending.then(() => true),
			vi.advanceTimersByTimeAsync(5_000).then(() => false),
		]);
		expect(settled).toBe(false);
		expect(subscribeApiBaseUrlMock).toHaveBeenCalled();

		await vi.advanceTimersByTimeAsync(5_001);
		await expect(pending).resolves.toBeNull();
	});
});

describe("parseTelemetryBootstrap", () => {
	it("accepts the daemon wire shape and drops unusable payloads", () => {
		expect(parseTelemetryBootstrap(null)).toBeNull();
		expect(parseTelemetryBootstrap({})).toBeNull();
		expect(parseTelemetryBootstrap({ distinctId: "  ", appVersion: "0.11.3", platform: "win32", disabledEvents: [] })).toBeNull();
		expect(parseTelemetryBootstrap({ distinctId: "ins_1", appVersion: "0.11.3" })).toBeNull();
		expect(parseTelemetryBootstrap({ distinctId: "ins_1", appVersion: "0.11.3", platform: "linux", disabledEvents: "nope" })).toBeNull();

		expect(
			parseTelemetryBootstrap({
				distinctId: "ins_1",
				appVersion: "",
				platform: "linux",
				disabledEvents: ["a", 7, "b"],
			}),
		).toEqual({ distinctId: "ins_1", appVersion: "", platform: "linux", disabledEvents: ["a", "b"] });
	});
});
