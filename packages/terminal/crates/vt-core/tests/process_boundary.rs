use vt_core::{BlockSource, BlockState, TerminalCore};

const BOUNDARY_OK: &[u8] = b"\x1b]7000;v=1;boundary=0\x07";
const BOUNDARY_UNKNOWN: &[u8] = b"\x1b]7000;v=1;boundary=\x07";

#[test]
fn a_boundary_closes_the_markless_frame_and_starts_a_fresh_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.resize(40, 6);
    core.set_agent_tui_mode(true);
    core.feed(b"old banner\r\nold line 2\r\n");
    core.feed(BOUNDARY_OK);
    core.feed(b"new banner\r\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 2, "{:?}", snapshot.blocks);
    let old = &snapshot.blocks[0];
    assert_eq!(old.source, BlockSource::Synthetic);
    assert_eq!(old.state, BlockState::Finished);
    assert_eq!(old.exit_code, Some(0));
    assert_eq!(old.first_row, 0);
    assert_eq!(old.row_count, 2);
    assert_eq!(snapshot.row_text(0), "old banner");
    assert_eq!(snapshot.row_text(1), "old line 2");

    let new = &snapshot.blocks[1];
    assert_eq!(new.source, BlockSource::Synthetic);
    assert_eq!(new.state, BlockState::Running);
    assert_eq!(new.first_row, 2);
    assert_eq!(snapshot.row_text(new.first_row as usize), "new banner");
    assert_eq!(snapshot.cursor_row, 3);
}

#[test]
fn a_boundary_scrolls_the_old_frame_out_even_when_clears_are_in_place() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.resize(40, 4);
    core.set_agent_tui_mode(true);
    core.feed(b"one\r\ntwo\r\nthree");
    core.feed(BOUNDARY_UNKNOWN);
    core.feed(b"\x1b[Hfresh");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.blocks[0].exit_code, None);
    assert_eq!(snapshot.blocks[0].row_count, 3);
    assert_eq!(snapshot.row_text(2), "three");
    assert_eq!(snapshot.row_text(3), "fresh");
    assert_eq!(snapshot.blocks[1].first_row, 3);
}

#[test]
fn a_boundary_finishes_an_open_osc133_block_with_the_exit_code() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07claude\r\n\x1b]133;C\x07hello\r\n");
    core.feed(b"\x1b]7000;v=1;boundary=1\x07");
    core.feed(b"\x1b]133;A\x07$ ");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 2, "{:?}", snapshot.blocks);
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.blocks[0].exit_code, Some(1));
    assert_eq!(snapshot.blocks[0].row_count, 2);
    assert_eq!(snapshot.blocks[1].source, BlockSource::Osc133);
    assert_eq!(snapshot.blocks[1].state, BlockState::Running);
    assert_eq!(snapshot.blocks[1].first_row, 2);
}

#[test]
fn a_boundary_with_nothing_after_it_adds_no_empty_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"old\r\n");
    core.feed(BOUNDARY_OK);
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1, "{:?}", snapshot.blocks);
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
}

#[test]
fn markless_output_before_the_first_prompt_becomes_its_own_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"motd\r\n");
    core.feed(b"\x1b]133;A\x07$ ");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 2, "{:?}", snapshot.blocks);
    assert_eq!(snapshot.blocks[0].source, BlockSource::Synthetic);
    assert_eq!(snapshot.blocks[0].state, BlockState::Abandoned);
    assert_eq!(snapshot.blocks[0].row_count, 1);
    assert_eq!(snapshot.blocks[1].source, BlockSource::Osc133);
    assert_eq!(snapshot.blocks[1].first_row, 1);
}
