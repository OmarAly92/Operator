import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;

beforeAll(async () => {
	const bytes = await readFile(
		join(process.cwd(), "../core/wasm/vt_core_bg.wasm"),
	);
	const wasm = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasm);
});

function mount() {
	const sent: string[] = [];
	const raw: string[] = [];
	const host: EditorHost & { sent: string[]; raw: string[] } = {
		send: (text) => sent.push(text),
		sendRaw: (data) => raw.push(data),
		sent,
		raw,
	};
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	return { editor, host, core, container };
}

describe("LineEditor ownership", () => {
	it("is read-only and passes keystrokes straight through while Released", () => {
		const { editor, host, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		editor.handleKey(key({ key: "l" }));
		editor.handleKey(key({ key: "s" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual([]);
		expect(host.raw.join("")).toBe("ls\r");
	});

	it("is read-only and passes keystrokes straight through while Unknown", () => {
		const { editor, host } = mount();
		editor.handleKey(key({ key: "x" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual([]);
		expect(host.raw.join("")).toBe("x\r");
	});

	it("preserves terminal editing sequences outside Owned", () => {
		const { editor, host } = mount();
		editor.handleKey(key({ key: "Delete" }));
		editor.handleKey(key({ key: "ArrowLeft", altKey: true }));
		editor.handleKey(key({ key: "r", ctrlKey: true }));
		expect(host.raw.join("")).toBe("\x1b[3~\x1bb\x12");
	});

	it("edits locally and submits once Owned", () => {
		const { editor, host, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		editor.handleKey(key({ key: "l" }));
		editor.handleKey(key({ key: "s" }));
		expect(host.raw).toEqual([]);
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual(["ls"]);
	});

	it("clears the buffer after submitting so the next command starts empty", () => {
		const { editor, host, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		editor.handleKey(key({ key: "a" }));
		editor.handleKey(key({ key: "Enter" }));
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		editor.handleKey(key({ key: "b" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual(["a", "b"]);
	});

	it("keeps Ctrl-C a passthrough even while Owned", () => {
		const { editor, host, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		editor.handleKey(key({ key: "c", ctrlKey: true }));
		expect(host.raw.join("")).toBe("\x03");
	});
});
