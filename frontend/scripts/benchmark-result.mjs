import { lstat, mkdir, mkdtemp, rename, rm, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

export const RESULT_FIELDS = Object.freeze([
	"schemaVersion",
	"shell",
	"scenario",
	"commit",
	"dirty",
	"buildProfile",
	"platform",
	"architecture",
	"osVersion",
	"cpu",
	"logicalCores",
	"physicalMemory",
	"webviewRuntimeVersion",
	"rendererKind",
	"displayScale",
	"scenarioConfiguration",
	"warmups",
	"sampleCount",
	"samples",
	"median",
	"p95",
	"unit",
]);

export const DEFAULT_RESULT_ROOT = fileURLToPath(new URL("../perf/results/", import.meta.url));

const execFileAsync = promisify(execFile);

const REQUIRED_SAMPLES = Object.freeze({
	"warm-start": 10,
	"first-run": 10,
	"idle-memory": 5,
	"idle-daemon-memory": 5,
	vtebench: 10,
	"large-output": 10,
});

const REQUIRED_WARMUPS = Object.freeze({
	"warm-start": 3,
	"first-run": 3,
	vtebench: 3,
	"large-output": 3,
});

function isPlainObject(value) {
	if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
	const prototype = Object.getPrototypeOf(value);
	return prototype === Object.prototype || prototype === null;
}

function fieldTokens(field) {
	return field
		.replace(/([a-z0-9])([A-Z])/g, "$1-$2")
		.toLowerCase()
		.split(/[^a-z0-9]+/)
		.filter(Boolean);
}

function isPidField(field) {
	const tokens = fieldTokens(field);
	return tokens.includes("pid") || tokens.includes("pids") || tokens.some((token, index) => token === "process" && /^ids?$/.test(tokens[index + 1] ?? ""));
}

function isPrivateField(field) {
	const privateTokens = new Set([
		"token",
		"tokens",
		"password",
		"passwords",
		"credential",
		"credentials",
		"secret",
		"secrets",
		"env",
		"environment",
	]);
	return fieldTokens(field).some((token) => privateTokens.has(token));
}

function isAbsolutePath(value) {
	return path.posix.isAbsolute(value) || path.win32.isAbsolute(value);
}

function validateSanitizedValue(value, location) {
	if (typeof value === "string") {
		if (isAbsolutePath(value)) throw new Error(`absolute paths are forbidden at ${location}`);
		return;
	}
	if (typeof value === "number") {
		if (!Number.isFinite(value)) throw new Error(`non-finite numbers are forbidden at ${location}`);
		return;
	}
	if (typeof value === "boolean" || value === null) return;
	if (Array.isArray(value)) {
		value.forEach((entry, index) => validateSanitizedValue(entry, `${location}[${index}]`));
		return;
	}
	if (!isPlainObject(value)) throw new Error(`unsupported value at ${location}`);
	for (const [key, entry] of Object.entries(value)) {
		if (isPidField(key)) throw new Error(`PID-like fields are forbidden at ${location}.${key}`);
		if (isPrivateField(key)) throw new Error(`private fields are forbidden at ${location}.${key}`);
		validateSanitizedValue(entry, `${location}.${key}`);
	}
}

function requireString(benchmarkResult, field) {
	if (typeof benchmarkResult[field] !== "string" || benchmarkResult[field].trim() === "") {
		throw new Error(`invalid result field: ${field}`);
	}
}

function requirePositiveNumber(benchmarkResult, field) {
	if (
		typeof benchmarkResult[field] !== "number" ||
		!Number.isFinite(benchmarkResult[field]) ||
		benchmarkResult[field] <= 0
	) {
		throw new Error(`invalid result field: ${field}`);
	}
}

export function summarizeSamples(samples) {
	if (!Array.isArray(samples) || samples.length === 0 || samples.some((sample) => !Number.isFinite(sample))) {
		throw new Error("samples must contain only finite numbers");
	}
	const ordered = [...samples].sort((left, right) => left - right);
	const middle = Math.floor(ordered.length / 2);
	const median = ordered.length % 2 === 0 ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle];
	const p95 = ordered[Math.ceil(ordered.length * 0.95) - 1];
	return { median, p95 };
}

export function createBenchmarkResult(input) {
	const sampleSummary = summarizeSamples(input.samples);
	return validateBenchmarkResult({
		schemaVersion: 1,
		shell: input.shell,
		scenario: input.scenario,
		commit: input.git.commit,
		dirty: input.git.dirty,
		buildProfile: input.buildProfile,
		platform: input.host.platform,
		architecture: input.host.architecture,
		osVersion: input.host.osVersion,
		cpu: input.host.cpu,
		logicalCores: input.host.logicalCores,
		physicalMemory: input.host.physicalMemory,
		webviewRuntimeVersion: input.renderer.webviewRuntimeVersion,
		rendererKind: input.renderer.rendererKind,
		displayScale: input.renderer.displayScale,
		scenarioConfiguration: input.scenarioConfiguration,
		warmups: input.warmups,
		sampleCount: input.samples.length,
		samples: input.samples,
		median: sampleSummary.median,
		p95: sampleSummary.p95,
		unit: input.unit,
	});
}

