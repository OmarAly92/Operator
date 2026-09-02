import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";

const encode = (text: string) => new TextEncoder().encode(text);

beforeAll(async () => {
	const bytes = await readFile(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"));
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function mount() {
	const sent: string[] = [];
	const raw: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: (data) => raw.push(data) };
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	const root = container.querySelector<HTMLElement>(".terminal-editor")!;
	return { editor, core, root, sent, raw };
}

function paste(root: HTMLElement, clipboard: { text?: string; types?: string[] }): Event {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: {
			types: clipboard.types ?? (clipboard.text === undefined ? [] : ["text/plain"]),
			getData: () => clipboard.text ?? "",
			files: [],
		},
	});
	root.dispatchEvent(event);
	return event;
}

describe("pasting into the line editor", () => {
	it("inserts into the buffer while the editor owns the line", () => {
		const { core, root } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		paste(root, { text: "git status" });
		expect(root.textContent).toContain("git status");
	});

	it("sends the text to the child that owns the line", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { text: "one\ntwo" });
		expect(raw).toEqual(["one\rtwo"]);
	});

	it("brackets the paste when the child asked for bracketed paste", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07\x1b[?2004h"));
		paste(root, { text: "one\ntwo" });
		expect(raw).toEqual(["\x1b[200~one\rtwo\x1b[201~"]);
	});

	it("turns an image into the Ctrl+V the child reads its own clipboard on", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { types: ["image/png"] });
		expect(raw).toEqual(["\x16"]);
	});

	it("always takes the paste away from the browser's own handling", () => {
		const { core, root } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		expect(paste(root, { text: "x" }).defaultPrevented).toBe(true);
	});
});
