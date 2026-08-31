import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";

const bootstrap = fileURLToPath(new URL("./fish.fish", import.meta.url));
const haveFish = (() => {
	try {
		execFileSync("fish", ["--version"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
})();
const fishCheck = haveFish
	? execFileSync("fish", ["--version"], { encoding: "utf8" }).trim()
	: "fish not found";
const fishSkip = haveFish ? false : `fish is not installed (${fishCheck})`;

console.log(`fish executable check: ${fishCheck}`);

function runFish(commands) {
	return runInPty("fish --no-config --interactive", [
		`source ${JSON.stringify(bootstrap)}`,
		...commands,
	]);
}

function runFishScript(script) {
	return execFileSync("fish", ["--no-config", "-c", script], { encoding: "latin1" });
}

test("produces two command records with fish OSC 133 enabled", { skip: fishSkip }, () => {
	const out = runFish(["echo one", "echo two"]);
	assert.ok((out.match(/\x1b\]133;A/g) ?? []).length >= 2);
	assert.match(out, /cmd=echo%20one/);
	assert.match(out, /cmd=echo%20two/);
});

test("emits line-editor ownership marks from real fish events", { skip: fishSkip }, () => {
	const out = runFish(["echo hi"]);
	assert.match(out, /input-ready=1/);
	assert.match(out, /input-released=1/);
});

test("suppresses the prompt only when requested", { skip: fishSkip }, () => {
	const on = runFishScript(
		`function fish_prompt; printf SHELLPROMPT; end; set -gx OPERATOR_TERMINAL_SUPPRESS_PROMPT 1; source ${JSON.stringify(bootstrap)}; __operator_terminal_prompt >/dev/null; fish_prompt`,
	);
	assert.equal(on, "");
	const off = runFishScript(
		`function fish_prompt; printf SHELLPROMPT; end; set -gx OPERATOR_TERMINAL_SUPPRESS_PROMPT 0; source ${JSON.stringify(bootstrap)}; __operator_terminal_prompt >/dev/null; fish_prompt`,
	);
	assert.equal(off, "SHELLPROMPT");
});

function field(payload, name) {
	return payload.match(new RegExp(`(?:^|;)${name}=([^;]*)`))?.[1];
}

test("emits fish lifecycle records for success, failure, syntax errors, and an empty prompt", { skip: fishSkip }, () => {
	const raw = runInPty(
		"fish --no-config --interactive",
		[
			`source ${JSON.stringify(bootstrap)}`,
			"true",
			"false",
			"echo )",
			{ keys: "" },
		],
		{ settleMs: 120, env: { OPERATOR_TERMINAL_ID: "terminal-1" } },
	);
	const records = parseOscRecords(raw);
	assert.deepEqual(parseOscRecords(raw, splitEveryByte(raw)), records);
	const commands = records
		.filter((record) => field(record.payload, "cmd") !== undefined)
		.map((record) => ({ id: field(record.payload, "id"), cmd: field(record.payload, "cmd") }));
	assert.deepEqual(commands, [
		{ id: "terminal-1-1", cmd: "true" },
		{ id: "terminal-1-2", cmd: "false" },
		{ id: "terminal-1-3", cmd: "echo%20%29" },
	]);
	const ends = records.filter((record) => record.payload.startsWith("133;D;")).map((record) => record.payload);
	assert.deepEqual(ends, ["133;D;0", "133;D;1", "133;D;2"]);
	const exitRecords = records.filter((record) => field(record.payload, "exit") !== undefined);
	assert.ok(exitRecords.length >= 2, "expected an OSC 7000 exit= for each executed command");
	for (const exitRecord of exitRecords) {
		const exitIndex = records.indexOf(exitRecord);
		const code = field(exitRecord.payload, "exit");
		const endIndex = records.findIndex(
			(record, index) => index > exitIndex && record.payload === `133;D;${code}`,
		);
		assert.ok(endIndex > exitIndex, `OSC 7000 exit=${code} must precede its OSC 133 D`);
	}
	const emptyPrompt = records.slice(-3).map((record) => record.payload);
	assert.deepEqual(emptyPrompt, ["133;A", "133;B", "7000;v=1;input-ready=1"]);
});
