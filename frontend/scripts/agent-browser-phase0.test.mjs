import assert from "node:assert/strict";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
	EXIT_CODES,
	assertSafeArguments,
	buildProbeEnvironment,
	createConcurrencyCoordinator,
	createSessionRoot,
	crossModeCookieIsolation,
	locateManagedExecutable,
	mapOutcomeToExitCode,
	runMode,
	sanitizeDoctorReport,
	sanitizeEvidenceText,
	scanForSessionElectronProcesses,
	serializeInstall,
} from "./agent-browser-phase0.mjs";

test("bounded process output never retains more than the configured byte limit", async () => {
	const { createBoundedOutput } = await import("./agent-browser-phase0.mjs");
	const output = createBoundedOutput(8);
	output.append(Buffer.from("123456"));
	output.append(Buffer.from("789012345"));
	assert.equal(Buffer.byteLength(output.text()), 8);
	assert.equal(output.truncated(), true);
});

function fakeSpawn(responses) {
	const calls = [];
	let pending = Promise.resolve();
	const spawn = (request) => {
		const result = pending.then(() => {
			const response = responses.shift();
			if (!response) throw new Error(`unexpected spawn: ${request.file} ${request.args.join(" ")}`);
			if (typeof response === "function") return response(request);
			return response;
		});
		pending = result.then(
			() => {},
			() => {},
		);
		calls.push({ request, result });
		return result;
	};
	return { spawn, calls };
}

test("probe environment allowlists exactly the session-scoped variables", () => {
	const sessionRoot = path.join(os.tmpdir(), "operator-abp-env");
	const parent = {
		HOME: "/Users/someone",
		USERPROFILE: "C:\\Users\\someone",
		AGENT_BROWSER_CDP: "http://127.0.0.1:9222",
		ELECTRON_RUN_AS_NODE: "1",
		ELECTRON_NO_ATTACH_CONSOLE: "1",
		PATH: "/usr/bin:/bin",
		LANG: "en_US.UTF-8",
		SOME_SECRET_TOKEN: "leak",
	};
	const env = buildProbeEnvironment(sessionRoot, parent, "darwin");
	assert.equal(env.HOME, sessionRoot);
	assert.equal(env.USERPROFILE, sessionRoot);
	assert.equal(env.PATH, "/usr/bin:/bin");
	assert.equal(env.AGENT_BROWSER_CDP, undefined);
	assert.equal(env.ELECTRON_RUN_AS_NODE, undefined);
	assert.ok(env.AGENT_BROWSER_SOCKET_DIR.startsWith(sessionRoot));
	assert.ok(env.XDG_CACHE_HOME.startsWith(sessionRoot));
	assert.ok(env.XDG_CONFIG_HOME.startsWith(sessionRoot));
	assert.ok(env.XDG_DATA_HOME.startsWith(sessionRoot));
	assert.ok(env.TMPDIR.startsWith(sessionRoot));
	assert.equal(env.SOME_SECRET_TOKEN, undefined);
});

test("probe environment carries windows essentials when on windows", () => {
	const sessionRoot = path.join(os.tmpdir(), "operator-abp-win");
	const env = buildProbeEnvironment(sessionRoot, { PATH: "C:\\Windows", SYSTEMROOT: "C:\\Windows", COMSPEC: "cmd.exe" }, "win32");
	assert.equal(env.SYSTEMROOT, "C:\\Windows");
	assert.equal(env.COMSPEC, "cmd.exe");
	assert.ok(env.LOCALAPPDATA.startsWith(sessionRoot));
});

async function policyRejects(args, options) {
	assert.throws(() => assertSafeArguments(args, options ?? { sessionRoot: "/tmp/root", platform: "darwin" }));
}

test("policy rejects cdp auto-connect and unsafe startup arguments", async () => {
	await policyRejects(["--cdp", "http://127.0.0.1:9222"]);
	await policyRejects(["open", "http://127.0.0.1:1/", "--auto-connect"]);
	await policyRejects(["--remote-debugging-port", "9222"]);
	await policyRejects(["--no-sandbox"]);
	await policyRejects(["--load-extension", "/tmp/plugin"]);
	await policyRejects(["--plugins"]);
});

