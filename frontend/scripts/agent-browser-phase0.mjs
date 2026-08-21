import { spawn as nodeSpawn } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const EXIT_CODES = {
	PASS: 0,
	USAGE: 2,
	BROWSER_ABSENT: 3,
	NETWORK: 4,
	ACTION_FAILED: 5,
	ELECTRON_DETECTED: 7,
	TIMEOUT: 8,
	CANCELLED: 9,
};

const AGENT_BROWSER_VERSION = "0.33.1";
const DEFAULT_OUTPUT_LIMIT_BYTES = 1024 * 1024;
const DEFAULT_DOCTOR_TIMEOUT_MS = 60_000;
const DEFAULT_INSTALL_TIMEOUT_MS = 600_000;
const DEFAULT_ACTION_TIMEOUT_MS = 30_000;

const COMMANDS = new Set(["doctor", "install", "open", "snapshot", "click", "console", "errors", "screenshot", "tab", "close"]);
const ALLOWED_FLAGS = new Set(["--json", "-i"]);
const FORBIDDEN_FLAGS = new Set([
	"--cdp",
	"--auto-connect",
	"--load-extension",
	"--plugins",
	"--plugin",
	"--proxy-server",
	"--proxy-bypass-list",
	"--proxy-pac-url",
	"--user-data-dir",
	"--profile",
	"--profile-directory",
	"--executable-path",
	"--browser-path",
	"--remote-debugging-port",
	"--remote-debugging-pipe",
	"--no-sandbox",
]);

export function buildProbeEnvironment(sessionRoot, parentEnv, platform) {
	const parent = parentEnv ?? {};
	const env = {
		HOME: sessionRoot,
		USERPROFILE: sessionRoot,
		PATH: parent.PATH ?? (platform === "win32" ? "C:\\Windows\\System32" : "/usr/bin:/bin:/usr/sbin"),
		XDG_CACHE_HOME: path.join(sessionRoot, ".cache"),
		XDG_CONFIG_HOME: path.join(sessionRoot, ".config"),
		XDG_DATA_HOME: path.join(sessionRoot, ".local", "share"),
		XDG_STATE_HOME: path.join(sessionRoot, ".local", "state"),
		XDG_RUNTIME_DIR: path.join(sessionRoot, "runtime"),
		TMPDIR: path.join(sessionRoot, "tmp"),
		TEMP: path.join(sessionRoot, "tmp"),
		TMP: path.join(sessionRoot, "tmp"),
		AGENT_BROWSER_SOCKET_DIR: path.join(sessionRoot, "agent-browser-socket"),
	};
	if (parent.LANG) env.LANG = parent.LANG;
	if (platform === "win32") {
		if (parent.SYSTEMROOT) env.SYSTEMROOT = parent.SYSTEMROOT;
		if (parent.COMSPEC) env.COMSPEC = parent.COMSPEC;
		if (parent.PROGRAMFILES) env.PROGRAMFILES = parent.PROGRAMFILES;
		env.LOCALAPPDATA = path.join(sessionRoot, "appdata", "local");
	}
	return env;
}

export function assertSafeArguments(args, options) {
	const { sessionRoot } = options;
	if (!Array.isArray(args) || args.length === 0) throw new Error("policy: empty argument list");
	const command = args[0];
	if (!COMMANDS.has(command)) throw new Error(`policy: command not allowed: ${String(command)}`);
	for (const token of args.slice(1)) {
		const value = String(token);
		if (value.startsWith("-")) {
			if (FORBIDDEN_FLAGS.has(value)) throw new Error(`policy: forbidden flag: ${value}`);
			if (!ALLOWED_FLAGS.has(value)) throw new Error(`policy: flag not allowed: ${value}`);
			continue;
		}
		if (value.includes("://")) {
			let parsed;
			try {
				parsed = new URL(value);
			} catch {
				throw new Error(`policy: malformed url: ${value}`);
			}
			if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
				throw new Error(`policy: scheme not allowed: ${parsed.protocol}`);
			}
			if (parsed.username || parsed.password) throw new Error("policy: embedded credentials rejected");
			if (!isLoopbackHost(parsed.hostname)) throw new Error(`policy: non-loopback target: ${parsed.hostname}`);
			continue;
		}
		if (value.startsWith("/") || /^[A-Za-z]:[\\/]/.test(value)) {
			const resolved = path.resolve(value);
			const rootResolved = path.resolve(sessionRoot);
			const relative = path.relative(rootResolved, resolved);
			if (relative.startsWith("..") || path.isAbsolute(relative)) {
				throw new Error(`policy: path outside session root: ${value}`);
			}
		}
		if (/^[A-Za-z][A-Za-z0-9+.-]*:[^/]/.test(value) && value.includes("@")) {
			throw new Error("policy: credential-bearing argument rejected");
		}
	}
	return true;
}

