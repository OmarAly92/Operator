import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { createTerminalCore, initTerminalCore } from "../ts/core/dist/index.js";
import { loadFixture } from "./agent-session/fixtures.mjs";

const QUERY = process.argv[2] ?? "12";
const PAIRS = 3;
const TAIL_BYTES = 64 * 1024;

const wasm = await readFile(fileURLToPath(new URL("../ts/core/wasm/vt_core_bg.wasm", import.meta.url)));
await initTerminalCore(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
const { recording, sizes } = await loadFixture("claude-long-50k");
const { cols, rows } = sizes[0];

function loadedCore() {
	const core = createTerminalCore({ columns: cols, rows, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
	core.setAgentTuiMode(true);
	core.setGraphemeClusters(true);
	core.feed(recording.subarray(0, recording.length - TAIL_BYTES));
	return core;
}

function rescan(core) {
	const started = performance.now();
	const id = core.findOpen(QUERY, false);
	while (!core.findUpdate(id).complete) {}
	const hits = core.findResults(id).length;
	core.findCancel(id);
	return { ms: performance.now() - started, hits };
}

function update(core, id) {
	const started = performance.now();
	core.findUpdate(id);
	const hits = core.findResults(id).length;
	return { ms: performance.now() - started, hits };
}

for (let pair = 0; pair < PAIRS; pair += 1) {
	const core = loadedCore();
	const id = core.findOpen(QUERY, false);
	while (!core.findUpdate(id).complete) {}
	const scannedBefore = core.findHistoryBytesScanned(id);
	core.feed(recording.subarray(recording.length - TAIL_BYTES));
	const updateFirst = pair % 2 === 0;
	const first = updateFirst ? update(core, id) : rescan(core);
	const second = updateFirst ? rescan(core) : update(core, id);
	const incremental = updateFirst ? first : second;
	const full = updateFirst ? second : first;
	const snapshot = core.snapshot();
	console.log(JSON.stringify({
		pair,
		order: updateFirst ? "update,rescan" : "rescan,update",
		historyRows: snapshot.historyRows,
		updateMs: Number(incremental.ms.toFixed(2)),
		rescanMs: Number(full.ms.toFixed(2)),
		updateHits: incremental.hits,
		rescanHits: full.hits,
		historyBytesScanned: scannedBefore,
		scannedByUpdate: core.findHistoryBytesScanned(id) - scannedBefore,
	}));
	core.findCancel(id);
	core.dispose();
}
