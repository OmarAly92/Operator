import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";
import { haveTmux, parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";

const bootstrap = fileURLToPath(new URL("./zsh.sh", import.meta.url));
const haveZsh = (() => {
	try {
		execFileSync("zsh", ["--version"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
})();
const skip = haveZsh ? false : "zsh is not installed";
const ptySkip = haveZsh && haveTmux() ? false : "zsh and tmux are required";

if (ptySkip) {
	console.warn("Skipping fires input-ready from the real zle line-init hook: zsh and tmux are required");
}

function runZsh(script) {
	return execFileSync("zsh", ["-f", "-c", script], { encoding: "latin1" });
}

function runZshCapture(script) {
	return runZsh(script);
}

function runZshWithBootstrap(script) {
	return runZsh(`source ${bootstrap}; ${script}`);
}

test("emits prompt-start, command-end and one extension mark", { skip }, () => {
	const out = runZsh(
		`source ${bootstrap}; __operator_terminal_preexec 'echo hi'; __operator_terminal_precmd`,
	);
	assert.match(out, /\x1b\]133;A\x07/, "expected a prompt-start mark");
	assert.match(out, /\x1b\]133;D;/, "expected a command-end mark");
	assert.match(out, /\x1b\]7000;v=1;/, "expected one extension mark");
});

test("preserves the user's own precmd functions", { skip }, () => {
	const out = runZsh(
		"autoload -Uz add-zsh-hook; user_hook() { print -n USERHOOK }; " +
			`add-zsh-hook precmd user_hook; source ${bootstrap}; ` +
			"for f in $precmd_functions; do $f; done",
	);
	assert.match(out, /USERHOOK/, "the user's precmd hook must still run");
});

test("does not rebind any key", { skip }, () => {
	const before = runZsh("bindkey | sort");
	const after = runZsh(`source ${bootstrap}; bindkey | sort`);
	assert.equal(before, after, "bootstrap must not touch the keymap");
});

test("is idempotent under a second source", { skip }, () => {
	const out = runZsh(`source ${bootstrap}; source ${bootstrap}; __operator_terminal_precmd`);
	const marks = out.match(/\x1b\]133;A\x07/g) ?? [];
	assert.equal(marks.length, 1, "sourcing twice must not double-register the hook");
});

test("leaves the user's prompt alone", { skip }, () => {
	const out = runZsh(`source ${bootstrap}; print -P -- '%n@%m'`);
	const expected = execFileSync("zsh", ["-f", "-c", "print -P -- '%n@%m'"], {
		encoding: "latin1",
	});
	assert.equal(out, expected, "bootstrap must not change the rendered prompt");
});

test("suppresses the prompt only when requested", { skip }, () => {
	const on = runZsh(
		`PROMPT=SHELLPROMPT; RPROMPT=RIGHTPROMPT; OPERATOR_TERMINAL_SUPPRESS_PROMPT=1; source ${bootstrap}; __operator_terminal_precmd; print -r -- "prompt=[$PROMPT] right=[$RPROMPT]"`,
	);
	assert.match(on, /prompt=\[\] right=\[\]/);
	const off = runZsh(
		`PROMPT=SHELLPROMPT; RPROMPT=RIGHTPROMPT; OPERATOR_TERMINAL_SUPPRESS_PROMPT=0; source ${bootstrap}; __operator_terminal_precmd; print -r -- "prompt=[$PROMPT] right=[$RPROMPT]"`,
	);
	assert.match(off, /prompt=\[SHELLPROMPT\] right=\[RIGHTPROMPT\]/);
});

test("fires input-ready from the real zle line-init hook", { skip: ptySkip }, () => {
	const out = runInPty("zsh -f -i", [`source ${bootstrap}`, "echo hi"]);
	const count = (value) => (out.match(new RegExp(value, "g")) ?? []).length;
	assert.ok(count("input-ready=1") >= 1, "zle line-init never fired");
	assert.ok(count("input-released=1") >= 1, "preexec never fired");
	assert.ok(
		out.indexOf("input-ready=1") < out.indexOf("input-released=1"),
		"ready must precede released for the first command",
	);
});

