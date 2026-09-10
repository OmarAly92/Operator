import { invoke as tauriInvoke } from "@tauri-apps/api/core";

const enabled = import.meta.env.DEV;

let sequence = 0;

// Every line carries milliseconds since the renderer started, so any two lines
// in a captured log can be subtracted. Without it the terminal log records the
// ORDER of the attach path but not its cost, which is the only question worth
// asking of it -- the surrounding vite/tauri lines are the only timestamps a
// captured session otherwise has, and they are minutes apart.
function stamp(): number {
	return Math.round(performance.now());
}

export function terminalDebug(scope: string, message: string, detail?: Record<string, unknown>): void {
	if (!enabled) return;
	sequence += 1;
	const suffix = detail ? ` ${JSON.stringify(detail)}` : "";
	const line = `#${sequence} @${stamp()}ms ${message}${suffix}`;
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

/**
 * Times one span of the attach path. Returns the closer, which logs the span
 * with its elapsed ms; calling it twice logs once.
 *
 * Spans, not just stamps, because the interesting costs are spans a reader
 * cannot reconstruct from line order alone: an attach that is slow because the
 * socket was slow and one that is slow because the replay was large produce the
 * same sequence of lines.
 */
export function terminalSpan(scope: string, message: string): (detail?: Record<string, unknown>) => void {
	const started = performance.now();
	let closed = false;
	return (detail?: Record<string, unknown>) => {
		if (closed) return;
		closed = true;
		terminalDebug(scope, message, { ms: Math.round(performance.now() - started), ...detail });
	};
}
