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
	scenarioResultConfiguration,
	writeBenchmarkResult,
} from "./benchmark-result.mjs";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const scenariosPath = fileURLToPath(new URL("../perf/scenarios.json", import.meta.url));
const terminalHarnessPath = fileURLToPath(new URL("../perf/terminal/index.html", import.meta.url));
const terminalViteConfigPath = fileURLToPath(new URL("../vite.terminal-perf.config.ts", import.meta.url));
const tauriCliPath = fileURLToPath(new URL("../node_modules/@tauri-apps/cli/tauri.js", import.meta.url));
const terminalScenarios = new Set(["vtebench", "large-output"]);
const execFileAsync = promisify(execFile);
const terminalAcknowledgementNames = new Set([
	"first-paint",
	"workload-start",
	"workload",
	"resize",
	"reconnect",
	"renderer-recovery",
	"disposal",
]);

export function parseTerminalArguments(argv) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron" && namedArguments.shell !== "tauri") {
		throw new Error("terminal benchmark supports only electron and tauri webviews");
	}
	if (!terminalScenarios.has(namedArguments.scenario)) {
		throw new Error(`unsupported terminal scenario: ${namedArguments.scenario ?? ""}`);
	}
	if (Object.keys(namedArguments).some((key) => key !== "shell" && key !== "scenario")) {
		throw new Error("unknown terminal benchmark argument");
	}
	return { shell: namedArguments.shell, scenario: namedArguments.scenario };
}

export function terminalThroughputSample(scenario, durationMilliseconds, configuration) {
	if (!Number.isFinite(durationMilliseconds) || durationMilliseconds <= 0) throw new Error("terminal benchmark requires a positive acknowledgement duration");
	const seconds = durationMilliseconds / 1000;
	if (scenario === "vtebench") return 1 / seconds;
	if (scenario === "large-output") return configuration.outputBytes / seconds;
	throw new Error(`unsupported terminal scenario: ${scenario}`);
}

export function terminalEvidenceProfile(env) {
	if (env.OPERATOR_BENCH_BUILD_PROFILE && env.OPERATOR_BENCH_BUILD_PROFILE !== "local-electron-webview-non-binding") {
		throw new Error("Task 2 terminal runner cannot produce binding release evidence without an attested installed Electron runtime");
	}
	return {
		buildProfile: "local-electron-webview-non-binding",
		evidenceScope: "non-binding",
		runtimeAttestation: "npm-electron-driver",
	};
}

export function tauriTerminalEvidenceProfile(env) {
	if (env.OPERATOR_BENCH_BUILD_PROFILE && env.OPERATOR_BENCH_BUILD_PROFILE !== "local-tauri-webview-non-binding") {
		throw new Error("Task 4 terminal runner cannot produce binding release evidence without an attested installed Tauri runtime");
	}
	return {
		buildProfile: "local-tauri-webview-non-binding",
		evidenceScope: "non-binding",
		runtimeAttestation: "tauri-dev-webview",
	};
}

export function terminalAcknowledgementDurations(messages) {
	if (!Array.isArray(messages)) throw new Error("terminal acknowledgements must be an array");
	for (const message of messages) assertTerminalAcknowledgement(message);
	const durations = [];
	let workloadStart;
	for (const message of [...messages].sort((left, right) => left.timestamp - right.timestamp)) {
		if (message.name === "workload-start") {
			if (workloadStart !== undefined) throw new Error("terminal workload acknowledgements are out of order");
			workloadStart = message.timestamp;
		}
		if (message.name === "workload") {
			if (workloadStart === undefined || message.timestamp <= workloadStart) {
				throw new Error("terminal workload acknowledgements are out of order");
			}
			durations.push(message.timestamp - workloadStart);
			workloadStart = undefined;
		}
	}
	if (workloadStart !== undefined) throw new Error("terminal workload acknowledgement is incomplete");
	return durations;
}

