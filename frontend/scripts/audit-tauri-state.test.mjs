import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { assertConfined, settledStateSnapshot, snapshotTargets } from "./audit-tauri-state.mjs";

test("exact Operator state is audited without enumerating its protected parent", async () => {
	const fixtureRoot = await mkdtemp(path.join(os.tmpdir(), "operator-state-audit-test-"));
	const protectedParent = path.join(fixtureRoot, "Cookies");
	const operatorCookie = path.join(protectedParent, "dev.operator.desktop.binarycookies");
	await mkdir(protectedParent);
	await writeFile(operatorCookie, "cookie");

	const snapshot = await snapshotTargets(
		[
			{ statePath: protectedParent, depth: 0 },
			{ statePath: operatorCookie, depth: Number.POSITIVE_INFINITY },
		],
		async (statePath, options) => {
			if (statePath === protectedParent) {
				const error = new Error("protected");
				error.code = "EPERM";
				throw error;
			}
			return readdir(statePath, options);
		},
	);

	assert.equal(snapshot.has(operatorCookie), true);
});

test("an exact Operator state target outside the allowed root fails the audit", async () => {
	const fixtureRoot = await mkdtemp(path.join(os.tmpdir(), "operator-state-audit-test-"));
	const allowedRoot = path.join(fixtureRoot, "allowed");
	const outsideOperatorState = path.join(fixtureRoot, "dev.operator.desktop");
	await mkdir(allowedRoot);

	const targets = [
		{ statePath: allowedRoot, depth: Number.POSITIVE_INFINITY },
		{ statePath: outsideOperatorState, depth: Number.POSITIVE_INFINITY },
	];
	const beforeSnapshot = await snapshotTargets(targets);
	await writeFile(path.join(allowedRoot, "state"), "allowed");
	await writeFile(outsideOperatorState, "outside");
	const afterSnapshot = await snapshotTargets(targets);

	assert.throws(
		() => assertConfined(beforeSnapshot, afterSnapshot, allowedRoot, "shutdown"),
		/wrote state outside the allowed root/,
	);
});

test("the audit entry point reaches executable validation", async () => {
	const fixtureRoot = await mkdtemp(path.join(os.tmpdir(), "operator-state-audit-test-"));
	const auditScript = fileURLToPath(new URL("./audit-tauri-state.mjs", import.meta.url));
	const execution = spawnSync(process.execPath, [auditScript], {
		env: {
			...process.env,
			OPERATOR_DATA_DIR: path.join(fixtureRoot, "data"),
			OPERATOR_RUN_FILE: path.join(fixtureRoot, "running.json"),
			OPERATOR_TAURI_AUDIT_EXECUTABLE: path.join(fixtureRoot, "missing-operator"),
		},
		encoding: "utf8",
	});

	assert.equal(execution.status, 1);
	assert.match(execution.stderr, /ENOENT/);
	assert.doesNotMatch(execution.stderr, /is not a function/);
});

test("the audit observes state that appears after the crashed process exits", async () => {
	const delayedStatePath = path.join(os.tmpdir(), "operator-delayed-crash-report");
	const emptySnapshot = new Map();
	const delayedSnapshot = new Map([[delayedStatePath, "file:1:1"]]);
	const snapshots = [emptySnapshot, emptySnapshot, delayedSnapshot, delayedSnapshot, delayedSnapshot];
	let elapsed = 0;

	const settledSnapshot = await settledStateSnapshot(
		async () => snapshots.shift() ?? delayedSnapshot,
		{
			now: () => elapsed,
			pause: async (milliseconds) => {
				elapsed += milliseconds;
			},
			minimumObservationMs: 3,
			timeoutMs: 10,
			pollIntervalMs: 1,
			requiredStableSamples: 2,
		},
	);

	assert.equal(settledSnapshot.has(delayedStatePath), true);
});
