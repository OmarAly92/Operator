import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, initTerminalCore } from "./index";

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
		expect([...snapshot.stylePairs]).toEqual([3, 1, 9, 255, 5, 255]);
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