function assertTerminalAcknowledgement(message) {
	if (
		!message ||
		typeof message !== "object" ||
		Array.isArray(message) ||
		Object.keys(message).sort().join(",") !== "name,timestamp" ||
		!terminalAcknowledgementNames.has(message.name) ||
		!Number.isFinite(message.timestamp) ||
		message.timestamp < 0
	) {
		throw new Error("terminal acknowledgements must contain only a name and timestamp");
	}
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

async function terminalAcknowledgementDuration(page, scenario, iteration) {
	const actionTimestamp = await page.evaluate(
		({ benchmarkScenario, benchmarkIteration }) => {
			performance.clearMarks("operator:terminal-ready");
			const timestamp = performance.now();
			window.dispatchEvent(
				new CustomEvent("operator:terminal-benchmark-run", {
					detail: { scenario: benchmarkScenario, iteration: benchmarkIteration },
				}),
			);
			return timestamp;
		},
		{ benchmarkScenario: scenario, benchmarkIteration: iteration },
	);
	await page.waitForFunction(
		({ markName, after }) => performance.getEntriesByName(markName, "mark").some((entry) => entry.startTime > after),
		{ markName: "operator:terminal-ready", after: actionTimestamp },
		{ timeout: 120_000 },
	);
	const acknowledgement = await page.evaluate((after) => {
		const entry = performance
			.getEntriesByName("operator:terminal-ready", "mark")
			.filter((candidate) => candidate.startTime > after)
			.at(-1);
		if (!entry) throw new Error("terminal acknowledgement mark missing");
		if ("detail" in entry && entry.detail !== null) throw new Error("terminal acknowledgement mark must contain a timestamp only");
		return entry.startTime;
	}, actionTimestamp);
	return acknowledgement - actionTimestamp;
}

async function terminalRendererMetadata(application, page) {
	const versions = await application.evaluate(() => ({ electron: process.versions.electron, chromium: process.versions.chrome }));
	const rendererKind = await page.evaluate(
		() => document.querySelector("[data-terminal-renderer-kind]")?.getAttribute("data-terminal-renderer-kind"),
	);
	if (rendererKind !== "webgl" && rendererKind !== "canvas") throw new Error("terminal harness did not report webgl|canvas renderer kind");
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
		!["webgl", "canvas"].includes(message.rendererKind) ||
		typeof message.webviewRuntimeVersion !== "string" ||
		message.webviewRuntimeVersion.trim() === "" ||
		!Number.isFinite(message.displayScale) ||
		message.displayScale <= 0
	) {
		throw new Error("terminal renderer metadata is invalid");
	}
}

function terminalReporter(expectedWorkloads) {
	const route = `/terminal-benchmark/${randomUUID()}`;
	const acknowledgements = [];
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
	const record = (message) => {
		if (message?.name === "renderer") {
			assertRendererMessage(message);
			renderer = {
				displayScale: message.displayScale,
				rendererKind: message.rendererKind,
				webviewRuntimeVersion: message.webviewRuntimeVersion,
			};
		} else {
			assertTerminalAcknowledgement(message);
			acknowledgements.push(message);
		}
		const workloads = acknowledgements.filter((message) => message.name === "workload").length;
		const disposed = acknowledgements.some((message) => message.name === "disposal");
		if (!settled && renderer && workloads === expectedWorkloads && disposed) {
			settled = true;
			resolveCompletion({ acknowledgements, renderer });
		}
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

async function terminalViteServer(query) {
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
		server: { host: "127.0.0.1", port: 0, strictPort: false },
	});
	await vite.listen();
	const address = vite.httpServer?.address();
	if (!address || typeof address === "string") {
		await vite.close();
		throw new Error("terminal benchmark Vite server did not bind a TCP port");
	}
	return { url: `http://127.0.0.1:${address.port}`, close: () => vite.close() };
}

function tauriHarnessQuery(env, scenarioName, scenario, reportUrl) {
	return new URLSearchParams({
		daemonBaseUrl: tauriDaemonUrl(env),
		sessionId: requiredTauriInput(env, "OPERATOR_BENCH_SESSION_ID"),
		terminalId: requiredTauriInput(env, "OPERATOR_BENCH_TERMINAL_ID"),
		scenario: scenarioName,
		warmups: String(scenario.warmups),
		samples: String(scenario.samples),
		reportUrl,
	}).toString();
}

