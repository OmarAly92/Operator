import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { haveTmux, runInPty } from "./pty.mjs";

const bootstrap = fileURLToPath(new URL("./fish.fish", import.meta.url));
const haveFish = (() => {
	try {
		execFileSync("fish", ["--version"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
})();
const ptySkip = haveFish && haveTmux() ? false : "fish and tmux are required";

if (ptySkip) {
	console.warn(
		"Skipping fish prompt and ownership integration tests: fish and tmux are required",
	);
}

function runFish(commands) {
	return runInPty("fish --no-config --interactive", [
		`source ${JSON.stringify(bootstrap)}`,
		...commands,
	]);
}

test("produces two command records with fish OSC 133 enabled", { skip: ptySkip }, () => {
	const out = runFish(["echo one", "echo two"]);
	assert.ok((out.match(/\x1b\]133;A/g) ?? []).length >= 2);
	assert.match(out, /cmd=echo%20one/);
	assert.match(out, /cmd=echo%20two/);
});

test("emits line-editor ownership marks from real fish events", { skip: ptySkip }, () => {
	const out = runFish(["echo hi"]);
	assert.match(out, /input-ready=1/);
	assert.match(out, /input-released=1/);
});
