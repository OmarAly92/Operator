import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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

import { createTauriBridge, parseTelemetryBootstrap } from "./tauri-bridge";

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

describe("tauri-bridge subscriptions", () => {
	it("accepts an asynchronous listener registration without a disposer", async () => {
		const listen = vi.fn().mockResolvedValue(undefined);
		const tauri = createTauriBridge({ invoke: vi.fn(), listen });

		expect(() => tauri.daemon.onStatus(() => undefined)()).not.toThrow();
		await Promise.resolve();
		expect(listen).toHaveBeenCalledWith("daemon:status", expect.any(Function));
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
