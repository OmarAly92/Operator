import { TerminalCore } from "./terminal-core.js";
import { ensureInitialized, type WasmInput } from "./wasm-runtime.js";
import type { TerminalCoreOptions } from "./types.js";

export type {
	BlockId,
	BlockRenderer,
	BlockSource,
	BlockState,
	BlockView,
	ChangeListener,
	FontConfig,
	RowRange,
	TerminalCoreOptions,
	TerminalSnapshot,
	TerminalStrings,
	TerminalTheme,
} from "./types.js";

export { defaultStrings, validateRowRange } from "./types.js";

export { BLOCK_RECORD_WORDS, decodeBlocks } from "./blocks.js";

export { TerminalCore };

export async function initTerminalCore(wasmBytes: WasmInput): Promise<void> {
	await ensureInitialized(wasmBytes);
}

export function createTerminalCore(options: TerminalCoreOptions): TerminalCore {
	return TerminalCore.create(options);
}
