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

#[wasm_bindgen]
pub fn is_spinner_line(line: &str) -> bool {
    vt_core::activity::compact::is_spinner_line(line)
}

#[wasm_bindgen]
pub fn compact_lines_text(text: &str) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    vt_core::activity::compact::compact_lines(&lines).join("\n")
}

#[wasm_bindgen]
pub fn cap_lines_text(text: &str, max_lines: u32) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    vt_core::activity::compact::cap_lines(&lines, max_lines as usize).join("\n")
}
