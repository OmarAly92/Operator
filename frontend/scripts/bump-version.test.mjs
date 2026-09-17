import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { bumpFiles } from "./bump-version.mjs";

function fixture() {
	const root = mkdtempSync(join(tmpdir(), "bump-version-"));
	mkdirSync(join(root, "src-tauri"));
	writeFileSync(join(root, "package.json"), JSON.stringify({ name: "operator", version: "0.1.0" }, null, 2));
	writeFileSync(
		join(root, "package-lock.json"),
		JSON.stringify({ name: "operator", version: "0.1.0", packages: { "": { version: "0.1.0" } } }, null, 2),
	);
	writeFileSync(join(root, "src-tauri", "Cargo.toml"), '[package]\nname = "operator"\nversion = "0.1.0"\nedition = "2021"\n');
	writeFileSync(
		join(root, "src-tauri", "Cargo.lock"),
		'[[package]]\nname = "libc"\nversion = "0.2.0"\n\n[[package]]\nname = "operator"\nversion = "0.1.0"\n',
	);
	return root;
}

test("bumpFiles rewrites every version declaration", () => {
	const root = fixture();
	assert.deepEqual(bumpFiles(root, "0.2.0"), { previous: "0.1.0", version: "0.2.0" });
	assert.equal(JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version, "0.2.0");
	const lock = JSON.parse(readFileSync(join(root, "package-lock.json"), "utf8"));
	assert.equal(lock.version, "0.2.0");
	assert.equal(lock.packages[""].version, "0.2.0");
	assert.match(readFileSync(join(root, "src-tauri", "Cargo.toml"), "utf8"), /^version = "0\.2\.0"$/m);
	const cargoLock = readFileSync(join(root, "src-tauri", "Cargo.lock"), "utf8");
	assert.match(cargoLock, /name = "operator"\nversion = "0\.2\.0"/);
	assert.match(cargoLock, /name = "libc"\nversion = "0\.2\.0"/);
});

test("bumpFiles rejects a non-semver version", () => {
	assert.throws(() => bumpFiles(fixture(), "v1"), /not a semver version/);
});
