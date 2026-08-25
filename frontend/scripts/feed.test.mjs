import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
	buildYml,
	feedFilename,
	generateFeeds,
	hashFile,
	selectInstallers,
} from "./feed.mjs";
import { writeBlockmap } from "./blockmap.mjs";

const V = "0.10.4";
const NAMES = [
	"Agent.Orchestrator.Setup.0.10.4.exe", // win versioned
	"Agent.Orchestrator-0.10.4.AppImage", // linux versioned
	"Agent.Orchestrator-darwin-arm64-0.10.4.zip", // mac arm64 versioned
	"Agent.Orchestrator-darwin-x64-0.10.4.zip", // mac x64 versioned
	"operator-darwin-arm64.zip", // opr-start alias (no version) -> excluded
	"operator-win32-x64.exe", // alias (no version) -> excluded
	"operator_0.10.4_amd64.deb", // deb -> excluded by extension
	"operator-0.10.4.x86_64.rpm", // rpm -> excluded by extension
];

test("selectInstallers keeps only versioned exe/AppImage/darwin-zip, split by arch", () => {
	const s = selectInstallers(NAMES, V);
	assert.deepEqual(s.win, ["Agent.Orchestrator.Setup.0.10.4.exe"]);
	assert.deepEqual(s.linux, ["Agent.Orchestrator-0.10.4.AppImage"]);
	assert.deepEqual(s.macArm64, ["Agent.Orchestrator-darwin-arm64-0.10.4.zip"]);
	assert.deepEqual(s.macX64, ["Agent.Orchestrator-darwin-x64-0.10.4.zip"]);
});

test("selectInstallers also selects Tauri-built NSIS, AppImage and ditto zip names", () => {
	const tauriNames = [
		"Operator_0.10.4_x64-setup.exe",
		"operator_0.10.4_amd64.AppImage",
		"Operator-darwin-arm64-0.10.4.zip",
		"Operator-darwin-x64-0.10.4.zip",
		"Operator_0.10.4_x64_en-US.msi",
	];
	const s = selectInstallers(tauriNames, V);
	assert.deepEqual(s.win, ["Operator_0.10.4_x64-setup.exe"]);
	assert.deepEqual(s.linux, ["operator_0.10.4_amd64.AppImage"]);
	assert.deepEqual(s.macArm64, ["Operator-darwin-arm64-0.10.4.zip"]);
	assert.deepEqual(s.macX64, ["Operator-darwin-x64-0.10.4.zip"]);
});

test("feedFilename maps channel + platform to electron-updater names", () => {
	assert.equal(feedFilename("latest", "win"), "latest.yml");
	assert.equal(feedFilename("latest", "mac"), "latest-mac.yml");
	assert.equal(feedFilename("latest", "linux"), "latest-linux.yml");
	assert.equal(feedFilename("nightly", "win"), "nightly.yml");
	assert.equal(feedFilename("nightly", "mac"), "nightly-mac.yml");
	assert.equal(feedFilename("nightly", "linux"), "nightly-linux.yml");
});

test("pr<N> channel isolation guards against #2270 latest-mac.yml poisoning", () => {
	assert.equal(feedFilename("pr2270", "mac"), "pr2270-mac.yml");
	assert.equal(feedFilename("pr2270", "linux"), "pr2270-linux.yml");
	assert.equal(feedFilename("pr2270", "win"), "pr2270.yml");
	for (const platform of ["mac", "linux", "win"]) {
		assert.doesNotMatch(feedFilename("pr2270", platform), /^latest/);
		assert.doesNotMatch(feedFilename("pr2270", platform), /^nightly/);
	}
});

test("buildYml serializes one file with deprecated top-level fields and no blockMapSize", () => {
	const yml = buildYml(
		"0.10.4",
		[{ url: "Agent.Orchestrator.Setup.0.10.4.exe", sha512: "AA/BB+cc==", size: 123 }],
		"2026-06-27T12:00:00.000Z",
	);
	assert.equal(
		yml,
		"version: 0.10.4\n" +
			"files:\n" +
			"  - url: Agent.Orchestrator.Setup.0.10.4.exe\n" +
			"    sha512: AA/BB+cc==\n" +
			"    size: 123\n" +
			"path: Agent.Orchestrator.Setup.0.10.4.exe\n" +
			"sha512: AA/BB+cc==\n" +
			"releaseDate: '2026-06-27T12:00:00.000Z'\n",
	);
	assert.ok(!yml.includes("blockMapSize"));
});