test("policy rejects user profiles arbitrary executables and proxy credentials", async () => {
	await policyRejects(["--user-data-dir", "/Users/someone/Library/Application Support/Chrome"]);
	await policyRejects(["--profile", "/Users/someone"]);
	await policyRejects(["--executable-path", "/opt/evil/chrome"]);
	await policyRejects(["--proxy-server", "http://user:pass@proxy.example:8080"]);
	await policyRejects(["--proxy-bypass-list", "<-loopback>"]);
});

test("policy rejects unknown commands flags and non-loopback open targets", async () => {
	await policyRejects(["shell", "rm -rf /"]);
	await policyRejects(["open", "http://evil.example/"]);
	await policyRejects(["open", "file:///etc/passwd"]);
	await policyRejects(["snapshot", "--everything"]);
	await policyRejects(["screenshot", "/etc/passwd"], { sessionRoot: "/tmp/root", platform: "darwin" });
});

test("policy allows the documented command vocabulary", () => {
	const options = { sessionRoot: "/tmp/root", platform: "darwin" };
	assertSafeArguments(["doctor", "--json"], options);
	assertSafeArguments(["install", "--json"], options);
	assertSafeArguments(["open", "http://127.0.0.1:45931/", "--json"], options);
	assertSafeArguments(["snapshot", "-i", "--json"], options);
	assertSafeArguments(["click", "@e1", "--json"], options);
	assertSafeArguments(["console", "--json"], options);
	assertSafeArguments(["errors", "--json"], options);
	assertSafeArguments(["screenshot", "/tmp/root/artifacts/page.png", "--json"], options);
	assertSafeArguments(["tab", "new", "http://127.0.0.1:45931/", "--json"], options);
	assertSafeArguments(["tab", "list", "--json"], options);
	assertSafeArguments(["tab", "close", "3", "--json"], options);
	assertSafeArguments(["close", "--json"], options);
});

test("install is serialized through a single flight", async () => {
	let started = 0;
	let release;
	const gate = new Promise((resolve) => {
		release = resolve;
	});
	const install = serializeInstall(async () => {
		started += 1;
		await gate;
		return "done";
	});
	const first = install();
	const second = install();
	release("done");
	assert.equal(await first, "done");
	assert.equal(await second, "done");
	assert.equal(started, 1);
});

test("failed install cleans partial engine directories from the session root", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-partial-"));
	const engineDir = path.join(sessionRoot, ".agent-browser", "browsers", "chromium-144");
	await mkdir(engineDir, { recursive: true });
	await writeFile(path.join(engineDir, "partial.download"), "bytes");
	const { spawn, calls } = fakeSpawn([
		{ code: 0, stdout: JSON.stringify({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }), stderr: "" },
		{ code: 1, stdout: "", stderr: "download interrupted" },
	]);
	let cleaned = [];
	const outcome = await runMode("managed", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		cleanupHook: async (root) => {
			cleaned.push(root);
			await rm(root, { recursive: true, force: true });
		},
	});
	assert.equal(calls.length >= 1, true);
	assert.equal(cleaned.includes(sessionRoot), true);
	await assert.rejects(() => readdir(engineDir), { code: "ENOENT" });
	assert.equal(outcome.outcome !== "pass", true);
});

test("each session gets its own isolated home under the operator state root", async () => {
	const base = await mkdtemp(path.join(os.tmpdir(), "operator-abp-homes-"));
	const first = await createSessionRoot(base, "system");
	const second = await createSessionRoot(base, "managed");
	assert.notEqual(first.root, second.root);
	assert.ok(first.root.startsWith(base));
	assert.ok(second.root.startsWith(base));
	const env = buildProbeEnvironment(first.root, {}, "linux");
	assert.equal(env.HOME, first.root);
});

test("command timeouts kill the child and report a timeout outcome", async () => {
	const { spawn, calls } = fakeSpawn([
		(request) =>
			new Promise((resolve) => {
				request.registerKill(() => resolve({ code: null, stdout: "", stderr: "killed", signal: "SIGKILL" }));
			}),
	]);
	const outcome = await runMode("system", {
		sessionRoot: path.join(os.tmpdir(), "operator-abp-timeout-"),
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		doctorTimeoutMs: 5,
		pause: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
	});
	assert.equal(outcome.outcome, "timeout");
	assert.equal(calls[0].request.timeoutMs, 5);
});

