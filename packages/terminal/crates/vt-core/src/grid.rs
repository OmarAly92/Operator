use crate::alt::AltGrid;
use crate::attribute_map::AttributeMap;
use crate::block::{BlockRecord, BlockSource, BlockState, TextSpan};
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::ScreenGrid;
use crate::style::CellStyle;
use crate::width::WidthMode;
use crate::{CoreError, LineEditorState};

/// Narrows a snapshot-local length to the `u32` the export buffers carry.
///
/// Every offset in a `GridSnapshot` is a `u32`, so an unchecked `as` here would
/// silently truncate on a snapshot past 4 GiB and hand the renderer ranges that
/// point at the wrong bytes. The failure surfaces instead.
pub(crate) fn checked_u32(value: usize) -> Result<u32, CoreError> {
    u32::try_from(value).map_err(|_| CoreError::OffsetOverflow)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CellSpan {
    pub start: u32,
    pub end: u32,
    pub width: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExportedRow {
    pub bytes: Vec<u8>,
    pub indent: u16,
    pub wrapped: bool,
    pub styles: Vec<(u32, CellStyle)>,
    pub spans: Vec<CellSpan>,
}

pub struct GridSnapshot {
    pub content: Vec<u8>,
    pub rows: Vec<(u32, u32)>,
    pub row_indents: Vec<u16>,
    pub row_wrapped: Vec<bool>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, CellStyle)>,
    pub span_ranges: Vec<(u32, u32)>,
    pub cell_spans: Vec<CellSpan>,
    pub blocks: Vec<BlockRecord>,
    pub block_text: Vec<u8>,
    pub line_editor_state: u32,
    pub cursor_row: u32,
    pub cursor_col: u32,
    pub cursor_visible: bool,
    pub history_rows: u32,
    pub first_stable_row: u64,
    pub alt: Option<crate::alt::AltSnapshot>,
}

impl GridSnapshot {
    pub fn row_count(&self) -> usize {
        self.rows.len()
    }

    pub fn block_command(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].command)
    }

    pub fn block_cwd(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].cwd)
    }

    pub fn block_branch(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].git_branch)
    }

    fn span_text(&self, span: TextSpan) -> &str {
        std::str::from_utf8(&self.block_text[span.start as usize..span.end as usize])
            .expect("block text is valid utf-8")
    }

    pub fn row_indent(&self, index: usize) -> usize {
        usize::from(self.row_indents[index])
    }

    pub fn row_wrapped(&self, index: usize) -> bool {
        self.row_wrapped[index]
    }

    pub fn row_text(&self, index: usize) -> &str {
        let (start, end) = self.rows[index];
        std::str::from_utf8(&self.content[start as usize..end as usize])
            .expect("row is valid utf-8")
    }

    pub fn row_style_pairs(&self, index: usize) -> &[(u32, CellStyle)] {
        let (start, end) = self.run_ranges[index];
        &self.style_pairs[start as usize..end as usize]
    }

    pub fn row_cell_spans(&self, index: usize) -> &[CellSpan] {
        let (start, end) = self.span_ranges[index];
        &self.cell_spans[start as usize..end as usize]
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn build_snapshot(
    content: &Content,
    rows: &RowIndex,
    styles: &AttributeMap<CellStyle>,
    grid: &BlockGrid,
    screen: &ScreenGrid,
    line_editor_state: LineEditorState,
    alt: Option<&AltGrid>,
    first_stable_row: u64,
    width_mode: WidthMode,
) -> Result<GridSnapshot, CoreError> {
    let mut all_content = Vec::new();
    let mut row_ranges: Vec<(u32, u32)> = Vec::new();
    let mut row_indents: Vec<u16> = Vec::new();
    let mut row_wrapped: Vec<bool> = Vec::new();
    let mut style_pairs: Vec<(u32, CellStyle)> = Vec::new();
    let mut run_ranges: Vec<(u32, u32)> = Vec::new();
    let mut span_ranges: Vec<(u32, u32)> = Vec::new();
    let mut cell_spans: Vec<CellSpan> = Vec::new();
    let mut ctx = SnapshotCtx {
        all_content: &mut all_content,
        row_ranges: &mut row_ranges,
        row_indents: &mut row_indents,
        row_wrapped: &mut row_wrapped,
        style_pairs: &mut style_pairs,
        run_ranges: &mut run_ranges,
        span_ranges: &mut span_ranges,
        cell_spans: &mut cell_spans,
    };

    for row in rows.completed() {
        ctx.push(export_history_row(content, styles, row, width_mode))?;
    }

    let history_rows = ctx.row_ranges.len();
    for row in 0..screen.content_rows() {
        ctx.push(export_screen_row(screen, row))?;
    }

    // The screen's own cursor row is relative to the top of the screen; the
    // renderer indexes the flat row list, which starts in the scrollback.
    let (screen_cursor_row, screen_cursor_col) = screen.cursor();
    let cursor_row = checked_u32(history_rows + screen_cursor_row)?;
    let cursor_col = checked_u32(screen_cursor_col)?;
    let cursor_visible = screen.cursor_visible();

    let (blocks, block_text) = export_blocks(grid, row_ranges.len(), |row| {
        row_ranges[row].1 > row_ranges[row].0
    })?;

    Ok(GridSnapshot {
        content: all_content,
        rows: row_ranges,
        row_indents,
        row_wrapped,
        run_ranges,
        style_pairs,
        span_ranges,
        cell_spans,
        blocks,
        block_text,
        line_editor_state: line_editor_state.wire(),
        cursor_row,
        cursor_col,
        cursor_visible,
        history_rows: checked_u32(history_rows)?,
        first_stable_row,
        alt: alt.map(|grid| grid.snapshot()),
    })
}

pub(crate) fn export_blocks(
    grid: &BlockGrid,
    total_rows: usize,
    row_has_bytes: impl Fn(usize) -> bool,
) -> Result<(Vec<BlockRecord>, Vec<u8>), CoreError> {
    let mut block_text: Vec<u8> = Vec::new();
    let blocks: Vec<BlockRecord> = if grid.is_empty() {
        // A core that has seen no marks has one block by definition: the
        // whole scrollback. This is what `output_with_no_marks_lands_in_one_synthetic_block`
        // and every Phase 0 test rely on.
        vec![BlockRecord {
            id: 0,
            first_row: 0,
            row_count: checked_u32(total_rows)?,
            state: BlockState::Running,
            source: BlockSource::Synthetic,
            exit_code: None,
            duration_ms: None,
            command: TextSpan::default(),
            cwd: TextSpan::default(),
            git_branch: TextSpan::default(),
            bookmarked: false,
        }]
    } else {
        let mut records = Vec::with_capacity(grid.blocks().count() + 1);
        for block in grid.blocks() {
            let (flat_first, flat_count) = grid.flat_extent(block);
            let command = append_block_text(&mut block_text, &block.meta.command)?;
            let cwd = append_block_text(&mut block_text, &block.meta.cwd)?;
            let git_branch = append_block_text(&mut block_text, &block.meta.git_branch)?;
            let first_row = checked_u32(flat_first)?;
            let row_count = if block.state == BlockState::Running {
                checked_u32(total_rows.saturating_sub(flat_first))?
            } else {
                checked_u32(flat_count)?
            };
            let started = block.meta.started_at_ms;
            let finished = block.meta.finished_at_ms;
            let duration_ms = match (started, finished) {
                (Some(s), Some(f)) if f >= s => Some(f - s),
                _ => None,
            };
            records.push(BlockRecord {
                id: block.id,
                first_row,
                row_count,
                state: block.state,
                source: block.source,
                exit_code: block.meta.exit_code,
                duration_ms,
                command,
                cwd,
                git_branch,
                bookmarked: block.meta.bookmarked,
            });
        }
        let covered_end = grid.covered_end();
        let trailing_has_content =
            !grid.has_open_block() && (covered_end..total_rows).any(&row_has_bytes);
        if trailing_has_content {
            records.push(BlockRecord {
                id: grid.next_id(),
                first_row: checked_u32(covered_end)?,
                row_count: checked_u32(total_rows - covered_end)?,
                state: BlockState::Running,
                source: BlockSource::Synthetic,
                exit_code: None,
                duration_ms: None,
                command: TextSpan::default(),
                cwd: TextSpan::default(),
                git_branch: TextSpan::default(),
                bookmarked: false,
            });
        }
        records
    };
    Ok((blocks, block_text))
}

fn append_block_text(buffer: &mut Vec<u8>, text: &str) -> Result<TextSpan, CoreError> {
    let start = checked_u32(buffer.len())?;
    buffer.extend_from_slice(text.as_bytes());
    let end = checked_u32(buffer.len())?;
    Ok(TextSpan { start, end })
}

struct SnapshotCtx<'a> {
    all_content: &'a mut Vec<u8>,
    row_ranges: &'a mut Vec<(u32, u32)>,
    row_indents: &'a mut Vec<u16>,
    row_wrapped: &'a mut Vec<bool>,
    style_pairs: &'a mut Vec<(u32, CellStyle)>,
    run_ranges: &'a mut Vec<(u32, u32)>,
    span_ranges: &'a mut Vec<(u32, u32)>,
    cell_spans: &'a mut Vec<CellSpan>,
}

