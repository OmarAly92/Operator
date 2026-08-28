import wasmUrl from "../wasm/vt_core_bg.wasm?url";
import { ensureInitialized } from "./wasm-runtime.js";

export async function initTerminalCoreFromUrl(): Promise<void> {
	const response = await fetch(wasmUrl);
	if (!response.ok) {
		throw new Error(
			`failed to fetch WASM: ${response.status} ${response.statusText} at ${wasmUrl}`,
		);
	}
	const bytes = await response.arrayBuffer();
	await ensureInitialized(bytes);
}
