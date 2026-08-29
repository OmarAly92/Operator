#!/usr/bin/env node
import { randomBytes } from "node:crypto";
import { execFile, spawn } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const repositoryRoot = resolve(packageRoot, "..", "..");
const frontendRoot = resolve(repositoryRoot, "frontend");
const maxBodyBytes = 16 * 1024;
const expectedReport = { status: "ready", text: "red caféplain", rows: 2, runs: 3 };

function run(command, args, options = {}) {
	return new Promise((resolveRun, rejectRun) => {
		execFile(command, args, { maxBuffer: 16 * 1024 * 1024, ...options }, (error, stdout, stderr) => {
			if (error) {
				rejectRun(new Error(`${command} ${args.join(" ")} failed: ${stderr || stdout || error.message}`));
				return;
			}
			resolveRun();
		});
	});
}

function send(response, statusCode, headers = {}) {
	response.writeHead(statusCode, {
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Headers": "Content-Type",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		...headers,
	});
	response.end();
}

function isExpectedReport(value) {
	if (!value || typeof value !== "object" || Array.isArray(value)) {
		return false;
	}
	const keys = Object.keys(value).sort();
	const expectedKeys = Object.keys(expectedReport).sort();
	return keys.length === expectedKeys.length && keys.every((key, index) => key === expectedKeys[index]) &&
		value.status === expectedReport.status &&
		value.text === expectedReport.text &&
		value.rows === expectedReport.rows &&
		value.runs === expectedReport.runs;
}

async function startReporter(reportPath) {
	let resolveReport;
	const report = new Promise((resolve) => {
		resolveReport = resolve;
	});
	let accepted = false;
	const server = createServer((request, response) => {
		if (request.url !== reportPath) {
			send(response, 404);
			return;
		}
		if (request.method === "OPTIONS") {
			send(response, 204);
			return;
		}
		if (request.method !== "POST" || accepted) {
			send(response, accepted ? 409 : 405);
			return;
		}
		const contentLength = Number(request.headers["content-length"] ?? 0);
		if (!Number.isFinite(contentLength) || contentLength > maxBodyBytes) {
			send(response, 413);
			return;
		}
		let size = 0;
		const chunks = [];
		request.on("data", (chunk) => {
			size += chunk.length;
			if (size > maxBodyBytes) {
				send(response, 413);
				request.destroy();
				return;
			}
			chunks.push(chunk);
		});
		request.on("end", () => {
			if (response.writableEnded || size > maxBodyBytes) {
				return;
			}
			let value;
			try {
				value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
			} catch {
				send(response, 400);
				return;
			}
			if (!isExpectedReport(value)) {
				send(response, 422);
				return;
			}
			accepted = true;
			send(response, 204);
			resolveReport(value);
		});
	});
	await new Promise((resolveListen, rejectListen) => {
		server.once("error", rejectListen);
		server.listen({ host: "127.0.0.1", port: 0 }, () => {
			server.off("error", rejectListen);
			resolveListen();
		});
	});
	const address = server.address();
	if (!address || typeof address === "string") {
		await new Promise((resolveClose) => server.close(resolveClose));
		throw new Error("terminal smoke reporter did not receive a numeric port");
	}
	return { server, report, url: `http://127.0.0.1:${address.port}${reportPath}` };
}

function processExit(child) {
	return new Promise((resolveExit, rejectExit) => {
		child.once("error", rejectExit);
		child.once("exit", (code, signal) => {
			rejectExit(new Error(`Tauri release binary exited before reporting (code ${code}, signal ${signal})`));
		});
	});
}

async function waitForReport(report, child) {
	let timeoutId;
	try {
		await Promise.race([
			report,
			processExit(child),
			new Promise((_, rejectTimeout) => {
				timeoutId = setTimeout(
					() => rejectTimeout(new Error("timed out waiting for Tauri release smoke report")),
					60_000,
				);
			}),
		]);
	} finally {
		clearTimeout(timeoutId);
	}
}

async function terminateProcessGroup(child) {
	if (!child.pid || child.exitCode !== null || child.signalCode !== null) {
		return;
	}
	if (process.platform === "win32") {
		await run("taskkill", ["/pid", String(child.pid), "/T", "/F"]).catch(() => {});
		return;
	}
	try {
		process.kill(-child.pid, "SIGTERM");
	} catch {
		return;
	}
	await Promise.race([
		new Promise((resolveExit) => child.once("exit", resolveExit)),
		new Promise((resolveDelay) => setTimeout(resolveDelay, 2000)),
	]);
	if (child.exitCode === null && child.signalCode === null) {
		try {
			process.kill(-child.pid, "SIGKILL");
		} catch {}
	}
}

async function main() {
	const runId = randomBytes(24).toString("hex");
	const stateDirectory = resolve(homedir(), ".operator", "terminal-smoke", runId);
	const reportPath = `/${randomBytes(24).toString("hex")}`;
	let reporter;
	let child;
	try {
		await mkdir(stateDirectory, { recursive: true });
		reporter = await startReporter(reportPath);
		await run("npm", ["exec", "--", "vite", "build", "smoke", "--config", "smoke/vite.config.ts"], {
			cwd: packageRoot,
			env: { ...process.env, TERMINAL_SMOKE_REPORT_URL: reporter.url },
		});
		const config = JSON.stringify({
			build: {
				beforeBuildCommand: "",
				frontendDist: "../../packages/terminal/smoke/dist",
			},
			bundle: {
				resources: [],
			},
		});
		await run("npm", ["--prefix", "frontend", "run", "tauri:build", "--", "--no-bundle", "--ci", "--config", config], {
			cwd: repositoryRoot,
		});
		const executable = resolve(frontendRoot, "src-tauri", "target", "release", process.platform === "win32" ? "operator.exe" : "operator");
		child = spawn(executable, [], {
			cwd: repositoryRoot,
			detached: true,
			env: {
				...process.env,
				OPERATOR_DATA_DIR: resolve(stateDirectory, "data"),
				OPERATOR_RUN_FILE: resolve(stateDirectory, "running.json"),
				OPERATOR_TAURI_TERMINAL_BENCHMARK: "1",
			},
			stdio: "ignore",
		});
		await waitForReport(reporter.report, child);
		process.stdout.write("Tauri release smoke loaded vt_core_bg.wasm and painted 2 rows / 3 runs.\n");
	} finally {
		if (child) {
			await terminateProcessGroup(child);
		}
		if (reporter) {
			await new Promise((resolveClose) => reporter.server.close(resolveClose));
		}
		await rm(stateDirectory, { recursive: true, force: true });
	}
}

main().catch((error) => {
	const message = error instanceof Error ? error.message : String(error);
	process.stderr.write(`smoke-tauri: ${message}\n`);
	process.exitCode = 1;
});
