import { execFile, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { _electron as electron } from "playwright";
import { createServer as createViteServer } from "vite";
import {
	benchmarkResultPath,
	collectGitMetadata,
	collectHostMetadata,
	createBenchmarkResult,
	parseNamedArguments,
	resolveEvidenceScope,
	sanitizedBindingEnvironment,
	scenarioResultConfiguration,
	writeBenchmarkResult,
} from "./benchmark-result.mjs";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const scenariosPath = fileURLToPath(new URL("../perf/scenarios.json", import.meta.url));
const terminalHarnessPath = fileURLToPath(new URL("../perf/terminal/index.html", import.meta.url));
const terminalViteConfigPath = fileURLToPath(new URL("../vite.terminal-perf.config.ts", import.meta.url));
const tauriCliPath = fileURLToPath(new URL("../node_modules/@tauri-apps/cli/tauri.js", import.meta.url));
const terminalScenarios = new Set(["vtebench", "large-output", "input-latency", "reconnect", "cpu-time", "active-memory"]);
const launchDrivenScenarios = new Set(["active-memory", "cpu-time"]);
const compositingModes = new Set(["enabled", "disabled"]);
const execFileAsync = promisify(execFile);
const terminalAcknowledgementNames = new Set([
	"first-paint",
	"workload-start",
	"workload",
	"reconnect",
	"disposal",
	"input-echo",
]);
const primaryAcknowledgementNames = Object.freeze({
	vtebench: "workload",
	"large-output": "workload",
	"input-latency": "input-echo",
	reconnect: "reconnect",
	"cpu-time": "workload",
	"active-memory": "workload",
});

export function parseTerminalArguments(argv) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron" && namedArguments.shell !== "tauri") {
		throw new Error("terminal benchmark supports only electron and tauri webviews");
	}
	if (!terminalScenarios.has(namedArguments.scenario)) {
		throw new Error(`unsupported terminal scenario: ${namedArguments.scenario ?? ""}`);
	}
	const knownKeys = ["shell", "scenario", ...(namedArguments.compositing !== undefined ? ["compositing"] : [])];
	if (Object.keys(namedArguments).some((key) => !knownKeys.includes(key))) {
		throw new Error("unknown terminal benchmark argument");
	}
	let compositing;
	if (namedArguments.compositing !== undefined) {
		if (!compositingModes.has(namedArguments.compositing)) throw new Error(`unsupported compositing mode: ${namedArguments.compositing}`);
		compositing = namedArguments.compositing;
	}
	return { shell: namedArguments.shell, scenario: namedArguments.scenario, ...(compositing ? { compositing } : {}) };
}

function scenarioMeasurementPlan(scenario) {
	if (scenario === "vtebench") return { eventName: "operator:terminal-benchmark-run", markName: "operator:terminal-ready", primaryName: "workload", reportsBytes: true };
	if (scenario === "large-output") return { eventName: "operator:terminal-benchmark-run", markName: "operator:terminal-ready", primaryName: "workload", reportsBytes: true };
	if (scenario === "input-latency") return { eventName: "operator:terminal-benchmark-input", markName: "operator:terminal-input-echo", primaryName: "input-echo", reportsBytes: false };
	if (scenario === "reconnect") return { eventName: "operator:terminal-benchmark-reconnect", markName: "operator:terminal-reconnect", primaryName: "reconnect", reportsBytes: false };
	if (scenario === "cpu-time") return { eventName: "operator:terminal-benchmark-run", markName: "operator:terminal-ready", primaryName: "workload", reportsBytes: true };
	if (scenario === "active-memory") return { eventName: "operator:terminal-benchmark-run", markName: "operator:terminal-ready", primaryName: "workload", reportsBytes: true };
	throw new Error(`unsupported terminal scenario: ${scenario}`);
}

export function terminalThroughputSample(scenario, durationMilliseconds, configuration) {
	if (!Number.isFinite(durationMilliseconds) || durationMilliseconds <= 0) throw new Error("terminal benchmark requires a positive acknowledgement duration");
	const seconds = durationMilliseconds / 1000;
	if (scenario === "vtebench") return 1 / seconds;
	if (scenario === "large-output") return configuration.outputBytes / seconds;
	if (scenario === "input-latency" || scenario === "reconnect") return durationMilliseconds;
	throw new Error(`unsupported terminal scenario: ${scenario}`);
}

function stampTerminalEvidenceScope(env, localBuildProfile, runtimeAttestation, label) {
	const evidenceScope = resolveEvidenceScope(env);
	let buildProfile = env.OPERATOR_BENCH_BUILD_PROFILE?.trim() || localBuildProfile;
	if (evidenceScope === "binding") {
		if (!env.OPERATOR_BENCH_BUILD_PROFILE?.trim()) {
			throw new Error(`${label}: OPERATOR_BENCH_EVIDENCE_SCOPE=binding requires an explicit non-local OPERATOR_BENCH_BUILD_PROFILE`);
		}
		if (/local/.test(buildProfile)) {
			throw new Error(`${label}: a local build profile (${buildProfile}) cannot be stamped with binding evidence scope; only a non-local build profile may carry it`);
		}
	}
	return { buildProfile, evidenceScope, runtimeAttestation };
}

export function terminalEvidenceProfile(env) {
	return stampTerminalEvidenceScope(env, "local-electron-webview-non-binding", "npm-electron-driver", "electron terminal runner");
}

export function tauriTerminalEvidenceProfile(env) {
	return stampTerminalEvidenceScope(env, "local-tauri-webview-non-binding", "tauri-dev-webview", "tauri terminal runner");
}

