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
	it("renders a prompt row from the newest block and ownership state", () => {
		const { container, core } = mount();
		core.feed(
			encode(
				"\x1b]133;A\x07\x1b]7000;v=1;cmd=false;cwd=%2FUsers%2Fx%2Fsrc%2Fapp;branch=main\x07\x1b]133;C\x07\x1b]133;D;1\x07\x1b]7000;v=1;input-ready=1\x07",
			),
		);
		const prompt = container.querySelector<HTMLElement>(".terminal-editor-prompt");
		expect(prompt?.textContent).toContain("app");
		expect(prompt?.textContent).toContain("main");
		expect(prompt?.dataset.lastExit).toBe("1");
		expect(prompt?.dataset.state).toBe("owned");
	});

	it("renders command syntax tokens without changing the buffer text", () => {
		const { editor, container } = mount();
		editor.setText("git status");
		const tokens = [...container.querySelectorAll<HTMLElement>(".terminal-editor-token")];
		expect(tokens.map((token) => [token.dataset.tokenKind, token.textContent])).toEqual([
			["command", "git"],
			["argument", "status"],
		]);
	});

	it("suggests mark-derived history and accepts the ghost with ArrowRight", () => {
		const { editor, container, core, host } = mount();
		core.feed(
			encode(
				"\x1b]133;A\x07\x1b]7000;v=1;cmd=git%20status\x07\x1b]133;C\x07ok\n\x1b]133;D;0\x07\x1b]7000;v=1;input-ready=1\x07",
			),
		);
		editor.setText("git ");
		expect(container.querySelector(".terminal-editor-ghost")?.textContent).toBe("status");
		editor.handleKey(key({ key: "ArrowRight" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual(["git status"]);
	});

	it("asks the core for completions when Tab is pressed", () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		const requested: { line: string; cursor: number }[] = [];
		const original = core.requestCompletions.bind(core);
		core.requestCompletions = (line, cursor) => {
			requested.push({ line, cursor });
			original(line, cursor);
		};
		editor.setText("git st");
		editor.handleKey(key({ key: "Tab" }));
		expect(requested).toEqual([{ line: "git st", cursor: 6 }]);
	});

	it("cancels completions when typing while the dropdown is open", () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		const cancelled: number[] = [];
		const original = core.cancelCompletions.bind(core);
		core.cancelCompletions = () => {
			cancelled.push(1);
			original();
		};
		const internal = editor as unknown as {
			dropdown: { isOpen(): boolean; setResult(result: unknown): void; close(): void };
			dropdownOpen: boolean;
		};
		internal.dropdown.setResult({
			items: [{ value: "status", displayValue: "status", description: null, kind: "subcommand", matchedIndices: [] }],
			span: { start: 4, end: 4 },
			query: "stat",
		});
		internal.dropdownOpen = internal.dropdown.isOpen();
		editor.setText("git");
		editor.handleKey(key({ key: "s" }));
		expect(cancelled.length).toBeGreaterThanOrEqual(1);
	});

	it("re-asks only when the accepted completion descends into a directory", () => {
		const openWith = (value: string) => {
			const { editor, core } = mount();
			core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
			const requested: string[] = [];
			const original = core.requestCompletions.bind(core);
			core.requestCompletions = (line, cursor) => {
				requested.push(line);
				original(line, cursor);
			};
			const internal = editor as unknown as {
				dropdown: { isOpen(): boolean; setResult(result: unknown): void };
				dropdownOpen: boolean;
			};
			editor.setText("cd ");
			internal.dropdown.setResult({
				items: [
					{ value, displayValue: value, description: null, kind: "path", matchedIndices: [] },
				],
				span: { start: 3, end: 3 },
				query: "",
			});
			internal.dropdownOpen = internal.dropdown.isOpen();
			editor.handleKey(key({ key: "Tab" }));
			return requested;
		};

		expect(openWith("src/")).toEqual(["cd src/"]);
		expect(openWith("README.md")).toEqual([]);
	});

	it("accepts a Ctrl-R match without submitting it", () => {
		const { editor, container, core, host } = mount();
		core.feed(
			encode(
				"\x1b]133;A\x07\x1b]7000;v=1;cmd=git%20status\x07\x1b]133;C\x07ok\n\x1b]133;D;0\x07\x1b]7000;v=1;input-ready=1\x07",
			),
		);
		editor.handleKey(key({ key: "r", ctrlKey: true }));
		editor.handleKey(key({ key: "s" }));
		editor.handleKey(key({ key: "t" }));
		expect(container.querySelector(".terminal-editor-search")?.textContent).toContain("git status");
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual([]);
		editor.handleKey(key({ key: "Enter" }));
		expect(host.sent).toEqual(["git status"]);
	});

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
