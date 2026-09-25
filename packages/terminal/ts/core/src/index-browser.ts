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
	FindUpdate,
	FontConfig,
	HostCapabilities,
	HistoryStore,
	LineEditorState,
	MemoryStats,
	OlderOutput,
	PaletteCommand,
	PasteUnsafeReason,
	PathCandidate,
	ResolvedPath,
	RowEvent,
	RowEventListener,
	RowRange,
	SecretPattern,
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
export {
	anchorFromElement,
	createCompositionTarget,
	type CompositionAnchor,
	type CompositionTarget,
} from "./composition-target.js";
export { BLOCK_RECORD_WORDS, decodeBlocks } from "./blocks.js";
export {
	ATTR_BLINK,
	ATTR_CURLY_UNDERLINE,
	ATTR_DASHED_UNDERLINE,
	ATTR_DOTTED_UNDERLINE,
	ATTR_DOUBLE_UNDERLINE,
	ATTR_HIDDEN,
	ATTR_ITALIC,
	ATTR_OVERLINE,
	ATTR_STRIKE,
	ATTR_UNDERLINE,
	STYLE_DEFAULT_BACKGROUND,
	STYLE_DEFAULT_FOREGROUND,
	STYLE_DEFAULT_UNDERLINE,
	STYLE_RUN_WORDS,
	STYLE_WORD_LINK,
} from "./style-runs.js";
export { CELL_SPAN_WORDS } from "./cell-spans.js";
export { joinLogicalLine, type LogicalLine } from "./logical-lines.js";
export { compileMarkRegex, markRegexValid, type MarkRegex } from "./mark-regex.js";
export {
	ProgramMessages,
	type ProgramMessageEvent,
	type ProgramMessageListener,
	type ProgramMessageSource,
	type ProgramNotification,
} from "./program-messages.js";
export {
	AgentEvents,
	type AgentEvent,
	type AgentEventListener,
	type AgentEventSource,
	type AgentState,
} from "./agent-events.js";
export {
	ACTIVITY_IDLE_AFTER_MS,
	ACTIVITY_POLLING_AFTER_MS,
	AgentActivityMonitor,
	cursorLineText,
	type AgentActivityListener,
	type AgentActivitySource,
	type AgentActivityState,
} from "./agent-activity.js";
export { detectsHighConfidenceInputPattern } from "./input-patterns.js";
export {
	COMPACT_MIN_REDRAW_LINES,
	COMPACT_REDRAW_LOOKBACK,
	capLines,
	compactLines,
	isSpinnerLine,
} from "./compact-output.js";
export { blockOutputText, type BlockOutputOptions } from "./block-output.js";
export {
	FEED_BUDGET_MS,
	FEED_SLICE_BYTES,
	FIND_UPDATE_BUDGET_BYTES,
	UNBOUNDED_BYTES,
} from "./terminal-core.js";
export { TerminalCore };

export async function initTerminalCore(wasmBytes: WasmInput): Promise<void> {
	await ensureInitialized(wasmBytes);
}

export function createTerminalCore(options: TerminalCoreOptions): TerminalCore {
	return TerminalCore.create(options);
}