export function terminalAcknowledgementDurations(messages, primaryName = "workload") {
	if (!Array.isArray(messages)) throw new Error("terminal acknowledgements must be an array");
	for (const message of messages) assertTerminalAcknowledgement(message, primaryName);
	const durations = [];
	const observedBytes = [];
	let workloadStart;
	for (const message of [...messages].sort((left, right) => left.timestamp - right.timestamp)) {
		if (message.name === "workload-start") {
			if (workloadStart !== undefined) throw new Error(`terminal workload acknowledgements are out of order: start ${message.timestamp} followed start ${workloadStart}`);
			workloadStart = message.timestamp;
		}
		if (message.name === primaryName) {
			if (workloadStart === undefined || message.timestamp <= workloadStart) {
				throw new Error(`terminal workload acknowledgements are out of order: ${primaryName} ${message.timestamp} after ${workloadStart ?? "no start"}`);
			}
			durations.push(message.timestamp - workloadStart);
			observedBytes.push(message.bytes);
			workloadStart = undefined;
		}
	}
	if (workloadStart !== undefined) throw new Error("terminal workload acknowledgement is incomplete");
	return { durations, observedBytes };
}

export function terminalWorkloadEvidence(messages, expectedWorkloads, scenario, configuration, primaryName = "workload") {
	if (!Number.isInteger(expectedWorkloads) || expectedWorkloads < 1) throw new Error("terminal workload count must be a positive integer");
	const { durations, observedBytes } = terminalAcknowledgementDurations(messages, primaryName);
	const primaries = messages.filter((message) => message.name === primaryName);
	if (durations.length !== expectedWorkloads || primaries.length !== expectedWorkloads) {
		throw new Error(`terminal workload observed ${primaries.length} successful ${primaryName} acknowledgements but required ${expectedWorkloads}`);
	}
	return {
		durations,
		observedBytes,
		observedWorkloads: primaries.length,
		requiredWorkloads: expectedWorkloads,
		workloadSuccess: true,
	};
}

function assertTerminalAcknowledgement(message, primaryName = "workload") {
	const expectedKeys = message?.name === primaryName && typeof message?.bytes !== "undefined" ? "bytes,name,timestamp" : "name,timestamp";
	if (
		!message ||
		typeof message !== "object" ||
		Array.isArray(message) ||
		Object.keys(message).sort().join(",") !== expectedKeys ||
		!terminalAcknowledgementNames.has(message.name) ||
		!Number.isFinite(message.timestamp) ||
		message.timestamp < 0 ||
		(typeof message?.bytes !== "undefined" && (message.name !== primaryName || !Number.isFinite(message.bytes) || message.bytes < 0))
	) {
		throw new Error("terminal acknowledgements must contain only a name and timestamp");
	}
}

export function terminalScenarioConfiguration(scenario, profile, workloadEvidence, extra = {}) {
	if (
		!workloadEvidence ||
		typeof workloadEvidence !== "object" ||
		workloadEvidence.workloadSuccess !== true ||
		!Number.isInteger(workloadEvidence.observedWorkloads) ||
		workloadEvidence.observedWorkloads < 1 ||
		workloadEvidence.observedWorkloads !== workloadEvidence.requiredWorkloads
	) {
		throw new Error("terminal results require observed workload acknowledgements; by-construction completeness is forbidden");
	}
	for (const [key, value] of Object.entries(extra)) {
		if (key === "compositingMode" && !compositingModes.has(value)) throw new Error(`compositingMode must be enabled or disabled, received ${String(value)}`);
		if (key === "observedOutputBytes" && (!Number.isFinite(value) || value < 0)) throw new Error("observedOutputBytes must be a finite non-negative number");
	}
	return {
		...scenarioResultConfiguration(scenario),
		evidenceScope: profile.evidenceScope,
		runtimeAttestation: profile.runtimeAttestation,
		workloadSuccess: workloadEvidence.workloadSuccess,
		observedWorkloads: workloadEvidence.observedWorkloads,
		requiredWorkloads: workloadEvidence.requiredWorkloads,
		...extra,
	};
}

const OUTPUT_OVERHEAD_TOLERANCE_BYTES = 65_536;

export function assertObservedOutputBytes(workloadEvidence, scenario, configuration) {
	if (scenario !== "large-output") return true;
	const configured = configuration?.outputBytes;
	if (!Number.isFinite(configured) || configured <= 0) throw new Error("large-output scenario requires a positive configured outputBytes");
	const observed = workloadEvidence?.observedBytes;
	if (!Array.isArray(observed) || observed.length === 0) throw new Error("terminal workload evidence never reported its observed byte count");
	observed.forEach((bytes, index) => {
		if (typeof bytes !== "number" || !Number.isFinite(bytes)) {
			throw new Error(`terminal workload ${index + 1} never reported its observed byte count`);
		}
		if (bytes < configured) {
			throw new Error(`terminal workload ${index + 1} observed ${bytes} bytes across the workload window but the scenario configured ${configured}`);
		}
		if (bytes > configured + OUTPUT_OVERHEAD_TOLERANCE_BYTES) {
			throw new Error(`terminal workload ${index + 1} observed ${bytes} bytes across the workload window, exceeding the configured output plus bounded shell overhead (${configured + OUTPUT_OVERHEAD_TOLERANCE_BYTES})`);
		}
	});
	return true;
}

export function terminalResultVariant(env = process.env, compositing) {
	const variant = [env?.OPERATOR_BENCH_VARIANT, compositing ? `compositing-${compositing}` : undefined]
		.filter(Boolean)
		.join("-");
	return variant === "" ? undefined : variant;
}

export function cpuTimePerWorkload(before, after) {
	for (const [label, snapshot] of [["before", before], ["after", after]]) {
		if (!snapshot || typeof snapshot !== "object" || !Number.isFinite(snapshot.cpuMs) || !Number.isFinite(snapshot.workloads)) {
			throw new Error(`terminal cpu-time ${label} snapshot must contain finite cpuMs and workloads`);
		}
	}
	if (after.cpuMs < before.cpuMs) throw new Error("observed process CPU time decreased between snapshots");
	if (after.workloads <= before.workloads) throw new Error("cpu-time accounting requires a positive number of completed workloads in the measured window");
	return (after.cpuMs - before.cpuMs) / (after.workloads - before.workloads);
}

