use vt_core::{CellSpan, CellStyle, GridSnapshot, TerminalCore};

use crate::block_marks::{settled_rows_end, SETTLED_BEGIN, SETTLED_END};
use crate::line_editor_marks::write_line_editor_marks;
use crate::{
    clip_row, frame_first_stable, write_cursor_position, write_indent, write_modes, READY_MARK,
};
use vt_core::style_sgr::write_styled_row_with;

// Serializes the terminal's CURRENT STATE as a wire-faithful repaint: the
// bytes a freshly attached client can apply to arrive at exactly the grid the
// host holds right now, at the host's current geometry.
//
// This is what attach replay must send, and it is NOT what `vt_render_styled`
// produces. The other renderers answer "what does the screen say", for
// GetOutput; they emit rows terminated by bare LFs and leave the cursor
// wherever the last row ended. A replay has to answer "how do I reproduce this
// screen", which additionally means CR-LF row terminators (the receiving
// terminal has LNM off, so a bare LF would stair-step every row), the
// alternate-screen mode set when the child is in it, and a final cursor
// placement — without which the child's next in-place redraw (cursor-up N,
// rewrite) lands on the wrong rows and paints a second copy of its UI below
// the first.
//
// Returns an empty frame for a genuinely empty terminal and None when the
// snapshot fails; `vt_replay` maps them to 0 and RENDER_ERR.
pub(crate) fn replay_frame(core: &TerminalCore, lines: u32) -> Option<Vec<u8>> {
    let Ok(snapshot) = core.snapshot() else {
        return None;
    };

    let mut text = String::new();
    if let Some(alt) = &snapshot.alt {
        // A full-screen child owns every cell of the alt grid, so the
        // replay is absolute: enter the alternate screen, paint all rows
        // from home, then place the cursor by absolute address.
        text.push_str(&format!(
            "\x1b]7000;v=1;origin={}\x1b\\",
            frame_first_stable(&snapshot, lines)
        ));
        write_modes(&mut text, core, true);
        text.push_str("\x1b[H");
        for (i, (start, end)) in alt.row_ranges.iter().enumerate() {
            let row_bytes = &alt.content[*start as usize..*end as usize];
            let (pair_start, pair_end) = alt.run_ranges[i];
            let pairs = &alt.style_pairs[pair_start as usize..pair_end as usize];
            let last = i + 1 == alt.row_ranges.len();
            write_styled_row_with(
                &mut text,
                row_bytes,
                pairs,
                &|id| snapshot.link_uri(id),
                if last { "" } else { "\r\n" },
            );
        }
        write_cursor_position(&mut text, alt.cursor_row, alt.cursor_col);
        if !alt.cursor_visible {
            text.push_str("\x1b[?25l");
        }
    } else {
        let total = snapshot.row_count();
        let first = total.saturating_sub(lines as usize);
        // A terminal that has drawn nothing still reports a cursor at the
        // origin over blank rows. Replaying that is not wrong, only
        // useless -- and the host reads 0 as "no replay frame to send".
        let blank = snapshot.cursor_row == 0
            && snapshot.cursor_col == 0
            && (first..total).all(|i| snapshot.row_text(i).is_empty());
        if total == 0 || blank {
            return Some(core.pending_sync_bytes().to_vec());
        }
        text.push_str(&format!(
            "\x1b]7000;v=1;origin={}\x1b\\",
            frame_first_stable(&snapshot, lines)
        ));
        write_modes(&mut text, core, false);
        // Rows are clipped to the grid. vt-core rewraps the hot window on
        // resize and `vt_touch_history` rewraps the cold rest before the
        // host renders this frame, so a row wider than the grid should not
        // exist; the clip guards the replay anyway, because a row wider
        // than the receiving grid wraps, lands as two rows and pushes every
        // row below it down by one -- the client's grid no longer agrees
        // with the host's about which row is which.
        let cols = core.columns();
        let (settled_row, settled_col) = settled_point(core, &snapshot, total);
        let settled = settled_row > first || (settled_row == first && settled_col > 0);
        if settled {
            text.push_str(SETTLED_BEGIN);
        }
        for i in first..total {
            let indent = snapshot.row_indent(i).min(cols.saturating_sub(1));
            let (row_bytes, pairs) = clip_row(
                snapshot.row_text(i).as_bytes(),
                snapshot.row_style_pairs(i),
                cols - indent,
            );
            let last = i + 1 == total;
            let terminator = if last { "" } else { "\r\n" };
            if settled && i == settled_row && settled_col > 0 {
                let split = settled_col.saturating_sub(indent);
                write_indent(&mut text, indent.min(settled_col));
                let at = byte_at_column(row_bytes, snapshot.row_cell_spans(i), split);
                let (head, tail) = split_pairs(&pairs, at);
                write_styled_row_with(
                    &mut text,
                    &row_bytes[..at],
                    &head,
                    &|id| snapshot.link_uri(id),
                    "",
                );
                text.push_str(SETTLED_END);
                write_indent(&mut text, indent.saturating_sub(settled_col));
                write_styled_row_with(
                    &mut text,
                    &row_bytes[at..],
                    &tail,
                    &|id| snapshot.link_uri(id),
                    terminator,
                );
                continue;
            }
            write_indent(&mut text, indent);
            write_styled_row_with(
                &mut text,
                row_bytes,
                &pairs,
                &|id| snapshot.link_uri(id),
                terminator,
            );
            if settled && settled_col == 0 && i + 1 == settled_row {
                text.push_str(SETTLED_END);
            }
        }
        // The cursor is addressed RELATIVELY, from the last row written.
        // Absolute addressing would be wrong: these rows scroll up into
        // the client's scrollback as they are written, so the row the
        // cursor belongs on has no fixed screen coordinate.
        let cursor_row = snapshot.cursor_row as usize;
        let last_row = total - 1;
        if cursor_row > last_row {
            // The cursor sits on a trailing blank row that the snapshot
            // does not materialise; walk down to it.
            for _ in 0..(cursor_row - last_row) {
                text.push_str("\r\n");
            }
        } else if cursor_row < last_row {
            text.push_str(&format!("\x1b[{}A", last_row - cursor_row));
        }
        write_line_editor_marks(&mut text, core, first, cursor_row);
        text.push('\r');
        let cursor_col = (snapshot.cursor_col as usize).min(cols.saturating_sub(1));
        if cursor_col > 0 {
            text.push_str(&format!("\x1b[{}C", cursor_col));
        }
        if !snapshot.cursor_visible {
            text.push_str("\x1b[?25l");
        }
    }

    let mut out = text.into_bytes();
    out.extend_from_slice(core.pending_sync_bytes());
    if !out.is_empty() {
        out.extend_from_slice(READY_MARK.as_bytes());
    }
    Some(out)
}

