// End-to-end macOS auto-update harness, Tauri edition (task 18).
//
// Does what a real user does: takes an already-installed version N-1 Tauri
// bundle, points it at a real published feed, and proves that version N is
// checked, downloaded, signature-verified, and STAGED by the shell's updater
// engine. With --expect-stage-only (the default gate while the verified apply
// path is pending) it stops at the staging record; without it the harness goes
// on to prove the install-on-quit swap and that the relaunched app reports
// version N and its daemon is alive.
//
// Dependency-free ESM so CI runs `node scripts/e2e-mac-update.mjs` directly and
// node:test unit-tests the pure argument/payload contract. macOS only.
//
// Five things about this flow are counter-intuitive. Do not "simplify" them:
//
//  1. The updater engine checks at LAUNCH and then hourly. There is no IPC to
//     trigger a check headlessly, so the harness enables updates through the
//     daemon's own loopback PATCH /api/v1/settings/updates and relaunches,
//     letting the real production launch-time check drive the flow.
//  2. Staging is observed through the engine's durable staging record
//     `<state-root>/updater/staged/<version>/meta.json`, written only after the
//     minisign signature verifies — not through any UI or log line.
//  3. A plain macOS quit does not swap bundles; the apply step owns that. Until
//     the project-owned verified apply path lands, --expect-stage-only is the
//     honest ceiling of what this harness can assert locally, and full-install
//     mode is exercised only by the designated release conductor on signed
//     builds (mac-update-e2e.yml).
//  4. Liveness is the daemon's running.json + loopback /healthz, the same
//     check backend/internal/cli/e2e_test.go uses. "A process exists" is not
//     proof the app came up.
//  5. Both launches spawn the bundle's executable DIRECTLY rather than going
//     through `open`, because the harness has to hand the app OPERATOR_RUN_FILE,
//     OPERATOR_DATA_DIR and the feed URL override. A direct spawn propagates
//     all of them; `open -a` propagates only ambient environment.
//
// usage:
//   node scripts/e2e-mac-update.mjs --app "/Applications/Operator.app" \
//     --expect-version 0.10.4 [--state-dir ~/.operator] [--channel latest|nightly] \
//     [--expect-stage-only] [--feed-url https://.../download/]
import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, isAbsolute, join } from "node:path";

const DEFAULTS = {
	channel: "latest",
	// A full mac zip is a few hundred MB; be generous but bounded.
	downloadTimeoutMs: 20 * 60 * 1000,
	// The apply swap of the staged bundle.
	swapTimeoutMs: 5 * 60 * 1000,
	// Cold start plus daemon boot.
	launchTimeoutMs: 3 * 60 * 1000,
	pollIntervalMs: 2000,
};

class UsageError extends Error {}

// parseArgs turns argv into harness options. Pure, so the flag contract is unit
// tested without launching anything. Throws UsageError on misuse (exit 2).
export function parseArgs(argv) {
	const opts = { ...DEFAULTS, expectStageOnly: false };
	for (let i = 0; i < argv.length; i += 1) {
		const flag = argv[i];
		const value = argv[i + 1];
		const needsValue = () => {
			if (value === undefined || value.startsWith("--")) throw new UsageError(`${flag} needs a value`);
			i += 1;
			return value;
		};
		switch (flag) {
			case "--app":
				opts.app = needsValue();
				break;
			case "--expect-version":
				opts.expectVersion = needsValue();
				break;
			case "--state-dir":
				opts.stateDir = needsValue();
				break;
			case "--run-file":
				opts.runFile = needsValue();
				break;
			case "--channel":
				opts.channel = needsValue();
				if (opts.channel !== "latest" && opts.channel !== "nightly") {
					throw new UsageError(`--channel must be latest or nightly, got ${opts.channel}`);
				}
				break;
			case "--feed-url":
				opts.feedUrl = validateFeedUrl(needsValue());
				break;
			case "--expect-stage-only":
				opts.expectStageOnly = true;
				break;
			case "--download-timeout":
				opts.downloadTimeoutMs = positiveSeconds(flag, needsValue());
				break;
			case "--swap-timeout":
				opts.swapTimeoutMs = positiveSeconds(flag, needsValue());
				break;
			case "--launch-timeout":
				opts.launchTimeoutMs = positiveSeconds(flag, needsValue());
				break;
			default:
				throw new UsageError(`unknown flag: ${flag}`);
		}
	}
	if (!opts.app) throw new UsageError("--app is required");
	if (!opts.expectVersion) throw new UsageError("--expect-version is required");
	if (!opts.app.endsWith(".app")) throw new UsageError(`--app must point at a .app bundle, got ${opts.app}`);
	opts.stateDir ??= join(homedir(), ".operator");
	// The run file is deleted before each launch so the liveness poll cannot pass
	// on a stale file. It must be absolute; removeRunFile validates any existing
	// target as an Operator run-file handshake before deletion.
	if (opts.runFile !== undefined) {
		if (!isAbsolute(opts.runFile)) throw new UsageError(`--run-file must be an absolute path, got ${opts.runFile}`);
	}
	if (!isAbsolute(opts.stateDir)) throw new UsageError(`--state-dir must be an absolute path, got ${opts.stateDir}`);
	opts.runFile ??= join(opts.stateDir, "running.json");
	// Durable daemon state. Mirrors backend/internal/config's resolveDataDir
	// default (<opr home>/data) so an overridden --state-dir keeps the daemon's
	// SQLite out of the real ~/.operator.
	opts.dataDir = join(opts.stateDir, "data");
	opts.appName = basename(opts.app, ".app");
	return opts;
}

