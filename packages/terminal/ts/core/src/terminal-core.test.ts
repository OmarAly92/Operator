import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore, type RowEvent } from "./index";
import { WasmTerminalCore } from "../wasm/vt_core.js";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

describe("TerminalCore", () => {
	it("reads flat content and style pairs directly from WASM memory", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		core.feed(new TextEncoder().encode("[31mred[0m café\r\nplain"));
		const snapshot = core.snapshot();

		expect(snapshot.content).toBeInstanceOf(Uint8Array);
		expect(snapshot.rows).toBeInstanceOf(Uint32Array);
		expect(snapshot.stylePairs).toBeInstanceOf(Uint32Array);
		expect(snapshot.runRanges).toBeInstanceOf(Uint32Array);
		expect(new TextDecoder().decode(snapshot.content)).toBe("red caféplain");
		expect([...snapshot.rows]).toEqual([0, 9, 9, 14]);
		expect([...snapshot.stylePairs]).toEqual([3, 1, 254, 0, 255, 9, 255, 254, 0, 255, 5, 255, 254, 0, 255]);
	});

	it("exports cell spans for wide and joined clusters", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 10 });
		core.feed(new TextEncoder().encode("ab漢c\r\né"));
		const snapshot = core.snapshot();
		expect([...snapshot.spanRanges]).toEqual([0, 1, 1, 2]);
		expect([...snapshot.cellSpans]).toEqual([2, 5, 2, 0, 3, 1]);
	});

	it("exports one wrapped byte per row and joins logical lines from it", () => {
		const core = createTerminalCore({ columns: 4, scrollback: 100 });
		core.resize(4, 3);
		core.feed(new TextEncoder().encode("abc def\r\nxy"));
		const snapshot = core.snapshot();
		expect(snapshot.rowWrapped.length).toBe(snapshot.rows.length / 2);
		expect([...snapshot.rowWrapped.subarray(0, 3)]).toEqual([1, 0, 0]);
		expect(core.logicalLines({ start: 1, end: 2 })).toEqual([
			{ firstRow: 0, rowCount: 2, text: "abc def", rowOffsets: [0, 4] },
		]);
		expect(core.logicalLines({ start: 0, end: 3 })).toEqual([
			{ firstRow: 0, rowCount: 2, text: "abc def", rowOffsets: [0, 4] },
			{ firstRow: 2, rowCount: 1, text: "xy", rowOffsets: [0] },
		]);
	});

	it("creates independent instances that do not share state", () => {
		const a = createTerminalCore({ columns: 16, scrollback: 100 });
		const b = createTerminalCore({ columns: 16, scrollback: 100 });
		a.feed(new TextEncoder().encode("alpha"));
		expect(new TextDecoder().decode(b.snapshot().content)).toBe("");
		expect(new TextDecoder().decode(a.snapshot().content)).toBe("alpha");
	});

	it("reports line-editor ownership exactly as the shell states it", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		expect(core.lineEditorState()).toBe("unknown");
		core.feed(new TextEncoder().encode("\x1b]7000;v=1;input-ready=1\x07"));
		expect(core.lineEditorState()).toBe("owned");
		core.feed(new TextEncoder().encode("\x1b]7000;v=1;input-released=1\x07"));
		expect(core.lineEditorState()).toBe("released");
		core.dispose();
	});

	it("publishes the mouse tracking level on the snapshot", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		expect(core.snapshot().mouseTrackingLevel).toBe(0);
		core.feed(new TextEncoder().encode("\x1b[?1002h"));
		expect(core.snapshot().mouseTrackingLevel).toBe(0b010);
		expect(core.snapshot().mouseTracking).toBe(true);
	});

	it("exports the first stable row and keeps it across a trim", () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const encoder = new TextEncoder();
		for (const line of ["1", "2", "3", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		expect(core.snapshot().firstStableRow).toBe(0);
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		const snapshot = core.snapshot();
		expect(snapshot.firstStableRow).toBe(1);
		const flat = 2 - snapshot.firstStableRow;
		expect(new TextDecoder().decode(snapshot.content.subarray(snapshot.rows[flat * 2]!, snapshot.rows[flat * 2 + 1]!))).toBe("3");
	});

	it("snapshot is cached per generation", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100, rows: 1 });
		core.feed(new TextEncoder().encode("one\r\n"));
		const first = core.snapshot();
		expect(core.snapshot()).toBe(first);
		expect(decodeBlocks(first)).toBe(decodeBlocks(first));
		core.feed(new TextEncoder().encode("two\r\n"));
		const second = core.snapshot();
		expect(second).not.toBe(first);
		expect(second.generation).not.toBe(first.generation);
		expect(second.historyRows).toBe(2);
		expect(second.rows.length / 2).toBeGreaterThan(second.historyRows);
	});

	it("feed alone does not export", () => {
		const sync = vi.spyOn(WasmTerminalCore.prototype, "sync");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		sync.mockClear();
		core.feed(new TextEncoder().encode("alpha\r\n"));
		core.feed(new TextEncoder().encode("beta\r\n"));
		expect(sync).not.toHaveBeenCalled();
		core.snapshot();
		expect(sync).toHaveBeenCalledTimes(1);
		core.snapshot();
		expect(sync).toHaveBeenCalledTimes(2);
	});

	it("still notifies onChange per parsed feed without exporting", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const generations: number[] = [];
		core.onChange((generation) => generations.push(generation));
		core.feed(new TextEncoder().encode("a"));
		core.feed(new TextEncoder().encode("b"));
		expect(generations).toHaveLength(2);
		expect(generations[0]).not.toBe(generations[1]);
	});

	it("accumulates dirty stable rows until they are taken", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100, rows: 3 });
		core.snapshot();
		expect(core.takeDirty().full).toBe(true);
		core.feed(new TextEncoder().encode("a\r\nb"));
		core.snapshot();
		core.feed(new TextEncoder().encode("\x1b[1;1HX"));
		core.snapshot();
		const dirty = core.takeDirty();
		expect(dirty.full).toBe(false);
		expect([...dirty.rows].sort((x, y) => x - y)).toEqual([0, 1]);
		expect(core.takeDirty()).toEqual({ full: false, rows: new Set() });
	});

	it("emits row events for a trim and a rewrap", () => {
		const core = createTerminalCore({ columns: 20, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const events: RowEvent[] = [];
		core.onRowEvents((event) => events.push(event));
		const encoder = new TextEncoder();
		core.snapshot();
		for (const line of ["1", "2", "3", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		core.snapshot();
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		core.snapshot();
		expect(events).toEqual([{ trimmed: 1, remap: null }]);
		core.feed(encoder.encode("aaaaaaaaaabbbbbbbbbbcccccccccc\r\n"));
		core.snapshot();
		core.resize(40, 2);
		core.snapshot();
		const remap = events.at(-1)!.remap!;
		expect(remap.length).toBeGreaterThan(0);
		expect(remap.every(([from, to]) => to <= from)).toBe(true);
		expect(core.snapshot().firstStableRow).toBeGreaterThan(0);
	});

	it("lays a ZWJ family out over two cells once grapheme clusters are on", () => {
		const family = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";
		const off = createTerminalCore({ columns: 20, scrollback: 10 });
		off.feed(new TextEncoder().encode(family));
		expect(off.graphemeClusters()).toBe(false);
		expect(off.snapshot().cursorColumn).toBe(6);
		const on = createTerminalCore({ columns: 20, scrollback: 10 });
		on.setGraphemeClusters(true);
		expect(on.graphemeClusters()).toBe(true);
		on.feed(new TextEncoder().encode(family));
		expect(on.snapshot().cursorColumn).toBe(2);
	});
});

describe("TerminalCore.onChange failure isolation", () => {
	it("runs every listener and reports the failures together", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const later = vi.fn();
		core.onChange(() => {
			throw new Error("renderer exploded");
		});
		core.onChange(later);

		expect(() => core.feed(new TextEncoder().encode("x"))).toThrow(AggregateError);
		expect(later).toHaveBeenCalledTimes(1);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("x");
	});
});

describe("TerminalCore.onChange", () => {
	it("fires once per successful feed and unsubscribes cleanly", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		const off = core.onChange(listener);
		core.feed(new TextEncoder().encode("first"));
		core.feed(new TextEncoder().encode("second"));
		expect(listener).toHaveBeenCalledTimes(2);
		off();
		core.feed(new TextEncoder().encode("third"));
		expect(listener).toHaveBeenCalledTimes(2);
	});
});

