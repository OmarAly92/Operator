import test from "node:test";
import assert from "node:assert/strict";
import { parseArguments, medianRun } from "./runner.mjs";

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

test("medianRun picks each scenario's median p95 independently", () => {
	const run = (a, b) => ({
		measured: { scenarios: { "input-latency": { p95: a }, vtebench: { p95: b } } },
	});
	const runs = [run(9, 1), run(7, 3), run(11, 2)];
	const chosen = medianRun(runs, ["input-latency", "vtebench"]);
	assert.equal(chosen.measured.scenarios["input-latency"].p95, 9);
	assert.equal(chosen.measured.scenarios.vtebench.p95, 2);
});

test("medianRun returns the single run untouched", () => {
	const only = { measured: { scenarios: { vtebench: { p95: 4 } } } };
	assert.equal(medianRun([only], ["vtebench"]), only);
});
