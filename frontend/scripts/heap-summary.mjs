import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";
import {
	collectGitMetadata,
	collectHostMetadata,
	parseNamedArguments,
	sanitizedBindingEnvironment,
	summarizeSamples,
} from "./benchmark-result.mjs";
import { assertNoAbsolutePaths } from "./route-bundle-report.mjs";

const execFileAsync = promisify(execFile);
const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const distRoot = path.join(frontendRoot, "dist");
const debugBinaryPath = path.join(frontendRoot, "src-tauri", "target", "debug", "operator");
const releaseBinaryPath = path.join(frontendRoot, "src-tauri", "target", "release", "operator");
const daemonBinaryPath = path.join(frontendRoot, "daemon", process.platform === "win32" ? "opr.exe" : "opr");
const terminalPerfConfigPath = fileURLToPath(new URL("../vite.terminal-perf.config.ts", import.meta.url));
const heapReportRoot = path.join(frontendRoot, "perf", "results", "heap");
const devUrlPort = 5173;
export const HEAP_SCHEMA_VERSION = 1;
export const HEAP_LABELS = Object.freeze(["before", "after"]);
export const PROBE_KINDS = Object.freeze(["empty-board", "terminal-disposal"]);

const STATIC_CONTENT_TYPES = new Map([
	[".html", "text/html"],
	[".js", "text/javascript"],
	[".css", "text/css"],
	[".json", "application/json"],
	[".svg", "image/svg+xml"],
	[".png", "image/png"],
	[".woff2", "font/woff2"],
	[".txt", "text/plain"],
]);

export function parsePosixProcessTable(table) {
	return String(table)
		.trim()
		.split("\n")
		.map((line) => line.trim().split(/\s+/).map(Number))
		.filter(([processId, parentProcessId, residentKilobytes]) =>
			[processId, parentProcessId, residentKilobytes].every(Number.isFinite),
		)
		.map(([processId, parentProcessId, residentKilobytes]) => ({
			processId,
			parentProcessId,
			rssBytes: residentKilobytes * 1024,
		}));
}

export function processTreeIds(rows, rootProcessId) {
	const included = new Set();
	if (!rows.some((row) => row.processId === rootProcessId)) return included;
	included.add(rootProcessId);
	let changed = true;
	while (changed) {
		changed = false;
		for (const row of rows) {
			if (included.has(row.processId)) continue;
			if (included.has(row.parentProcessId)) {
				included.add(row.processId);
				changed = true;
			}
		}
	}
	return included;
}

function subtreeBytes(rows, rootProcessId) {
	const included = processTreeIds(rows, rootProcessId);
	return rows
		.filter((row) => included.has(row.processId))
		.reduce((total, row) => total + row.rssBytes, 0);
}

export function subtreeTotalBytes(rows, rootProcessId) {
	if (!rows.some((row) => row.processId === rootProcessId)) {
		throw new Error("shell root process is missing from the sampled process table");
	}
	return subtreeBytes(rows, rootProcessId);
}

export function shellVsDaemonBytes(rows, shellRootProcessId, daemonProcessId) {
	const shellTree = processTreeIds(rows, shellRootProcessId);
	if (shellTree.size === 0) throw new Error("shell root process is missing from the sampled process table");
	if (!shellTree.has(daemonProcessId)) throw new Error("daemon is not a descendant of the shell root process");
	return {
		shellBytes: subtreeBytes(rows, shellRootProcessId) - subtreeBytes(rows, daemonProcessId),
		daemonBytes: subtreeBytes(rows, daemonProcessId),
	};
}

async function samplePosixProcessTable() {
	const { stdout } = await execFileAsync("ps", ["-axo", "pid=,ppid=,rss="]);
	return parsePosixProcessTable(stdout);
}

export function retentionSummary({ baselineBytes, cycleBytes }) {
	if (!Array.isArray(cycleBytes) || cycleBytes.length === 0 || cycleBytes.some((value) => !Number.isFinite(value))) {
		throw new Error("retention evidence requires at least one finite post-cycle byte sample");
	}
	const deltas = cycleBytes.map((value) => value - baselineBytes);
	return { baselineBytes, cycleBytes, deltas, maxRetainedDelta: Math.max(...deltas) };
}

