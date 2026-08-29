import { WasmTerminalCore } from "../wasm/vt_core.js";
import { BLOCK_RECORD_WORDS } from "./blocks.js";
import {
	getMemory,
	isInitialized,
	u32View,
	u8View,
	type WasmInput,
} from "./wasm-runtime.js";
import type {
	ChangeListener,
	TerminalCoreOptions,
	TerminalSnapshot,
} from "./types.js";

export class TerminalCore {
	private readonly inner: WasmTerminalCore;
	private readonly listeners: Set<ChangeListener> = new Set();
	private disposed = false;

	constructor(inner: WasmTerminalCore) {
		this.inner = inner;
	}

	static create(options: TerminalCoreOptions): TerminalCore {
		if (!isInitialized()) {
			throw new Error("terminal core WASM is not initialized");
		}
		const inner = new WasmTerminalCore(options.columns, options.scrollback);
		return new TerminalCore(inner);
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
		return {
			generation: this.inner.generation(),
			content: u8View(memory, contentPtr, contentLen),
			rows: u32View(memory, rowsPtr, rowsLen),
			runRanges: u32View(memory, runRangesPtr, runRangesLen),
			stylePairs: u32View(memory, stylePairsPtr, stylePairsLen),
			blocks: u32View(memory, blocksPtr, blocksLen),
			blockText: u8View(memory, blockTextPtr, blockTextLen),
		};
	}

	onChange(listener: ChangeListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	dispose(): void {
		if (this.disposed) {
			return;
		}
		this.disposed = true;
		this.listeners.clear();
		this.inner.free();
	}
}

function validateEvenLength(name: string, length: number): void {
	if (length % 2 !== 0) {
		throw new Error(`${name} length ${length} is not even`);
	}
}

export type { WasmInput };
