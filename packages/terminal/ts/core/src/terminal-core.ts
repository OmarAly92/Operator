import { WasmTerminalCore } from "../wasm/vt_core.js";
import { BLOCK_RECORD_WORDS, decodeBlocks } from "./blocks.js";
import {
	getMemory,
	isInitialized,
	u32View,
	u8View,
	type WasmInput,
} from "./wasm-runtime.js";
import type {
	BlockId,
	ChangeListener,
	FindMatch,
	HostCapabilities,
	LineEditorState,
	TerminalCoreOptions,
	TerminalSnapshot,
} from "./types.js";
import type {
	CompletionListener,
	CompletionProvider,
} from "./completions.js";
import { CompletionDispatcher } from "./completions.js";

const LINE_EDITOR_STATES: readonly LineEditorState[] = ["unknown", "owned", "released"];

export const FIND_MATCH_WORDS = 5;

export const FIND_STEP_BUDGET = 1000;

const NOOP_HOST: HostCapabilities = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
};

export class TerminalCore {
	private readonly inner: WasmTerminalCore;
	private readonly listeners: Set<ChangeListener> = new Set();
	private readonly completions: CompletionDispatcher;
	private disposed = false;

	constructor(inner: WasmTerminalCore, host: HostCapabilities) {
		this.inner = inner;
		this.completions = new CompletionDispatcher(
			() => decodeBlocks(this.snapshot()).at(-1)?.cwd ?? "",
			host,
		);
	}

	static create(options: TerminalCoreOptions): TerminalCore {
		if (!isInitialized()) {
			throw new Error("terminal core WASM is not initialized");
		}
		const inner = new WasmTerminalCore(options.columns, options.scrollback);
		const core = new TerminalCore(inner, options.host ?? NOOP_HOST);
		if (options.rows !== undefined) {
			core.resize(options.columns, options.rows);
		}
		return core;
	}

	feed(bytes: Uint8Array): void {
		if (this.disposed) {
			return;
		}
		this.inner.feed(bytes);
		const generation = this.inner.generation();
		// Every listener runs even when one throws: the core has already
		// consumed the bytes, so skipping the rest would leave subscribers
		// disagreeing with core state. Failures surface together afterwards.
		let failures: unknown[] | null = null;
		for (const listener of this.listeners) {
			try {
				listener(generation);
			} catch (error) {
				(failures ??= []).push(error);
			}
		}
		if (failures) {
			throw new AggregateError(failures, "terminal core change listener failed");
		}
	}

	snapshot(): TerminalSnapshot {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const memory = getMemory();
		const contentPtr = this.inner.content_ptr();
		const contentLen = this.inner.content_len();
		const rowsPtr = this.inner.rows_ptr();
		const rowsLen = this.inner.rows_len();
		const runRangesPtr = this.inner.run_ranges_ptr();
		const runRangesLen = this.inner.run_ranges_len();
		const stylePairsPtr = this.inner.style_pairs_ptr();
		const stylePairsLen = this.inner.style_pairs_len();
		const blocksPtr = this.inner.blocks_ptr();
		const blocksLen = this.inner.blocks_len();
		const blockTextPtr = this.inner.block_text_ptr();
		const blockTextLen = this.inner.block_text_len();
		validateEvenLength("rows", rowsLen);
		validateEvenLength("runRanges", runRangesLen);
		validateEvenLength("stylePairs", stylePairsLen);
		if (blocksLen % BLOCK_RECORD_WORDS !== 0) {
			throw new Error(
				`blocks length ${blocksLen} is not a multiple of ${BLOCK_RECORD_WORDS}`,
			);
		}
		const altScreen = this.inner.alt_active()
			? {
					rows: this.inner.alt_rows(),
					columns: this.inner.alt_cols(),
					content: u8View(memory, this.inner.alt_content_ptr(), this.inner.alt_content_len()),
					rowRanges: u32View(memory, this.inner.alt_row_ranges_ptr(), this.inner.alt_row_ranges_len()),
					runRanges: u32View(memory, this.inner.alt_run_ranges_ptr(), this.inner.alt_run_ranges_len()),
					stylePairs: u32View(memory, this.inner.alt_style_pairs_ptr(), this.inner.alt_style_pairs_len()),
					cursorRow: this.inner.alt_cursor_row(),
					cursorColumn: this.inner.alt_cursor_col(),
					cursorVisible: this.inner.alt_cursor_visible(),
				}
			: null;
		return {
			generation: this.inner.generation(),
			content: u8View(memory, contentPtr, contentLen),
			rows: u32View(memory, rowsPtr, rowsLen),
			runRanges: u32View(memory, runRangesPtr, runRangesLen),
			stylePairs: u32View(memory, stylePairsPtr, stylePairsLen),
			blocks: u32View(memory, blocksPtr, blocksLen),
			blockText: u8View(memory, blockTextPtr, blockTextLen),
			lineEditorState: this.inner.line_editor_state(),
			cursorRow: this.inner.cursor_row(),
			cursorColumn: this.inner.cursor_col(),
			cursorVisible: this.inner.cursor_visible(),
			altScreen,
			applicationCursorKeys: this.inner.application_cursor_keys(),
			sgrMouse: this.inner.sgr_mouse(),
			bracketedPaste: this.inner.bracketed_paste(),
			mouseTracking: this.inner.mouse_tracking(),
		};
	}

