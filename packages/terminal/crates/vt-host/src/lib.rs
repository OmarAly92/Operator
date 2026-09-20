use std::cell::RefCell;
use std::collections::HashMap;
use vt_core::{CellStyle, StyleCode, TerminalCore};

thread_local! {
    static CORES: RefCell<HashMap<u32, TerminalCore>> = RefCell::new(HashMap::new());
    static NEXT_ID: RefCell<u32> = const { RefCell::new(1) };
}

#[no_mangle]
pub extern "C" fn vt_alloc(len: u32) -> u32 {
    let mut buf = Vec::<u8>::with_capacity(len as usize);
    let ptr = buf.as_mut_ptr() as u32;
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn vt_free(ptr: u32, len: u32) {
    unsafe { drop(Vec::from_raw_parts(ptr as *mut u8, 0, len as usize)) };
}

#[no_mangle]
pub extern "C" fn vt_new(cols: u32, rows: u32, scrollback_rows: u32, scrollback_bytes: u32) -> u32 {
    let limits = vt_core::Limits {
        rows: scrollback_rows as usize,
        bytes: scrollback_bytes as usize,
    };
    let Ok(mut core) = TerminalCore::with_limits(cols as usize, limits) else {
        return 0;
    };
    core.set_reflow_on_resize(false);
    core.set_answers_queries(true);
    core.resize(cols as usize, rows as usize);
    NEXT_ID.with(|n| {
        let mut n = n.borrow_mut();
        let id = *n;
        *n += 1;
        CORES.with(|c| c.borrow_mut().insert(id, core));
        id
    })
}

#[no_mangle]
pub extern "C" fn vt_memory_stats(handle: u32, out_ptr: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => {
            let stats = core.memory_stats();
            let words = [
                stats.content_bytes as u32,
                stats.style_entries as u32,
                stats.rows as u32,
                stats.blocks as u32,
            ];
            let out = out_ptr as *mut u8;
            for (index, word) in words.iter().enumerate() {
                let bytes = word.to_le_bytes();
                unsafe {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out.add(index * 4), 4);
                }
            }
            1
        }
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_resize(handle: u32, cols: u32, rows: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.resize(cols as usize, rows as usize);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_feed(handle: u32, ptr: u32, len: u32, now_ms: u64) {
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.feed_at(bytes, now_ms);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_tick(handle: u32, now_ms: u64) -> u32 {
    CORES.with(|c| match c.borrow_mut().get_mut(&handle) {
        Some(core) => u32::from(core.tick(now_ms)),
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_set_terminal_identity(handle: u32, ptr: u32, len: u32) {
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    let name = String::from_utf8_lossy(bytes);
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_terminal_identity(&name);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_take_query_replies(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let mut cores = c.borrow_mut();
        let Some(core) = cores.get_mut(&handle) else {
            return RENDER_ERR;
        };
        let replies = core.take_query_replies();
        if replies.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(replies.as_ptr(), out_ptr as *mut u8, replies.len());
        }
        replies.len() as u32
    })
}

/// Rewraps every history row vt-core left cut at an older width, so the rows
/// a replay or a history chunk is about to serialise are all at the current
/// grid width. The renderer does this a window at a time off its own export
/// (`WasmTerminalCore::sync`); the mirror has no export, and the replay and
/// the chunks would otherwise clip a stale row's tail off (TERMINAL.md §4.20).
///
/// It runs ONCE, before the frame's origin is rendered: rewrapping changes how
/// many rows history holds, and the client's chunks are numbered downward from
/// that origin. Rewrapping between chunks would move the numbering out from
/// under the origin the client already adopted and the receiver would reject
/// every chunk.
#[no_mangle]
pub extern "C" fn vt_touch_history(handle: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.touch_rows(0..usize::MAX);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_in_sync(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) if core.synchronized_output() => 1,
        _ => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_alt_active(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) if core.alt_screen_active() => 1,
        _ => 0,
    })
}

pub const RENDER_ERR: u32 = u32::MAX;
pub const RENDER_TOO_BIG: u32 = u32::MAX - 1;

const READY_MARK: &str = "\x1b]7000;v=1;ready=1\x1b\\";

fn frame_first_stable(snapshot: &vt_core::GridSnapshot, lines: u32) -> u64 {
    snapshot.first_stable_row + snapshot.row_count().saturating_sub(lines as usize) as u64
}

fn write_modes(text: &mut String, core: &TerminalCore, alt: bool) {
    if alt {
        text.push_str("\x1b[?1049h");
    }
    // mouse_tracking_level is a bitmask, not an enum
    // (crates/vt-core/src/parser.rs:341-350).
    let tracking = core.mouse_tracking_level();
    if tracking & 0b001 != 0 {
        text.push_str("\x1b[?1000h");
    }
    if tracking & 0b010 != 0 {
        text.push_str("\x1b[?1002h");
    }
    if tracking & 0b100 != 0 {
        text.push_str("\x1b[?1003h");
    }
    if core.sgr_mouse() {
        text.push_str("\x1b[?1006h");
    }
    if core.bracketed_paste() {
        text.push_str("\x1b[?2004h");
    }
    if core.focus_reporting() {
        text.push_str("\x1b[?1004h");
    }
    if core.application_cursor_keys() {
        text.push_str("\x1b[?1h");
    }
}

// Writes the last `lines` rendered rows as UTF-8 into out_ptr, returning the
// byte count written. 0 means a genuinely empty screen; RENDER_ERR means a bad
// handle or snapshot failure; RENDER_TOO_BIG means out_cap is too small. The
// three must stay distinct: the caller treats only RENDER_* as failures, never
// an empty screen. When the alternate screen is active the alt grid is rendered
// instead, matching what `tmux capture-pane` returns for a full-screen app.
#[no_mangle]
pub extern "C" fn vt_render(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Ok(snapshot) = core.snapshot() else {
            return RENDER_ERR;
        };

        let mut text = String::new();
        if let Some(alt) = &snapshot.alt {
            for (start, end) in &alt.row_ranges {
                text.push_str(
                    std::str::from_utf8(&alt.content[*start as usize..*end as usize]).unwrap_or(""),
                );
                text.push('\n');
            }
        } else {
            let total = snapshot.row_count();
            let first = total.saturating_sub(lines as usize);
            for i in first..total {
                write_indent(&mut text, snapshot.row_indent(i));
                text.push_str(snapshot.row_text(i));
                text.push('\n');
            }
        }

        let bytes = text.as_bytes();
        if bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
        }
        bytes.len() as u32
    })
}

