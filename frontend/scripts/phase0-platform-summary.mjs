import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { REQUIRED_SAMPLES, validateBenchmarkResult } from "./benchmark-result.mjs";
import { crossModeCookieIsolation } from "./agent-browser-phase0.mjs";
import { validateBridgeHandoff, validateMigrationExercise } from "./phase0-legacy-update.mjs";
import { verifyFixture } from "./phase0-updater-signing.mjs";

const RESERVED_RESULT_NAMES = new Set([
	"state-audit.json",
	"cors-evidence.json",
	"browser-evidence-system.json",
	"browser-evidence-managed.json",
	"legacy-update-evidence.json",
	"windows-artifact-verification.json",
	"phase0-evidence.json",
]);
const SHELLS = Object.freeze(["electron", "tauri"]);
const BROWSER_MODES = Object.freeze(["system", "managed"]);
const COMPOSITING_MODES = Object.freeze(["enabled", "disabled"]);
const THROUGHPUT_SCENARIOS = Object.freeze(new Set(["vtebench", "large-output"]));
const TERMINAL_METRICS = Object.freeze({
	"warm-start": { metric: "warmStart", fields: ["median", "p95"] },
	"first-run": { metric: "firstRun", fields: ["median", "p95"] },
	"terminal-open": { metric: "terminalOpen", fields: ["median", "p95"] },
	vtebench: { metric: "vtebench", fields: ["median"] },
	"large-output": { metric: "largeOutput", fields: ["median"] },
	"idle-memory": { metric: "idleMemory", fields: ["median"], valueField: "median" },
	"active-memory": { metric: "activeMemory", fields: ["bytes"], valueField: "median" },
	"input-latency": { metric: "inputLatency", fields: ["p95"], valueField: "p95" },
	reconnect: { metric: "reconnect", fields: ["p95"], valueField: "p95" },
	"cpu-time": { metric: "cpuTime", fields: ["ms"], valueField: "median" },
});
const REQUIRED_ALIAS_LITERALS = Object.freeze([
	"operator-darwin-arm64.zip",
	"operator-darwin-x64.zip",
	"operator-win32-x64.exe",
	"operator-linux-x64.AppImage",
]);

function sha256Bytes(bytes) {
	return createHash("sha256").update(bytes).digest("hex");
}

