import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
	assertResultPath,
	createBenchmarkResult,
	summarizeSamples,
	validateBenchmarkResult,
	writeBenchmarkResult,
} from "./benchmark-result.mjs";

const samples = [9, 1, 5, 7, 3, 2, 4, 6, 8, 10];

function validResult() {
	return {
		schemaVersion: 1,
		shell: "electron",
		scenario: "warm-start",
		commit: "8311fc6004cefc1146dc1ac2b13413cb801c835b",
		dirty: false,
		buildProfile: "signed-release",
		platform: "darwin",
		architecture: "arm64",
		osVersion: "25.6.0",
		cpu: "Apple M3 Pro",
		logicalCores: 12,
		physicalMemory: 18_000_000_000,
		webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
		rendererKind: "chromium-webgl",
		displayScale: 2,
		scenarioConfiguration: {
			completionMark: "operator:board-interactive",
			processState: "warm",
		},
		warmups: 3,
		sampleCount: 10,
		samples,
		median: 5.5,
		p95: 10,
		unit: "milliseconds",
	};
}

async function createMacReleaseFixture(temporaryRoot) {
	const artifact = path.join(temporaryRoot, "Operator-1.2.3-arm64.zip");
	const installedApp = path.join(temporaryRoot, "Operator.app");
	const executable = path.join(installedApp, "Contents", "MacOS", "operator");
	const resources = path.join(installedApp, "Contents", "Resources");
	const packagedFiles = [
		path.join(resources, "daemon", "opr"),
		path.join(resources, "agent-browser", "agent-browser"),
		path.join(resources, "acp-runtime", "node", "bin", "node"),
		path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js"),
	];
	await writeFile(artifact, "signed-release");
	for (const target of [executable, ...packagedFiles]) {
		await mkdir(path.dirname(target), { recursive: true });
		await writeFile(target, path.basename(target));
	}
	return { artifact, installedApp };
}

test("summarizeSamples returns the median and nearest-rank p95", () => {
	assert.deepEqual(summarizeSamples(samples), { median: 5.5, p95: 10 });
});

test("validateBenchmarkResult accepts the exact public result schema", () => {
	assert.deepEqual(validateBenchmarkResult(validResult()), validResult());
});

test("validateBenchmarkResult rejects unknown top-level fields", () => {
	assert.throws(
		() => validateBenchmarkResult({ ...validResult(), outputFile: "warm-start.json" }),
		/unknown result field: outputFile/,
	);
});

test("validateBenchmarkResult rejects fewer samples than the scenario requires", () => {
	const result = validResult();
	result.samples = result.samples.slice(0, 9);
	result.sampleCount = 9;
	result.median = 5;
	result.p95 = 9;
	assert.throws(() => validateBenchmarkResult(result), /warm-start requires at least 10 samples/);
});

test("validateBenchmarkResult enforces the scenario warmup contract", () => {
	assert.throws(() => validateBenchmarkResult({ ...validResult(), warmups: 2 }), /warm-start requires at least 3 warmups/);
});

test("validateBenchmarkResult rejects non-finite samples", () => {
	for (const value of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
		const result = validResult();
		result.samples = [...result.samples];
		result.samples[4] = value;
		assert.throws(() => validateBenchmarkResult(result), /samples must contain only finite numbers/);
	}
});

test("validateBenchmarkResult rejects missing hardware and webview metadata", () => {
	for (const field of [
		"platform",
		"architecture",
		"osVersion",
		"cpu",
		"logicalCores",
		"physicalMemory",
		"webviewRuntimeVersion",
		"rendererKind",
		"displayScale",
	]) {
		const result = validResult();
		delete result[field];
		assert.throws(() => validateBenchmarkResult(result), new RegExp(`missing result field: ${field}`));
	}
});

test("validateBenchmarkResult rejects absolute paths in nested configuration", () => {
	for (const absolutePath of ["/Users/example/Operator.app", "C:\\Users\\example\\Operator.exe", "\\\\server\\share\\Operator.exe"]) {
		const result = validResult();
		result.scenarioConfiguration = { artifact: { location: absolutePath } };
		assert.throws(() => validateBenchmarkResult(result), /absolute paths are forbidden/);
	}
});

test("validateBenchmarkResult rejects PID-like fields at any depth", () => {
	for (const key of ["pid", "processId", "renderer_pid", "childPids"]) {
		const result = validResult();
		result.scenarioConfiguration = { process: { [key]: 42119 } };
		assert.throws(() => validateBenchmarkResult(result), /PID-like fields are forbidden/);
	}
});

test("validateBenchmarkResult rejects credential and environment fields", () => {
	for (const key of ["token", "password", "credential", "environment", "env"]) {
		const result = validResult();
		result.scenarioConfiguration = { [key]: "private" };
		assert.throws(() => validateBenchmarkResult(result), /private fields are forbidden/);
	}
});

test("validateBenchmarkResult rejects summary values that do not match samples", () => {
	assert.throws(() => validateBenchmarkResult({ ...validResult(), p95: 9 }), /p95 must equal 10/);
});