export function validateDisposalAcks(acks, expectedCycles) {
	if (!Array.isArray(acks)) throw new Error("disposal acknowledgements must be an array");
	if (acks.length !== expectedCycles) {
		throw new Error(`disposal acknowledgements are incomplete: expected ${expectedCycles}, observed ${acks.length}`);
	}
	for (const ack of acks) {
		if (!ack || typeof ack !== "object" || !Number.isFinite(ack.timestamp)) {
			throw new Error("each disposal acknowledgement must carry a finite timestamp");
		}
	}
	for (let index = 1; index < acks.length; index += 1) {
		if (!(acks[index].timestamp > acks[index - 1].timestamp)) {
			throw new Error("disposal acknowledgements must arrive with strictly increasing timestamps");
		}
	}
	return acks;
}

function baseResultMetadata({ label, git, host, buildKind, webviewRuntimeVersion }) {
	if (!HEAP_LABELS.includes(label)) throw new Error(`label must be one of ${HEAP_LABELS.join("|")}`);
	return {
		schemaVersion: HEAP_SCHEMA_VERSION,
		label,
		commit: git.commit,
		dirty: git.dirty,
		platform: host.platform,
		architecture: host.architecture,
		osVersion: host.osVersion,
		cpu: host.cpu,
		logicalCores: host.logicalCores,
		buildKind,
		webviewRuntimeVersion,
		unit: "bytes",
	};
}

export function buildEmptyBoardResult({
	label,
	git,
	host,
	buildKind,
	webviewRuntimeVersion,
	idleSeconds,
	samples,
	daemonSamples,
}) {
	const summary = summarizeSamples(samples);
	const daemonSummary = summarizeSamples(daemonSamples);
	return validateHeapResultSchema({
		...baseResultMetadata({ label, git, host, buildKind, webviewRuntimeVersion }),
		probeKind: "empty-board",
		accounting: "tauri-shell-plus-webview-process-tree-excluding-daemon",
		scenarioConfiguration: {
			idleSeconds,
			daemonAccounting: "isolated-go-daemon-process-tree-reported-separately",
		},
		samples,
		median: summary.median,
		p95: summary.p95,
		daemonSamples,
		daemonMedian: daemonSummary.median,
	});
}

export function buildDisposalResult({
	label,
	git,
	host,
	buildKind,
	webviewRuntimeVersion,
	cycles,
	disposalBytesPerCycle,
	baselineBytes,
	cycleBytes,
	acks,
}) {
	const summary = summarizeSamples(cycleBytes);
	const validatedAcks = validateDisposalAcks(acks, cycleBytes.length);
	return validateHeapResultSchema({
		...baseResultMetadata({ label, git, host, buildKind, webviewRuntimeVersion }),
		probeKind: "terminal-disposal",
		accounting: "tauri-process-tree-rss-per-disposal-cycle-excluding-daemon",
		scenarioConfiguration: {
			configuredCycles: cycles,
			disposalBytesPerCycle,
			disposalAckCount: validatedAcks.length,
		},
		samples: cycleBytes,
		median: summary.median,
		p95: summary.p95,
		retention: {
			...retentionSummary({ baselineBytes, cycleBytes }),
			cycleCount: cycleBytes.length,
			disposalAckCount: validatedAcks.length,
			disposalTimestamps: validatedAcks.map((ack) => ack.timestamp),
		},
	});
}

