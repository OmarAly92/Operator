import { execFile } from "node:child_process";
import { createHash, createPublicKey, verify } from "node:crypto";
import { createReadStream } from "node:fs";
import { lstat, mkdir, mkdtemp, readFile, readdir, readlink, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { _electron as electron } from "playwright";
import {
	DEFAULT_RESULT_ROOT,
	benchmarkResultPath,
	collectHostMetadata,
	createBenchmarkResult,
	parseNamedArguments,
	writeBenchmarkResultBatch,
} from "./benchmark-result.mjs";

const execFileAsync = promisify(execFile);
const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const macVerifier = fileURLToPath(new URL("./verify-mac-artifact.sh", import.meta.url));
const expectedComponents = Object.freeze({ agentBrowser: "0.33.1", node: "22.23.2", acp: "0.64.2" });
const expectedRuntime = Object.freeze({ electron: "33.4.11", chromium: "130.0.6723.191" });

export function parseArtifactArguments(argv, env = process.env) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron") throw new Error("Task 2 supports only electron artifact measurements");
	if (Object.keys(namedArguments).some((key) => key !== "shell")) throw new Error("unknown artifact benchmark argument");
	if (!env.OPERATOR_BENCH_SIGNED_ARTIFACT) throw new Error("OPERATOR_BENCH_SIGNED_ARTIFACT must name the native signed download artifact");
	if (!env.OPERATOR_BENCH_INSTALLED_APP) throw new Error("OPERATOR_BENCH_INSTALLED_APP must name the installed application");
	if (!env.OPERATOR_BENCH_RELEASE_ATTESTATION) throw new Error("OPERATOR_BENCH_RELEASE_ATTESTATION must name the publisher-signed release attestation");
	if (!env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE) throw new Error("OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE must name its detached Ed25519 signature");
	if (!env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY) throw new Error("OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY must name the trusted Ed25519 public key");
	const expectedAttestationKeySha256 = env.OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256?.toLowerCase();
	if (!/^[0-9a-f]{64}$/.test(expectedAttestationKeySha256 ?? "")) {
		throw new Error("OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256 must contain the trusted public-key SHA-256 fingerprint");
	}
	return {
		shell: namedArguments.shell,
		signedArtifact: env.OPERATOR_BENCH_SIGNED_ARTIFACT,
		installedApp: env.OPERATOR_BENCH_INSTALLED_APP,
		attestationPath: env.OPERATOR_BENCH_RELEASE_ATTESTATION,
		signaturePath: env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE,
		publicKeyPath: env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY,
		expectedKeySha256: expectedAttestationKeySha256,
		managedBrowser: env.OPERATOR_BENCH_MANAGED_BROWSER,
		...(env.OPERATOR_BENCH_ARTIFACT_SIGNATURE ? { artifactSignature: env.OPERATOR_BENCH_ARTIFACT_SIGNATURE } : {}),
	};
}

export async function measurePathBytes(targetPath) {
	const pathMetadata = await lstat(targetPath);
	if (pathMetadata.isSymbolicLink()) return 0;
	if (pathMetadata.isFile()) return pathMetadata.size;
	if (!pathMetadata.isDirectory()) return 0;
	const entries = await readdir(targetPath);
	const sizes = await Promise.all(entries.map((entry) => measurePathBytes(path.join(targetPath, entry))));
	return sizes.reduce((total, size) => total + size, 0);
}

function requireString(value, location) {
	if (typeof value !== "string" || value.trim() === "") throw new Error(`missing verified metadata: ${location}`);
	return value;
}

async function fileSha256(targetPath) {
	const hash = createHash("sha256");
	for await (const chunk of createReadStream(targetPath)) hash.update(chunk);
	return hash.digest("hex");
}

function observedPublisherIdentity(platform, observedPublisher) {
	if (platform === "darwin") return observedPublisher?.teamId;
	if (platform === "win32") return observedPublisher?.thumbprint?.replaceAll(" ", "").toUpperCase();
	if (platform === "linux") return observedPublisher?.fingerprint?.replaceAll(" ", "").toUpperCase();
	throw new Error(`unsupported native publisher platform: ${platform}`);
}