describe("TerminalCore.dispose", () => {
	it("frees the generated instance and clears listeners", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		core.feed(new TextEncoder().encode("hello"));
		expect(listener).toHaveBeenCalledTimes(1);
		core.dispose();
		core.feed(new TextEncoder().encode("after"));
		expect(listener).toHaveBeenCalledTimes(1);
	});
});

describe("createTerminalCore invalid options", () => {
	it("preserves the Rust error for zero columns", () => {
		expect(() => createTerminalCore({ columns: 0, scrollback: 100 })).toThrow();
	});

	it("preserves the Rust error for zero scrollback", () => {
		expect(() => createTerminalCore({ columns: 16, scrollback: 0 })).toThrow();
	});
});

describe("TerminalCore replay ready", () => {
	it("reports the replay as ready only once the mark is parsed", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		expect(core.replayReady()).toBe(false);
		core.enqueue(new TextEncoder().encode("frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		expect(core.replayReady()).toBe(false);
		core.drain();
		expect(core.replayReady()).toBe(true);
	});

	it("notifies a change on the feed that parses the ready mark", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		let ready = false;
		core.onChange(() => {
			ready = ready || core.replayReady();
		});
		core.feed(new TextEncoder().encode("frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		expect(ready).toBe(true);
	});
});

describe("TerminalCore alternate screen", () => {
	it("exposes the alternate grid with a cursor, and nothing when inactive", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.resize(20, 5);
		expect(core.snapshot().altScreen).toBeNull();
		core.feed(new TextEncoder().encode("\x1b[?1049h\x1b[2;3Hhi"));
		const alt = core.snapshot().altScreen;
		expect(alt).not.toBeNull();
		expect(alt!.rows).toBe(5);
		expect(alt!.columns).toBe(20);
		expect(alt!.cursorRow).toBe(1);
		expect(alt!.cursorColumn).toBe(4);
		expect(alt!.cursorVisible).toBe(true);
		const text = new TextDecoder().decode(
			alt!.content.subarray(alt!.rowRanges[2], alt!.rowRanges[3]),
		);
		expect(text.trimEnd()).toBe("  hi");
		core.dispose();
	});

	it("reports no scrollback for the alternate buffer", () => {
		const core = createTerminalCore({ columns: 10, scrollback: 5000 });
		core.resize(10, 3);
		core.feed(new TextEncoder().encode("\x1b[?1049h"));
		for (let i = 0; i < 50; i += 1) {
			core.feed(new TextEncoder().encode(`line ${i}\r\n`));
		}
		expect(core.snapshot().altScreen!.rowRanges.length / 2).toBe(3);
		core.dispose();
	});

	it("reports application cursor keys, and keeps reporting it after the program leaves", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		expect(core.snapshot().applicationCursorKeys).toBe(false);
		core.feed(new TextEncoder().encode("\x1b[?1049h\x1b[?1h"));
		expect(core.snapshot().applicationCursorKeys).toBe(true);
		core.feed(new TextEncoder().encode("\x1b[?1049l"));
		expect(core.snapshot().applicationCursorKeys).toBe(true);
		core.dispose();
	});

	it("drops the alternate view when the program leaves", () => {
		const core = createTerminalCore({ columns: 10, scrollback: 100 });
		core.feed(new TextEncoder().encode("\x1b[?1049hx\x1b[?1049l"));
		expect(core.snapshot().altScreen).toBeNull();
		core.dispose();
	});
});

