import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const killLine = key({ key: "Backspace", metaKey: true });

beforeAll(async () => {
	const bytes = await readFile(
		join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"),
	);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function mount(ownership: "owned" | "released" = "owned") {
	const raw: string[] = [];
	const sent: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: (data) => raw.push(data) };
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	if (ownership === "released") core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	return { editor, core, container, raw, sent };
}

function type(editor: LineEditor, text: string): void {
	for (const character of text) {
		editor.handleKey(key({ key: character === "\n" ? "Enter" : character, shiftKey: character === "\n" }));
	}
}

// Submitting is the only way to read the buffer back without the caret span,
// which renders a space of its own on an empty line.
function value(editor: LineEditor, sent: string[]): string {
	editor.handleKey(key({ key: "Enter" }));
	return sent[sent.length - 1] ?? "";
}

describe("killing the line in the editor's own buffer", () => {
	it("removes everything left of the cursor on that line", () => {
		const { editor, sent } = mount();
		type(editor, "git commit --amend");
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("");
	});

	it("keeps what is right of the cursor", () => {
		const { editor, sent } = mount();
		type(editor, "git commit");
		for (let i = 0; i < 6; i += 1) editor.handleKey(key({ key: "ArrowLeft" }));
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("commit");
	});

	// Warp's delete_all_left: at the start of a row it deletes the character
	// before instead of doing nothing, so the row joins the one above it
	// (editor/view/mod.rs, "if the line was empty, move to the previous one").
	// Doing nothing there is the case that reads as a dead key.
	it("joins the line above when the cursor is already at the start", () => {
		const { editor, sent } = mount();
		type(editor, "one\ntwo");
		for (let i = 0; i < 3; i += 1) editor.handleKey(key({ key: "ArrowLeft" }));
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("onetwo");
	});

	it("leaves the lines above a killed line alone", () => {
		const { editor, sent } = mount();
		type(editor, "one\ntwo three");
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("one\n");
	});

	it("does nothing at the very start of an empty buffer", () => {
		const { editor, sent } = mount();
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("");
	});

	it("kills each line in turn until the buffer is empty", () => {
		const { editor, sent } = mount();
		type(editor, "one\ntwo");
		editor.handleKey(killLine);
		editor.handleKey(killLine);
		editor.handleKey(killLine);
		expect(value(editor, sent)).toBe("");
	});

	it("kills forward to the end of the line on Command+Delete", () => {
		const { editor, sent } = mount();
		type(editor, "git commit --amend");
		for (let i = 0; i < 8; i += 1) editor.handleKey(key({ key: "ArrowLeft" }));
		editor.handleKey(key({ key: "Delete", metaKey: true }));
		expect(value(editor, sent)).toBe("git commit");
	});

	it("does not pull the next line up on Command+Delete at the line end", () => {
		const { editor, sent } = mount();
		type(editor, "one\ntwo");
		for (let i = 0; i < 3; i += 1) editor.handleKey(key({ key: "ArrowLeft" }));
		editor.handleKey(key({ key: "ArrowLeft" }));
		editor.handleKey(key({ key: "Delete", metaKey: true }));
		expect(value(editor, sent)).toBe("one\ntwo");
	});
});

describe("killing the line while a child owns it", () => {
	it("sends NAK and leaves the editor's buffer alone", () => {
		const { editor, container, raw } = mount("released");
		editor.handleKey(killLine);
		expect(raw).toEqual(["\x15"]);
		expect(container.textContent).toBe("");
	});

	it("sends VT for Command+Delete", () => {
		const { editor, raw } = mount("released");
		editor.handleKey(key({ key: "Delete", metaKey: true }));
		expect(raw).toEqual(["\x0b"]);
	});
});

describe("killing the line with an overlay open", () => {
	it("clears the reverse-search query rather than one character of it", () => {
		const { editor, container } = mount();
		editor.handleKey(key({ key: "r", ctrlKey: true }));
		type(editor, "git");
		expect(container.querySelector(".terminal-editor-search")?.textContent).toContain("git");
		editor.handleKey(killLine);
		const search = container.querySelector(".terminal-editor-search")?.textContent ?? "";
		expect(search).not.toContain("g");
	});
});