function isLoopbackHost(hostname) {
	return hostname === "127.0.0.1" || hostname === "localhost" || hostname === "[::1]" || hostname === "::1";
}

export function serializeInstall(installFunction) {
	let flight = null;
	return () => {
		if (!flight) {
			flight = Promise.resolve()
				.then(installFunction)
				.finally(() => {
					flight = null;
				});
		}
		return flight;
	};
}

export async function createSessionRoot(baseDirectory, mode) {
	const root = await mkdtemp(path.join(baseDirectory, `${mode}-`));
	await mkdir(path.join(root, "tmp"), { recursive: true });
	return { root };
}

function defaultPause(milliseconds) {
	let resolvePause;
	const promise = new Promise((resolve) => {
		resolvePause = resolve;
	});
	const timer = setTimeout(() => resolvePause(), milliseconds);
	timer.unref?.();
	return promise;
}

async function runCommand(spawnImpl, request) {
	const startedAt = Date.now();
	let killFunction = null;
	let timedOut = false;
	let cancelled = false;
	let settled = false;
	const execution = new Promise((resolve) => {
		const finish = (result) => {
			if (settled) return;
			settled = true;
			resolve(result);
		};
		spawnImpl({
				file: request.file,
				args: request.args,
				env: request.env,
				timeoutMs: request.timeoutMs,
				signal: request.signal,
				scanStep: request.scanStep,
				registerKill: (fn) => {
					killFunction = fn;
					if (timedOut || cancelled) fn();
				},
			})
			.then(
				(result) => finish({ ...result, timedOut, cancelled }),
				(error) => finish({ code: null, stdout: "", stderr: String(error?.message ?? error), timedOut, cancelled }),
			);
		if (request.signal) {
			if (request.signal.aborted) {
				cancelled = true;
				killFunction?.();
			} else {
				request.signal.addEventListener(
					"abort",
					() => {
						cancelled = true;
						killFunction?.();
					},
					{ once: true },
				);
			}
		}
		request.pause(request.timeoutMs).then(() => {
			if (settled) return;
			timedOut = true;
			killFunction?.();
		});
	});
	const result = await execution;
	const originalStdoutBytes = Buffer.byteLength(result.stdout ?? "");
	const originalStderrBytes = Buffer.byteLength(result.stderr ?? "");
	const limit = request.outputLimitBytes;
	const truncated = limit !== undefined && (originalStdoutBytes > limit || originalStderrBytes > limit);
	const stdoutText = truncateText(result.stdout ?? "", limit);
	const stderrText = truncateText(result.stderr ?? "", limit);
	const stdoutBytes = Buffer.byteLength(stdoutText);
	const stderrBytes = Buffer.byteLength(stderrText);
	return {
		code: result.code,
		stdout: stdoutText,
		stderr: stderrText,
		signal: result.signal ?? null,
		timedOut: result.timedOut || timedOut,
		cancelled: result.cancelled || cancelled,
		truncated,
		stdoutBytes,
		stderrBytes,
		durationMs: Date.now() - startedAt,
	};
}

function truncateText(text, limit) {
	if (limit === undefined) return text;
	if (Buffer.byteLength(text) <= limit) return text;
	return Buffer.from(text, "utf8").subarray(0, limit).toString("utf8");
}

export function sanitizeDoctorReport(raw) {
	if (!raw || typeof raw !== "object") return { success: false, summary: { pass: 0, warn: 0, fail: 0 }, checks: [] };
	const summary = raw.summary ?? { pass: 0, warn: 0, fail: 0 };
	const checks = Array.isArray(raw.checks)
		? raw.checks.map((check) => ({
				id: String(check.id ?? check.name ?? "unknown"),
				category: String(check.category ?? "unknown"),
				status: String(check.status ?? "fail"),
			}))
		: [];
	return { success: Boolean(raw.success), summary, checks };
}