function validateResultShape(benchmarkResult) {
	if (!isPlainObject(benchmarkResult)) throw new Error("benchmark result must be an object");
	for (const key of Object.keys(benchmarkResult)) {
		if (!RESULT_FIELDS.includes(key)) throw new Error(`unknown result field: ${key}`);
	}
	for (const field of RESULT_FIELDS) {
		if (!Object.hasOwn(benchmarkResult, field)) throw new Error(`missing result field: ${field}`);
	}
}

function validateResultMetadata(benchmarkResult) {
	if (benchmarkResult.schemaVersion !== 1) throw new Error("schemaVersion must equal 1");
	for (const field of [
		"shell",
		"scenario",
		"commit",
		"buildProfile",
		"platform",
		"architecture",
		"osVersion",
		"cpu",
		"webviewRuntimeVersion",
		"rendererKind",
		"unit",
	]) {
		requireString(benchmarkResult, field);
	}
	if (!/^[0-9a-f]{40}$/i.test(benchmarkResult.commit)) throw new Error("commit must be a full Git object ID");
	if (typeof benchmarkResult.dirty !== "boolean") throw new Error("dirty must be a boolean");
	if (!Number.isInteger(benchmarkResult.logicalCores) || benchmarkResult.logicalCores <= 0) {
		throw new Error("invalid result field: logicalCores");
	}
	requirePositiveNumber(benchmarkResult, "physicalMemory");
	requirePositiveNumber(benchmarkResult, "displayScale");
	if (!isPlainObject(benchmarkResult.scenarioConfiguration)) throw new Error("scenarioConfiguration must be an object");
}

function validateResultSampling(benchmarkResult) {
	if (!Number.isInteger(benchmarkResult.warmups) || benchmarkResult.warmups < 0) {
		throw new Error("warmups must be a non-negative integer");
	}
	const requiredWarmups = REQUIRED_WARMUPS[benchmarkResult.scenario] ?? 0;
	if (benchmarkResult.warmups < requiredWarmups) {
		throw new Error(`${benchmarkResult.scenario} requires at least ${requiredWarmups} warmups`);
	}
	if (!Number.isInteger(benchmarkResult.sampleCount) || benchmarkResult.sampleCount < 1) {
		throw new Error("sampleCount must be a positive integer");
	}
	if (
		!Array.isArray(benchmarkResult.samples) ||
		benchmarkResult.samples.some((sample) => typeof sample !== "number" || !Number.isFinite(sample))
	) {
		throw new Error("samples must contain only finite numbers");
	}
	if (benchmarkResult.samples.some((sample) => sample < 0)) throw new Error("samples must be non-negative");
	if (benchmarkResult.sampleCount !== benchmarkResult.samples.length) {
		throw new Error("sampleCount must equal samples.length");
	}
	const requiredSamples = REQUIRED_SAMPLES[benchmarkResult.scenario] ?? 1;
	if (benchmarkResult.samples.length < requiredSamples) {
		throw new Error(`${benchmarkResult.scenario} requires at least ${requiredSamples} samples`);
	}
}

function validateResultSummary(benchmarkResult) {
	const sampleSummary = summarizeSamples(benchmarkResult.samples);
	if (!Object.is(benchmarkResult.median, sampleSummary.median)) throw new Error(`median must equal ${sampleSummary.median}`);
	if (!Object.is(benchmarkResult.p95, sampleSummary.p95)) throw new Error(`p95 must equal ${sampleSummary.p95}`);
}

export function validateBenchmarkResult(benchmarkResult) {
	validateResultShape(benchmarkResult);
	validateResultMetadata(benchmarkResult);
	validateResultSampling(benchmarkResult);
	validateResultSummary(benchmarkResult);
	validateSanitizedValue(benchmarkResult, "result");
	return benchmarkResult;
}

export function assertResultPath(outputPath, resultRoot = DEFAULT_RESULT_ROOT) {
	const resolvedRoot = path.resolve(resultRoot);
	const resolvedOutput = path.resolve(outputPath);
	const relative = path.relative(resolvedRoot, resolvedOutput);
	if (relative === "" || relative.startsWith(`..${path.sep}`) || relative === ".." || path.isAbsolute(relative)) {
		throw new Error(`result path is outside perf/results: ${outputPath}`);
	}
	return resolvedOutput;
}

export async function writeBenchmarkResult(outputPath, benchmarkResult, options = {}) {
	const validated = validateBenchmarkResult(benchmarkResult);
	const resolvedOutput = assertResultPath(outputPath, options.resultRoot ?? DEFAULT_RESULT_ROOT);
	await mkdir(path.dirname(resolvedOutput), { recursive: true });
	await writeFile(resolvedOutput, `${JSON.stringify(validated, null, "\t")}\n`, "utf8");
	return resolvedOutput;
}

async function pathExists(targetPath) {
	try {
		await lstat(targetPath);
		return true;
	} catch (error) {
		if (error?.code === "ENOENT") return false;
		throw error;
	}
}

