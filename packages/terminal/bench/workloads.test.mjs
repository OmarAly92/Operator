import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
	INPUT_BYTE,
	LARGE_OUTPUT_BYTES,
	VTEBENCH_BYTES,
	VTEBENCH_SEED,
	chunkBytes,
	createLargeOutput,
	createVtebench,
} from "./workloads.mjs";

test("large output is exactly 16 MiB of printable x bytes in 64 KiB chunks", () => {
	const workload = createLargeOutput();
	assert.equal(workload.byteLength, LARGE_OUTPUT_BYTES);
	assert.equal(workload.every((byte) => byte === 0x78), true);
	const chunks = [...chunkBytes(workload)];
	assert.equal(chunks.length, 256);
	assert.equal(chunks.every((chunk) => chunk.byteLength === 65536), true);
});

test("vtebench is deterministic byte-for-byte for seed 7000", () => {
	const first = createVtebench(VTEBENCH_SEED);
	const second = createVtebench(VTEBENCH_SEED);
	assert.equal(first.byteLength, VTEBENCH_BYTES);
	assert.deepEqual(first, second);
	assert.equal(
		createHash("sha256").update(first).digest("hex"),
		"6c9e4053f0f94cabc58028b527c0fb5215cbe565ae35db382728942cc2893676",
	);
	assert.notDeepEqual(first, createVtebench(VTEBENCH_SEED + 1));
});

test("input latency loops one printable byte", () => {
	assert.deepEqual(INPUT_BYTE, new Uint8Array([0x78]));
});
