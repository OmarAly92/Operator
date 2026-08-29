import assert from "node:assert/strict";
import test from "node:test";
import { startReporter, terminateProcessGroup } from "./smoke-tauri.mjs";

const expectedReport = { status: "ready", text: "red caféplain", rows: 2, runs: 3 };

async function close(server) {
	await new Promise((resolveClose) => server.close(resolveClose));
}

test("accepts only one concurrent valid report", async () => {
	const reporter = await startReporter("/one-shot");
	try {
		const responses = await Promise.all([
			fetch(reporter.url, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(expectedReport),
			}),
			fetch(reporter.url, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(expectedReport),
			}),
		]);
		assert.deepEqual(responses.map((response) => response.status).sort(), [204, 409]);
		assert.deepEqual(await reporter.report, expectedReport);
	} finally {
		await close(reporter.server);
	}
});

test("signals a retained process group after its leader has exited", async () => {
	const signals = [];
	await terminateProcessGroup(12345, {
		platform: "darwin",
		kill: (processGroupId, signal) => {
			signals.push([processGroupId, signal]);
		},
		wait: async () => {},
	});
	assert.deepEqual(signals, [[-12345, "SIGTERM"], [-12345, "SIGKILL"]]);
});

test("treats a confirmed missing process group as clean", async () => {
	const signals = [];
	await terminateProcessGroup(12345, {
		platform: "darwin",
		kill: (processGroupId, signal) => {
			signals.push([processGroupId, signal]);
			const error = new Error("missing process group");
			error.code = "ESRCH";
			throw error;
		},
		wait: async () => {},
	});
	assert.deepEqual(signals, [[-12345, "SIGTERM"]]);
});
