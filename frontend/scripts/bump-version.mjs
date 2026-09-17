// Sets the desktop version everywhere it is declared: package.json,
// package-lock.json, src-tauri/Cargo.toml and Cargo.lock. The Tauri config reads
// package.json, and a shell test asserts Cargo.toml agrees with it.
//
//   node scripts/bump-version.mjs <version>
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

export function bumpFiles(root, version) {
	if (!SEMVER.test(version)) throw new Error(`bump-version: '${version}' is not a semver version`);
	const pkgPath = join(root, "package.json");
	const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
	const previous = pkg.version;
	pkg.version = version;
	writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);

	const lockPath = join(root, "package-lock.json");
	const lock = JSON.parse(readFileSync(lockPath, "utf8"));
	lock.version = version;
	if (lock.packages && lock.packages[""]) lock.packages[""].version = version;
	writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`);

	const cargoPath = join(root, "src-tauri", "Cargo.toml");
	const cargo = readFileSync(cargoPath, "utf8");
	const bumpedCargo = cargo.replace(/^version = "[^"]+"/m, `version = "${version}"`);
	if (bumpedCargo === cargo && !cargo.includes(`version = "${version}"`)) {
		throw new Error("bump-version: no [package] version line in src-tauri/Cargo.toml");
	}
	writeFileSync(cargoPath, bumpedCargo);

	const cargoLockPath = join(root, "src-tauri", "Cargo.lock");
	const cargoLock = readFileSync(cargoLockPath, "utf8");
	const bumpedLock = cargoLock.replace(
		/(\[\[package\]\]\nname = "operator"\nversion = )"[^"]+"/,
		`$1"${version}"`,
	);
	writeFileSync(cargoLockPath, bumpedLock);
	return { previous, version };
}

if (import.meta.url === `file://${process.argv[1]}`) {
	const version = process.argv[2];
	if (!version) {
		process.stderr.write("usage: node scripts/bump-version.mjs <version>\n");
		process.exit(2);
	}
	const root = join(dirname(fileURLToPath(import.meta.url)), "..");
	const { previous } = bumpFiles(root, version);
	process.stdout.write(`${previous} -> ${version}\n`);
}
