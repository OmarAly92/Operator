// Native Tauri shell E2E (task 20). Drives a real `e2e`-feature debug build of
// src-tauri through the @wdio/tauri-service embedded provider: the WebDriver
// server runs INSIDE the app, so everything asserted here exercises the same
// process a packaged user runs — window, renderer webview, Tauri commands,
// tray/menu/shortcut state, and the daemon the shell owns.
//
// Scope contract with perf/parity-ledger.json ("status" field): every assertion
// here is named in that ledger as `e2e-tauri:desktop`. Behaviors that cannot be
// driven headlessly (real native chooser click-through, OS-level hotkey
// synthesis, notification click activation, verified update install) stay on
// their named lower-level contract tests or external gates and are NOT faked
// here. The build-contract proof that the embedded driver is absent from normal
// builds lives in scripts/e2e-tauri-build-contract.mjs, not in this suite.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import packageJson from "../package.json";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type RunFile = { pid: number; port: number; startedAt: string };

function requireEnv(name: string): string {
	const value = process.env[name];
	if (!value) throw new Error(`${name} must be set by wdio.conf.ts`);
	return value;
}

// wdio.conf.ts pins the state dir into the environment before workers fork, so
// every process in the run resolves the same dir the app was pointed at.
const stateDir = requireEnv("OPERATOR_E2E_STATE_DIR");
const runFile = path.join(stateDir, "running.json");

function readRunFile(): RunFile {
	return JSON.parse(readFileSync(runFile, "utf8")) as RunFile;
}

function apiBase(): string {
	return `http://127.0.0.1:${readRunFile().port}`;
}

async function waitForDaemon(timeoutMs = 120_000): Promise<number> {
	const deadline = Date.now() + timeoutMs;
	for (;;) {
		try {
			const run = readRunFile();
			const response = await fetch(`http://127.0.0.1:${run.port}/healthz`, { signal: AbortSignal.timeout(2_000) });
			if (response.ok) return run.port;
		} catch {
			// Daemon not answering yet; keep polling until the deadline.
		}
		if (Date.now() >= deadline) throw new Error("the app-owned daemon never answered /healthz");
		await sleep(500);
	}
}

async function rest(method: string, pathname: string, body?: unknown): Promise<any> {
	const { ok, status, payload } = await restRaw(method, pathname, body);
	assert.equal(ok, true, `${method} ${pathname} failed with ${status}: ${JSON.stringify(payload)}`);
	return payload;
}

async function restRaw(
	method: string,
	pathname: string,
	body?: unknown,
): Promise<{ ok: boolean; status: number; payload: any }> {
	const response = await fetch(`${apiBase()}${pathname}`, {
		method,
		headers: body === undefined ? undefined : { "content-type": "application/json" },
		body: body === undefined ? undefined : JSON.stringify(body),
		signal: AbortSignal.timeout(30_000),
	});
	const payload = await response.json().catch(() => null);
	return { ok: response.ok, status: response.status, payload };
}

async function invoke(command: string, args?: Record<string, unknown>): Promise<any> {
	const script =
		`return window.__TAURI_INTERNALS__.invoke(${JSON.stringify(command)}, ${JSON.stringify(args ?? {})})`;
	return browser.execute(script);
}

async function invokeUntil(command: string, args: Record<string, unknown> | undefined, until: (result: any) => boolean, timeoutMs = 30_000): Promise<any> {
	const deadline = Date.now() + timeoutMs;
	let last: unknown;
	for (;;) {
		last = await invoke(command, args).catch((error: Error) => ({ __error: error.message }));
		if (!("__error" in (last as object)) && until(last)) return last;
		if (Date.now() >= deadline) {
			assert.fail(`${command} never reached the expected state; last: ${JSON.stringify(last)}`);
		}
		await sleep(500);
	}
}

async function waitForDom(testid: string, timeoutMs = 60_000): Promise<void> {
	const deadline = Date.now() + timeoutMs;
	for (;;) {
		const present = await browser.execute(
			`return document.querySelector(${JSON.stringify(`[data-testid="${testid}"]`)}) !== null`,
		);
		if (present === true) return;
		if (Date.now() >= deadline) assert.fail(`[data-testid="${testid}"] never appeared in the renderer`);
		await sleep(500);
	}
}

