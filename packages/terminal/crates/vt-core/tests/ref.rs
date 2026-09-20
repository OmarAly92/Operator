use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use vt_core::TerminalCore;

const REF_SCROLLBACK_ROWS: usize = 200_000;

#[derive(Deserialize, Clone, Copy)]
struct SizeEntry {
    offset: usize,
    cols: usize,
    rows: usize,
}

#[derive(Deserialize, serde::Serialize, PartialEq, Eq, Debug)]
struct CursorExpectation {
    row: u32,
    col: u32,
    visible: bool,
}

macro_rules! ref_tests {
    ($($name:ident)*) => {
        $(
            #[test]
            fn $name() {
                let dir = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/ref")).join(stringify!($name));
                ref_test(&dir);
            }
        )*
    };
}

ref_tests! {
    alt_reset
    clear_underline
    colored_reset
    colored_underline
    csi_rep
    decaln_reset
    deccolm_reset
    delete_chars_reset
    delete_lines
    erase_chars_reset
    erase_in_line
    fish_cc
    grid_reset
    history
    hyperlinks
    indexed_256_colors
    insert_blank_reset
    issue_855
    ll
    newline_with_cursor_beyond_scroll_region
    origin_goto
    region_scroll_down
    row_reset
    saved_cursor
    saved_cursor_alt
    scroll_in_region_up_preserves_history
    scroll_up_reset
    selective_erasure
    sgr
    tab_rendering
    tmux_git_log
    tmux_htop
    underline
    vim_24bitcolors_bce
    vim_large_window_scroll
    vim_simple_edit
    vttest_cursor_movement_1
    vttest_insert
    vttest_origin_mode_1
    vttest_origin_mode_2
    vttest_scroll
    vttest_tab_clear_set
    wrapline_alt_toggle
    zerowidth
    zsh_tab_completion
    claude_spinner_10s
}

fn replay(dir: &Path) -> TerminalCore {
    let recording = fs::read(dir.join("recording")).expect("recording");
    let sizes: Vec<SizeEntry> =
        serde_json::from_str(&fs::read_to_string(dir.join("size.json")).expect("size.json"))
            .expect("size.json is a JSON array of {offset, cols, rows}");
    let first = sizes.first().expect("size.json has at least one entry");
    assert_eq!(first.offset, 0, "the first size entry starts at offset 0");
    let mut core = TerminalCore::new(first.cols, REF_SCROLLBACK_ROWS).expect("core");
    core.resize(first.cols, first.rows);
    let mut fed = 0usize;
    for size in sizes.iter().skip(1) {
        let upto = size.offset.min(recording.len());
        if upto > fed {
            core.feed(&recording[fed..upto]);
            fed = upto;
        }
        core.resize(size.cols, size.rows);
    }
    if fed < recording.len() {
        core.feed(&recording[fed..]);
    }
    core
}

fn render(core: &TerminalCore) -> (String, CursorExpectation) {
    let snapshot = core.snapshot().expect("snapshot");
    let mut screen = String::new();
    for index in 0..snapshot.row_count() {
        for _ in 0..snapshot.row_indent(index) {
            screen.push(' ');
        }
        screen.push_str(snapshot.row_text(index));
        screen.push('\n');
    }
    let cursor = CursorExpectation {
        row: snapshot.cursor_row,
        col: snapshot.cursor_col,
        visible: snapshot.cursor_visible,
    };
    (screen, cursor)
}

fn ref_test(dir: &Path) {
    let core = replay(dir);
    let (screen, cursor) = render(&core);
    let screen_path: PathBuf = dir.join("screen.txt");
    let cursor_path: PathBuf = dir.join("cursor.json");
    if std::env::var_os("UPDATE_REF").is_some() {
        fs::write(&screen_path, &screen).expect("write screen.txt");
        fs::write(&cursor_path, serde_json::to_string(&cursor).unwrap())
            .expect("write cursor.json");
        return;
    }
    let expected_screen =
        fs::read_to_string(&screen_path).expect("screen.txt (run with UPDATE_REF=1 to create)");
    let expected_cursor: CursorExpectation =
        serde_json::from_str(&fs::read_to_string(&cursor_path).expect("cursor.json"))
            .expect("cursor.json");
    if screen != expected_screen {
        let got: Vec<&str> = screen.lines().collect();
        let want: Vec<&str> = expected_screen.lines().collect();
        let mut reported = 0;
        for index in 0..got.len().max(want.len()) {
            let g = got.get(index).copied().unwrap_or("<missing>");
            let w = want.get(index).copied().unwrap_or("<missing>");
            if g != w {
                eprintln!("row {index}\n  want: {w:?}\n  got:  {g:?}");
                reported += 1;
                if reported == 10 {
                    break;
                }
            }
        }
        panic!(
            "{} rows differ from screen.txt ({} got, {} want)",
            reported,
            got.len(),
            want.len()
        );
    }
    assert_eq!(cursor, expected_cursor, "cursor differs from cursor.json");
}