	resize(columns: number, rows: number): void {
		if (this.disposed) {
			return;
		}
		this.inner.resize(columns, rows);
		for (const listener of this.listeners) {
			listener(this.inner.generation());
		}
	}

	findOpen(query: string, isRegex: boolean): number {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		return this.inner.find_open(query, isRegex);
	}

	findStep(id: number, budget: number = FIND_STEP_BUDGET): void {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		this.inner.find_step(id, budget);
	}

	findResults(): FindMatch[] {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const memory = getMemory();
		const ptr = this.inner.find_results_ptr();
		const len = this.inner.find_results_len();
		if (len % FIND_MATCH_WORDS !== 0) {
			throw new Error(
				`find results length ${len} is not a multiple of ${FIND_MATCH_WORDS}`,
			);
		}
		const view = u32View(memory, ptr, len);
		const count = len / FIND_MATCH_WORDS;
		const matches: FindMatch[] = [];
		for (let index = 0; index < count; index += 1) {
			const base = index * FIND_MATCH_WORDS;
			matches.push({
				blockId: `${view[base + 1]!}:${view[base]!}`,
				row: view[base + 2]!,
				byteRangeStart: view[base + 3]!,
				byteRangeEnd: view[base + 4]!,
			});
		}
		return matches;
	}

	findIsComplete(id: number): boolean {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		return this.inner.find_is_complete(id);
	}

	findCancel(id: number): void {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		this.inner.find_cancel(id);
	}

	setAgentTuiMode(on: boolean): void {
		if (this.disposed) {
			return;
		}
		this.inner.setAgentTuiMode(on);
	}

	setBlockBookmarked(id: BlockId, bookmarked: boolean): void {
		if (this.disposed) {
			return;
		}
		const [idLo, idHi] = parseBlockId(id);
		this.inner.set_block_bookmarked(idLo, idHi, bookmarked);
	}

	blockBookmarked(id: BlockId): boolean {
		if (this.disposed) {
			return false;
		}
		const [idLo, idHi] = parseBlockId(id);
		return this.inner.block_bookmarked(idLo, idHi);
	}

	lineEditorState(): LineEditorState {
		return LINE_EDITOR_STATES[this.snapshot().lineEditorState] ?? "unknown";
	}

	onChange(listener: ChangeListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	registerCompletionProvider(provider: CompletionProvider): () => void {
		return this.completions.register(provider);
	}

	requestCompletions(line: string, cursor: number): void {
		this.completions.request(line, cursor);
	}

	cancelCompletions(): void {
		this.completions.cancel();
	}

	onCompletions(listener: CompletionListener): () => void {
		return this.completions.onResult(listener);
	}

	currentCwd(): string {
		return decodeBlocks(this.snapshot()).at(-1)?.cwd ?? "";
	}

	dispose(): void {
		if (this.disposed) {
			return;
		}
		this.disposed = true;
		this.completions.dispose();
		this.listeners.clear();
		this.inner.free();
	}
}

function validateEvenLength(name: string, length: number): void {
	if (length % 2 !== 0) {
		throw new Error(`${name} length ${length} is not even`);
	}
}

function parseBlockId(id: BlockId): [number, number] {
	const separator = id.indexOf(":");
	if (separator < 0) {
		throw new Error(`block id ${id} is not in hi:lo form`);
	}
	const hi = Number.parseInt(id.slice(0, separator), 10);
	const lo = Number.parseInt(id.slice(separator + 1), 10);
	if (!Number.isFinite(hi) || !Number.isFinite(lo)) {
		throw new Error(`block id ${id} is not numeric`);
	}
	return [lo, hi];
}

export type { WasmInput };
