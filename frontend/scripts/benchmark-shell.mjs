import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";
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

const execFileAsync = promisify(execFile);
const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const scenariosPath = fileURLToPath(new URL("../perf/scenarios.json", import.meta.url));
const shellScenarios = new Set(["warm-start", "first-run", "idle-memory"]);

export function parseShellArguments(argv) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron") throw new Error("Task 2 supports only electron shell measurements");
	if (!shellScenarios.has(namedArguments.scenario)) {
		throw new Error(`unsupported shell scenario: ${namedArguments.scenario ?? ""}`);
	}
	if (Object.keys(namedArguments).some((key) => key !== "shell" && key !== "scenario")) {
		throw new Error("unknown shell benchmark argument");
	}
	return { shell: namedArguments.shell, scenario: namedArguments.scenario };
}

export function processTreeBytesFromPosixTable(table, rootProcessId) {
	const processes = table
		.trim()
		.split("\n")
		.map((line) => line.trim().split(/\s+/).map(Number))
		.filter(([processId, parentProcessId, residentKilobytes]) =>
			[processId, parentProcessId, residentKilobytes].every(Number.isFinite),
		)
		.map(([processId, parentProcessId, residentKilobytes]) => ({ processId, parentProcessId, bytes: residentKilobytes * 1024 }));
	return sumProcessTree(processes, rootProcessId);
}

function sumProcessTree(processes, rootProcessId) {
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
	return processes.filter((process) => included.has(process.processId)).reduce((total, process) => total + process.bytes, 0);
}

async function processTreeBytes(rootProcessId) {
	if (process.platform === "win32") {
		const command = "Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,WorkingSetSize | ConvertTo-Json -Compress";
		const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command]);
		const decoded = JSON.parse(stdout);
		const rows = Array.isArray(decoded) ? decoded : [decoded];
		return sumProcessTree(
			rows.map((row) => ({
				processId: Number(row.ProcessId),
				parentProcessId: Number(row.ParentProcessId),
				bytes: Number(row.WorkingSetSize),
			})),
			rootProcessId,
		);
	}
	const { stdout } = await execFileAsync("ps", ["-axo", "pid=,ppid=,rss="]);
	return processTreeBytesFromPosixTable(stdout, rootProcessId);
}

async function availablePort() {
	return await new Promise((resolve, reject) => {
		const server = net.createServer();
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			const address = server.address();
			if (!address || typeof address === "string") {
				server.close();
				reject(new Error("could not reserve a benchmark daemon port"));
				return;
			}
			server.close((error) => (error ? reject(error) : resolve(address.port)));
		});
	});
}

async function resolveElectronExecutable(env) {
	if (env.OPERATOR_BENCH_ELECTRON_EXECUTABLE) {
		const configured = path.resolve(env.OPERATOR_BENCH_ELECTRON_EXECUTABLE);
		if (!existsSync(configured)) throw new Error(`configured Electron executable does not exist: ${configured}`);
		return configured;
	}
	const candidates =
		process.platform === "darwin"
			? ["/Applications/Operator.app/Contents/MacOS/operator"]
			: process.platform === "win32"
				? [path.join(env.ProgramFiles ?? "C:\\Program Files", "Operator", "operator.exe")]
				: ["/opt/Operator/operator", "/usr/bin/operator"];
	for (const candidate of candidates) {
		if (existsSync(candidate)) return candidate;
	}
	throw new Error("no installed Electron build found; set OPERATOR_BENCH_ELECTRON_EXECUTABLE to the native release executable");
}

async function rendererMarkTimestamp(page, markName) {
	await page.waitForFunction(
		(name) => performance.getEntriesByName(name, "mark").length > 0,
		markName,
		{ timeout: 120_000 },
	);
	return await page.evaluate((name) => {
		const entry = performance.getEntriesByName(name, "mark").at(-1);
		if (!entry) throw new Error(`renderer mark missing: ${name}`);
		return performance.timeOrigin + entry.startTime;
	}, markName);
}

