use vt_core::{BlockSource, BlockState, TerminalCore};

#[test]
fn a_fresh_core_reports_one_synthetic_block_covering_every_row() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"alpha\nbravo");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    let block = &snapshot.blocks[0];
    assert_eq!(block.first_row, 0);
    assert_eq!(block.row_count, snapshot.row_count() as u32);
    assert_eq!(block.state, BlockState::Running);
    assert_eq!(block.source, BlockSource::Synthetic);
    assert_eq!(block.exit_code, None);
    assert_eq!(snapshot.block_command(0), "");
    assert_eq!(snapshot.block_cwd(0), "");
}

#[test]
fn block_ids_are_stable_across_feeds() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"one\n");
    let first = core.snapshot().unwrap().blocks[0].id;
    core.feed(b"two\n");
    assert_eq!(core.snapshot().unwrap().blocks[0].id, first);
}

#[test]
fn marked_command_output_excludes_the_shell_prompt_and_command_echo() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.feed(b"\x1b]133;A\x07user% \x1b]133;B\x07echo hello\r\n\x1b]7000;v=1;cmd=echo%20hello\x07\x1b]133;C\x07hello\r\n\x1b]133;D;0\x07");
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks[0].first_row, 1);
    assert_eq!(snapshot.blocks[0].row_count, 1);
    assert_eq!(snapshot.block_command(0), "echo hello");
}

#[test]
fn an_unmarked_command_keeps_its_prompt_in_the_transcript() {
    let mut core = TerminalCore::new(80, 100).unwrap();
    core.feed(
        b"\x1b]133;A\x07user% \x1b]133;B\x07echo hello\r\n\x1b]133;C\x07hello\r\n\x1b]133;D;0\x07",
    );
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks[0].first_row, 0);
    assert_eq!(snapshot.blocks[0].row_count, 2);
}
