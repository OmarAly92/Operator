import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import { DEFAULT_QUICK_FIX_RULES } from "./quick-fix-rules";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const PUSH_OUTPUT = [
	"fatal: The current branch feat has no upstream branch.",
	"To push the current branch and set the remote as upstream, use",
	"",
	"    git push --set-upstream origin feat",
	"",
].join("\r\n");
const run = (cmd: string, output: string, exit: number) =>
	`\x1b]133;A\x07\x1b]7000;v=1;cmd=${encodeURIComponent(cmd)}\x07\x1b]133;C\x07${output}\r\n\x1b]133;D;${exit}\x07`;
const FIX = "git push --set-upstream origin feat";

beforeAll(async () => {
	const bytes = await readFile(join(process.cwd(), "../core/wasm/vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function mount(rules = DEFAULT_QUICK_FIX_RULES) {
	const sent: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: () => {} };
	const core = createTerminalCore({ columns: 80, scrollback: 200 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	document.body.append(container);
	editor.mount(container, core, host);
	editor.setQuickFixRules(rules);
	return { editor, core, sent, container };
}

const row = (container: HTMLElement) => container.querySelector<HTMLElement>(".terminal-editor-quick-fix");
const useButton = (container: HTMLElement) => container.querySelector<HTMLButtonElement>(".terminal-editor-quick-fix-use");

describe("LineEditor quick fixes", () => {
	it("shows the fix for a failed push above the prompt and fills the box on click without sending", () => {
		const { core, container, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 128) + READY));
		expect(row(container)?.dataset.quickFix).toBe("git-push-set-upstream");
		expect(row(container)?.textContent).toContain(FIX);
		expect(container.querySelector(".terminal-editor-ghost")?.textContent).toBe(FIX);
		useButton(container)!.click();
		expect(sent).toEqual([]);
		expect(row(container)).toBeNull();
		expect(container.querySelector(".terminal-editor-content")?.textContent).toContain(FIX);
	});

	it("accepts the fix with ArrowRight in an empty box and runs it only on Enter", () => {
		const { editor, core, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		editor.handleKey(key({ key: "ArrowRight" }));
		expect(sent).toEqual([]);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual([FIX]);
	});

	it("hides the fix while the user types and never replaces what they typed", () => {
		const { editor, core, container, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		editor.handleKey(key({ key: "l" }));
		expect(row(container)).toBeNull();
		editor.handleKey(key({ key: "ArrowRight" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["l"]);
	});

	it("does not bring an applied fix back after the user edits it", () => {
		const { editor, core, container } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		useButton(container)!.click();
		editor.handleKey(key({ key: "Backspace", metaKey: true }));
		expect(row(container)).toBeNull();
		expect(container.querySelector(".terminal-editor-ghost")).toBeNull();
	});

	it("offers nothing for a successful command or with no rules", () => {
		const ok = mount();
		ok.core.feed(encode(run("git push", PUSH_OUTPUT, 0) + READY));
		expect(row(ok.container)).toBeNull();
		const none = mount([]);
		none.core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		expect(row(none.container)).toBeNull();
	});

	it("offers nothing for a failed block that was already there when the editor mounted", () => {
		const sent: string[] = [];
		const core = createTerminalCore({ columns: 80, scrollback: 200 });
		core.feed(encode(run("git push", PUSH_OUTPUT, 1)));
		const editor = new LineEditor();
		const container = document.createElement("div");
		editor.mount(container, core, { send: (text) => sent.push(text), sendRaw: () => {} });
		editor.setQuickFixRules(DEFAULT_QUICK_FIX_RULES);
		core.feed(encode(READY));
		expect(row(container)).toBeNull();
	});

	it("withdraws the fix once the next command starts", () => {
		const { core, container } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		expect(row(container)).not.toBeNull();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07"));
		core.feed(encode("a\r\n\x1b]133;D;0\x07" + READY));
		expect(row(container)).toBeNull();
	});
});