export async function observeStartupCompletion({
	scenario,
	page,
	daemonPort,
	fetchImpl = fetch,
	now = Date.now,
	wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
	rendererTimestamp = rendererMarkTimestamp,
	timeoutMilliseconds = 120_000,
	requestTimeoutMilliseconds = 2_000,
	AbortControllerClass = AbortController,
	setRequestTimeout = setTimeout,
	clearRequestTimeout = clearTimeout,
}) {
	if (scenario.processState === "warm" && scenario.completionMark === "operator:board-interactive") {
		return await rendererTimestamp(page, scenario.completionMark);
	}
	if (scenario.processState !== "fresh-daemon" || scenario.completionEndpoint !== "daemon:/readyz") {
		throw new Error("startup scenario has no supported observed completion boundary");
	}
	const endpoint = `http://127.0.0.1:${daemonPort}/readyz`;
	const deadline = now() + timeoutMilliseconds;
	while (now() <= deadline) {
		const remainingMilliseconds = deadline - now();
		if (remainingMilliseconds <= 0) break;
		const controller = new AbortControllerClass();
		const requestTimeout = setRequestTimeout(
			() => controller.abort(),
			Math.max(1, Math.min(requestTimeoutMilliseconds, remainingMilliseconds)),
		);
		try {
			const response = await fetchImpl(endpoint, { signal: controller.signal });
			const payload = response.ok ? await response.json() : undefined;
			if (payload?.status === "ready" && payload.service === "operator-daemon") return now();
		} catch (error) {
			if (!(error instanceof TypeError || error instanceof SyntaxError || error?.name === "AbortError")) throw error;
		} finally {
			clearRequestTimeout(requestTimeout);
		}
		if (now() < deadline) await wait(Math.min(50, deadline - now()));
	}
	throw new Error("daemon readiness endpoint was not observed before timeout");
}

export function startupDurationFromSpawn(rawSpawnTimestamp, completionTimestamp) {
	const spawnTimestamp = Number(rawSpawnTimestamp);
	if (!rawSpawnTimestamp || !Number.isFinite(spawnTimestamp) || spawnTimestamp <= 0) {
		throw new Error("native process spawn timestamp unavailable");
	}
	if (!Number.isFinite(completionTimestamp) || completionTimestamp < spawnTimestamp) {
		throw new Error("native process spawn timestamp is later than observed completion");
	}
	return completionTimestamp - spawnTimestamp;
}

export async function prepareSpawnAttestation(executablePath, stateRoot) {
	const timestampPath = path.join(stateRoot, "electron-spawn.timestamp");
	if (process.platform === "win32") return { executablePath, timestampPath, env: {} };
	const launcherPath = path.join(stateRoot, "electron-spawn-launcher.mjs");
	const source = [
		"#!/usr/bin/env node",
		'import { writeFileSync } from "node:fs";',
		"writeFileSync(process.env.OPERATOR_BENCH_SPAWN_TIMESTAMP_FILE, String(Date.now()));",
		"const executable = process.env.OPERATOR_BENCH_NATIVE_EXECUTABLE;",
		"process.execve(executable, [executable, ...process.argv.slice(2)], process.env);",
		"",
	].join("\n");
	await writeFile(launcherPath, source, "utf8");
	await chmod(launcherPath, 0o755);
	return {
		executablePath: launcherPath,
		timestampPath,
		env: {
			OPERATOR_BENCH_NATIVE_EXECUTABLE: executablePath,
			OPERATOR_BENCH_SPAWN_TIMESTAMP_FILE: timestampPath,
		},
	};
}

async function nativeSpawnTimestamp(application, attestation) {
	if (process.platform !== "win32") return await readFile(attestation.timestampPath, "utf8");
	const processId = await application.evaluate(() => process.pid);
	if (!Number.isInteger(processId) || processId <= 0) throw new Error("Electron process identifier unavailable for native spawn attestation");
	const command = `(Get-CimInstance Win32_Process -Filter \"ProcessId = ${processId}\").CreationDate.ToUniversalTime().ToString(\"o\")`;
	const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command]);
	const timestamp = Date.parse(stdout.trim());
	if (!Number.isFinite(timestamp)) throw new Error("native process spawn timestamp unavailable");
	return String(timestamp);
}

async function rendererMetadata(application, page) {
	const versions = await application.evaluate(() => ({ electron: process.versions.electron, chromium: process.versions.chrome }));
	return {
		webviewRuntimeVersion: `Electron ${versions.electron} / Chromium ${versions.chromium}`,
		rendererKind: "chromium",
		displayScale: await page.evaluate(() => window.devicePixelRatio),
	};
}

