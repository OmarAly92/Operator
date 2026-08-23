import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createBenchmarkResult } from "./benchmark-result.mjs";
import { derivePlatformSummary, writePlatformSummary } from "./phase0-platform-summary.mjs";

const COMMIT = "8311fc6004cefc1146dc1ac2b13413cb801c835b";

test("the producer resolves retained updater material from the canonical results-relative layout", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-updaterlayout-"));
	try {
		const tree = await buildValidEvidenceTree(root);
		const summary = await derivePlatformSummary({
			platform: tree.platform,
			sourceCommit: tree.sourceCommit,
			resultsDir: tree.resultsDir,
			configPath: tree.configPath,
			releaseWorkflowPath: tree.releaseWorkflowPath,
		});
		assert.equal(summary.updaterSigning.signatureValid, true);
		assert.ok(summary.inputs.some((entry) => entry.file.startsWith("updater-signing/")));
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("the linux rpm requirement is satisfied by observed package evidence from the tauri runner", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-rpmflag-"));
	try {
		const tree = await buildValidEvidenceTree(root, { platform: "linux", rpmEvidence: "result-flag" });
		const summary = await derivePlatformSummary(tree);
		assert.equal(summary.evidence.artifact.rpmExists, true);

		const absentRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-rpmabsent-"));
		try {
			const absent = await buildValidEvidenceTree(absentRoot, { platform: "linux", rpmEvidence: "absent" });
			await assert.rejects(() => derivePlatformSummary(absent), /rpm/i);
		} finally {
			await rm(absentRoot, { recursive: true, force: true });
		}
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("windows authenticode verification output is consumed as known evidence not refused", async () => {
	const validRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-winver-"));
	try {
		const valid = await buildValidEvidenceTree(validRoot, {
			platform: "win32",
			windowsVerification: [{ Status: 0, StatusMessage: "Signature verified.", SignerCertificate: { Subject: "CN=Operator Release" } }],
		});
		const summary = await derivePlatformSummary(valid);
		assert.ok(summary.inputs.some((entry) => entry.file === "windows-artifact-verification.json"));

		const invalidRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-winver-bad-"));
		try {
			const invalid = await buildValidEvidenceTree(invalidRoot, { platform: "win32", windowsVerification: [{ Status: 1, StatusMessage: "An error occurred" }] });
			await assert.rejects(() => derivePlatformSummary(invalid), /authenticode/i);
		} finally {
			await rm(invalidRoot, { recursive: true, force: true });
		}

		const emptyRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-winver-empty-"));
		try {
			const empty = await buildValidEvidenceTree(emptyRoot, { platform: "win32", windowsVerification: [] });
			await assert.rejects(() => derivePlatformSummary(empty), /authenticode/i);
		} finally {
			await rm(emptyRoot, { recursive: true, force: true });
		}
	} finally {
		await rm(validRoot, { recursive: true, force: true });
	}
});

test("producer refuses to write a summary when raw inputs are missing and names each gap", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-gap-"));
	try {
		await assert.rejects(
			async () => derivePlatformSummary(await buildValidEvidenceTree(root, { dropEverything: true })),
			(error) => {
				const message = error.message;
				return ["state-audit.json", "cors-evidence.json", "browser-evidence-system.json", "browser-evidence-managed.json", "legacy-update-evidence.json"].every((name) => message.includes(name));
			},
		);
		await assert.rejects(
			async () => writePlatformSummary(await buildValidEvidenceTree(root, { dropEverything: true })),
			/missing/,
		);
		assert.equal(await readFile(path.join(root, "results", "phase0-platform-linux.json"), "utf8").then(() => true, () => false), false);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("producer derives terminal metrics from binding benchmark results including the linux compositing pair", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-terminal-"));
	try {
		const tree = await buildValidEvidenceTree(root, { platform: "linux", tauriVtebenchPairMedians: [12, 10] });
		const summary = await derivePlatformSummary(tree);
		assert.equal(summary.schemaVersion, 1);
		assert.equal(summary.platform, "linux");
		assert.equal(summary.sourceCommit, COMMIT);
		assert.equal(summary.evidence.terminal.tauri.vtebench.median, 10);
		assert.equal(summary.evidence.terminal.tauri.compositingPairObserved, true);
		assert.equal(summary.evidence.terminal.electron.vtebench.median, tree.expectedMetrics.electron.vtebench.median);

		const incompleteRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-pairgap-"));
		try {
			const incomplete = await buildValidEvidenceTree(incompleteRoot, { platform: "linux", tauriVtebenchPairMedians: [12] });
			await assert.rejects(() => derivePlatformSummary(incomplete), /compositing/i);
		} finally {
			await rm(incompleteRoot, { recursive: true, force: true });
		}
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("producer rejects non-binding scopes commit drift and fabricated workload success", async () => {
	for (const [pattern, options] of [
		[/commit/, { driftOneCommit: true }],
		[/binding/, { evidenceScope: "non-binding" }],
		[/workload/, { observedWorkloads: 12, requiredWorkloads: 13 }],
	]) {
		const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-strict-"));
		try {
			const tree = await buildValidEvidenceTree(root, options);
			await assert.rejects(() => derivePlatformSummary(tree), pattern);
		} finally {
			await rm(root, { recursive: true, force: true });
		}
	}
});

test("producer re-verifies retained updater material cryptographically instead of trusting JSON equality", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-updater-"));
	try {
		const tree = await buildValidEvidenceTree(root);
		await derivePlatformSummary(tree);

		const tamperRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-tamper-"));
		const tampered = await buildValidEvidenceTree(tamperRoot, { tamperRetainedFixture: true });
		await assert.rejects(() => derivePlatformSummary(tampered), /signature is invalid|retained updater/);

		const lieRoot = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-lie-"));
		const lyingDigest = await buildValidEvidenceTree(lieRoot, { lieAboutSignatureSha256: true });
		await assert.rejects(() => derivePlatformSummary(lyingDigest), /signatureSha256/);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("producer binds legacy migration digests to the derived artifact digests", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-legacy-"));
	try {
	 const mismatched = await buildValidEvidenceTree(root, { legacyTargetDigest: "34".repeat(32) });
	 await assert.rejects(() => derivePlatformSummary(mismatched), /target artifact/);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("written summaries carry an inputs manifest whose digests match the consumed bytes", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-write-"));
	try {
		const tree = await buildValidEvidenceTree(root);
		const outputPath = await writePlatformSummary(tree);
		const written = JSON.parse(await readFile(outputPath, "utf8"));
		assert.equal(written.sourceCommit, COMMIT);
		assert.match(written.generatedAt, /^\d{4}-\d{2}-\d{2}T/);
		for (const entry of written.inputs) {
			const candidate = path.join(root, "results", entry.file);
			const exists = await readFile(candidate).then(() => true, () => false);
			if (!exists) continue;
			const bytes = await readFile(candidate);
			assert.equal(createHash("sha256").update(bytes).digest("hex"), entry.sha256);
		}
		assert.ok(written.inputs.length >= 5);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

const ELECTRON_ARTIFACT_SHA256 = "ef".repeat(32);
const TAURI_ARTIFACT_SHA256 = "12".repeat(32);
const ALIASES = ["operator-darwin-arm64.zip", "operator-darwin-x64.zip", "operator-win32-x64.exe", "operator-linux-x64.AppImage"];

function benchmarkResultFixture({ shell, scenario, samples, warmups, unit, configuration, rendererKind = "webgl", commit = COMMIT }) {
	return createBenchmarkResult({
		shell,
		scenario,
		buildProfile: "signed-release-attested",
		git: { commit, dirty: false },
		host: {
			platform: "linux",
			architecture: "x64",
			osVersion: "6.8.0",
			cpu: "test cpu",
			logicalCores: 8,
			physicalMemory: 16_000_000_000,
		},
		renderer: { webviewRuntimeVersion: "WebKit 620.1", rendererKind, displayScale: 1 },
		scenarioConfiguration: configuration,
		warmups,
		samples,
		unit,
	});
}

function medianOf(values) {
	const ordered = [...values].sort((left, right) => left - right);
	const middle = Math.floor(ordered.length / 2);
	return ordered.length % 2 === 0 ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle];
}

async function buildValidEvidenceTree(root, options = {}) {
	const platform = options.platform ?? "linux";
	const resultsDir = path.join(root, "results");
	const updaterDir = path.join(resultsDir, "updater-signing");
	await mkdir(updaterDir, { recursive: true });
	if (options.dropEverything) {
		return {
			platform,
			sourceCommit: COMMIT,
			resultsDir,
			updaterDir,
			configPath: path.join(root, "tauri.conf.json"),
			releaseWorkflowPath: path.join(root, "frontend-release.yml"),
			expectedMetrics: {},
		};
	}
	await writeFile(path.join(resultsDir, "state-audit.json"), `${JSON.stringify({ platform, passed: true, leaked: false, scannedRoots: 3, observedOutsideRoot: 0, shutdownChanges: 5, crashChanges: 2 }, null, "\t")}\n`);
	await writeFile(path.join(resultsDir, "cors-evidence.json"), `${JSON.stringify({
		schemaVersion: 1,
		passed: true,
		exactAllowlist: true,
		allowlist: ["tauri://localhost", "http://tauri.localhost"],
		probes: [
			{ origin: "tauri://localhost", allowed: true },
			{ origin: "http://tauri.localhost", allowed: true },
			{ origin: "null", allowed: false },
			{ origin: "http://evil.example", allowed: false },
		],
	}, null, "\t")}\n`);
	for (const mode of ["system", "managed"]) {
		await writeFile(path.join(resultsDir, `browser-evidence-${mode}.json`), `${JSON.stringify({
			schemaVersion: 1,
			mode,
			passed: true,
			isolatedWhileRunning: true,
			cleanupPassed: true,
			stateRootRemoved: true,
			observedProcessCount: 2,
			cookies: { observedNames: [`phase0_${mode}_marker`], markerPresent: true },
			crossModeCookieIsolation: true,
		}, null, "\t")}\n`);
	}
	const artifactConfig = (shell) => ({
		artifactKind: "primary-signed-update",
		accounting: "recursive-regular-file-bytes",
		...(shell === "tauri" && options.rpmEvidence === "result-flag" ? { rpmExists: true } : {}),
		baseContents: ["opr 0.10.3", "agent-browser 0.33.1", "@agentclientprotocol/claude-agent-acp 0.64.2"],
		artifactIdentity: "native-signature-and-required-contents-verified",
		runtimeMetadataSource: "installed-release-launch",
		evidenceScope: "binding",
		workloadSuccess: true,
		releaseAttestation: {
			statement: {
				schemaVersion: 1,
				artifactSha256: shell === "electron" ? ELECTRON_ARTIFACT_SHA256 : TAURI_ARTIFACT_SHA256,
				applicationVersion: "0.10.3",
				architecture: "x64",
				sourceCommit: options.driftOneCommit ? COMMIT : COMMIT,
				publisherIdentity: "TEAM123456",
			},
			verification: { publicKeySha256: "ab".repeat(32) },
			source: "publisher-ed25519-signed",
		},
	});
	const resultFiles = [];
	const pushResult = (result) => {
		const name = `${result.platform}-${result.architecture}-${result.shell}-${result.scenario}${result.scenarioConfiguration.compositingMode ? `-${result.scenarioConfiguration.compositingMode}` : ""}.json`;
		resultFiles.push(writeFile(path.join(resultsDir, name), `${JSON.stringify(result, null, "\t")}\n`));
	};
	const expectedMetrics = { electron: {}, tauri: {} };
	for (const shell of ["electron", "tauri"]) {
		for (const scenario of ["warm-start", "first-run"]) {
			const values = Array.from({ length: 10 }, (_, index) => index + 1);
			pushResult(benchmarkResultFixture({
				shell,
				scenario,
				samples: options.driftOneCommit && scenario === "vtebench" && shell === "tauri" ? values : values,
				warmups: 3,
				unit: "milliseconds",
				configuration: { evidenceScope: options.evidenceScope ?? "binding", workloadSuccess: true, observedWorkloads: options.observedWorkloads ?? 13, requiredWorkloads: options.requiredWorkloads ?? 13 },
			}));
			expectedMetrics[shell][scenario] = { median: 5.5, p95: 10 };
		}
		for (const scenario of ["idle-memory"]) {
			const values = Array.from({ length: 5 }, (_, index) => 100 + index * 2);
			pushResult(benchmarkResultFixture({ shell, scenario, samples: values, warmups: 0, unit: "bytes", configuration: { evidenceScope: "binding" } }));
			expectedMetrics[shell][scenario] = { median: 104 };
		}
		const memoryVariants = shell === "tauri" && platform === "linux" ? ["enabled", "disabled"] : [undefined];
		for (const compositingMode of memoryVariants) {
			const values = Array.from({ length: 5 }, (_, index) => 100 + index * 2);
			pushResult(benchmarkResultFixture({
				shell,
				scenario: "active-memory",
				samples: values,
				warmups: 0,
				unit: "bytes",
				configuration: { ...(compositingMode ? { compositingMode } : {}), evidenceScope: "binding" },
			}));
			if (!compositingMode || compositingMode === "disabled") expectedMetrics[shell]["active-memory"] = { median: 104 };
		}
	}
	const terminalScenarioUnits = {
		"terminal-open": "milliseconds",
		vtebench: "workloads-per-second",
		"large-output": "bytes-per-second",
		"input-latency": "milliseconds",
		reconnect: "milliseconds",
		"cpu-time": "cpu-ms-per-workload",
	};
	const pairMedians = options.tauriVtebenchPairMedians;
	for (const shell of ["electron", "tauri"]) {
		for (const scenario of Object.keys(terminalScenarioUnits)) {
			const needsPair = shell === "tauri" && platform === "linux" && !["warm-start", "first-run", "idle-memory"].includes(scenario);
			const variants = needsPair
				? (Array.isArray(pairMedians) && pairMedians.length < 2 ? ["enabled"] : ["enabled", "disabled"])
				: [undefined];
			for (let variantIndex = 0; variantIndex < variants.length; variantIndex += 1) {
				const compositingMode = variants[variantIndex];
				let value = 7;
				if (scenario === "vtebench" && shell === "tauri") {
					value = Array.isArray(pairMedians) ? (pairMedians[variantIndex] ?? 12) : 12;
				}
				pushResult(benchmarkResultFixture({
					shell,
					scenario,
					samples: Array.from({ length: 10 }, () => value),
					warmups: 3,
					unit: terminalScenarioUnits[scenario],
					configuration: {
						...(compositingMode ? { compositingMode } : {}),
						evidenceScope: options.evidenceScope ?? "binding",
						workloadSuccess: true,
						observedWorkloads: options.observedWorkloads ?? 13,
						requiredWorkloads: options.requiredWorkloads ?? 13,
					},
				}));
				expectedMetrics[shell][scenario] = { median: value };
			}
		}
	}
	for (const shell of ["electron", "tauri"]) {
		for (const scenario of ["base-signed-download", "base-installed-footprint"]) {
			pushResult(benchmarkResultFixture({
				shell,
				scenario,
				samples: [scenario === "base-signed-download" ? 80_000_000 : 150_000_000],
				warmups: 0,
				unit: "bytes",
				configuration: artifactConfig(shell),
			}));
		}
	}
	if (options.driftOneCommit) {
		resultFiles.push((async () => {
			const drifted = benchmarkResultFixture({
				shell: "tauri",
				scenario: "vtebench",
				samples: Array.from({ length: 10 }, () => 12),
				warmups: 3,
				unit: "workloads-per-second",
				commit: "751744d15340c3d65166023f8c358f9a2438af78",
				configuration: { evidenceScope: "binding", workloadSuccess: true, observedWorkloads: 13, requiredWorkloads: 13 },
			});
			await writeFile(path.join(resultsDir, "linux-x64-tauri-vtebench-drift.json"), `${JSON.stringify(drifted, null, "\t")}\n`);
		})());
	}
	await Promise.all(resultFiles);
	if (platform === "win32") {
		const verification = options.windowsVerification ?? [{ Status: 0, StatusMessage: "Signature verified." }];
		await writeFile(path.join(resultsDir, "windows-artifact-verification.json"), `${JSON.stringify(verification, null, "\t")}\n`);
	}
	if (options.rpmEvidence !== "result-flag" && options.rpmEvidence !== "absent") {
		await writeFile(path.join(resultsDir, "rpm-signature.txt"), "/bundle/rpm/operator-0.10.3-1.x86_64.rpm: digests signatures OK\n");
	}
	await writeFile(path.join(resultsDir, "legacy-update-evidence.json"), `${JSON.stringify({
		[platform]: {
			directSuccess: true,
			success: true,
			bridgeRequired: false,
			bridgeProven: false,
			migrationObserved: true,
			exercise: {
				kind: "electron-to-tauri",
				runner: "native-installed-update",
				legacyVersion: "0.10.3",
				targetVersion: "1.0.0",
				legacyArtifactSha256: ELECTRON_ARTIFACT_SHA256,
				targetArtifactSha256: options.legacyTargetDigest ?? TAURI_ARTIFACT_SHA256,
				launchedLegacy: true,
				updateRequested: true,
				updaterExitCode: 0,
				launchedTarget: true,
				identityPreserved: true,
				statePreserved: true,
				observedAt: "2026-08-22T00:00:00.000Z",
			},
		},
	}, null, "\t")}\n`);
	const { runEphemeralSigningFlow } = await import("./phase0-updater-signing.mjs");
	const fixturePath = path.join(root, "updater-fixture.tar");
	await writeFile(fixturePath, "tauri updater fixture bytes");
	const signingTmp = path.join(root, "signing-tmp");
	await mkdir(signingTmp, { recursive: true });
	const signingEvidence = await runEphemeralSigningFlow({ tmpDir: signingTmp, fixturePath, outputDir: updaterDir });
	if (options.lieAboutSignatureSha256) {
		signingEvidence.signatureSha256 = "ff".repeat(32);
		await writeFile(path.join(updaterDir, "updater-signing-evidence.json"), `${JSON.stringify(signingEvidence, null, "\t")}\n`);
	}
	if (options.tamperRetainedFixture) {
		await writeFile(path.join(updaterDir, "fixture.tar"), "tampered updater fixture bytes");
	}
	await writeFile(path.join(root, "tauri.conf.json"), `${JSON.stringify({ identifier: "dev.operator.desktop", productName: "Operator", mainBinaryName: "operator" }, null, "\t")}\n`);
	await writeFile(path.join(root, "frontend-release.yml"), `aliases:\n${ALIASES.map((alias) => `  - ${alias}`).join("\n")}\n`);
	return {
		platform,
		sourceCommit: COMMIT,
		resultsDir,
		updaterDir,
		configPath: path.join(root, "tauri.conf.json"),
		releaseWorkflowPath: path.join(root, "frontend-release.yml"),
		expectedMetrics,
		updaterSigning: signingEvidence,
	};
}

test("cors probe targets cover the exact packaged origins and every rejection class", async () => {
	const { corsProbeTargets } = await import("./phase0-cors-probe.mjs");
	const targets = corsProbeTargets();
	const origins = targets.map((target) => target.origin);
	for (const expected of ["app://renderer", "tauri://localhost", "http://tauri.localhost"]) {
		assert.ok(origins.includes(expected), `missing packaged origin ${expected}`);
	}
	for (const rejected of ["null", "*", "https://evil.example", "http://tauri.localhost.evil.example", "https://tauri.localhost", "http://localhost:5173"]) {
		assert.ok(origins.includes(rejected), `missing rejection-class origin ${rejected}`);
	}
	const expected = new Set(["app://renderer", "tauri://localhost", "http://tauri.localhost"]);
	for (const target of targets) {
		assert.equal(target.expectGranted, expected.has(target.origin));
	}
});

test("the cors evidence producer derives the file from real loopback HTTP observations", async () => {
	const { createServer } = await import("node:http");
	const { runCorsProbe } = await import("./phase0-cors-probe.mjs");
	const allowedOrigins = new Set(["app://renderer", "tauri://localhost", "http://tauri.localhost"]);
	const server = createServer((request, response) => {
		const origin = request.headers.origin ?? "";
		response.setHeader("vary", "Origin");
		if (!allowedOrigins.has(origin)) {
			response.writeHead(403, { "content-type": "application/json" });
			response.end(JSON.stringify({ error: "forbidden", code: "ORIGIN_FORBIDDEN" }));
			return;
		}
		response.setHeader("access-control-allow-origin", origin);
		response.writeHead(200, { "content-type": "application/json" });
		response.end(JSON.stringify({ status: "ready", service: "operator-daemon" }));
	});
	await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
	try {
		const baseUrl = `http://127.0.0.1:${server.address().port}`;
		const evidence = await runCorsProbe({ baseUrl });
		assert.equal(evidence.schemaVersion, 1);
		assert.equal(evidence.passed, true);
		assert.equal(evidence.exactAllowlist, true);
		assert.deepEqual(evidence.allowlist, ["app://renderer", "tauri://localhost", "http://tauri.localhost"]);
		const tauriProbe = evidence.probes.find((probe) => probe.origin === "tauri://localhost");
		assert.equal(tauriProbe.allowed, true);
		assert.equal(tauriProbe.status, 200);
		assert.equal(tauriProbe.allowOrigin, "tauri://localhost");
		const nullProbe = evidence.probes.find((probe) => probe.origin === "null");
		assert.equal(nullProbe.allowed, false);
		assert.equal(nullProbe.status, 403);

		const starServer = createServer((request, response) => {
			response.setHeader("access-control-allow-origin", "*");
			response.writeHead(200, { "content-type": "application/json" });
			response.end("{}");
		});
		await new Promise((resolve) => starServer.listen(0, "127.0.0.1", resolve));
		try {
			await assert.rejects(
				() => runCorsProbe({ baseUrl: `http://127.0.0.1:${starServer.address().port}` }),
				/access-control-allow-origin/,
			);
		} finally {
			await new Promise((resolve) => starServer.close(resolve));
		}

		const echoServer = createServer((request, response) => {
			response.setHeader("access-control-allow-origin", request.headers.origin ?? "");
			response.writeHead(200, "application/json");
			response.end("{}");
		});
		await new Promise((resolve) => echoServer.listen(0, "127.0.0.1", resolve));
		try {
			await assert.rejects(
				() => runCorsProbe({ baseUrl: `http://127.0.0.1:${echoServer.address().port}` }),
				/are not exactly the configured allowlist/,
			);
		} finally {
			await new Promise((resolve) => echoServer.close(resolve));
		}
	} finally {
		await new Promise((resolve) => server.close(resolve));
	}
});

test("the results collector still refuses unrecognized evidence files dropped into results", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-summary-unknown-"));
	try {
		const tree = await buildValidEvidenceTree(root);
		await writeFile(path.join(tree.resultsDir, "acp-runtime-manifest.json"), `${JSON.stringify({ someDependencyManifest: true })}\n`);
		await assert.rejects(() => derivePlatformSummary(tree), /is not a recognized evidence file/);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});
