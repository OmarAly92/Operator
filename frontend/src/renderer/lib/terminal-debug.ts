import { invoke as tauriInvoke } from "@tauri-apps/api/core";

const enabled = import.meta.env.DEV;

let sequence = 0;

export function terminalDebug(scope: string, message: string, detail?: Record<string, unknown>): void {
	if (!enabled) return;
	sequence += 1;
	const suffix = detail ? ` ${JSON.stringify(detail)}` : "";
	const line = `#${sequence} ${message}${suffix}`;
	if ((window as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__) {
		void Promise.resolve(tauriInvoke("debug_log", { scope, message: line })).catch((error: unknown) => {
			console.log(`[renderer:${scope}] ${line} (debug_log unavailable: ${String(error)})`);
		});
		return;
	}
	console.log(`[renderer:${scope}] ${line}`);
}

export function previewBytes(bytes: Uint8Array, limit = 60): string {
	const slice = bytes.subarray(0, limit);
	let out = "";
	for (const byte of slice) {
		if (byte === 0x1b) out += "\\e";
		else if (byte === 0x0a) out += "\\n";
		else if (byte === 0x0d) out += "\\r";
		else if (byte === 0x07) out += "\\a";
		else if (byte < 0x20 || byte > 0x7e) out += `\\x${byte.toString(16).padStart(2, "0")}`;
		else out += String.fromCharCode(byte);
	}
	return bytes.length > limit ? `${out}…` : out;
}