export function validateHeapResultSchema(result) {
	if (!result || typeof result !== "object") throw new Error("heap result must be an object");
	for (const field of [
		"schemaVersion",
		"label",
		"commit",
		"dirty",
		"platform",
		"architecture",
		"osVersion",
		"cpu",
		"logicalCores",
		"buildKind",
		"webviewRuntimeVersion",
		"unit",
		"probeKind",
		"accounting",
		"scenarioConfiguration",
		"samples",
		"median",
		"p95",
	]) {
		if (!(field in result)) throw new Error(`heap result is missing field: ${field}`);
	}
	if (result.schemaVersion !== HEAP_SCHEMA_VERSION) throw new Error("schemaVersion must equal 1");
	if (!HEAP_LABELS.includes(result.label)) throw new Error(`label must be one of ${HEAP_LABELS.join("|")}`);
	if (!/^[0-9a-f]{40}$/i.test(result.commit)) throw new Error("commit must be a full Git object ID");
	if (typeof result.dirty !== "boolean") throw new Error("dirty must be a boolean");
	for (const field of ["platform", "architecture", "osVersion", "cpu", "buildKind", "webviewRuntimeVersion", "unit", "probeKind", "accounting"]) {
		if (typeof result[field] !== "string" || result[field].trim() === "") {
			throw new Error(`${field} must be a non-empty string`);
		}
	}
	if (!Number.isInteger(result.logicalCores) || result.logicalCores <= 0) throw new Error("logicalCores must be positive");
	const summary = summarizeSamples(result.samples);
	if (result.median !== summary.median) throw new Error(`median must equal ${summary.median}`);
	if (result.p95 !== summary.p95) throw new Error(`p95 must equal ${summary.p95}`);
	if (!result.scenarioConfiguration || typeof result.scenarioConfiguration !== "object") {
		throw new Error("scenarioConfiguration must be an object");
	}
	if (result.probeKind === "empty-board") {
		for (const field of ["daemonSamples", "daemonMedian"]) {
			if (!(field in result)) throw new Error(`empty-board heap result is missing field: ${field}`);
		}
		const daemonSummary = summarizeSamples(result.daemonSamples);
		if (result.daemonMedian !== daemonSummary.median) {
			throw new Error(`daemonMedian must equal ${daemonSummary.median}`);
		}
	} else if (result.probeKind === "terminal-disposal") {
		const retention = result.retention;
		if (!retention || typeof retention !== "object") throw new Error("terminal-disposal requires retention evidence");
		for (const field of ["baselineBytes", "deltas", "maxRetainedDelta", "cycleCount", "disposalAckCount"]) {
			if (!(field in retention)) throw new Error(`retention is missing field: ${field}`);
		}
		if (retention.cycleCount !== result.samples.length) throw new Error("retention.cycleCount must match samples length");
		if (retention.deltas.length !== result.samples.length) throw new Error("retention.deltas must match samples length");
		if (retention.maxRetainedDelta !== Math.max(...retention.deltas)) throw new Error("maxRetainedDelta mismatch");
		if (!Number.isInteger(retention.disposalAckCount) || retention.disposalAckCount < 1) {
			throw new Error("disposal acknowledgements are required for terminal-disposal evidence");
		}
	} else {
		throw new Error(`unknown probeKind: ${result.probeKind}`);
	}
	assertNoAbsolutePaths(result, "heap result");
	return result;
}

async function availableTcpPort() {
	return await new Promise((resolve, reject) => {
		const server = net.createServer();
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			const address = server.address();
			server.close((error) => (error ? reject(error) : resolve(address.port)));
		});
	});
}

async function waitForDaemonReady(port, timeoutMilliseconds = 120_000) {
	const deadline = Date.now() + timeoutMilliseconds;
	while (Date.now() <= deadline) {
		try {
			const response = await fetch(`http://127.0.0.1:${port}/readyz`);
			const payload = response.ok ? await response.json() : undefined;
			if (payload?.status === "ready" && payload?.service === "operator-daemon") return;
		} catch {
			// retry until the deadline
		}
		await new Promise((resolve) => setTimeout(resolve, 100));
	}
	throw new Error("tauri probe daemon did not report ready before the timeout");
}

async function readRunningPid(runningFilePath) {
	const runFile = JSON.parse(await readFile(runningFilePath, "utf8"));
	if (!Number.isInteger(runFile.pid) || runFile.pid <= 0) {
		throw new Error("isolated daemon pid unavailable in the probe running file");
	}
	return runFile.pid;
}

function terminateProcessGroup(child) {
	return new Promise((resolve) => {
		if (!child || child.exitCode !== null || child.signalCode !== null) return resolve();
		if (process.platform === "win32") {
			execFileAsync("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"]).catch(() => undefined);
			return resolve();
		}
		try {
			process.kill(-child.pid, "SIGTERM");
		} catch {
			return resolve();
		}
		const timer = setTimeout(() => {
			try {
				process.kill(-child.pid, "SIGKILL");
			} catch {
				// already gone
			}
			resolve();
		}, 5_000);
		child.once("exit", () => {
			clearTimeout(timer);
			resolve();
		});
	});
}