async function waitForDomGone(testid: string, timeoutMs = 30_000): Promise<void> {
	const deadline = Date.now() + timeoutMs;
	for (;;) {
		const present = await browser.execute(
			`return document.querySelector(${JSON.stringify(`[data-testid="${testid}"]`)}) !== null`,
		);
		if (present === false) return;
		if (Date.now() >= deadline) assert.fail(`[data-testid="${testid}"] never left the renderer`);
		await sleep(500);
	}
}

function jsClick(testid: string): Promise<unknown> {
	return browser.execute(
		`const el = document.querySelector(${JSON.stringify(`[data-testid="${testid}"]`)});
		 if (!el) throw new Error("missing element ${testid}");
		 el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
		 return true;`,
	);
}

describe("Operator Tauri desktop parity", () => {
	before(async () => {
		await waitForDaemon();
	});

	it("boots the real renderer through the embedded WebDriver session", async () => {
		const body = await $("body");
		assert.equal(await body.isExisting(), true, "WebDriver cannot see the app webview DOM");
		await waitForDom("app-shell-ready", 90_000);
		const version = await invoke("plugin:app|version");
		assert.equal(version, packageJson.version, "shell version disagrees with package.json");
	});

	it("writes the launch marker for this exact binary under the isolated state root", () => {
		const marker = JSON.parse(readFileSync(path.join(stateDir, "app-state.json"), "utf8")) as Record<string, unknown>;
		assert.equal(marker.schemaVersion, 2);
		assert.match(String(marker.version), /^\d+\.\d+\.\d+/);
		assert.ok(String(marker.appPath).includes("operator"), `marker appPath misses the app binary: ${marker.appPath}`);
		assert.ok(existsSync(runFile), "daemon handshake running.json missing");
		const run = readRunFile();
		assert.ok(Number.isInteger(run.pid) && run.pid > 0);
		assert.ok(Number.isInteger(run.port) && run.port > 0);
		assert.ok(typeof run.startedAt === "string" && !Number.isNaN(Date.parse(run.startedAt)));
	});

	it("creates and opens a project registered with the app-owned daemon", async () => {
		const repo = mkdtempSync(path.join(os.tmpdir(), "operator-e2e-repo-"));
		try {
			writeFileSync(path.join(repo, "README.md"), "operator e2e\n");
			execFileSync("git", ["init", "-q"], { cwd: repo });
			execFileSync("git", ["add", "."], { cwd: repo });
			execFileSync("git", ["-c", "user.name=e2e", "-c", "user.email=e2e@invalid", "commit", "-qm", "init"], { cwd: repo });
			const created = await rest("POST", "/api/v1/projects", { path: repo });
			const projectId = String(created.project?.id ?? created.project?.projectId ?? "");
			assert.notEqual(projectId, "", "project add returned no id");
			const opened = await rest("GET", `/api/v1/projects/${encodeURIComponent(projectId)}`);
			assert.equal(String(opened.project?.id ?? opened.id ?? projectId), projectId);
			await rest("DELETE", `/api/v1/projects/${encodeURIComponent(projectId)}`);
		} finally {
			rmSync(repo, { recursive: true, force: true });
		}
	});

	it("runs a terminal mux round trip through a shell-terminal session", async () => {
		const opened = await rest("POST", "/api/v1/shell-terminals", {});
		const handleId = String(opened.shellTerminal?.handleId ?? "");
		assert.notEqual(handleId, "", "shell terminal open returned no handle");

		const marker = `operator-e2e-mux-${Math.floor(Math.random() * 1_000_000)}`;
		const socket = new WebSocket(`ws://127.0.0.1:${readRunFile().port}/mux`);
		try {
			assert.equal(
				await Promise.race([
					new Promise<boolean>((resolve, reject) => {
						socket.addEventListener("open", () => resolve(true), { once: true });
						socket.addEventListener("error", () => reject(new Error("mux websocket failed to open")), { once: true });
					}),
					sleep(20_000).then(() => false),
				]),
				true,
				"mux websocket did not open",
			);

			const received: string[] = [];
			let openedAck = deferPromise();
			let gotMarker = deferPromise();
			socket.addEventListener("message", (event: MessageEvent) => {
				if (typeof event.data !== "string") return;
				const frame = JSON.parse(event.data) as { ch?: string; type?: string; id?: string; data?: string };
				if (frame.ch !== "terminal") return;
				if (frame.type === "opened" && frame.id === handleId) openedAck.resolve();
				if (frame.type === "data" && frame.id === handleId && frame.data) {
					const text = Buffer.from(frame.data, "base64").toString("utf8");
					received.push(text);
					if (text.includes(marker)) gotMarker.resolve();
				}
			});

			socket.send(JSON.stringify({ ch: "terminal", type: "open", id: handleId, cols: 80, rows: 24 }));
			await withTimeout(openedAck.promise, 30_000, "mux never acknowledged the pane open");
			socket.send(
				JSON.stringify({ ch: "terminal", type: "data", id: handleId, data: Buffer.from(`echo ${marker}\r`, "utf8").toString("base64") }),
			);
			await withTimeout(gotMarker.promise, 60_000, `mux never echoed ${marker}`);
			assert.ok(received.join("").includes(marker));
		} finally {
			socket.close();
			await rest("DELETE", `/api/v1/shell-terminals/${encodeURIComponent(handleId)}`).catch(() => undefined);
		}
	});

	it("round-trips text through the native clipboard", async () => {
		const text = `operator-e2e-clipboard-${Date.now()}`;
		await invoke("clipboard_write", { text });
		assert.equal(await invoke("clipboard_read"), text);
	});

	it("stages and removes dropped files inside the shell state root", async () => {
		const name = "e2e-drop.txt";
		const bytes = Buffer.from("dropped through the native seam\n", "utf8");
		const stagedPath = String(await invoke("stage_dropped_file", { name, data: bytes.toString("base64") }));
		try {
			assert.ok(stagedPath.startsWith(path.join(stateDir, "tauri", "terminal-drops")), `staged outside the state root: ${stagedPath}`);
			assert.equal(readFileSync(stagedPath, "utf8"), bytes.toString("utf8"));
		} finally {
			await invoke("delete_dropped_file", { path: stagedPath });
		}
		assert.equal(existsSync(stagedPath), false, "delete_dropped_file left the staged copy behind");
		assert.rejects(() => invoke("stage_dropped_file", { name, data: "not base64!!" }), /base64/);
	});

	it("applies theme, overlay, menu, shortcut, tray, and notification seams", async () => {
		await invoke("theme_set", { preference: "dark" });
		await invoke("theme_set", { preference: "system" });
		await invoke("window_set_overlay", { color: "#0f1014", symbolColor: "#ffffff" });
		assert.equal(await invoke("window_is_fullscreen"), false);
		await invoke("menu_action", { action: "zoomIn" });
		await invoke("menu_action", { action: "zoomOut" });
		await invoke("menu_action", { action: "zoomReset" });
		await invoke("shell_focus");

		await invoke("keybindings_apply", {
			overrides: { "new-session": [{ key: "e", ctrl: true, meta: false, shift: false, alt: false }] },
		});
		// Restored immediately: an override is a LIVE GLOBAL HOTKEY, not UI state.
		// Leaving one registered would hijack the real machine (and spawn real
		// sessions) for every later keystroke until the next full reset.
		await invoke("keybindings_apply", { overrides: {} });
		await invoke("keybindings_recording", { active: true });
		await invoke("keybindings_recording", { active: false });
		await invoke("set_close_shell_terminal_shortcut_enabled", { enabled: false });
		await invoke("set_close_shell_terminal_shortcut_enabled", { enabled: true });

		await invoke("tray_attention_state", {
			attention: {
				sessions: [{ projectId: "p", projectName: "parity", sessionId: "s", title: "parity", zone: "merge" }],
			},
		});
		await invoke("tray_renderer_ready");
		await invoke("tray_set_locale", { locale: "en" });

		assert.deepEqual(
			await invoke("notification_show", { notification: { id: "", title: "ignored by policy" } }),
			null,
		);
		await invoke("notification_badge", { count: 3 });
		await invoke("notification_badge", { count: 0 });
		await invoke("notification_dev_bounce");
	});

	it("covers the external preview seams: manual validator matrix and the automatic preview-opened ack route", async () => {
		// Manual external preview: the shell-owned seam is the URL validator at the
		// open_external IPC boundary (the same command the renderer's manual
		// reopen path and automatic preview opener both funnel through).
		for (const url of ["ftp://operator.invalid/setup", "file:///etc/passwd", "javascript:alert(1)"]) {
			await invoke("open_external", { url }).then(
				() => assert.fail(`open_external accepted a disallowed scheme: ${url}`),
				(error: Error) => assert.match(error.message, /Unsupported external URL/),
			);
		}
		// Happy-path acceptance at the IPC boundary. Everything after the validator
		// is the OS opener handoff (tauri-plugin-opener), whose outcome depends on
		// the runner's desktop handlers — a headless Linux xdg-open rejects even
		// though the shell surface behaved correctly. The deterministic,
		// cross-platform assertion is therefore: an http preview target passes
		// validation and reaches the opener (any rejection must be the OS's, never
		// the validator's). Pointing at the daemon's own healthz keeps the target
		// loopback-local wherever a handler does open it.
		const openerOutcome = await invoke("open_external", {
			url: `http://127.0.0.1:${readRunFile().port}/healthz`,
		}).then(
			() => "opened",
			(error: Error) => error.message,
		);
		assert.notEqual(
			openerOutcome,
			"Unsupported external URL",
			"an http preview target must pass the open_external validator",
		);

		// Automatic preview: after the opener succeeds the renderer acks once per
		// revision on the daemon's loopback-only /internal/desktop route. The
		// route-level contract is provable without a live agent session: mounted
		// (not ROUTE_NOT_FOUND), strict body validation, revision guard, and a
		// typed service error for an unknown session.
		const revisionGuard = await restRaw("POST", "/internal/desktop/sessions/e2e-bogus/preview-opened", {
			revision: 0,
		});
		assert.equal(revisionGuard.status, 400);
		assert.equal(revisionGuard.payload.code, "REVISION_REQUIRED");

		const malformed = await restRaw("POST", "/internal/desktop/sessions/e2e-bogus/preview-opened", {
			revision: "one",
			unexpected: true,
		});
		assert.equal(malformed.status, 400);
		assert.equal(malformed.payload.code, "INVALID_JSON");

		const unknownSession = await restRaw("POST", "/internal/desktop/sessions/e2e-bogus/preview-opened", {
			revision: 1,
		});
		assert.equal(unknownSession.status, 404);
		assert.equal(unknownSession.payload.code, "SESSION_NOT_FOUND");
		assert.notEqual(unknownSession.payload.code, "ROUTE_NOT_FOUND");
	});

	it("reports the dev-build fail-closed updater surface through the engine IPC", async () => {
		assert.equal(await invoke("feature_builds_active"), null);
		await invoke("updates_check", { requestId: "e2e-check" });
		const status = await invokeUntil("updates_status", undefined, (value) => value?.state !== "checking");
		assert.equal(status.state, "unsupported");
		assert.match(String(status.message ?? ""), /installed app/i);
		await invoke("updates_apply_settings", {
			settings: { enabled: true, channel: "latest", nightlyAck: false, feature: null },
		});
	});

	it("persists ui, keybinding, update, and migration settings across daemon stop/start/restart", async () => {
		await rest("PATCH", "/api/v1/settings/ui", { locale: "ja" });
		await rest("PATCH", "/api/v1/settings/keybindings", {
			"new-session": [{ key: "e", ctrl: true }],
		});
		await rest("PATCH", "/api/v1/settings/updates", { enabled: true, channel: "nightly", nightlyAck: true });
		await rest("PATCH", "/api/v1/settings/migration", {
			status: "declined",
			lastAttemptAt: new Date().toISOString(),
		});

		await invoke("daemon_stop");
		const stopDeadline = Date.now() + 60_000;
		for (;;) {
			try {
				await fetch(`${apiBase()}/healthz`, { signal: AbortSignal.timeout(1_000) });
			} catch {
				break;
			}
			if (Date.now() >= stopDeadline) assert.fail("daemon_stop left a live daemon behind");
			await sleep(500);
		}
		await invoke("daemon_start");
		await waitForDaemon();

		await invoke("daemon_restart");
		await waitForDaemon();

		const settings = await rest("GET", "/api/v1/settings");
		assert.equal(settings.ui?.locale, "ja");
		assert.deepEqual(settings.updates, { enabled: true, channel: "nightly", nightlyAck: true });
		assert.deepEqual(settings.keybindings?.["new-session"], [
			{ key: "e", ctrl: true, meta: false, shift: false, alt: false },
		]);
		assert.equal(settings.migration?.status, "declined");

		await rest("PATCH", "/api/v1/settings/ui", { locale: "en" });
		await rest("PATCH", "/api/v1/settings/keybindings", {});
		await rest("PATCH", "/api/v1/settings/updates", { enabled: false, channel: "latest", nightlyAck: false });
		await rest("PATCH", "/api/v1/settings/migration", { status: "pending" });
		await invoke("updates_apply_settings", {
			settings: { enabled: false, channel: "latest", nightlyAck: false, feature: null },
		});
	});

	it("answers standalone-browser route wiring through the daemon adapter", async () => {
		const response = await fetch(`${apiBase()}/api/v1/browser/status?sessionId=operator-e2e-probe`, {
			signal: AbortSignal.timeout(30_000),
		});
		const payload = (await response.json()) as Record<string, unknown>;
		assert.notEqual(response.status, 501, "standalone browser adapter is not wired into the daemon");
		if (response.ok) {
			assert.equal(payload.transport, "agent-browser-standalone");
		} else {
			assert.equal(typeof payload.error, "string", "expected the locked error envelope");
			assert.notEqual(payload.error, "");
			assert.equal(typeof payload.code, "string");
			assert.notEqual(payload.code, "");
			assert.equal(typeof payload.requestId, "string");
			assert.notEqual(payload.requestId, "");
		}
	});

	it("shows the first-run update opt-in once and persists the decline", async () => {
		// Force the fresh-ask path regardless of anything that answered the
		// prompt earlier in this webview's lifetime: clear the asked flag and
		// reload, then the prompt must come back exactly once.
		await browser.execute(
			"localStorage.removeItem('operator-update-opt-in-asked'); location.reload(); return true;",
		).catch(() => undefined);
		await waitForDom("app-shell-ready", 90_000);
		await waitForDom("updates-opt-in", 90_000);
		await jsClick("updates-opt-in-decline");
		await waitForDomGone("updates-opt-in");
		const settings = await rest("GET", "/api/v1/settings");
		assert.equal(settings.updates?.enabled, false, "declining opt-in must persist disabled updates");

		await browser.execute("location.reload(); return true;").catch(() => undefined);
		await waitForDom("app-shell-ready", 90_000);
		await waitForDomGone("updates-opt-in", 45_000);
		const asked = await browser.execute("return localStorage.getItem(\"operator-update-opt-in-asked\")");
		assert.equal(asked, "1", "opt-in decision was not remembered across reloads");
	});
});

function deferPromise(): { promise: Promise<void>; resolve: () => void } {
	let resolve!: () => void;
	const promise = new Promise<void>((res) => {
		resolve = res;
	});
	return { promise, resolve };
}

async function withTimeout(promise: Promise<void>, timeoutMs: number, message: string): Promise<void> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	try {
		await Promise.race([
			promise,
			new Promise((_resolve, reject) => {
				timer = setTimeout(() => reject(new Error(message)), timeoutMs);
			}),
		]);
	} finally {
		if (timer) clearTimeout(timer);
	}
}
