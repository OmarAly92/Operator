import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
	launchEnv,
	parseArgs,
	patchUpdateSettings,
	removeRunFile,
	stagedMarkerPath,
	updateSettingsPayload,
} from "./e2e-mac-update.mjs";

const REQUIRED = ["--app", "/Applications/Operator.app", "--expect-version", "0.10.4"];

test("parseArgs keeps the flag contract and defaults the state dir to ~/.operator", () => {
	const opts = parseArgs(REQUIRED);
	assert.equal(opts.app, "/Applications/Operator.app");
	assert.equal(opts.expectVersion, "0.10.4");
	assert.equal(opts.appName, "Operator");
	assert.equal(opts.stateDir, join(homedir(), ".operator"));
	assert.equal(opts.runFile, join(homedir(), ".operator", "running.json"));
});

test("parseArgs rejects misuse loudly before any slow work", () => {
	assert.throws(() => parseArgs(["--app"]), /needs a value/);
	assert.throws(() => parseArgs(["--app", "/Applications/Operator.app"]), /expect-version/);
	assert.throws(() => parseArgs([...REQUIRED, "--wat"]), /unknown flag/);
	assert.throws(() => parseArgs([...REQUIRED, "--app", "/Applications/Operator"]), /\.app bundle/);
	assert.throws(() => parseArgs([...REQUIRED, "--state-dir", "relative/path"]), /absolute/);
	assert.throws(() => parseArgs([...REQUIRED, "--run-file", "running.json"]), /absolute/);
	assert.throws(() => parseArgs([...REQUIRED, "--channel", "beta"]), /latest or nightly/);
});

test("parseArgs accepts latest and nightly channels", () => {
	assert.equal(parseArgs([...REQUIRED, "--channel", "latest"]).channel, "latest");
	assert.equal(parseArgs([...REQUIRED, "--channel", "nightly"]).channel, "nightly");
});

test("parseArgs accepts timeouts as positive seconds", () => {
	const opts = parseArgs([
		...REQUIRED,
		"--download-timeout",
		"30",
		"--swap-timeout",
		"60",
		"--launch-timeout",
		"45",
	]);
	assert.equal(opts.downloadTimeoutMs, 30_000);
	assert.equal(opts.swapTimeoutMs, 60_000);
	assert.equal(opts.launchTimeoutMs, 45_000);
});

test("parseArgs rejects non-positive timeouts", () => {
	for (const flag of ["--download-timeout", "--swap-timeout", "--launch-timeout"]) {
		assert.throws(() => parseArgs([...REQUIRED, flag, "0"]), /positive number/);
		assert.throws(() => parseArgs([...REQUIRED, flag, "-5"]), /positive number/);
		assert.throws(() => parseArgs([...REQUIRED, flag, "soon"]), /positive number/);
	}
});

test("parseArgs supports stage-only mode for builds without a verified apply path", () => {
	const staged = parseArgs([...REQUIRED, "--expect-stage-only"]);
	assert.equal(staged.expectStageOnly, true);
	const full = parseArgs(REQUIRED);
	assert.equal(full.expectStageOnly, false);
});

test("parseArgs validates --feed-url as https or loopback http", () => {
	const opts = parseArgs([
		...REQUIRED,
		"--feed-url",
		"https://github.com/OmarAly92/operator/releases/latest/download/",
	]);
	assert.equal(opts.feedUrl, "https://github.com/OmarAly92/operator/releases/latest/download/");
	assert.equal(
		parseArgs([...REQUIRED, "--feed-url", "http://127.0.0.1:9876/"]).feedUrl,
		"http://127.0.0.1:9876/",
	);
	assert.throws(
		() => parseArgs([...REQUIRED, "--feed-url", "http://github.com/OmarAly92/operator/"]),
		/insecure|https/,
	);
});

test("launchEnv hands the app the sentinel-free Tauri harness environment", () => {
	const base = { PATH: "/usr/bin" };
	const env = launchEnv({ runFile: "/tmp/x/running.json", dataDir: "/tmp/x/data" }, base);
	assert.equal(env.PATH, "/usr/bin");
	assert.equal(env.OPERATOR_RUN_FILE, "/tmp/x/running.json");
	assert.equal(env.OPERATOR_DATA_DIR, "/tmp/x/data");
	const withFeed = launchEnv(
		{
			runFile: "/tmp/x/running.json",
			dataDir: "/tmp/x/data",
			feedUrl: "http://127.0.0.1:9876/",
		},
		base,
	);
	assert.equal(withFeed.OPERATOR_UPDATER_FEED_URL, "http://127.0.0.1:9876/");
});

test("stagedMarkerPath points at the engine's staging record under the state root", () => {
	assert.equal(
		stagedMarkerPath("/tmp/state", "0.10.4"),
		join("/tmp/state", "tauri", "updater", "staged", "0.10.4", "meta.json"),
	);
});

test("updateSettingsPayload matches the Go updates-settings PATCH shape", () => {
	assert.deepEqual(updateSettingsPayload("latest"), { enabled: true, channel: "latest", nightlyAck: false });
	assert.deepEqual(updateSettingsPayload("nightly"), { enabled: true, channel: "nightly", nightlyAck: true });
});

test("patchUpdateSettings PATCHes the daemon loopback endpoint", async () => {
	let seen;
	const fakeFetch = async (url, init) => {
		seen = { url, init };
		return { ok: true };
	};
	await patchUpdateSettings(43110, "nightly", { fetchImpl: fakeFetch });
	assert.equal(seen.url, "http://127.0.0.1:43110/api/v1/settings/updates");
	assert.equal(seen.init.method, "PATCH");
	assert.deepEqual(JSON.parse(seen.init.body), { enabled: true, channel: "nightly", nightlyAck: true });
	const failing = async () => ({ ok: false, status: 500 });
	await assert.rejects(() => patchUpdateSettings(43110, "latest", { fetchImpl: failing }), /500|failed/i);
});

test("removeRunFile deletes only a genuine Operator running.json handshake", () => {
	const dir = mkdtempSync(join(tmpdir(), "e2e-mac-update-test-"));
	const runFile = join(dir, "running.json");

	removeRunFile(runFile);
	assert.equal(existsSync(runFile), false);

	writeFileSync(runFile, JSON.stringify({ pid: 42, port: 43110, startedAt: "2026-08-24T00:00:00.000Z" }));
	removeRunFile(runFile);
	assert.equal(existsSync(runFile), false);

	for (const bad of [
		"not json",
		JSON.stringify({ pid: -1, port: 43110, startedAt: "2026-08-24T00:00:00.000Z" }),
		JSON.stringify({ pid: 42, port: 0, startedAt: "2026-08-24T00:00:00.000Z" }),
		JSON.stringify({ pid: 42, port: 43110 }),
	]) {
		writeFileSync(runFile, bad);
		assert.throws(() => removeRunFile(runFile), /handshake/);
	}

	rmSync(dir, { recursive: true, force: true });
});