function staticFileServer(root) {
	const server = http.createServer(async (request, response) => {
		try {
			const url = new URL(request.url, "http://127.0.0.1");
			const relative = decodeURIComponent(url.pathname).replace(/^\/+/, "");
			const resolved = path.join(root, relative || "index.html");
			if (!resolved.startsWith(root)) {
				response.writeHead(403).end();
				return;
			}
			const body = await readFile(resolved);
			response.writeHead(200, {
				"content-type": STATIC_CONTENT_TYPES.get(path.extname(resolved)) ?? "application/octet-stream",
			});
			response.end(body);
		} catch {
			response.writeHead(404).end();
		}
	});
	return {
		listen: async () => {
			await new Promise((resolve, reject) => {
				server.once("error", reject);
				server.listen(devUrlPort, "127.0.0.1", resolve);
			});
		},
		close: async () => {
			if (!server.listening) return;
			await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
		},
	};
}

function resolveProbeBinary(requestedBuild) {
	if (requestedBuild === "release") {
		if (!existsSync(releaseBinaryPath)) throw new Error("no release tauri binary found; run npm run tauri:build -- --no-bundle");
		return { binaryPath: releaseBinaryPath, buildKind: "release-embedded-assets", serveDist: false };
	}
	if (!existsSync(debugBinaryPath)) throw new Error(`no local tauri binary found; build one first (${debugBinaryPath})`);
	return { binaryPath: debugBinaryPath, buildKind: "debug-devurl", serveDist: true };
}

function controlledProbeEnvironment(stateRoot, daemonPort, { benchmarkMode = false } = {}) {
	return sanitizedBindingEnvironment(process.env, {
		OPERATOR_DATA_DIR: path.join(stateRoot, "data"),
		OPERATOR_RUN_FILE: path.join(stateRoot, "running.json"),
		OPERATOR_PORT: String(daemonPort),
		OPERATOR_KEEP_DAEMON: "0",
		// Benchmark mode registers the harness-only IPC surface
		// (terminal_benchmark_runtime_identity); it also stops the shell from
		// auto-spawning its daemon, so only the disposal probe uses it.
		...(benchmarkMode
			? {
				OPERATOR_TAURI_TERMINAL_BENCHMARK: "1",
				OPERATOR_TAURI_TERMINAL_BENCHMARK_URL: `http://127.0.0.1:${devUrlPort}`,
			}
			: {}),
		...(existsSync(daemonBinaryPath) ? { OPERATOR_DAEMON_COMMAND: `${daemonBinaryPath} daemon` } : {}),
	});
}

function spawnTauriApplication(binaryPath, environment) {
	return spawn(binaryPath, [], {
		detached: process.platform !== "win32",
		env: environment,
		stdio: ["ignore", "ignore", "pipe"],
	});
}

async function createMessageCollector(route) {
	const messages = [];
	const server = http.createServer((request, response) => {
		response.setHeader("access-control-allow-origin", "*");
		if (request.method !== "POST" || !request.url.startsWith(route)) {
			response.writeHead(404).end();
			return;
		}
		let body = "";
		request.setEncoding("utf8");
		request.on("data", (chunk) => {
			body += chunk;
			if (body.length > 16_384) request.destroy();
		});
		request.on("end", () => {
			try {
				const message = JSON.parse(body);
				if (message && typeof message === "object" && typeof message.name === "string") messages.push(message);
				response.writeHead(204).end();
			} catch {
				response.writeHead(400).end();
			}
		});
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", resolve);
	});
	const url = `http://127.0.0.1:${server.address().port}${route}`;
	return {
		url,
		messages,
		waitForCount: async (name, count, timeoutMilliseconds) => {
			const deadline = Date.now() + timeoutMilliseconds;
			while (Date.now() < deadline) {
				const observed = messages.filter((message) => message.name === name);
				if (observed.length >= count) return observed;
				await new Promise((resolve) => setTimeout(resolve, 100));
			}
			throw new Error(`collector timed out waiting for ${count} "${name}" messages`);
		},
		close: async () => {
			if (!server.listening) return;
			await new Promise((resolve) => server.close(resolve));
		},
	};
}

