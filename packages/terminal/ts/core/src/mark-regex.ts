import { WasmMarkRegex } from "../wasm/vt_core.js";
import { isInitialized } from "./wasm-runtime.js";

export type MarkRegex = Readonly<{ ranges(text: string): Uint32Array; dispose(): void }>;

const NONE = new Uint32Array(0);

export function compileMarkRegex(pattern: string): MarkRegex | null {
	if (!isInitialized() || pattern === "") return null;
	let inner: WasmMarkRegex | undefined = WasmMarkRegex.compile(pattern);
	if (!inner) return null;
	return {
		ranges: (text) => inner?.ranges(text) ?? NONE,
		dispose: () => {
			inner?.free();
			inner = undefined;
		},
	};
}

export function markRegexValid(pattern: string): boolean | null {
	if (!isInitialized()) return null;
	const regex = compileMarkRegex(pattern);
	if (!regex) return false;
	regex.dispose();
	return true;
}
