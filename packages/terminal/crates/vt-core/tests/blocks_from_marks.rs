use vt_core::{BlockSource, BlockState, TerminalCore};

#[test]
fn osc133_alone_produces_correct_blocks_with_no_bootstrap() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07ls\x1b]133;C\x07a.txt\nb.txt\n\x1b]133;D;0\x07");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.blocks[0].source, BlockSource::Osc133);
    assert_eq!(snapshot.blocks[0].exit_code, Some(0));
}

#[test]
fn an_unpaired_prompt_start_abandons_the_open_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07one\n\x1b]133;A\x07two\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 2);
    assert_eq!(snapshot.blocks[0].state, BlockState::Abandoned);
    assert_eq!(snapshot.blocks[1].state, BlockState::Running);
}

#[test]
fn extension_marks_upgrade_the_block_and_carry_the_command() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=git%20status;cwd=%2Ftmp;branch=main\x07");
    core.feed(b"\x1b]133;C\x07clean\n\x1b]133;D;0\x07");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks[0].source, BlockSource::Extension);
    assert_eq!(snapshot.block_command(0), "git status");
    assert_eq!(snapshot.block_cwd(0), "/tmp");
    assert_eq!(snapshot.block_branch(0), "main");
}

#[test]
fn output_with_no_marks_lands_in_one_synthetic_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"no marks here\nat all\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].source, BlockSource::Synthetic);
}

#[test]
fn alt_screen_enter_and_leave_are_tracked() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    assert!(!core.alt_screen_active());
    core.feed(b"\x1b[?1049h");
    assert!(core.alt_screen_active());
    core.feed(b"\x1b[?1049l");
    assert!(!core.alt_screen_active());
}

#[test]
fn marks_inside_the_alt_screen_do_not_change_the_block_list() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07before\n");
    let before = core.snapshot().unwrap().blocks.len();

    core.feed(b"\x1b[?1049h");
    core.feed(b"\x1b]133;A\x07\x1b]133;A\x07\x1b]133;D;1\x07");
    assert_eq!(core.snapshot().unwrap().blocks.len(), before);

    core.feed(b"\x1b[?1049l");
    assert!(!core.alt_screen_active());
}

#[test]
fn blocks_survive_scrollback_trimming() {
    let mut core = TerminalCore::new(20, 10).unwrap();
    for index in 0..50 {
        core.feed(
            format!("\x1b]133;A\x07\x1b]133;C\x07row{index:03}\n\x1b]133;D;0\x07").as_bytes(),
        );
    }
    let snapshot = core.snapshot().unwrap();

    assert!(snapshot.blocks.len() <= 10);
    assert!(snapshot.blocks.iter().all(|b| b.row_count > 0));
    assert_eq!(snapshot.blocks.first().unwrap().first_row, 0);
}
