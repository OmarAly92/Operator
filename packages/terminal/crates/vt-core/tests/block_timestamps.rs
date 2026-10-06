mod common;

use vt_core::{BlockRecord, BlockState, TerminalCore};

fn records(core: &TerminalCore) -> Vec<BlockRecord> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    snapshot.blocks
}

#[test]
fn a_block_without_hook_timestamps_gets_the_feed_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n", 1_000);
    core.feed_at(b"\x1b]133;D;0\x07", 4_500);
    let blocks = records(&core);
    let block = blocks
        .iter()
        .find(|b| b.state == BlockState::Finished)
        .expect("finished block");
    assert_eq!(block.started_at_ms, Some(1_000));
    assert_eq!(block.finished_at_ms, Some(4_500));
    assert_eq!(block.duration_ms, Some(3_500));
}

#[test]
fn hook_timestamps_win_over_the_fallback() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(
        b"\x1b]7000;v=1;start_ms=500\x07\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n",
        1_000,
    );
    core.feed_at(b"\x1b]7000;v=1;end_ms=2000\x07\x1b]133;D;0\x07", 4_500);
    let blocks = records(&core);
    let block = blocks
        .iter()
        .find(|b| b.state == BlockState::Finished)
        .expect("finished block");
    assert_eq!(block.started_at_ms, Some(500));
    assert_eq!(block.finished_at_ms, Some(2_000));
    assert_eq!(block.duration_ms, Some(1_500));
}

#[test]
fn a_markless_pane_stamps_its_synthetic_block_from_the_first_feed_and_the_boundary() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"banner\r\n", 10_000);
    core.feed_at(b"more\r\n", 12_000);
    let running = records(&core);
    assert_eq!(running.len(), 1);
    assert_eq!(running[0].state, BlockState::Running);
    assert_eq!(running[0].started_at_ms, Some(10_000));
    assert_eq!(running[0].finished_at_ms, None);
    core.feed_at(b"\x1b]7000;v=1;boundary=0\x07next\r\n", 20_000);
    let after = records(&core);
    let closed = after
        .iter()
        .find(|b| b.state == BlockState::Finished)
        .expect("closed synthetic");
    assert_eq!(closed.started_at_ms, Some(10_000));
    assert_eq!(closed.finished_at_ms, Some(20_000));
    let trailing = after
        .iter()
        .find(|b| b.state == BlockState::Running)
        .expect("new trailing block");
    assert_eq!(trailing.started_at_ms, Some(20_000));
}

#[test]
fn a_block_closed_by_the_next_prompt_is_finished_at_that_prompts_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07one\r\n", 1_000);
    core.feed_at(b"\x1b]133;A\x07", 3_000);
    let blocks = records(&core);
    let abandoned = blocks
        .iter()
        .find(|b| b.state == BlockState::Abandoned)
        .expect("abandoned");
    assert_eq!(abandoned.started_at_ms, Some(1_000));
    assert_eq!(abandoned.finished_at_ms, Some(3_000));
}

fn finished(core: &TerminalCore) -> BlockRecord {
    records(core)
        .into_iter()
        .find(|b| b.state == BlockState::Finished)
        .expect("finished block")
}

// warp/app/src/terminal/model/block.rs Block::start and ensure_started_for_preexec,
// warp/app/src/terminal/view.rs block_duration
#[test]
fn a_block_is_timed_from_its_output_start_not_its_prompt() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07$ \x1b]133;B\x07", 1_000);
    core.feed_at(b"\x1b]133;C\x07out\r\n", 16_000);
    core.feed_at(b"\x1b]133;D;0\x07", 20_000);
    let block = finished(&core);
    assert_eq!(block.started_at_ms, Some(16_000));
    assert_eq!(block.finished_at_ms, Some(20_000));
    assert_eq!(block.duration_ms, Some(4_000));
}

#[test]
fn a_hook_start_sent_after_the_prompt_still_wins_over_the_output_start() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07$ \x1b]133;B\x07", 1_000);
    core.feed_at(b"\x1b]7000;v=1;start_ms=15000\x07", 15_500);
    core.feed_at(b"\x1b]133;C\x07out\r\n", 16_000);
    core.feed_at(b"\x1b]133;D;0\x07", 20_000);
    let block = finished(&core);
    assert_eq!(block.started_at_ms, Some(15_000));
    assert_eq!(block.duration_ms, Some(5_000));
}

#[test]
fn a_hook_start_sent_before_the_prompt_still_wins_over_the_output_start() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(
        b"\x1b]7000;v=1;start_ms=500\x07\x1b]133;A\x07$ \x1b]133;B\x07",
        1_000,
    );
    core.feed_at(b"\x1b]133;C\x07out\r\n", 16_000);
    core.feed_at(b"\x1b]133;D;0\x07", 20_000);
    assert_eq!(finished(&core).started_at_ms, Some(500));
}

#[test]
fn a_second_output_start_in_one_block_does_not_restart_its_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07$ \x1b]133;B\x07", 1_000);
    core.feed_at(b"\x1b]133;C\x07one\r\n", 2_000);
    core.feed_at(b"\x1b]133;C\x07two\r\n", 9_000);
    core.feed_at(b"\x1b]133;D;0\x07", 12_000);
    assert_eq!(finished(&core).started_at_ms, Some(2_000));
}

#[test]
fn a_prompt_that_never_ran_a_command_keeps_its_prompt_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07$ \x1b]133;B\x07", 1_000);
    core.feed_at(b"\x1b]133;A\x07", 3_000);
    let blocks = records(&core);
    let abandoned = blocks
        .iter()
        .find(|b| b.state == BlockState::Abandoned)
        .expect("abandoned");
    assert_eq!(abandoned.started_at_ms, Some(1_000));
}