// Same contract as `vt_render`, but re-emits SGR escapes at each style-run
// boundary so colour/bold/dim survive the round trip through the snapshot.
#[no_mangle]
pub extern "C" fn vt_render_styled(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Ok(snapshot) = core.snapshot() else {
            return RENDER_ERR;
        };

        let mut text = String::new();
        if let Some(alt) = &snapshot.alt {
            for (i, (start, end)) in alt.row_ranges.iter().enumerate() {
                let row_bytes = &alt.content[*start as usize..*end as usize];
                let (pair_start, pair_end) = alt.run_ranges[i];
                let pairs = &alt.style_pairs[pair_start as usize..pair_end as usize];
                write_styled_row(&mut text, row_bytes, pairs);
            }
        } else {
            let total = snapshot.row_count();
            let first = total.saturating_sub(lines as usize);
            for i in first..total {
                let row_bytes = snapshot.row_text(i).as_bytes();
                write_indent(&mut text, snapshot.row_indent(i));
                write_styled_row(&mut text, row_bytes, snapshot.row_style_pairs(i));
            }
        }

        let bytes = text.as_bytes();
        if bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
        }
        bytes.len() as u32
    })
}

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
// Returns 0 for a genuinely empty terminal; RENDER_ERR / RENDER_TOO_BIG carry
// the same meaning as in `vt_render`.
#[no_mangle]
pub extern "C" fn vt_replay(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Ok(snapshot) = core.snapshot() else {
            return RENDER_ERR;
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
                write_styled_row_with(&mut text, row_bytes, pairs, if last { "" } else { "\r\n" });
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
                let pending = core.pending_sync_bytes();
                if pending.is_empty() {
                    return 0;
                }
                if pending.len() > out_cap as usize {
                    return RENDER_TOO_BIG;
                }
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        pending.as_ptr(),
                        out_ptr as *mut u8,
                        pending.len(),
                    );
                }
                return pending.len() as u32;
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
            for i in first..total {
                let indent = snapshot.row_indent(i).min(cols.saturating_sub(1));
                let (row_bytes, pairs) = clip_row(
                    snapshot.row_text(i).as_bytes(),
                    snapshot.row_style_pairs(i),
                    cols - indent,
                );
                let last = i + 1 == total;
                write_indent(&mut text, indent);
                write_styled_row_with(&mut text, row_bytes, &pairs, if last { "" } else { "\r\n" });
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
        if out.is_empty() {
            return 0;
        }
        out.extend_from_slice(READY_MARK.as_bytes());
        if out.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
        }
        out.len() as u32
    })
}

