import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import type { CommandHistoryEntry, CommandHistorySource } from "./history";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const block = (cmd: string) =>
	`\x1b]133;A\x07\x1b]7000;v=1;cmd=${encodeURIComponent(cmd)}\x07\x1b]133;C\x07ok\r\n\x1b]133;D;0\x07`;

beforeAll(async () => {
	const bytes = await readFile(join(process.cwd(), "../core/wasm/vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function fakeSource(initial: CommandHistoryEntry[]) {
	let entries = initial;
	const listeners = new Set<() => void>();
	let refreshes = 0;
	const source: CommandHistorySource = {
		entries: () => entries,
		subscribe: (listener) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
		refresh: () => {
			refreshes += 1;
		},
	};
	return {
		source,
		refreshes: () => refreshes,
		listeners: () => listeners.size,
		land(next: CommandHistoryEntry[]) {
			entries = next;
			for (const listener of [...listeners]) listener();
		},
	};
}

function mount() {
	const sent: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: () => {} };
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	return { editor, core, sent, container };
}

function recall(editor: LineEditor, presses: number): void {
	for (let index = 0; index < presses; index += 1) editor.handleKey(key({ key: "ArrowUp" }));
}

describe("LineEditor shared history", () => {
	it("reaches commands from other terminals and earlier runs, newest first", () => {
		const { editor, core, sent } = mount();
		const shared = fakeSource([
			{ command: "make build", at: 1 },
			{ command: "npm test", at: 2 },
		]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["make build"]);
	});

	it("puts this pane's newer commands ahead of older shared ones and never repeats one", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([
			{ command: "ls", at: 1 },
			{ command: "make", at: 2 },
		]).source);
		core.feed(encode(block("ls") + READY));
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["make"]);
	});

	it("asks the source to refresh once per walk", () => {
		const { editor, core } = mount();
		const shared = fakeSource([{ command: "a", at: 1 }]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 3);
		editor.handleKey(key({ key: "ArrowDown" }));
		expect(shared.refreshes()).toBe(1);
		editor.handleKey(key({ key: "x" }));
		recall(editor, 1);
		expect(shared.refreshes()).toBe(2);
	});

	it("walks this pane's own commands before commands another pane ran later", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([{ command: "cargo build", at: Date.now() + 60_000 }]).source);
		core.feed(encode(block("ls") + READY));
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls"]);
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls", "cargo build"]);
	});

	it("keeps the recalled command when a refresh lands during the walk", () => {
		const { editor, core, sent } = mount();
		const shared = fakeSource([
			{ command: "one", at: 1 },
			{ command: "two", at: 2 },
		]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 1);
		shared.land([
			{ command: "one", at: 1 },
			{ command: "two", at: 2 },
			{ command: "three", at: 3 },
		]);
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["one"]);
	});

	it("recalls a multi-line shared command whole", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([{ command: "for f in a b; do\n  echo $f\ndone", at: 1 }]).source);
		core.feed(encode(READY));
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["for f in a b; do\n  echo $f\ndone"]);
	});

	it("suggests from shared history as ghost text", () => {
		const { editor, core, container } = mount();
		editor.setHistorySource(fakeSource([{ command: "docker compose up", at: 1 }]).source);
		core.feed(encode(READY));
		editor.setText("docker c");
		expect(container.querySelector(".terminal-editor-ghost")?.textContent).toBe("ompose up");
	});

	it("drops its subscription when the source changes or the editor is disposed", () => {
		const { editor } = mount();
		const first = fakeSource([]);
		const second = fakeSource([]);
		editor.setHistorySource(first.source);
		editor.setHistorySource(second.source);
		expect(first.listeners()).toBe(0);
		expect(second.listeners()).toBe(1);
		editor.dispose();
		expect(second.listeners()).toBe(0);
	});
});