async function runEmptyBoardProbe(options) {
	const probe = resolveProbeBinary(process.env.OPERATOR_HEAP_BUILD === "release" ? "release" : "debug");
	if (probe.serveDist && !existsSync(distRoot)) {
		throw new Error("frontend/dist is missing; build the renderer before measuring (npm exec -- vite build --config vite.renderer.config.ts)");
	}
	const git = await collectGitMetadata();
	const host = collectHostMetadata();
	const server = probe.serveDist ? staticFileServer(distRoot) : undefined;
	const shellSamples = [];
	const daemonSamples = [];
	try {
		if (server) await server.listen();
		for (let index = 0; index < options.samples; index += 1) {
			const stateRoot = await mkdtemp(path.join(os.tmpdir(), "operator-heap-empty-"));
			const daemonPort = await availableTcpPort();
			const application = spawnTauriApplication(probe.binaryPath, controlledProbeEnvironment(stateRoot, daemonPort));
			try {
				await waitForDaemonReady(daemonPort);
				await new Promise((resolve) => setTimeout(resolve, options.idleSeconds * 1000));
				const daemonPid = await readRunningPid(path.join(stateRoot, "running.json"));
				const { shellBytes, daemonBytes } = shellVsDaemonBytes(
					await samplePosixProcessTable(),
					application.pid,
					daemonPid,
				);
				shellSamples.push(shellBytes);
				daemonSamples.push(daemonBytes);
			} finally {
				await terminateProcessGroup(application);
				await rm(stateRoot, { recursive: true, force: true });
			}
			process.stdout.write(
				`empty-board sample ${index + 1}/${options.samples}: shell=${shellSamples.at(-1)} daemon=${daemonSamples.at(-1)}\n`,
			);
		}
	} finally {
		if (server) await server.close();
	}
	return buildEmptyBoardResult({
		label: options.label,
		git,
		host,
		buildKind: probe.buildKind,
		webviewRuntimeVersion: `OS WebKit (${probe.buildKind})`,
		idleSeconds: options.idleSeconds,
		samples: shellSamples,
		daemonSamples,
	});
}

async function runDisposalProbe(options) {
	const probe = resolveProbeBinary("debug");
	const git = await collectGitMetadata();
	const host = collectHostMetadata();
	const stateRoot = await mkdtemp(path.join(os.tmpdir(), "operator-heap-disposal-"));
	const daemonPort = await availableTcpPort();
	const collectorRoute = `/heap-disposal/${Date.now()}`;
	let collector;
	let harnessServer;
	let application;
	try {
		collector = await createMessageCollector(collectorRoute);
		const query = new URLSearchParams({
			daemonBaseUrl: `http://127.0.0.1:${daemonPort}`,
			sessionId: "heap-probe",
			terminalId: "heap-probe-terminal",
			scenario: "disposal",
			warmups: "0",
			samples: String(options.cycles),
			disposalStartMs: String(options.startMs),
			disposalBytes: String(options.disposalBytes),
			reportUrl: collector.url,
		}).toString();
		harnessServer = await startHarnessServer(query);
		application = spawnTauriApplication(probe.binaryPath, controlledProbeEnvironment(stateRoot, daemonPort, { benchmarkMode: true }));
		let applicationDiagnostics = "";
		application.stderr?.on("data", (chunk) => {
			applicationDiagnostics = `${applicationDiagnostics}${chunk}`.slice(-8_192);
		});
		// Benchmark mode does not spawn a daemon; the baseline ack proves the page
		// booted, and the whole process tree is shell accounting (nothing to exclude).
		await collector.waitForCount("disposal-baseline", 1, 180_000);
		await new Promise((resolve) => setTimeout(resolve, 1_000));
		const baseline = subtreeTotalBytes(await samplePosixProcessTable(), application.pid);
		process.stdout.write(`disposal baseline tree=${baseline}\n`);
		const cycleBytes = [];
		const disposalAcks = [];
		const overallDeadline = Date.now() + options.cycles * 60_000 + 120_000;
		while (cycleBytes.length < options.cycles && Date.now() < overallDeadline) {
			const pending = collector.messages.filter((message) => message.name === "disposal");
			if (pending.length <= cycleBytes.length) {
				const stallDeadline = Date.now() + 120_000;
				const observedBeforeStall = collector.messages.length;
				while (
					Date.now() < stallDeadline &&
					Date.now() < overallDeadline &&
					collector.messages.filter((message) => message.name === "disposal").length <= cycleBytes.length
				) {
					if (collector.messages.length !== observedBeforeStall) {
						process.stdout.write(`collector message: ${collector.messages.at(-1).name}\n`);
					}
					await new Promise((resolve) => setTimeout(resolve, 250));
				}
				continue;
			}
			for (const ack of pending.slice(cycleBytes.length)) {
				if (cycleBytes.length >= options.cycles) break;
				await new Promise((resolve) => setTimeout(resolve, options.settleMs));
				const shellBytes = subtreeTotalBytes(await samplePosixProcessTable(), application.pid);
				disposalAcks.push({ name: "disposal", timestamp: ack.timestamp });
				cycleBytes.push(shellBytes);
				process.stdout.write(`disposal cycle ${cycleBytes.length}/${options.cycles}: tree=${shellBytes}\n`);
			}
		}
		if (cycleBytes.length < options.cycles) {
			throw new Error(
				`disposal probe stalled after ${cycleBytes.length}/${options.cycles} cycles; collector saw ${
					collector.messages.map((message) => message.name).join(",") || "nothing"
				}; app diagnostics: ${applicationDiagnostics.trim() || "none"}`,
			);
		}
		return buildDisposalResult({
			label: options.label,
			git,
			host,
			buildKind: probe.buildKind,
			webviewRuntimeVersion: `OS WebKit (${probe.buildKind})`,
			cycles: options.cycles,
			disposalBytesPerCycle: options.disposalBytes,
			baselineBytes: baseline,
			cycleBytes,
			acks: disposalAcks,
		});
	} finally {
		await terminateProcessGroup(application);
		if (harnessServer) await harnessServer.close();
		if (collector) await collector.close();
		await rm(stateRoot, { recursive: true, force: true });
	}
}

