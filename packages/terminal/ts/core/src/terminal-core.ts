import { WasmTerminalCore } from "../wasm/vt_core.js";
import { BLOCK_RECORD_WORDS, decodeBlocks } from "./blocks.js";
import { CELL_SPAN_WORDS } from "./cell-spans.js";
import { STYLE_RUN_WORDS } from "./style-runs.js";
import {
	getMemory,
	isInitialized,
	u16View,
	u32View,
	u8View,
	type WasmInput,
} from "./wasm-runtime.js";
import type {
	BlockId,
	ChangeListener,
	DirtyRows,
	FindMatch,
	HostCapabilities,
	LineEditorState,
	MemoryStats,
	RowEvent,
	RowEventListener,
	TerminalCoreOptions,
	TerminalLimits,
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

export const FEED_BUDGET_MS = 12;

export const FEED_SLICE_BYTES = 64 * 1024;

export const UNBOUNDED_BYTES = 0xffff_ffff;

function limitsOf(options: TerminalCoreOptions): TerminalLimits {
	if (options.limits) {
		return options.limits;
	}
	if (options.scrollback !== undefined) {
		return { rows: options.scrollback, bytes: UNBOUNDED_BYTES };
	}
	throw new Error("terminal core needs limits or scrollback");
}

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
	private lastNotifiedGeneration = 0;
	private backlog: Uint8Array[] = [];
	private backlogBytes = 0;
	private readonly feedParsedListeners = new Set<(bytes: number) => void>();
	private cached: { generation: number; buffer: ArrayBufferLike; snapshot: TerminalSnapshot } | null = null;
	private readonly rowEventListeners = new Set<RowEventListener>();

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
		const limits = limitsOf(options);
		const inner = new WasmTerminalCore(options.columns, limits.rows, limits.bytes);
		const core = new TerminalCore(inner, options.host ?? NOOP_HOST);
		if (options.rows !== undefined) {
			core.resize(options.columns, options.rows);
		}
		return core;
	}

	memoryStats(): MemoryStats {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const words = this.inner.memory_stats();
		return { contentBytes: words[0]!, styleEntries: words[1]!, rows: words[2]!, blocks: words[3]! };
	}

	staleRowCount(): number {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		return this.inner.stale_row_count();
	}

	feed(bytes: Uint8Array): void {
		if (this.disposed) {
			return;
		}
		this.inner.feed(bytes, nowMs());
		if (!this.notifyIfChanged() && this.inner.synchronized_output()) {
			this.notifyAll();
		}
	}

	enqueue(bytes: Uint8Array): void {
		if (this.disposed || bytes.length === 0) {
			return;
		}
		const wasEmpty = this.backlogBytes === 0;
		this.backlog.push(bytes);
		this.backlogBytes += bytes.length;
		if (wasEmpty) {
			this.notifyAll();
		}
	}

	drain(deadlineMs: number = FEED_BUDGET_MS): { remaining: number } {
		if (this.disposed) {
			return { remaining: 0 };
		}
		const start = nowMs();
		while (this.backlog.length > 0) {
			const head = this.backlog[0]!;
			let slice: Uint8Array;
			if (head.length <= FEED_SLICE_BYTES) {
				slice = head;
				this.backlog.shift();
			} else {
				slice = head.subarray(0, FEED_SLICE_BYTES);
				this.backlog[0] = head.subarray(FEED_SLICE_BYTES);
			}
			this.backlogBytes -= slice.length;
			this.feed(slice);
			for (const listener of [...this.feedParsedListeners]) listener(slice.length);
			if (nowMs() - start >= deadlineMs) {
				break;
			}
		}
		return { remaining: this.backlogBytes };
	}

	hasBacklog(): boolean {
		return this.backlogBytes > 0;
	}

	onFeedParsed(listener: (bytes: number) => void): () => void {
		this.feedParsedListeners.add(listener);
		return () => {
			this.feedParsedListeners.delete(listener);
		};
	}

	tick(nowMs: number): boolean {
		if (this.disposed) {
			return false;
		}
		if (!this.inner.tick(nowMs)) {
			return false;
		}
		this.notifyIfChanged();
		return true;
	}

	synchronizedOutput(): boolean {
		if (this.disposed) {
			return false;
		}
		return this.inner.synchronized_output();
	}

	/** True once a replay READY mark has been parsed on this core. */
	replayReady(): boolean {
		if (this.disposed) {
			return false;
		}
		return this.inner.replay_ready();
	}

	private notifyIfChanged(): boolean {
		const generation = this.inner.generation();
		if (generation === this.lastNotifiedGeneration) {
			return false;
		}
		this.lastNotifiedGeneration = generation;
		this.notifyAll();
		return true;
	}

	private notifyAll(): void {
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

	/** Declares the history rows the next snapshot must have rewrapped. */
	setExportWindow(firstRow: number, lastRow: number): void {
		if (this.disposed) {
			return;
		}
		this.inner.set_export_window(Math.max(0, firstRow), Math.max(0, lastRow));
	}

	snapshot(): TerminalSnapshot {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const generation = this.inner.sync();
		const memory = getMemory();
		const cached = this.cached;
		if (cached && cached.generation === generation && cached.buffer === memory.buffer) {
			return cached.snapshot;
		}
		const snapshot = this.buildSnapshot(memory, generation);
		this.cached = { generation, buffer: memory.buffer, snapshot };
		this.emitRowEvents();
		return snapshot;
	}

	private buildSnapshot(memory: WebAssembly.Memory, generation: number): TerminalSnapshot {
		const contentPtr = this.inner.content_ptr();
		const contentLen = this.inner.content_len();
		const rowsPtr = this.inner.rows_ptr();
		const rowsLen = this.inner.rows_len();
		const runRangesPtr = this.inner.run_ranges_ptr();
		const runRangesLen = this.inner.run_ranges_len();
		const stylePairsPtr = this.inner.style_pairs_ptr();
		const stylePairsLen = this.inner.style_pairs_len();
		const spanRangesPtr = this.inner.span_ranges_ptr();
		const spanRangesLen = this.inner.span_ranges_len();
		const cellSpansPtr = this.inner.cell_spans_ptr();
		const cellSpansLen = this.inner.cell_spans_len();
		const blocksPtr = this.inner.blocks_ptr();
		const blocksLen = this.inner.blocks_len();
		const blockTextPtr = this.inner.block_text_ptr();
		const blockTextLen = this.inner.block_text_len();
		const rowIndentsPtr = this.inner.row_indents_ptr();
		const rowIndentsLen = this.inner.row_indents_len();
		validateEvenLength("rows", rowsLen);
		validateEvenLength("runRanges", runRangesLen);
		if (rowIndentsLen * 2 !== rowsLen) {
			throw new Error(`rowIndents length ${rowIndentsLen} does not match ${rowsLen / 2} rows`);
		}
		validateMultipleOf("stylePairs", stylePairsLen, STYLE_RUN_WORDS);
		validateEvenLength("spanRanges", spanRangesLen);
		if (spanRangesLen !== rowsLen) {
			throw new Error(`spanRanges length ${spanRangesLen} does not match ${rowsLen} rows`);
		}
		validateMultipleOf("cellSpans", cellSpansLen, CELL_SPAN_WORDS);
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
					spanRanges: u32View(memory, this.inner.alt_span_ranges_ptr(), this.inner.alt_span_ranges_len()),
					cellSpans: u32View(memory, this.inner.alt_cell_spans_ptr(), this.inner.alt_cell_spans_len()),
					cursorRow: this.inner.alt_cursor_row(),
					cursorColumn: this.inner.alt_cursor_col(),
					cursorVisible: this.inner.alt_cursor_visible(),
				}
			: null;
		return {
			generation,
			firstStableRow: this.inner.first_stable_row_hi() * 2 ** 32 + this.inner.first_stable_row_lo(),
			historyRows: this.inner.history_rows(),
			content: u8View(memory, contentPtr, contentLen),
			rows: u32View(memory, rowsPtr, rowsLen),
			rowIndents: u16View(memory, rowIndentsPtr, rowIndentsLen),
			runRanges: u32View(memory, runRangesPtr, runRangesLen),
			stylePairs: u32View(memory, stylePairsPtr, stylePairsLen),
			spanRanges: u32View(memory, spanRangesPtr, spanRangesLen),
			cellSpans: u32View(memory, cellSpansPtr, cellSpansLen),
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
			focusReporting: this.inner.focus_reporting(),
			mouseTracking: this.inner.mouse_tracking(),
			mouseTrackingLevel: this.inner.mouse_tracking_level(),
		};
	}

	private emitRowEvents(): void {
		const trimmed = this.inner.row_events_trimmed();
		const remapLen = this.inner.remap_len();
		if (trimmed === 0 && remapLen === 0) return;
		const words = u32View(getMemory(), this.inner.remap_ptr(), remapLen);
		const remap: Array<readonly [number, number]> = [];
		for (let index = 0; index + 1 < words.length; index += 2) remap.push([words[index]!, words[index + 1]!]);
		this.inner.clear_row_events();
		const event: RowEvent = { trimmed, remap: remap.length > 0 ? remap : null };
		for (const listener of [...this.rowEventListeners]) listener(event);
	}

	takeDirty(): DirtyRows {
		if (this.disposed) {
			return { full: false, rows: new Set() };
		}
		this.inner.sync();
		const full = this.inner.dirty_full();
		const rows = new Set<number>(u32View(getMemory(), this.inner.dirty_rows_ptr(), this.inner.dirty_rows_len()));
		this.inner.ack_dirty();
		return { full, rows: full ? new Set() : rows };
	}

	onRowEvents(listener: RowEventListener): () => void {
		this.rowEventListeners.add(listener);
		return () => {
			this.rowEventListeners.delete(listener);
		};
	}

	resize(columns: number, rows: number): void {
		if (this.disposed) {
			return;
		}
		this.inner.resize(columns, rows);
		this.notifyIfChanged();
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

	setGraphemeClusters(on: boolean): void {
		if (this.disposed) return;
		this.inner.setGraphemeClusters(on);
	}

	graphemeClusters(): boolean {
		return this.inner.graphemeClusters();
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
		this.backlog = [];
		this.backlogBytes = 0;
		this.feedParsedListeners.clear();
		this.cached = null;
		this.rowEventListeners.clear();
		this.inner.free();
	}
}

function nowMs(): number {
	return typeof performance !== "undefined" ? performance.now() : Date.now();
}

function validateEvenLength(name: string, length: number): void {
	if (length % 2 !== 0) {
		throw new Error(`${name} length ${length} is not even`);
	}
}

function validateMultipleOf(name: string, length: number, words: number): void {
	if (length % words !== 0) {
		throw new Error(`${name} length ${length} is not a multiple of ${words}`);
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