test("buildYml lists both mac arches with arm64 first and points top-level at arm64", () => {
	const yml = buildYml(
		"0.10.4",
		[
			{ url: "Agent.Orchestrator-darwin-arm64-0.10.4.zip", sha512: "ARM==", size: 10 },
			{ url: "Agent.Orchestrator-darwin-x64-0.10.4.zip", sha512: "X64==", size: 20 },
		],
		"2026-06-27T12:00:00.000Z",
	);
	const lines = yml.split("\n");
	assert.equal(lines[2], "  - url: Agent.Orchestrator-darwin-arm64-0.10.4.zip");
	assert.equal(lines[5], "  - url: Agent.Orchestrator-darwin-x64-0.10.4.zip");
	assert.ok(yml.includes("path: Agent.Orchestrator-darwin-arm64-0.10.4.zip"));
});

test("buildYml omits important when false and emits it when true", () => {
	const off = buildYml(
		"0.10.4",
		[{ url: "Agent.Orchestrator.Setup.0.10.4.exe", sha512: "AA/BB+cc==", size: 123 }],
		"2026-06-27T12:00:00.000Z",
		false,
	);
	assert.ok(!off.includes("important"));
	const on = buildYml(
		"0.10.4",
		[{ url: "Agent.Orchestrator.Setup.0.10.4.exe", sha512: "AA/BB+cc==", size: 123 }],
		"2026-06-27T12:00:00.000Z",
		true,
	);
	assert.ok(on.includes("important: true\n"));
	assert.ok(on.includes("version: 0.10.4"));
	assert.match(on, /releaseDate:/);
});

test("hashFile computes sha512 (base64) and byte size without writing any sidecar", () => {
	const dir = mkdtempSync(join(tmpdir(), "feed-test-"));
	const filePath = join(dir, "sample.zip");
	const content = "fake zip contents for hashing";
	writeFileSync(filePath, content);

	const { sha512, size } = hashFile(filePath);

	assert.equal(sha512, createHash("sha512").update(Buffer.from(content)).digest("base64"));
	assert.equal(size, Buffer.byteLength(content));
	assert.equal(existsSync(`${filePath}.blockmap`), false);

	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds mac zips never produce a .blockmap sidecar (#3034)", async () => {
	const dir = mkdtempSync(join(tmpdir(), "feed-test-"));
	const macZip = "Agent.Orchestrator-darwin-arm64-0.10.4.zip";
	writeFileSync(join(dir, macZip), "fake mac zip");

	await generateFeeds(dir, "0.10.4", "nightly", "2026-06-27T12:00:00.000Z");

	assert.equal(existsSync(join(dir, `${macZip}.blockmap`)), false);
	const yml = readFileSync(join(dir, "nightly-mac.yml"), "utf8");
	assert.ok(!yml.includes("blockMapSize"));
	assert.ok(yml.includes(`url: ${macZip}`));

	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds still writes blockmaps for win and linux installers by default", async () => {
	const dir = mkdtempSync(join(tmpdir(), "feed-test-"));
	const winExe = "Agent.Orchestrator.Setup.0.10.4.exe";
	const linuxAppImage = "Agent.Orchestrator-0.10.4.AppImage";
	writeFileSync(join(dir, winExe), "fake win installer");
	writeFileSync(join(dir, linuxAppImage), "fake linux installer");

	await generateFeeds(dir, "0.10.4", "nightly", "2026-06-27T12:00:00.000Z");

	const names = readdirSync(dir);
	assert.ok(names.includes(`${winExe}.blockmap`));
	assert.ok(names.includes(`${linuxAppImage}.blockmap`));

	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds blockmap:false writes no sidecars anywhere (Tauri migration baseline)", async () => {
	const dir = mkdtempSync(join(tmpdir(), "feed-test-"));
	writeFileSync(join(dir, "Operator_0.10.4_x64-setup.exe"), "fake nsis");
	writeFileSync(join(dir, "operator_0.10.4_amd64.AppImage"), "fake appimage");
	let blockmapCalls = 0;
	const spy = async () => {
		blockmapCalls += 1;
		return { sha512: "SPY", size: 1 };
	};

	await generateFeeds(dir, "0.10.4", "latest", "2026-08-24T00:00:00Z", false, { blockmap: false, writeBlockmap: spy });

	assert.equal(blockmapCalls, 0);
	const names = readdirSync(dir);
	assert.ok(!names.some((name) => name.endsWith(".blockmap")));
	assert.ok(names.includes("latest.yml"));
	assert.ok(names.includes("latest-linux.yml"));

	rmSync(dir, { recursive: true, force: true });
});
