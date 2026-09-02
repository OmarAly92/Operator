import { beforeEach, describe, expect, it, vi } from "vitest";
import { nativeTerminalRuntimeIdentity, startTauriDaemonForScenario } from "./runtime";

const invokeState = vi.hoisted(() => ({
	invoke: vi.fn<(command: string) => Promise<unknown>>(),
}));

vi.mock("@tauri-apps/api/core", () => ({
	invoke: (command: string) => invokeState.invoke(command),
}));

describe("terminal benchmark native runtime identity", () => {
	beforeEach(() => invokeState.invoke.mockReset());

	it("uses the benchmark-only native Tauri command", async () => {
		invokeState.invoke.mockResolvedValue("macos arm64 / WebView 619.3 / Tauri 2.11.5");

		await expect(nativeTerminalRuntimeIdentity()).resolves.toBe(
			"macos arm64 / WebView 619.3 / Tauri 2.11.5",
		);
		expect(invokeState.invoke).toHaveBeenCalledWith("terminal_benchmark_runtime_identity");
	});

	it("fails closed for an empty native identity", async () => {
		invokeState.invoke.mockResolvedValue("  ");

		await expect(nativeTerminalRuntimeIdentity()).rejects.toThrow(/unavailable/);
	});
});

describe("startTauriDaemonForScenario", () => {
	beforeEach(() => invokeState.invoke.mockReset());

	it.each(["cpu-time", "active-memory"])("starts the daemon for %s", async (scenario) => {
		invokeState.invoke.mockResolvedValue(undefined);

		await startTauriDaemonForScenario(scenario);

		expect(invokeState.invoke).toHaveBeenCalledWith("daemon_start");
	});

	it.each(["vtebench", "large-output", "input-latency", "scroll-latency", "reconnect", "disposal", null])(
		"does not start the daemon for %s",
		async (scenario) => {
			await startTauriDaemonForScenario(scenario);

			expect(invokeState.invoke).not.toHaveBeenCalled();
		},
	);
});