async function verifiedAttestationBytes({ attestationPath, signaturePath, publicKeyPath, expectedKeySha256 }) {
	const [attestationBytes, signature, publicKeyBytes] = await Promise.all([
		readFile(attestationPath),
		readFile(signaturePath),
		readFile(publicKeyPath),
	]);
	const publicKey = createPublicKey(publicKeyBytes);
	if (publicKey.asymmetricKeyType !== "ed25519") throw new Error("release attestation public key must be Ed25519");
	const publicKeySha256 = createHash("sha256").update(publicKey.export({ type: "spki", format: "der" })).digest("hex");
	if (publicKeySha256 !== expectedKeySha256?.toLowerCase()) throw new Error("release attestation public key does not match the trusted fingerprint");
	if (!verify(null, attestationBytes, publicKey, signature)) throw new Error("release attestation signature is invalid");
	return attestationBytes;
}

function parseReleaseAttestation(attestationBytes) {
	let attestation;
	try {
		attestation = JSON.parse(attestationBytes);
	} catch {
		throw new Error("release attestation must contain valid JSON");
	}
	const fields = ["schemaVersion", "artifactSha256", "applicationVersion", "architecture", "sourceCommit", "publisherIdentity"];
	if (
		attestation === null ||
		typeof attestation !== "object" ||
		Array.isArray(attestation) ||
		Object.keys(attestation).length !== fields.length ||
		fields.some((field) => !Object.hasOwn(attestation, field))
	) {
		throw new Error("release attestation must contain only the required provenance fields");
	}
	if (attestation.schemaVersion !== 1) throw new Error("release attestation schemaVersion must equal 1");
	if (!/^[0-9a-f]{64}$/.test(attestation.artifactSha256 ?? "")) throw new Error("release attestation artifactSha256 must be a lowercase SHA-256 digest");
	if (!/^[0-9a-f]{40}$/.test(attestation.sourceCommit ?? "")) throw new Error("release attestation sourceCommit must be a full lowercase Git object ID");
	for (const field of ["applicationVersion", "architecture", "publisherIdentity"]) requireString(attestation[field], `attestation.${field}`);
	return attestation;
}

function validateAttestationClaims(attestation, expected) {
	const { artifactSha256, applicationVersion, architecture, publisherIdentity } = expected;
	if (attestation.artifactSha256 !== artifactSha256) throw new Error("release attestation artifact digest does not match the signed artifact");
	if (attestation.applicationVersion !== applicationVersion) throw new Error("release attestation application version does not match the installed runtime");
	if (attestation.architecture !== architecture) throw new Error("release attestation architecture does not match the installed runtime");
	if (attestation.publisherIdentity !== publisherIdentity) throw new Error("release attestation publisher identity does not match the native signature");
	return attestation;
}

export async function validateReleaseAttestation(input) {
	const [attestationBytes, artifactSha256] = await Promise.all([
		verifiedAttestationBytes(input),
		fileSha256(input.signedArtifact),
	]);
	const attestation = parseReleaseAttestation(attestationBytes);
	return validateAttestationClaims(attestation, { artifactSha256, ...input });
}

function artifactExtension(platform) {
	if (platform === "darwin") return ".zip";
	if (platform === "win32") return ".exe";
	if (platform === "linux") return ".AppImage";
	throw new Error(`unsupported native benchmark platform: ${platform}`);
}

function assertReleaseArtifactPath(targetPath, platform) {
	const extension = artifactExtension(platform);
	const basename = path.basename(targetPath);
	if (!/^operator[- ].+/i.test(basename) || !basename.endsWith(extension)) {
		throw new Error(`signed artifact must be an Operator native Electron release artifact ending in ${extension}`);
	}
}

function signingIdentity(verificationOutput) {
	return verificationOutput.match(/(?:Authority|origin)=([^\r\n]+)/)?.[1]?.trim();
}