export function cpuDeltasFromIterationSnapshots(snapshots, { warmups }) {
	if (!Array.isArray(snapshots) || snapshots.length < 2) throw new Error("cpu-time requires at least two observed iteration snapshots");
	for (const snapshot of snapshots) {
		if (!snapshot || typeof snapshot !== "object" || !Number.isFinite(snapshot.cpuMs) || !Number.isFinite(snapshot.workloads)) {
			throw new Error("cpu-time snapshots must record finite cpuMs and their completed workload counts");
		}
	}
	const deltas = [];
	for (let index = 1; index < snapshots.length; index += 1) {
		if (snapshots[index].workloads > warmups) {
			deltas.push(cpuTimePerWorkload(snapshots[index - 1], snapshots[index]));
		}
	}
	return deltas;
}

function validatedHarnessUrl(rawUrl) {
	if (!rawUrl) throw new Error("OPERATOR_BENCH_TERMINAL_URL must name the Task 4 benchmark entry");
	const url = new URL(rawUrl);
	if (!["http:", "https:"].includes(url.protocol) || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
		throw new Error("OPERATOR_BENCH_TERMINAL_URL must use a loopback HTTP(S) origin");
	}
	return url.toString();
}

function electronDriverSource() {
	return [
		'const { app, BrowserWindow } = require("electron");',
		'const path = require("node:path");',
		'app.setPath("userData", path.join(process.env.OPERATOR_BENCH_STATE_ROOT, "electron"));',
		'app.whenReady().then(() => {',
		'  const window = new BrowserWindow({ show: true, webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true } });',
		'  void window.loadURL(process.env.OPERATOR_BENCH_TERMINAL_URL);',
		'});',
		'app.on("window-all-closed", () => app.quit());',
		"",
	].join("\n");
}

async function benchmarkStateDirectory(shell) {
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	return await mkdtemp(path.join(parent, `${shell}-terminal-`));
}

