// WebdriverIO runner for the native Tauri shell (task 20).
//
// The @wdio/tauri-service spawns the app binary DIRECTLY with `driverProvider:
// "embedded"`: the WebDriver server lives inside the app behind tauri-plugin-wdio-webdriver,
// which src-tauri compiles ONLY under its `e2e` Cargo feature. A normal debug or
// production build never exposes the driver, so this suite cannot even start a
// session against one — scripts/e2e-tauri-build-contract.mjs proves that absence
// and this config fails with a timeout when it is missing.
//
// State isolation mirrors scripts/e2e-mac-update.mjs: every run gets a fresh
// temp state dir handed to the app through OPERATOR_RUN_FILE / OPERATOR_DATA_DIR
// (the shell derives <state-root>/tauri from the data-dir parent), plus a pinned
// daemon command so the suite never depends on `go run` at test time. The same
// variables are mirrored into process.env so worker processes can read them.
//
// The renderer is served by the vite dev server on the devUrl port from
// tauri.conf.json (127.0.0.1:5173). A debug cargo build has no embedded frontend
// assets — exactly like `tauri dev`, which is the development mode this suite
// tests. This file starts and stops vite itself so `npm run test:e2e:tauri` is
// self-contained.
import { spawn } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { existsSync, mkdirSync, mkdtempSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

type AfterTestResults = { error?: unknown };
type WdioTest = { parent?: string; title?: string };

const frontendRoot = fileURLToPath(new URL("..", import.meta.url));
const rendererPort = 5173;
const rendererUrl = `http://127.0.0.1:${rendererPort}`;
const executableSuffix = process.platform === "win32" ? ".exe" : "";

// This config is imported by the launcher AND by every worker process. The
// launcher runs first and pins the state dir into the environment, so every
// later import reuses the exact dir the app-under-test was pointed at instead
// of minting a second one.
export const stateDir =
	process.env.OPERATOR_E2E_STATE_DIR ?? mkdtempSync(path.join(os.tmpdir(), "operator-e2e-tauri-"));
process.env.OPERATOR_E2E_STATE_DIR = stateDir;
export const runFile = path.join(stateDir, "running.json");
export const appDataDir = path.join(stateDir, "data");
export const artifactsDir = path.join(frontendRoot, "test-results", "e2e-tauri");

export const appBinaryPath =
	process.env.OPERATOR_TAURI_E2E_BINARY ??
	path.join(frontendRoot, "src-tauri", "target", "debug", `operator${executableSuffix}`);
const daemonBinary = path.join(frontendRoot, "daemon", `opr${executableSuffix}`);
// OPERATOR_DAEMON_COMMAND is handed to `sh -c` (cmd.exe /C on Windows) by the
// supervisor, so the daemon SUBCOMMAND must be part of the command string; a
// bare binary path would exec `opr` with no arguments and exit immediately.
export const daemonCommand =
	process.env.OPERATOR_TAURI_E2E_DAEMON ?? `${daemonBinary} daemon`;

for (const [label, candidate] of [
	["app binary (build it with npm run test:e2e:tauri)", appBinaryPath],
	["daemon binary (build it with npm run build:daemon)", daemonBinary],
] as const) {
	if (!existsSync(candidate)) {
		throw new Error(`e2e-tauri: missing ${label}: ${candidate}`);
	}
}

mkdirSync(artifactsDir, { recursive: true });
process.env.OPERATOR_RUN_FILE = runFile;
process.env.OPERATOR_DATA_DIR = appDataDir;

let rendererProcess: ReturnType<typeof spawn> | undefined;

async function waitForRenderer(): Promise<void> {
	const deadline = Date.now() + 60_000;
	while (Date.now() < deadline) {
		try {
			const response = await fetch(rendererUrl);
			if (response.ok) return;
		} catch {
			// Not accepting connections yet.
		}
		await new Promise((resolve) => setTimeout(resolve, 500));
	}
	throw new Error(`e2e-tauri: the vite dev server did not answer at ${rendererUrl}`);
}

function stopRenderer(): void {
	rendererProcess?.kill();
	rendererProcess = undefined;
}

export const config = {
	runner: "local",
	specs: [path.join(frontendRoot, "e2e-tauri", "**", "*.e2e.ts")],
	maxInstances: 1,
	outputDir: artifactsDir,
	capabilities: [
		{
			browserName: "tauri",
			"tauri:options": {
				application: appBinaryPath,
			},
		},
	],
	services: [
		[
			"@wdio/tauri-service",
			{
				driverProvider: "embedded",
				windowLabel: "main",
				startTimeout: 120_000,
				commandTimeout: 120_000,
				autoDownloadEdgeDriver: false,
				env: {
					OPERATOR_RUN_FILE: runFile,
					OPERATOR_DATA_DIR: appDataDir,
					OPERATOR_DAEMON_COMMAND: daemonCommand,
				},
			},
		],
	],
	framework: "mocha",
	mochaOpts: {
		ui: "bdd",
		timeout: 240_000,
	},
	reporters: ["spec"],
	logLevel: "info",
	bail: 0,
	waitforTimeout: 30_000,
	connectionRetryTimeout: 120_000,
	connectionRetryCount: 3,

	onPrepare: async () => {
		const existing = process.env.OPERATOR_E2E_RENDERER_URL;
		if (!existing) {
			rendererProcess = spawn(
				process.platform === "win32" ? "npx.cmd" : "npx",
				["vite", "--config", "vite.renderer.config.ts", "--host", "127.0.0.1", "--port", String(rendererPort), "--strictPort"],
				{ cwd: frontendRoot, stdio: "inherit" },
			);
		}
		await waitForRenderer();
	},

	onComplete: () => {
		stopRenderer();
	},

	onError: () => {
		stopRenderer();
	},

	afterTest: async (test: WdioTest, _context: unknown, results: AfterTestResults) => {
		if (!results.error) return;
		const name = `${test.parent ?? ""}-${test.title ?? ""}`.replace(/[^a-z0-9-]+/gi, "-").slice(0, 120);
		const file = path.join(artifactsDir, `failure-${name}.png`);
		try {
			const browserGlobal = (globalThis as { browser?: { takeScreenshot?: () => Promise<string> } }).browser;
			const png = await browserGlobal?.takeScreenshot?.();
			if (png) {
				await writeFile(file, png, "base64");
				console.log(`e2e-tauri failure screenshot: ${file}`);
			}
		} catch (error) {
			console.log(`e2e-tauri screenshot failed: ${error instanceof Error ? error.message : String(error)}`);
		}
	},
};