export function expectedPublisherForPlatform(platform, env) {
	if (platform === "darwin") {
		const teamId = env.OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID;
		if (!/^[A-Z0-9]{10}$/.test(teamId ?? "")) throw new Error("OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID must contain the trusted 10-character Team ID");
		return { teamId };
	}
	if (platform === "win32") {
		const identity = env.OPERATOR_BENCH_EXPECTED_WINDOWS_PUBLISHER;
		const thumbprint = env.OPERATOR_BENCH_EXPECTED_WINDOWS_CERTIFICATE_THUMBPRINT?.replaceAll(" ", "").toUpperCase();
		if (!identity?.trim()) throw new Error("OPERATOR_BENCH_EXPECTED_WINDOWS_PUBLISHER must contain the trusted certificate subject");
		if (!/^[A-F0-9]{40,64}$/.test(thumbprint ?? "")) throw new Error("OPERATOR_BENCH_EXPECTED_WINDOWS_CERTIFICATE_THUMBPRINT must contain the trusted certificate thumbprint");
		return { identity: identity.trim(), thumbprint };
	}
	if (platform === "linux") {
		const fingerprint = env.OPERATOR_BENCH_EXPECTED_LINUX_GPG_FINGERPRINT?.replaceAll(" ", "").toUpperCase();
		if (!/^[A-F0-9]{40,64}$/.test(fingerprint ?? "")) throw new Error("OPERATOR_BENCH_EXPECTED_LINUX_GPG_FINGERPRINT must contain the trusted signing-key fingerprint");
		return { fingerprint };
	}
	throw new Error(`unsupported native publisher platform: ${platform}`);
}

export function validatePublisherIdentity(platform, observedPublisher, expectedPublisher) {
	if (platform === "darwin" && observedPublisher?.teamId === expectedPublisher.teamId) return;
	if (
		platform === "win32" &&
		observedPublisher?.identity === expectedPublisher.identity &&
		observedPublisher?.thumbprint?.toUpperCase() === expectedPublisher.thumbprint
	) return;
	if (platform === "linux" && observedPublisher?.fingerprint?.toUpperCase() === expectedPublisher.fingerprint) return;
	throw new Error(`native signature does not match the trusted ${platform === "darwin" ? "macOS Team ID" : platform === "win32" ? "Windows publisher certificate" : "Linux GPG fingerprint"}`);
}

async function nativeSignatureVerification({ signedArtifact, installedApp, installedExecutable, artifactSignature, platform }) {
	if (platform === "darwin") {
		const artifactVerification = await execFileAsync(macVerifier, [signedArtifact]);
		const installedVerification = await execFileAsync(macVerifier, [installedApp]);
		const artifactIdentity = signingIdentity(`${artifactVerification.stdout}\n${artifactVerification.stderr}`);
		const installedIdentity = signingIdentity(`${installedVerification.stdout}\n${installedVerification.stderr}`);
		if (!artifactIdentity || artifactIdentity !== installedIdentity) throw new Error("download and installed application signing identities do not match");
		const teamId = artifactIdentity.match(/\(([A-Z0-9]{10})\)$/)?.[1];
		if (!teamId) throw new Error("macOS signing identity does not expose a Team ID");
		return { identity: artifactIdentity, teamId };
	}
	if (platform === "win32") {
		let verifiedPublisher;
		for (const target of [signedArtifact, installedExecutable]) {
			const escaped = target.replaceAll("'", "''");
			const command = `$signature = Get-AuthenticodeSignature -LiteralPath '${escaped}'; if ($signature.Status -ne 'Valid') { exit 1 }; @{ identity = $signature.SignerCertificate.Subject; thumbprint = $signature.SignerCertificate.Thumbprint } | ConvertTo-Json -Compress`;
			const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command]);
			const publisher = JSON.parse(stdout);
			if (
				!publisher.identity ||
				!publisher.thumbprint ||
				(verifiedPublisher && (publisher.identity !== verifiedPublisher.identity || publisher.thumbprint !== verifiedPublisher.thumbprint))
			) {
				throw new Error("download and installed application signing identities do not match");
			}
			verifiedPublisher = publisher;
		}
		return verifiedPublisher;
	}
	if (platform === "linux") {
		const { stdout } = await execFileAsync("gpg", ["--batch", "--status-fd=1", "--verify", artifactSignature, signedArtifact]);
		const validSignature = stdout.split("\n").find((line) => line.startsWith("[GNUPG:] VALIDSIG "));
		const fingerprint = validSignature?.split(/\s+/)[2];
		if (!fingerprint) throw new Error("Linux artifact signature identity is unavailable");
		return { fingerprint };
	}
	throw new Error(`unsupported native signature verification platform: ${platform}`);
}

