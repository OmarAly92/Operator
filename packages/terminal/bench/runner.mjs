import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright";
import { createServer } from "vite";

import { installReportChannel } from "./report-channel.mjs";
import { validateBenchmark } from "./schema.mjs";
import scenarios from "./scenarios.json" with { type: "json" };
import { WORKLOAD_METADATA } from "./workloads.mjs";

const benchDirectory = path.dirname(fileURLToPath(import.meta.url));
const packageDirectory = path.dirname(benchDirectory);
const repositoryDirectory = path.resolve(packageDirectory, "../..");
const scenarioNames = Object.keys(scenarios);

function usage(message) {
	if (message) process.stderr.write(`${message}\n`);
	process.stderr.write("usage: npm run bench:terminal -- --renderer xterm --scenario vtebench|large-output|input-latency\n");
	process.stderr.write("       npm run bench:baseline -- --renderer xterm --record\n");
	process.exit(2);
}

function parseArguments(args) {
	let renderer;
	let scenario;
	let record = false;
	for (let index = 0; index < args.length; index += 1) {
		const argument = args[index];
		if (argument === "--renderer" && renderer === undefined) renderer = args[++index];
		else if (argument === "--scenario" && scenario === undefined) scenario = args[++index];
		else if (argument === "--record" && !record) record = true;
		else usage(`unsupported argument: ${argument}`);
	}
	if (renderer !== "xterm") usage("--renderer must be xterm");
	if (record && scenario !== undefined) usage("--record measures all scenarios and does not accept --scenario");
	if (!record && !scenarioNames.includes(scenario)) usage("--scenario must name a documented scenario");
	return { record, names: record ? scenarioNames : [scenario] };
}

function git(...args) {
	return execFileSync("git", args, {
		cwd: repositoryDirectory,
		encoding: "utf8",
	}).trim();
}

async function rendererVersion() {
	const manifest = JSON.parse(
		await readFile(path.join(packageDirectory, "node_modules/@xterm/xterm/package.json"), "utf8"),
	);
	return manifest.version;
}

function verifyWorkloads(result, names) {
	if (result.renderer !== "xterm") throw new Error("browser returned an unexpected renderer");
	if (result.rendererVersion !== "5.5.0") throw new Error("xterm renderer version must be 5.5.0");
	for (const name of names) {
		const measured = result.scenarios[name];
		if (!measured) throw new Error(`browser omitted ${name}`);
		if (measured.workload !== WORKLOAD_METADATA[name].workload) {
			throw new Error(`${name} workload name changed`);
		}
		if (measured.workloadDigest !== WORKLOAD_METADATA[name].workloadDigest) {
			throw new Error(`${name} workload digest changed`);
		}
		if (measured.configuration.warmups !== 3 || measured.samples.length !== 10) {
			throw new Error(`${name} must contain 3 warmups and 10 samples`);
		}
	}
}

async function runBrowser(names) {
	const server = await createServer({
		configFile: path.join(benchDirectory, "vite.config.ts"),
		logLevel: "error",
	});
	let browser;
	let channel;
	try {
		await server.listen(0);
		const address = server.httpServer?.address();
		if (!address || typeof address === "string") throw new Error("Vite did not bind a loopback port");
		browser = await chromium.launch({ headless: true });
		const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
		channel = await installReportChannel(page);
		const [, measured] = await Promise.all([
			page.goto(`http://127.0.0.1:${address.port}/?scenarios=${names.join(",")}`),
			channel.result,
		]);
		return {
			measured,
			browserVersion: browser.version(),
		};
	} finally {
		channel?.dispose();
		await browser?.close();
		await server.close();
	}
}

async function writeResult(result, record) {
	const json = `${JSON.stringify(result, null, "\t")}\n`;
	const resultsDirectory = path.join(benchDirectory, "results");
	await mkdir(resultsDirectory, { recursive: true });
	const stamp = result.recordedAt.replaceAll(":", "-");
	const resultPath = path.join(resultsDirectory, `${stamp}-${result.renderer}.json`);
	await writeFile(resultPath, json);
	process.stdout.write(`wrote ${path.relative(packageDirectory, resultPath)}\n`);
	if (record) {
		const baselinePath = path.join(
			benchDirectory,
			"baselines",
			`${result.platform}-${result.architecture}-${result.renderer}.json`,
		);
		await mkdir(path.dirname(baselinePath), { recursive: true });
		await writeFile(baselinePath, json);
		process.stdout.write(`recorded ${path.relative(packageDirectory, baselinePath)}\n`);
	}
}

const { record, names } = parseArguments(process.argv.slice(2));
if (record && git("status", "--porcelain", "--untracked-files=all") !== "") {
	throw new Error("refusing to record a baseline from a dirty git tree");
}
if (record && names.length !== 3) throw new Error("baseline recording requires all three scenarios");
if (await rendererVersion() !== "5.5.0") throw new Error("installed xterm version must be exactly 5.5.0");

const { measured, browserVersion } = await runBrowser(names);
verifyWorkloads(measured, names);
const cpus = os.cpus();
const result = {
	schema: "operator.terminal-benchmark.v1",
	recordedAt: new Date().toISOString(),
	commit: git("rev-parse", "HEAD"),
	platform: os.platform(),
	architecture: os.arch(),
	cpu: cpus[0]?.model ?? "unknown",
	logicalCores: cpus.length,
	physicalMemory: os.totalmem(),
	browserVersion,
	displayScale: measured.displayScale,
	renderer: measured.renderer,
	rendererVersion: measured.rendererVersion,
	rendererKind: measured.rendererKind,
	scenarios: measured.scenarios,
};
validateBenchmark(result);
await writeResult(result, record);
