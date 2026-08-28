import { describe, expect, it } from "vitest";
import { createTerminalCore } from "./index";

describe("createTerminalCore before initialization", () => {
	it("throws because the WASM module has not been initialized", () => {
		expect(() => createTerminalCore({ columns: 16, scrollback: 100 })).toThrow(
			"terminal core WASM is not initialized",
		);
	});
});
