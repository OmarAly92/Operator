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
	collectGitMetadata,
	collectHostMetadata,
	createBenchmarkResult,
	parseNamedArguments,
	resolveEvidenceScope,
	sanitizedBindingEnvironment,
	writeBenchmarkResultBatch,
} from "./benchmark-result.mjs";

const execFileAsync = promisify(execFile);
const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const macVerifier = fileURLToPath(new URL("./verify-mac-artifact.sh", import.meta.url));
const releaseTrustPath = fileURLToPath(new URL("./phase0-release-trust.json", import.meta.url));
const expectedComponents = Object.freeze({ agentBrowser: "0.33.1", node: "22.23.2", acp: "0.64.2" });
const expectedRuntime = Object.freeze({ electron: "33.4.11", chromium: "130.0.6723.191" });

function optionalPackageArguments(env) {
	const packages = {};
	if (env.OPERATOR_BENCH_PACKAGE_DEB) packages.deb = env.OPERATOR_BENCH_PACKAGE_DEB;
	if (env.OPERATOR_BENCH_PACKAGE_RPM) packages.rpm = env.OPERATOR_BENCH_PACKAGE_RPM;
	return packages;
}

export function parseArtifactArguments(argv, env = process.env) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron" && namedArguments.shell !== "tauri") {
		throw new Error("artifact benchmark supports only electron and tauri shells");
	}
	if (Object.keys(namedArguments).some((key) => key !== "shell")) throw new Error("unknown artifact benchmark argument");
	if (namedArguments.shell === "tauri") {
		if (!env.OPERATOR_BENCH_SIGNED_ARTIFACT) throw new Error("OPERATOR_BENCH_SIGNED_ARTIFACT must name the native signed download artifact");
		return {
			shell: "tauri",
			signedArtifact: env.OPERATOR_BENCH_SIGNED_ARTIFACT,
			installedApp: env.OPERATOR_BENCH_INSTALLED_APP,
			packages: optionalPackageArguments(env),
			...(env.OPERATOR_BENCH_ARTIFACT_SIGNATURE ? { artifactSignature: env.OPERATOR_BENCH_ARTIFACT_SIGNATURE } : {}),
			...(env.OPERATOR_BENCH_MANAGED_BROWSER ? { managedBrowser: env.OPERATOR_BENCH_MANAGED_BROWSER } : {}),
		};
	}
	if (!env.OPERATOR_BENCH_SIGNED_ARTIFACT) throw new Error("OPERATOR_BENCH_SIGNED_ARTIFACT must name the native signed download artifact");
	if (!env.OPERATOR_BENCH_INSTALLED_APP) throw new Error("OPERATOR_BENCH_INSTALLED_APP must name the installed application");
	if (!env.OPERATOR_BENCH_RELEASE_ATTESTATION) throw new Error("OPERATOR_BENCH_RELEASE_ATTESTATION must name the publisher-signed release attestation");
	if (!env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE) throw new Error("OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE must name its detached Ed25519 signature");
	if (!env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY) throw new Error("OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY must name the trusted Ed25519 public key");
	return {
		shell: namedArguments.shell,
		signedArtifact: env.OPERATOR_BENCH_SIGNED_ARTIFACT,
		installedApp: env.OPERATOR_BENCH_INSTALLED_APP,
		attestationPath: env.OPERATOR_BENCH_RELEASE_ATTESTATION,
		signaturePath: env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE,
		publicKeyPath: env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY,
		managedBrowser: env.OPERATOR_BENCH_MANAGED_BROWSER,
		...(env.OPERATOR_BENCH_ARTIFACT_SIGNATURE ? { artifactSignature: env.OPERATOR_BENCH_ARTIFACT_SIGNATURE } : {}),
	};
}

