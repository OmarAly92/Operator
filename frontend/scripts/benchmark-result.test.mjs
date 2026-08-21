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
			expectedKeySha256: "ab".repeat(32),
			managedBrowser: undefined,
		},
	);
	assert.throws(() => parseArtifactArguments(["--shell", "electron"], {}), /OPERATOR_BENCH_SIGNED_ARTIFACT/);
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

test("release attestation accepts a signed artifact-bound provenance statement", async () => {
	const { validateReleaseAttestation } = await import("./benchmark-artifact.mjs");
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-benchmark-release-attestation-valid-"));
	try {
		const artifact = path.join(temporaryRoot, "Operator-1.2.3-arm64.zip");
		await writeFile(artifact, "signed-release");
		const fixture = await createReleaseAttestationFixture(temporaryRoot, artifact);
		assert.deepEqual(
			await validateReleaseAttestation({
				signedArtifact: artifact,
				...fixture,
				applicationVersion: "1.2.3",
				architecture: process.arch,
				publisherIdentity: "TEAM123456",
			}),
			fixture.attestation,
		);
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
				env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
				{ platform: "darwin", env: {}, collectRuntimeMetadata: runtime },
			),
			/OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID/,
		);
		await assert.rejects(
			preflightArtifactBenchmark(
				{ shell: "electron", signedArtifact: artifact, installedApp },
				{
					platform: "darwin",
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
	const windowsPublisher = expectedPublisherForPlatform("win32", {
		OPERATOR_BENCH_EXPECTED_WINDOWS_PUBLISHER: "CN=Operator Release",
		OPERATOR_BENCH_EXPECTED_WINDOWS_CERTIFICATE_THUMBPRINT: "AA BB CC DD EE FF 00 11 22 33 44 55 66 77 88 99 AA BB CC DD",
	});
	assert.deepEqual(windowsPublisher, {
		identity: "CN=Operator Release",
		thumbprint: "AABBCCDDEEFF00112233445566778899AABBCCDD",
	});
	assert.doesNotThrow(() => validatePublisherIdentity("win32", windowsPublisher, windowsPublisher));
	assert.throws(
		() => validatePublisherIdentity("win32", { ...windowsPublisher, thumbprint: "00".repeat(20) }, windowsPublisher),
		/trusted Windows publisher certificate/,
	);
	const linuxPublisher = expectedPublisherForPlatform("linux", {
		OPERATOR_BENCH_EXPECTED_LINUX_GPG_FINGERPRINT: "0123456789ABCDEF0123456789ABCDEF01234567",
	});
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
						env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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
					env: { OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID: "TEAM123456" },
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

test("artifact binding fails closed on native formats without a proven extractor", async () => {
	const { verifyInstalledArtifactBinding } = await import("./benchmark-artifact.mjs");
	await assert.rejects(
		verifyInstalledArtifactBinding({ platform: "win32", signedArtifact: "installer.exe", installedApp: "installed" }),
		/cannot cryptographically bind the Windows installed tree/,
	);
	await assert.rejects(
		verifyInstalledArtifactBinding({ platform: "linux", signedArtifact: "release.AppImage", installedApp: "installed" }),
		/cannot cryptographically bind the Linux installed tree/,
	);
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
				{ resultRoot },
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
