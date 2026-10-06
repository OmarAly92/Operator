import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "./index";

const encode = (text: string) => new TextEncoder().encode(text);
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const RELEASED = "\x1b]7000;v=1;input-released=1\x07";
const TYPED = "\x1b]7000;v=1;typeahead=echo%20caf%c3%a9\x07";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

describe("TerminalCore.takeTypeahead", () => {
	it("hands over the text the shell reported after input-ready exactly once", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + TYPED));
		expect(core.takeTypeahead()).toBe("echo café");
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("returns nothing for a report while a program owns the tty", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + RELEASED + TYPED));
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("returns nothing for a report in a pane no shell has spoken in", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(TYPED));
		expect(core.lineEditorState()).toBe("unknown");
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("notifies change listeners when a report arrives on its own", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY));
		let changes = 0;
		const off = core.onChange(() => {
			changes += 1;
		});
		core.feed(encode(TYPED));
		expect(changes).toBe(1);
		off();
		core.dispose();
	});

	it("returns nothing once the core is disposed", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + TYPED));
		core.dispose();
		expect(core.takeTypeahead()).toBe("");
	});
});
