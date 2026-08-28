import { TerminalCore } from "./terminal-core.js";
import { ensureInitialized, type WasmInput } from "./wasm-runtime.js";
import type { TerminalCoreOptions } from "./types.js";

export type {
	BlockId,
	BlockRenderer,
	ChangeListener,
	FontConfig,
	RowRange,
	TerminalCoreOptions,
	TerminalSnapshot,
	TerminalTheme,
} from "./types.js";

export { validateRowRange } from "./types.js";

export { TerminalCore };

export async function initTerminalCore(wasmBytes: WasmInput): Promise<void> {
	await ensureInitialized(wasmBytes);
}

export function createTerminalCore(options: TerminalCoreOptions): TerminalCore {
	return TerminalCore.create(options);
}
