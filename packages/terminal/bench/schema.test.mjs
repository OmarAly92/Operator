import assert from "node:assert/strict";
import test from "node:test";

import { summarizeSamples, validateBenchmark } from "./schema.mjs";

const samples = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

function benchmark() {
	return {
		schema: "operator.terminal-benchmark.v1",
		recordedAt: "2026-08-29T00:00:00.000Z",
		commit: "569c51bc0",
		platform: "darwin",
		architecture: "arm64",
		cpu: "Apple M4 Max",
		logicalCores: 16,
		physicalMemory: 68719476736,
		browserVersion: "Chromium 140.0.7339.16",
		displayScale: 2,
		renderer: "xterm",
		rendererVersion: "5.5.0",
		rendererKind: "webgl",
		scenarios: {
			vtebench: {
				configuration: {
					warmups: 3,
					samples: 10,
					unit: "workloads-per-second",
					columns: 120,
					rows: 40,
					scrollback: 5000,
					payloadBytes: 8388608,
					seed: 7000,
				},
				samples: [...samples],
				median: 5.5,
				p95: 10,
				unit: "workloads-per-second",
				workload: "vtebench-random-write-v1",
				seed: 7000,
				workloadDigest: "6c9e4053f0f94cabc58028b527c0fb5215cbe565ae35db382728942cc2893676",
			},
		},
	};
}

test("summarizes ten finite positive samples with nearest-rank p95", () => {
	assert.deepEqual(summarizeSamples(samples), { median: 5.5, p95: 10 });
	assert.throws(() => summarizeSamples([1, 2, Number.NaN]), /finite positive/);
	assert.throws(() => summarizeSamples([1, 2, 0]), /finite positive/);
});

test("accepts benchmark results with hardware and runtime metadata", () => {
	assert.doesNotThrow(() => validateBenchmark(benchmark()));
});

test("accepts a dom renderer result with a non-empty renderer version", () => {
	const result = benchmark();
	result.renderer = "dom";
	result.rendererVersion = "0.1.0";
	result.rendererKind = "dom";
	assert.doesNotThrow(() => validateBenchmark(result));
});

test("rejects a dom result claiming an xterm backend", () => {
	const result = benchmark();
	result.renderer = "dom";
	result.rendererVersion = "0.1.0";
	result.rendererKind = "canvas";
	assert.throws(() => validateBenchmark(result), /rendererKind for dom/);
});

test("rejects an xterm result claiming the dom kind", () => {
	const result = benchmark();
	result.rendererKind = "dom";
	assert.throws(() => validateBenchmark(result), /rendererKind for xterm/);
});

test("requires exactly ten measured samples", () => {
	const result = benchmark();
	result.scenarios.vtebench.samples.pop();
	assert.throws(() => validateBenchmark(result), /10 measured samples/);
});

test("requires hardware and runtime metadata", () => {
	for (const field of [
		"cpu",
		"logicalCores",
		"physicalMemory",
		"browserVersion",
		"displayScale",
	]) {
		const result = benchmark();
		delete result[field];
		assert.throws(() => validateBenchmark(result), new RegExp(field));
	}
});

test("rejects absolute paths, process identifiers, and environment metadata", () => {
	for (const [field, value] of [
		["cwd", "/Users/example/repository"],
		["pid", 1234],
		["environment", { CI: "true" }],
		["artifactPath", "/tmp/result.json"],
	]) {
		const result = benchmark();
		result[field] = value;
		assert.throws(() => validateBenchmark(result), /sensitive metadata/);
	}
});

test("rejects unexpected per-scenario result fields", () => {
	const result = benchmark();
	result.scenarios.vtebench.notes = "private benchmark note";
	assert.throws(() => validateBenchmark(result), /unexpected vtebench field: notes/);
});

test("rejects nested paths, process identifiers, environment, and terminal text", () => {
	for (const [field, value, message] of [
		["details", { value: "/Users/example/private" }, /absolute path/],
		["processId", 1234, /sensitive metadata/],
		["environment", { CI: "true" }, /sensitive metadata/],
		["terminalText", "secret output", /sensitive metadata/],
	]) {
		const result = benchmark();
		result.scenarios.vtebench[field] = value;
		assert.throws(() => validateBenchmark(result), message);
	}
});
