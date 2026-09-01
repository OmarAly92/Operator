import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, readdir, rename, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import {
	assertResultPath,
	createBenchmarkResult,
	summarizeSamples,
	validateBenchmarkResult,
	writeBenchmarkResult,
	writeBenchmarkResultBatch,
} from "./benchmark-result.mjs";

const samples = [9, 1, 5, 7, 3, 2, 4, 6, 8, 10];
const execFileAsync = promisify(execFile);

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
	const daemon = path.join(resources, "daemon", "opr");
	const agentBrowser = path.join(resources, "agent-browser", "agent-browser");
	const node = path.join(resources, "acp-runtime", "node", "bin", "node");
	const adapterRoot = path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp");
	const adapter = path.join(adapterRoot, "dist", "index.js");
	await writeFile(artifact, "signed-release");
	for (const [target, source] of [
		[executable, "process.stdout.write('Operator desktop\\n');"],
		[daemon, "process.stdout.write(process.argv.includes('version') ? '1.2.3\\n' : 'Operator opr\\n');"],
		[agentBrowser, "process.stdout.write('agent-browser 0.33.1\\n');"],
		[node, "if (process.argv[2]?.endsWith('dist/index.js')) { const { status } = require('node:child_process').spawnSync(process.execPath, process.argv.slice(2), { stdio: 'inherit' }); process.exit(status ?? 1); } process.stdout.write('v22.23.2\\n');"],
	]) {
		await mkdir(path.dirname(target), { recursive: true });
		await writeFile(target, `#!/usr/bin/env node\n${source}\n`);
		await chmod(target, 0o755);
	}
	await mkdir(path.dirname(adapter), { recursive: true });
	await writeFile(adapter, "if (process.argv.includes('--version')) process.stdout.write('0.64.2\\n');\n");
	await writeFile(path.join(adapterRoot, "package.json"), JSON.stringify({
		name: "@agentclientprotocol/claude-agent-acp",
		version: "0.64.2",
		bin: { "claude-agent-acp": "dist/index.js" },
	}));
	await writeFile(path.join(resources, "acp-runtime", "package.json"), JSON.stringify({ name: "@operator-dev/acp-runtime", dependencies: { "@agentclientprotocol/claude-agent-acp": "0.64.2" } }));
	return { artifact, installedApp };
}

async function createReleaseAttestationFixture(temporaryRoot, artifact, overrides = {}) {
	const { privateKey, publicKey } = generateKeyPairSync("ed25519");
	const publicKeyPath = path.join(temporaryRoot, "release-attestation-public.pem");
	const attestationPath = path.join(temporaryRoot, "release-attestation.json");
	const signaturePath = path.join(temporaryRoot, "release-attestation.sig");
	const publicKeyDer = publicKey.export({ type: "spki", format: "der" });
	const attestation = {
		schemaVersion: 1,
		artifactSha256: createHash("sha256").update(await readFile(artifact)).digest("hex"),
		applicationVersion: "1.2.3",
		architecture: process.arch,
		sourceCommit: "8311fc6004cefc1146dc1ac2b13413cb801c835b",
		publisherIdentity: "TEAM123456",
		...overrides,
	};
	const serialized = `${JSON.stringify(attestation, null, "\t")}\n`;
	await writeFile(publicKeyPath, publicKey.export({ type: "spki", format: "pem" }));
	await writeFile(attestationPath, serialized);
	await writeFile(signaturePath, sign(null, Buffer.from(serialized), privateKey));
	return {
		attestation,
		attestationPath,
		signaturePath,
		publicKeyPath,
		expectedKeySha256: createHash("sha256").update(publicKeyDer).digest("hex"),
	};
}