function validateFeedUrl(raw) {
	let parsed;
	try {
		parsed = new URL(raw);
	} catch {
		throw new UsageError(`--feed-url must be a valid URL, got ${raw}`);
	}
	const loopback = ["127.0.0.1", "localhost", "::1"].includes(parsed.hostname);
	if (parsed.protocol !== "https:" && !(loopback && parsed.protocol === "http:")) {
		throw new UsageError(`--feed-url must be https (or loopback http), got ${raw}`);
	}
	return raw;
}

// launchEnv is the environment BOTH launches hand the app. Exported so the
// contract is testable: every one of these has to reach the app, and a missing
// override would silently point the harness at the real user state.
export function launchEnv(opts, baseEnv = process.env) {
	const env = {
		...baseEnv,
		OPERATOR_RUN_FILE: opts.runFile,
		OPERATOR_DATA_DIR: opts.dataDir,
	};
	if (opts.feedUrl) env.OPERATOR_UPDATER_FEED_URL = opts.feedUrl;
	return env;
}

// stagedMarkerPath is the durable proof an update staged: the engine writes
// meta.json only after the downloaded artifact passed minisign verification.
export function stagedMarkerPath(stateDir, version) {
	return join(stateDir, "updater", "staged", version, "meta.json");
}

// updateSettingsPayload matches the Go PATCH /api/v1/settings/updates body
// exactly (see backend/internal/httpd/controllers/settings_test.go). Nightly
// requires the instability acknowledgement or the daemon coerces it away.
export function updateSettingsPayload(channel) {
	return { enabled: true, channel, nightlyAck: channel === "nightly" };
}

// patchUpdateSettings flips auto-updates on through the daemon's loopback API —
// the same store the packaged shell reads at launch (header note 1).
export async function patchUpdateSettings(port, channel, dependencies = {}) {
	const fetchImpl = dependencies.fetchImpl ?? fetch;
	const response = await fetchImpl(`http://127.0.0.1:${port}/api/v1/settings/updates`, {
		method: "PATCH",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(updateSettingsPayload(channel)),
	});
	if (!response.ok) {
		throw new Error(`update settings PATCH failed with status ${response.status}`);
	}
}

function positiveSeconds(flag, raw) {
	const seconds = Number(raw);
	if (!Number.isFinite(seconds) || seconds <= 0) throw new UsageError(`${flag} must be a positive number of seconds`);
	return seconds * 1000;
}