test("cancellation kills the child and reports a cancelled outcome", async () => {
	const controller = new AbortController();
	const { spawn } = fakeSpawn([
		(request) =>
			new Promise((resolve) => {
				request.registerKill(() => resolve({ code: null, stdout: "", stderr: "", signal: "SIGTERM" }));
			}),
	]);
	controller.abort();
	const outcome = await runMode("system", {
		sessionRoot: path.join(os.tmpdir(), "operator-abp-cancel-"),
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		signal: controller.signal,
	});
	assert.equal(outcome.outcome, "cancelled");
});

test("captured output is truncated at the configured limit", async () => {
	const big = "x".repeat(2 * 1024 * 1024);
	const { spawn } = fakeSpawn([{ code: 0, stdout: big, stderr: "" }]);
	const outcome = await runMode("system", {
		sessionRoot: path.join(os.tmpdir(), "operator-abp-output-"),
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		outputLimitBytes: 64 * 1024,
	});
	const doctorStep = outcome.steps.find((step) => step.command === "doctor");
	assert.equal(doctorStep.outputTruncated, true);
	assert.ok(doctorStep.stdoutBytes <= 64 * 1024 + 16);
});

test("doctor evidence is sanitized to identifiers statuses and counts", () => {
	const raw = {
		success: true,
		summary: { pass: 2, warn: 0, fail: 0 },
		checks: [
			{ id: "chrome", category: "browser", status: "pass", message: "Chrome at /Users/someone/Applications/Chrome.app", fix: "install it" },
			{ id: "network", category: "net", status: "warn", message: "slow" },
		],
		fixed: [],
	};
	const clean = sanitizeDoctorReport(raw);
	assert.deepEqual(clean.summary, { pass: 2, warn: 0, fail: 0 });
	assert.equal(clean.checks.length, 2);
	assert.deepEqual(clean.checks[0], { id: "chrome", category: "browser", status: "pass" });
	assert.equal(JSON.stringify(clean).includes("/Users/someone"), false);
	assert.equal(JSON.stringify(clean).includes("message"), false);
});

test("electron scan flags only processes scoped to this session", () => {
	const sessionRoot = "/tmp/operator-abp-session";
	const listing = [
		"  101  /Applications/Visual Studio Code.app/Contents/MacOS/Electron .",
		`  202  /tmp/operator-abp-session/.agent-browser/browsers/chromium --flag`,
		`  303  /tmp/operator-abp-session/electron Electron Helper (renderer)`,
		"  404  Slack Helper",
	].join("\n");
	const flagged = scanForSessionElectronProcesses(listing, [sessionRoot]);
	assert.deepEqual(flagged, [{ pid: "303", command: "/tmp/operator-abp-session/electron Electron Helper (renderer)" }]);
});

test("managed executable is located across platform layouts", () => {
	const darwinRoot = "/root";
	assert.equal(
		locateManagedExecutable(
			{
				"/root/.agent-browser/browsers/chromium-144/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing": true,
			},
			darwinRoot,
			"darwin",
		),
		"/root/.agent-browser/browsers/chromium-144/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
	);
	assert.equal(
		locateManagedExecutable({ "/root/.agent-browser/browsers/chromium-144/chrome-linux64/chrome": true }, "/root", "linux"),
		"/root/.agent-browser/browsers/chromium-144/chrome-linux64/chrome",
	);
	assert.equal(
		locateManagedExecutable({ "/root\\.agent-browser\\browsers\\chromium-144\\chrome-win64\\chrome.exe": true }, "/root", "win32"),
		"/root\\.agent-browser\\browsers\\chromium-144\\chrome-win64\\chrome.exe",
	);
	assert.equal(locateManagedExecutable({}, "/root", "linux"), null);
});

test("outcomes map to stable exit codes", () => {
	assert.equal(mapOutcomeToExitCode("pass"), 0);
	assert.equal(mapOutcomeToExitCode("usage"), EXIT_CODES.USAGE);
	assert.equal(mapOutcomeToExitCode("browser-absent"), EXIT_CODES.BROWSER_ABSENT);
	assert.equal(mapOutcomeToExitCode("network"), EXIT_CODES.NETWORK);
	assert.equal(mapOutcomeToExitCode("action-failed"), EXIT_CODES.ACTION_FAILED);
	assert.equal(mapOutcomeToExitCode("electron-detected"), EXIT_CODES.ELECTRON_DETECTED);
	assert.equal(mapOutcomeToExitCode("timeout"), EXIT_CODES.TIMEOUT);
	assert.equal(mapOutcomeToExitCode("cancelled"), EXIT_CODES.CANCELLED);
});

