use vt_core::{GridSnapshot, TerminalCore};
use wasm_bindgen::prelude::*;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportError {
    OffsetOverflow,
}

pub fn checked_u32_from_u64(value: u64) -> Result<u32, ExportError> {
    if value > u32::MAX as u64 {
        Err(ExportError::OffsetOverflow)
    } else {
        Ok(value as u32)
    }
}

#[derive(Default)]
pub struct ExportBuffers {
    content: Vec<u8>,
    rows: Vec<u32>,
    run_ranges: Vec<u32>,
    style_pairs: Vec<u32>,
}

impl ExportBuffers {
    pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError> {
        self.content.clear();
        self.rows.clear();
        self.run_ranges.clear();
        self.style_pairs.clear();

        self.content.extend_from_slice(snapshot.content.as_slice());

        for &(start, end) in &snapshot.rows {
            self.rows.push(start);
            self.rows.push(end);
        }

        for &(start, end) in &snapshot.run_ranges {
            self.run_ranges.push(start);
            self.run_ranges.push(end);
        }

        for &(end, code) in &snapshot.style_pairs {
            self.style_pairs.push(end);
            self.style_pairs.push(code.value());
        }

        Ok(())
    }

    pub fn content(&self) -> &[u8] {
        &self.content
    }

    pub fn rows(&self) -> &[u32] {
        &self.rows
    }

    pub fn run_ranges(&self) -> &[u32] {
        &self.run_ranges
    }

    pub fn style_pairs(&self) -> &[u32] {
        &self.style_pairs
    }
}

#[wasm_bindgen]
pub struct WasmTerminalCore {
    core: TerminalCore,
    export: ExportBuffers,
    generation: u32,
}

#[wasm_bindgen]
impl WasmTerminalCore {
    #[wasm_bindgen(constructor)]
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<WasmTerminalCore, JsError> {
        let core = TerminalCore::new(columns, scrollback_rows).map_err(js_error_from_core)?;
        let mut export = ExportBuffers::default();
        export.refresh(&core.snapshot())?;
        Ok(WasmTerminalCore {
            core,
            export,
            generation: 0,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), JsError> {
        self.core.feed(bytes);
        self.export.refresh(&self.core.snapshot())?;
        self.generation = self.generation.wrapping_add(1);
        Ok(())
    }

    pub fn generation(&self) -> u32 {
        self.generation
    }

    pub fn content_ptr(&self) -> *const u8 {
        self.export.content().as_ptr()
    }

    pub fn content_len(&self) -> usize {
        self.export.content().len()
    }

    pub fn rows_ptr(&self) -> *const u32 {
        self.export.rows().as_ptr()
    }

    pub fn rows_len(&self) -> usize {
        self.export.rows().len()
    }

    pub fn run_ranges_ptr(&self) -> *const u32 {
        self.export.run_ranges().as_ptr()
    }

    pub fn run_ranges_len(&self) -> usize {
        self.export.run_ranges().len()
    }

    pub fn style_pairs_ptr(&self) -> *const u32 {
        self.export.style_pairs().as_ptr()
    }

    pub fn style_pairs_len(&self) -> usize {
        self.export.style_pairs().len()
    }
}

fn js_error_from_core(err: vt_core::CoreError) -> JsError {
    match err {
        vt_core::CoreError::ZeroColumns => JsError::new("terminal core requires columns > 0"),
        vt_core::CoreError::ZeroScrollback => {
            JsError::new("terminal core requires scrollback_rows > 0")
        }
    }
}

impl From<ExportError> for JsError {
    fn from(err: ExportError) -> Self {
        match err {
            ExportError::OffsetOverflow => JsError::new("offset overflows u32"),
        }
    }
}