export async function launchSample({ executablePath, scenario, stateRoot }, dependencies = {}) {
	const daemonPort = await (dependencies.availablePort ?? availablePort)();
	const spawnAttestation = await (dependencies.prepareSpawnAttestation ?? prepareSpawnAttestation)(executablePath, stateRoot);
	const applicationPromise = (dependencies.launchElectron ?? ((options) => electron.launch(options)))({
		executablePath: spawnAttestation.executablePath,
		env: {
			...process.env,
			...spawnAttestation.env,
			OPERATOR_DATA_DIR: path.join(stateRoot, "data"),
			OPERATOR_RUN_FILE: path.join(stateRoot, "running.json"),
			OPERATOR_PORT: String(daemonPort),
			OPERATOR_KEEP_DAEMON: "0",
		},
		timeout: 120_000,
	});
	const observeCompletion = dependencies.observeStartupCompletion ?? observeStartupCompletion;
	const firstRunCompletionPromise = scenario.processState === "fresh-daemon"
		? observeCompletion({ scenario, daemonPort })
		: undefined;
	const [application, firstRunCompletion] = firstRunCompletionPromise
		? await Promise.all([applicationPromise, firstRunCompletionPromise])
		: [await applicationPromise, undefined];
	try {
		const rawSpawnTimestamp = await (dependencies.nativeSpawnTimestamp ?? nativeSpawnTimestamp)(application, spawnAttestation);
		const page = await application.firstWindow({ timeout: 120_000 });
		const renderer = await (dependencies.rendererMetadata ?? rendererMetadata)(application, page);
		if (scenario.kind === "memory") {
			await page.waitForTimeout(scenario.idleSeconds * 1000);
			const rootProcessId = application.process().pid;
			if (!rootProcessId) throw new Error("Electron process identifier unavailable for transient accounting");
			return { sample: await (dependencies.processTreeBytes ?? processTreeBytes)(rootProcessId), renderer };
		}
		const completionTimestamp = firstRunCompletion ?? (await observeCompletion({ scenario, page, daemonPort }));
		return { sample: startupDurationFromSpawn(rawSpawnTimestamp, completionTimestamp), renderer };
	} finally {
		await application.close();
	}
}

async function stateDirectory(prefix) {
	const root = path.join(os.homedir(), ".operator", "benchmarks");
	await mkdir(root, { recursive: true });
	return await mkdtemp(path.join(root, `${prefix}-`));
}

export async function runShellBenchmark(argv = process.argv.slice(2), env = process.env) {
	const options = parseShellArguments(argv);
	const scenarios = JSON.parse(await readFile(scenariosPath, "utf8"));
	const scenario = scenarios[options.scenario];
	const executablePath = await resolveElectronExecutable(env);
	const git = await collectGitMetadata();
	const host = collectHostMetadata();
	const measurements = [];
	let rendererMetadataSnapshot;
	const sharedState = options.scenario === "warm-start" ? await stateDirectory("electron-warm") : undefined;
	try {
		const total = scenario.warmups + scenario.samples;
		for (let index = 0; index < total; index += 1) {
			const launchState = sharedState ?? (await stateDirectory(`electron-${options.scenario}`));
			try {
				const launchMeasurement = await launchSample({ executablePath, scenario, stateRoot: launchState });
				rendererMetadataSnapshot ??= launchMeasurement.renderer;
				if (index >= scenario.warmups) measurements.push(launchMeasurement.sample);
			} finally {
				if (!sharedState) await rm(launchState, { recursive: true, force: true });
			}
		}
	} finally {
		if (sharedState) await rm(sharedState, { recursive: true, force: true });
	}
	const benchmarkResult = createBenchmarkResult({
		shell: options.shell,
		scenario: options.scenario,
		buildProfile: env.OPERATOR_BENCH_BUILD_PROFILE || "local-packaged",
		git,
		host,
		renderer: rendererMetadataSnapshot,
		scenarioConfiguration: scenarioResultConfiguration(scenario),
		warmups: scenario.warmups,
		samples: measurements,
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

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("node scripts/benchmark-shell.mjs --shell electron --scenario warm-start|first-run|idle-memory\n");
		return;
	}
	await runShellBenchmark();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