test("evidence text scrubbing removes session root paths", () => {
	const sessionRoot = "/tmp/operator-abp-scrub";
	const scrubbed = sanitizeEvidenceText(`saved to ${sessionRoot}/artifacts/page.png`, [sessionRoot]);
	assert.equal(scrubbed.includes(sessionRoot), false);
	assert.ok(scrubbed.includes("<session-root>"));
});

test("system mode happy path runs the full action suite without cdp or electron", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-e2e-"));
	const seenEnvs = [];
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const { spawn, calls } = fakeSpawn([
		jsonBody({
			success: true,
			summary: { pass: 3, warn: 0, fail: 0 },
			checks: [
				{ id: "chrome", category: "browser", status: "pass", message: "Chrome at /Applications/Chrome.app" },
				{ id: "node", category: "runtime", status: "pass", message: "ok" },
				{ id: "network", category: "net", status: "pass", message: "ok" },
			],
		}),
		(request) => {
			seenEnvs.push(request.env);
			return jsonBody({ ok: true, pageId: "p1" });
		},
		{ code: 0, stdout: `  900  ${sessionRoot}/.agent-browser/chromium --headless`, stderr: "" },
		jsonBody({ ok: true }),
		jsonBody({ ok: true }),
		jsonBody({ messages: ["hello"] }),
		jsonBody({ errors: [] }),
		jsonBody({ ok: true, path: "page.png" }),
		jsonBody({ ok: true }),
		jsonBody({ tabs: [] }),
		jsonBody({ ok: true }),
		jsonBody({ ok: true }),
		{ code: 0, stdout: "", stderr: "" },
	]);
	const outcome = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		fixturePort: 45931,
		binaryPath: "/tmp/agent-browser",
		cleanupHook: async () => {},
	});
	assert.equal(outcome.outcome, "pass", JSON.stringify(outcome));
	const commands = calls.map((call) => (call.request.scanStep ? "process-scan" : call.request.args[0]));
	assert.deepEqual(commands, [
		"doctor",
		"open",
		"process-scan",
		"snapshot",
		"click",
		"console",
		"errors",
		"screenshot",
		"tab",
		"tab",
		"tab",
		"close",
		"process-scan",
	]);
	for (const env of seenEnvs) {
		assert.equal(env.AGENT_BROWSER_CDP, undefined);
	}
	assert.deepEqual(outcome.electronProcessesInSession, []);
	assert.equal(outcome.daemonStarted, false);
	const evidenceText = JSON.stringify(outcome.evidence);
	assert.equal(evidenceText.includes(sessionRoot), false);
});

test("browser evidence proves isolation while running and cleanup after close", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-live-proof-"));
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const { spawn } = fakeSpawn([
		jsonBody({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }),
		jsonBody({ ok: true }),
		{ code: 0, stdout: `  901  ${sessionRoot}/.agent-browser/chromium --headless`, stderr: "" },
		jsonBody({ ok: true }),
		{ code: 0, stdout: "", stderr: "" },
	]);
	const result = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		now: () => 0,
		fixturePort: 45931,
		binaryPath: "/tmp/agent-browser",
		scenario: { actions: ["open {fixture} --json", "close --json"] },
		cleanupHook: async () => {},
	});
	assert.equal(result.outcome, "pass");
	assert.equal(result.evidence.isolatedWhileRunning, true);
	assert.equal(result.evidence.cleanupPassed, true);
	assert.equal(result.evidence.stateRootRemoved, true);
	assert.equal(result.evidence.observedProcessCount, 1);
});

test("a failed action still closes the browser before removing its isolated state", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-failure-cleanup-"));
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const { spawn, calls } = fakeSpawn([
		jsonBody({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }),
		jsonBody({ ok: true }),
		{ code: 0, stdout: `  902  ${sessionRoot}/.agent-browser/chromium --headless`, stderr: "" },
		{ code: 1, stdout: "", stderr: "snapshot failed" },
		jsonBody({ ok: true }),
		{ code: 0, stdout: "", stderr: "" },
	]);
	const result = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		now: () => 0,
		fixturePort: 45931,
		binaryPath: "/tmp/agent-browser",
		scenario: { actions: ["open {fixture} --json", "snapshot -i --json"] },
		cleanupHook: async () => {},
	});
	assert.equal(result.outcome, "action-failed");
	assert.ok(calls.some(({ request }) => request.args?.[0] === "close"));
	assert.equal(result.evidence.cleanupPassed, true);
});

