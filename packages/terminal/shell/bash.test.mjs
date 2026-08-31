import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { haveTmux, parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";

const bootstrap = fileURLToPath(new URL("./bash.sh", import.meta.url));
const ptySkip = haveTmux() ? false : "tmux is required";

function runBash(script) {
	return execFileSync("bash", ["--noprofile", "--norc", "-c", script], {
		encoding: "latin1",
	});
}

test("emits command and line-editor ownership marks", () => {
	const out = runBash(`source ${JSON.stringify(bootstrap)}; printf command-ran; __operator_terminal_precmd`);
	assert.match(out, /cmd=/);
	assert.match(out, /input-released=1/);
	assert.match(out, /input-ready=1/);
});

test("preserves a pre-existing DEBUG trap", () => {
	const out = runBash(
		`trap 'printf user-debug-ran' DEBUG; source ${JSON.stringify(bootstrap)}; :`,
	);
	assert.match(out, /user-debug-ran/);
	assert.match(out, /input-released=1/);
});

test("preserves a pre-existing PROMPT_COMMAND", () => {
	const out = runBash(
		`PROMPT_COMMAND='printf user-prompt-ran'; source ${JSON.stringify(bootstrap)}; eval "$PROMPT_COMMAND"`,
	);
	assert.match(out, /user-prompt-ran/);
	assert.match(out, /input-ready=1/);
});

test("is idempotent under a second source", () => {
	const out = runBash(
		`source ${JSON.stringify(bootstrap)}; source ${JSON.stringify(bootstrap)}; __operator_terminal_precmd`,
	);
	assert.equal((out.match(/input-ready=1/g) ?? []).length, 1);
});

test("suppresses the prompt only when requested", () => {
	const on = runBash(
		`PS1=SHELLPROMPT; OPERATOR_TERMINAL_SUPPRESS_PROMPT=1; source ${JSON.stringify(bootstrap)}; __operator_terminal_precmd >/dev/null; printf 'prompt=[%s]' "$PS1"`,
	);
	assert.match(on, /prompt=\[\]/);
	const off = runBash(
		`PS1=SHELLPROMPT; OPERATOR_TERMINAL_SUPPRESS_PROMPT=0; source ${JSON.stringify(bootstrap)}; __operator_terminal_precmd >/dev/null; printf 'prompt=[%s]' "$PS1"`,
	);
	assert.match(off, /prompt=\[SHELLPROMPT\]/);
});

function field(payload, name) {
	return payload.match(new RegExp(`(?:^|;)${name}=([^;]*)`))?.[1];
}

function lifecycleRecords() {
	const raw = runInPty(
		"bash --noprofile --norc -i",
		[
			`source ${bootstrap}`,
			"true",
			"false",
			"printf x | grep x",
			"for value in one two; do",
			"printf '%s\\n' $value",
			"done",
			{ keys: "sleep 5" },
			{ keys: "C-c", enter: false, waitMs: 300 },
			"cd /tmp",
			"true",
			"false",
		],
		{ settleMs: 120, env: { OPERATOR_TERMINAL_ID: "terminal-1" } },
	);
	return { raw, records: parseOscRecords(raw) };
}

test("emits one ordered bash lifecycle without DEBUG hook commands", { skip: ptySkip }, () => {
	const { raw, records } = lifecycleRecords();
	assert.deepEqual(parseOscRecords(raw, splitEveryByte(raw)), records);
	const commands = records
		.filter((record) => field(record.payload, "cmd") !== undefined)
		.map((record) => ({ id: field(record.payload, "id"), cmd: field(record.payload, "cmd") }));
	assert.deepEqual(commands, [
		{ id: "terminal-1-1", cmd: "true" },
		{ id: "terminal-1-2", cmd: "false" },
		{ id: "terminal-1-3", cmd: "printf%20x%20%7c%20grep%20x" },
		{
			id: "terminal-1-4",
			cmd: "for%20value%20in%20one%20two%3b%20do%0aprintf%20%27%25s%5cn%27%20$value%0adone",
		},
		{ id: "terminal-1-5", cmd: "sleep%205" },
		{ id: "terminal-1-6", cmd: "cd%20/tmp" },
		{ id: "terminal-1-7", cmd: "true" },
		{ id: "terminal-1-8", cmd: "false" },
	]);
	assert.ok(records.every((record) => !record.payload.includes("__operator_terminal_")));
	for (const { id } of commands) {
		const commandIndex = records.findIndex(
			(record) => field(record.payload, "id") === id && field(record.payload, "cmd") !== undefined,
		);
		const releasedIndex = records.findIndex(
			(record, index) => index > commandIndex && record.payload === "7000;v=1;input-released=1",
		);
		const outputIndex = records.findIndex(
			(record, index) => index > releasedIndex && record.payload === "133;C",
		);
		const exitIndex = records.findIndex(
			(record, index) => index > outputIndex && field(record.payload, "id") === id && field(record.payload, "exit") !== undefined,
		);
		const endIndex = records.findIndex(
			(record, index) => index > exitIndex && record.payload === `133;D;${field(records[exitIndex].payload, "exit")}`,
		);
		assert.ok(commandIndex < releasedIndex && releasedIndex < outputIndex && outputIndex < exitIndex && exitIndex < endIndex);
	}
});