async function startHarnessServer(query) {
	const { createServer } = await import("vite");
	const vite = await createServer({
		configFile: terminalPerfConfigPath,
		logLevel: "error",
		plugins: [
			{
				name: "heap-disposal-harness-configuration",
				transformIndexHtml(html) {
					return html.replace("<head>", `<head><script>history.replaceState(null, '', ${JSON.stringify(`?${query}`)})</script>`);
				},
			},
		],
		server: { host: "127.0.0.1", port: devUrlPort, strictPort: true },
	});
	await vite.listen();
	return {
		close: async () => {
			await vite.close();
		},
	};
}

function parseHeapArguments(argv) {
	const named = parseNamedArguments(argv);
	if (!HEAP_LABELS.includes(named.label)) throw new Error("--label must be one of before|after");
	if (named.probe !== undefined && !PROBE_KINDS.includes(named.probe) && named.probe !== "all") {
		throw new Error("--probe must be one of all|empty-board|terminal-disposal");
	}
	for (const key of Object.keys(named)) {
		if (!["label", "probe", "samples", "cycles", "idle-seconds", "settle-ms", "start-ms", "disposal-bytes"].includes(key)) {
			throw new Error(`unknown heap-summary argument: ${key}`);
		}
	}
	const numberOr = (value, fallback) => (value === undefined ? fallback : Number(value));
	return {
		label: named.label,
		probe: named.probe ?? "all",
		samples: numberOr(named["samples"], 3),
		cycles: numberOr(named["cycles"], 8),
		idleSeconds: numberOr(named["idle-seconds"], 20),
		settleMs: numberOr(named["settle-ms"], 1_500),
		startMs: numberOr(named["start-ms"], 3_000),
		disposalBytes: numberOr(named["disposal-bytes"], 2_097_152),
	};
}

export async function runHeapSummary(argv = process.argv.slice(2)) {
	const options = parseHeapArguments(argv);
	const probes = options.probe === "all" ? PROBE_KINDS : [options.probe];
	const written = [];
	for (const probe of probes) {
		const result = probe === "empty-board"
			? await runEmptyBoardProbe(options)
			: await runDisposalProbe(options);
		const outputPath = path.join(heapReportRoot, `${options.label}-${probe}.json`);
		await mkdir(heapReportRoot, { recursive: true });
		await writeFile(outputPath, `${JSON.stringify(result, null, "\t")}\n`, "utf8");
		written.push(outputPath);
		process.stdout.write(
			`heap[${probe}] label=${result.label} median=${result.median} p95=${result.p95}\nwrote ${path.relative(frontendRoot, outputPath)}\n`,
		);
	}
	return written;
}

async function main() {
	await runHeapSummary();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