test("absent browser in system mode maps to the stable browser-absent outcome", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-absent-"));
	const { spawn } = fakeSpawn([
		{
			code: 0,
			stdout: JSON.stringify({
				success: false,
				summary: { pass: 0, warn: 0, fail: 2 },
				checks: [
					{ id: "chrome", category: "browser", status: "fail", message: "missing at /Applications" },
					{ id: "edge", category: "browser", status: "fail", message: "missing" },
				],
			}),
			stderr: "",
		},
	]);
	const outcome = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		homedir: os.homedir,
		now: () => 0,
		binaryPath: "/tmp/agent-browser",
		cleanupHook: async () => {},
	});
	assert.equal(outcome.outcome, "browser-absent");
	assert.equal(mapOutcomeToExitCode(outcome.outcome), EXIT_CODES.BROWSER_ABSENT);
});

test("scenarios file defines both modes within the policy vocabulary", async () => {
	const { readFile } = await import("node:fs/promises");
	const scenariosFile = new URL("../perf/browser/scenarios.json", import.meta.url);
	const scenarios = JSON.parse(await readFile(scenariosFile, "utf8"));
	for (const mode of ["system", "managed"]) {
		assert.ok(scenarios[mode], `missing scenario ${mode}`);
		assert.ok(scenarios[mode].actions.length > 0);
		for (const action of scenarios[mode].actions) {
			assertSafeArguments(action.split(" ").filter(Boolean), {
				sessionRoot: "/tmp/root",
				platform: "darwin",
			});
		}
	}
	assert.ok(scenarios.managed.actions.some((action) => action.startsWith("install")));
});

test("truncated command output fails closed like timeouts", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-truncate-"));
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const { spawn } = fakeSpawn([
		jsonBody({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }),
		{ code: 0, stdout: `${"y".repeat(4096)}not-retained`, stderr: "", outputTruncated: true },
	]);
	const outcome = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		now: () => 0,
		fixturePort: 45931,
		binaryPath: "/tmp/agent-browser",
		outputLimitBytes: 64,
		scenario: { actions: ["open {fixture} --json"] },
		cleanupHook: async () => {},
	});
	assert.equal(outcome.outcome, "truncated");
	assert.equal(mapOutcomeToExitCode("truncated"), EXIT_CODES.OUTPUT_TRUNCATED);
});

test("cookie actions are allowed within the policy vocabulary for loopback targets", async () => {
	const options = { sessionRoot: "/tmp/root", platform: "darwin" };
	assertSafeArguments(["cookies", "set", "phase0_system_marker", "system", "--url", "http://127.0.0.1:45931/", "--json"], options);
	assertSafeArguments(["cookies", "get", "--json"], options);
	assertSafeArguments(["cookies", "clear", "--json"], options);
	await policyRejects(["cookies", "set", "phase0_system_marker", "system", "--url", "http://evil.example/", "--json"]);
});

test("cookie distinctness is observed per mode and recorded in evidence", async () => {
	const sessionRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-cookies-"));
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const { spawn, calls } = fakeSpawn([
		jsonBody({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }),
		jsonBody({ ok: true }),
		{ code: 0, stdout: `  911  ${sessionRoot}/.agent-browser/chromium --headless`, stderr: "" },
		jsonBody({ ok: true }),
		jsonBody([{ name: "phase0_system_marker", value: "system", domain: "127.0.0.1" }]),
		jsonBody({ ok: true }),
		{ code: 0, stdout: "", stderr: "" },
	]);
	const result = await runMode("system", {
		sessionRoot,
		spawnImpl: spawn,
		platform: "darwin",
		now: () => 0,
		fixturePort: 45931,
		binaryPath: "/tmp/agent-browser",
		scenario: {
			actions: [
				"open {fixture} --json",
				"cookies set phase0_system_marker system --url {fixture} --json",
				"cookies get --json",
				"close --json",
			],
		},
		cleanupHook: async () => {},
	});
	assert.equal(result.outcome, "pass", JSON.stringify(result.evidence));
	assert.deepEqual(result.evidence.cookies.observedNames, ["phase0_system_marker"]);
	assert.equal(result.evidence.cookies.markerPresent, true);
	assert.ok(calls.some(({ request }) => request.args?.[0] === "cookies"));
	const evidenceText = JSON.stringify(result.evidence);
	assert.equal(evidenceText.includes(sessionRoot), false);
});