async function availablePort() {
	return await new Promise((resolve, reject) => {
		const server = net.createServer();
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			const address = server.address();
			if (!address || typeof address === "string") {
				server.close();
				reject(new Error("could not reserve an artifact benchmark daemon port"));
				return;
			}
			server.close((error) => error ? reject(error) : resolve(address.port));
		});
	});
}

async function collectInstalledRuntimeMetadata({ executable }) {
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	const stateRoot = await mkdtemp(path.join(parent, "electron-artifact-runtime-"));
	let application;
	try {
		application = await electron.launch({
			executablePath: executable,
			env: {
				...process.env,
				OPERATOR_DATA_DIR: path.join(stateRoot, "data"),
				OPERATOR_RUN_FILE: path.join(stateRoot, "running.json"),
				OPERATOR_PORT: String(await availablePort()),
				OPERATOR_KEEP_DAEMON: "0",
			},
			timeout: 120_000,
		});
		const page = await application.firstWindow({ timeout: 120_000 });
		const versions = await application.evaluate(({ app }) => ({
			application: app.getVersion(),
			architecture: process.arch,
			electron: process.versions.electron,
			chromium: process.versions.chrome,
		}));
		const rendererKind = await page.evaluate(() => navigator.userAgent.includes("Electron/") ? "chromium" : "");
		return {
			source: "installed-release-launch",
			applicationVersion: versions.application,
			architecture: versions.architecture,
			webviewRuntimeVersion: `Electron ${versions.electron} / Chromium ${versions.chromium}`,
			rendererKind,
			displayScale: await page.evaluate(() => window.devicePixelRatio),
		};
	} finally {
		if (application) await application.close();
		await rm(stateRoot, { recursive: true, force: true });
	}
}

function validateRuntime(runtime) {
	if (runtime?.source !== "installed-release-launch") throw new Error("runtime metadata must come from an installed release launch");
	const applicationVersion = requireString(runtime.applicationVersion, "runtime.applicationVersion");
	const architecture = requireString(runtime.architecture, "runtime.architecture");
	const webviewRuntimeVersion = requireString(runtime.webviewRuntimeVersion, "runtime.webviewRuntimeVersion");
	const expectedWebviewRuntimeVersion = `Electron ${expectedRuntime.electron} / Chromium ${expectedRuntime.chromium}`;
	if (webviewRuntimeVersion !== expectedWebviewRuntimeVersion) {
		throw new Error(`installed runtime expected Electron ${expectedRuntime.electron} and Chromium ${expectedRuntime.chromium}`);
	}
	const rendererKind = requireString(runtime.rendererKind, "runtime.rendererKind");
	if (!Number.isFinite(runtime.displayScale) || runtime.displayScale <= 0) throw new Error("runtime metadata must contain the observed positive display scale");
	return { applicationVersion, architecture, webviewRuntimeVersion, rendererKind, displayScale: runtime.displayScale };
}

async function updateTreeDigest(hash, root, target) {
	const metadata = await lstat(target);
	const relative = path.relative(root, target).split(path.sep).join("/") || ".";
	const mode = (metadata.mode & 0o7777).toString(8);
	if (metadata.isSymbolicLink()) {
		hash.update(`L\0${relative}\0${mode}\0${await readlink(target)}\0`);
		return;
	}
	if (metadata.isFile()) {
		hash.update(`F\0${relative}\0${mode}\0${metadata.size}\0`);
		hash.update(await readFile(target));
		return;
	}
	if (!metadata.isDirectory()) throw new Error(`unsupported installed artifact entry: ${relative}`);
	hash.update(`D\0${relative}\0${mode}\0`);
	const entries = (await readdir(target)).sort();
	for (const entry of entries) await updateTreeDigest(hash, root, path.join(target, entry));
}

async function treeDigest(target) {
	const hash = createHash("sha256");
	await updateTreeDigest(hash, target, target);
	return hash.digest("hex");
}

