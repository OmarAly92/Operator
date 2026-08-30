import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const bootstrap = fileURLToPath(new URL("./bash.sh", import.meta.url));

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
