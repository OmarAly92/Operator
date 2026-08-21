import { beforeEach, describe, expect, it, vi } from "vitest";
import { nativeTerminalRuntimeIdentity } from "./runtime";

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
