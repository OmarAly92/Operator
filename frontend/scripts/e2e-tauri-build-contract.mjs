// Build-contract gate for the native Tauri E2E surface (task 20).
//
// Proves the load-bearing isolation claim of the e2e Cargo feature: the
// WebdriverIO plugins (tauri-plugin-wdio, tauri-plugin-wdio-webdriver — the
// embedded WebDriver server) compile ONLY when `--features e2e` is passed, and
// lib.rs registers them only behind `cfg(feature = "e2e")`. A normal debug or
// production build therefore contains neither plugin crate, no driver port
// env var, and no driver startup marker string.
//
// Checks, in order:
//  1. `cargo tree` on default features contains neither plugin crate; the same
//     query with `--features e2e` contains BOTH (positive control — the feature
//     actually wires the plugins rather than silently resolving to nothing).
//  2. src-tauri/src/lib.rs registers both `init()` calls inside a
//     `#[cfg(feature = "e2e")]` block, and no registration line appears
//     outside one.
//  3. When OPERATOR_TAURI_E2E_PLAIN_BINARY points at a built normal binary,
//     the driver marker string must be ABSENT from it; when
//     OPERATOR_TAURI_E2E_DRIVER_BINARY points at an e2e build, the marker must
//     be PRESENT. CI sets both; local runs skip the binary legs.
//
// Dependency-free ESM; pure helpers are unit-tested in
// e2e-tauri-build-contract.test.mjs via `npm run test:e2e-tauri:build-contract:unit`.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const manifestPath = path.join("src-tauri", "Cargo.toml");

export const WDIO_CRATES = ["tauri-plugin-wdio", "tauri-plugin-wdio-webdriver"];
export const DRIVER_MARKER = "WDIO WebDriver plugin initialized on port";
export const REGISTRATION_GUARD = "#[cfg(feature = \"e2e\")]";
export const REGISTRATION_CALLS = ["tauri_plugin_wdio::init()", "tauri_plugin_wdio_webdriver::init()"];

export function cargoTreeCrates(stdout) {
	return stdout
		.split("\n")
		.map((line) => {
			const match = line.match(/(?:^|[\s(\[])([a-z0-9_-]+) v\d/);
			return match?.[1];
		})
		.filter((name) => name !== undefined);
}

export function assertFeatureIsolation(treeWithout, treeWith) {
	const without = new Set(cargoTreeCrates(treeWithout));
	const with_ = new Set(cargoTreeCrates(treeWith));
	const errors = [];
	for (const crate of WDIO_CRATES) {
		if (without.has(crate)) errors.push(`default-feature build resolves ${crate}; it must be e2e-only`);
		if (!with_.has(crate)) errors.push(`e2e-feature build does not resolve ${crate}; the feature is broken`);
	}
	return errors;
}

// registrationErrors scans lib.rs and requires every WDIO registration call to
// sit inside a `#[cfg(feature = "e2e")]` block. The scan is deliberately textual:
// the guard is a cfg attribute whose span tracking would otherwise pull in a
// TypeScript-scale parser dependency for one check.
export function registrationErrors(sourceText) {
	const errors = [];
	const guardPositions = [];
	let index = sourceText.indexOf(REGISTRATION_GUARD);
	while (index >= 0) {
		guardPositions.push(index);
		index = sourceText.indexOf(REGISTRATION_GUARD, index + 1);
	}
	for (const call of REGISTRATION_CALLS) {
		let callIndex = sourceText.indexOf(call);
		if (callIndex < 0) {
			errors.push(`lib.rs never registers ${call}`);
			continue;
		}
		while (callIndex >= 0) {
			const guarding = guardPositions.some((guard) => guard < callIndex);
			if (!guarding) errors.push(`${call} is registered outside a ${REGISTRATION_GUARD} block`);
			callIndex = sourceText.indexOf(call, callIndex + 1);
		}
	}
	return errors;
}

// binaryContainsDriver reads the built binary and looks for the driver startup
// marker literal. Rust keeps the tracing format string in the binary, so a plain
// byte search is exact — no fuzzy symbol heuristics.
export function binaryContainsDriver(buffer) {
	return buffer.includes(DRIVER_MARKER);
}

function runCargoTree(features) {
	const args = ["tree", "--manifest-path", manifestPath, "--locked"];
	if (features) args.push("--features", features);
	return execFileSync("cargo", args, { cwd: frontendRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

export function buildContractErrors({ treeWithout, treeWith, libRs, plainBinary, driverBinary }) {
	const errors = [
		...assertFeatureIsolation(treeWithout, treeWith),
		...registrationErrors(libRs),
	];
	if (plainBinary !== undefined && binaryContainsDriver(plainBinary)) {
		errors.push("normal build binary contains the embedded WebDriver marker; the e2e feature leaked");
	}
	if (driverBinary !== undefined && !binaryContainsDriver(driverBinary)) {
		errors.push("e2e-feature binary does not contain the embedded WebDriver marker; registration is broken");
	}
	return errors;
}

function main() {
	const treeWithout = runCargoTree(undefined);
	const treeWith = runCargoTree("e2e");
	const libRs = readFileSync(path.join(frontendRoot, "src-tauri", "src", "lib.rs"), "utf8");
	const readOptionalBinary = (name) => {
		const value = process.env[name];
		return value ? readFileSync(value) : undefined;
	};
	const errors = buildContractErrors({
		treeWithout,
		treeWith,
		libRs,
		plainBinary: readOptionalBinary("OPERATOR_TAURI_E2E_PLAIN_BINARY"),
		driverBinary: readOptionalBinary("OPERATOR_TAURI_E2E_DRIVER_BINARY"),
	});
	if (errors.length > 0) {
		process.stderr.write(`${errors.join("\n")}\n`);
		process.exit(1);
	}
	process.stdout.write(
		`e2e-tauri build contract holds: WDIO plugins resolve only under --features e2e, registration is cfg-guarded${
			process.env.OPERATOR_TAURI_E2E_PLAIN_BINARY ? ", normal binary carries no driver marker" : ""
		}${process.env.OPERATOR_TAURI_E2E_DRIVER_BINARY ? ", e2e binary carries the driver marker" : ""}.\n`,
	);
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
	main();
}