/// `before == u64::MAX` means "start just above the frame of `lines` rows".
/// Rows are clipped to the grid exactly as `vt_replay` clips them, and for the
/// same reason; `vt_touch_history` is what keeps a lazily-rewrapped row from
/// reaching the clip still cut at an older, wider grid.
/// Writes one chunk and stores the chunk's own first stable row at
/// `next_ptr` as 8 little-endian bytes. Returns the byte count written,
/// 0 when no history remains, or RENDER_ERR / RENDER_TOO_BIG.
#[no_mangle]
pub extern "C" fn vt_history_chunk(
    handle: u32,
    before: u64,
    lines: u32,
    max_rows: u32,
    out_ptr: u32,
    out_cap: u32,
    next_ptr: u32,
) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Ok(snapshot) = core.snapshot() else {
            return RENDER_ERR;
        };
        let first_stable = snapshot.first_stable_row;
        let bound_stable = if before == u64::MAX {
            frame_first_stable(&snapshot, lines)
        } else {
            before
        };
        if bound_stable <= first_stable {
            return 0;
        }
        let bound = (bound_stable - first_stable) as usize;
        let count = bound.min(max_rows.max(1) as usize);
        let start = bound - count;
        let chunk_first_stable = first_stable + start as u64;

        let mut text = format!(
            "\x1b]7000;v=1;history={},{}\x1b\\",
            chunk_first_stable, count
        );
        let cols = core.columns();
        for row in start..bound {
            write_block_open(&mut text, &snapshot, row);
            let indent = snapshot.row_indent(row).min(cols.saturating_sub(1));
            let (row_bytes, pairs) = clip_row(
                snapshot.row_text(row).as_bytes(),
                snapshot.row_style_pairs(row),
                cols - indent,
            );
            write_indent(&mut text, indent);
            // The closing mark is the row's terminator, not a separate line:
            // a byte after the chunk's final CR-LF falls through to the live
            // parser (Task 3's receiver ends the chunk at the count-th LF).
            let mut terminator = String::new();
            write_block_close(&mut terminator, &snapshot, row);
            terminator.push_str("\r\n");
            write_styled_row_with(&mut text, row_bytes, &pairs, &terminator);
        }

        let out = text.into_bytes();
        if out.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
            std::ptr::copy_nonoverlapping(
                chunk_first_stable.to_le_bytes().as_ptr(),
                next_ptr as *mut u8,
                8,
            );
        }
        out.len() as u32
    })
}

fn write_block_open(text: &mut String, snapshot: &vt_core::GridSnapshot, row: usize) {
    for (index, block) in snapshot.blocks.iter().enumerate() {
        if block.source == vt_core::BlockSource::Synthetic {
            continue;
        }
        if block.first_row as usize == row {
            text.push_str("\x1b]7000;v=1;id=");
            text.push_str(&index.to_string());
            text.push_str(";cmd=");
            percent_encode_into(text, snapshot.block_command(index));
            text.push_str("\x1b\\");
            return;
        }
    }
}

