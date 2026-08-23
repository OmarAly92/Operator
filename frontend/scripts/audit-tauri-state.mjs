import { spawn } from "node:child_process";
import { watch, watchFile } from "node:fs";
import { access, lstat, mkdir, mkdtemp, readdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const homeDirectory = os.homedir();

function operatorRoot() {
	if (process.env.OPERATOR_DATA_DIR) return path.dirname(path.resolve(process.env.OPERATOR_DATA_DIR));
	if (process.env.OPERATOR_RUN_FILE) return path.dirname(path.resolve(process.env.OPERATOR_RUN_FILE));
	if (!homeDirectory || !path.isAbsolute(homeDirectory)) throw new Error("Operator root could not be resolved");
	return path.join(homeDirectory, ".operator");
}

function macOSStateTargets(operatorDirectory, platformHomeDirectory) {
	const libraryDirectory = path.join(platformHomeDirectory, "Library");
	const shallowDirectories = [
		"Application Support",
		"Caches",
		"HTTPStorages",
		path.join("Logs", "DiagnosticReports"),
		"Preferences",
		"Saved Application State",
		"WebKit",
	];
	const cookieDirectory = path.join(libraryDirectory, "Cookies");
	const cookieNames = ["dev.operator.desktop.binarycookies", "operator.binarycookies", "Operator.binarycookies"];
	return [
		{ statePath: operatorDirectory, depth: Number.POSITIVE_INFINITY },
		...shallowDirectories.map((stateDirectory) => ({ statePath: path.join(libraryDirectory, stateDirectory), depth: 1 })),
		{ statePath: cookieDirectory, depth: 0 },
		...cookieNames.map((cookieName) => ({
			statePath: path.join(cookieDirectory, cookieName),
			depth: Number.POSITIVE_INFINITY,
			exact: true,
		})),
	];
}

function windowsStateTargets(operatorDirectory, platformEnvironment) {
	const platformRoots = [operatorDirectory, platformEnvironment.APPDATA, platformEnvironment.LOCALAPPDATA]
		.filter(Boolean)
		.map((platformRoot) => path.resolve(platformRoot));
	const roots = [...new Set(platformRoots)].map((statePath) => ({
		statePath,
		depth: statePath === operatorDirectory ? Number.POSITIVE_INFINITY : 1,
	}));
	if (!platformEnvironment.LOCALAPPDATA) return roots;
	return [...roots, { statePath: path.resolve(platformEnvironment.LOCALAPPDATA, "CrashDumps"), depth: 1 }];
}

function linuxStateTargets(operatorDirectory, platformEnvironment, platformHomeDirectory) {
	return [
		operatorDirectory,
		path.resolve(platformEnvironment.XDG_CACHE_HOME ?? path.join(platformHomeDirectory, ".cache")),
		path.resolve(platformEnvironment.XDG_CONFIG_HOME ?? path.join(platformHomeDirectory, ".config")),
		path.resolve(platformEnvironment.XDG_DATA_HOME ?? path.join(platformHomeDirectory, ".local", "share")),
		path.resolve(platformEnvironment.XDG_STATE_HOME ?? path.join(platformHomeDirectory, ".local", "state")),
	].map((statePath) => ({ statePath, depth: statePath === operatorDirectory ? Number.POSITIVE_INFINITY : 1 }));
}

export function nativeStateTargets(
	operatorDirectory,
	platform = process.platform,
	platformEnvironment = process.env,
	platformHomeDirectory = homeDirectory,
) {
	if (platform === "darwin") return macOSStateTargets(operatorDirectory, platformHomeDirectory);
	if (platform === "win32") return windowsStateTargets(operatorDirectory, platformEnvironment);
	return linuxStateTargets(operatorDirectory, platformEnvironment, platformHomeDirectory);
}

async function recordTree(currentPath, filesystemSnapshot, remainingDepth, readDirectory) {
	const metadata = await lstat(currentPath);
	filesystemSnapshot.set(
		currentPath,
		`${metadata.isDirectory() ? "directory" : metadata.isSymbolicLink() ? "symlink" : "file"}:${metadata.size}:${metadata.mtimeMs}`,
	);
	if (!metadata.isDirectory() || metadata.isSymbolicLink() || remainingDepth === 0) return;
	let directoryEntries;
	try {
		directoryEntries = await readDirectory(currentPath, { withFileTypes: true });
	} catch (error) {
		if (error?.code === "EPERM" || error?.code === "EACCES") return;
		throw error;
	}
	for (const directoryEntry of directoryEntries) {
		const nextDepth = /operator|tauri|dev\.operator\.desktop/i.test(directoryEntry.name)
			? Number.POSITIVE_INFINITY
			: remainingDepth - 1;
		await recordTree(path.join(currentPath, directoryEntry.name), filesystemSnapshot, nextDepth, readDirectory);
	}
}

export async function snapshotTargets(snapshotTargets, readDirectory = readdir) {
	const filesystemSnapshot = new Map();
	for (const { statePath, depth } of snapshotTargets) {
		try {
			await recordTree(statePath, filesystemSnapshot, depth, readDirectory);
		} catch (error) {
			if (error?.code !== "ENOENT") throw error;
		}
	}
	return filesystemSnapshot;
}

function pathInside(candidatePath, parentPath) {
	const normalize = process.platform === "win32" ? (candidate) => candidate.toLowerCase() : (candidate) => candidate;
	const relativePath = path.relative(normalize(parentPath), normalize(candidatePath));
	return relativePath === "" || (!relativePath.startsWith(`..${path.sep}`) && relativePath !== ".." && !path.isAbsolute(relativePath));
}

function changedPaths(beforeSnapshot, afterSnapshot) {
	return [...afterSnapshot].filter(([statePath, signature]) => beforeSnapshot.get(statePath) !== signature).map(([statePath]) => statePath);
}

function snapshotsMatch(leftSnapshot, rightSnapshot) {
	if (leftSnapshot.size !== rightSnapshot.size) return false;
	return [...leftSnapshot].every(([statePath, signature]) => rightSnapshot.get(statePath) === signature);
}

function operatorOwnedStatePath(statePath) {
	const relativeStatePath = path.relative(homeDirectory, statePath);
	return relativeStatePath
		.split(path.sep)
		.some((component) => /^(?:dev\.)?operator(?:[.\s_-]|$)|^tauri(?:[.\s_-]|$)/i.test(component));
}

function createObserverState(options) {
	let rejectFailure;
	const failure = new Promise((_, reject) => {
		rejectFailure = reject;
	});
	failure.catch(() => {});
	return {
		watchDirectory: options.watchDirectory ?? watch,
		watchExactFile: options.watchExactFile ?? watchFile,
		directoryWatchers: new Map(),
		exactWatchers: [],
		observedSnapshot: new Map(),
		pendingTasks: new Set(),
		observationIndex: 0,
		failureError: undefined,
		stopping: false,
		stopped: false,
		failure,
		rejectFailure,
	};
}

function failObservation(observer, error) {
	if (observer.stopped) return;
	observer.failureError ??= error instanceof Error ? error : new Error(String(error));
	observer.rejectFailure(observer.failureError);
}

function scheduleObservation(observer, operation) {
	const task = Promise.resolve()
		.then(operation)
		.catch((error) => failObservation(observer, error))
		.finally(() => observer.pendingTasks.delete(task));
	observer.pendingTasks.add(task);
}

function recordObservation(observer, statePath) {
	if (observer.stopped) return;
	observer.observationIndex += 1;
	observer.observedSnapshot.set(statePath, `observed:${observer.observationIndex}`);
}

async function metadataIfExists(statePath) {
	try {
		return await lstat(statePath);
	} catch (error) {
		if (error?.code === "ENOENT") return undefined;
		throw error;
	}
}

function addDirectoryWatcher(observer, directoryPath, recursive, listener) {
	if (observer.stopping || observer.stopped) return;
	const resolvedDirectory = path.resolve(directoryPath);
	const watcherKey = `${recursive}:${resolvedDirectory}`;
	const existing = observer.directoryWatchers.get(watcherKey);
	if (existing) {
		existing.listeners.add(listener);
		return;
	}
	const listeners = new Set([listener]);
	const filesystemWatcher = observer.watchDirectory(resolvedDirectory, { recursive }, (_eventType, filename) => {
		if (filename === null) return failObservation(observer, new Error(`state observation lost the changed path beneath ${resolvedDirectory}`));
		for (const watcherListener of listeners) scheduleObservation(observer, () => watcherListener(filename.toString()));
	});
	filesystemWatcher.once("error", (error) => failObservation(observer, error));
	observer.directoryWatchers.set(watcherKey, { filesystemWatcher, listeners });
}

async function observeDirectoryWhenPresent(observer, directoryPath, observeDirectory) {
	const metadata = await metadataIfExists(directoryPath);
	if (metadata) {
		if (!metadata.isDirectory() || metadata.isSymbolicLink()) throw new Error(`required state target is not an observable directory: ${directoryPath}`);
		await observeDirectory();
		return;
	}
	const parentDirectory = path.dirname(directoryPath);
	if (parentDirectory === directoryPath) throw new Error(`required state target cannot be observed: ${directoryPath}`);
	await observeDirectoryWhenPresent(observer, parentDirectory, () => {
		addDirectoryWatcher(observer, parentDirectory, false, (changedName) => {
			const changedComponent = changedName.split(/[\\/]/, 1)[0];
			if (changedComponent === path.basename(directoryPath) || changedComponent === path.basename(parentDirectory)) {
				throw new Error(`required state target changed without continuous observation coverage: ${directoryPath}`);
			}
		});
	});
}

async function observeTree(observer, directoryPath) {
	addDirectoryWatcher(observer, directoryPath, true, async (changedName) => {
		const changedPath = path.resolve(directoryPath, changedName);
		if (!pathInside(changedPath, directoryPath)) throw new Error(`state observation escaped its target: ${changedPath}`);
		const metadata = await metadataIfExists(changedPath);
		if (changedName === path.basename(directoryPath) && !metadata) return;
		recordObservation(observer, changedPath);
	});
}

async function observeShallowTarget(observer, target) {
	await observeDirectoryWhenPresent(observer, target.statePath, async () => {
		addDirectoryWatcher(observer, target.statePath, true, async (changedName) => {
			const changedPath = path.resolve(target.statePath, changedName);
			recordObservation(observer, changedPath);
		});
	});
}

function observeExactTarget(observer, target) {
	const statWatcher = observer.watchExactFile(target.statePath, { interval: 25, persistent: true }, (current, previous) => {
		const currentSignature = `${current.dev}:${current.ino}:${current.size}:${current.mtimeMs}:${current.nlink}`;
		const previousSignature = `${previous.dev}:${previous.ino}:${previous.size}:${previous.mtimeMs}:${previous.nlink}`;
		if (currentSignature !== previousSignature) recordObservation(observer, target.statePath);
	});
	statWatcher.once("error", (error) => failObservation(observer, error));
	observer.exactWatchers.push(statWatcher);
}

async function stopObservation(observer) {
	if (observer.stopping || observer.stopped) return;
	observer.stopping = true;
	for (const { filesystemWatcher } of observer.directoryWatchers.values()) filesystemWatcher.close();
	for (const statWatcher of observer.exactWatchers) statWatcher.stop();
	while (observer.pendingTasks.size > 0) await Promise.allSettled([...observer.pendingTasks]);
	observer.stopped = true;
}

export async function observeStateTargets(stateTargets, options = {}) {
	const observer = createObserverState(options);

	try {
		for (const target of stateTargets) {
			if (target.exact) observeExactTarget(observer, target);
			else if (target.depth === Number.POSITIVE_INFINITY) {
				await observeDirectoryWhenPresent(observer, target.statePath, () => observeTree(observer, target.statePath));
			} else if (target.depth > 0) await observeShallowTarget(observer, target);
		}
	} catch (error) {
		await stopObservation(observer);
		throw error;
	}

	return {
		error: () => observer.failureError,
		failure: observer.failure,
		snapshot: () => new Map(observer.observedSnapshot),
		stop: () => stopObservation(observer),
	};
}

export async function settledStateSnapshot(readSnapshot, options = {}) {
	const now = options.now ?? Date.now;
	const pause = options.pause ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
	const minimumObservationMs = options.minimumObservationMs ?? 10_000;
	const timeoutMs = options.timeoutMs ?? 30_000;
	const pollIntervalMs = options.pollIntervalMs ?? 250;
	const requiredStableSamples = options.requiredStableSamples ?? 4;
	const startedAt = now();
	let stableSamples = 0;
	let latestSnapshot = await readSnapshot();
	while (now() - startedAt <= timeoutMs) {
		await pause(pollIntervalMs);
		const nextSnapshot = await readSnapshot();
		stableSamples = snapshotsMatch(latestSnapshot, nextSnapshot) ? stableSamples + 1 : 0;
		latestSnapshot = nextSnapshot;
		if (now() - startedAt >= minimumObservationMs && stableSamples >= requiredStableSamples) return latestSnapshot;
	}
	throw new Error(`state did not settle within ${timeoutMs}ms`);
}

export function assertConfined(beforeSnapshot, afterSnapshot, confinement) {
	const { allowedRoot, operatorDirectory, phase, monitoredRoots = [] } = confinement;
	const changedStatePaths = changedPaths(beforeSnapshot, afterSnapshot);
	const outsidePaths = changedStatePaths.filter(
		(statePath) =>
			!pathInside(statePath, allowedRoot) &&
			(pathInside(statePath, operatorDirectory) || operatorOwnedStatePath(statePath) || monitoredRoots.some((root) => pathInside(statePath, root))),
	);
	if (outsidePaths.length > 0) {
		const displayedPaths = outsidePaths.slice(0, 20).map((statePath) => path.relative(homeDirectory, statePath));
		throw new Error(`${phase} wrote state outside the allowed root: ${displayedPaths.join(", ")}`);
	}
	if (!changedStatePaths.some((statePath) => pathInside(statePath, allowedRoot))) {
		throw new Error(`${phase} produced no auditable state beneath the allowed root`);
	}
	return changedStatePaths.length;
}

function auditExecutable() {
	if (process.env.OPERATOR_TAURI_AUDIT_EXECUTABLE) return path.resolve(process.env.OPERATOR_TAURI_AUDIT_EXECUTABLE);
	const executableName = process.platform === "win32" ? "operator.exe" : "operator";
	const targetDirectory = process.env.CARGO_TARGET_DIR
		? path.resolve(process.env.CARGO_TARGET_DIR)
		: path.resolve("src-tauri", "target");
	return path.join(targetDirectory, "debug", executableName);
}

function phaseExitExpected(mode, exitCode, signal) {
	if (mode === "shutdown") return exitCode === 0 && signal === null;
	return signal !== null || (exitCode !== null && exitCode !== 0 && exitCode !== 70);
}

function spawnPhaseProcess(executablePath, launchEnvironment, mode, options) {
	const application = spawn(executablePath, options.launchArguments ?? [], {
		env: { ...process.env, ...launchEnvironment, OPERATOR_TAURI_STATE_AUDIT_MODE: mode },
		stdio: ["ignore", "pipe", "pipe"],
	});
	application.stdout.on("data", (chunk) => process.stderr.write(chunk));
	application.stderr.on("data", (chunk) => process.stderr.write(chunk));
	const completion = new Promise((resolveLaunch, rejectLaunch) => {
		let completed = false;
		const finish = (settle, value) => {
			if (completed) return;
			completed = true;
			clearTimeout(timeout);
			settle(value);
		};
		const timeout = setTimeout(() => {
			application.kill("SIGKILL");
			finish(rejectLaunch, new Error(`${mode} phase timed out`));
		}, options.timeoutMs ?? 30_000);
		application.once("error", (error) => finish(rejectLaunch, error));
		application.once("exit", (exitCode, signal) => {
			if (phaseExitExpected(mode, exitCode, signal)) finish(resolveLaunch);
			else finish(rejectLaunch, new Error(`${mode} phase exited unexpectedly with code ${exitCode} and signal ${signal}`));
		});
	});
	return { application, completion };
}

export async function launchPhase(executablePath, launchEnvironment, mode, completionMarker, options = {}) {
	const accessPath = options.accessPath ?? access;
	await accessPath(executablePath);
	const observer = await observeStateTargets(options.stateTargets ?? [], {
		watchDirectory: options.watchDirectory,
		watchExactFile: options.watchExactFile,
	});
	let application;
	let phaseError;
	try {
		const phaseProcess = spawnPhaseProcess(executablePath, launchEnvironment, mode, options);
		application = phaseProcess.application;
		await Promise.race([phaseProcess.completion, observer.failure]);
		if (completionMarker) await accessPath(completionMarker);
	} catch (error) {
		phaseError = error;
		if (application && application.exitCode === null && application.signalCode === null) application.kill("SIGKILL");
	} finally {
		await observer.stop();
	}
	if (phaseError) throw phaseError;
	if (observer.error()) throw observer.error();
	return observer.snapshot();
}

function mergeSnapshots(settledSnapshot, observedSnapshot) {
	const mergedSnapshot = new Map(settledSnapshot);
	for (const [statePath, signature] of observedSnapshot) mergedSnapshot.set(statePath, signature);
	return mergedSnapshot;
}

export async function auditPhase(options) {
	const observedSnapshot = await launchPhase(
		options.executablePath,
		options.launchEnvironment,
		options.mode,
		options.completionMarker,
		{
			launchArguments: options.launchArguments,
			stateTargets: options.stateTargets,
			timeoutMs: options.timeoutMs,
		},
	);
	const snapshot = await settledStateSnapshot(() => snapshotTargets(options.stateTargets), options.settlementOptions);
	const changes = assertConfined(
		options.beforeSnapshot,
		mergeSnapshots(snapshot, observedSnapshot),
		{ ...options.confinement, monitoredRoots: options.confinement.monitoredRoots ?? options.stateTargets.map(({ statePath }) => statePath) },
	);
	return { changes, snapshot };
}

export function deriveStateAuditSummary({ scannedRoots, phaseResults }) {
	if (!Number.isInteger(scannedRoots) || scannedRoots < 1) throw new Error("state audit summary requires a positive scanned-root count");
	const observedOutsideRoot = phaseResults.reduce((total, result) => total + (result.observedOutsideRoot ?? 0), 0);
	return {
		passed: observedOutsideRoot === 0 && phaseResults.every((result) => result.changes > 0),
		leaked: observedOutsideRoot > 0,
		observedOutsideRoot,
		scannedRoots,
	};
}

async function main() {
	const operatorDirectory = operatorRoot();
	await mkdir(path.join(operatorDirectory, "dev"), { recursive: true });
	const allowedRoot = await mkdtemp(path.join(operatorDirectory, "dev", "tauri-state-audit-"));
	const stateTargets = [
		...nativeStateTargets(operatorDirectory),
		{ statePath: allowedRoot, depth: Number.POSITIVE_INFINITY },
	];
	const executablePath = auditExecutable();
	const launchEnvironment = {
		OPERATOR_DATA_DIR: path.join(allowedRoot, "data"),
		OPERATOR_RUN_FILE: path.join(allowedRoot, "running.json"),
	};

	const initialSnapshot = await snapshotTargets(stateTargets);
	const confinement = { allowedRoot, operatorDirectory, phase: "shutdown" };
	const shutdown = await auditPhase({
		beforeSnapshot: initialSnapshot,
		stateTargets,
		executablePath,
		launchEnvironment,
		mode: "shutdown",
		completionMarker: path.join(allowedRoot, "tauri", "renderer-shutdown-complete"),
		confinement,
	});
	const crash = await auditPhase({
		beforeSnapshot: shutdown.snapshot,
		stateTargets,
		executablePath,
		launchEnvironment,
		mode: "crash",
		completionMarker: path.join(allowedRoot, "tauri", "renderer-crash-complete"),
		confinement: { ...confinement, phase: "crash" },
	});
	const summary = deriveStateAuditSummary({
		scannedRoots: stateTargets.length,
		phaseResults: [
			{ phase: "shutdown", changes: shutdown.changes },
			{ phase: "crash", changes: crash.changes },
		],
	});
	process.stdout.write(
		`${JSON.stringify({ platform: process.platform, ...summary, shutdownChanges: shutdown.changes, crashChanges: crash.changes })}\n`,
	);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
