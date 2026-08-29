import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { WORKLOAD_METADATA } from "./workloads.mjs";

const scenarios = JSON.parse(
	await readFile(new URL("./scenarios.json", import.meta.url), "utf8"),
);

const topLevelFields = new Set([
	"schema",
	"recordedAt",
	"commit",
	"platform",
	"architecture",
	"cpu",
	"logicalCores",
	"physicalMemory",
	"browserVersion",
	"displayScale",
	"renderer",
	"rendererVersion",
	"rendererKind",
	"scenarios",
]);

function requireString(value, field) {
	if (typeof value !== "string" || value.length === 0) {
		throw new Error(`${field} must be a non-empty string`);
	}
}

function requirePositive(value, field, integer = false) {
	if (!Number.isFinite(value) || value <= 0 || (integer && !Number.isInteger(value))) {
		throw new Error(`${field} must be finite and positive`);
	}
}

function rejectSensitive(value) {
	if (Array.isArray(value)) {
		for (const item of value) rejectSensitive(item);
		return;
	}
	if (!value || typeof value !== "object") return;
	for (const [key, child] of Object.entries(value)) {
		const normalized = key.toLowerCase();
		if (
			normalized === "cwd" ||
			normalized === "pid" ||
			normalized.includes("path") ||
			normalized.includes("environment") ||
			normalized === "env" ||
			normalized.includes("username") ||
			normalized === "terminaltext" ||
			normalized === "contents"
		) {
			throw new Error(`sensitive metadata field is forbidden: ${key}`);
		}
		rejectSensitive(child);
	}
}

function validateConfiguration(name, actual) {
	const expected = scenarios[name];
	if (!actual || typeof actual !== "object" || Array.isArray(actual)) {
		throw new Error(`${name}.configuration must be an object`);
	}
	const actualKeys = Object.keys(actual).sort();
	const expectedKeys = Object.keys(expected).sort();
	if (JSON.stringify(actualKeys) !== JSON.stringify(expectedKeys)) {
		throw new Error(`${name}.configuration does not match scenarios.json`);
	}
	for (const key of expectedKeys) {
		if (actual[key] !== expected[key]) {
			throw new Error(`${name}.configuration.${key} does not match scenarios.json`);
		}
	}
}

export function summarizeSamples(samples) {
	if (!Array.isArray(samples) || samples.length === 0 || samples.some((sample) => !Number.isFinite(sample) || sample <= 0)) {
		throw new Error("samples must contain only finite positive values");
	}
	const sorted = [...samples].sort((left, right) => left - right);
	const middle = Math.floor(sorted.length / 2);
	const median = sorted.length % 2 === 0
		? (sorted[middle - 1] + sorted[middle]) / 2
		: sorted[middle];
	const p95 = sorted[Math.ceil(sorted.length * 0.95) - 1];
	return { median, p95 };
}

export function validateBenchmark(result) {
	if (!result || typeof result !== "object" || Array.isArray(result)) {
		throw new Error("benchmark result must be an object");
	}
	rejectSensitive(result);
	for (const key of Object.keys(result)) {
		if (!topLevelFields.has(key)) throw new Error(`unexpected field: ${key}`);
	}
	if (result.schema !== "operator.terminal-benchmark.v1") {
		throw new Error("schema must be operator.terminal-benchmark.v1");
	}
	for (const field of [
		"recordedAt",
		"commit",
		"platform",
		"architecture",
		"cpu",
		"browserVersion",
		"renderer",
		"rendererVersion",
		"rendererKind",
	]) requireString(result[field], field);
	if (Number.isNaN(Date.parse(result.recordedAt))) throw new Error("recordedAt must be an ISO timestamp");
	requirePositive(result.logicalCores, "logicalCores", true);
	requirePositive(result.physicalMemory, "physicalMemory", true);
	requirePositive(result.displayScale, "displayScale");
	if (result.renderer !== "xterm") throw new Error("renderer must be xterm");
	if (result.rendererVersion !== "5.5.0") throw new Error("rendererVersion must be 5.5.0");
	if (!new Set(["webgl", "canvas"]).has(result.rendererKind)) {
		throw new Error("rendererKind must be webgl or canvas");
	}
	if (!result.scenarios || typeof result.scenarios !== "object" || Array.isArray(result.scenarios)) {
		throw new Error("scenarios must be an object");
	}
	const entries = Object.entries(result.scenarios);
	if (entries.length === 0) throw new Error("scenarios must not be empty");
	for (const [name, scenario] of entries) {
		if (!(name in scenarios)) throw new Error(`unknown scenario: ${name}`);
		validateConfiguration(name, scenario.configuration);
		if (!Array.isArray(scenario.samples) || scenario.samples.length !== scenarios[name].samples) {
			throw new Error(`${name} must contain exactly 10 measured samples`);
		}
		const summary = summarizeSamples(scenario.samples);
		if (scenario.median !== summary.median || scenario.p95 !== summary.p95) {
			throw new Error(`${name} summary does not match samples`);
		}
		if (scenario.unit !== scenarios[name].unit) throw new Error(`${name}.unit does not match configuration`);
		requireString(scenario.workload, `${name}.workload`);
		if (!/^[a-f0-9]{64}$/.test(scenario.workloadDigest)) {
			throw new Error(`${name}.workloadDigest must be SHA-256`);
		}
		if (
			scenario.workload !== WORKLOAD_METADATA[name].workload ||
			scenario.workloadDigest !== WORKLOAD_METADATA[name].workloadDigest
		) {
			throw new Error(`${name} workload metadata does not match its generator`);
		}
		if (name === "vtebench" && scenario.seed !== scenarios[name].seed) {
			throw new Error("vtebench.seed does not match configuration");
		}
	}
	return result;
}

async function validateFile(path) {
	const result = JSON.parse(await readFile(path, "utf8"));
	validateBenchmark(result);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
	if (process.argv.length !== 3) {
		process.stderr.write("usage: node bench/schema.mjs <result.json>\n");
		process.exitCode = 2;
	} else {
		try {
			await validateFile(process.argv[2]);
		} catch (error) {
			process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
			process.exitCode = 1;
		}
	}
}
