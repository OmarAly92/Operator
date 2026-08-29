use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::style::StyleCode;
use crate::CoreError;

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
}

impl GridSnapshot {
    pub fn row_count(&self) -> usize {
        self.rows.len()
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
) -> Result<GridSnapshot, CoreError> {
    let open_start = rows.open_start();
    let end = content.end_offset();
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

    append_row(&mut ctx, content, styles, open_start, end)?;

    Ok(GridSnapshot {
        content: all_content,
        rows: row_ranges,
        run_ranges,
        style_pairs,
    })
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
