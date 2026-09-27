import { detects_high_confidence_input_pattern } from "../wasm/vt_core.js";

export function detectsHighConfidenceInputPattern(cursorLine: string): boolean {
	return detects_high_confidence_input_pattern(cursorLine);
}
