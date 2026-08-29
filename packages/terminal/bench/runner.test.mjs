import test from "node:test";
import assert from "node:assert/strict";
import { parseArguments } from "./runner.mjs";

test("accepts the dom renderer", () => {
	const parsed = parseArguments(["--renderer", "dom", "--scenario", "vtebench"]);
	assert.equal(parsed.renderer, "dom");
	assert.deepEqual(parsed.names, ["vtebench"]);
});

test("accepts the xterm renderer", () => {
	const parsed = parseArguments(["--renderer", "xterm", "--scenario", "large-output"]);
	assert.equal(parsed.renderer, "xterm");
});

test("rejects an unknown renderer", () => {
	assert.throws(() => parseArguments(["--renderer", "webgl", "--scenario", "vtebench"]));
});

test("record measures every scenario and refuses a single scenario", () => {
	const parsed = parseArguments(["--renderer", "dom", "--record"]);
	assert.equal(parsed.record, true);
	assert.ok(parsed.names.length >= 3);
	assert.throws(() => parseArguments(["--renderer", "dom", "--record", "--scenario", "vtebench"]));
});