export function locateManagedExecutable(files, root, platform) {
	const keys = files instanceof Map ? [...files.keys()] : files instanceof Set ? [...files] : Object.keys(files);
	const rootResolved = root ? path.resolve(root) : null;
	const suffixes =
		platform === "darwin"
			? ["Google Chrome for Testing"]
			: platform === "win32"
				? ["chrome.exe"]
				: ["chrome-linux64/chrome", "chrome-linux/chrome"];
	for (const key of keys) {
		if (!key.includes(".agent-browser")) continue;
		for (const suffix of suffixes) {
			if (key.endsWith(suffix)) {
				if (rootResolved) {
					const resolver = platform === "win32" ? path.win32 : path;
					const relative = resolver.relative(resolver.resolve(root), resolver.resolve(key));
					if (relative.startsWith("..") || resolver.isAbsolute(relative)) continue;
				}
				return key;
			}
		}
	}
	return null;
}

export function scanForSessionElectronProcesses(listing, sessionTokens) {
	const findings = [];
	for (const line of String(listing).split("\n")) {
		const match = line.match(/^\s*(\d+)\s+(.*)$/);
		if (!match) continue;
		const [, pid, command] = match;
		const inScope = sessionTokens.some((token) => command.includes(token));
		if (inScope && /electron/i.test(command)) findings.push({ pid, command });
	}
	return findings;
}

export function mapOutcomeToExitCode(outcome) {
	switch (outcome) {
		case "pass":
			return EXIT_CODES.PASS;
		case "usage":
			return EXIT_CODES.USAGE;
		case "browser-absent":
			return EXIT_CODES.BROWSER_ABSENT;
		case "network":
			return EXIT_CODES.NETWORK;
		case "action-failed":
			return EXIT_CODES.ACTION_FAILED;
		case "electron-detected":
			return EXIT_CODES.ELECTRON_DETECTED;
		case "timeout":
			return EXIT_CODES.TIMEOUT;
		case "cancelled":
			return EXIT_CODES.CANCELLED;
		default:
			return EXIT_CODES.ACTION_FAILED;
	}
}

export function sanitizeEvidenceText(text, sessionTokens) {
	let scrubbed = String(text);
	for (const token of sessionTokens) scrubbed = scrubbed.split(token).join("<session-root>");
	return scrubbed;
}

async function walkFiles(directory, platform) {
	const found = [];
	async function visit(current) {
		let entries;
		try {
			entries = await readdir(current, { withFileTypes: true });
		} catch (error) {
			if (error?.code !== "ENOENT") throw error;
			return;
		}
		for (const entry of entries) {
			const entryPath = path.join(current, entry.name);
			if (entry.isDirectory()) await visit(entryPath);
			else found.push(entryPath);
		}
	}
	await visit(directory);
	return new Set(platform === "win32" ? found.map((entry) => entry.split(path.sep).join("\\")) : found);
}