export async function verifyInstalledArtifactBinding({ platform, signedArtifact, installedApp }) {
	if (platform === "win32") throw new Error("cannot cryptographically bind the Windows installed tree to the signed installer payload");
	if (platform === "linux") throw new Error("cannot cryptographically bind the Linux installed tree to the signed AppImage payload");
	if (platform !== "darwin") throw new Error(`unsupported native artifact binding platform: ${platform}`);
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	const extractionRoot = await mkdtemp(path.join(parent, "electron-artifact-binding-"));
	try {
		await execFileAsync("ditto", ["-x", "-k", signedArtifact, extractionRoot]);
		const applications = (await readdir(extractionRoot)).filter((entry) => entry === "Operator.app");
		if (applications.length !== 1) throw new Error("signed macOS artifact must contain exactly one Operator.app payload");
		const artifactApplication = path.join(extractionRoot, applications[0]);
		const [artifactDigest, installedDigest] = await Promise.all([
			treeDigest(artifactApplication),
			treeDigest(installedApp),
		]);
		if (artifactDigest !== installedDigest) throw new Error("installed tree does not match the signed artifact payload");
	} finally {
		await rm(extractionRoot, { recursive: true, force: true });
	}
}

function installedReleaseLayout(installedApp, platform) {
	const resources = platform === "darwin" ? path.join(installedApp, "Contents", "Resources") : path.join(installedApp, "resources");
	const executable = platform === "darwin"
		? path.join(installedApp, "Contents", "MacOS", "operator")
		: path.join(installedApp, platform === "win32" ? "operator.exe" : "operator");
	const acpRoot = path.join(resources, "acp-runtime");
	const acpPackageRoot = path.join(acpRoot, "node_modules", "@agentclientprotocol", "claude-agent-acp");
	return {
		executable,
		daemon: path.join(resources, "daemon", platform === "win32" ? "opr.exe" : "opr"),
		agentBrowser: path.join(resources, "agent-browser", platform === "win32" ? "agent-browser.exe" : "agent-browser"),
		node: path.join(acpRoot, "node", platform === "win32" ? "node.exe" : path.join("bin", "node")),
		acpAdapter: path.join(acpPackageRoot, "dist", "index.js"),
		acpPackage: path.join(acpPackageRoot, "package.json"),
		acpRuntimePackage: path.join(acpRoot, "package.json"),
	};
}

async function preflightRequestedPaths(options, platform) {
	const requestedPaths = {
		signedArtifact: options.signedArtifact,
		installedApp: options.installedApp,
		...(options.managedBrowser ? { managedBrowser: options.managedBrowser } : {}),
		...(options.artifactSignature ? { artifactSignature: options.artifactSignature } : {}),
		...(options.attestationPath ? { attestationPath: options.attestationPath } : {}),
		...(options.signaturePath ? { signaturePath: options.signaturePath } : {}),
		...(options.publicKeyPath ? { publicKeyPath: options.publicKeyPath } : {}),
	};
	const requestedPathMetadata = Object.fromEntries(await Promise.all(Object.entries(requestedPaths).map(async ([name, target]) => [name, await lstat(target)])));
	if (!requestedPathMetadata.signedArtifact.isFile() || requestedPathMetadata.signedArtifact.isSymbolicLink()) throw new Error("signed release artifact must be a regular file");
	if (!requestedPathMetadata.installedApp.isDirectory() || requestedPathMetadata.installedApp.isSymbolicLink()) throw new Error("installed application must be a real directory");
	if (requestedPathMetadata.managedBrowser && (!requestedPathMetadata.managedBrowser.isDirectory() || requestedPathMetadata.managedBrowser.isSymbolicLink())) throw new Error("managed browser input must be a real directory");
	if (requestedPathMetadata.artifactSignature && (!requestedPathMetadata.artifactSignature.isFile() || requestedPathMetadata.artifactSignature.isSymbolicLink())) throw new Error("artifact signature must be a regular file");
	for (const name of ["attestationPath", "signaturePath", "publicKeyPath"]) {
		if (requestedPathMetadata[name] && (!requestedPathMetadata[name].isFile() || requestedPathMetadata[name].isSymbolicLink())) throw new Error(`${name} must be a regular file`);
	}
	if (platform === "darwin" && path.extname(options.installedApp) !== ".app") throw new Error("macOS installed application must be an Operator .app bundle");
}

async function commandStdout(commandOutput, executable, arguments_) {
	const execution = await commandOutput(executable, arguments_, { timeout: 10_000 });
	return execution.stdout.trim();
}

