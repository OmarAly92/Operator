import { invoke } from "@tauri-apps/api/core";

export async function nativeTerminalRuntimeIdentity(): Promise<string> {
	const identity = await invoke<unknown>("terminal_benchmark_runtime_identity");
	if (typeof identity !== "string" || !identity.trim()) {
		throw new Error("terminal benchmark native runtime identity is unavailable");
	}
	return identity.trim();
}

// Terminal-benchmark mode registers daemon_start as an invokable command
// (see lib.rs's builder split on OPERATOR_TAURI_TERMINAL_BENCHMARK) instead
// of auto-starting the daemon on launch, the same way audit mode does — so
// the harness page has to ask for it explicitly. Only the cpu-time and
// active-memory scenarios need a live daemon (they read its process id off
// the run file it writes on start); every other scenario drives the
// terminal component directly and must not pay this cost or its side
// effects.
export async function startTauriDaemonForScenario(scenario: string | null): Promise<void> {
	if (scenario !== "cpu-time" && scenario !== "active-memory") return;
	await invoke("daemon_start");
}
