import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, initTerminalCore, ProgramMessages, type HostCapabilities, type ProgramMessageEvent } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encode = (text: string) => new TextEncoder().encode(text);

function hostWith(notify?: HostCapabilities["notify"]): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		...(notify ? { notify } : {}),
	};
}

describe("ProgramMessages", () => {
	it("delivers every message to every listener even when one throws, then reports the failure", () => {
		let notifications = ["Build", "done"];
		const source = {
			program_generation: () => 1,
			title: () => "◐ Working",
			pointer_shape: () => "",
			take_notifications: () => {
				const taken = notifications;
				notifications = [];
				return taken;
			},
		};
		const program = new ProgramMessages(source, hostWith());
		const seen: ProgramMessageEvent[] = [];
		program.onMessage(() => {
			throw new Error("boom");
		});
		program.onMessage((event) => seen.push(event));
		expect(() => program.poll()).toThrow(AggregateError);
		expect(seen).toEqual([
			{ kind: "title", title: "◐ Working" },
			{ kind: "notification", notification: { title: "Build", body: "done" } },
		]);
		expect(program.title()).toBe("◐ Working");
	});

	it("reads nothing while the generation is unchanged", () => {
		const source = {
			program_generation: vi.fn(() => 0),
			title: vi.fn(() => ""),
			pointer_shape: vi.fn(() => ""),
			take_notifications: vi.fn(() => [] as string[]),
		};
		const program = new ProgramMessages(source, hostWith());
		program.poll();
		expect(source.title).not.toHaveBeenCalled();
		expect(source.take_notifications).not.toHaveBeenCalled();
	});

	it("emits a title, a pointer shape and each notification once", () => {
		let generation = 0;
		let notifications: string[] = [];
		const source = {
			program_generation: () => generation,
			title: () => "◐ Working",
			pointer_shape: () => "pointer",
			take_notifications: () => {
				const taken = notifications;
				notifications = [];
				return taken;
			},
		};
		const notify = vi.fn();
		const program = new ProgramMessages(source, hostWith(notify));
		const events: ProgramMessageEvent[] = [];
		program.onMessage((event) => events.push(event));
		generation = 1;
		notifications = ["Build", "done", "", "second"];
		program.poll();
		program.poll();
		expect(events).toEqual([
			{ kind: "title", title: "◐ Working" },
			{ kind: "pointer", shape: "pointer" },
			{ kind: "notification", notification: { title: "Build", body: "done" } },
			{ kind: "notification", notification: { title: "", body: "second" } },
		]);
		expect(notify.mock.calls).toEqual([
			["Build", "done"],
			["", "second"],
		]);
		expect(program.title()).toBe("◐ Working");
		expect(program.pointerShape()).toBe("pointer");
	});

	it("stops calling a listener once it unsubscribes or the messages are disposed", () => {
		let generation = 0;
		let title = "";
		const source = {
			program_generation: () => generation,
			title: () => title,
			pointer_shape: () => "",
			take_notifications: () => [] as string[],
		};
		const program = new ProgramMessages(source, hostWith());
		const kept = vi.fn();
		const dropped = vi.fn();
		program.onMessage(kept);
		const off = program.onMessage(dropped);
		off();
		generation = 1;
		title = "one";
		program.poll();
		expect(dropped).not.toHaveBeenCalled();
		expect(kept).toHaveBeenCalledTimes(1);
		program.dispose();
		generation = 2;
		title = "two";
		program.poll();
		expect(kept).toHaveBeenCalledTimes(1);
	});
});

describe("TerminalCore program messages", () => {
	it("follows OSC 0/2 titles and OSC 22 pointer shapes", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const events: ProgramMessageEvent[] = [];
		const off = core.onProgramMessage((event) => events.push(event));
		core.feed(encode("\x1b]0;✳ Claude Code\x07\x1b]22;xterm\x07"));
		expect(core.title()).toBe("✳ Claude Code");
		expect(core.pointerShape()).toBe("text");
		expect(events).toEqual([
			{ kind: "title", title: "✳ Claude Code" },
			{ kind: "pointer", shape: "text" },
		]);
		off();
		core.dispose();
	});

	it("hands OSC 9, 777 and 99 notifications to the host notify seam", () => {
		const notify = vi.fn();
		const core = createTerminalCore({ columns: 40, scrollback: 100, host: hostWith(notify) });
		core.feed(encode("\x1b]9;hello\x07\x1b]777;notify;Build;done\x07\x1b]99;;Kitty\x1b\\"));
		expect(notify.mock.calls).toEqual([
			["", "hello"],
			["Build", "done"],
			["Kitty", ""],
		]);
		core.dispose();
	});

	it("sees a title that arrives inside a sync block when a tick flushes it", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const titles: string[] = [];
		core.onProgramMessage((event) => {
			if (event.kind === "title") titles.push(event.title);
		});
		core.feed(encode("\x1b[?2026h\x1b]2;framed\x07"));
		expect(titles).toEqual([]);
		core.tick(Date.now() + 1_000);
		expect(titles).toEqual(["framed"]);
		core.dispose();
	});

	it("never answers a size or colour query from the renderer core", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		core.feed(encode("\x1b[18t\x1b]10;?\x07"));
		expect(core.title()).toBe("");
		core.dispose();
	});
});