impl SnapshotCtx<'_> {
    fn push(&mut self, row: ExportedRow) -> Result<(), CoreError> {
        let content_base = checked_u32(self.all_content.len())?;
        let content_end = checked_u32(self.all_content.len() + row.bytes.len())?;
        self.row_ranges.push((content_base, content_end));
        self.row_indents.push(row.indent);
        self.row_wrapped.push(row.wrapped);
        self.all_content.extend_from_slice(&row.bytes);

        let pair_start = checked_u32(self.style_pairs.len())?;
        self.style_pairs.extend(row.styles);
        let pair_end = checked_u32(self.style_pairs.len())?;
        self.run_ranges.push((pair_start, pair_end));

        let span_start = checked_u32(self.cell_spans.len())?;
        self.cell_spans.extend(row.spans);
        let span_end = checked_u32(self.cell_spans.len())?;
        self.span_ranges.push((span_start, span_end));
        Ok(())
    }
}

pub(crate) fn text_spans(text: &str, mode: WidthMode) -> Vec<CellSpan> {
    crate::width::clusters(text, mode)
        .into_iter()
        .filter(|cluster| {
            cluster.width != 1 || text[cluster.start..cluster.end].chars().nth(1).is_some()
        })
        .map(|cluster| CellSpan {
            start: cluster.start as u32,
            end: cluster.end as u32,
            width: cluster.width.min(2) as u8,
        })
        .collect()
}

