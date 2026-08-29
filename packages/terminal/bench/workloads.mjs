export const CHUNK_BYTES = 65536;
export const LARGE_OUTPUT_BYTES = 16777216;
export const VTEBENCH_BYTES = 8388608;
export const VTEBENCH_SEED = 7000;
export const INPUT_BYTE = new Uint8Array([0x78]);

export const WORKLOAD_METADATA = {
	"vtebench": {
		workload: "vtebench-random-write-v1",
		seed: VTEBENCH_SEED,
		workloadDigest: "6c9e4053f0f94cabc58028b527c0fb5215cbe565ae35db382728942cc2893676",
	},
	"large-output": {
		workload: "large-output-x-v1",
		workloadDigest: "a06c26cbac8b80704f420222dae5658b88ff2da96702d12ef7a4223e9361f7c1",
	},
	"input-latency": {
		workload: "input-loopback-x-v1",
		workloadDigest: "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881",
	},
};

export function createLargeOutput() {
	return new Uint8Array(LARGE_OUTPUT_BYTES).fill(0x78);
}

export function createVtebench(seed = VTEBENCH_SEED) {
	const encoder = new TextEncoder();
	const output = new Uint8Array(VTEBENCH_BYTES);
	let state = seed >>> 0;
	let index = 0;
	let offset = 0;
	const next = () => {
		state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
		return state;
	};

	while (offset < output.byteLength) {
		let token;
		switch (next() % 5) {
			case 0:
				token = `row-${index.toString(16).padStart(8, "0")} ${"abcdefghijklmnopqrstuvwxyz0123456789".repeat(3)}\r\n`;
				break;
			case 1:
				token = `\x1b[${1 + (next() % 40)};${1 + (next() % 120)}H`;
				break;
			case 2:
				token = "\x1b[2K";
				break;
			case 3:
				token = `\x1b[3${next() % 8}mcolor-${index.toString(16).padStart(8, "0")} ${"terminal ".repeat(10)}\x1b[0m\r\n`;
				break;
			default:
				token = `scroll-${index.toString(16).padStart(8, "0")} ${"x".repeat(120)}\r\n`;
		}
		const bytes = encoder.encode(token);
		const length = Math.min(bytes.byteLength, output.byteLength - offset);
		output.set(bytes.subarray(0, length), offset);
		offset += length;
		index += 1;
	}

	return output;
}

export function* chunkBytes(bytes, size = CHUNK_BYTES) {
	for (let offset = 0; offset < bytes.byteLength; offset += size) {
		yield bytes.subarray(offset, Math.min(offset + size, bytes.byteLength));
	}
}