describe("TerminalCore synchronized output", () => {
	const BSU = "\x1b[?2026h";
	const ESU = "\x1b[?2026l";

	it("notifies a pending sync block without exposing it, and flushes on the terminator", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		const generationBefore = core.snapshot().generation;
		core.feed(new TextEncoder().encode(`${BSU}hidden`));
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.snapshot().generation).toBe(generationBefore);
		expect(core.synchronizedOutput()).toBe(true);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("");
		core.feed(new TextEncoder().encode(ESU));
		expect(listener).toHaveBeenCalledTimes(2);
		expect(core.synchronizedOutput()).toBe(false);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("hidden");
	});

	it("tick past the deadline flushes and notifies", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		const start = performance.now();
		core.feed(new TextEncoder().encode(`${BSU}late`));
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.tick(start + 100)).toBe(false);
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.tick(start + 200)).toBe(true);
		expect(listener).toHaveBeenCalledTimes(2);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("late");
	});
});

describe("TerminalCore feed budget", () => {
	function rows(count: number): Uint8Array {
		let text = "";
		for (let index = 0; index < count; index += 1) text += `row ${String(index).padStart(6, "0")}\r\n`;
		return new TextEncoder().encode(text);
	}

	it("a 1 MiB enqueue drains over several frames in order", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		const bytes = rows(100000);
		expect(bytes.length).toBeGreaterThan(1024 * 1024);
		core.enqueue(bytes);
		expect(core.hasBacklog()).toBe(true);
		let calls = 0;
		while (core.drain(0).remaining > 0) calls += 1;
		expect(calls).toBeGreaterThan(10);
		expect(core.hasBacklog()).toBe(false);
		const snapshot = core.snapshot();
		const text = new TextDecoder().decode(snapshot.content);
		expect(text.startsWith("row 000000row 000001")).toBe(true);
		expect(text.endsWith("row 099999")).toBe(true);
	});

	it("drain stops at the deadline", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		core.enqueue(rows(100000));
		let tick = 0;
		const spy = vi.spyOn(performance, "now").mockImplementation(() => (tick += 20));
		const { remaining } = core.drain(12);
		spy.mockRestore();
		expect(remaining).toBeGreaterThan(0);
		expect(new TextDecoder().decode(core.snapshot().content).length).toBeLessThanOrEqual(64 * 1024);
	});

	it("onFeedParsed fires per slice", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		const parsed = vi.fn();
		core.onFeedParsed(parsed);
		core.enqueue(rows(20000));
		while (core.drain(0).remaining > 0) {}
		expect(parsed.mock.calls.length).toBeGreaterThan(2);
		const total = parsed.mock.calls.reduce((sum, [bytes]) => sum + (bytes as number), 0);
		expect(total).toBe(rows(20000).length);
	});

	it("enqueue notifies onChange once when the backlog becomes non-empty", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		core.enqueue(new TextEncoder().encode("a"));
		core.enqueue(new TextEncoder().encode("b"));
		expect(listener).toHaveBeenCalledTimes(1);
		core.drain();
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("ab");
	});

	it("takes limits or the scrollback alias and reports memory stats", () => {
		const limited = createTerminalCore({ columns: 40, limits: { rows: 100_000, bytes: 8192 } });
		const encoder = new TextEncoder();
		for (let i = 0; i < 600; i += 1) limited.feed(encoder.encode(`row ${String(i).padStart(5, "0")} xxxxxxxxxx\r\n`));
		const stats = limited.memoryStats();
		expect(stats.contentBytes + stats.styleEntries * 16).toBeLessThanOrEqual(8192);
		expect(stats.rows).toBeGreaterThan(100);
		expect(stats.rows).toBeLessThan(600);
		const alias = createTerminalCore({ columns: 40, scrollback: 50 });
		for (let i = 0; i < 100; i += 1) alias.feed(encoder.encode(`row ${i}\r\n`));
		expect(alias.memoryStats().rows).toBe(49);
		expect(() => createTerminalCore({ columns: 40 } as never)).toThrow(/limits/);
	});

	it("rewraps the declared window before the snapshot it hands back", () => {
		const core = createTerminalCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		for (let index = 0; index < 3000; index += 1) {
			core.feed(new TextEncoder().encode(`the quick brown fox jumps over the lazy dog ${index}\r\n`));
		}
		core.resize(20, 24);
		const cold = core.snapshot();
		const decodeRow = (snapshot: typeof cold, index: number) =>
			new TextDecoder().decode(snapshot.content.subarray(snapshot.rows[2 * index]!, snapshot.rows[2 * index + 1]!));
		expect(decodeRow(cold, 0).length).toBeGreaterThan(20);

		core.setExportWindow(0, 40);
		const warm = core.snapshot();
		expect(decodeRow(warm, 0).length).toBeLessThanOrEqual(20);
	});

	it("does not re-rewrap a window it has already served", () => {
		const core = createTerminalCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		for (let index = 0; index < 3000; index += 1) {
			core.feed(new TextEncoder().encode(`the quick brown fox jumps over the lazy dog ${index}\r\n`));
		}
		core.resize(20, 24);
		core.setExportWindow(0, 40);
		const first = core.snapshot().generation;
		core.setExportWindow(0, 40);
		expect(core.snapshot().generation).toBe(first);
	});
});