test("does not add or remove any bindkey binding", { skip }, () => {
	const before = runZshCapture("bindkey -L | sort");
	const after = runZshWithBootstrap("bindkey -L | sort");
	assert.equal(after, before);
});

test("leaves the user's own zle-line-init widget installed and callable", { skip }, () => {
	const out = runZsh(
		`user_widget() { print -n user-widget-ran }; zle -N zle-line-init user_widget; source ${bootstrap}; zle -lL; user_widget`,
	);
	assert.match(out, /user-widget-ran/);
	assert.match(out, /zle -N zle-line-init/);
});

function field(payload, name) {
	return payload.match(new RegExp(`(?:^|;)${name}=([^;]*)`))?.[1];
}

function lifecycleRecords() {
	const raw = runInPty(
		"zsh -f -i",
		[
			`source ${bootstrap}`,
			"true",
			"false",
			"printf x | grep x",
			"for value in one two; do",
			"print $value",
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

test("preserves ordered raw OSC records when every byte is a PTY boundary", () => {
	const raw = "\x1b]133;A\x07\x1b]7000;v=1;id=terminal-1-1\x1b\\\x1b]133;C\x07";
	assert.deepEqual(parseOscRecords(raw, splitEveryByte(raw)), [
		{ raw: "\x1b]133;A\x07", payload: "133;A", terminator: "BEL" },
		{
			raw: "\x1b]7000;v=1;id=terminal-1-1\x1b\\",
			payload: "7000;v=1;id=terminal-1-1",
			terminator: "ST",
		},
		{ raw: "\x1b]133;C\x07", payload: "133;C", terminator: "BEL" },
	]);
});

test("emits the real zsh lifecycle for successful, failed, multiline, interrupted, and directory commands", { skip: ptySkip }, () => {
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
			cmd: "for%20value%20in%20one%20two%3b%20do%0aprint%20$value%0adone",
		},
		{ id: "terminal-1-5", cmd: "sleep%205" },
		{ id: "terminal-1-6", cmd: "cd%20/tmp" },
		{ id: "terminal-1-7", cmd: "true" },
		{ id: "terminal-1-8", cmd: "false" },
	]);
	const exits = records
		.filter((record) => field(record.payload, "exit") !== undefined)
		.map((record) => ({ id: field(record.payload, "id"), exit: field(record.payload, "exit") }));
	assert.deepEqual(exits, [
		{ id: "terminal-1-1", exit: "0" },
		{ id: "terminal-1-2", exit: "1" },
		{ id: "terminal-1-3", exit: "0" },
		{ id: "terminal-1-4", exit: "0" },
		{ id: "terminal-1-5", exit: "130" },
		{ id: "terminal-1-6", exit: "0" },
		{ id: "terminal-1-7", exit: "0" },
		{ id: "terminal-1-8", exit: "1" },
	]);
	for (const { id } of commands) {
		const commandIndex = records.findIndex(
			(record) => field(record.payload, "id") === id && field(record.payload, "cmd") !== undefined,
		);
		const nextCommandIndex = records.findIndex(
			(record, index) => index > commandIndex && field(record.payload, "cmd") !== undefined,
		);
		const lifecycleEnd = nextCommandIndex < 0 ? records.length : nextCommandIndex;
		const releasedIndex = records.findIndex(
			(record, index) => index > commandIndex && index < lifecycleEnd && record.payload === "7000;v=1;input-released=1",
		);
		const outputIndex = records.findIndex(
			(record, index) => index > releasedIndex && index < lifecycleEnd && record.payload === "133;C",
		);
		const exitIndex = records.findIndex(
			(record, index) => index > outputIndex && index < lifecycleEnd && field(record.payload, "id") === id && field(record.payload, "exit") !== undefined,
		);
		const endIndex = records.findIndex(
			(record, index) => index > exitIndex && index < lifecycleEnd && record.payload === `133;D;${field(records[exitIndex].payload, "exit")}`,
		);
		assert.ok(commandIndex < releasedIndex && releasedIndex < outputIndex && outputIndex < exitIndex && exitIndex < endIndex);
	}
});
