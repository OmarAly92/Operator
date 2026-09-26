import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";
import { haveTmux, parseOscRecords, runInPty, runInPtySegments, splitEveryByte } from "./pty.mjs";

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

const TYPEAHEAD_PREFIX = "7000;v=1;typeahead=";

function typeaheadReports(records) {
	return records
		.filter((record) => record.payload.startsWith(TYPEAHEAD_PREFIX))
		.map((record) => record.payload.slice(TYPEAHEAD_PREFIX.length));
}

function commandsRun(records) {
	return records.map((record) => field(record.payload, "cmd")).filter((command) => command !== undefined);
}

function typeaheadSession(steps) {
	const raw = runInPty("zsh -f -i", [`source ${bootstrap}`, ...steps], {
		settleMs: 300,
		env: { OPERATOR_TERMINAL_ID: "terminal-1", LANG: "C.UTF-8", LC_ALL: "C.UTF-8" },
	});
	return { raw, records: parseOscRecords(raw) };
}

test("reports text typed during a command once the prompt returns, and a Ctrl-U clears the shell's copy", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo hi", enter: false, waitMs: 1800 },
		{ keys: "C-u", enter: false, waitMs: 200 },
		{ keys: "echo second", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20hi"]);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20second"]);
	const report = records.findIndex((record) => record.payload.startsWith(TYPEAHEAD_PREFIX));
	const finished = records.findIndex((record) => record.payload === "133;D;0");
	assert.ok(finished >= 0 && finished < report, "the report comes after the command finished");
	assert.equal(records[report - 1].payload, "7000;v=1;input-ready=1", "the report directly follows input-ready");
});

test("keeps the reported text in the shell when nothing clears it, so a separate Enter still runs it", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo sent", enter: false, waitMs: 1800 },
		{ keys: "", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20sent"]);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20sent"]);
});

test("reports typed-ahead UTF-8 as percent-encoded bytes", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo café €", enter: false, waitMs: 1800 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20caf%c3%a9%20%e2%82%ac"]);
});

test("runs a line typed ahead with Enter exactly as before and reports nothing", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo queued", waitMs: 1800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20queued"]);
});

test("runs every command of a multi-line submission and reports nothing", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([{ keys: "sleep 1\necho two\necho three", waitMs: 2000 }]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20two", "echo%20three"]);
});

test("does not report text longer than the cap and leaves it to the shell", { skip: ptySkip }, () => {
	const long = `echo ${"x".repeat(300)}`;
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: long, enter: false, waitMs: 1800 },
		{ keys: "", waitMs: 600 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", `echo%20${"x".repeat(300)}`]);
});

test("never surfaces a password a program read with echo off", { skip: ptySkip }, () => {
	const { raw, records } = typeaheadSession([
		{ keys: "read -s -k 7 pw; echo got-${#pw}", waitMs: 300 },
		{ keys: "hunter2", enter: false, waitMs: 800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.equal(raw.includes("hunter2"), false, "the password must appear nowhere in the pane");
	assert.match(raw, /got-7/);
});

test("a program's own prompt still receives the keys typed at it", { skip: ptySkip }, () => {
	const { raw, records } = typeaheadSession([
		{ keys: "read 'name?name: '; echo got-$name", waitMs: 300 },
		{ keys: "bob", waitMs: 800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.match(raw, /got-bob/);
});

test("clears the reported text with Ctrl-U in vi insert mode too", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		"bindkey -v",
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo hi", enter: false, waitMs: 1800 },
		{ keys: "C-u", enter: false, waitMs: 200 },
		{ keys: "echo second", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20hi"]);
	assert.deepEqual(commandsRun(records), ["bindkey%20-v", "sleep%201", "echo%20second"]);
});

test("percent-encodes non-ASCII bytes as UTF-8", { skip }, () => {
	const out = execFileSync("zsh", ["-f", "-c", `source ${bootstrap}; __operator_terminal_pct_encode 'café € ?[x]'`], {
		encoding: "utf8",
		env: { ...process.env, LANG: "C.UTF-8", LC_ALL: "C.UTF-8" },
	});
	assert.equal(out, "caf%c3%a9%20%e2%82%ac%20%3f%5bx%5d");
});

test("after a width change redraws the prompt from its first row, counted at the old width", { skip: ptySkip }, () => {
	const [, afterResize] = runInPtySegments(
		"zsh -f -i",
		[`source ${bootstrap}`, "PROMPT=$'first-line\\nsecond $ '", { keys: "clear", waitMs: 800 }, { resize: [60, 40] }],
		{ settleMs: 800 },
	);
	const ups = afterResize.match(/\x1bM|\x1b\[1?A/g) ?? [];
	assert.equal(ups.length, 1, JSON.stringify(afterResize));
	assert.ok(afterResize.indexOf("\x1b[J") < afterResize.indexOf("first-line"), JSON.stringify(afterResize));
	assert.match(afterResize, /second \$ /);
});