fn write_block_close(text: &mut String, snapshot: &vt_core::GridSnapshot, row: usize) {
    for block in snapshot.blocks.iter() {
        if block.source == vt_core::BlockSource::Synthetic {
            continue;
        }
        let last_row = block.first_row as usize + block.row_count as usize - 1;
        if last_row == row {
            if let Some(exit_code) = block.exit_code {
                text.push_str("\x1b]7000;v=1;exit=");
                text.push_str(&exit_code.to_string());
                text.push_str("\x1b\\");
            }
            return;
        }
    }
}

fn percent_encode_into(text: &mut String, value: &str) {
    for ch in value.chars() {
        if ch.is_ascii() && matches!(ch as u8, b';' | b'=' | b'%' | 0x00..=0x1f) {
            text.push_str(&format!("%{:02X}", ch as u8));
        } else {
            text.push(ch);
        }
    }
}

fn clip_row<'a>(
    row_bytes: &'a [u8],
    pairs: &[(u32, CellStyle)],
    cols: usize,
) -> (&'a [u8], Vec<(u32, CellStyle)>) {
    let text = std::str::from_utf8(row_bytes).unwrap_or("");
    let Some((limit, _)) = text.char_indices().nth(cols) else {
        return (row_bytes, pairs.to_vec());
    };
    let mut clipped = Vec::with_capacity(pairs.len());
    for (end, style) in pairs {
        if *end as usize >= limit {
            clipped.push((limit as u32, *style));
            break;
        }
        clipped.push((*end, *style));
    }
    (&row_bytes[..limit], clipped)
}

fn write_indent(text: &mut String, indent: usize) {
    text.extend(std::iter::repeat_n(' ', indent));
}

fn write_cursor_position(text: &mut String, row: usize, col: usize) {
    text.push_str(&format!("\x1b[{};{}H", row + 1, col + 1));
}

fn write_styled_row(text: &mut String, row_bytes: &[u8], pairs: &[(u32, CellStyle)]) {
    write_styled_row_with(text, row_bytes, pairs, "\n");
}

fn write_styled_row_with(
    text: &mut String,
    row_bytes: &[u8],
    pairs: &[(u32, CellStyle)],
    terminator: &str,
) {
    let mut start = 0usize;
    for (end, style) in pairs {
        let end = *end as usize;
        text.push_str("\x1b[0m");
        if let Some(params) = style_sgr_params(*style) {
            text.push_str("\x1b[");
            text.push_str(&params);
            text.push('m');
        }
        text.push_str(std::str::from_utf8(&row_bytes[start..end]).unwrap_or(""));
        start = end;
    }
    text.push_str("\x1b[0m");
    text.push_str(terminator);
}

// Mirrors the bit layout in vt-core's `style.rs` (`TAG_INDEXED`/`TAG_RGB`,
// neither exported) since only `StyleCode`'s public accessors cross the
// crate boundary.
const TAG_INDEXED: u32 = 0x0100_0000;
const TAG_RGB: u32 = 0x0200_0000;

fn colour_params(colour: StyleCode, base: u32, extended: u32) -> String {
    let value = colour.value();
    if value & TAG_RGB != 0 {
        let rgb = value & 0x00ff_ffff;
        format!(
            "{};2;{};{};{}",
            extended,
            (rgb >> 16) & 0xff,
            (rgb >> 8) & 0xff,
            rgb & 0xff
        )
    } else if value & TAG_INDEXED != 0 {
        format!("{};5;{}", extended, value & 0xff)
    } else if value < 8 {
        format!("{}", base + value)
    } else {
        format!("{}", base + 60 + (value - 8))
    }
}

fn style_sgr_params(style: CellStyle) -> Option<String> {
    let mut params = Vec::new();
    if style.fg.is_bold() {
        params.push("1".to_string());
    }
    if style.fg.is_dim() {
        params.push("2".to_string());
    }
    let foreground = style.fg.colour();
    if foreground != StyleCode::DEFAULT.colour() {
        params.push(colour_params(foreground, 30, 38));
    }
    let background = style.bg.colour();
    if background != StyleCode::DEFAULT_BACKGROUND.colour() {
        params.push(colour_params(background, 40, 48));
    }
    if params.is_empty() {
        None
    } else {
        Some(params.join(";"))
    }
}