export async function runMode(mode, options) {
	const {
		sessionRoot,
		spawnImpl,
		platform = process.platform,
		now = () => Date.now(),
		pause = defaultPause,
		outputLimitBytes = DEFAULT_OUTPUT_LIMIT_BYTES,
		doctorTimeoutMs = DEFAULT_DOCTOR_TIMEOUT_MS,
		installTimeoutMs = DEFAULT_INSTALL_TIMEOUT_MS,
		actionTimeoutMs = DEFAULT_ACTION_TIMEOUT_MS,
		signal,
		fixturePort = 0,
		binaryPath,
		cleanupHook,
		scenario,
	} = options;
	const steps = [];
	const sessionTokens = [sessionRoot];
	const sessionEnv = buildProbeEnvironment(sessionRoot, options.parentEnv, platform);
	const artifactsDir = path.join(sessionRoot, "artifacts");
	let outcome = "action-failed";
	const evidence = {
		schemaVersion: 1,
		mode,
		agentBrowserVersion: AGENT_BROWSER_VERSION,
		startedAt: new Date(now()).toISOString(),
		platform: { os: platform, arch: process.arch },
		daemonStarted: false,
		steps: [],
		doctor: null,
		electronProcessesInSession: [],
		outcome: "action-failed",
	};

	const record = (command, result, extra = {}) => {
		steps.push({
			command,
			code: result?.code ?? null,
			timedOut: Boolean(result?.timedOut),
			cancelled: Boolean(result?.cancelled),
			outputTruncated: Boolean(result?.truncated),
			stdoutBytes: result?.stdoutBytes ?? 0,
			stderrBytes: result?.stderrBytes ?? 0,
			durationMs: result?.durationMs ?? 0,
			...extra,
		});
	};

	const invoke = async (args, timeoutMs, extra = {}) => {
		assertSafeArguments(args, { sessionRoot, platform });
		const result = await runCommand(spawnImpl, {
			file: binaryPath,
			args,
			env: sessionEnv,
			timeoutMs,
			signal,
			pause,
			outputLimitBytes,
		});
		record(args[0], result, extra);
		return result;
	};

	const scan = async () => {
		const listArgs = platform === "win32" ? ["-NoProfile", "-Command", "Get-CimInstance Win32_Process | ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }"] : ["-axo", "pid=,args="];
		const result = await runCommand(spawnImpl, {
			file: platform === "win32" ? "powershell" : "ps",
			args: listArgs,
			env: {},
			timeoutMs: actionTimeoutMs,
			signal,
			pause,
			outputLimitBytes,
			scanStep: true,
		});
		record("process-scan", result, { scanStep: true });
		return scanForSessionElectronProcesses(result.stdout, sessionTokens);
	};

	try {
		const doctorResult = await invoke(["doctor", "--json"], doctorTimeoutMs);
		if (doctorResult.timedOut) outcome = "timeout";
		else if (doctorResult.cancelled) outcome = "cancelled";
		else {
			let doctorRaw = null;
			try {
				doctorRaw = JSON.parse(doctorResult.stdout);
			} catch {
				doctorRaw = null;
			}
			const doctor = sanitizeDoctorReport(doctorRaw);
			evidence.doctor = doctor;
			const browserDiscovered =
				doctor.success &&
				doctor.checks.some((check) => {
					const cat = String(check.category).toLowerCase();
					const id = String(check.id).toLowerCase();
					const isBrowser =
						cat.includes("browser") ||
						cat.includes("chrome") ||
						cat.includes("chromium") ||
						cat.includes("edge") ||
						id.includes("chrome") ||
						id.includes("browser") ||
						id.includes("chromium") ||
						id.includes("edge");
					return isBrowser && check.status === "pass";
				});
			if (!browserDiscovered && mode === "system") {
				outcome = "browser-absent";
			} else if (mode === "managed") {
				const installOnce = serializeInstall(async () => invoke(["install", "--json"], installTimeoutMs));
				const installResult = await installOnce();
				if (installResult.timedOut) outcome = "timeout";
				else if (installResult.cancelled) outcome = "cancelled";
				else if (installResult.code !== 0) outcome = "network";
				else {
					const files = await walkFiles(path.join(sessionRoot, ".agent-browser", "browsers"), platform);
					const managedPath = locateManagedExecutable(files, sessionRoot, platform);
					if (!managedPath) outcome = "browser-absent";
				}
			}
			if (outcome === "action-failed") {
				await mkdir(artifactsDir, { recursive: true });
				const fixtureUrl = `http://127.0.0.1:${fixturePort}/`;
				const substitutions = [
					[/\{fixture\}/g, fixtureUrl],
					[/\{artifacts\}/g, artifactsDir],
				];
				const rawActions = scenario?.actions ?? [
					"open {fixture} --json",
					"snapshot -i --json",
					"click @e1 --json",
					"console --json",
					"errors --json",
					"screenshot {artifacts}/page.png --json",
					"tab new {fixture} --json",
					"tab list --json",
					"tab close --json",
					"close --json",
				];
				const actions = rawActions.filter((action) => !action.startsWith("doctor") && !action.startsWith("install"));
				for (const action of actions) {
					const args = action
						.split(" ")
						.map((token) => substitutions.reduce((acc, [pattern, replacement]) => acc.replace(pattern, replacement), token))
						.filter(Boolean);
					const result = await invoke(args, actionTimeoutMs);
					if (result.timedOut) {
						outcome = "timeout";
						break;
					}
					if (result.cancelled) {
						outcome = "cancelled";
						break;
					}
					if (result.code !== 0) {
						outcome = "action-failed";
						break;
					}
					outcome = "pass";
				}
			}
			if (outcome === "pass") {
				const detected = await scan();
				evidence.electronProcessesInSession = detected.map((finding) => ({
					pid: finding.pid,
					command: sanitizeEvidenceText(finding.command, sessionTokens),
				}));
				if (detected.length > 0) outcome = "electron-detected";
			}
		}
	} finally {
		evidence.finishedAt = new Date(now()).toISOString();
		evidence.outcome = outcome;
		evidence.steps = steps.map((step) => ({
			...step,
			scanStep: undefined,
		}));
		if (cleanupHook) await cleanupHook(sessionRoot);
		else await rm(sessionRoot, { recursive: true, force: true });
	}
	return { outcome, steps, electronProcessesInSession: evidence.electronProcessesInSession, daemonStarted: false, evidence };
}

