use vt_core::{GridSnapshot, TerminalCore};
use wasm_bindgen::prelude::*;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Words each `BlockRecord` flattens to in the `blocks` buffer.
///
/// The TypeScript side pins the same constant and strides its `Uint32Array` by
/// it, so the two must never drift apart.
pub const BLOCK_RECORD_WORDS: usize = 14;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportError {
    OffsetOverflow,
}

/// Narrows a byte count to the `u32` the JavaScript views index with.
///
/// `refresh` uses it on the content length: `GridSnapshot` row offsets are
/// already checked `u32`s, but the flat content buffer is a `usize` that the
/// TypeScript side addresses as `u32`, so it needs its own guard.
pub fn checked_u32_from_u64(value: u64) -> Result<u32, ExportError> {
    u32::try_from(value).map_err(|_| ExportError::OffsetOverflow)
}

#[derive(Default)]
pub struct ExportBuffers {
    content: Vec<u8>,
    rows: Vec<u32>,
    run_ranges: Vec<u32>,
    style_pairs: Vec<u32>,
    blocks: Vec<u32>,
    block_text: Vec<u8>,
}

impl ExportBuffers {
    pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError> {
        self.content.clear();
        self.rows.clear();
        self.run_ranges.clear();
        self.style_pairs.clear();
        self.blocks.clear();
        self.block_text.clear();

        checked_u32_from_u64(snapshot.content.len() as u64)?;
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

        for record in &snapshot.blocks {
            let before = self.blocks.len();

            self.blocks.push(record.id as u32);
            self.blocks.push((record.id >> 32) as u32);
            self.blocks.push(record.first_row);
            self.blocks.push(record.row_count);
            self.blocks
                .push(record.state.as_u32() | (record.source.as_u32() << 8));
            self.blocks.push(match record.exit_code {
                None => 0,
                Some(exit) => (exit + 1) as u32,
            });
            let (duration_lo, duration_hi) = match record.duration_ms {
                None => (u32::MAX, u32::MAX),
                Some(ms) => (ms as u32, (ms >> 32) as u32),
            };
            self.blocks.push(duration_lo);
            self.blocks.push(duration_hi);
            self.blocks.push(record.command.start);
            self.blocks.push(record.command.end);
            self.blocks.push(record.cwd.start);
            self.blocks.push(record.cwd.end);
            self.blocks.push(record.git_branch.start);
            self.blocks.push(record.git_branch.end);

            debug_assert_eq!(self.blocks.len() - before, BLOCK_RECORD_WORDS);
        }

        checked_u32_from_u64(snapshot.block_text.len() as u64)?;
        self.block_text
            .extend_from_slice(snapshot.block_text.as_slice());

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

    pub fn blocks(&self) -> &[u32] {
        &self.blocks
    }

    pub fn block_text(&self) -> &[u8] {
        &self.block_text
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
        let snapshot = core.snapshot().map_err(js_error_from_core)?;
        export.refresh(&snapshot)?;
        Ok(WasmTerminalCore {
            core,
            export,
            generation: 0,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), JsError> {
        self.core.feed(bytes);
        let snapshot = self.core.snapshot().map_err(js_error_from_core)?;
        self.export.refresh(&snapshot)?;
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

    pub fn blocks_ptr(&self) -> *const u32 {
        self.export.blocks().as_ptr()
    }

    pub fn blocks_len(&self) -> usize {
        self.export.blocks().len()
    }

    pub fn block_text_ptr(&self) -> *const u8 {
        self.export.block_text().as_ptr()
    }

    pub fn block_text_len(&self) -> usize {
        self.export.block_text().len()
    }
}

fn js_error_from_core(err: vt_core::CoreError) -> JsError {
    match err {
        vt_core::CoreError::ZeroColumns => JsError::new("terminal core requires columns > 0"),
        vt_core::CoreError::ZeroScrollback => {
            JsError::new("terminal core requires scrollback_rows > 0")
        }
        vt_core::CoreError::OffsetOverflow => JsError::new("snapshot offset overflows u32"),
    }
}

impl From<ExportError> for JsError {
    fn from(err: ExportError) -> Self {
        match err {
            ExportError::OffsetOverflow => JsError::new("offset overflows u32"),
        }
    }
}
