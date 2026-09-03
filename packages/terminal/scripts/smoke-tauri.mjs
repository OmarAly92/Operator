#!/usr/bin/env node
import { randomBytes } from "node:crypto";
import { execFile, spawn } from "node:child_process";
import { mkdir, readFile, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const repositoryRoot = resolve(packageRoot, "..", "..");
const frontendRoot = resolve(repositoryRoot, "frontend");
const smokeDistDir = resolve(packageRoot, "smoke", "dist");
const maxBodyBytes = 16 * 1024;
const expectedReport = { status: "ready", text: "red caféplain", rows: 2, runs: 3 };
const staticContentTypes = {
	".html": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".map": "application/json; charset=utf-8",
	".wasm": "application/wasm",
	".woff2": "font/woff2",
};

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

export async function startReporter(reportPath) {
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
			if (accepted) {
				send(response, 409);
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

export async function startStaticServer(rootDir) {
	const server = createServer((request, response) => {
		void (async () => {
			const requestPath = new URL(request.url, "http://localhost").pathname;
			const relativePath = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "");
			const filePath = join(rootDir, relativePath);
			if (!filePath.startsWith(rootDir)) {
				send(response, 403);
				return;
			}
			try {
				const body = await readFile(filePath);
				const contentType = staticContentTypes[extname(filePath)] ?? "application/octet-stream";
				response.writeHead(200, { "Content-Type": contentType });
				response.end(body);
			} catch {
				send(response, 404);
			}
		})();
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
		throw new Error("terminal smoke static server did not bind a numeric port");
	}
	return { server, url: `http://127.0.0.1:${address.port}` };
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

function isMissingProcessGroup(error) {
	return Boolean(error && typeof error === "object" && error.code === "ESRCH");
}

function delay(milliseconds) {
	return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

export async function terminateProcessGroup(processGroupId, options = {}) {
	if (!processGroupId) {
		return;
	}
	const platform = options.platform ?? process.platform;
	const kill = options.kill ?? process.kill;
	const runCommand = options.runCommand ?? run;
	const wait = options.wait ?? delay;
	if (platform === "win32") {
		await runCommand("taskkill", ["/pid", String(processGroupId), "/T", "/F"]);
		return;
	}
	try {
		kill(-processGroupId, "SIGTERM");
	} catch (error) {
		if (isMissingProcessGroup(error)) {
			return;
		}
		throw error;
	}
	await wait(2000);
	try {
		kill(-processGroupId, "SIGKILL");
	} catch (error) {
		if (!isMissingProcessGroup(error)) {
			throw error;
		}
	}
}

async function main() {
	const runId = randomBytes(24).toString("hex");
	const stateDirectory = resolve(homedir(), ".operator", "terminal-smoke", runId);
	const reportPath = `/${randomBytes(24).toString("hex")}`;
	let reporter;
	let staticServer;
	let child;
	let processGroupId;
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
		staticServer = await startStaticServer(smokeDistDir);
		const executable = resolve(frontendRoot, "src-tauri", "target", "release", process.platform === "win32" ? "operator.exe" : "operator");
		child = spawn(executable, [], {
			cwd: repositoryRoot,
			detached: true,
			env: {
				...process.env,
				OPERATOR_DATA_DIR: resolve(stateDirectory, "data"),
				OPERATOR_RUN_FILE: resolve(stateDirectory, "running.json"),
				OPERATOR_TAURI_TERMINAL_BENCHMARK: "1",
				OPERATOR_TAURI_TERMINAL_BENCHMARK_URL: staticServer.url,
			},
			stdio: "ignore",
		});
		processGroupId = child.pid;
		await waitForReport(reporter.report, child);
		process.stdout.write("Tauri release smoke loaded vt_core_bg.wasm and painted 2 rows / 3 runs.\n");
	} finally {
		if (processGroupId) {
			await terminateProcessGroup(processGroupId);
		}
		if (reporter) {
			await new Promise((resolveClose) => reporter.server.close(resolveClose));
		}
		if (staticServer) {
			await new Promise((resolveClose) => staticServer.server.close(resolveClose));
		}
		await rm(stateDirectory, { recursive: true, force: true });
	}
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	main().catch((error) => {
		const message = error instanceof Error ? error.message : String(error);
		process.stderr.write(`smoke-tauri: ${message}\n`);
		process.exitCode = 1;
	});
}