pub(crate) fn export_history_row(
    content: &Content,
    styles: &AttributeMap<CellStyle>,
    row: &RowRange,
    mode: WidthMode,
) -> ExportedRow {
    let bytes = content.copy_range(row.start, row.end);
    // Style runs are keyed by the row's own byte span. `copy_range` returns
    // exactly that span, so the pair offsets and `bytes` always agree.
    let pairs = if bytes.is_empty() {
        Vec::new()
    } else {
        styles.runs(row.start, row.end)
    };
    let text = std::str::from_utf8(&bytes).expect("row is valid utf-8");
    let spans = text_spans(text, mode);
    ExportedRow {
        bytes,
        indent: row.indent,
        wrapped: row.wrapped,
        styles: pairs,
        spans,
    }
}

pub(crate) fn export_screen_row(screen: &ScreenGrid, row: usize) -> ExportedRow {
    let wrapped = screen.row_wrapped(row);
    let width = if wrapped {
        screen.cols()
    } else {
        (0..screen.cols())
            .rposition(|col| !screen.cell(row, col).is_blank())
            .map_or(0, |col| col + 1)
    };
    let mut bytes: Vec<u8> = Vec::new();
    let mut pairs: Vec<(u32, CellStyle)> = Vec::new();
    let mut spans: Vec<CellSpan> = Vec::new();
    let mut run_style = None;
    let mut buffer = [0u8; 4];

    for col in 0..width {
        let cell = screen.cell(row, col);
        if cell.ch == '\0' {
            continue;
        }
        if run_style != Some(cell.style) {
            if let Some(previous) = run_style {
                pairs.push((bytes.len() as u32, previous));
            }
            run_style = Some(cell.style);
        }
        let start = bytes.len() as u32;
        let text = cell.text(&mut buffer);
        bytes.extend_from_slice(text.as_bytes());
        let spacers = (col + 1..screen.cols())
            .take_while(|next| screen.cell(row, *next).ch == '\0')
            .count();
        let cell_width = 1 + spacers;
        if cell_width != 1 || text.chars().nth(1).is_some() {
            spans.push(CellSpan {
                start,
                end: bytes.len() as u32,
                width: cell_width as u8,
            });
        }
    }
    if let Some(style) = run_style {
        pairs.push((bytes.len() as u32, style));
    }

    ExportedRow {
        bytes,
        indent: 0,
        wrapped,
        styles: pairs,
        spans,
    }
}
