import { invoke } from "@tauri-apps/api/core";

export async function nativeTerminalRuntimeIdentity(): Promise<string> {
	const identity = await invoke<unknown>("terminal_benchmark_runtime_identity");
	if (typeof identity !== "string" || !identity.trim()) {
		throw new Error("terminal benchmark native runtime identity is unavailable");
	}
	return identity.trim();
}
