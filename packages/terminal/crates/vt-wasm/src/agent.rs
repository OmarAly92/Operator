use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

#[wasm_bindgen]
pub fn detects_high_confidence_input_pattern(line: &str) -> bool {
    vt_core::activity::input_patterns::detects_high_confidence_input_pattern(line)
}

#[wasm_bindgen]
impl WasmTerminalCore {
    pub fn cursor_line_prompts(&self) -> bool {
        self.core.cursor_line_prompts()
    }
}