async function removeBenchmarkState(stateRoot) {
	await rm(stateRoot, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
}

async function terminalIterationObservation(page, plan, scenarioName, iteration) {
	const actionTimestamp = await page.evaluate(
		({ eventName, markName, benchmarkScenario, benchmarkIteration }) => {
			performance.clearMarks(markName);
			const timestamp = performance.now();
			window.dispatchEvent(
				new CustomEvent(eventName, {
					detail: { scenario: benchmarkScenario, iteration: benchmarkIteration },
				}),
			);
			return timestamp;
		},
		{ eventName: plan.eventName, markName: plan.markName, benchmarkScenario: scenarioName, benchmarkIteration: iteration },
	);
	await page.waitForFunction(
		({ markName, after }) => performance.getEntriesByName(markName, "mark").some((entry) => entry.startTime > after),
		{ markName: plan.markName, after: actionTimestamp },
		{ timeout: 120_000 },
	);
	const acknowledgement = await page.evaluate(
		({ markName, after }) => {
			const entry = performance
				.getEntriesByName(markName, "mark")
				.filter((candidate) => candidate.startTime > after)
				.at(-1);
			if (!entry) throw new Error("terminal acknowledgement mark missing");
			if ("detail" in entry && entry.detail !== null) throw new Error("terminal acknowledgement mark must contain a timestamp only");
			return entry.startTime;
		},
		{ markName: plan.markName, after: actionTimestamp },
	);
	const observedBytes = plan.reportsBytes
		? await page.evaluate(() => window.__operatorTerminalBenchmark?.takeLastPrimaryBytes?.())
		: undefined;
	return {
		actionTimestamp,
		acknowledgementTimestamp: acknowledgement,
		duration: acknowledgement - actionTimestamp,
		observedBytes: typeof observedBytes === "number" ? observedBytes : undefined,
	};
}

async function terminalRendererMetadata(application, page) {
	const versions = await application.evaluate(() => ({ electron: process.versions.electron, chromium: process.versions.chrome }));
	const rendererKind = await page.evaluate(
		() => document.querySelector("[data-terminal-renderer-kind]")?.getAttribute("data-terminal-renderer-kind"),
	);
	if (rendererKind !== "dom") throw new Error("terminal harness did not report the dom renderer kind");
	return {
		webviewRuntimeVersion: `Electron ${versions.electron} / Chromium ${versions.chromium}`,
		rendererKind,
		displayScale: await page.evaluate(() => window.devicePixelRatio),
	};
}

function requiredTauriInput(env, name) {
	const input = env[name]?.trim();
	if (!input) throw new Error(`${name} is required for the live Tauri terminal benchmark`);
	return input;
}

export function tauriDaemonUrl(env) {
	const rawUrl = requiredTauriInput(env, "OPERATOR_BENCH_DAEMON_URL");
	const url = new URL(rawUrl);
	if (
		!["http:", "https:"].includes(url.protocol) ||
		!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
		url.username ||
		url.password
	) {
		throw new Error("OPERATOR_BENCH_DAEMON_URL must use a loopback HTTP(S) origin");
	}
	url.pathname = "/";
	url.search = "";
	url.hash = "";
	return url.toString();
}

function assertRendererMessage(message) {
	if (
		!message ||
		typeof message !== "object" ||
		Array.isArray(message) ||
		Object.keys(message).sort().join(",") !== "displayScale,name,rendererKind,webviewRuntimeVersion" ||
		message.name !== "renderer" ||
		message.rendererKind !== "dom" ||
		typeof message.webviewRuntimeVersion !== "string" ||
		message.webviewRuntimeVersion.trim() === "" ||
		!Number.isFinite(message.displayScale) ||
		message.displayScale <= 0
	) {
		throw new Error("terminal renderer metadata is invalid");
	}
}

function terminalReporter(expectedWorkloads, { primaryName = "workload", requireDisposal = true, onPrimary } = {}) {
	const route = `/terminal-benchmark/${randomUUID()}`;
	const acknowledgements = [];
	const pendingObservations = new Set();
	let renderer;
	let resolveCompletion;
	let rejectCompletion;
	let settled = false;
	const completion = new Promise((resolve, reject) => {
		resolveCompletion = resolve;
		rejectCompletion = reject;
	});
	const fail = (error) => {
		if (settled) return;
		settled = true;
		rejectCompletion(error);
	};
	const trySettle = () => {
		const primaries = acknowledgements.filter((message) => message.name === primaryName).length;
		const disposed = acknowledgements.some((message) => message.name === "disposal");
		if (!settled && renderer && primaries === expectedWorkloads && (disposed || !requireDisposal) && pendingObservations.size === 0) {
			settled = true;
			resolveCompletion({ acknowledgements, renderer });
		}
	};
	const record = (message) => {
		if (message?.name === "renderer") {
			assertRendererMessage(message);
			renderer = {
				displayScale: message.displayScale,
				rendererKind: message.rendererKind,
				webviewRuntimeVersion: message.webviewRuntimeVersion,
			};
		} else {
			assertTerminalAcknowledgement(message, primaryName);
			acknowledgements.push(message);
			if (onPrimary && message.name === primaryName) {
				const observationTask = Promise.resolve()
					.then(() => onPrimary(message))
					.catch(fail)
					.finally(() => {
						pendingObservations.delete(observationTask);
						trySettle();
					});
				pendingObservations.add(observationTask);
			}
		}
		trySettle();
	};
	const server = http.createServer((request, response) => {
		response.setHeader("access-control-allow-origin", "*");
		if (request.method !== "POST" || request.url !== route) {
			response.writeHead(404).end();
			return;
		}
		let body = "";
		request.setEncoding("utf8");
		request.on("data", (chunk) => {
			body += chunk;
			if (body.length > 16_384) request.destroy(new Error("terminal reporter message exceeds the byte limit"));
		});
		request.on("error", fail);
		request.on("end", () => {
			try {
				record(JSON.parse(body));
				response.writeHead(204).end();
			} catch (error) {
				response.writeHead(400).end();
				fail(error);
			}
		});
	});
	return {
		completion,
		fail,
		listen: async () => {
			await new Promise((resolve, reject) => {
				server.once("error", reject);
				server.listen(0, "127.0.0.1", resolve);
			});
			const address = server.address();
			if (!address || typeof address === "string") throw new Error("terminal reporter did not bind a TCP port");
			return `http://127.0.0.1:${address.port}${route}`;
		},
		close: async () => {
			if (!server.listening) return;
			await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
		},
	};
}


export function tauriHarnessProxyConfig(daemonBaseUrl) {
	return {
		target: tauriDaemonUrl({ OPERATOR_BENCH_DAEMON_URL: daemonBaseUrl }),
		ws: true,
		configure(proxy) {
			proxy.on("proxyReqWs", (request) => request.removeHeader("origin"));
		},
	};
}

async function terminalViteServer(queryForUrl, daemonBaseUrl) {
	let query = "";
	const vite = await createViteServer({
		configFile: terminalViteConfigPath,
		logLevel: "error",
		plugins: [
			{
				name: "terminal-benchmark-configuration",
				transformIndexHtml(html) {
					return html.replace("<head>", `<head><script>history.replaceState(null, '', ${JSON.stringify(`?${query}`)})</script>`);
				},
			},
		],
		server: {
			host: "127.0.0.1",
			port: 0,
			strictPort: false,
			proxy: { "/mux": tauriHarnessProxyConfig(daemonBaseUrl) },
		},
	});
	await vite.listen();
	const address = vite.httpServer?.address();
	if (!address || typeof address === "string") {
		await vite.close();
		throw new Error("terminal benchmark Vite server did not bind a TCP port");
	}
	const url = `http://127.0.0.1:${address.port}`;
	try {
		query = queryForUrl(url);
	} catch (error) {
		await vite.close();
		throw error;
	}
	return { url, close: () => vite.close() };
}

function tauriHarnessQuery(env, scenarioName, scenario, reportUrl, daemonBaseUrl = tauriDaemonUrl(env)) {
	return new URLSearchParams({
		daemonBaseUrl,
		sessionId: requiredTauriInput(env, "OPERATOR_BENCH_SESSION_ID"),
		terminalId: requiredTauriInput(env, "OPERATOR_BENCH_TERMINAL_ID"),
		scenario: scenarioName,
		warmups: String(scenario.warmups),
		samples: String(scenario.samples),
		...(scenario.fixedWorkloads !== undefined ? { fixedWorkloads: String(scenario.fixedWorkloads) } : {}),
		reportUrl,
	}).toString();
}

export function tauriHarnessConfig(harnessUrl) {
	return JSON.stringify({
		productName: "Operator Benchmark",
		identifier: "dev.operator.desktop.benchmark",
		build: { beforeDevCommand: "", devUrl: harnessUrl },
		app: { security: { capabilities: ["phase0", "default", "terminal-benchmark"] } },
	});
}

function spawnTauriHarness(harnessUrl, stateRoot, env, compositing) {
	const config = tauriHarnessConfig(harnessUrl);
	const controlled = {
		OPERATOR_DATA_DIR: path.join(stateRoot, "operator", "data"),
		OPERATOR_RUN_FILE: path.join(stateRoot, "operator", "running.json"),
		OPERATOR_TAURI_TERMINAL_BENCHMARK: "1",
		OPERATOR_TAURI_TERMINAL_BENCHMARK_URL: harnessUrl,
	};
	if (compositing === "disabled") controlled.WEBKIT_DISABLE_COMPOSITING_MODE = "1";
	const application = spawn(
		process.execPath,
		[tauriCliPath, "dev", "--no-watch", "--no-dev-server-wait", "--config", config],
		{
			cwd: frontendRoot,
			detached: process.platform !== "win32",
			env: sanitizedBindingEnvironment(env, controlled),
			stdio: ["ignore", "pipe", "pipe"],
		},
	);
	let diagnostic = "";
	const collectDiagnostic = (chunk) => {
		diagnostic = `${diagnostic}${chunk}`.slice(-16_384);
	};
	application.stdout.on("data", collectDiagnostic);
	application.stderr.on("data", collectDiagnostic);
	return { application, diagnostic: () => diagnostic.trim() };
}

async function terminateTauriHarness(application) {
	if (application.exitCode !== null || application.signalCode !== null) return;
	if (process.platform === "win32") {
		await execFileAsync("taskkill.exe", ["/PID", String(application.pid), "/T", "/F"]);
		return;
	}
	process.kill(-application.pid, "SIGTERM");
	let exitTimeout;
	try {
		await Promise.race([
			new Promise((resolve) => application.once("exit", resolve)),
			new Promise((resolve) => {
				exitTimeout = setTimeout(resolve, 5_000);
			}),
		]);
	} finally {
		clearTimeout(exitTimeout);
	}
	if (application.exitCode === null && application.signalCode === null) process.kill(-application.pid, "SIGKILL");
}

async function withinTimeout(promise, milliseconds, message) {
	let timeout;
	try {
		return await Promise.race([
			promise,
			new Promise((_, reject) => {
				timeout = setTimeout(() => reject(new Error(message)), milliseconds);
			}),
		]);
	} finally {
		clearTimeout(timeout);
	}
}

async function writeTerminalResult({ options, evidence, renderer, scenario, samples, env, workloadEvidence, resourceConfiguration }) {
	const configurationExtra = {};
	if (options.compositing) {
		if (process.platform !== "linux") throw new Error("compositing on/off pairs are a Linux-only measurement");
		configurationExtra.compositingMode = options.compositing;
	}
	if (resourceConfiguration) Object.assign(configurationExtra, resourceConfiguration);
	if (options.scenario === "large-output") {
		assertObservedOutputBytes(workloadEvidence, options.scenario, scenario);
		configurationExtra.observedOutputBytes = Math.max(...workloadEvidence.observedBytes);
	}
	const benchmarkResult = createBenchmarkResult({
		shell: options.shell,
		scenario: options.scenario,
		buildProfile: evidence.buildProfile,
		git: await collectGitMetadata(),
		host: collectHostMetadata(),
		renderer,
		scenarioConfiguration: terminalScenarioConfiguration(scenario, evidence, workloadEvidence, configurationExtra),
		warmups: scenario.warmups,
		samples,
		unit: scenario.unit,
	});
	const outputPath = benchmarkResultPath({
		shell: options.shell,
		scenario: options.scenario,
		variant: terminalResultVariant(env, options.compositing),
	});
	await writeBenchmarkResult(outputPath, benchmarkResult);
	process.stdout.write(`${path.relative(frontendRoot, outputPath)}\n`);
	return benchmarkResult;
}

function totalScenarioIterations(scenario) {
	if (scenario.kind === "memory") return 1;
	const workloadsPerWindow = Math.max(1, Number(scenario.fixedWorkloads ?? 1));
	return scenario.warmups + scenario.samples * workloadsPerWindow;
}

export async function runTerminalBenchmark(argv = process.argv.slice(2), env = process.env) {
	const options = parseTerminalArguments(argv);
	if (options.shell === "tauri" && env.OPERATOR_RUNTIME !== undefined) {
		throw new Error("OPERATOR_RUNTIME selects the benchmark shell's unused daemon, not OPERATOR_BENCH_DAEMON_URL; start the measured daemon with the intended runtime instead");
	}
	const scenarios = JSON.parse(await readFile(scenariosPath, "utf8"));
	const scenario = scenarios[options.scenario];
	if (!scenario) throw new Error(`missing terminal scenario configuration: ${options.scenario}`);
	if (scenario.completionMark !== "operator:terminal-ready" || scenario.transport !== "daemon-terminal-mux") {
		throw new Error("terminal scenario does not require the timestamp-only real-mux acknowledgement");
	}
	if (!existsSync(terminalHarnessPath)) {
		throw new Error("terminal benchmark requires the real-mux acknowledgement harness from Task 4; no result was written");
	}
	if (options.compositing && process.platform !== "linux") {
		throw new Error("compositing on/off pairs are a Linux-only measurement");
	}
	if (options.shell === "tauri") return await runTauriTerminalBenchmark(options, env, scenario);
	return await runElectronTerminalBenchmark(options, env, scenario);
}

export function parsePosixProcessResourceTable(table) {
	const rows = [];
	for (const line of table.trim().split("\n")) {
		const columns = line.trim().split(/\s+/);
		if (columns.length < 4) continue;
		const [processIdColumn, parentProcessIdColumn, residentKilobytesColumn, timeColumn] = columns;
		if (!/^\d+$/.test(processIdColumn) || !/^\d+$/.test(parentProcessIdColumn)) continue;
		if (!/^\d+$/.test(residentKilobytesColumn)) continue;
		const cpuMs = posixTimeColumnToMs(timeColumn);
		if (cpuMs === null) continue;
		rows.push({
			processId: Number(processIdColumn),
			parentProcessId: Number(parentProcessIdColumn),
			bytes: Number(residentKilobytesColumn) * 1024,
			cpuMs,
		});
	}
	return rows;
}

function posixTimeColumnToMs(column) {
	const match = column.match(/^(?:(\d+)-)?(\d{1,3}):(\d{2})(?:\.(\d{1,2}))?$/);
	if (!match) return null;
	const [, days, hours, minutes, fraction] = match;
	let milliseconds = Number(days ?? 0) * 86_400_000 + Number(hours) * 3_600_000 + Number(minutes) * 60_000;
	if (fraction !== undefined) milliseconds += Number(fraction.padEnd(2, "0")) * 10;
	return milliseconds;
}

export function processTreeIds(processes, rootProcessId) {
	const included = new Set([rootProcessId]);
	let changed = true;
	while (changed) {
		changed = false;
		for (const process of processes) {
			if (!included.has(process.processId) && included.has(process.parentProcessId)) {
				included.add(process.processId);
				changed = true;
			}
		}
	}
	return included;
}

export function sumProcessTreeField(processes, rootProcessId, field) {
	const included = processTreeIds(processes, rootProcessId);
	return processes.filter((process) => included.has(process.processId)).reduce((total, process) => total + (Number.isFinite(process[field]) ? process[field] : 0), 0);
}

export function applicationProcessIdFromAncestry(processes, rootProcessId, daemonProcessId) {
	const parentByProcessId = new Map(processes.map((row) => [row.processId, row.parentProcessId]));
	if (!parentByProcessId.has(daemonProcessId)) throw new Error("isolated daemon process was not visible in the observed process table");
	if (!parentByProcessId.has(rootProcessId) && !processes.some((row) => row.processId === rootProcessId)) {
		throw new Error("harness root process was not visible in the observed process table");
	}
	let cursor = daemonProcessId;
	for (;;) {
		const parent = parentByProcessId.get(cursor);
		if (parent === undefined || cursor === parent) throw new Error("launched application ancestry could not be resolved from the observed process table");
		if (parent === rootProcessId) return cursor;
		cursor = parent;
	}
}

async function collectProcessResourceTable(dependencies = {}) {
	const execFileImpl = dependencies.execFile ?? execFileAsync;
	if (process.platform === "win32") {
		const command = "Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,WorkingSetSize,KernelModeTime,UserModeTime | ConvertTo-Json -Compress";
		const { stdout } = await execFileImpl("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command]);
		const decoded = JSON.parse(stdout);
		return (Array.isArray(decoded) ? decoded : [decoded]).map((row) => ({
			processId: Number(row.ProcessId),
			parentProcessId: Number(row.ParentProcessId),
			bytes: Number(row.WorkingSetSize),
			cpuMs: (Number(row.KernelModeTime) + Number(row.UserModeTime)) / 10_000,
		}));
	}
	const { stdout } = await execFileImpl("ps", ["-axo", "pid=,ppid=,rss=,time="]);
	return parsePosixProcessResourceTable(stdout);
}

async function collectProcessTreeCpuMs(rootProcessId, dependencies = {}) {
	const rows = await collectProcessResourceTable(dependencies);
	return sumProcessTreeField(rows, rootProcessId, "cpuMs");
}

async function readDaemonProcessId(stateRoot) {
	const runFile = JSON.parse(await readFile(path.join(stateRoot, "operator", "running.json"), "utf8"));
	const daemonProcessId = Number(runFile.pid);
	if (!Number.isInteger(daemonProcessId) || daemonProcessId <= 0) throw new Error("isolated daemon process identifier unavailable for terminal resource accounting");
	return daemonProcessId;
}

async function resolveTauriApplicationProcessId(stateRoot, rootProcessId, dependencies = {}) {
	const rows = await collectProcessResourceTable(dependencies);
	const daemonProcessId = await readDaemonProcessId(stateRoot);
	return applicationProcessIdFromAncestry(rows, rootProcessId, daemonProcessId);
}

export function cpuTimeSamplesFromWindows(deltas, scenario) {
	const workloadsPerWindow = Math.max(1, Number(scenario.fixedWorkloads ?? 1));
	if (!Array.isArray(deltas) || deltas.length === 0 || deltas.some((delta) => !Number.isFinite(delta))) {
		throw new Error("cpu-time accounting requires finite per-workload CPU deltas");
	}
	const windows = [];
	for (let start = 0; start + workloadsPerWindow <= deltas.length; start += workloadsPerWindow) {
		windows.push(deltas.slice(start, start + workloadsPerWindow).reduce((total, delta) => total + delta, 0) / workloadsPerWindow);
	}
	if (windows.length < scenario.samples) throw new Error(`cpu-time observed ${windows.length} complete workload windows but the scenario requires ${scenario.samples}`);
	return windows;
}

async function waitForElectronFirstPaint(application, page) {
	await page.waitForFunction(() => performance.getEntriesByName("operator:terminal-first-paint", "mark").length > 0, undefined, {
		timeout: 120_000,
	});
	return await terminalRendererMetadata(application, page);
}

async function launchElectronHarness(options, env, stateRoot) {
	const driverPath = path.join(stateRoot, "main.cjs");
	await writeFile(driverPath, electronDriverSource(), "utf8");
	const application = await electron.launch({
		args: [driverPath],
		env: sanitizedBindingEnvironment(env, {
			OPERATOR_BENCH_STATE_ROOT: stateRoot,
			OPERATOR_BENCH_TERMINAL_URL: validatedHarnessUrl(env.OPERATOR_BENCH_TERMINAL_URL),
		}),
		timeout: 120_000,
	});
	const page = await application.firstWindow({ timeout: 120_000 });
	return { application, page };
}

async function runElectronTerminalBenchmark(options, env, scenario) {
	const evidence = terminalEvidenceProfile(env);
	if (options.scenario === "active-memory") return await runElectronActiveMemoryScenario(options, env, scenario, evidence);
	const plan = scenarioMeasurementPlan(options.scenario);
	const primaryName = primaryAcknowledgementNames[options.scenario];
	const stateRoot = await benchmarkStateDirectory("electron");
	let application;
	try {
		application = (await launchElectronHarness(options, env, stateRoot)).application;
		const page = await application.firstWindow({ timeout: 120_000 });
		const renderer = await waitForElectronFirstPaint(application, page);
		const measured = await driveElectronScenarioMeasurements({ application, page, options, scenario, plan, primaryName });
		return await writeTerminalResult({ options, evidence, renderer, scenario, samples: measured.samples, env, workloadEvidence: measured.workloadEvidence, resourceConfiguration: measured.resourceConfiguration });
	} finally {
		if (application) await application.close();
		await removeBenchmarkState(stateRoot);
	}
}

async function runElectronActiveMemoryScenario(options, env, scenario, evidence) {
	const plan = scenarioMeasurementPlan(options.scenario);
	const rendererSnapshot = undefined;
	const samples = [];
	let observedWorkloads = 0;
	for (let launch = 0; launch < scenario.samples; launch += 1) {
		const stateRoot = await benchmarkStateDirectory("electron");
		let application;
		try {
			const launched = await launchElectronHarness(options, env, stateRoot);
			application = launched.application;
			const page = launched.page;
			rendererSnapshot ??= await waitForElectronFirstPaint(application, page);
			for (let iteration = 0; iteration < steadyStateWorkloads(scenario); iteration += 1) {
				await terminalIterationObservation(page, plan, options.scenario, iteration);
				observedWorkloads += 1;
			}
			await new Promise((resolve) => setTimeout(resolve, (scenario.idleSeconds ?? 60) * 1000));
			samples.push((await collectActiveTreeBytes(application.process().pid)).bytes);
		} finally {
			if (application) await application.close();
			await removeBenchmarkState(stateRoot);
		}
	}
	const requiredWorkloads = scenario.samples * steadyStateWorkloads(scenario);
	const workloadEvidence = {
		durations: [],
		observedBytes: [],
		observedWorkloads,
		requiredWorkloads,
		workloadSuccess: observedWorkloads === requiredWorkloads && observedWorkloads > 0,
	};
	return await writeTerminalResult({ options, evidence, renderer: rendererSnapshot, scenario, samples, env, workloadEvidence, resourceConfiguration: { accounting: "launched-application-full-process-tree-at-idle-stability" } });
}

function steadyStateWorkloads(scenario) {
	const count = Number(scenario.steadyStateWorkloads ?? 5);
	if (!Number.isInteger(count) || count < 1) throw new Error("steady-state scenarios require a positive steadyStateWorkloads count");
	return count;
}

async function collectActiveTreeBytes(rootProcessId, dependencies = {}) {
	const rows = await collectProcessResourceTable(dependencies);
	return { bytes: sumProcessTreeField(rows, rootProcessId, "bytes") };
}

async function driveElectronScenarioMeasurements({ application, page, options, scenario, plan, primaryName }) {
	const messages = [];
	const runIteration = async (iteration) => {
		const observation = await terminalIterationObservation(page, plan, options.scenario, iteration);
		messages.push({ name: "workload-start", timestamp: observation.actionTimestamp });
		messages.push({
			name: primaryName,
			timestamp: observation.acknowledgementTimestamp,
			...(typeof observation.observedBytes === "number" ? { bytes: observation.observedBytes } : {}),
		});
		return observation;
	};
	if (options.scenario === "cpu-time") {
		const rootProcessId = application.process().pid;
		const snapshots = [{ cpuMs: await collectProcessTreeCpuMs(rootProcessId), workloads: 0 }];
		let observedWorkloads = 0;
		const total = totalScenarioIterations(scenario);
		for (let iteration = 0; iteration < total; iteration += 1) {
			await runIteration(iteration);
			observedWorkloads += 1;
			snapshots.push({ cpuMs: await collectProcessTreeCpuMs(rootProcessId), workloads: observedWorkloads });
		}
		return {
			samples: cpuTimeSamplesFromWindows(cpuDeltasFromIterationSnapshots(snapshots, { warmups: scenario.warmups }), scenario),
			workloadEvidence: resourceWorkloadEvidence(observedWorkloads, total),
			resourceConfiguration: { fixedWorkloads: Math.max(1, Number(scenario.fixedWorkloads ?? 1)), accounting: "per-workload-process-tree-cpu-deltas" },
		};
	}
	const samples = [];
	for (let iteration = 0; iteration < scenario.warmups + scenario.samples; iteration += 1) {
		const observation = await runIteration(iteration);
		if (iteration >= scenario.warmups) {
			samples.push(terminalThroughputSample(options.scenario, observation.duration, scenario));
		}
	}
	const workloadEvidence = terminalWorkloadEvidence(messages, scenario.warmups + scenario.samples, options.scenario, scenario, primaryName);
	return { samples, workloadEvidence };
}

function resourceWorkloadEvidence(observedWorkloads, requiredWorkloads) {
	return {
		durations: [],
		observedBytes: [],
		observedWorkloads,
		requiredWorkloads,
		workloadSuccess: observedWorkloads === requiredWorkloads && observedWorkloads > 0,
	};
}

async function runTauriTerminalBenchmark(options, env, scenario) {
	const evidence = tauriTerminalEvidenceProfile(env);
	if (options.scenario === "active-memory") return await runTauriActiveMemoryScenario(options, env, scenario, evidence);
	const plan = scenarioMeasurementPlan(options.scenario);
	const primaryName = primaryAcknowledgementNames[options.scenario];
	const expectedPrimaries = totalScenarioIterations(scenario);
	const requireDisposal = true;
	let applicationPidRef = null;
	const cpuSnapshots = [];
	let seenPrimaries = 0;
	const reporter = terminalReporter(expectedPrimaries, {
		primaryName,
		requireDisposal,
		onPrimary: async () => {
			if (options.scenario !== "cpu-time" || applicationPidRef === null) return;
			seenPrimaries += 1;
			cpuSnapshots.push({ cpuMs: await collectProcessTreeCpuMs(applicationPidRef), workloads: seenPrimaries });
		},
	});
	const reportUrl = await reporter.listen();
	let vite;
	let stateRoot;
	let nativeHarness;
	let stopOnSignal;
	try {
		vite = await terminalViteServer(
			(harnessUrl) => tauriHarnessQuery(env, options.scenario, scenario, reportUrl, harnessUrl),
			tauriDaemonUrl(env),
		);
		stateRoot = await benchmarkStateDirectory("tauri");
		nativeHarness = spawnTauriHarness(vite.url, stateRoot, env, options.compositing);
		nativeHarness.application.once("exit", (code, signal) => {
			reporter.fail(new Error(`Tauri terminal harness exited before completion (${code ?? signal ?? "unknown"})${nativeHarness.diagnostic() ? `: ${nativeHarness.diagnostic()}` : ""}`));
		});
		stopOnSignal = () => reporter.fail(new Error("Tauri terminal harness interrupted by a process signal"));
		process.once("SIGINT", stopOnSignal);
		process.once("SIGTERM", stopOnSignal);
		if (options.scenario === "cpu-time") {
			await waitForTauriDaemon(stateRoot);
			applicationPidRef = await resolveTauriApplicationProcessId(stateRoot, nativeHarness.application.pid);
			cpuSnapshots.push({ cpuMs: await collectProcessTreeCpuMs(applicationPidRef), workloads: 0 });
		}
		const timeoutMilliseconds = 120_000 * expectedPrimaries + 120_000;
		const observation = await withinTimeout(
			reporter.completion,
			timeoutMilliseconds,
			"Tauri terminal harness timed out",
		);
		const workloadEvidence = terminalWorkloadEvidence(observation.acknowledgements, expectedPrimaries, options.scenario, scenario, primaryName);
		let samples;
		if (options.scenario === "cpu-time") {
			samples = cpuTimeSamplesFromWindows(cpuDeltasFromIterationSnapshots(cpuSnapshots, { warmups: scenario.warmups }), scenario);
		} else {
			samples = workloadEvidence.durations
				.slice(scenario.warmups)
				.map((duration) => terminalThroughputSample(options.scenario, duration, scenario));
		}
		return await writeTerminalResult({
			options,
			evidence,
			renderer: observation.renderer,
			scenario,
			samples,
			env,
			workloadEvidence,
			resourceConfiguration: options.scenario === "cpu-time"
				? { fixedWorkloads: Math.max(1, Number(scenario.fixedWorkloads ?? 1)), accounting: "per-workload-process-tree-cpu-deltas" }
				: undefined,
		});
	} finally {
		if (stopOnSignal) {
			process.off("SIGINT", stopOnSignal);
			process.off("SIGTERM", stopOnSignal);
		}
		if (nativeHarness) await terminateTauriHarness(nativeHarness.application);
		if (vite) await vite.close();
		await reporter.close();
		if (stateRoot) await removeBenchmarkState(stateRoot);
	}
}

async function runTauriActiveMemoryScenario(options, env, scenario, evidence) {
	const plan = scenarioMeasurementPlan(options.scenario);
	let rendererSnapshot;
	const samples = [];
	let observedWorkloads = 0;
	for (let launch = 0; launch < scenario.samples; launch += 1) {
		const burstCount = steadyStateWorkloads(scenario);
		const reporter = terminalReporter(burstCount, { primaryName: plan.primaryName, requireDisposal: false });
		const reportUrl = await reporter.listen();
		let vite;
		let stateRoot;
		let nativeHarness;
		try {
			vite = await terminalViteServer(
				(harnessUrl) => tauriHarnessQuery(env, options.scenario, { ...scenario, warmups: 0, samples: burstCount }, reportUrl, harnessUrl),
				tauriDaemonUrl(env),
			);
			stateRoot = await benchmarkStateDirectory("tauri");
			nativeHarness = spawnTauriHarness(vite.url, stateRoot, env, options.compositing);
			nativeHarness.application.once("exit", (code, signal) => {
				reporter.fail(new Error(`Tauri terminal harness exited before completion (${code ?? signal ?? "unknown"})${nativeHarness.diagnostic() ? `: ${nativeHarness.diagnostic()}` : ""}`));
			});
			const observation = await withinTimeout(reporter.completion, 120_000 * burstCount + 120_000, "Tauri active-memory harness timed out");
			rendererSnapshot ??= observation.renderer;
			observedWorkloads += burstCount;
			await new Promise((resolve) => setTimeout(resolve, (scenario.idleSeconds ?? 60) * 1000));
			const applicationProcessId = await resolveTauriApplicationProcessId(stateRoot, nativeHarness.application.pid);
			samples.push((await collectActiveTreeBytes(applicationProcessId)).bytes);
		} finally {
			if (nativeHarness) await terminateTauriHarness(nativeHarness.application);
			if (vite) await vite.close();
			await reporter.close();
			if (stateRoot) await removeBenchmarkState(stateRoot);
		}
	}
	const requiredWorkloads = scenario.samples * steadyStateWorkloads(scenario);
	const workloadEvidence = resourceWorkloadEvidence(observedWorkloads, requiredWorkloads);
	return await writeTerminalResult({
		options,
		evidence,
		renderer: rendererSnapshot,
		scenario,
		samples,
		env,
		workloadEvidence,
		resourceConfiguration: { accounting: "launched-application-full-process-tree-at-idle-stability" },
	});
}

async function waitForTauriDaemon(stateRoot, dependencies = {}) {
	const pause = dependencies.pause ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
	const deadline = Date.now() + 120_000;
	while (Date.now() < deadline) {
		try {
			await readFile(path.join(stateRoot, "operator", "running.json"), "utf8");
			return true;
		} catch (error) {
			if (error?.code !== "ENOENT") throw error;
			await pause(500);
		}
	}
	throw new Error("isolated Tauri benchmark daemon did not publish its run file before timeout");
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("node scripts/benchmark-terminal.mjs --shell electron|tauri --scenario vtebench|large-output|input-latency|reconnect|cpu-time|active-memory [--compositing enabled|disabled]\n");
		return;
	}
	await runTerminalBenchmark();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