test("assertResultPath rejects paths outside perf/results", () => {
	const root = path.join(os.tmpdir(), "operator-benchmark", "perf", "results");
	assert.throws(() => assertResultPath(path.join(root, "..", "private.json"), root), /outside perf\/results/);
	assert.equal(assertResultPath(path.join(root, "electron-warm-start.json"), root), path.join(root, "electron-warm-start.json"));
});

test("writeBenchmarkResult writes validated JSON only within perf/results", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-result-"));
	const resultRoot = path.join(temporaryRoot, "perf", "results");
	const outputPath = path.join(resultRoot, "electron-warm-start.json");
	try {
		await writeBenchmarkResult(outputPath, validResult(), { resultRoot });
		assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), validResult());
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("createBenchmarkResult derives sample count and summaries", () => {
	const result = createBenchmarkResult({
		shell: "electron",
		scenario: "warm-start",
		buildProfile: "local-packaged",
		git: { commit: "8311fc6004cefc1146dc1ac2b13413cb801c835b", dirty: true },
		host: {
			platform: "darwin",
			architecture: "arm64",
			osVersion: "25.6.0",
			cpu: "Apple M3 Pro",
			logicalCores: 12,
			physicalMemory: 18_000_000_000,
		},
		renderer: {
			webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
			rendererKind: "chromium-webgl",
			displayScale: 2,
		},
		scenarioConfiguration: { completionMark: "operator:board-interactive" },
		warmups: 3,
		samples,
		unit: "milliseconds",
	});
	assert.equal(result.sampleCount, 10);
	assert.equal(result.median, 5.5);
	assert.equal(result.p95, 10);
	assert.equal(result.dirty, true);
	assert.deepEqual(Object.keys(result), [
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
});

test("scenarios fix startup, memory, and terminal sampling contracts", async () => {
	const scenarios = JSON.parse(await readFile(new URL("../perf/scenarios.json", import.meta.url), "utf8"));
	assert.deepEqual(scenarios["warm-start"], {
		kind: "startup",
		warmups: 3,
		samples: 10,
		unit: "milliseconds",
		completionMark: "operator:board-interactive",
		processState: "warm",
	});
	assert.deepEqual(scenarios["first-run"], {
		kind: "startup",
		warmups: 3,
		samples: 10,
		unit: "milliseconds",
		completionEndpoint: "daemon:/readyz",
		processState: "fresh-daemon",
	});
	assert.deepEqual(scenarios["idle-memory"], {
		kind: "memory",
		warmups: 0,
		samples: 5,
		unit: "bytes",
		idleSeconds: 60,
		accounting: "full-electron-process-tree",
	});
	assert.equal(scenarios.vtebench.completionMark, "operator:terminal-ready");
	assert.equal(scenarios.vtebench.transport, "daemon-terminal-mux");
	assert.equal(scenarios["large-output"].outputBytes, 16_777_216);
});

test("shell arguments accept only Electron shell scenarios", async () => {
	const { parseShellArguments } = await import("./benchmark-shell.mjs");
	assert.deepEqual(parseShellArguments(["--shell", "electron", "--scenario", "warm-start"]), {
		shell: "electron",
		scenario: "warm-start",
	});
	assert.throws(() => parseShellArguments(["--shell", "tauri", "--scenario", "warm-start"]), /only electron/);
	assert.throws(() => parseShellArguments(["--shell", "electron", "--scenario", "vtebench"]), /unsupported shell scenario/);
});

test("process-tree accounting includes the launched process and every descendant", async () => {
	const { processTreeBytesFromPosixTable } = await import("./benchmark-shell.mjs");
	const table = ["100 1 1024", "101 100 512", "102 101 256", "200 1 8192"].join("\n");
	assert.equal(processTreeBytesFromPosixTable(table, 100), 1_835_008);
});

test("first-run completion observes daemon readiness while warm-start uses the renderer mark", async () => {
	const { observeStartupCompletion } = await import("./benchmark-shell.mjs");
	let requests = 0;
	const firstRunTimestamp = await observeStartupCompletion({
		scenario: { processState: "fresh-daemon", completionEndpoint: "daemon:/readyz" },
		daemonPort: 45001,
		fetchImpl: async (url) => {
			assert.equal(url, "http://127.0.0.1:45001/readyz");
			requests += 1;
			return {
				ok: true,
				json: async () => (requests === 1 ? { status: "starting" } : { status: "ready", service: "operator-daemon" }),
			};
		},
		now: () => 2345,
		wait: async () => {},
	});
	assert.equal(firstRunTimestamp, 2345);
	assert.equal(requests, 2);
	const warmTimestamp = await observeStartupCompletion({
		scenario: { processState: "warm", completionMark: "operator:board-interactive" },
		page: {},
		rendererTimestamp: async (_page, mark) => {
			assert.equal(mark, "operator:board-interactive");
			return 3456;
		},
	});
	assert.equal(warmTimestamp, 3456);
});

test("startup duration requires a timestamp attested at native process spawn", async () => {
	const { startupDurationFromSpawn } = await import("./benchmark-shell.mjs");
	assert.equal(startupDurationFromSpawn("1000", 1125), 125);
	assert.throws(() => startupDurationFromSpawn("", 1125), /spawn timestamp unavailable/);
	assert.throws(() => startupDurationFromSpawn("1200", 1125), /spawn timestamp is later/);
});

test("terminal arguments require the Task 4 acknowledgement scenarios", async () => {
	const { parseTerminalArguments, terminalEvidenceProfile, terminalThroughputSample } = await import("./benchmark-terminal.mjs");
	assert.deepEqual(parseTerminalArguments(["--shell", "electron", "--scenario", "vtebench"]), {
		shell: "electron",
		scenario: "vtebench",
	});
	assert.throws(() => parseTerminalArguments(["--shell", "electron", "--scenario", "warm-start"]), /unsupported terminal scenario/);
	assert.equal(terminalThroughputSample("vtebench", 250, {}), 4);
	assert.equal(terminalThroughputSample("large-output", 2000, { outputBytes: 16_777_216 }), 8_388_608);
	assert.throws(() => terminalThroughputSample("large-output", 0, { outputBytes: 16_777_216 }), /positive acknowledgement duration/);
	assert.deepEqual(terminalEvidenceProfile({}), {
		buildProfile: "local-electron-webview-non-binding",
		evidenceScope: "non-binding",
		runtimeAttestation: "npm-electron-driver",
	});
	assert.throws(() => terminalEvidenceProfile({ OPERATOR_BENCH_BUILD_PROFILE: "signed-release" }), /cannot produce binding release evidence/);
});

test("artifact arguments require explicit signed and installed inputs", async () => {
	const { parseArtifactArguments } = await import("./benchmark-artifact.mjs");
	assert.deepEqual(
		parseArtifactArguments(["--shell", "electron"], {
			OPERATOR_BENCH_SIGNED_ARTIFACT: "release.zip",
			OPERATOR_BENCH_INSTALLED_APP: "installed-app",
		}),
		{
			shell: "electron",
			signedArtifact: "release.zip",
			installedApp: "installed-app",
			managedBrowser: undefined,
		},
	);
	assert.throws(() => parseArtifactArguments(["--shell", "electron"], {}), /OPERATOR_BENCH_SIGNED_ARTIFACT/);
});

test("artifact preflight rejects arbitrary paths before signature and runtime collection", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-attestation-"));
	try {
		const artifact = path.join(temporaryRoot, "notes.txt");
		const installedApp = path.join(temporaryRoot, "Operator.app");
		await writeFile(artifact, "not a release");
		await mkdir(installedApp);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{ platform: "darwin", verifySignature: async () => {} },
			),
			/native Electron release artifact/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight verifies signed identity, packaged contents, and runtime provenance", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-attested-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const preflight = await preflightArtifactBenchmark(
			{ shell: "electron", signedArtifact: artifact, installedApp },
			{
				platform: "darwin",
				verifySignature: async () => "Developer ID Application: Operator",
				collectRuntimeMetadata: async () => ({
					source: "installed-release-launch",
					webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
					rendererKind: "chromium",
					displayScale: 2,
				}),
			},
		);
		assert.equal(preflight.buildProfile, "signed-release-attested");
		assert.equal(preflight.renderer.webviewRuntimeVersion, "Electron 33.4.11 / Chromium 130.0.6723.191");
		assert.equal(preflight.renderer.displayScale, 2);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight refuses runtime metadata not observed from the installed release", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-runtime-refusal-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					verifySignature: async () => "Developer ID Application: Operator",
					collectRuntimeMetadata: async () => ({ source: "checkout-default" }),
				},
			),
			/must come from an installed release launch/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact runner preflights every input before creating result files", async () => {
	const { runArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-no-partial-"));
	const resultRoot = path.join(temporaryRoot, "perf", "results");
	try {
		const artifact = path.join(temporaryRoot, "Operator-missing-browser.zip");
		const installedApp = path.join(temporaryRoot, "Operator.app");
		await writeFile(artifact, "release");
		await mkdir(installedApp);
		await assert.rejects(
			runArtifactBenchmark(
				["--shell", "electron"],
				{
					OPERATOR_BENCH_SIGNED_ARTIFACT: artifact,
					OPERATOR_BENCH_INSTALLED_APP: installedApp,
					OPERATOR_BENCH_MANAGED_BROWSER: path.join(temporaryRoot, "missing-browser"),
				},
				{ resultRoot },
			),
		);
		await assert.rejects(readdir(resultRoot), /ENOENT/);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact byte accounting sums files recursively without following symlinks", async () => {
	const { measurePathBytes } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-artifact-"));
	try {
		await mkdir(path.join(temporaryRoot, "nested"));
		await writeFile(path.join(temporaryRoot, "one.bin"), Buffer.alloc(7));
		await writeFile(path.join(temporaryRoot, "nested", "two.bin"), Buffer.alloc(11));
		await symlink(path.join(temporaryRoot, "nested", "two.bin"), path.join(temporaryRoot, "linked.bin"));
		assert.equal(await measurePathBytes(temporaryRoot), 18);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});
