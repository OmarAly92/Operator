import { spawn } from "node:child_process";
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
	const directoryEntries = await readDirectory(currentPath, { withFileTypes: true });
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
	const { allowedRoot, operatorDirectory, phase } = confinement;
	const changedStatePaths = changedPaths(beforeSnapshot, afterSnapshot);
	const outsidePaths = changedStatePaths.filter(
		(statePath) =>
			!pathInside(statePath, allowedRoot) &&
			(pathInside(statePath, operatorDirectory) || operatorOwnedStatePath(statePath)),
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

async function launchPhase(executablePath, launchEnvironment, mode, completionMarker) {
	await access(executablePath);
	await new Promise((resolveLaunch, rejectLaunch) => {
		const application = spawn(executablePath, [], {
			env: { ...process.env, ...launchEnvironment, OPERATOR_TAURI_STATE_AUDIT_MODE: mode },
			stdio: "inherit",
		});
		const timeout = setTimeout(() => {
			application.kill("SIGKILL");
			rejectLaunch(new Error(`${mode} phase timed out`));
		}, 30_000);
		application.once("error", rejectLaunch);
		application.once("exit", (exitCode, signal) => {
			clearTimeout(timeout);
			const expectedExit =
				mode === "shutdown"
					? exitCode === 0 && signal === null
					: signal !== null || (exitCode !== null && exitCode !== 0 && exitCode !== 70);
			if (expectedExit) resolveLaunch();
			else rejectLaunch(new Error(`${mode} phase exited unexpectedly with code ${exitCode} and signal ${signal}`));
		});
	});
	await access(completionMarker);
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
	await launchPhase(executablePath, launchEnvironment, "shutdown", path.join(allowedRoot, "tauri", "renderer-shutdown-complete"));
	const shutdownSnapshot = await settledStateSnapshot(() => snapshotTargets(stateTargets));
	const confinement = { allowedRoot, operatorDirectory, phase: "shutdown" };
	const shutdownChanges = assertConfined(initialSnapshot, shutdownSnapshot, confinement);
	await launchPhase(executablePath, launchEnvironment, "crash", path.join(allowedRoot, "tauri", "renderer-crash-complete"));
	const crashSnapshot = await settledStateSnapshot(() => snapshotTargets(stateTargets));
	const crashChanges = assertConfined(shutdownSnapshot, crashSnapshot, { ...confinement, phase: "crash" });
	process.stdout.write(`${JSON.stringify({ platform: process.platform, shutdownChanges, crashChanges })}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