function resolveBinary(platform) {
	const binaryName = platform === "win32" ? "agent-browser.exe" : "agent-browser";
	const packaged = fileURLToPath(new URL("../agent-browser/" + binaryName, import.meta.url));
	return packaged;
}

async function loadScenarios() {
	const { readFile } = await import("node:fs/promises");
	const scenariosFile = fileURLToPath(new URL("../perf/browser/scenarios.json", import.meta.url));
	return JSON.parse(await readFile(scenariosFile, "utf8"));
}

async function startFixtureServer(preferredPort) {
	const { createServer } = await import("node:http");
	const html = "<!doctype html><html><head><title>Operator Phase 0 Fixture</title></head><body><h1 id='title'>ready</h1><button id='swap' onclick='document.getElementById(\"title\").textContent=\"clicked\"'>swap</button><script>console.log('fixture-loaded');</script></body></html>";
	const server = createServer((request, response) => {
		response.writeHead(200, { "content-type": "text/html" });
		response.end(html);
	});
	await new Promise((resolve) => server.listen(preferredPort, "127.0.0.1", resolve));
	return server;
}

async function exportArtifacts(sessionRoot, artifactsOutput) {
	let entries;
	try {
		entries = await readdir(path.join(sessionRoot, "artifacts"));
	} catch {
		return;
	}
	await mkdir(artifactsOutput, { recursive: true });
	for (const entry of entries) {
		await copyFile(path.join(sessionRoot, "artifacts", entry), path.join(artifactsOutput, entry));
	}
}

export async function main(argv) {
	let mode = null;
	let artifactsOutput = null;
	let preferredPort = 0;
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--mode") mode = argv[index + 1];
		else if (argv[index] === "--artifacts") artifactsOutput = argv[index + 1];
		else if (argv[index] === "--fixture-port") preferredPort = Number(argv[index + 1]);
	}
	if (mode !== "system" && mode !== "managed") {
		console.error("usage: agent-browser-phase0.mjs --mode system|managed [--artifacts DIR] [--fixture-port PORT]");
		return EXIT_CODES.USAGE;
	}
	const operatorRoot = process.env.OPERATOR_DATA_DIR
		? path.dirname(path.resolve(process.env.OPERATOR_DATA_DIR))
		: path.join(os.homedir(), ".operator");
	const baseDirectory = path.join(operatorRoot, "dev");
	await mkdir(baseDirectory, { recursive: true });
	const { root: sessionRoot } = await createSessionRoot(baseDirectory, mode);
	const binaryPath = resolveBinary(process.platform);
	const scenarios = await loadScenarios();
	const scenario = scenarios[mode];
	let server = null;
	try {
		server = await startFixtureServer(preferredPort);
		const port = server.address().port;
		const resolvedArtifacts = artifactsOutput ?? path.join(os.tmpdir(), `agent-browser-phase0-${mode}-artifacts`);
		const result = await runMode(mode, {
			sessionRoot,
			spawnImpl: (request) =>
				new Promise((resolve) => {
					const child = nodeSpawn(request.file, request.args, {
						env: request.env,
						stdio: ["ignore", "pipe", "pipe"],
						windowsHide: true,
					});
					let stdout = "";
					let stderr = "";
					child.stdout.on("data", (chunk) => {
						stdout += chunk;
					});
					child.stderr.on("data", (chunk) => {
						stderr += chunk;
					});
					request.registerKill(() => child.kill("SIGKILL"));
					child.on("error", (error) => resolve({ code: null, stdout, stderr: String(error) }));
					child.on("close", (code, signal) => resolve({ code, stdout, stderr, signal }));
				}),
			platform: process.platform,
			fixturePort: port,
			binaryPath,
			scenario,
			parentEnv: process.env,
			cleanupHook: async (root) => {
				await exportArtifacts(root, resolvedArtifacts);
				await rm(root, { recursive: true, force: true });
			},
		});
		const evidencePath = path.join(resolvedArtifacts, `evidence-${mode}.json`);
		await mkdir(path.dirname(evidencePath), { recursive: true });
		const { writeFile } = await import("node:fs/promises");
		await writeFile(evidencePath, `${JSON.stringify(result.evidence, null, "\t")}\n`, "utf8");
		console.log(`outcome=${result.outcome} evidence=${evidencePath}`);
		return mapOutcomeToExitCode(result.outcome);
	} finally {
		server?.close();
	}
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
	main(process.argv.slice(2)).then(
		(code) => {
			process.exitCode = code;
		},
		(error) => {
			console.error(String(error));
			process.exitCode = EXIT_CODES.ACTION_FAILED;
		},
	);
}
