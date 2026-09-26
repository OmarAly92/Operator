import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { beforeAll, describe, expect, it } from "vitest";
import { createSettledReplayFilter } from "./settled-replay-filter";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const SETTLED_BEGIN = "\x1b]7000;v=1;settled=begin\x1b\\";
const SETTLED_END = "\x1b]7000;v=1;settled=end\x1b\\";
const ORIGIN = "\x1b]7000;v=1;origin=0\x1b\\";
const READY = "\x1b]7000;v=1;ready=1\x1b\\";

function zshBlock(id: string, command: string, output: string): string {
	return (
		`\x1b]7000;v=1;id=${id};cwd=%2Ftmp;branch=\x1b\\` +
		`\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m${" ".repeat(79)}\r \r` +
		`\x1b]133;A\x07tmp % \x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07${command}\r\n` +
		`\x1b]7000;v=1;id=${id};cmd=${command}\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07` +
		`${output}\x1b]7000;v=1;id=${id};exit=0\x1b\\\x1b]133;D;0\x07`
	);
}

const durableBlocks = [
	zshBlock("t-1", "cat", "one two\r\none two\r\n"),
	zshBlock("t-2", "printf 'P8-A\\n'", "P8-A\r\n"),
	zshBlock("t-3", "printf 'P8-END\\n'", "P8-END\r\n"),
];

const hostReplay =
	ORIGIN +
	SETTLED_BEGIN +
	"\x1b[0mtmp % cat\x1b[0m\r\n\x1b[0mone two\x1b[0m\r\n\x1b[0mone two\x1b[0m\r\n" +
	"\x1b[0mtmp % printf 'P8-A\\n'\x1b[0m\r\n\x1b[0mP8-A\x1b[0m\r\n" +
	"\x1b[0mtmp % printf 'P8-END\\n'\x1b[0m\r\n\x1b[0mP8-END\x1b[0m\r\n" +
	SETTLED_END +
	"\x1b[0mtmp %\x1b[0m\r\x1b[6C" +
	READY;

const liveTail = ORIGIN + "\x1b[0mtmp %\x1b[0m\r\x1b[6C" + READY;

function pushAll(chunks: string[]): string {
	const filter = createSettledReplayFilter();
	return chunks.map((chunk) => decoder.decode(filter.push(encoder.encode(chunk)))).join("");
}

function rowTexts(core: TerminalCore): string[] {
	const snapshot = core.snapshot();
	const rows: string[] = [];
	for (let index = 0; index < snapshot.rows.length / 2; index += 1) {
		rows.push(decoder.decode(snapshot.content.subarray(snapshot.rows[index * 2]!, snapshot.rows[index * 2 + 1]!)));
	}
	while (rows.length > 0 && rows.at(-1) === "") rows.pop();
	return rows;
}

beforeAll(async () => {
	const bytes = await readFile(resolve(process.cwd(), "../packages/terminal/ts/core/wasm/vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

describe("createSettledReplayFilter", () => {
	it("drops a replay's settled rows and keeps the frame around them", () => {
		expect(pushAll([hostReplay])).toBe(liveTail);
	});

	it("drops the same rows wherever the transport splits the frame", () => {
		for (let first = 1; first < hostReplay.length; first += 1) {
			for (const second of [first + 1, first + 7, hostReplay.length]) {
				const chunks = [hostReplay.slice(0, first), hostReplay.slice(first, second), hostReplay.slice(second)];
				expect(pushAll(chunks)).toBe(liveTail);
			}
		}
	});

	it("passes output without a settled pair through unchanged", () => {
		const live = "ls\r\n\x1b[31mred\x1b[0m\r\n\x1b]133;D;0\x07";
		expect(pushAll([live])).toBe(live);
		expect(pushAll([ORIGIN + "\x1b[0mhi\x1b[0m" + READY])).toBe(ORIGIN + "\x1b[0mhi\x1b[0m" + READY);
	});

	it("holds back only a partial mark, and releases it once the next bytes rule the mark out", () => {
		const filter = createSettledReplayFilter();
		expect(decoder.decode(filter.push(encoder.encode("abc\x1b]7000;v=1;set")))).toBe("abc");
		expect(decoder.decode(filter.push(encoder.encode("x=1\x07def")))).toBe("\x1b]7000;v=1;setx=1\x07def");
	});

	it("stops dropping at the next frame when a frame ended before its settled rows did", () => {
		const cut = ORIGIN + SETTLED_BEGIN + "\x1b[0mold rows\x1b[0m\r\n";
		const next = ORIGIN + "\x1b[0mtmp %\x1b[0m" + READY + "live";
		expect(pushAll([cut, next])).toBe(ORIGIN + next);
	});

	it("shows each finished command once when durable blocks precede the host's replay", () => {
		const core = createTerminalCore({ columns: 80, rows: 24, limits: { rows: 1000, bytes: 1 << 24 } });
		for (const block of durableBlocks) core.feed(encoder.encode(block));
		const filter = createSettledReplayFilter();
		for (let at = 0; at < hostReplay.length; at += 64) {
			core.feed(filter.push(encoder.encode(hostReplay.slice(at, at + 64))));
		}

		expect(rowTexts(core)).toEqual([
			"tmp % cat",
			"one two",
			"one two",
			"tmp % printf 'P8-A\\n'",
			"P8-A",
			"tmp % printf 'P8-END\\n'",
			"P8-END",
			"tmp %",
		]);
		core.dispose();
	});
});