// plistValue reads a key straight off the installed bundle's Info.plist, so the
// harness observes what actually swapped in rather than trusting anything the
// app reports about itself.
export function plistValue(appPath, key) {
	return execFileSync("plutil", ["-extract", key, "raw", "-o", "-", join(appPath, "Contents", "Info.plist")], {
		encoding: "utf8",
	}).trim();
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// waitFor polls until check() returns truthy or the budget runs out. Bounded
// polling, never a fixed sleep: neither the download nor the swap has a
// completion signal and both vary with bundle size and disk speed.
async function waitFor(label, timeoutMs, check) {
	const deadline = Date.now() + timeoutMs;
	for (;;) {
		let result;
		try {
			result = await check();
		} catch {
			result = false;
		}
		if (result) return result;
		if (Date.now() >= deadline) throw new Error(`timed out after ${Math.round(timeoutMs / 1000)}s waiting for ${label}`);
		await sleep(DEFAULTS.pollIntervalMs);
	}
}

// removeRunFile clears a stale daemon handshake without treating an arbitrary
// JSON file as disposable harness state. The daemon always writes pid, port and
// startedAt; require that complete shape whenever a target already exists.
export function removeRunFile(runFile) {
	if (!existsSync(runFile)) return;
	let info;
	try {
		info = JSON.parse(readFileSync(runFile, "utf8"));
	} catch {
		throw new UsageError(`refusing to remove ${runFile}: existing file is not an Operator running.json handshake`);
	}
	if (
		typeof info !== "object" ||
		info === null ||
		!Number.isInteger(info.pid) ||
		info.pid <= 0 ||
		!Number.isInteger(info.port) ||
		info.port < 1 ||
		info.port > 65535 ||
		typeof info.startedAt !== "string" ||
		Number.isNaN(Date.parse(info.startedAt))
	) {
		throw new UsageError(`refusing to remove ${runFile}: existing file is not an Operator running.json handshake`);
	}
	rmSync(runFile);
}

function quitApp(appName) {
	try {
		execFileSync("osascript", ["-e", `tell application "${appName}" to quit`], { stdio: "ignore" });
	} catch {
		// Already gone, or never registered with LaunchServices. Either is fine.
	}
}

async function isDaemonAlive(runFile) {
	if (!existsSync(runFile)) return false;
	const info = JSON.parse(readFileSync(runFile, "utf8"));
	if (!info.port) return false;
	// Same liveness contract as backend/internal/cli/e2e_test.go: loopback only.
	const res = await fetch(`http://127.0.0.1:${info.port}/healthz`, { signal: AbortSignal.timeout(5000) });
	return res.ok;
}

async function daemonPort(runFile) {
	const info = JSON.parse(readFileSync(runFile, "utf8"));
	return info.port;
}

async function run(opts) {
	if (process.platform !== "darwin") throw new UsageError(`macOS only; host is ${process.platform}`);
	if (!existsSync(opts.app)) throw new UsageError(`no such app bundle: ${opts.app}`);

	const startVersion = plistValue(opts.app, "CFBundleShortVersionString");
	console.log(`installed baseline: ${startVersion}`);
	if (startVersion === opts.expectVersion) {
		throw new UsageError(`baseline is already ${opts.expectVersion}; --expect-version must be the NEW version`);
	}
	// Fail fast on an Electron bundle: it has no Tauri updater engine, so the
	// staging poll below could only ever time out.
	const identifier = plistValue(opts.app, "CFBundleIdentifier");
	if (identifier !== "dev.operator.desktop") {
		throw new UsageError(
			`${opts.app} has CFBundleIdentifier '${identifier}', expected dev.operator.desktop; this harness drives the Tauri shell only`,
		);
	}

	// A stale instance would hold the daemon port and confuse the liveness check.
	quitApp(opts.appName);
	removeRunFile(opts.runFile);

	const env = launchEnv(opts);
	console.log(`launching ${opts.app} (channel: ${opts.channel}, run file: ${opts.runFile})`);
	spawn(join(opts.app, "Contents", "MacOS", plistValue(opts.app, "CFBundleExecutable")), [], {
		env,
		stdio: "inherit",
		detached: false,
	}).unref();

	await waitFor("the first launch's daemon to answer /healthz", opts.launchTimeoutMs, () => isDaemonAlive(opts.runFile));
	await patchUpdateSettings(await daemonPort(opts.runFile), opts.channel);
	console.log(`auto-updates enabled on channel ${opts.channel}; relaunching for the launch-time check`);

	quitApp(opts.appName);
	await sleep(5000);
	removeRunFile(opts.runFile);
	spawn(join(opts.app, "Contents", "MacOS", plistValue(opts.app, "CFBundleExecutable")), [], {
		env,
		stdio: "inherit",
		detached: false,
	}).unref();

	const marker = stagedMarkerPath(opts.stateDir, opts.expectVersion);
	await waitFor(`the updater engine to stage ${opts.expectVersion}`, opts.downloadTimeoutMs, () => existsSync(marker));
	console.log(`update staged: ${marker}`);

	if (!opts.expectStageOnly) {
		await waitFor(`the apply swap to land ${opts.expectVersion}`, opts.swapTimeoutMs, () => {
			const current = plistValue(opts.app, "CFBundleShortVersionString");
			if (current !== startVersion) console.log(`bundle version now: ${current}`);
			return current === opts.expectVersion;
		});
		console.log(`installed bundle is now ${opts.expectVersion}`);
		await waitFor("the relaunched app's daemon to answer /healthz", opts.launchTimeoutMs, () =>
			isDaemonAlive(opts.runFile),
		);
	}

	quitApp(opts.appName);
	console.log(
		opts.expectStageOnly
			? `PASS: ${startVersion} checked, verified and staged ${opts.expectVersion} (stage-only)`
			: `PASS: ${startVersion} updated to ${plistValue(opts.app, "CFBundleShortVersionString")}, relaunched, daemon alive`,
	);
}

if (import.meta.url === `file://${process.argv[1]}`) {
	let opts;
	try {
		opts = parseArgs(process.argv.slice(2));
	} catch (err) {
		process.stderr.write(`${err.message}\n`);
		process.stderr.write(
			"usage: node e2e-mac-update.mjs --app <bundle.app> --expect-version <version> [--expect-stage-only]\n",
		);
		process.exit(2);
	}
	run(opts).catch((err) => {
		process.stderr.write(`${err.stack || err}\n`);
		process.exit(err instanceof UsageError ? 2 : 1);
	});
}