function releaseTrustAnchor(attestationKeySha256 = "ab".repeat(32)) {
	return {
		schemaVersion: 1,
		status: "trusted",
		attestationKeySha256,
		publishers: {
			darwin: { teamId: "TEAM123456" },
			win32: { identity: "CN=Operator Release", thumbprint: "AABBCCDDEEFF00112233445566778899AABBCCDD" },
			linux: { fingerprint: "0123456789ABCDEF0123456789ABCDEF01234567" },
		},
	};
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

test("idle-memory accounting excludes the daemon subtree and reports it separately", async () => {
	const { processTreeMemoryFromPosixTable } = await import("./benchmark-shell.mjs");
	const table = ["100 1 1024", "101 100 512", "102 100 256", "103 102 128", "200 1 8192"].join("\n");
	assert.deepEqual(processTreeMemoryFromPosixTable(table, 100, 102), {
		shellBytes: 1_572_864,
		daemonBytes: 393_216,
	});
});

test("unattested shell executables cannot inherit a requested binding profile", async () => {
	const { resolveShellBenchmarkProvenance } = await import("./benchmark-shell.mjs");
	const provenance = await resolveShellBenchmarkProvenance(
		{
			OPERATOR_BENCH_ELECTRON_EXECUTABLE: "/arbitrary/operator",
			OPERATOR_BENCH_BUILD_PROFILE: "signed-release-attested",
		},
		{
			resolveExecutable: async () => "/arbitrary/operator",
			collectGitMetadata: async () => ({ commit: "751744d15340c3d65166023f8c358f9a2438af78", dirty: true }),
		},
	);
	assert.deepEqual(provenance, {
		executablePath: "/arbitrary/operator",
		buildProfile: "local-installed-unattested-non-binding",
		git: { commit: "751744d15340c3d65166023f8c358f9a2438af78", dirty: true },
		attestation: undefined,
	});
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

test("native spawn launcher records its timestamp and replaces itself with the target executable", async (context) => {
	if (process.platform === "win32") {
		context.skip("POSIX launcher is not used on Windows");
		return;
	}
	const { prepareSpawnAttestation } = await import("./benchmark-shell.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-launcher-"));
	try {
		const target = path.join(temporaryRoot, "target.mjs");
		const targetOutput = path.join(temporaryRoot, "target-output.json");
		await writeFile(
			target,
			`#!/usr/bin/env node\nimport { writeFileSync } from "node:fs";\nwriteFileSync(process.env.OPERATOR_BENCH_TARGET_OUTPUT, JSON.stringify(process.argv.slice(2)));\n`,
		);
		await chmod(target, 0o755);
		const attestation = await prepareSpawnAttestation(target, temporaryRoot);
		const before = Date.now();
		await execFileAsync(attestation.executablePath, ["alpha", "beta"], {
			env: { ...process.env, ...attestation.env, OPERATOR_BENCH_TARGET_OUTPUT: targetOutput },
		});
		const after = Date.now();
		const spawnTimestamp = Number(await readFile(attestation.timestampPath, "utf8"));
		assert.ok(spawnTimestamp >= before && spawnTimestamp <= after);
		assert.deepEqual(JSON.parse(await readFile(targetOutput, "utf8")), ["alpha", "beta"]);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("first-run readiness observation starts before Playwright launch connection resolves", async () => {
	const { launchSample } = await import("./benchmark-shell.mjs");
	let readinessStarted = false;
	const application = {
		firstWindow: async () => ({}),
		close: async () => {},
	};
	const launchMeasurement = await launchSample(
		{
			executablePath: "/native/operator",
			scenario: { kind: "startup", processState: "fresh-daemon", completionEndpoint: "daemon:/readyz" },
			stateRoot: "/isolated/state",
		},
		{
			availablePort: async () => 45002,
			prepareSpawnAttestation: async (executablePath) => ({ executablePath, env: {}, timestampPath: "spawn" }),
			launchElectron: async () => {
				await new Promise((resolve) => setImmediate(resolve));
				assert.equal(readinessStarted, true);
				return application;
			},
			observeStartupCompletion: async () => {
				readinessStarted = true;
				return 1125;
			},
			nativeSpawnTimestamp: async () => "1000",
			rendererMetadata: async () => ({ webviewRuntimeVersion: "Electron 33 / Chromium 130", rendererKind: "chromium", displayScale: 2 }),
		},
	);
	assert.equal(launchMeasurement.sample, 125);
});

test("binding launch environment removes daemon ACP browser and runtime injection overrides", async () => {
	const { launchSample } = await import("./benchmark-shell.mjs");
	let launchedEnvironment;
	await launchSample(
		{
			executablePath: "/native/operator",
			scenario: { kind: "startup", processState: "warm", completionMark: "operator:board-interactive" },
			stateRoot: "/isolated/state",
		},
		{
			parentEnv: {
				PATH: "/usr/bin",
				CI: "true",
				OPERATOR_DAEMON_COMMAND: "/tmp/fake-daemon",
				OPERATOR_CLAUDE_ACP_COMMAND: "/tmp/fake-acp",
				OPERATOR_ACP_RUNTIME_DIR: "/tmp/fake-runtime",
				OPERATOR_AGENT_BROWSER_PATH: "/tmp/fake-browser",
				OPERATOR_BROWSER_RUNTIME_ADDRESS: "127.0.0.1:1",
				AGENT_BROWSER_CDP: "http://127.0.0.1:9222",
				NODE_OPTIONS: "--require=/tmp/inject.cjs",
				LD_PRELOAD: "/tmp/inject.so",
				DYLD_INSERT_LIBRARIES: "/tmp/inject.dylib",
				operator_daemon_command: "C:\\poison.exe",
				Path: "C:\\poison-bin",
			},
			availablePort: async () => 45006,
			prepareSpawnAttestation: async (executablePath) => ({ executablePath, env: {}, timestampPath: "spawn" }),
			launchElectron: async (options) => {
				launchedEnvironment = options.env;
				return { firstWindow: async () => ({}), close: async () => {} };
			},
			nativeSpawnTimestamp: async () => "1000",
			rendererMetadata: async () => ({ webviewRuntimeVersion: "Electron 33 / Chromium 130", rendererKind: "chromium", displayScale: 2 }),
			observeStartupCompletion: async () => 1125,
		},
	);
	assert.equal(launchedEnvironment.PATH, "/usr/bin");
	assert.equal(launchedEnvironment.Path, undefined);
	assert.equal(launchedEnvironment.operator_daemon_command, undefined);
	assert.equal(launchedEnvironment.CI, "true");
	for (const name of [
		"OPERATOR_DAEMON_COMMAND",
		"OPERATOR_CLAUDE_ACP_COMMAND",
		"OPERATOR_ACP_RUNTIME_DIR",
		"OPERATOR_AGENT_BROWSER_PATH",
		"OPERATOR_BROWSER_RUNTIME_ADDRESS",
		"AGENT_BROWSER_CDP",
		"NODE_OPTIONS",
		"LD_PRELOAD",
		"DYLD_INSERT_LIBRARIES",
	]) assert.equal(launchedEnvironment[name], undefined, name);
	assert.equal(launchedEnvironment.OPERATOR_DATA_DIR, "/isolated/state/data");
	assert.equal(launchedEnvironment.OPERATOR_PORT, "45006");
});

test("first-run closes Electron when readiness fails after launch succeeds", async () => {
	const { launchSample } = await import("./benchmark-shell.mjs");
	let closeCalls = 0;
	await assert.rejects(
		launchSample(
			{
				executablePath: "/native/operator",
				scenario: { kind: "startup", processState: "fresh-daemon", completionEndpoint: "daemon:/readyz" },
				stateRoot: "/isolated/state",
			},
			{
				availablePort: async () => 45004,
				prepareSpawnAttestation: async (executablePath) => ({ executablePath, env: {}, timestampPath: "spawn" }),
				launchElectron: async () => ({ close: async () => { closeCalls += 1; } }),
				observeStartupCompletion: async () => { throw new Error("readiness timed out"); },
			},
		),
		/readiness timed out/,
	);
	assert.equal(closeCalls, 1);
});

test("first-run cancels readiness observation when Electron launch fails", async () => {
	const { launchSample } = await import("./benchmark-shell.mjs");
	let readinessCancelled = false;
	await assert.rejects(
		launchSample(
			{
				executablePath: "/native/operator",
				scenario: { kind: "startup", processState: "fresh-daemon", completionEndpoint: "daemon:/readyz" },
				stateRoot: "/isolated/state",
			},
			{
				availablePort: async () => 45005,
				prepareSpawnAttestation: async (executablePath) => ({ executablePath, env: {}, timestampPath: "spawn" }),
				launchElectron: async () => { throw new Error("native launch failed"); },
				observeStartupCompletion: async ({ signal }) => await new Promise((_resolve, reject) => {
					signal?.addEventListener("abort", () => {
						readinessCancelled = true;
						reject(new DOMException("aborted", "AbortError"));
					});
				}),
			},
		),
		/native launch failed/,
	);
	assert.equal(readinessCancelled, true);
});

test("hung readiness requests are aborted within the overall deadline", async () => {
	const { observeStartupCompletion } = await import("./benchmark-shell.mjs");
	let abortedRequests = 0;
	await assert.rejects(
		observeStartupCompletion({
			scenario: { processState: "fresh-daemon", completionEndpoint: "daemon:/readyz" },
			daemonPort: 45003,
			timeoutMilliseconds: 30,
			requestTimeoutMilliseconds: 5,
			wait: async () => {},
			fetchImpl: async (_url, options) => {
				if (!options?.signal) throw new Error("missing bounded abort signal");
				return await new Promise((_resolve, reject) => {
					options.signal.addEventListener("abort", () => {
						abortedRequests += 1;
						reject(new DOMException("aborted", "AbortError"));
					});
				});
			},
		}),
		/readiness endpoint was not observed/,
	);
	assert.ok(abortedRequests > 0);
});

test("terminal arguments require the Task 4 acknowledgement scenarios", async () => {
	const { parseTerminalArguments, terminalEvidenceProfile, terminalThroughputSample, terminalWorkloadEvidence } = await import("./benchmark-terminal.mjs");
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
	assert.equal(
		terminalEvidenceProfile({ OPERATOR_BENCH_BUILD_PROFILE: "signed-release" }).buildProfile,
		"signed-release",
	);
	assert.deepEqual(
		terminalWorkloadEvidence(
			[
				{ name: "workload-start", timestamp: 10 },
				{ name: "workload", timestamp: 20 },
			],
			1,
			"large-output",
			{ outputBytes: 16_777_216 },
		),
		{ durations: [10], observedBytes: [undefined], observedWorkloads: 1, requiredWorkloads: 1, workloadSuccess: true },
	);
	assert.throws(
		() => terminalWorkloadEvidence(
			[
				{ name: "workload-start", timestamp: 10 },
			],
			1,
			"large-output",
			{ outputBytes: 16_777_216 },
		),
		/incomplete|required 1/,
	);
});

test("artifact arguments require explicit signed and installed inputs", async () => {
	const { parseArtifactArguments } = await import("./benchmark-artifact.mjs");
	assert.deepEqual(
		parseArtifactArguments(["--shell", "electron"], {
			OPERATOR_BENCH_SIGNED_ARTIFACT: "release.zip",
			OPERATOR_BENCH_INSTALLED_APP: "installed-app",
			OPERATOR_BENCH_RELEASE_ATTESTATION: "release-attestation.json",
			OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE: "release-attestation.sig",
			OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY: "release-attestation-public.pem",
			OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256: "ab".repeat(32),
		}),
		{
			shell: "electron",
			signedArtifact: "release.zip",
			installedApp: "installed-app",
			attestationPath: "release-attestation.json",
			signaturePath: "release-attestation.sig",
			publicKeyPath: "release-attestation-public.pem",
			managedBrowser: undefined,
		},
	);
	assert.throws(() => parseArtifactArguments(["--shell", "electron"], {}), /OPERATOR_BENCH_SIGNED_ARTIFACT/);
});

test("artifact trust identities cannot be supplied by the benchmark environment", async () => {
	const { parseArtifactArguments } = await import("./benchmark-artifact.mjs");
	const options = parseArtifactArguments(["--shell", "electron"], {
		OPERATOR_BENCH_SIGNED_ARTIFACT: "release.zip",
		OPERATOR_BENCH_INSTALLED_APP: "installed-app",
		OPERATOR_BENCH_RELEASE_ATTESTATION: "release-attestation.json",
		OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE: "release-attestation.sig",
		OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY: "release-attestation-public.pem",
		OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256: "ab".repeat(32),
		OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "ATTACKER123",
	});
	assert.equal(options.expectedKeySha256, undefined);
	assert.equal(options.expectedPublisher, undefined);
});

test("release attestation rejects an artifact digest mismatch", async () => {
	const { validateReleaseAttestation } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-release-artifact-mismatch-"));
	try {
		const artifact = path.join(temporaryRoot, "Operator-1.2.3-arm64.zip");
		await writeFile(artifact, "signed-release");
		const fixture = await createReleaseAttestationFixture(temporaryRoot, artifact);
		await writeFile(artifact, "different-signed-release");
		await assert.rejects(
			validateReleaseAttestation({
				signedArtifact: artifact,
				...fixture,
				applicationVersion: "1.2.3",
				architecture: process.arch,
				publisherIdentity: "TEAM123456",
			}),
			/artifact digest does not match/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("release attestation rejects a source commit changed after publisher signing", async () => {
	const { validateReleaseAttestation } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-release-commit-mismatch-"));
	try {
		const artifact = path.join(temporaryRoot, "Operator-1.2.3-arm64.zip");
		await writeFile(artifact, "signed-release");
		const fixture = await createReleaseAttestationFixture(temporaryRoot, artifact);
		await writeFile(fixture.attestationPath, `${JSON.stringify({ ...fixture.attestation, sourceCommit: "751744d15340c3d65166023f8c358f9a2438af78" }, null, "\t")}\n`);
		await assert.rejects(
			validateReleaseAttestation({
				signedArtifact: artifact,
				...fixture,
				applicationVersion: "1.2.3",
				architecture: process.arch,
				publisherIdentity: "TEAM123456",
			}),
			/release attestation signature is invalid/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("release attestation retains the key and detached signature needed for independent verification", async () => {
	const { validateReleaseAttestation } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-release-attestation-valid-"));
	try {
		const artifact = path.join(temporaryRoot, "Operator-1.2.3-arm64.zip");
		await writeFile(artifact, "signed-release");
		const fixture = await createReleaseAttestationFixture(temporaryRoot, artifact);
		const validated = await validateReleaseAttestation({
				signedArtifact: artifact,
				...fixture,
				applicationVersion: "1.2.3",
				architecture: process.arch,
				publisherIdentity: "TEAM123456",
			});
		assert.deepEqual(validated.statement, fixture.attestation);
		assert.equal(validated.verification.publicKeySha256, fixture.expectedKeySha256);
		assert.match(validated.verification.publicKeyPem, /^-----BEGIN PUBLIC KEY-----/);
		assert.match(validated.verification.signatureBase64, /^[A-Za-z0-9+/]+=*$/);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
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
		const attestation = await createReleaseAttestationFixture(temporaryRoot, artifact);
		const preflight = await preflightArtifactBenchmark(
			{
				shell: "electron",
				signedArtifact: artifact,
				installedApp,
				attestationPath: attestation.attestationPath,
				signaturePath: attestation.signaturePath,
				publicKeyPath: attestation.publicKeyPath,
				expectedKeySha256: attestation.expectedKeySha256,
			},
			{
				platform: "darwin",
				trustAnchor: releaseTrustAnchor(attestation.expectedKeySha256),
				verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
				verifyArtifactBinding: async () => {},
				collectRuntimeMetadata: async () => ({
					source: "installed-release-launch",
					architecture: process.arch,
					applicationVersion: "1.2.3",
					webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
					rendererKind: "chromium",
					displayScale: 2,
				}),
			},
		);
		assert.equal(preflight.buildProfile, "signed-release-attested");
		assert.equal(preflight.renderer.webviewRuntimeVersion, "Electron 33.4.11 / Chromium 130.0.6723.191");
		assert.equal(preflight.renderer.displayScale, 2);
		assert.deepEqual(preflight.attestation, attestation.attestation);
		assert.deepEqual(preflight.components, {
			daemon: "opr 1.2.3",
			agentBrowser: "agent-browser 0.33.1",
			node: "v22.23.2",
			acp: "@agentclientprotocol/claude-agent-acp 0.64.2",
		});
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
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({ source: "checkout-default" }),
				},
			),
			/must come from an installed release launch/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight refuses absent or mismatched trusted publisher identity", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-publisher-refusal-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const runtime = async () => ({
			source: "installed-release-launch",
			architecture: process.arch,
			webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
			rendererKind: "chromium",
			displayScale: 2,
		});
		await assert.rejects(
				preflightArtifactBenchmark(
					{ shell: "electron", signedArtifact: artifact, installedApp },
					{ platform: "darwin", collectRuntimeMetadata: runtime },
				),
				/repository-pinned release trust anchor is not configured/,
		);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Other", teamId: "OTHER98765" }),
					collectRuntimeMetadata: runtime,
				},
			),
			/trusted macOS Team ID/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("trusted publisher validation pins Windows certificate and Linux GPG identities", async () => {
	const { expectedPublisherForPlatform, validatePublisherIdentity } = await import("./benchmark-artifact.mjs");
	const trust = releaseTrustAnchor();
	const windowsPublisher = expectedPublisherForPlatform("win32", trust);
	assert.deepEqual(windowsPublisher, {
		identity: "CN=Operator Release",
		thumbprint: "AABBCCDDEEFF00112233445566778899AABBCCDD",
	});
	assert.doesNotThrow(() => validatePublisherIdentity("win32", windowsPublisher, windowsPublisher));
	assert.throws(
		() => validatePublisherIdentity("win32", { ...windowsPublisher, thumbprint: "00".repeat(20) }, windowsPublisher),
		/trusted Windows publisher certificate/,
	);
	const linuxPublisher = expectedPublisherForPlatform("linux", trust);
	assert.deepEqual(linuxPublisher, { fingerprint: "0123456789ABCDEF0123456789ABCDEF01234567" });
	assert.doesNotThrow(() => validatePublisherIdentity("linux", linuxPublisher, linuxPublisher));
	assert.throws(
		() => validatePublisherIdentity("linux", { fingerprint: "89ABCDEF0123456789ABCDEF0123456789ABCDEF" }, linuxPublisher),
		/trusted Linux GPG fingerprint/,
	);
});

test("artifact preflight rejects expected-path files with false component identities", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-component-refusal-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const agentBrowser = path.join(installedApp, "Contents", "Resources", "agent-browser", "agent-browser");
		await writeFile(agentBrowser, "#!/usr/bin/env node\nprocess.stdout.write('not-agent-browser\\n');\n");
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/agent-browser 0\.33\.1/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight rejects an ACP package whose executable mapping is not the packaged adapter", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-acp-refusal-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const acpPackage = path.join(installedApp, "Contents", "Resources", "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "package.json");
		await writeFile(acpPackage, JSON.stringify({
			name: "@agentclientprotocol/claude-agent-acp",
			version: "0.64.2",
			bin: { "claude-agent-acp": "dist/other.js" },
		}));
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/ACP adapter executable/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight requires exact agent-browser version semantics", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-browser-version-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const agentBrowser = path.join(installedApp, "Contents", "Resources", "agent-browser", "agent-browser");
		await writeFile(agentBrowser, "#!/usr/bin/env node\nprocess.stdout.write('agent-browser 0.33.10\\n');\n");
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						applicationVersion: "1.2.3",
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/exactly agent-browser 0\.33\.1/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight refuses a dev daemon for signed release evidence", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-daemon-version-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const daemon = path.join(installedApp, "Contents", "Resources", "daemon", "opr");
		await writeFile(daemon, "#!/usr/bin/env node\nprocess.stdout.write(process.argv.includes('version') ? 'dev\\n' : 'Operator opr\\n');\n");
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						applicationVersion: "1.2.3",
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/release semantic version instead of dev/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight requires the daemon version to match the installed application", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-version-match-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						applicationVersion: "1.2.4",
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/daemon version 1\.2\.3 does not match installed application version 1\.2\.4/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight pins the installed Electron and Chromium runtime versions", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-electron-version-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const daemon = path.join(installedApp, "Contents", "Resources", "daemon", "opr");
		await writeFile(daemon, "#!/usr/bin/env node\nprocess.stdout.write(process.argv.includes('version') ? '1.2.3\\n' : 'Operator opr\\n');\n");
		for (const webviewRuntimeVersion of [
			"Electron 33.4.12 / Chromium 130.0.6723.191",
			"Electron 33.4.11 / Chromium 130.0.6723.192",
		]) {
			await assert.rejects(
				preflightArtifactBenchmark(
					{ shell: "electron", signedArtifact: artifact, installedApp },
					{
						platform: "darwin",
						trustAnchor: releaseTrustAnchor(),
						verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
						verifyArtifactBinding: async () => {},
						collectRuntimeMetadata: async () => ({
							source: "installed-release-launch",
							architecture: process.arch,
							applicationVersion: "1.2.3",
							webviewRuntimeVersion,
							rendererKind: "chromium",
							displayScale: 2,
						}),
					},
				),
				/expected Electron 33\.4\.11 and Chromium 130\.0\.6723\.191/,
			);
		}
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight executes the packaged ACP adapter with the packaged Node runtime", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-acp-version-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const adapter = path.join(installedApp, "Contents", "Resources", "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js");
		await writeFile(adapter, "process.stdout.write('0.64.3\\n');\n");
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						applicationVersion: "1.2.3",
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/ACP executable must report exactly 0\.64\.2/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact preflight refuses installed components not bound to the signed artifact", async () => {
	const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-artifact-binding-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					trustAnchor: releaseTrustAnchor(),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => { throw new Error("installed tree does not match the signed artifact payload"); },
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
				},
			),
			/does not match the signed artifact payload/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("Windows and Linux artifact binding compare installed trees with extracted signed payloads", async () => {
	const { verifyInstalledArtifactBinding } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-cross-platform-binding-"));
	try {
		for (const platform of ["win32", "linux"]) {
			const payload = path.join(temporaryRoot, `${platform}-payload`);
			const installed = path.join(temporaryRoot, `${platform}-installed`);
			await mkdir(path.join(payload, "resources"), { recursive: true });
			await mkdir(path.join(installed, "resources"), { recursive: true });
			await writeFile(path.join(payload, platform === "win32" ? "operator.exe" : "operator"), "signed executable");
			await writeFile(path.join(installed, platform === "win32" ? "operator.exe" : "operator"), "signed executable");
			await writeFile(path.join(payload, "resources", "runtime"), "signed runtime");
			await writeFile(path.join(installed, "resources", "runtime"), "signed runtime");
			await assert.doesNotReject(verifyInstalledArtifactBinding(
				{ platform, signedArtifact: platform === "win32" ? "installer.exe" : "release.AppImage", installedApp: installed },
				{ extractPayload: async () => payload },
			));
			await writeFile(path.join(installed, "resources", "runtime"), "modified runtime");
			await assert.rejects(
				verifyInstalledArtifactBinding(
					{ platform, signedArtifact: platform === "win32" ? "installer.exe" : "release.AppImage", installedApp: installed },
					{ extractPayload: async () => payload },
				),
				/installed tree does not match the signed artifact payload/,
			);
		}
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("macOS artifact binding compares the installed tree with the signed zip payload", async (context) => {
	if (process.platform !== "darwin") {
		context.skip("ditto artifact binding is native to macOS");
		return;
	}
	const { verifyInstalledArtifactBinding } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-mac-binding-"));
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		await rm(artifact, { force: true });
		await execFileAsync("ditto", ["-c", "-k", "--keepParent", installedApp, artifact]);
		await assert.doesNotReject(verifyInstalledArtifactBinding({ platform: "darwin", signedArtifact: artifact, installedApp }));
		const agentBrowser = path.join(installedApp, "Contents", "Resources", "agent-browser", "agent-browser");
		await writeFile(agentBrowser, "#!/usr/bin/env node\nprocess.stdout.write('agent-browser 0.33.1\\nchanged');\n");
		await assert.rejects(
			verifyInstalledArtifactBinding({ platform: "darwin", signedArtifact: artifact, installedApp }),
			/installed tree does not match the signed artifact payload/,
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
		const attestation = await createReleaseAttestationFixture(temporaryRoot, artifact);
		await assert.rejects(
			runArtifactBenchmark(
				["--shell", "electron"],
				{
					OPERATOR_BENCH_SIGNED_ARTIFACT: artifact,
					OPERATOR_BENCH_INSTALLED_APP: installedApp,
					OPERATOR_BENCH_MANAGED_BROWSER: path.join(temporaryRoot, "missing-browser"),
					OPERATOR_BENCH_RELEASE_ATTESTATION: attestation.attestationPath,
					OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE: attestation.signaturePath,
					OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY: attestation.publicKeyPath,
					OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256: attestation.expectedKeySha256,
					OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456",
				},
					{ resultRoot, trustAnchor: releaseTrustAnchor(attestation.expectedKeySha256) },
			),
		);
		await assert.rejects(readdir(resultRoot), /ENOENT/);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("artifact runner rolls back the batch when a later result publication fails", async () => {
	const { runArtifactBenchmark } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-batch-rollback-"));
	const resultRoot = path.join(temporaryRoot, "perf", "results");
	try {
		const { artifact, installedApp } = await createMacReleaseFixture(temporaryRoot);
		const attestation = await createReleaseAttestationFixture(temporaryRoot, artifact);
		let publicationAttempts = 0;
		await assert.rejects(
			runArtifactBenchmark(
				["--shell", "electron"],
				{
					OPERATOR_BENCH_SIGNED_ARTIFACT: artifact,
					OPERATOR_BENCH_INSTALLED_APP: installedApp,
					OPERATOR_BENCH_RELEASE_ATTESTATION: attestation.attestationPath,
					OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE: attestation.signaturePath,
					OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY: attestation.publicKeyPath,
					OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256: attestation.expectedKeySha256,
					OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456",
				},
					{
						platform: "darwin",
						resultRoot,
						trustAnchor: releaseTrustAnchor(attestation.expectedKeySha256),
					verifySignature: async () => ({ identity: "Developer ID Application: Operator", teamId: "TEAM123456" }),
					verifyArtifactBinding: async () => {},
					collectRuntimeMetadata: async () => ({
						source: "installed-release-launch",
						architecture: process.arch,
						applicationVersion: "1.2.3",
						webviewRuntimeVersion: "Electron 33.4.11 / Chromium 130.0.6723.191",
						rendererKind: "chromium",
						displayScale: 2,
					}),
					collectHostMetadata: () => ({
						platform: "darwin",
						architecture: "arm64",
						osVersion: "25.5.0",
						cpu: "Apple M1 Max",
						logicalCores: 10,
						physicalMemory: 34_359_738_368,
					}),
					rename: async (...arguments_) => {
						publicationAttempts += 1;
						if (publicationAttempts === 2) throw new Error("induced later result publication failure");
						return await rename(...arguments_);
					},
				},
			),
			/induced later result publication failure/,
		);
		assert.equal(publicationAttempts, 2);
		assert.deepEqual(await readdir(resultRoot), []);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("batch rollback restores every existing result and reports cleanup failures", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-existing-rollback-"));
	const firstOutput = path.join(temporaryRoot, "first.json");
	const secondOutput = path.join(temporaryRoot, "second.json");
	try {
		await writeFile(firstOutput, "first-original\n");
		await writeFile(secondOutput, "second-original\n");
		let publicationRenames = 0;
		await assert.rejects(
			writeBenchmarkResultBatch(
				[
					{ outputPath: firstOutput, benchmarkResult: validResult() },
					{ outputPath: secondOutput, benchmarkResult: validResult() },
				],
				{
					resultRoot: temporaryRoot,
					rename: async (source, destination) => {
						const isPublication = /^[01]\.json$/.test(path.basename(source));
						if (isPublication && destination === secondOutput) {
							publicationRenames += 1;
							throw new Error("induced second publication failure");
						}
						if (isPublication) publicationRenames += 1;
						return await rename(source, destination);
					},
					rm: async (target, options) => {
						if (target === firstOutput) throw new Error("induced published-file removal failure");
						return await rm(target, options);
					},
				},
			),
			(error) => {
				assert.equal(error instanceof AggregateError, true);
				assert.match(error.message, /rollback encountered 1 cleanup failure/);
				assert.deepEqual(error.errors.map((entry) => entry.message), [
					"induced second publication failure",
					"induced published-file removal failure",
				]);
				return true;
			},
		);
		assert.equal(publicationRenames, 2);
		assert.equal(await readFile(firstOutput, "utf8"), "first-original\n");
		assert.equal(await readFile(secondOutput, "utf8"), "second-original\n");
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("batch rollback preserves an original backup when its restoration fails", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-preserved-backup-"));
	const firstOutput = path.join(temporaryRoot, "first.json");
	const secondOutput = path.join(temporaryRoot, "second.json");
	try {
		await writeFile(firstOutput, "first-original\n");
		await writeFile(secondOutput, "second-original\n");
		await assert.rejects(
			writeBenchmarkResultBatch(
				[
					{ outputPath: firstOutput, benchmarkResult: validResult() },
					{ outputPath: secondOutput, benchmarkResult: validResult() },
				],
				{
					resultRoot: temporaryRoot,
					rename: async (source, destination) => {
						if (path.basename(source) === "1.json") throw new Error("induced publication failure");
						if (source.endsWith("0.backup")) throw new Error("induced restoration failure");
						return await rename(source, destination);
					},
				},
			),
			(error) => error instanceof AggregateError && error.errors.some((entry) => entry.message === "induced restoration failure"),
		);
		const stagingDirectories = (await readdir(temporaryRoot)).filter((entry) => entry.startsWith(".benchmark-stage-"));
		assert.equal(stagingDirectories.length, 1);
		assert.equal(await readFile(path.join(temporaryRoot, stagingDirectories[0], "0.backup"), "utf8"), "first-original\n");
		assert.equal(await readFile(secondOutput, "utf8"), "second-original\n");
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

test("electron terminal results require observed workload evidence without by-construction defaults", async () => {
	const { terminalScenarioConfiguration } = await import("./benchmark-terminal.mjs");
	const scenario = { kind: "terminal", warmups: 3, samples: 10, unit: "workloads-per-second", completionMark: "operator:terminal-ready", transport: "daemon-terminal-mux" };
	const profile = { buildProfile: "local-electron-webview-non-binding", evidenceScope: "non-binding", runtimeAttestation: "npm-electron-driver" };
	assert.throws(() => terminalScenarioConfiguration(scenario, profile, undefined), /observed workload acknowledgements/);
	assert.throws(
		() => terminalScenarioConfiguration(scenario, profile, { durations: [], observedWorkloads: 0, requiredWorkloads: 13, workloadSuccess: false }),
		/observed workload acknowledgements/,
	);
	assert.deepEqual(terminalScenarioConfiguration(scenario, profile, { durations: [1], observedWorkloads: 13, requiredWorkloads: 13, workloadSuccess: true }), {
		completionMark: "operator:terminal-ready",
		transport: "daemon-terminal-mux",
		evidenceScope: "non-binding",
		runtimeAttestation: "npm-electron-driver",
		workloadSuccess: true,
		observedWorkloads: 13,
		requiredWorkloads: 13,
	});
});

test("workload acknowledgements may carry observed byte counts only on workload messages", async () => {
	const { terminalAcknowledgementDurations, terminalWorkloadEvidence } = await import("./benchmark-terminal.mjs");
	assert.deepEqual(
		terminalAcknowledgementDurations([
			{ name: "workload-start", timestamp: 10 },
			{ name: "workload", timestamp: 20, bytes: 4096 },
		]),
		{ durations: [10], observedBytes: [4096] },
	);
	assert.throws(
		() => terminalAcknowledgementDurations([{ name: "workload-start", timestamp: 10, bytes: 5 }]),
		/only a name and timestamp|name and timestamp/,
	);
	const evidence = terminalWorkloadEvidence(
		[
			{ name: "first-paint", timestamp: 1 },
			{ name: "workload-start", timestamp: 10 },
			{ name: "workload", timestamp: 20, bytes: 16_777_216 },
			{ name: "disposal", timestamp: 30 },
		],
		1,
		"large-output",
		{ outputBytes: 16_777_216 },
	);
	assert.deepEqual(evidence.observedBytes, [16_777_216]);
});

test("large-output results fail closed unless every observed workload carried the configured bytes", async () => {
	const { assertObservedOutputBytes } = await import("./benchmark-terminal.mjs");
	const configuration = { outputBytes: 16_777_216 };
	assert.equal(
		assertObservedOutputBytes({ observedBytes: [16_777_216, 16_777_400] }, "large-output", configuration),
		true,
	);
	assert.throws(
		() => assertObservedOutputBytes({ observedBytes: [16_777_216, undefined] }, "large-output", configuration),
		/never reported its observed byte count/,
	);
	assert.throws(
		() => assertObservedOutputBytes({ observedBytes: [8_388_608] }, "large-output", configuration),
		/observed 8388608 bytes across the workload window/,
	);
	assert.throws(
		() => assertObservedOutputBytes({ observedBytes: [16_777_216 + 131_072] }, "large-output", configuration),
		/the configured output plus bounded shell overhead/,
	);
	assert.equal(assertObservedOutputBytes({ observedBytes: [] }, "vtebench", {}), true);
});

test("terminal benchmark accepts the resource and latency scenarios with their sampling contracts", async () => {
	const { parseTerminalArguments, runTerminalBenchmark, tauriHarnessConfig, tauriHarnessProxyConfig } = await import("./benchmark-terminal.mjs");
	for (const scenario of ["input-latency", "reconnect", "cpu-time", "scroll-latency"]) {
		assert.deepEqual(parseTerminalArguments(["--shell", "tauri", "--scenario", scenario]), { shell: "tauri", scenario });
	}
	await assert.rejects(
		runTerminalBenchmark(["--shell", "tauri", "--scenario", "scroll-latency"], { OPERATOR_RUNTIME: "ptyhost" }),
		/OPERATOR_RUNTIME selects the benchmark shell's unused daemon, not OPERATOR_BENCH_DAEMON_URL/,
	);
	assert.deepEqual(JSON.parse(tauriHarnessConfig("http://127.0.0.1:5173")), {
		productName: "Operator Benchmark",
		identifier: "dev.operator.desktop.benchmark",
		build: { beforeDevCommand: "", devUrl: "http://127.0.0.1:5173" },
		app: { security: { capabilities: ["phase0", "default", "terminal-benchmark"] } },
	});
	const handlers = new Map();
	const proxy = tauriHarnessProxyConfig("http://127.0.0.1:4317");
	proxy.configure({ on: (event, handler) => handlers.set(event, handler) });
	assert.equal(proxy.target, "http://127.0.0.1:4317/");
	assert.equal(proxy.ws, true);
	let removedHeader;
	handlers.get("proxyReqWs")({ removeHeader: (name) => { removedHeader = name; } });
	assert.equal(removedHeader, "origin");
	assert.deepEqual(parseTerminalArguments(["--shell", "tauri", "--scenario", "vtebench", "--compositing", "disabled"]), {
		shell: "tauri",
		scenario: "vtebench",
		compositing: "disabled",
	});
	assert.deepEqual(parseTerminalArguments(["--shell", "tauri", "--scenario", "large-output", "--compositing", "enabled"]), {
		shell: "tauri",
		scenario: "large-output",
		compositing: "enabled",
	});
	assert.throws(() => parseTerminalArguments(["--shell", "tauri", "--scenario", "vtebench", "--compositing", "sometimes"]), /compositing/);
	const { REQUIRED_SAMPLES, REQUIRED_WARMUPS } = await import("./benchmark-result.mjs");
	assert.equal(REQUIRED_SAMPLES["input-latency"], 10);
	assert.equal(REQUIRED_SAMPLES.reconnect, 10);
	assert.equal(REQUIRED_SAMPLES["cpu-time"], 10);
	assert.equal(REQUIRED_SAMPLES["active-memory"], 5);
	assert.equal(REQUIRED_SAMPLES["scroll-latency"], 20);
	assert.equal(REQUIRED_WARMUPS["input-latency"], 3);
	assert.equal(REQUIRED_WARMUPS.reconnect, 3);
	assert.equal(REQUIRED_WARMUPS["cpu-time"], 3);
	assert.equal(REQUIRED_WARMUPS["scroll-latency"], 3);
});

test("compositing mode is recorded in terminal results and only pairs on linux", async () => {
	const { terminalScenarioConfiguration } = await import("./benchmark-terminal.mjs");
	const scenario = { kind: "terminal", warmups: 3, samples: 10, unit: "milliseconds", completionMark: "operator:terminal-ready", transport: "daemon-terminal-mux" };
	const profile = { buildProfile: "local-tauri-webview-non-binding", evidenceScope: "non-binding", runtimeAttestation: "tauri-dev-webview" };
	const workloadEvidence = { durations: [1], observedWorkloads: 13, requiredWorkloads: 13, workloadSuccess: true };
	const enabled = terminalScenarioConfiguration(scenario, profile, workloadEvidence, { compositingMode: "enabled" });
	assert.equal(enabled.compositingMode, "enabled");
	assert.throws(() => terminalScenarioConfiguration(scenario, profile, workloadEvidence, { compositingMode: "diabled" }), /compositingMode/);
});

test("cpu time per completed workload derives from observed process CPU time over observed workloads", async () => {
	const { cpuTimePerWorkload } = await import("./benchmark-terminal.mjs");
	assert.equal(cpuTimePerWorkload({ cpuMs: 1000, workloads: 10 }, { cpuMs: 3000, workloads: 20 }), 200);
	assert.throws(() => cpuTimePerWorkload({ cpuMs: 1000, workloads: 10 }, { cpuMs: 900, workloads: 20 }), /decreased/);
	assert.throws(() => cpuTimePerWorkload({ cpuMs: 1000, workloads: 10 }, { cpuMs: 2000, workloads: 0 }), /positive number of completed workloads/);
	assert.throws(() => cpuTimePerWorkload({ cpuMs: Number.NaN, workloads: 10 }, { cpuMs: 2000, workloads: 10 }), /finite/);
});

test("scenarios define the latency reconnect and resource scenarios on the fixed grid", async () => {
	const { readFile } = await import("node:fs/promises");
	const scenarios = JSON.parse(await readFile(new URL("../perf/scenarios.json", import.meta.url), "utf8"));
	for (const name of ["input-latency", "reconnect", "cpu-time", "active-memory"]) {
		assert.ok(scenarios[name], `missing scenario ${name}`);
		assert.equal(scenarios[name].completionMark, "operator:terminal-ready");
		assert.equal(scenarios[name].transport, "daemon-terminal-mux");
	}
	for (const name of ["input-latency", "reconnect", "cpu-time", "vtebench", "large-output"]) {
		assert.equal(scenarios[name].columns, 120);
		assert.equal(scenarios[name].rows, 40);
		assert.equal(scenarios[name].scrollback, 5000);
	}
	assert.equal(scenarios["active-memory"].kind, "memory");
	assert.equal(scenarios["cpu-time"].fixedWorkloads > 0, true);
});

test("evidence scope resolves only from the strictly validated environment switch", async () => {
	const { resolveEvidenceScope } = await import("./benchmark-result.mjs");
	assert.equal(resolveEvidenceScope({}), "non-binding");
	assert.equal(resolveEvidenceScope({ OPERATOR_BENCH_EVIDENCE_SCOPE: "non-binding" }), "non-binding");
	assert.equal(resolveEvidenceScope({ OPERATOR_BENCH_EVIDENCE_SCOPE: "binding" }), "binding");
	assert.throws(() => resolveEvidenceScope({ OPERATOR_BENCH_EVIDENCE_SCOPE: "BINDING" }), /OPERATOR_BENCH_EVIDENCE_SCOPE/);
	assert.throws(() => resolveEvidenceScope({ OPERATOR_BENCH_EVIDENCE_SCOPE: "attested" }), /OPERATOR_BENCH_EVIDENCE_SCOPE/);
});

test("terminal profiles stamp the resolved scope and binding requires a non-local build profile", async () => {
	const { terminalEvidenceProfile, tauriTerminalEvidenceProfile } = await import("./benchmark-terminal.mjs");
	assert.deepEqual(terminalEvidenceProfile({}), {
		buildProfile: "local-electron-webview-non-binding",
		evidenceScope: "non-binding",
		runtimeAttestation: "npm-electron-driver",
	});
	assert.equal(
		terminalEvidenceProfile({ OPERATOR_BENCH_BUILD_PROFILE: "ci-electron-release" }).buildProfile,
		"ci-electron-release",
	);
	assert.equal(terminalEvidenceProfile({ OPERATOR_BENCH_EVIDENCE_SCOPE: "binding", OPERATOR_BENCH_BUILD_PROFILE: "ci-electron-release" }).evidenceScope, "binding");
	assert.equal(tauriTerminalEvidenceProfile({ OPERATOR_BENCH_EVIDENCE_SCOPE: "binding", OPERATOR_BENCH_BUILD_PROFILE: "ci-tauri-release" }).buildProfile, "ci-tauri-release");
	assert.throws(
		() => terminalEvidenceProfile({ OPERATOR_BENCH_EVIDENCE_SCOPE: "binding" }),
		/OPERATOR_BENCH_BUILD_PROFILE/,
	);
	assert.throws(
		() => tauriTerminalEvidenceProfile({ OPERATOR_BENCH_EVIDENCE_SCOPE: "binding", OPERATOR_BENCH_BUILD_PROFILE: "local-tauri-webview-non-binding" }),
		/non-local/,
	);
});

test("cpu-time deltas derive from workload-tagged snapshots and reject untagged ones", async () => {
	const { cpuDeltasFromIterationSnapshots } = await import("./benchmark-terminal.mjs");
	assert.deepEqual(
		cpuDeltasFromIterationSnapshots(
			[
				{ cpuMs: 1000, workloads: 0 },
				{ cpuMs: 1010, workloads: 1 },
				{ cpuMs: 1030, workloads: 2 },
				{ cpuMs: 1055, workloads: 3 },
			],
			{ warmups: 1 },
		),
		[20, 25],
	);
	assert.throws(
		() => cpuDeltasFromIterationSnapshots([{ cpuMs: 1000 }, { cpuMs: 2000 }], { warmups: 0 }),
		/completed workload/,
	);
});

test("artifact arguments accept the tauri shell with its bundle inputs", async () => {
	const { parseArtifactArguments } = await import("./benchmark-artifact.mjs");
	assert.deepEqual(parseArtifactArguments(["--shell", "tauri"], {
		OPERATOR_BENCH_SIGNED_ARTIFACT: "dist/operator.AppImage",
	}), {
		shell: "tauri",
		signedArtifact: "dist/operator.AppImage",
		installedApp: undefined,
		packages: {},
	});
	assert.deepEqual(parseArtifactArguments(["--shell", "tauri"], {
		OPERATOR_BENCH_SIGNED_ARTIFACT: "dist/operator.zip",
		OPERATOR_BENCH_INSTALLED_APP: "dist/Operator.app",
		OPERATOR_BENCH_PACKAGE_DEB: "dist/operator.deb",
		OPERATOR_BENCH_PACKAGE_RPM: "dist/operator.rpm",
	}), {
		shell: "tauri",
		signedArtifact: "dist/operator.zip",
		installedApp: "dist/Operator.app",
		packages: { deb: "dist/operator.deb", rpm: "dist/operator.rpm" },
	});
	assert.throws(
		() => parseArtifactArguments(["--shell", "tauri"], {}),
		/OPERATOR_BENCH_SIGNED_ARTIFACT/,
	);
});

test("tauri artifact preflight extracts discovers and verifies the bundled components", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-tauri-artifact-preflight-"));
	try {
		const artifact = path.join(temporaryRoot, "operator-linux-x64.AppImage");
		await writeFile(artifact, "appimage-bytes");
		const debPath = path.join(temporaryRoot, "operator-linux-amd64.deb");
		const rpmPath = path.join(temporaryRoot, "operator-linux-x64.rpm");
		await writeFile(debPath, "deb");
		await writeFile(rpmPath, "rpm");
		const payloadRoot = path.join(temporaryRoot, "squashfs-root");
		const executable = path.join(payloadRoot, "usr", "bin", "operator");
		const resources = path.join(payloadRoot, "usr", "lib", "operator");
		for (const [target, source] of [
			[executable, "process.stdout.write('operator 0.10.3\\n');"],
			[path.join(resources, "daemon", "opr"), "process.stdout.write(process.argv.includes('version') ? '0.10.3\\n' : 'Operator opr\\n');"],
			[path.join(resources, "agent-browser", "agent-browser"), "process.stdout.write('agent-browser 0.33.1\\n');"],
			[path.join(resources, "acp-runtime", "node", "bin", "node"), "if (process.argv[2]?.endsWith('dist/index.js')) { const { status } = require('node:child_process').spawnSync(process.execPath, process.argv.slice(2), { stdio: 'inherit' }); process.exit(status ?? 1); } process.stdout.write('v22.23.2\\n');"],
		]) {
			await mkdir(path.dirname(target), { recursive: true });
			await writeFile(target, `#!/usr/bin/env node\n${source}\n`);
			await chmod(target, 0o755);
		}
		await mkdir(path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist"), { recursive: true });
		await writeFile(path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js"), "if (process.argv.includes('--version')) process.stdout.write('0.64.2\\n');\n");
		await writeFile(path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "package.json"), JSON.stringify({ name: "@agentclientprotocol/claude-agent-acp", version: "0.64.2", bin: { "claude-agent-acp": "dist/index.js" } }));
		await writeFile(path.join(resources, "acp-runtime", "package.json"), JSON.stringify({ name: "@operator-dev/acp-runtime", dependencies: { "@agentclientprotocol/claude-agent-acp": "0.64.2" } }));

		const { preflightArtifactBenchmark } = await import("./benchmark-artifact.mjs");
		const preflight = await preflightArtifactBenchmark({
			shell: "tauri",
			signedArtifact: artifact,
			installedApp: undefined,
			packages: { deb: debPath, rpm: rpmPath },
		}, {
			extractPayload: async () => ({
				resourcesRoot: resources,
				executable,
				applicationRoot: payloadRoot,
				daemon: path.join(resources, "daemon", "opr"),
				agentBrowser: path.join(resources, "agent-browser", "agent-browser"),
			}),
			commandOutput: async (file_, args_) => {
				const stdout = (() => {
					if (String(file_).includes(`acp-runtime${path.sep}node`) || String(file_).includes("acp-runtime/node")) {
						return args_?.[0]?.endsWith("dist/index.js") ? "0.64.2" : "v22.23.2";
					}
					if (String(file_).endsWith("agent-browser")) return "agent-browser 0.33.1";
					if (String(file_).endsWith("opr")) return args_?.includes("--help") ? "Operator opr" : "0.10.3";
					if (args_?.[0] === "--version") return "operator 0.10.3";
					return "";
				})();
				return { stdout };
			},
			collectRuntimeMetadata: async () => ({
				source: "packaged-binary-probe",
				applicationVersion: "0.10.3",
				architecture: process.arch,
				webviewRuntimeVersion: `operator 0.10.3`,
				rendererKind: "webview",
				displayScale: 1,
			}),
		});
		assert.equal(preflight.buildProfile, "local-tauri-bundle-unattested-non-binding");
		assert.equal(preflight.packages.rpmExists, true);
		assert.equal(preflight.packages.debExists, true);
		assert.equal(preflight.components.daemon, "opr 0.10.3");

		await assert.rejects(
			() => preflightArtifactBenchmark({ shell: "tauri", signedArtifact: path.join(temporaryRoot, "missing.AppImage") }, {}),
			/ENOENT|must be a regular file/,
		);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("the artifact runner writes binding-scope electron results and tauri results through one entrypoint", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-artifact-entrypoint-"));
	try {
		const { runArtifactBenchmark } = await import("./benchmark-artifact.mjs");
		const artifact = path.join(temporaryRoot, "operator-linux-x64.AppImage");
		await writeFile(artifact, "appimage-bytes");
		let sawShell;
		await runArtifactBenchmark(["--shell", "tauri"], {
			OPERATOR_BENCH_SIGNED_ARTIFACT: artifact,
		}, {
			resultRoot: temporaryRoot,
			preflightArtifactBenchmark: async (options) => {
				sawShell = options.shell;
				return {
					buildProfile: "local-tauri-bundle-unattested-non-binding",
					components: { daemon: "opr 0.10.3" },
					measured: [{ scenario: "base-signed-download", artifactKind: "primary-signed-update", bytes: 1234 }],
					renderer: { webviewRuntimeVersion: "operator 0.10.3", rendererKind: "webview", displayScale: 1 },
					executable: "/tmp/operator",
					packages: { rpmExists: false, debExists: false },
				};
			},
		});
		assert.equal(sawShell, "tauri");
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});

test("terminal result variants distinguish linux compositing pairs on disk", async () => {
	const { terminalResultVariant } = await import("./benchmark-terminal.mjs");
	const { benchmarkResultPath } = await import("./benchmark-result.mjs");
	assert.equal(terminalResultVariant({}, undefined), undefined);
	assert.equal(terminalResultVariant({}, "disabled"), "compositing-disabled");
	assert.equal(terminalResultVariant({ OPERATOR_BENCH_VARIANT: "nightly" }, undefined), "nightly");
	assert.equal(terminalResultVariant({ OPERATOR_BENCH_VARIANT: "nightly" }, "enabled"), "nightly-compositing-enabled");
	const enabled = benchmarkResultPath({ shell: "tauri", scenario: "vtebench", variant: terminalResultVariant({}, "enabled") });
	const disabled = benchmarkResultPath({ shell: "tauri", scenario: "vtebench", variant: terminalResultVariant({}, "disabled") });
	assert.notEqual(enabled, disabled);
	assert.match(enabled, /compositing-enabled\.json$/);
	assert.match(disabled, /compositing-disabled\.json$/);
});
