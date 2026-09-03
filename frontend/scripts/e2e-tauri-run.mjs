// Orchestrates the native Tauri E2E suite (task 20): builds the debug shell with
// the `e2e` Cargo feature (which is the ONLY way the embedded WebDriver plugins
// compile in — see scripts/e2e-tauri-build-contract.mjs for the absence proof on
// normal builds), then hands control to WebdriverIO. Dependency-free ESM so CI
// and `npm run test:e2e:tauri` run it directly.
//
// The vite dev server that serves the renderer is started and stopped by
// e2e-tauri/wdio.conf.ts itself; this script only builds and launches wdio.
//
// usage:
//   node scripts/e2e-tauri-run.mjs [--skip-build] [--binary <path>] [-- spec args...]
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));

function parseArgs(argv) {
	const options = { skipBuild: false, binary: undefined, wdioArgs: [] };
	for (let i = 0; i < argv.length; i += 1) {
		if (argv[i] === "--skip-build") options.skipBuild = true;
		else if (argv[i] === "--binary") options.binary = argv[(i += 1)];
		else if (argv[i] === "--") options.wdioArgs = argv.slice(i + 1);
		else throw new Error(`unknown argument: ${argv[i]}`);
	}
	return options;
}

export function resolveBinaryPath(frontendRootDir, platform, override) {
	if (override) return path.resolve(override);
	const suffix = platform === "win32" ? ".exe" : "";
	return path.join(frontendRootDir, "src-tauri", "target", "debug", `operator${suffix}`);
}

export function resolveWdioCli(frontendRootDir) {
	return path.join(frontendRootDir, "node_modules", "@wdio", "cli", "bin", "wdio.js");
}

function main() {
	const options = parseArgs(process.argv.slice(2));
	const binaryPath = resolveBinaryPath(frontendRoot, process.platform, options.binary);

	if (!options.skipBuild) {
		const build = spawnSync(
			"cargo",
			["build", "--manifest-path", path.join("src-tauri", "Cargo.toml"), "--features", "e2e"],
			{ cwd: frontendRoot, stdio: "inherit" },
		);
		if (build.error) {
			process.stderr.write(`e2e-tauri: could not run cargo: ${build.error.message}\n`);
			process.exit(1);
		}
		if (build.status !== 0) {
			process.stderr.write(`e2e-tauri: cargo build --features e2e failed\n`);
			process.exit(build.status ?? 1);
		}
	}
	if (!existsSync(binaryPath)) {
		process.stderr.write(`e2e-tauri: no app binary at ${binaryPath}\n`);
		process.exit(1);
	}

	const wdioCli = resolveWdioCli(frontendRoot);
	if (!existsSync(wdioCli)) {
		process.stderr.write(`e2e-tauri: no wdio cli at ${wdioCli}\n`);
		process.exit(1);
	}

	const run = spawnSync(
		process.execPath,
		[wdioCli, "run", "e2e-tauri/wdio.conf.ts", ...options.wdioArgs],
		{
			cwd: frontendRoot,
			stdio: "inherit",
			env: { ...process.env, OPERATOR_TAURI_E2E_BINARY: binaryPath },
		},
	);
	if (run.error) {
		process.stderr.write(`e2e-tauri: could not run wdio: ${run.error.message}\n`);
		process.exit(1);
	}
	if (run.status === null) {
		process.stderr.write(`e2e-tauri: wdio terminated by signal ${run.signal ?? "unknown"}\n`);
		process.exit(1);
	}
	process.exit(run.status);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
	main();
}
