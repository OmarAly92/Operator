import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));

function parseArgs(argv) {
	const args = {};
	for (let index = 0; index < argv.length; index += 1) {
		const flag = argv[index];
		if (!flag?.startsWith("--")) throw new Error(`unexpected argument: ${flag}`);
		args[flag.slice(2)] = argv[index + 1];
		index += 1;
	}
	return args;
}

async function availablePort() {
	return await new Promise((resolve, reject) => {
		const server = net.createServer();
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			const address = server.address();
			if (!address || typeof address === "string") {
				server.close();
				reject(new Error("could not reserve a legacy exercise port"));
				return;
			}
			server.close((error) => (error ? reject(error) : resolve(address.port)));
		});
	});
}

async function waitForReadiness(port, deadlineMs) {
	const startedAt = Date.now();
	while (Date.now() - startedAt < deadlineMs) {
		try {
			const response = await fetch(`http://127.0.0.1:${port}/readyz`, { signal: AbortSignal.timeout(1500) });
			if (response.ok) {
				const payload = await response.json();
				if (payload?.status === "ready" && payload?.service === "operator-daemon") return String(payload.service);
			}
		} catch {
		}
		await new Promise((resolve) => setTimeout(resolve, 500));
	}
	throw new Error(`daemon readiness was not observed within ${deadlineMs}ms`);
}

async function treeDigest(root) {
	async function visit(current, hash) {
		const metadata = await lstat(current);
		if (metadata.isSymbolicLink()) return;
		if (metadata.isFile()) {
			hash.update(`${path.relative(root, current)}\0${metadata.size}\0${Math.round(metadata.mtimeMs)}\0`);
			hash.update(await readFile(current));
			return;
		}
		if (!metadata.isDirectory()) return;
		for (const entry of (await readdir(current)).sort()) {
			await visit(path.join(current, entry), hash);
		}
	}
	const hash = createHash("sha256");
	await visit(root, hash);
	return hash.digest("hex");
}

async function terminate(application) {
	if (!application || application.exitCode !== null || application.signalCode !== null) return;
	if (process.platform === "win32") {
		await new Promise((resolve) => {
			const killer = spawn("taskkill.exe", ["/PID", String(application.pid), "/T", "/F"], { stdio: "ignore", windowsHide: true });
			killer.on("close", resolve);
			killer.on("error", () => {
				application.kill("SIGKILL");
				resolve();
			});
		});
		return;
	}
	try {
		process.kill(-application.pid, "SIGTERM");
	} catch {
		application.kill("SIGTERM");
	}
	await Promise.race([
		new Promise((resolve) => application.once("exit", resolve)),
		new Promise((resolve) => setTimeout(resolve, 5000)),
	]);
	if (application.exitCode === null && application.signalCode === null) {
		try {
			process.kill(-application.pid, "SIGKILL");
		} catch {
			application.kill("SIGKILL");
		}
	}
}

export async function runExercise({ legacyExecutable, targetExecutable, observationsDir, timeoutMilliseconds = 180_000 }) {
	const operatorRoot = process.env.OPERATOR_DATA_DIR
		? path.dirname(path.resolve(process.env.OPERATOR_DATA_DIR))
		: path.join(os.homedir(), ".operator");
	await mkdir(path.join(operatorRoot, "dev"), { recursive: true });
	const stateRoot = await mkdtemp(path.join(operatorRoot, "dev", "legacy-exercise-"));
	await mkdir(observationsDir, { recursive: true });
	const writeObservation = async (name, payload) => {
		await writeFile(path.join(observationsDir, name), `${JSON.stringify(payload, null, "\t")}\n`, "utf8");
	};
	const launchGeneration = async (executable, port) => {
		const application = spawn(executable, [], {
			detached: process.platform !== "win32",
			env: {
				...process.env,
				OPERATOR_DATA_DIR: path.join(stateRoot, "data"),
				OPERATOR_RUN_FILE: path.join(stateRoot, "running.json"),
				OPERATOR_PORT: String(port),
				OPERATOR_KEEP_DAEMON: "0",
			},
			stdio: "ignore",
		});
		return application;
	};

	let identityBefore;
	const legacyPort = await availablePort();
	let legacyApplication;
	try {
		legacyApplication = await launchGeneration(legacyExecutable, legacyPort);
		identityBefore = await waitForReadiness(legacyPort, timeoutMilliseconds);
	} finally {
		await terminate(legacyApplication);
	}
	const launchedAt = new Date().toISOString();
	writeObservation("legacy-launch.json", { launchedAt, readyObserved: true });

	const updateCommand = process.env.OPERATOR_LEGACY_UPDATE_COMMAND;
	if (updateCommand) {
		const exitCode = await new Promise((resolve) => {
			const updater = spawn(updateCommand, { shell: process.platform !== "win32", stdio: "ignore" });
			updater.on("error", () => resolve(127));
			updater.on("close", resolve);
		});
		writeObservation("update-request.json", { requestedAt: new Date().toISOString(), exitCode });
	}

	const stateDigestBefore = await treeDigest(path.join(stateRoot, "data"));

	const targetPort = await availablePort();
	let targetApplication;
	try {
		targetApplication = await launchGeneration(targetExecutable, targetPort);
		const identityAfter = await waitForReadiness(targetPort, timeoutMilliseconds);
		const stateDigestAfter = await treeDigest(path.join(stateRoot, "data"));
		writeObservation("target-launch.json", { launchedAt: new Date().toISOString(), readyObserved: true });
		writeObservation("state-preservation.json", {
			identityBefore,
			identityAfter,
			stateDigestBefore,
			stateDigestAfter,
		});
	} finally {
		await terminate(targetApplication);
	}
	await rm(stateRoot, { recursive: true, force: true, maxRetries: 10, retryDelay: 250 });
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("Usage: node scripts/phase0-legacy-exercise.mjs --legacy <executable> --target <executable> --observations <dir> [--legacy-version v] [--target-version v]\n");
		return;
	}
	const args = parseArgs(process.argv.slice(2));
	await runExercise({
		legacyExecutable: path.resolve(args.legacy),
		targetExecutable: path.resolve(args.target),
		observationsDir: path.resolve(args.observations),
	});
	await writeFile(
		path.join(path.resolve(args.observations), "versions.json"),
		`${JSON.stringify({ legacyVersion: args["legacy-version"] ?? "", targetVersion: args["target-version"] ?? "" }, null, "\t")}\n`,
		"utf8",
	);
	process.stdout.write("exercise observations written\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