async function verifyPackagedComponents(layout, dependencies = {}) {
	const packagedFiles = Object.values(layout);
	const packagedFileMetadata = await Promise.all(packagedFiles.map((target) => lstat(target)));
	if (packagedFileMetadata.some((entry) => !entry.isFile() || entry.isSymbolicLink())) {
		throw new Error("installed Electron release is missing the executable, daemon, agent-browser, or ACP runtime contents");
	}
	const commandOutput = dependencies.commandOutput ?? execFileAsync;
	const [daemonVersionOutput, daemonHelp, agentBrowserVersion, nodeVersion, acpVersion] = await Promise.all([
		commandStdout(commandOutput, layout.daemon, ["version"]),
		commandStdout(commandOutput, layout.daemon, ["--help"]),
		commandStdout(commandOutput, layout.agentBrowser, ["--version"]),
		commandStdout(commandOutput, layout.node, ["--version"]),
		commandStdout(commandOutput, layout.node, [layout.acpAdapter, "--version"]),
	]);
	const daemonVersion = daemonVersionOutput.split(/\s+/)[0];
	if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(daemonVersion) || !daemonHelp.includes("Operator")) {
		throw new Error("packaged daemon must identify as Operator opr with a release semantic version instead of dev");
	}
	if (agentBrowserVersion !== `agent-browser ${expectedComponents.agentBrowser}`) throw new Error(`packaged agent-browser must report exactly agent-browser ${expectedComponents.agentBrowser}`);
	if (nodeVersion !== `v${expectedComponents.node}`) throw new Error(`packaged Node runtime must identify as v${expectedComponents.node}`);
	if (acpVersion !== expectedComponents.acp) throw new Error(`packaged ACP executable must report exactly ${expectedComponents.acp} through the packaged Node runtime`);
	const runtimePackage = JSON.parse(await (dependencies.readFile ?? readFile)(layout.acpRuntimePackage, "utf8"));
	const adapterPackage = JSON.parse(await (dependencies.readFile ?? readFile)(layout.acpPackage, "utf8"));
	if (runtimePackage.name !== "@operator-dev/acp-runtime" || runtimePackage.dependencies?.["@agentclientprotocol/claude-agent-acp"] !== expectedComponents.acp) {
		throw new Error(`packaged ACP runtime must pin @agentclientprotocol/claude-agent-acp ${expectedComponents.acp}`);
	}
	if (
		adapterPackage.name !== "@agentclientprotocol/claude-agent-acp" ||
		adapterPackage.version !== expectedComponents.acp ||
		adapterPackage.bin?.["claude-agent-acp"] !== "dist/index.js"
	) {
		throw new Error(`packaged ACP adapter executable must identify as @agentclientprotocol/claude-agent-acp ${expectedComponents.acp} at dist/index.js`);
	}
	return {
		daemon: `opr ${daemonVersion}`,
		agentBrowser: agentBrowserVersion,
		node: nodeVersion,
		acp: `${adapterPackage.name} ${adapterPackage.version}`,
	};
}

async function artifactMeasurements(options) {
	const measurements = [
		{ scenario: "base-signed-download", artifactKind: "primary-signed-update", target: options.signedArtifact },
		{ scenario: "base-installed-footprint", artifactKind: "installed-application", target: options.installedApp },
	];
	if (options.managedBrowser) measurements.push({ scenario: "managed-browser-footprint", artifactKind: "post-browser-install", target: options.managedBrowser });
	return await Promise.all(measurements.map(async (measurement) => ({ ...measurement, bytes: await measurePathBytes(measurement.target) })));
}