fn settled_point(core: &TerminalCore, snapshot: &GridSnapshot, total: usize) -> (usize, usize) {
    let end = settled_rows_end(snapshot);
    match core.command_end() {
        Some((row, col)) if end > 0 && (row == end || row + 1 == end) && row < total => (row, col),
        _ => (end.min(total - 1), 0),
    }
}

fn byte_at_column(row: &[u8], spans: &[CellSpan], column: usize) -> usize {
    let text = std::str::from_utf8(row).unwrap_or("");
    let mut at = 0;
    let mut filled = 0;
    while at < text.len() && filled < column {
        match spans.iter().find(|span| span.start as usize == at) {
            Some(span) => {
                filled += usize::from(span.width);
                at = span.end as usize;
            }
            None => {
                filled += 1;
                at += text[at..].chars().next().map_or(1, char::len_utf8);
            }
        }
    }
    at.min(row.len())
}

type StylePairs = Vec<(u32, CellStyle)>;

fn split_pairs(pairs: &[(u32, CellStyle)], at: usize) -> (StylePairs, StylePairs) {
    let at = at as u32;
    let mut head = Vec::new();
    let mut tail = Vec::new();
    for &(end, style) in pairs {
        if end <= at {
            head.push((end, style));
            continue;
        }
        if head.last().is_none_or(|&(last, _)| last < at) && at > 0 {
            head.push((at, style));
        }
        tail.push((end - at, style));
    }
    (head, tail)
}
