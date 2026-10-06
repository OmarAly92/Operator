import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const benchDir = path.dirname(fileURLToPath(import.meta.url));
const label = process.argv[2] ?? "run";
const wasmDir = path.resolve(process.argv[3] ?? path.join(benchDir, "..", "ts", "core", "wasm"));
const RUNS = 7;
const CHUNK = 64 * 1024;

const glue = await import(pathToFileURL(path.join(wasmDir, "vt_core.js")).href);
glue.initSync({ module: readFileSync(path.join(wasmDir, "vt_core_bg.wasm")) });

const recording = readFileSync(path.join(benchDir, "agent-session", "fixtures", "claude-long-50k", "recording"));

function mbPerSecond(graphemes) {
	const core = new glue.WasmTerminalCore(120, 200_000, 128 * 1024 * 1024);
	core.resize(120, 40);
	core.setGraphemeClusters(graphemes);
	const start = performance.now();
	for (let at = 0; at < recording.length; at += CHUNK) {
		core.feed(recording.subarray(at, Math.min(at + CHUNK, recording.length)), 0);
	}
	const seconds = (performance.now() - start) / 1000;
	core.free();
	return recording.length / (1024 * 1024) / seconds;
}

for (const [mode, graphemes] of [["grapheme", true], ["scalar", false]]) {
	const samples = [];
	for (let run = 0; run < RUNS; run += 1) samples.push(mbPerSecond(graphemes));
	samples.sort((a, b) => a - b);
	console.log(`${label} wasm claude-long-50k ${mode} ${samples[Math.floor(RUNS / 2)].toFixed(2)} MB/s`);
}