export async function preflightArtifactBenchmark(options, dependencies = {}) {
	const platform = dependencies.platform ?? process.platform;
	assertReleaseArtifactPath(options.signedArtifact, platform);
	if (platform === "linux" && !options.artifactSignature) throw new Error("Linux release evidence requires an explicit detached artifact signature");
	const expectedPublisher = expectedPublisherForPlatform(platform, dependencies.env ?? process.env);
	await preflightRequestedPaths(options, platform);
	const layout = installedReleaseLayout(options.installedApp, platform);
	const observedPublisher = await (dependencies.verifySignature ?? nativeSignatureVerification)({
		signedArtifact: options.signedArtifact,
		installedApp: options.installedApp,
		installedExecutable: layout.executable,
		artifactSignature: options.artifactSignature,
		platform,
	});
	validatePublisherIdentity(platform, observedPublisher, expectedPublisher);
	await (dependencies.verifyArtifactBinding ?? verifyInstalledArtifactBinding)({
		platform,
		signedArtifact: options.signedArtifact,
		installedApp: options.installedApp,
	});
	const components = await verifyPackagedComponents(layout, dependencies);
	const observedRuntime = await (dependencies.collectRuntimeMetadata ?? collectInstalledRuntimeMetadata)({
		executable: layout.executable,
	});
	const { applicationVersion, architecture, ...renderer } = validateRuntime(observedRuntime);
	if (components.daemon !== `opr ${applicationVersion}`) {
		throw new Error(`packaged daemon version ${components.daemon.slice(4)} does not match installed application version ${applicationVersion}`);
	}
	const attestation = await (dependencies.validateAttestation ?? validateReleaseAttestation)({
		signedArtifact: options.signedArtifact,
		attestationPath: options.attestationPath,
		signaturePath: options.signaturePath,
		publicKeyPath: options.publicKeyPath,
		expectedKeySha256: options.expectedKeySha256,
		applicationVersion,
		architecture,
		publisherIdentity: observedPublisherIdentity(platform, observedPublisher),
	});
	const measured = await artifactMeasurements(options);
	return { buildProfile: "signed-release-attested", components, measured, renderer, executable: layout.executable, attestation };
}

export async function runArtifactBenchmark(argv = process.argv.slice(2), env = process.env, dependencies = {}) {
	const options = parseArtifactArguments(argv, env);
	const preflight = await preflightArtifactBenchmark(options, { ...dependencies, env });
	const host = { ...(dependencies.collectHostMetadata ?? collectHostMetadata)(), architecture: preflight.attestation.architecture };
	const git = { commit: preflight.attestation.sourceCommit, dirty: false };
	const benchmarkResults = preflight.measured.map((measurement) => createBenchmarkResult({
		shell: options.shell,
		scenario: measurement.scenario,
		buildProfile: preflight.buildProfile,
		git,
		host,
		renderer: preflight.renderer,
			scenarioConfiguration: {
			artifactKind: measurement.artifactKind,
			accounting: "recursive-regular-file-bytes",
			baseContents: Object.values(preflight.components),
			artifactIdentity: "native-signature-and-required-contents-verified",
				runtimeMetadataSource: "installed-release-launch",
				releaseAttestation: {
					artifactSha256: preflight.attestation.artifactSha256,
					applicationVersion: preflight.attestation.applicationVersion,
					publisherIdentity: preflight.attestation.publisherIdentity,
					source: "publisher-ed25519-signed",
				},
		},
		warmups: 0,
		samples: [measurement.bytes],
		unit: "bytes",
	}));
	const resultRoot = dependencies.resultRoot ?? DEFAULT_RESULT_ROOT;
	const outputs = benchmarkResults.map((benchmarkResult) => path.join(resultRoot, path.basename(benchmarkResultPath({ shell: options.shell, scenario: benchmarkResult.scenario, variant: env.OPERATOR_BENCH_VARIANT }))));
	await writeBenchmarkResultBatch(
		benchmarkResults.map((benchmarkResult, index) => ({ outputPath: outputs[index], benchmarkResult })),
		{
			resultRoot,
			writeFile: dependencies.writeFile,
			rename: dependencies.rename,
			rm: dependencies.rm,
		},
	);
	for (const outputPath of outputs) process.stdout.write(`${path.relative(frontendRoot, outputPath)}\n`);
	return benchmarkResults;
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("OPERATOR_BENCH_SIGNED_ARTIFACT=... OPERATOR_BENCH_INSTALLED_APP=... OPERATOR_BENCH_RELEASE_ATTESTATION=... OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE=... OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY=... OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256=... OPERATOR_BENCH_EXPECTED_MACOS_TEAM_ID=... node scripts/benchmark-artifact.mjs --shell electron\nWindows additionally requires OPERATOR_BENCH_EXPECTED_WINDOWS_PUBLISHER and OPERATOR_BENCH_EXPECTED_WINDOWS_CERTIFICATE_THUMBPRINT; Linux requires OPERATOR_BENCH_ARTIFACT_SIGNATURE and OPERATOR_BENCH_EXPECTED_LINUX_GPG_FINGERPRINT.\n");
		return;
	}
	await runArtifactBenchmark();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
