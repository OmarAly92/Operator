mod common;

use vt_core::{BlockState, TerminalCore};

const FISH_START: &str = "\x1b[?u\x1b[>0q\x1b]11;?\x1b\\\x1b[?1049h\x1bP+q696e646e\x1b\\\x1b[?1049l\x1b[0c\r\x1b]7000;v=1;id=t-1;cwd=/w;branch=main\x1b\\\x1b]7000;v=1;input-ready=1\x07\x1b]0;~/w\x1b\\\x1b[m\x1b]11;?\x1b\\\x1b[6n\x1b[0c\x1b[?2004h\x1b[?2031h\x1b[>4;1m\x1b=\x1b]133;A;click_events=1\x1b\\\x1b]133;B\x1b\\\x1b[K";

const FISH_SEQ: &str = "seq \r\x1b[4C1 \r\x1b[6C\x1b[?2004l\x1b[?2031l\x1b[>4;0m\x1b>5\r\x1b[7C\rseq 1 5\r\x1b[7C\r\n\x1b[m\x1b]133;C;cmdline_url=seq%201%205\x1b\\\x1b]7000;v=1;id=t-1;cmd=seq%201%205\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]0;seq 1 5 ~/w\x1b\\\x1b[m\r1\r\n2\r\n3\r\n4\r\n5\r\n\x1b]133;D;0\x1b\\\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]7000;v=1;id=t-2;cwd=/w;branch=main\x1b\\\x1b[?25h\x1b[2m\u{23ce}\x1b[m                                                                                                                       \r\u{23ce} \r\x1b[K\x1b]7000;v=1;input-ready=1\x07\x1b]0;~/w\x1b\\\x1b[m\x1b]11;?\x1b\\\x1b[6n\x1b[0c\x1b[?2004h\x1b[?2031h\x1b[>4;1m\x1b=\x1b]133;A;click_events=1\x1b\\\x1b]133;B\x1b\\\x1b[K";

const FISH_REPAINT_EMPTY: &str = "\x1b[6n\x1b[0c\x1b[?2004l\x1b[?2031l\x1b[>4;0m\x1b>\x1b]0;~/w\x1b\\\x1b[m\x1b[?2004h\x1b[?2031h\x1b[>4;1m\x1b=\r\r\x1b]133;A;click_events=1\x1b\\\x1b]133;B\x1b\\\x1b[J\x1b]133;A;click_events=1\x1b\\";

const FISH_TWO_LINE_START: &str = "\x1b]7000;v=1;id=t-1;cwd=/w;branch=main\x1b\\\x1b]7000;v=1;input-ready=1\x07\x1b]0;~/w\x1b\\\x1b[m\x1b[?2004h\x1b[K\x1b]133;A;click_events=1\x1b\\first-line\r\nsecond $ \x1b]133;B\x1b\\\x1b[K\r\x1b[9C";

const FISH_TWO_LINE_REPAINT: &str = "\x1b[6n\x1b[0c\x1b[?2004l\x1b[?2031l\x1b[>4;0m\x1b>\x1b]0;~/w\x1b\\\x1b[m\x1b[?2004h\x1b[?2031h\x1b[>4;1m\x1b=\r\r\x1b[A\x1b[K\x1b]133;A;click_events=1\x1b\\first-line\r\nsecond $ \x1b]133;B\x1b\\\x1b[J\r\x1b[9C";

fn core(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn block_count(core: &TerminalCore) -> usize {
    core.snapshot().unwrap().blocks.len()
}

#[test]
fn a_fish_prompt_repaint_after_each_resize_adds_no_block() {
    let mut core = core(120, 40);
    core.feed(FISH_START.as_bytes());
    core.feed(FISH_SEQ.as_bytes());
    assert_eq!(block_count(&core), 2);
    for cols in [55, 118, 55, 118] {
        core.resize(cols, 36);
        core.feed(FISH_REPAINT_EMPTY.as_bytes());
        common::check(&core);
        assert_eq!(block_count(&core), 2, "after a resize to {cols} columns");
    }
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.block_command(0), "seq 1 5");
    assert_eq!(snapshot.blocks[1].state, BlockState::Running);
    assert_eq!(snapshot.block_cwd(1), "/w");
}

#[test]
fn a_repainted_fish_prompt_keeps_its_block_for_the_next_command() {
    let mut core = core(120, 40);
    core.feed(FISH_START.as_bytes());
    core.feed(FISH_SEQ.as_bytes());
    core.resize(60, 36);
    core.feed(FISH_REPAINT_EMPTY.as_bytes());
    core.feed(
        b"\r\n\x1b]133;C;cmdline_url=echo%20hi\x1b\\\x1b]7000;v=1;id=t-2;cmd=echo%20hi\x1b\\\x1b]7000;v=1;input-released=1\x07hi\r\n\x1b]133;D;0\x1b\\\x1b]7000;v=1;id=t-2;exit=0\x1b\\",
    );
    common::check(&core);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks.len(), 2);
    assert_eq!(snapshot.block_command(1), "echo hi");
    assert_eq!(snapshot.block_cwd(1), "/w");
    assert_eq!(snapshot.blocks[1].exit_code, Some(0));
}

#[test]
fn a_repainted_two_line_fish_prompt_adds_no_block() {
    let mut core = core(80, 24);
    core.feed(FISH_TWO_LINE_START.as_bytes());
    assert_eq!(block_count(&core), 1);
    for cols in [40, 80, 40, 80] {
        core.resize(cols, 24);
        core.feed(FISH_TWO_LINE_REPAINT.as_bytes());
        common::check(&core);
        assert_eq!(block_count(&core), 1, "after a resize to {cols} columns");
    }
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.block_cwd(0), "/w");
    let texts: Vec<String> = (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).trim_end().to_string())
        .collect();
    assert_eq!(
        texts
            .iter()
            .filter(|row| row.as_str() == "first-line")
            .count(),
        1
    );
}

#[test]
fn a_prompt_started_below_an_unused_prompt_moves_it_instead_of_opening_a_new_block() {
    let mut core = core(40, 10);
    core.feed(
        b"\x1b]7000;v=1;cwd=/w\x07\x1b]133;A\x07$ \x1b]133;B\x07\r\n\x1b]133;A\x07$ \x1b]133;B\x07",
    );
    common::check(&core);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].state, BlockState::Running);
    assert_eq!(snapshot.blocks[0].first_row, 1);
    assert_eq!(snapshot.block_cwd(0), "/w");
}
