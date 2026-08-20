import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { _electron as electron } from "playwright";
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
const terminalScenarios = new Set(["vtebench", "large-output"]);

export function parseTerminalArguments(argv) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron") throw new Error("Task 2 supports only electron terminal measurements");
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

async function benchmarkStateDirectory() {
	const parent = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(parent, { recursive: true });
	return await mkdtemp(path.join(parent, "electron-terminal-"));
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

export async function runTerminalBenchmark(argv = process.argv.slice(2), env = process.env) {
	const options = parseTerminalArguments(argv);
	const evidence = terminalEvidenceProfile(env);
	const scenarios = JSON.parse(await readFile(scenariosPath, "utf8"));
	const scenario = scenarios[options.scenario];
	if (scenario.completionMark !== "operator:terminal-ready" || scenario.transport !== "daemon-terminal-mux") {
		throw new Error("terminal scenario does not require the timestamp-only real-mux acknowledgement");
	}
	if (!existsSync(terminalHarnessPath)) {
		throw new Error("terminal benchmark requires the real-mux acknowledgement harness from Task 4; no result was written");
	}
	const harnessUrl = validatedHarnessUrl(env.OPERATOR_BENCH_TERMINAL_URL);
	const stateRoot = await benchmarkStateDirectory();
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
		await page.waitForFunction(() => performance.getEntriesByName("operator:terminal-ready", "mark").length > 0, undefined, {
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
			samples: throughputSamples,
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
	} finally {
		if (application) await application.close();
		await rm(stateRoot, { recursive: true, force: true });
	}
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("OPERATOR_BENCH_TERMINAL_URL=... node scripts/benchmark-terminal.mjs --shell electron --scenario vtebench|large-output\n");
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
