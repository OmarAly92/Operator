use vt_core::mark_regex::MarkRegex;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmMarkRegex {
    inner: MarkRegex,
}

#[wasm_bindgen]
impl WasmMarkRegex {
    pub fn compile(pattern: &str) -> Option<WasmMarkRegex> {
        MarkRegex::new(pattern).map(|inner| WasmMarkRegex { inner })
    }

    pub fn ranges(&self, text: &str) -> Vec<u32> {
        self.inner.utf16_ranges(text)
    }
}
