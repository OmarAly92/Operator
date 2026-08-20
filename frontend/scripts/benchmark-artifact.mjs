import { execFile } from "node:child_process";
import { lstat, mkdir, mkdtemp, readdir, rm } from "node:fs/promises";
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
	writeBenchmarkResult,
} from "./benchmark-result.mjs";

const execFileAsync = promisify(execFile);
const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const macVerifier = fileURLToPath(new URL("./verify-mac-artifact.sh", import.meta.url));

export function parseArtifactArguments(argv, env = process.env) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron") throw new Error("Task 2 supports only electron artifact measurements");
	if (Object.keys(namedArguments).some((key) => key !== "shell")) throw new Error("unknown artifact benchmark argument");
	if (!env.OPERATOR_BENCH_SIGNED_ARTIFACT) throw new Error("OPERATOR_BENCH_SIGNED_ARTIFACT must name the native signed download artifact");
	if (!env.OPERATOR_BENCH_INSTALLED_APP) throw new Error("OPERATOR_BENCH_INSTALLED_APP must name the installed application");
	return {
		shell: namedArguments.shell,
		signedArtifact: env.OPERATOR_BENCH_SIGNED_ARTIFACT,
		installedApp: env.OPERATOR_BENCH_INSTALLED_APP,
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

async function nativeSignatureVerification({ signedArtifact, installedApp, installedExecutable, artifactSignature, platform }) {
	if (platform === "darwin") {
		const artifactVerification = await execFileAsync(macVerifier, [signedArtifact]);
		const installedVerification = await execFileAsync(macVerifier, [installedApp]);
		const artifactIdentity = signingIdentity(`${artifactVerification.stdout}\n${artifactVerification.stderr}`);
		const installedIdentity = signingIdentity(`${installedVerification.stdout}\n${installedVerification.stderr}`);
		if (!artifactIdentity || artifactIdentity !== installedIdentity) throw new Error("download and installed application signing identities do not match");
		return artifactIdentity;
	}
	if (platform === "win32") {
		let verifiedIdentity;
		for (const target of [signedArtifact, installedExecutable]) {
			const escaped = target.replaceAll("'", "''");
			const command = `$signature = Get-AuthenticodeSignature -LiteralPath '${escaped}'; if ($signature.Status -ne 'Valid') { exit 1 }; $signature.SignerCertificate.Subject`;
			const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command]);
			const identity = stdout.trim();
			if (!identity || (verifiedIdentity && identity !== verifiedIdentity)) throw new Error("download and installed application signing identities do not match");
			verifiedIdentity = identity;
		}
		return verifiedIdentity;
	}
	if (platform === "linux") {
		const { stdout } = await execFileAsync("gpg", ["--batch", "--status-fd=1", "--verify", artifactSignature, signedArtifact]);
		const validSignature = stdout.split("\n").find((line) => line.startsWith("[GNUPG:] VALIDSIG "));
		const identity = validSignature?.split(/\s+/)[2];
		if (!identity) throw new Error("Linux artifact signature identity is unavailable");
		return identity;
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
		const versions = await application.evaluate(() => ({ electron: process.versions.electron, chromium: process.versions.chrome }));
		const rendererKind = await page.evaluate(() => navigator.userAgent.includes("Electron/") ? "chromium" : "");
		return {
			source: "installed-release-launch",
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
	const webviewRuntimeVersion = requireString(runtime.webviewRuntimeVersion, "runtime.webviewRuntimeVersion");
	if (!/^Electron \S+ \/ Chromium \S+$/.test(webviewRuntimeVersion)) throw new Error("runtime metadata must identify Electron and Chromium from the installed release launch");
	const rendererKind = requireString(runtime.rendererKind, "runtime.rendererKind");
	if (!Number.isFinite(runtime.displayScale) || runtime.displayScale <= 0) throw new Error("runtime metadata must contain the observed positive display scale");
	return { webviewRuntimeVersion, rendererKind, displayScale: runtime.displayScale };
}

function installedReleaseLayout(installedApp, platform) {
	const resources = platform === "darwin" ? path.join(installedApp, "Contents", "Resources") : path.join(installedApp, "resources");
	const executable = platform === "darwin"
		? path.join(installedApp, "Contents", "MacOS", "operator")
		: path.join(installedApp, platform === "win32" ? "operator.exe" : "operator");
	return {
		executable,
		requiredFiles: [
			path.join(resources, "daemon", platform === "win32" ? "opr.exe" : "opr"),
			path.join(resources, "agent-browser", platform === "win32" ? "agent-browser.exe" : "agent-browser"),
			path.join(resources, "acp-runtime", "node", platform === "win32" ? "node.exe" : path.join("bin", "node")),
			path.join(resources, "acp-runtime", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js"),
		],
	};
}

async function preflightRequestedPaths(options, platform) {
	const requestedPaths = {
		signedArtifact: options.signedArtifact,
		installedApp: options.installedApp,
		...(options.managedBrowser ? { managedBrowser: options.managedBrowser } : {}),
		...(options.artifactSignature ? { artifactSignature: options.artifactSignature } : {}),
	};
	const requestedPathMetadata = Object.fromEntries(await Promise.all(Object.entries(requestedPaths).map(async ([name, target]) => [name, await lstat(target)])));
	if (!requestedPathMetadata.signedArtifact.isFile() || requestedPathMetadata.signedArtifact.isSymbolicLink()) throw new Error("signed release artifact must be a regular file");
	if (!requestedPathMetadata.installedApp.isDirectory() || requestedPathMetadata.installedApp.isSymbolicLink()) throw new Error("installed application must be a real directory");
	if (requestedPathMetadata.managedBrowser && (!requestedPathMetadata.managedBrowser.isDirectory() || requestedPathMetadata.managedBrowser.isSymbolicLink())) throw new Error("managed browser input must be a real directory");
	if (requestedPathMetadata.artifactSignature && (!requestedPathMetadata.artifactSignature.isFile() || requestedPathMetadata.artifactSignature.isSymbolicLink())) throw new Error("artifact signature must be a regular file");
	if (platform === "darwin" && path.extname(options.installedApp) !== ".app") throw new Error("macOS installed application must be an Operator .app bundle");
}

async function verifyPackagedContents(layout) {
	const packagedFileMetadata = await Promise.all([layout.executable, ...layout.requiredFiles].map((target) => lstat(target)));
	if (packagedFileMetadata.some((entry) => !entry.isFile() || entry.isSymbolicLink())) {
		throw new Error("installed Electron release is missing the executable, daemon, agent-browser, or ACP runtime contents");
	}
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
	await preflightRequestedPaths(options, platform);
	const layout = installedReleaseLayout(options.installedApp, platform);
	await verifyPackagedContents(layout);
	const signatureIdentity = await (dependencies.verifySignature ?? nativeSignatureVerification)({
		signedArtifact: options.signedArtifact,
		installedApp: options.installedApp,
		installedExecutable: layout.executable,
		artifactSignature: options.artifactSignature,
		platform,
	});
	requireString(signatureIdentity, "native signing identity");
	const observedRuntime = await (dependencies.collectRuntimeMetadata ?? collectInstalledRuntimeMetadata)({
		executable: layout.executable,
	});
	const renderer = validateRuntime(observedRuntime);
	const measured = await artifactMeasurements(options);
	return { buildProfile: "signed-release-attested", measured, renderer };
}

export async function runArtifactBenchmark(argv = process.argv.slice(2), env = process.env, dependencies = {}) {
	const options = parseArtifactArguments(argv, env);
	const preflight = await preflightArtifactBenchmark(options, dependencies);
	const git = await (dependencies.collectGitMetadata ?? collectGitMetadata)();
	const host = (dependencies.collectHostMetadata ?? collectHostMetadata)();
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
			baseContents: ["go-daemon", "agent-browser", "node-22.23.2-acp-runtime"],
			artifactIdentity: "native-signature-and-required-contents-verified",
			runtimeMetadataSource: "installed-release-launch",
		},
		warmups: 0,
		samples: [measurement.bytes],
		unit: "bytes",
	}));
	const resultRoot = dependencies.resultRoot ?? DEFAULT_RESULT_ROOT;
	const outputs = benchmarkResults.map((benchmarkResult) => path.join(resultRoot, path.basename(benchmarkResultPath({ shell: options.shell, scenario: benchmarkResult.scenario, variant: env.OPERATOR_BENCH_VARIANT }))));
	for (let index = 0; index < benchmarkResults.length; index += 1) {
		await writeBenchmarkResult(outputs[index], benchmarkResults[index], { resultRoot });
		process.stdout.write(`${path.relative(frontendRoot, outputs[index])}\n`);
	}
	return benchmarkResults;
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("OPERATOR_BENCH_SIGNED_ARTIFACT=... OPERATOR_BENCH_INSTALLED_APP=... node scripts/benchmark-artifact.mjs --shell electron\n");
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