function isRecord(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function finiteNonNegative(value) {
	return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

class SummaryRefusal extends Error {
	constructor(missing) {
		super(`platform summary refused; missing or invalid raw evidence: ${missing.join("; ")}`);
		this.name = "SummaryRefusal";
	}
}

function refuse(collector, message) {
	collector.push(message);
}

async function readJsonInput(resultsDir, name, consumed, collector) {
	const filePath = path.join(resultsDir, name);
	let raw;
	try {
		raw = await readFile(filePath);
	} catch {
		refuse(collector, `${name} is missing`);
		return undefined;
	}
	consumed.push({ file: name, sha256: sha256Bytes(raw), bytes: raw.byteLength });
	try {
		return JSON.parse(raw.toString("utf8"));
	} catch {
		refuse(collector, `${name} contains invalid JSON`);
		return undefined;
	}
}

function validateStateAudit(stateAudit, platform, collector) {
	if (!isRecord(stateAudit)) return;
	const checks = [
		[stateAudit.platform === platform, "state audit platform disagrees"],
		[stateAudit.passed === true, "state audit did not pass"],
		[stateAudit.leaked === false, "state audit observed a leak"],
		[Number.isInteger(stateAudit.scannedRoots) && stateAudit.scannedRoots >= 1, "state audit scanned-root count is invalid"],
		[stateAudit.observedOutsideRoot === 0, "state audit observed writes outside the root"],
		[finiteNonNegative(stateAudit.shutdownChanges), "state audit shutdown change count is invalid"],
		[finiteNonNegative(stateAudit.crashChanges), "state audit crash change count is invalid"],
	];
	for (const [ok, message] of checks) {
		if (!ok) refuse(collector, `state-audit.json ${message}`);
	}
}

function validateWindowsAuthenticodeVerification(verification, collector) {
	const entries = Array.isArray(verification) ? verification : [verification];
	if (entries.length === 0 || entries.some((entry) => !isRecord(entry))) {
		refuse(collector, "windows-artifact-verification.json carries no Authenticode signature observations");
		return;
	}
	const validStatus = (status) => status === 0 || status === "Valid";
	for (const entry of entries) {
		if (!validStatus(entry.Status)) {
			refuse(collector, `windows-artifact-verification.json observed a non-Valid Authenticode status: ${JSON.stringify(entry.Status ?? null)}`);
		}
	}
}

function validateCorsEvidence(cors, collector) {
	if (!isRecord(cors)) return;
	if (cors.schemaVersion !== 1 || cors.passed !== true || cors.exactAllowlist !== true) {
		refuse(collector, "cors-evidence.json did not pass with an exact allowlist");
		return;
	}
	if (!Array.isArray(cors.allowlist) || cors.allowlist.some((origin) => typeof origin !== "string")) {
		refuse(collector, "cors-evidence.json allowlist is malformed");
		return;
	}
	if (!Array.isArray(cors.probes) || cors.probes.some((probe) => !isRecord(probe) || typeof probe.origin !== "string" || typeof probe.allowed !== "boolean")) {
		refuse(collector, "cors-evidence.json probes are malformed");
		return;
	}
	for (const origin of cors.allowlist) {
		if (!cors.probes.some((probe) => probe.origin === origin && probe.allowed === true)) {
			refuse(collector, `cors-evidence.json never proved the allowed origin ${origin}`);
		}
	}
	for (const probe of cors.probes) {
		const expected = cors.allowlist.includes(probe.origin);
		if (probe.allowed !== expected) {
			refuse(collector, `cors-evidence.json probe for ${probe.origin} disagrees with the allowlist`);
		}
	}
	if (!cors.probes.some((probe) => probe.allowed === false)) {
		refuse(collector, "cors-evidence.json never probed a rejected origin");
	}
}

function validateBrowserEvidence(modeEvidence, mode, platform, collector) {
	if (!isRecord(modeEvidence)) {
		refuse(collector, `browser-evidence-${mode}.json is missing or malformed`);
		return;
	}
	const shapeValid = modeEvidence.mode === mode &&
		modeEvidence.passed === true &&
		modeEvidence.isolatedWhileRunning === true &&
		modeEvidence.cleanupPassed === true &&
		modeEvidence.stateRootRemoved === true &&
		Number.isInteger(modeEvidence.observedProcessCount) &&
		modeEvidence.observedProcessCount >= 1 &&
		isRecord(modeEvidence.cookies) &&
		Array.isArray(modeEvidence.cookies.observedNames) &&
		modeEvidence.cookies.markerPresent === true &&
		modeEvidence.cookies.observedNames.includes(`phase0_${mode}_marker`);
	if (!shapeValid) {
		refuse(collector, `browser-evidence-${mode}.json does not prove isolation cleanup and cookie distinctness on ${platform}`);
	}
}

const COMPOSITING_PAIR_SCENARIOS = Object.freeze(new Set([
	"terminal-open",
	"vtebench",
	"large-output",
	"input-latency",
	"reconnect",
	"cpu-time",
	"active-memory",
]));

function validateBenchmarkResultEntry(result, sourceCommit, collector) {
	const cfg = result.scenarioConfiguration ?? {};
	if (result.commit !== sourceCommit) {
		refuse(collector, `benchmark result ${result.shell}/${result.scenario} commit disagrees with the workflow commit`);
	}
	if (cfg.evidenceScope !== "binding") {
		refuse(collector, `benchmark result ${result.shell}/${result.scenario} is not binding evidence`);
	}
	const requiredSamples = REQUIRED_SAMPLES[result.scenario] ?? 1;
	if (result.sampleCount < requiredSamples) {
		refuse(collector, `benchmark result ${result.shell}/${result.scenario} has ${result.sampleCount} samples but requires ${requiredSamples}`);
	}
	if (Number.isInteger(cfg.requiredWorkloads) && cfg.requiredWorkloads > 0) {
		if (cfg.observedWorkloads !== cfg.requiredWorkloads) {
			refuse(collector, `benchmark result ${result.shell}/${result.scenario} observed ${cfg.observedWorkloads} of ${cfg.requiredWorkloads} workloads`);
		} else if (cfg.workloadSuccess !== true) {
			refuse(collector, `benchmark result ${result.shell}/${result.scenario} did not observe successful workloads`);
		}
	}
}

async function collectBenchmarkResults(resultsDir, sourceCommit, consumed, collector) {
	const entries = await readdir(resultsDir);
	const results = [];
	const reserved = new Set([...RESERVED_RESULT_NAMES]);
	for (const entry of entries.filter((name) => name.startsWith("phase0-platform-"))) reserved.add(entry.name ?? entry);
	for (const entry of entries) {
		const name = typeof entry === "string" ? entry : entry.name;
		if (!name.endsWith(".json") || reserved.has(name)) continue;
		const raw = await readFile(path.join(resultsDir, name));
		let parsed;
		try {
			parsed = JSON.parse(raw.toString("utf8"));
		} catch {
			refuse(collector, `${name} is not a recognized evidence file and contains invalid JSON`);
			continue;
		}
		if (!isRecord(parsed) || typeof parsed.shell !== "string" || typeof parsed.scenario !== "string") {
			refuse(collector, `${name} is not a recognized evidence file in the results directory`);
			continue;
		}
		try {
			validateBenchmarkResult(parsed);
		} catch (error) {
			refuse(collector, `${name} failed benchmark result validation: ${error.message}`);
			continue;
		}
		consumed.push({ file: name, sha256: sha256Bytes(raw), bytes: raw.byteLength });
		validateBenchmarkResultEntry(parsed, sourceCommit, collector);
		results.push(parsed);
	}
	return results;
}

function metricValues(result, mapping) {
	const values = {};
	for (const field of mapping.fields) {
		values[field] = mapping.valueField ? result[mapping.valueField] : result[field];
	}
	return values;
}

function worseOf(left, right, scenario) {
	const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
	const combined = {};
	for (const key of keys) {
		const first = left[key];
		const second = right[key];
		if (typeof first !== "number" || typeof second !== "number") return undefined;
		combined[key] = THROUGHPUT_SCENARIOS.has(scenario) ? Math.min(first, second) : Math.max(first, second);
	}
	return combined;
}

function deriveTerminalProfiles(results, platform, collector) {
	const profiles = {};
	for (const shell of SHELLS) {
		const grouped = new Map();
		for (const result of results.filter((entry) => entry.shell === shell && TERMINAL_METRICS[entry.scenario])) {
			const compositingMode = result.scenarioConfiguration?.compositingMode;
			if (compositingMode !== undefined && !(platform === "linux" && shell === "tauri" && COMPOSITING_MODES.includes(compositingMode))) {
				refuse(collector, `benchmark result ${shell}/${result.scenario} carries an out-of-place compositing variant`);
				continue;
			}
			const key = `${result.scenario}`;
			grouped.set(key, grouped.get(key) ?? new Map());
			const variants = grouped.get(key);
			const variantKey = compositingMode ?? "single";
			if (variants.has(variantKey)) {
				refuse(collector, `duplicate benchmark results for ${shell}/${result.scenario}${compositingMode ? `/${compositingMode}` : ""}`);
				continue;
			}
			variants.set(variantKey, result);
		}
		const profile = { electron: undefined, tauri: undefined, rendererKind: "" };
		const profileMetrics = {};
		for (const [scenario, variants] of grouped) {
			const mapping = TERMINAL_METRICS[scenario];
			let selected;
			const needsPair = platform === "linux" && shell === "tauri" && COMPOSITING_PAIR_SCENARIOS.has(scenario);
			if (needsPair) {
				if (!variants.has("enabled") || !variants.has("disabled")) {
					refuse(collector, `benchmark scenario ${shell}/${scenario} is missing its linux WEBKIT_DISABLE_COMPOSITING_MODE pair`);
					continue;
				}
				selected = worseOf(metricValues(variants.get("enabled"), mapping), metricValues(variants.get("disabled"), mapping), scenario);
				if (!selected) {
					refuse(collector, `benchmark scenario ${shell}/${scenario} compositing pair could not be combined`);
					continue;
				}
			} else if (variants.size !== 1) {
				refuse(collector, `benchmark scenario ${shell}/${scenario} must appear exactly once outside the linux tauri compositing pair`);
				continue;
			} else {
				selected = metricValues([...variants.values()][0], mapping);
			}
			const representative = [...variants.values()][0];
			const cfg = representative.scenarioConfiguration ?? {};
			profileMetrics[mapping.metric] = {
				...selected,
				evidenceScope: "binding",
				workloadSuccess: cfg.workloadSuccess === true,
				observedCount: Number.isInteger(cfg.observedWorkloads) ? cfg.observedWorkloads : representative.sampleCount,
				requiredCount: Number.isInteger(cfg.requiredWorkloads) ? cfg.requiredWorkloads : REQUIRED_SAMPLES[representative.scenario] ?? representative.sampleCount,
			};
			if ((profile.rendererKind === "" || mapping.metric === "vtebench") && ["webgl", "canvas"].includes(representative.rendererKind)) {
				profile.rendererKind = representative.rendererKind;
			}
		}
		Object.assign(profile, profileMetrics);
		profiles[shell] = profile;
	}
	for (const shell of SHELLS) {
		for (const [scenario, mapping] of Object.entries(TERMINAL_METRICS)) {
			const profile = profiles[shell];
			if (profile && profile[mapping.metric] === undefined) {
				refuse(collector, `no binding benchmark result produced terminal metric ${shell}.${mapping.metric} (${scenario})`);
			}
		}
		if (profiles[shell]) {
			delete profiles[shell].electron;
			delete profiles[shell].tauri;
		}
	}
	if (platform === "linux") {
		profiles.tauri.compositingPairObserved = true;
	}
	return profiles;
}

function validateAttestationStatement(statement, collector, label) {
	if (!isRecord(statement) || !/^[0-9a-f]{64}$/.test(statement?.artifactSha256 ?? "")) {
		refuse(collector, `${label} release attestation statement has no usable artifact digest`);
		return false;
	}
	return true;
}

async function deriveArtifactSection(results, platform, resultsDir, consumed, collector) {
	const section = {};
	for (const shell of SHELLS) {
		const download = results.find((entry) => entry.shell === shell && entry.scenario === "base-signed-download");
		const installed = results.find((entry) => entry.shell === shell && entry.scenario === "base-installed-footprint");
		if (!download || !installed) {
			refuse(collector, `no binding artifact measurement results for the ${shell} base download and installed footprint`);
			continue;
		}
		const statement = download.scenarioConfiguration?.releaseAttestation?.statement;
		if (!validateAttestationStatement(statement, collector, shell)) continue;
		const contents = installed.scenarioConfiguration?.baseContents;
		if (!Array.isArray(contents)) {
			refuse(collector, `${shell} installed-footprint result carries no packaged component list`);
			continue;
		}
		section[shell] = {
			downloadBytes: download.samples[0],
			installedBytes: installed.samples[0],
			sha256: statement.artifactSha256,
		};
		if (shell === "tauri") {
			section.includesACP = contents.some((component) => typeof component === "string" && component.startsWith("@agentclientprotocol/"));
			section.includesDaemon = contents.some((component) => typeof component === "string" && component.startsWith("opr "));
			section.includesBrowser = contents.some((component) => typeof component === "string" && component.startsWith("agent-browser "));
			if (platform === "linux") {
				const rpmObservedByRunner = installed.scenarioConfiguration?.rpmExists === true;
				section.rpmExists = rpmObservedByRunner || (await checkRpmSignatures(resultsDir, consumed, collector));
			}
		}
	}
	return section;
}

async function checkRpmSignatures(resultsDir, consumed, collector) {
	const filePath = path.join(resultsDir, "rpm-signature.txt");
	let raw;
	try {
		raw = await readFile(filePath, "utf8");
	} catch {
		refuse(collector, "rpm-signature.txt is missing so the linux RPM target is unproven");
		return false;
	}
	consumed.push({ file: "rpm-signature.txt", sha256: sha256Bytes(Buffer.from(raw, "utf8")), bytes: Buffer.byteLength(raw, "utf8") });
	const rpmLines = raw.split("\n").filter((line) => line.includes(".rpm"));
	if (rpmLines.length === 0) {
		refuse(collector, "rpm-signature.txt lists no checked RPM artifacts");
		return false;
	}
	return rpmLines.every((line) => /signatures[ \t]+OK/i.test(line) || /digests[ \t]+OK/i.test(line));
}

function deriveLegacyUpdate(legacyEvidence, artifactSection, collector) {
	if (!isRecord(legacyEvidence)) return undefined;
	const record = legacyEvidence;
	let derived;
	try {
		if (record.success === true) {
			validateMigrationExercise(record.exercise);
			const directDigestsBound =
				record.exercise.legacyArtifactSha256 === artifactSection?.electron?.sha256 &&
				record.exercise.targetArtifactSha256 === artifactSection?.tauri?.sha256;
			if (!directDigestsBound) {
				refuse(collector, "migration exercise target artifact digest does not match the derived Tauri artifact digest");
			}
			derived = {
				success: true,
				bridgeRequired: false,
				bridgeProven: false,
				migrationObserved: true,
				exercise: record.exercise,
			};
		} else if (record.bridgeRequired === true && record.bridgeProven === true && isRecord(record.handoff)) {
			validateBridgeHandoff(record.handoff);
			if (record.handoff.targetArtifactSha256 !== artifactSection?.tauri?.sha256) {
				refuse(collector, "bridge handoff target artifact digest does not match the derived Tauri artifact digest");
			}
			derived = {
				success: false,
				bridgeRequired: true,
				bridgeProven: true,
				handoff: record.handoff,
			};
		} else {
			refuse(collector, "legacy update evidence proves neither direct migration nor a signed bridge handoff");
		}
	} catch (error) {
		refuse(collector, `legacy update evidence is invalid: ${error.message}`);
	}
	return derived;
}

async function deriveUpdaterSigning(updaterDir, consumed, collector) {
	const names = ["updater-signing-evidence.json", "public.key", "fixture.sig", "fixture.tar"];
	const files = {};
	for (const name of names) {
		try {
			files[name] = await readFile(path.join(updaterDir, name));
		} catch {
			refuse(collector, `retained updater material ${name} is missing`);
			return undefined;
		}
		consumed.push({ file: `updater-signing/${name}`, sha256: sha256Bytes(files[name]), bytes: files[name].byteLength });
	}
	let evidence;
	try {
		evidence = JSON.parse(files["updater-signing-evidence.json"].toString("utf8"));
	} catch {
		refuse(collector, "retained updater-signing-evidence.json contains invalid JSON");
		return undefined;
	}
	const shapeValid = isRecord(evidence) &&
		evidence.valid === true &&
		evidence.signatureValid === true &&
		evidence.privateKeyLeaked === false &&
		evidence.format === "tauri-minisign" &&
		evidence.signer === "@tauri-apps/cli@2.11.4";
	if (!shapeValid) {
		refuse(collector, "retained updater signing evidence is not a valid Tauri minisign record");
		return undefined;
	}
	try {
		await verifyFixture({
			fixturePath: path.join(updaterDir, "fixture.tar"),
			signaturePath: path.join(updaterDir, "fixture.sig"),
			publicKeyPath: path.join(updaterDir, "public.key"),
		});
	} catch {
		refuse(collector, "retained updater signature does not verify against the retained fixture bytes");
		return undefined;
	}
	const recomputedSignatureSha256 = sha256Bytes(files["fixture.sig"]);
	if (evidence.signatureSha256 !== recomputedSignatureSha256) {
		refuse(collector, "retained updater evidence signatureSha256 does not match the retained signature bytes");
		return undefined;
	}
	const recomputedFingerprint = sha256Bytes(files["public.key"]);
	if (evidence.publicKeyFingerprint !== recomputedFingerprint) {
		refuse(collector, "retained updater evidence publicKeyFingerprint does not match the retained public key bytes");
		return undefined;
	}
	return evidence;
}

async function deriveIdentity(configPath, releaseWorkflowPath, consumed, collector) {
	let configRaw;
	try {
		configRaw = await readFile(configPath, "utf8");
		consumed.push({ file: path.basename(configPath), sha256: sha256Bytes(Buffer.from(configRaw, "utf8")), bytes: Buffer.byteLength(configRaw, "utf8") });
	} catch {
		refuse(collector, "src-tauri config is missing so application identity cannot be derived");
		return undefined;
	}
	let config;
	try {
		config = JSON.parse(configRaw);
	} catch {
		refuse(collector, "src-tauri config contains invalid JSON");
		return undefined;
	}
	let workflowRaw = "";
	try {
		workflowRaw = await readFile(releaseWorkflowPath, "utf8");
		consumed.push({ file: path.basename(releaseWorkflowPath), sha256: sha256Bytes(Buffer.from(workflowRaw, "utf8")), bytes: Buffer.byteLength(workflowRaw, "utf8") });
	} catch {
		refuse(collector, "release workflow is missing so version-free alias preservation cannot be derived");
	}
	return {
		identifier: config.identifier,
		productName: config.productName,
		executable: config.mainBinaryName,
		aliasesPreserved: REQUIRED_ALIAS_LITERALS.every((alias) => workflowRaw.includes(alias)),
	};
}

const DEFAULT_UPDATER_DIRNAME = "updater-signing";

export async function derivePlatformSummary(options) {
	const { platform, sourceCommit, resultsDir, configPath, releaseWorkflowPath } = options;
	const updaterDir = options.updaterDir ?? path.join(resultsDir, DEFAULT_UPDATER_DIRNAME);
	const collector = [];
	const consumed = [];
	if (!SHELLS.every(() => true) || !["darwin", "win32", "linux"].includes(platform)) {
		throw new Error(`unsupported summary platform: ${String(platform)}`);
	}
	if (!/^[0-9a-f]{40}$/.test(sourceCommit ?? "")) {
		throw new Error("summary source commit must be a full Git object ID");
	}
	const stateAudit = await readJsonInput(resultsDir, "state-audit.json", consumed, collector);
	if (stateAudit) validateStateAudit(stateAudit, platform, collector);
	const windowsVerificationPath = path.join(resultsDir, "windows-artifact-verification.json");
	const windowsVerificationPresent = await readFile(windowsVerificationPath).then(
		(bytes) => {
			consumed.push({ file: "windows-artifact-verification.json", sha256: sha256Bytes(bytes), bytes: bytes.byteLength });
			return true;
		},
		(error) => {
			if (error?.code !== "ENOENT") throw error;
			return false;
		},
	);
	if (windowsVerificationPresent) {
		const verification = await readJsonInput(resultsDir, "windows-artifact-verification.json", [], collector);
		validateWindowsAuthenticodeVerification(verification, collector);
	} else if (platform === "win32") {
		refuse(collector, "windows-artifact-verification.json is required on win32 summaries");
	}
	const cors = await readJsonInput(resultsDir, "cors-evidence.json", consumed, collector);
	if (cors) validateCorsEvidence(cors, collector);
	const browserByMode = {};
	for (const mode of BROWSER_MODES) {
		const modeEvidence = await readJsonInput(resultsDir, `browser-evidence-${mode}.json`, consumed, collector);
		validateBrowserEvidence(modeEvidence, mode, platform, collector);
		browserByMode[mode] = modeEvidence;
	}
	const browserSection = {
		system: browserByMode.system ? {
			passed: browserByMode.system.passed,
			isolatedWhileRunning: browserByMode.system.isolatedWhileRunning,
			cleanupPassed: browserByMode.system.cleanupPassed,
			stateRootRemoved: browserByMode.system.stateRootRemoved,
			observedProcessCount: browserByMode.system.observedProcessCount,
			cookieMarkerPresent: browserByMode.system.cookies?.markerPresent === true,
		} : undefined,
		managed: browserByMode.managed ? {
			passed: browserByMode.managed.passed,
			isolatedWhileRunning: browserByMode.managed.isolatedWhileRunning,
			cleanupPassed: browserByMode.managed.cleanupPassed,
			stateRootRemoved: browserByMode.managed.stateRootRemoved,
			observedProcessCount: browserByMode.managed.observedProcessCount,
			cookieMarkerPresent: browserByMode.managed.cookies?.markerPresent === true,
		} : undefined,
	};
	const bothModesPresent = Boolean(browserSection.system && browserSection.managed);
	if (bothModesPresent) {
		browserSection.crossModeCookieIsolation = crossModeCookieIsolation(browserByMode);
		if (browserSection.crossModeCookieIsolation !== true) {
			refuse(collector, "browser probe evidence shows cookies crossing between concurrently active modes");
		}
	}
	const legacyRaw = await readJsonInput(resultsDir, "legacy-update-evidence.json", consumed, collector);
	const benchmarkResults = await collectBenchmarkResults(resultsDir, sourceCommit, consumed, collector);
	const terminal = deriveTerminalProfiles(benchmarkResults, platform, collector);
	const artifact = await deriveArtifactSection(benchmarkResults, platform, resultsDir, consumed, collector);
	const legacyUpdate = legacyRaw && isRecord(legacyRaw[platform])
		? deriveLegacyUpdate(legacyRaw[platform], artifact, collector)
		: undefined;
	if (!legacyUpdate) refuse(collector, "legacy-update-evidence.json carries no migration record for this platform");
	const updaterSigning = await deriveUpdaterSigning(updaterDir, consumed, collector);
	const identity = await deriveIdentity(configPath, releaseWorkflowPath, consumed, collector);
	if (collector.length > 0) throw new SummaryRefusal(collector);
	return {
		schemaVersion: 1,
		platform,
		sourceCommit,
		generatedAt: new Date().toISOString(),
		identity,
		updaterSigning,
		evidence: {
			stateAudit,
			cors,
			browser: browserSection,
			artifact,
			legacyUpdate,
			updaterSigning,
			terminal,
		},
		inputs: consumed.map(({ file, sha256, bytes }) => ({ file, sha256, bytes })),
	};
}

export async function writePlatformSummary(options) {
	const summary = await derivePlatformSummary(options);
	const outputPath = options.outputPath ?? path.join(options.resultsDir, `phase0-platform-${options.platform}.json`);
	const bytes = Buffer.from(`${JSON.stringify(summary, null, "\t")}\n`, "utf8");
	await writeFile(outputPath, bytes);
	return outputPath;
}

function parseArgs(argv) {
	const args = {};
	for (let index = 0; index < argv.length; index += 2) {
		const flag = argv[index];
		const value = argv[index + 1];
		if (!flag?.startsWith("--") || value === undefined) throw new Error(`invalid argument: ${flag ?? ""}`);
		args[flag.slice(2)] = value;
	}
	return args;
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("node scripts/phase0-platform-summary.mjs --platform darwin|win32|linux --commit <sha> --results <dir> --updater-dir <dir> --config <tauri.conf.json> --release-workflow <yml> [--output <file>]\n");
		return;
	}
	const args = parseArgs(process.argv.slice(2));
	const outputPath = await writePlatformSummary({
		platform: args.platform,
		sourceCommit: args.commit,
		resultsDir: path.resolve(args.results),
		updaterDir: args["updater-dir"] ? path.resolve(args["updater-dir"]) : undefined,
		configPath: path.resolve(args.config),
		releaseWorkflowPath: path.resolve(args["release-workflow"]),
		outputPath: args.output ? path.resolve(args.output) : undefined,
	});
	process.stdout.write(`${outputPath}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
