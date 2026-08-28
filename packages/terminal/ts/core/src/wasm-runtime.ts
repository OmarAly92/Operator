import init, { type InitOutput } from "../wasm/vt_core.js";

type InitState =
	| { kind: "pending"; promise: Promise<InitOutput> }
	| { kind: "ready"; output: InitOutput }
	| { kind: "idle" };

let state: InitState = { kind: "idle" };

export type WasmInput = BufferSource | WebAssembly.Module;

export function isInitialized(): boolean {
	return state.kind === "ready";
}

export function getMemory(): WebAssembly.Memory {
	if (state.kind !== "ready") {
		throw new Error("terminal core WASM is not initialized");
	}
	return state.output.memory;
}

export async function ensureInitialized(wasmBytes: WasmInput): Promise<InitOutput> {
	if (state.kind === "ready") {
		return state.output;
	}
	if (state.kind === "pending") {
		return state.promise;
	}
	const promise = init({ module_or_path: wasmBytes })
		.then((output) => {
			state = { kind: "ready", output };
			return output;
		})
		.catch((error) => {
			state = { kind: "idle" };
			throw error;
		});
	state = { kind: "pending", promise };
	return promise;
}

export function u8View(memory: WebAssembly.Memory, pointer: number, length: number): Uint8Array {
	return new Uint8Array(memory.buffer, pointer, length);
}

export function u32View(memory: WebAssembly.Memory, pointer: number, length: number): Uint32Array {
	return new Uint32Array(memory.buffer, pointer, length);
}
