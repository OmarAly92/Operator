import { TerminalCore } from "./terminal-core.js";
import { ensureInitialized, type WasmInput } from "./wasm-runtime.js";
import type { TerminalCoreOptions } from "./types.js";

export type {
	AltScreenView,
	BlockId,
	BlockRenderer,
	BlockSource,
	BlockState,
	BlockView,
	BootstrapOptions,
	ChangeListener,
	DirEntry,
	DirtyRows,
	FindMatch,
	FontConfig,
	HostCapabilities,
	HistoryStore,
	LineEditorState,
	MemoryStats,
	PaletteCommand,
	RowEvent,
	RowEventListener,
	RowRange,
	ShellKind,
	SpawnRecipe,
	TerminalCoreOptions,
	TerminalLimits,
	TerminalSnapshot,
	TerminalStrings,
	TerminalTheme,
} from "./types.js";

export type {
	CompletionItem,
	CompletionProvider,
	CompletionRequest,
	CompletionResult,
} from "./completions.js";

export { defaultStrings, validateRowRange } from "./types.js";
export { createCompositionTarget, type CompositionTarget } from "./composition-target.js";
export { BLOCK_RECORD_WORDS, decodeBlocks } from "./blocks.js";
export {
	STYLE_DEFAULT_BACKGROUND,
	STYLE_DEFAULT_FOREGROUND,
	STYLE_RUN_WORDS,
} from "./style-runs.js";
export {
	FEED_BUDGET_MS,
	FEED_SLICE_BYTES,
	FIND_STEP_BUDGET,
	UNBOUNDED_BYTES,
} from "./terminal-core.js";
export { TerminalCore };

export async function initTerminalCore(wasmBytes: WasmInput): Promise<void> {
	await ensureInitialized(wasmBytes);
}

export function createTerminalCore(options: TerminalCoreOptions): TerminalCore {
	return TerminalCore.create(options);
}