async function cleanupFailures(operations) {
	const failures = [];
	for (const operation of operations) {
		try {
			await operation();
		} catch (error) {
			failures.push(error);
		}
	}
	return failures;
}

async function rollbackBenchmarkResultBatch({ backups, published, stagingRoot, renamePath, removePath }) {
	const removals = [...published].reverse().map((outputPath) => () => removePath(outputPath, { force: true }));
	const restorations = [...backups].reverse().map(({ backupPath, outputPath }) => () => renamePath(backupPath, outputPath));
	const failures = [
		...await cleanupFailures(removals),
		...await cleanupFailures(restorations),
	];
	const backupsRemain = (await Promise.all(backups.map(({ backupPath }) => pathExists(backupPath)))).some(Boolean);
	if (!backupsRemain) failures.push(...await cleanupFailures([() => removePath(stagingRoot, { recursive: true, force: true })]));
	return failures;
}

export async function writeBenchmarkResultBatch(entries, options = {}) {
	if (!Array.isArray(entries) || entries.length === 0) throw new Error("benchmark result batch must not be empty");
	const resultRoot = path.resolve(options.resultRoot ?? DEFAULT_RESULT_ROOT);
	const plannedResults = entries.map(({ outputPath, benchmarkResult }) => ({
		outputPath: assertResultPath(outputPath, resultRoot),
		benchmarkResult: validateBenchmarkResult(benchmarkResult),
	}));
	await mkdir(resultRoot, { recursive: true });
	const stagingRoot = await mkdtemp(path.join(resultRoot, ".benchmark-stage-"));
	const backups = [];
	const published = [];
	const renamePath = options.rename ?? rename;
	const removePath = options.rm ?? rm;
	try {
		for (let index = 0; index < plannedResults.length; index += 1) {
			await (options.writeFile ?? writeFile)(
				path.join(stagingRoot, `${index}.json`),
				`${JSON.stringify(plannedResults[index].benchmarkResult, null, "\t")}\n`,
				"utf8",
			);
		}
		for (let index = 0; index < plannedResults.length; index += 1) {
			const outputPath = plannedResults[index].outputPath;
			await mkdir(path.dirname(outputPath), { recursive: true });
			if (await pathExists(outputPath)) {
				const backupPath = path.join(stagingRoot, `${index}.backup`);
				await renamePath(outputPath, backupPath);
				backups.push({ outputPath, backupPath });
			}
			await renamePath(path.join(stagingRoot, `${index}.json`), outputPath);
			published.push(outputPath);
		}
	} catch (error) {
		const cleanupErrors = await rollbackBenchmarkResultBatch({ backups, published, stagingRoot, renamePath, removePath });
		if (cleanupErrors.length > 0) {
			throw new AggregateError(
				[error, ...cleanupErrors],
				`benchmark result publication failed and rollback encountered ${cleanupErrors.length} cleanup failure${cleanupErrors.length === 1 ? "" : "s"}`,
				{ cause: error },
			);
		}
		throw error;
	}
	await removePath(stagingRoot, { recursive: true, force: true });
	return plannedResults.map(({ outputPath }) => outputPath);
}

export function parseNamedArguments(argv) {
	const namedArguments = {};
	for (let index = 0; index < argv.length; index += 2) {
		const flag = argv[index];
		const value = argv[index + 1];
		if (!flag?.startsWith("--") || value === undefined) throw new Error(`invalid argument: ${flag ?? ""}`);
		const name = flag.slice(2);
		if (Object.hasOwn(namedArguments, name)) throw new Error(`duplicate argument: ${flag}`);
		namedArguments[name] = value;
	}
	return namedArguments;
}

export function scenarioResultConfiguration(scenario) {
	return Object.fromEntries(
		Object.entries(scenario).filter(([key]) => !["kind", "warmups", "samples", "unit"].includes(key)),
	);
}

export function collectHostMetadata() {
	return {
		platform: process.platform,
		architecture: process.arch,
		osVersion: os.release(),
		cpu: os.cpus()[0]?.model?.trim() || "unknown",
		logicalCores: os.cpus().length,
		physicalMemory: os.totalmem(),
	};
}

export async function collectGitMetadata(repositoryRoot = fileURLToPath(new URL("../../", import.meta.url))) {
	const [{ stdout: commitOutput }, { stdout: statusOutput }] = await Promise.all([
		execFileAsync("git", ["rev-parse", "HEAD"], { cwd: repositoryRoot }),
		execFileAsync(
			"git",
			["status", "--porcelain", "--untracked-files=normal", "--", ".", ":(exclude)frontend/perf/results/**"],
			{ cwd: repositoryRoot },
		),
	]);
	return { commit: commitOutput.trim(), dirty: statusOutput.trim() !== "" };
}

export function benchmarkResultPath({ shell, scenario, platform = process.platform, architecture = process.arch, variant }) {
	const segments = [platform, architecture, shell, scenario, variant].filter(Boolean);
	if (segments.some((segment) => !/^[a-z0-9][a-z0-9._-]*$/i.test(segment))) throw new Error("invalid benchmark result filename segment");
	return path.join(DEFAULT_RESULT_ROOT, `${segments.join("-")}.json`);
}