test("cross-mode cookie isolation requires every mode marker to stay inside its own session", () => {
	const system = { cookies: { observedNames: ["phase0_system_marker"], markerPresent: true } };
	const managed = { cookies: { observedNames: ["phase0_managed_marker"], markerPresent: true } };
	assert.equal(crossModeCookieIsolation({ system, managed }), true);
	const leaked = { system, managed: { cookies: { observedNames: ["phase0_managed_marker", "phase0_system_marker"], markerPresent: true } } };
	assert.equal(crossModeCookieIsolation(leaked), false);
	const missingMarker = { system: { cookies: { observedNames: [], markerPresent: false } }, managed };
	assert.equal(crossModeCookieIsolation(missingMarker), false);
});

test("both modes are concurrently active and observe each other through one process scan", async () => {
	const systemRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-conc-system-"));
	const managedRoot = await mkdtemp(path.join(os.tmpdir(), "operator-abp-conc-managed-"));
	const jsonBody = (payload) => ({ code: 0, stdout: JSON.stringify(payload), stderr: "" });
	const managedEngine = path.join(
		managedRoot,
		".agent-browser",
		"browsers",
		"chromium-144",
		"chrome-mac-arm64",
		"Google Chrome for Testing.app",
		"Contents",
		"MacOS",
		"Google Chrome for Testing",
	);
	await mkdir(path.dirname(managedEngine), { recursive: true });
	await writeFile(managedEngine, "#!/bin/sh\n", { mode: 0o755 });
	const makeSpawn = (sessionRoot, otherRoot, isManaged) => fakeSpawn([
		jsonBody({ success: true, summary: { pass: 1, warn: 0, fail: 0 }, checks: [{ id: "chrome", category: "browser", status: "pass" }] }),
		...(isManaged ? [jsonBody({ ok: true })] : []),
		jsonBody({ ok: true }),
		(request) => new Promise((resolve) => setTimeout(() => resolve({
			code: 0,
			stdout: [
				`  921  ${sessionRoot}/.agent-browser/chromium --headless`,
				`  922  ${otherRoot}/.agent-browser/chromium --headless`,
			].join("\n"),
			stderr: "",
		}), 25)),
		(request) => new Promise((resolve) => setTimeout(() => resolve({
			code: 0,
			stdout: [
				`  921  ${sessionRoot}/.agent-browser/chromium --headless`,
				`  922  ${otherRoot}/.agent-browser/chromium --headless`,
			].join("\n"),
			stderr: "",
		}), 25)),
		jsonBody({ ok: true }),
	]);
	const peersByMode = {};
	const registerArrival = (mode) => async (peers) => {
		peersByMode[mode] = peers;
		return peers;
	};
	const coordinator = createConcurrencyCoordinator(["system", "managed"], registerArrival);
	const [system, managed] = await Promise.all([
		runMode("system", {
			sessionRoot: systemRoot,
			spawnImpl: makeSpawn(systemRoot, managedRoot, false).spawn,
			platform: "darwin",
			now: () => 0,
			fixturePort: 45931,
			binaryPath: "/tmp/agent-browser",
			scenario: { actions: ["open {fixture} --json", "close --json"] },
			concurrency: coordinator.forMode("system"),
			cleanupHook: async () => {},
		}),
		runMode("managed", {
			sessionRoot: managedRoot,
			spawnImpl: makeSpawn(managedRoot, systemRoot, true).spawn,
			platform: "darwin",
			now: () => 0,
			fixturePort: 45931,
			binaryPath: "/tmp/agent-browser",
			scenario: { actions: ["open {fixture} --json", "close --json"] },
			concurrency: coordinator.forMode("managed"),
			cleanupHook: async () => {},
		}),
	]);
	assert.equal(system.outcome, "pass", JSON.stringify(system.evidence));
	assert.equal(managed.outcome, "pass", JSON.stringify(managed.evidence));
	assert.equal(system.evidence.concurrentlyActiveModes.length, 1);
	assert.equal(system.evidence.peerBrowserProcessCount >= 1, true);
	assert.equal(managed.evidence.peerBrowserProcessCount >= 1, true);
});
