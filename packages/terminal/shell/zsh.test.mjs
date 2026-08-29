import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";
import { haveTmux, runInPty } from "./pty.mjs";

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
