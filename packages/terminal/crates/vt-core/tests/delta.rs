mod common;

use vt_core::{Delta, DeltaKind, Limits, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 3);
    let first = core.take_delta();
    assert_eq!(first.kind, DeltaKind::Full);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: &[&str]) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

#[test]
fn printing_marks_one_screen_row_dirty() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b"]);
    core.take_delta();
    let before = core.generation();
    core.feed(b"\x1b[2;1HX");
    assert_eq!(core.generation(), before + 1);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.screen_rows, vec![1, 2]);
    assert_eq!(delta.appended_history, 0..0);
    assert_eq!(delta.trimmed_rows, 0);
    assert_eq!(delta.remap, None);
    assert_eq!(core.snapshot().unwrap().row_text(1), "X");
    common::check(&core);
}

#[test]
fn a_cursor_move_marks_the_row_it_left_and_the_row_it_reached() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b"]);
    core.take_delta();
    core.feed(b"\x1b[1;1H");
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.screen_rows, vec![0, 2]);
}

#[test]
fn toggling_cursor_visibility_marks_the_cursor_row() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b"]);
    core.take_delta();
    core.feed(b"\x1b[?25l");
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.screen_rows, vec![2]);
    core.feed(b"\x1b[?25l");
    assert_eq!(core.take_delta().screen_rows, Vec::<usize>::new());
    core.feed(b"\x1b[?25h");
    assert_eq!(core.take_delta().screen_rows, vec![2]);
}

#[test]
fn scroll_off_appends_history_and_marks_moved_rows() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b", "c"]);
    core.take_delta();
    feed_lines(&mut core, &["d"]);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.appended_history, 1..2);
    assert_eq!(delta.screen_rows, vec![0, 1, 2]);
    assert_eq!(core.history_rows(), 2);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.history_rows, 2);
    assert_eq!(snapshot.row_text(1), "b");
    common::check(&core);
}

#[test]
fn rewrap_yields_full_delta_with_remap() {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(100)).unwrap();
    core.resize(20, 2);
    core.take_delta();
    core.feed(b"aaaaaaaaaabbbbbbbbbbcccccccccc\r\n");
    core.feed(b"tail\r\n");
    core.take_delta();
    assert_eq!(core.history_rows(), 2);
    core.resize(40, 2);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Full);
    assert_eq!(core.history_rows(), 2);
    assert_eq!(delta.remap, Some(vec![(0, 0), (1, 0), (2, 1)]));
    assert_eq!(delta.screen_rows, vec![0]);
    assert_eq!(
        core.snapshot().unwrap().row_text(0),
        "aaaaaaaaaabbbbbbbbbbcccccccccc"
    );
    assert_eq!(core.snapshot().unwrap().row_text(1), "tail");
    common::check(&core);
}

#[test]
fn trim_reports_trimmed_rows() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4", "5"]);
    let first = core.take_delta();
    assert_eq!(first.appended_history, 0..3);
    feed_lines(&mut core, &["6", "7", "8"]);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.trimmed_rows, 1);
    assert_eq!(delta.appended_history, 2..5);
    assert_eq!(core.first_stable_row(), 1);
    common::check(&core);
}

#[test]
fn take_delta_clears() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b", "c", "d"]);
    let first = core.take_delta();
    assert_ne!(first.screen_rows, Vec::<usize>::new());
    let generation = core.generation();
    let second = core.take_delta();
    assert_eq!(
        second,
        Delta {
            generation,
            kind: DeltaKind::Partial,
            trimmed_rows: 0,
            appended_history: 2..2,
            screen_rows: Vec::new(),
            remap: None,
            history_rewritten_from: None,
        }
    );
    common::check(&core);
}

#[test]
fn alt_screen_and_process_boundary_are_full() {
    let mut core = core();
    feed_lines(&mut core, &["a"]);
    core.take_delta();
    core.feed(b"\x1b[?1049h");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"x");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"\x1b[?1049l");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    common::check(&core);
}

#[test]
fn snapshot_equals_the_export_api() {
    let mut core = core();
    feed_lines(&mut core, &["\x1b[31mred\x1b[0m", "plain", "  - bullet"]);
    let snapshot = core.snapshot().unwrap();
    let history = core.export_history_rows(0..core.history_rows());
    let screen = core.export_screen_rows();
    assert_eq!(history.len() + screen.len(), snapshot.row_count());
    for (index, row) in history.iter().chain(screen.iter()).enumerate() {
        assert_eq!(row.bytes, snapshot.row_text(index).as_bytes());
        assert_eq!(usize::from(row.indent), snapshot.row_indent(index));
        assert_eq!(row.styles.as_slice(), snapshot.row_style_pairs(index));
    }
    let (records, text) = core
        .export_blocks(snapshot.row_count(), |row| {
            snapshot.rows[row].1 > snapshot.rows[row].0
        })
        .unwrap();
    assert_eq!(records, snapshot.blocks);
    assert_eq!(text, snapshot.block_text);
    let (row, col, visible) = core.export_cursor();
    assert_eq!(
        (row as u32, col as u32, visible),
        (
            snapshot.cursor_row,
            snapshot.cursor_col,
            snapshot.cursor_visible
        )
    );
}