function spawnTauriHarness(harnessUrl, stateRoot, env) {
	const config = JSON.stringify({ build: { beforeDevCommand: "", devUrl: harnessUrl } });
	const application = spawn(
		process.execPath,
		[tauriCliPath, "dev", "--no-watch", "--no-dev-server-wait", "--config", config],
		{
			cwd: frontendRoot,
			detached: process.platform !== "win32",
			env: {
				...process.env,
				...env,
				OPERATOR_DATA_DIR: path.join(stateRoot, "operator", "data"),
				OPERATOR_TAURI_TERMINAL_BENCHMARK: "1",
			},
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

async function writeTerminalResult({ options, evidence, renderer, scenario, samples, env }) {
	const benchmarkResult = createBenchmarkResult({
		shell: options.shell,
		scenario: options.scenario,
		buildProfile: evidence.buildProfile,
		git: await collectGitMetadata(),
		host: collectHostMetadata(),
		renderer,
		scenarioConfiguration: {
			...scenarioResultConfiguration(scenario),
			evidenceScope: evidence.evidenceScope,
			runtimeAttestation: evidence.runtimeAttestation,
		},
		warmups: scenario.warmups,
		samples,
		unit: scenario.unit,
	});
	const outputPath = benchmarkResultPath({
		shell: options.shell,
		scenario: options.scenario,
		variant: env.OPERATOR_BENCH_VARIANT,
	});
	await writeBenchmarkResult(outputPath, benchmarkResult);
	process.stdout.write(`${path.relative(frontendRoot, outputPath)}\n`);
	return benchmarkResult;
}

export async function runTerminalBenchmark(argv = process.argv.slice(2), env = process.env) {
	const options = parseTerminalArguments(argv);
	const scenarios = JSON.parse(await readFile(scenariosPath, "utf8"));
	const scenario = scenarios[options.scenario];
	if (scenario.completionMark !== "operator:terminal-ready" || scenario.transport !== "daemon-terminal-mux") {
		throw new Error("terminal scenario does not require the timestamp-only real-mux acknowledgement");
	}
	if (!existsSync(terminalHarnessPath)) {
		throw new Error("terminal benchmark requires the real-mux acknowledgement harness from Task 4; no result was written");
	}
	if (options.shell === "tauri") return await runTauriTerminalBenchmark(options, env, scenario);
	return await runElectronTerminalBenchmark(options, env, scenario);
}

async function runElectronTerminalBenchmark(options, env, scenario) {
	const evidence = terminalEvidenceProfile(env);
	const harnessUrl = validatedHarnessUrl(env.OPERATOR_BENCH_TERMINAL_URL);
	const stateRoot = await benchmarkStateDirectory("electron");
	const driverPath = path.join(stateRoot, "main.cjs");
	await writeFile(driverPath, electronDriverSource(), "utf8");
	let application;
	try {
		application = await electron.launch({
			args: [driverPath],
			env: {
				...process.env,
				OPERATOR_BENCH_STATE_ROOT: stateRoot,
				OPERATOR_BENCH_TERMINAL_URL: harnessUrl,
			},
			timeout: 120_000,
		});
		const page = await application.firstWindow({ timeout: 120_000 });
		await page.waitForFunction(() => performance.getEntriesByName("operator:terminal-first-paint", "mark").length > 0, undefined, {
			timeout: 120_000,
		});
		const renderer = await terminalRendererMetadata(application, page);
		const throughputSamples = [];
		for (let iteration = 0; iteration < scenario.warmups + scenario.samples; iteration += 1) {
			const duration = await terminalAcknowledgementDuration(page, options.scenario, iteration);
			if (iteration >= scenario.warmups) {
				throughputSamples.push(terminalThroughputSample(options.scenario, duration, scenario));
			}
		}
		return await writeTerminalResult({ options, evidence, renderer, scenario, samples: throughputSamples, env });
	} finally {
		if (application) await application.close();
		await removeBenchmarkState(stateRoot);
	}
}

async function runTauriTerminalBenchmark(options, env, scenario) {
	const evidence = tauriTerminalEvidenceProfile(env);
	const expectedWorkloads = scenario.warmups + scenario.samples;
	const reporter = terminalReporter(expectedWorkloads);
	const reportUrl = await reporter.listen();
	let vite;
	let stateRoot;
	let nativeHarness;
	let stopOnSignal;
	try {
		const query = tauriHarnessQuery(env, options.scenario, scenario, reportUrl);
		vite = await terminalViteServer(query);
		stateRoot = await benchmarkStateDirectory("tauri");
		nativeHarness = spawnTauriHarness(vite.url, stateRoot, env);
		nativeHarness.application.once("exit", (code, signal) => {
			reporter.fail(new Error(`Tauri terminal harness exited before completion (${code ?? signal ?? "unknown"})${nativeHarness.diagnostic() ? `: ${nativeHarness.diagnostic()}` : ""}`));
		});
		stopOnSignal = () => reporter.fail(new Error("Tauri terminal harness interrupted by a process signal"));
		process.once("SIGINT", stopOnSignal);
		process.once("SIGTERM", stopOnSignal);
		const timeoutMilliseconds = 120_000 * expectedWorkloads + 120_000;
		const observation = await withinTimeout(
			reporter.completion,
			timeoutMilliseconds,
			"Tauri terminal harness timed out",
		);
		const durations = terminalAcknowledgementDurations(observation.acknowledgements);
		if (durations.length !== expectedWorkloads) throw new Error("Tauri terminal harness returned an incomplete sample set");
		const throughputSamples = durations
			.slice(scenario.warmups)
			.map((duration) => terminalThroughputSample(options.scenario, duration, scenario));
		return await writeTerminalResult({
			options,
			evidence,
			renderer: observation.renderer,
			scenario,
			samples: throughputSamples,
			env,
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

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("node scripts/benchmark-terminal.mjs --shell electron|tauri --scenario vtebench|large-output\n");
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