export function validateReleaseTrust(trust) {
	if (trust?.schemaVersion !== 1 || trust?.status !== "trusted" || !/^[0-9a-f]{64}$/.test(trust?.attestationKeySha256 ?? "")) {
		throw new Error("repository-pinned release trust anchor is not configured");
	}
	const publishers = trust.publishers;
	if (!publishers || !/^[A-Z0-9]{10}$/.test(publishers.darwin?.teamId ?? "") ||
		!publishers.win32?.identity?.trim() || !/^[A-F0-9]{40,64}$/.test(publishers.win32?.thumbprint ?? "") ||
		!/^[A-F0-9]{40,64}$/.test(publishers.linux?.fingerprint ?? "")) {
		throw new Error("repository-pinned release publisher identities are not configured");
	}
	return trust;
}

export async function loadReleaseTrust(anchorPath = releaseTrustPath) {
	let trust;
	try {
		trust = JSON.parse(await readFile(anchorPath, "utf8"));
	} catch {
		throw new Error("repository-pinned release trust anchor is missing or malformed");
	}
	return validateReleaseTrust(trust);
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
	return {
		attestationBytes,
		verification: {
			publicKeySha256,
			publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
			signatureBase64: signature.toString("base64"),
		},
	};
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
	const [verified, artifactSha256] = await Promise.all([
		verifiedAttestationBytes(input),
		fileSha256(input.signedArtifact),
	]);
	const statement = parseReleaseAttestation(verified.attestationBytes);
	validateAttestationClaims(statement, { artifactSha256, ...input });
	return { statement, verification: verified.verification };
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

export function expectedPublisherForPlatform(platform, trust) {
	if (platform === "darwin") {
		const teamId = trust?.publishers?.darwin?.teamId;
		if (!/^[A-Z0-9]{10}$/.test(teamId ?? "")) throw new Error("repository-pinned macOS Team ID is unavailable");
		return { teamId };
	}
	if (platform === "win32") {
		const identity = trust?.publishers?.win32?.identity;
		const thumbprint = trust?.publishers?.win32?.thumbprint?.replaceAll(" ", "").toUpperCase();
		if (!identity?.trim()) throw new Error("repository-pinned Windows certificate subject is unavailable");
		if (!/^[A-F0-9]{40,64}$/.test(thumbprint ?? "")) throw new Error("repository-pinned Windows certificate thumbprint is unavailable");
		return { identity: identity.trim(), thumbprint };
	}
	if (platform === "linux") {
		const fingerprint = trust?.publishers?.linux?.fingerprint?.replaceAll(" ", "").toUpperCase();
		if (!/^[A-F0-9]{40,64}$/.test(fingerprint ?? "")) throw new Error("repository-pinned Linux signing-key fingerprint is unavailable");
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
			env: sanitizedBindingEnvironment(process.env, {
				OPERATOR_DATA_DIR: path.join(stateRoot, "data"),
				OPERATOR_RUN_FILE: path.join(stateRoot, "running.json"),
				OPERATOR_PORT: String(await availablePort()),
				OPERATOR_KEEP_DAEMON: "0",
			}),
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

async function findFiles(root, predicate) {
	const found = [];
	async function visit(target) {
		const metadata = await lstat(target);
		if (metadata.isSymbolicLink()) return;
		if (metadata.isFile()) {
			if (predicate(target)) found.push(target);
			return;
		}
		if (!metadata.isDirectory()) return;
		for (const entry of await readdir(target)) await visit(path.join(target, entry));
	}
	await visit(root);
	return found;
}

async function hasDirectory(target) {
	try {
		return (await lstat(target)).isDirectory();
	} catch (error) {
		if (error?.code === "ENOENT") return false;
		throw error;
	}
}

async function extractedApplicationRoot(extractionRoot, platform) {
	if (platform === "darwin") {
		const applications = (await readdir(extractionRoot)).filter((entry) => entry === "Operator.app");
		if (applications.length !== 1) throw new Error("signed macOS artifact must contain exactly one Operator.app payload");
		return path.join(extractionRoot, applications[0]);
	}
	const executableName = platform === "win32" ? "operator.exe" : "operator";
	const executables = await findFiles(extractionRoot, (target) => path.basename(target).toLowerCase() === executableName);
	const candidates = [];
	for (const executable of executables) {
		const candidate = path.dirname(executable);
		if (await hasDirectory(path.join(candidate, "resources"))) candidates.push(candidate);
	}
	const uniqueCandidates = [...new Set(candidates)];
	if (uniqueCandidates.length !== 1) throw new Error(`signed ${platform} artifact must contain exactly one Operator application payload`);
	return uniqueCandidates[0];
}

async function extractNativePayload({ platform, signedArtifact, extractionRoot }, dependencies = {}) {
	const execute = dependencies.execFile ?? execFileAsync;
	if (platform === "darwin") {
		await execute("ditto", ["-x", "-k", signedArtifact, extractionRoot]);
		return await extractedApplicationRoot(extractionRoot, platform);
	}
	if (platform === "linux") {
		await execute("unsquashfs", ["-f", "-d", extractionRoot, signedArtifact]);
		return await extractedApplicationRoot(extractionRoot, platform);
	}
	if (platform === "win32") {
		await execute("7z", ["x", "-y", `-o${extractionRoot}`, signedArtifact]);
		try {
			return await extractedApplicationRoot(extractionRoot, platform);
		} catch (initialError) {
			const nestedArchives = await findFiles(extractionRoot, (target) => target.toLowerCase().endsWith(".7z"));
			for (let index = 0; index < nestedArchives.length; index += 1) {
				await execute("7z", ["x", "-y", `-o${path.join(extractionRoot, `nested-${index}`)}`, nestedArchives[index]]);
			}
			if (nestedArchives.length === 0) throw initialError;
			return await extractedApplicationRoot(extractionRoot, platform);
		}
	}
	throw new Error(`unsupported native artifact binding platform: ${platform}`);
}

export async function verifyInstalledArtifactBinding({ platform, signedArtifact, installedApp }, dependencies = {}) {
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	const extractionRoot = await mkdtemp(path.join(parent, "electron-artifact-binding-"));
	try {
		const artifactApplication = dependencies.extractPayload
			? await dependencies.extractPayload({ platform, signedArtifact, extractionRoot })
			: await extractNativePayload({ platform, signedArtifact, extractionRoot }, dependencies);
		const [artifactDigest, installedDigest] = await Promise.all([
			treeDigest(artifactApplication),
			treeDigest(installedApp),
		]);
		if (artifactDigest !== installedDigest) throw new Error("installed tree does not match the signed artifact payload");
	} finally {
		await rm(extractionRoot, { recursive: true, force: true });
	}
}

function commonAncestor(firstPath, secondPath) {
	const firstParts = firstPath.split(path.sep);
	const secondParts = secondPath.split(path.sep);
	let shared = 0;
	while (shared < firstParts.length && shared < secondParts.length && firstParts[shared] === secondParts[shared]) shared += 1;
	return firstParts.slice(0, shared).join(path.sep) || path.sep;
}

async function discoverTauriApplicationRoot(extractionRoot, platform) {
	const executableName = platform === "win32" ? "operator.exe" : "operator";
	const acpPackages = await findFiles(extractionRoot, (target) => target.endsWith(`${path.sep}acp-runtime${path.sep}package.json`) || path.relative(extractionRoot, target).split(path.sep).slice(-2).join("/") === "acp-runtime/package.json");
	if (acpPackages.length !== 1) throw new Error(`tauri bundle must contain exactly one packaged ACP runtime, found ${acpPackages.length}`);
	const resourcesRoot = path.dirname(path.dirname(acpPackages[0]));
	const daemons = await findFiles(resourcesRoot, (target) => path.basename(target).toLowerCase() === (platform === "win32" ? "opr.exe" : "opr"));
	if (daemons.length !== 1) throw new Error("tauri bundle must contain exactly one packaged daemon binary");
	const agentBrowsers = await findFiles(resourcesRoot, (target) => path.basename(target).toLowerCase() === (platform === "win32" ? "agent-browser.exe" : "agent-browser"));
	if (agentBrowsers.length !== 1) throw new Error("tauri bundle must contain exactly one packaged agent-browser binary");
	const executables = [];
	for (const candidate of await findFiles(extractionRoot, (target) => path.basename(target).toLowerCase() === executableName)) {
		if (!pathInside(candidate, resourcesRoot)) executables.push(candidate);
	}
	if (executables.length !== 1) throw new Error(`tauri bundle must contain exactly one application executable, found ${executables.length}`);
	const executable = executables[0];
	let applicationRoot;
	if (platform === "darwin") {
		applicationRoot = path.dirname(executable);
		while (path.extname(applicationRoot) !== ".app" && applicationRoot !== extractionRoot) applicationRoot = path.dirname(applicationRoot);
		if (path.extname(applicationRoot) !== ".app") throw new Error("tauri macOS bundle must contain an .app payload");
	} else {
		applicationRoot = commonAncestor(path.dirname(executable), resourcesRoot);
	}
	return {
		resourcesRoot,
		executable,
		applicationRoot,
		daemon: daemons[0],
		agentBrowser: agentBrowsers[0],
	};
}

function tauriComponentLayout(discovered) {
	const { resourcesRoot } = discovered;
	const acpRuntimePackage = path.join(resourcesRoot, "acp-runtime", "package.json");
	return {
		executable: discovered.executable,
		daemon: discovered.daemon,
		agentBrowser: discovered.agentBrowser,
		node: path.join(resourcesRoot, "acp-runtime", "node", process.platform === "win32" ? "node.exe" : path.join("bin", "node")),
		acpAdapter: path.join(resourcesRoot, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js"),
		acpPackage: path.join(resourcesRoot, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "package.json"),
		acpRuntimePackage,
	};
}

async function extractTauriPayload({ platform, signedArtifact, extractionRoot }, dependencies = {}) {
	const execute = dependencies.execFile ?? execFileAsync;
	if (platform === "darwin") {
		await execute("ditto", ["-x", "-k", signedArtifact, extractionRoot]);
	} else if (platform === "win32") {
		await execute("7z", ["x", "-y", `-o${extractionRoot}`, signedArtifact]);
	} else if (platform === "linux") {
		await execute(signedArtifact, ["--appimage-extract"], { cwd: extractionRoot });
		extractionRoot = path.join(extractionRoot, "squashfs-root");
	} else {
		throw new Error(`unsupported tauri artifact extraction platform: ${platform}`);
	}
	return await discoverTauriApplicationRoot(extractionRoot, platform);
}

async function collectTauriRuntimeMetadata(discovered, env = {}, dependencies = {}) {
	const commandOutput = dependencies.commandOutput ?? execFileAsync;
	let versionOutput;
	try {
		const execution = await commandOutput(discovered.executable, ["--version"], { timeout: 10_000 });
		versionOutput = String(execution.stdout ?? execution).trim();
	} catch (error) {
		throw new Error(`packaged tauri binary did not report its version: ${error instanceof Error ? error.message : String(error)}`);
	}
	if (!versionOutput) throw new Error("packaged tauri binary reported an empty version");
	const displayScale = Number(env.OPERATOR_BENCH_DISPLAY_SCALE || 1);
	if (!Number.isFinite(displayScale) || displayScale <= 0) throw new Error("OPERATOR_BENCH_DISPLAY_SCALE must be a positive number when provided");
	return {
		source: "packaged-binary-probe",
		applicationVersion: requireString(versionOutput.split(/\s+/).pop(), "runtime.applicationVersion"),
		architecture: process.arch,
		webviewRuntimeVersion: requireString(versionOutput, "runtime.webviewRuntimeVersion"),
		rendererKind: "webview",
		displayScale,
	};
}

async function preflightTauriArtifactBenchmark(options, dependencies) {
	const env = dependencies.env ?? process.env;
	const platform = dependencies.platform ?? process.platform;
	const evidenceScope = resolveEvidenceScope(env);
	await lstat(options.signedArtifact).then(
		(metadata) => {
			if (!metadata.isFile() || metadata.isSymbolicLink()) throw new Error("signed release artifact must be a regular file");
		},
		(error) => {
			if (error?.code === "ENOENT") throw new Error(`signed release artifact must be a regular file: ${error.path ?? options.signedArtifact}`);
			throw error;
		},
	);
	for (const [name, packagePath] of Object.entries(options.packages ?? {})) {
		const metadata = await lstat(packagePath);
		if (!metadata.isFile() || metadata.isSymbolicLink()) throw new Error(`tauri ${name} package must be a regular file`);
	}
	if (options.installedApp) {
		const metadata = await lstat(options.installedApp);
		if (!metadata.isDirectory() || metadata.isSymbolicLink()) throw new Error("installed application must be a real directory");
	}
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	const extractionRoot = await mkdtemp(path.join(parent, "tauri-artifact-binding-"));
	let discovered;
	let attestation;
	let attestationVerification;
	let buildProfile;
	try {
		discovered = dependencies.extractPayload
			? await dependencies.extractPayload({ platform, signedArtifact: options.signedArtifact, extractionRoot })
			: await extractTauriPayload({ platform, signedArtifact: options.signedArtifact, extractionRoot }, dependencies);
		const components = await verifyPackagedComponents(tauriComponentLayout(discovered), dependencies);
		if (evidenceScope === "binding") {
			const releaseTrust = validateReleaseTrust(dependencies.trustAnchor ?? await (dependencies.loadTrustAnchor ?? loadReleaseTrust)());
			const expectedPublisher = expectedPublisherForPlatform(platform, releaseTrust);
			if (!env.OPERATOR_BENCH_RELEASE_ATTESTATION || !env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE || !env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY) {
				throw new Error("binding tauri artifact evidence requires the publisher attestation inputs");
			}
			if (platform === "linux" && !options.artifactSignature) throw new Error("binding Linux tauri evidence requires an explicit detached artifact signature");
			const observedPublisher = await (dependencies.verifySignature ?? nativeSignatureVerification)({
				signedArtifact: options.signedArtifact,
				installedApp: options.installedApp ?? discovered.applicationRoot,
				installedExecutable: discovered.executable,
				artifactSignature: options.artifactSignature,
				platform,
			});
			validatePublisherIdentity(platform, observedPublisher, expectedPublisher);
			const validatedAttestation = await (dependencies.validateAttestation ?? validateReleaseAttestation)({
				signedArtifact: options.signedArtifact,
				attestationPath: env.OPERATOR_BENCH_RELEASE_ATTESTATION,
				signaturePath: env.OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE,
				publicKeyPath: env.OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY,
				expectedKeySha256: releaseTrust.attestationKeySha256,
				applicationVersion: components.daemon.slice(4),
				architecture: process.arch,
				publisherIdentity: observedPublisherIdentity(platform, observedPublisher),
			});
			attestation = validatedAttestation.statement;
			attestationVerification = validatedAttestation.verification;
			buildProfile = "signed-release-attested";
		} else {
			buildProfile = "local-tauri-bundle-unattested-non-binding";
		}
		const renderer = await (dependencies.collectRuntimeMetadata ?? collectTauriRuntimeMetadata)(discovered, env, dependencies);
		const measured = [
			{ scenario: "base-signed-download", artifactKind: "primary-signed-update", bytes: await measurePathBytes(options.signedArtifact) },
			{ scenario: "base-installed-footprint", artifactKind: "installed-application", bytes: await measurePathBytes(options.installedApp ?? discovered.applicationRoot) },
		];
		if (options.managedBrowser) {
			measured.push({ scenario: "managed-browser-footprint", artifactKind: "post-browser-install", bytes: await measurePathBytes(options.managedBrowser) });
		}
		const packages = {};
		if (options.packages?.rpm) packages.rpmExists = true;
		if (options.packages?.deb) packages.debExists = true;
		return {
			buildProfile,
			components,
			measured,
			renderer,
			executable: discovered.executable,
			packages,
			...(attestation ? { attestation, attestationVerification } : {}),
		};
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
	if ((options.shell ?? "electron") === "tauri") return await preflightTauriArtifactBenchmark(options, dependencies);
	const platform = dependencies.platform ?? process.platform;
	assertReleaseArtifactPath(options.signedArtifact, platform);
	if (platform === "linux" && !options.artifactSignature) throw new Error("Linux release evidence requires an explicit detached artifact signature");
	const releaseTrust = validateReleaseTrust(dependencies.trustAnchor ?? await (dependencies.loadTrustAnchor ?? loadReleaseTrust)());
	const expectedPublisher = expectedPublisherForPlatform(platform, releaseTrust);
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
	const validatedAttestation = await (dependencies.validateAttestation ?? validateReleaseAttestation)({
		signedArtifact: options.signedArtifact,
		attestationPath: options.attestationPath,
		signaturePath: options.signaturePath,
		publicKeyPath: options.publicKeyPath,
		expectedKeySha256: releaseTrust.attestationKeySha256,
		applicationVersion,
		architecture,
		publisherIdentity: observedPublisherIdentity(platform, observedPublisher),
	});
	const measured = await artifactMeasurements(options);
	return {
		buildProfile: "signed-release-attested",
		components,
		measured,
		renderer,
		executable: layout.executable,
		attestation: validatedAttestation.statement,
		attestationVerification: validatedAttestation.verification,
	};
}

export async function runArtifactBenchmark(argv = process.argv.slice(2), env = process.env, dependencies = {}) {
	const options = parseArtifactArguments(argv, env);
	const shell = options.shell;
	const preflight = await (dependencies.preflightArtifactBenchmark ?? preflightArtifactBenchmark)(options, { ...dependencies, env });
	const host = { ...(dependencies.collectHostMetadata ?? collectHostMetadata)(), architecture: preflight.attestation?.architecture ?? process.arch };
	const git = preflight.attestation
		? { commit: preflight.attestation.sourceCommit, dirty: false }
		: await (dependencies.collectGitMetadata ?? collectGitMetadata)();
	const evidenceScope = shell === "electron" ? "binding" : resolveEvidenceScope(env);
	const benchmarkResults = preflight.measured.map((measurement) => createBenchmarkResult({
		shell,
		scenario: measurement.scenario,
		buildProfile: preflight.buildProfile,
		git,
		host,
		renderer: preflight.renderer,
			scenarioConfiguration: {
			artifactKind: measurement.artifactKind,
			accounting: "recursive-regular-file-bytes",
			evidenceScope,
			baseContents: Object.values(preflight.components),
			artifactIdentity: "native-signature-and-required-contents-verified",
				runtimeMetadataSource: preflight.renderer?.source === "packaged-binary-probe" ? "packaged-binary-probe" : "installed-release-launch",
				...(preflight.packages ?? {}),
				...(preflight.attestation
					? {
							releaseAttestation: {
								statement: preflight.attestation,
								verification: preflight.attestationVerification,
								source: "publisher-ed25519-signed",
							},
						}
					: {}),
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
		process.stdout.write("Electron: OPERATOR_BENCH_SIGNED_ARTIFACT=... OPERATOR_BENCH_INSTALLED_APP=... OPERATOR_BENCH_RELEASE_ATTESTATION=... OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE=... OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY=... node scripts/benchmark-artifact.mjs --shell electron\n");
		process.stdout.write("Tauri:    OPERATOR_BENCH_SIGNED_ARTIFACT=... [OPERATOR_BENCH_INSTALLED_APP=...] [OPERATOR_BENCH_PACKAGE_DEB=...] [OPERATOR_BENCH_PACKAGE_RPM=...] [OPERATOR_BENCH_DISPLAY_SCALE=...] node scripts/benchmark-artifact.mjs --shell tauri\n");
		process.stdout.write("Publisher identities and the attestation-key fingerprint come only from scripts/phase0-release-trust.json. Linux additionally requires OPERATOR_BENCH_ARTIFACT_SIGNATURE for binding evidence. Tauri binding evidence also requires the attestation inputs; without OPERATOR_BENCH_EVIDENCE_SCOPE=binding it records non-binding local measurements.\n");
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
