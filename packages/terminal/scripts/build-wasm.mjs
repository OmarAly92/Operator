#!/usr/bin/env node
import { existsSync, statSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const manifestPath = join(packageRoot, "Cargo.toml");
const wasmSource = join(
	packageRoot,
	"target",
	"wasm32-unknown-unknown",
	"release",
	"vt_wasm.wasm",
);
const outDir = join(packageRoot, "ts", "core", "wasm");
const expectedOutputs = ["vt_core.js", "vt_core.d.ts", "vt_core_bg.wasm", "vt_core_bg.wasm.d.ts"];

const requiredRustcPrefix = "rustc 1.96.0";
const requiredWasmTarget = "wasm32-unknown-unknown";
const requiredBindgenVersion = "wasm-bindgen 0.2.127";

const force = process.argv.includes("--force");

function fail(message) {
	process.stderr.write(`build-wasm: ${message}\n`);
	process.exit(1);
}

function runChecked(file, args) {
	const result = spawnSync(file, args, { stdio: "inherit" });
	if (result.status !== 0) {
		process.exit(result.status ?? 1);
	}
}

function versionOutput(file, args) {
	const result = spawnSync(file, args, { encoding: "utf8" });
	if (result.status !== 0) {
		fail(`${file} ${args.join(" ")} exited with code ${result.status ?? "null"}`);
	}
	return (result.stdout ?? "").trim();
}

function checkToolchain() {
	const rustcLine = versionOutput("rustc", ["--version"]);
	if (!rustcLine.startsWith(requiredRustcPrefix)) {
		fail(`rustc version mismatch: expected '${requiredRustcPrefix}' prefix, got '${rustcLine}'`);
	}

	const targetsLine = versionOutput("rustup", ["target", "list", "--installed"]);
	const installed = targetsLine.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
	if (!installed.includes(requiredWasmTarget)) {
		fail(`rustup target ${requiredWasmTarget} is not installed (have: ${installed.join(", ")})`);
	}

	const bindgenLine = versionOutput("wasm-bindgen", ["--version"]);
	if (bindgenLine !== requiredBindgenVersion) {
		fail(
			`wasm-bindgen version mismatch: expected exactly '${requiredBindgenVersion}', got '${bindgenLine}'`,
		);
	}
}

function oldestOutputMtime() {
	let oldest = Number.POSITIVE_INFINITY;
	for (const name of expectedOutputs) {
		const path = join(outDir, name);
		if (!existsSync(path)) {
			return null;
		}
		const mtime = statSync(path).mtimeMs;
		if (mtime < oldest) {
			oldest = mtime;
		}
	}
	return oldest;
}

function rustSourceMtime() {
	const candidates = [
		join(packageRoot, "crates", "vt-wasm", "src", "lib.rs"),
		join(packageRoot, "crates", "vt-wasm", "Cargo.toml"),
		join(packageRoot, "crates", "vt-core", "src", "lib.rs"),
		join(packageRoot, "crates", "vt-core", "Cargo.toml"),
		join(packageRoot, "Cargo.toml"),
		join(packageRoot, "Cargo.lock"),
	];
	let newest = 0;
	for (const path of candidates) {
		if (!existsSync(path)) {
			continue;
		}
		const mtime = statSync(path).mtimeMs;
		if (mtime > newest) {
			newest = mtime;
		}
	}
	return newest;
}

function needsRebuild() {
	if (force) {
		return true;
	}
	if (!existsSync(wasmSource)) {
		return true;
	}
	const oldest = oldestOutputMtime();
	if (oldest === null) {
		return true;
	}
	return rustSourceMtime() > oldest;
}

function buildWasm() {
	runChecked("cargo", [
		"build",
		"--manifest-path",
		manifestPath,
		"-p",
		"vt-wasm",
		"--target",
		"wasm32-unknown-unknown",
		"--release",
		"--locked",
	]);
}

function runWasmBindgen() {
	if (!existsSync(wasmSource)) {
		fail(`expected wasm artifact at ${wasmSource} but it was not produced`);
	}
	runChecked("wasm-bindgen", [
		wasmSource,
		"--target",
		"web",
		"--out-dir",
		outDir,
		"--out-name",
		"vt_core",
	]);
}

function verifyOutputs() {
	for (const name of expectedOutputs) {
		const path = join(outDir, name);
		if (!existsSync(path)) {
			fail(`expected generated output missing: ${path}`);
		}
	}
}

checkToolchain();
if (needsRebuild()) {
	buildWasm();
	runWasmBindgen();
} else {
	process.stdout.write("build-wasm: outputs are up to date\n");
}
verifyOutputs();

process.stdout.write("build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready\n");
