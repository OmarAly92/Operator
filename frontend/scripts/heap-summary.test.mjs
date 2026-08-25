import assert from "node:assert/strict";
import test from "node:test";
import {
	buildDisposalResult,
	buildEmptyBoardResult,
	parsePosixProcessTable,
	processTreeIds,
	retentionSummary,
	shellVsDaemonBytes,
	subtreeTotalBytes,
	validateDisposalAcks,
	validateHeapResultSchema,
} from "./heap-summary.mjs";

const posixTable = [
	"  PID  PPID   RSS",
	"    1     0 100000",
	"    2     1   20000",
	"    3     1   30000",
	"    4     3    5000",
	"    5     4    7000",
	"  garbage that does not parse",
].join("\n");

test("parsePosixProcessTable keeps only finite pid/ppid/rss rows as bytes", () => {
	const rows = parsePosixProcessTable(posixTable);
	assert.deepEqual(
		rows,
		[
			{ processId: 1, parentProcessId: 0, rssBytes: 100000 * 1024 },
			{ processId: 2, parentProcessId: 1, rssBytes: 20000 * 1024 },
			{ processId: 3, parentProcessId: 1, rssBytes: 30000 * 1024 },
			{ processId: 4, parentProcessId: 3, rssBytes: 5000 * 1024 },
			{ processId: 5, parentProcessId: 4, rssBytes: 7000 * 1024 },
		],
	);
});

test("processTreeIds walks the full descendant closure of a root process", () => {
	const ids = processTreeIds(parsePosixProcessTable(posixTable), 3);
	assert.deepEqual([...ids].sort((left, right) => left - right), [3, 4, 5]);
	assert.equal(processTreeIds(parsePosixProcessTable(posixTable), 409).size, 0);
});

test("shellVsDaemonBytes subtracts the daemon subtree from the shell tree", () => {
	const rows = parsePosixProcessTable(posixTable);
	const { shellBytes, daemonBytes } = shellVsDaemonBytes(rows, 1, 4);
	assert.equal(daemonBytes, (5000 + 7000) * 1024);
	assert.equal(shellBytes, (100000 + 20000 + 30000) * 1024);
	assert.equal(subtreeTotalBytes(rows, 1), (100000 + 20000 + 30000 + 5000 + 7000) * 1024);
	assert.throws(() => subtreeTotalBytes(rows, 409), /missing from the sampled process table/);
});

test("retentionSummary reports per-cycle deltas against the pre-mount baseline", () => {
	const summary = retentionSummary({ baselineBytes: 1000, cycleBytes: [1200, 1050, 1010] });
	assert.deepEqual(summary.deltas, [200, 50, 10]);
	assert.equal(summary.maxRetainedDelta, 200);
	assert.throws(() => retentionSummary({ baselineBytes: 1000, cycleBytes: [] }), /at least one/);
});

test("validateDisposalAcks requires one increasing ack per disposal cycle", () => {
	const acks = validateDisposalAcks(
		[
			{ name: "disposal", timestamp: 110 },
			{ name: "disposal", timestamp: 220 },
		],
		2,
	);
	assert.equal(acks.length, 2);
	assert.throws(() => validateDisposalAcks([{ name: "disposal", timestamp: 1 }], 2), /expected/);
	assert.throws(
		() =>
			validateDisposalAcks(
				[
					{ name: "disposal", timestamp: 30 },
					{ name: "disposal", timestamp: 20 },
				],
				2,
			),
		/increasing/,
	);
});

function emptyBoardResult(label) {
	return buildEmptyBoardResult({
		label,
		git: { commit: "a".repeat(40), dirty: true },
		host: { platform: "darwin", architecture: "arm64", osVersion: "Darwin 25.5.0", cpu: "Apple Silicon", logicalCores: 10 },
		buildKind: "debug-devurl",
		webviewRuntimeVersion: "OS WebKit (tauri debug devUrl build)",
		idleSeconds: 20,
		samples: [111, 222, 333],
		daemonSamples: [44, 55, 66],
	});
}

test("empty-board results validate for before and after labels and reject tampering", () => {
	for (const label of ["before", "after"]) {
		const result = emptyBoardResult(label);
		validateHeapResultSchema(result);
		assert.equal(result.probeKind, "empty-board");
		assert.equal(result.median, 222);
		assert.equal(result.p95, 333);
		assert.equal(result.daemonMedian, 55);
	}
	const stale = emptyBoardResult("after");
	stale.median = 1;
	assert.throws(() => validateHeapResultSchema(stale), /median/);
	const leaked = emptyBoardResult("before");
	leaked.scenarioConfiguration.daemonCommand = "/Users/somebody/frontend/daemon/opr daemon";
	assert.throws(() => validateHeapResultSchema(leaked), /absolute path/);
});

test("terminal-disposal results carry per-cycle retention evidence and validate", () => {
	const result = buildDisposalResult({
		label: "after",
		git: { commit: "b".repeat(40), dirty: false },
		host: { platform: "darwin", architecture: "arm64", osVersion: "Darwin 25.5.0", cpu: "Apple Silicon", logicalCores: 10 },
		buildKind: "debug-devurl",
		webviewRuntimeVersion: "OS WebKit (tauri debug devUrl build)",
		cycles: 8,
		disposalBytesPerCycle: 2097152,
		baselineBytes: 50_000_000,
		cycleBytes: [52_000_000, 50_400_000, 50_100_000],
		acks: [
			{ name: "disposal", timestamp: 10 },
			{ name: "disposal", timestamp: 20 },
			{ name: "disposal", timestamp: 30 },
		],
	});
	validateHeapResultSchema(result);
	assert.equal(result.probeKind, "terminal-disposal");
	assert.equal(result.retention.maxRetainedDelta, 2_000_000);
	assert.equal(result.retention.cycleCount, 3);
	assert.notEqual(result.retention.disposalAckCount, 0);

	const shortAcks = {
		...result,
		retention: { ...result.retention, disposalAckCount: 0 },
	};
	assert.throws(() => validateHeapResultSchema(shortAcks), /disposal acknowledgements are required/);
	assert.throws(
		() =>
			buildDisposalResult({
				label: "after",
				git: { commit: "b".repeat(40), dirty: false },
				host: { platform: "darwin", architecture: "arm64", osVersion: "Darwin 25.5.0", cpu: "Apple Silicon", logicalCores: 10 },
				buildKind: "debug-devurl",
				webviewRuntimeVersion: "OS WebKit (tauri debug devUrl build)",
				cycles: 8,
				disposalBytesPerCycle: 2097152,
				baselineBytes: 100,
				cycleBytes: [120],
				acks: [],
			}),
		/acknowledgements/,
	);
});
