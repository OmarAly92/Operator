import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import { acceptTypeahead, CLEAR_SHELL_LINE, TYPEAHEAD_MAX_CHARS } from "./typeahead";

const here = dirname(fileURLToPath(import.meta.url));
const encode = (text: string) => new TextEncoder().encode(text);
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const RELEASED = "\x1b]7000;v=1;input-released=1\x07";
const report = (text: string) => `\x1b]7000;v=1;typeahead=${encodeURIComponent(text)}\x07`;

beforeAll(async () => {
	const bytes = await readFile(join(here, "..", "..", "core", "wasm", "vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function mount() {
	const sent: string[] = [];
	const raw: string[] = [];
	const drafts: string[] = [];
	const host: EditorHost = {
		send: (text) => sent.push(text),
		sendRaw: (data) => raw.push(data),
		onDraftChange: (draft) => drafts.push(draft),
	};
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	const root = container.querySelector<HTMLElement>(".terminal-editor")!;
	const lines = () => [...container.querySelectorAll(".terminal-editor-line")].map((line) => line.textContent?.replace(/ /g, "") ?? "");
	return { editor, core, root, sent, raw, drafts, lines };
}

function typeWhileRunning(editor: LineEditor, text: string) {
	for (const character of text) editor.handleKey(key({ key: character }));
}

function paste(root: HTMLElement, text: string) {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: { types: ["text/plain"], getData: () => text, files: [] },
	});
	root.dispatchEvent(event);
}

describe("typing ahead into the line editor", () => {
	it("forgets keys sent during an earlier command once the next command starts", () => {
		const { editor, core, raw, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "y");
		core.feed(encode(READY));
		core.feed(encode(RELEASED));
		core.feed(encode(READY + report("echo from-elsewhere")));
		expect(lines()).toEqual([""]);
		expect(raw.join("")).toBe("y");
	});

	it("puts the text the shell reports into the input box without running it", () => {
		const { editor, core, sent, raw, drafts, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "echo hi");
		expect(raw.join("")).toBe("echo hi");
		core.feed(encode(READY + report("echo hi")));
		expect(lines()).toEqual(["echo hi"]);
		expect(drafts.at(-1)).toBe("echo hi");
		expect(sent).toEqual([]);
		expect(raw.join("")).toBe("echo hi\x15");
	});

	it("submits the adopted text once, so the shell never sees it twice", () => {
		const { editor, core, sent, raw } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "ls");
		core.feed(encode(READY + report("ls")));
		editor.handleKey(key({ key: " " }));
		editor.handleKey(key({ key: "-" }));
		editor.handleKey(key({ key: "a" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls -a"]);
		expect(raw).toEqual(["l", "s", CLEAR_SHELL_LINE]);
	});

	it("appends the report to a draft the host put back while the command ran", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		editor.setText("git ");
		typeWhileRunning(editor, "status");
		core.feed(encode(READY + report("status")));
		expect(lines()).toEqual(["git status"]);
	});

	it("counts a paste sent to the running command as typing ahead", async () => {
		const { core, root, lines } = mount();
		core.feed(encode(READY + RELEASED));
		paste(root, "make test");
		await settle();
		core.feed(encode(READY + report("make test")));
		expect(lines()).toEqual(["make test"]);
	});

	it("leaves a report it did not type to the shell: nothing shown, the shell's line not cleared", () => {
		const { core, lines, drafts, raw } = mount();
		core.feed(encode(READY + RELEASED));
		core.feed(encode(READY + report("rm -rf ~")));
		expect(lines()).toEqual([""]);
		expect(drafts).toEqual([]);
		expect(raw).toEqual([]);
	});

	it("adopts one report per burst of typing", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "a");
		core.feed(encode(READY + report("a")));
		editor.handleKey(key({ key: "Enter" }));
		core.feed(encode(RELEASED + READY + report("b")));
		expect(lines()).toEqual([""]);
	});

	it("drops a report carrying a control character or longer than the cap, and leaves the shell's line alone", () => {
		const { editor, core, lines, raw } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "x");
		core.feed(encode(READY + report("ls\nrm -rf ~")));
		expect(lines()).toEqual([""]);
		core.feed(encode(RELEASED));
		typeWhileRunning(editor, "x");
		core.feed(encode(READY + report("y".repeat(TYPEAHEAD_MAX_CHARS + 1))));
		expect(lines()).toEqual([""]);
		expect(raw).toEqual(["x", "x"]);
	});

	it("takes a report while the pane is hidden and shows it when the pane is shown", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "pwd");
		editor.setVisible(false);
		core.feed(encode(READY + report("pwd")));
		expect(core.takeTypeahead()).toBe("");
		editor.setVisible(true);
		expect(lines()).toEqual(["pwd"]);
	});

	it("stops taking reports once disposed", () => {
		const { editor, core } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "ls");
		editor.dispose();
		core.feed(encode(READY + report("ls")));
		expect(core.takeTypeahead()).toBe("ls");
	});

	it("leaves a Claude Code pane exactly as before: every key goes to Claude, nothing reaches the box", async () => {
		const recording = await readFile(join(here, "..", "..", "..", "bench", "agent-session", "fixtures", "claude-spinner-10s", "recording"));
		const { editor, core, root, raw, sent, lines, drafts } = mount();
		core.feed(new Uint8Array(recording));
		expect(root.dataset.ownership).toBe("unknown");
		typeWhileRunning(editor, "yes");
		editor.handleKey(key({ key: "Enter" }));
		expect(raw).toEqual(["y", "e", "s", "\r"]);
		core.feed(encode(report("yes")));
		expect(lines()).toEqual([]);
		expect(drafts).toEqual([]);
		expect(sent).toEqual([]);
	});
});

describe("acceptTypeahead", () => {
	it("keeps printable text up to the cap, counted in characters", () => {
		expect(acceptTypeahead("echo café €")).toBe("echo café €");
		expect(acceptTypeahead("é".repeat(TYPEAHEAD_MAX_CHARS))).toBe("é".repeat(TYPEAHEAD_MAX_CHARS));
		expect(acceptTypeahead("é".repeat(TYPEAHEAD_MAX_CHARS + 1))).toBeNull();
	});

	it("refuses empty text and any C0, DEL or C1 control", () => {
		expect(acceptTypeahead("")).toBeNull();
		for (const control of ["\t", "\n", "\r", "\x1b[A", "\x7f", "\x9b"]) {
			expect(acceptTypeahead(`ls${control}`)).toBeNull();
		}
	});
});
