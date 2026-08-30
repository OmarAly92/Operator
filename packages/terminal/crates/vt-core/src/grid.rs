use crate::alt::AltGrid;
use crate::attribute_map::AttributeMap;
use crate::block::{BlockRecord, BlockSource, BlockState, TextSpan};
use crate::block_grid::BlockGrid;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::screen::ScreenGrid;
use crate::style::StyleCode;
use crate::{CoreError, LineEditorState};

/// Narrows a snapshot-local length to the `u32` the export buffers carry.
///
/// Every offset in a `GridSnapshot` is a `u32`, so an unchecked `as` here would
/// silently truncate on a snapshot past 4 GiB and hand the renderer ranges that
/// point at the wrong bytes. The failure surfaces instead.
pub(crate) fn checked_u32(value: usize) -> Result<u32, CoreError> {
    u32::try_from(value).map_err(|_| CoreError::OffsetOverflow)
}

pub struct GridSnapshot {
    pub content: Vec<u8>,
    pub rows: Vec<(u32, u32)>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, StyleCode)>,
    pub blocks: Vec<BlockRecord>,
    pub block_text: Vec<u8>,
    pub line_editor_state: u32,
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

    pub fn row_text(&self, index: usize) -> &str {
        let (start, end) = self.rows[index];
        std::str::from_utf8(&self.content[start as usize..end as usize])
            .expect("row is valid utf-8")
    }

    pub fn row_style_pairs(&self, index: usize) -> &[(u32, StyleCode)] {
        let (start, end) = self.run_ranges[index];
        &self.style_pairs[start as usize..end as usize]
    }
}

pub(crate) fn build_snapshot(
    content: &Content,
    rows: &RowIndex,
    styles: &AttributeMap<StyleCode>,
    grid: &BlockGrid,
    screen: &ScreenGrid,
    line_editor_state: LineEditorState,
    alt: Option<&AltGrid>,
) -> Result<GridSnapshot, CoreError> {
    let mut all_content = Vec::new();
    let mut row_ranges: Vec<(u32, u32)> = Vec::new();
    let mut style_pairs: Vec<(u32, StyleCode)> = Vec::new();
    let mut run_ranges: Vec<(u32, u32)> = Vec::new();
    let mut ctx = SnapshotCtx {
        all_content: &mut all_content,
        row_ranges: &mut row_ranges,
        style_pairs: &mut style_pairs,
        run_ranges: &mut run_ranges,
    };

    for row in rows.completed() {
        append_row(&mut ctx, content, styles, row.start, row.end)?;
    }

    for row in 0..screen.content_rows() {
        append_screen_row(&mut ctx, screen, row)?;
    }

    let mut block_text: Vec<u8> = Vec::new();
    let blocks: Vec<BlockRecord> = if grid.is_empty() {
        // A core that has seen no marks has one block by definition: the
        // whole scrollback. This is what `output_with_no_marks_lands_in_one_synthetic_block`
        // and every Phase 0 test rely on.
        vec![BlockRecord {
            id: 0,
            first_row: 0,
            row_count: checked_u32(row_ranges.len())?,
            state: BlockState::Running,
            source: BlockSource::Synthetic,
            exit_code: None,
            duration_ms: None,
            command: TextSpan::default(),
            cwd: TextSpan::default(),
            git_branch: TextSpan::default(),
        }]
    } else {
        let mut records = Vec::with_capacity(grid.blocks().count());
        for block in grid.blocks() {
            let command = append_block_text(&mut block_text, &block.meta.command)?;
            let cwd = append_block_text(&mut block_text, &block.meta.cwd)?;
            let git_branch = append_block_text(&mut block_text, &block.meta.git_branch)?;
            let first_row = checked_u32(block.first_row)?;
            let row_count = if block.state == BlockState::Running {
                checked_u32(row_ranges.len().saturating_sub(block.first_row))?
            } else {
                checked_u32(block.row_count)?
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
            });
        }
        records
    };

    Ok(GridSnapshot {
        content: all_content,
        rows: row_ranges,
        run_ranges,
        style_pairs,
        blocks,
        block_text,
        line_editor_state: line_editor_state.wire(),
        alt: alt.map(|grid| grid.snapshot()),
    })
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
    style_pairs: &'a mut Vec<(u32, StyleCode)>,
    run_ranges: &'a mut Vec<(u32, u32)>,
}

fn append_row(
    ctx: &mut SnapshotCtx,
    content: &Content,
    styles: &AttributeMap<StyleCode>,
    row_start: u64,
    row_end: u64,
) -> Result<(), CoreError> {
    let bytes = content.copy_range(row_start, row_end);
    let content_base = checked_u32(ctx.all_content.len())?;
    let content_end = checked_u32(ctx.all_content.len() + bytes.len())?;
    ctx.row_ranges.push((content_base, content_end));
    ctx.all_content.extend_from_slice(&bytes);

    let pair_start = checked_u32(ctx.style_pairs.len())?;
    if !bytes.is_empty() {
        // Style runs are keyed by the row's own byte span. `copy_range` returns
        // exactly that span, so the pair offsets and `bytes` always agree.
        let pairs = styles.runs(row_start, row_end);
        for (end, code) in pairs {
            ctx.style_pairs.push((end, code));
        }
    }
    let pair_end = checked_u32(ctx.style_pairs.len())?;
    ctx.run_ranges.push((pair_start, pair_end));
    Ok(())
}

fn append_screen_row(
    ctx: &mut SnapshotCtx,
    screen: &ScreenGrid,
    row: usize,
) -> Result<(), CoreError> {
    let width = (0..screen.cols())
        .rposition(|col| !screen.cell(row, col).is_blank())
        .map_or(0, |col| col + 1);
    let content_base = checked_u32(ctx.all_content.len())?;
    let pair_start = checked_u32(ctx.style_pairs.len())?;
    let mut run_style = None;
    let mut buffer = [0u8; 4];

    for col in 0..width {
        let cell = screen.cell(row, col);
        if cell.ch == '\0' {
            continue;
        }
        if run_style != Some(cell.style) {
            if let Some(previous) = run_style {
                ctx.style_pairs
                    .push((checked_u32(ctx.all_content.len())? - content_base, previous));
            }
            run_style = Some(cell.style);
        }
        ctx.all_content
            .extend_from_slice(cell.text(&mut buffer).as_bytes());
    }

    let content_end = checked_u32(ctx.all_content.len())?;
    if let Some(style) = run_style {
        ctx.style_pairs.push((content_end - content_base, style));
    }
    let pair_end = checked_u32(ctx.style_pairs.len())?;
    ctx.row_ranges.push((content_base, content_end));
    ctx.run_ranges.push((pair_start, pair_end));
    Ok(())
}
