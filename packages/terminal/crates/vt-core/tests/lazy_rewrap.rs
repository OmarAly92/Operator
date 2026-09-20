use vt_core::TerminalCore;

fn fill(core: &mut TerminalCore, rows: usize) {
    for index in 0..rows {
        core.feed(format!("the quick brown fox jumps over the lazy dog {index:05}\r\n").as_bytes());
    }
}

fn row_text(core: &TerminalCore, index: usize) -> String {
    core.snapshot()
        .expect("snapshot")
        .row_text(index)
        .to_string()
}

#[test]
fn hot_rows_are_rewrapped_eagerly() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    let history = core.history_rows();
    core.resize(20, 24);

    let last = core.history_rows() - 1;
    assert!(
        row_text(&core, last).chars().count() <= 20,
        "the newest row was not rewrapped: {:?}",
        row_text(&core, last)
    );
    assert!(
        core.stale_row_count() > 0,
        "nothing was left cold on a {history}-row session"
    );
}

#[test]
fn cold_rows_are_rewrapped_on_access() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    assert!(core.stale_row_count() > 0);

    core.touch_rows(0..50);
    assert!(
        row_text(&core, 0).chars().count() <= 20,
        "row 0 is still cut at the old width: {:?}",
        row_text(&core, 0)
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn two_width_changes_before_access_rewrap_once() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(30, 24);
    // Rows written between the two changes were hot at 30 columns and are
    // pushed out of the hot region by this fill. They must still be marked.
    fill(&mut core, 3_000);
    core.resize(20, 24);

    let before = core.generation();
    core.touch_rows(0..50);
    let after_first = core.generation();
    core.touch_rows(0..50);
    let after_second = core.generation();

    assert!(after_first > before, "the first access did not rewrap");
    assert_eq!(
        after_second, after_first,
        "the range was rewrapped a second time"
    );
    assert!(row_text(&core, 0).chars().count() <= 20);

    // The band that was hot at 30 columns and cold at 20 must rewrap too.
    let middle = core.history_rows() / 2;
    core.touch_rows(middle..middle + 50);
    assert!(
        row_text(&core, middle).chars().count() <= 20,
        "a row hot at the first width and cold at the second stayed cut at 30: {:?}",
        row_text(&core, middle)
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn stale_runs_follow_a_prepend() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=100000\x1b\\");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    let stale_before = core.stale_row_count();
    assert!(stale_before > 0);

    let first = core.first_stable_row();
    core.feed(format!("\x1b]7000;v=1;history={},2\x1b\\", first - 2).as_bytes());
    core.feed(b"\x1b[0mprepended one\x1b[0m\r\n\x1b[0mprepended two\x1b[0m\r\n");

    assert_eq!(core.first_stable_row(), first - 2);
    assert_eq!(core.stale_row_count(), stale_before);
    assert_eq!(core.verify_integrity(), Ok(()));

    // The prepended rows are not stale; the cold band still is, two rows
    // further down than it was.
    core.touch_rows(0..4);
    assert_eq!(row_text(&core, 0), "prepended one");
    assert!(
        core.stale_row_count() > 0,
        "touching the prepended rows rewrapped the cold band"
    );
}

#[test]
fn blocks_and_pins_follow_lazy_remap() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    core.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=first\x1b\\");
    fill(&mut core, 40);
    core.feed(b"\x1b]133;D;0\x07");
    fill(&mut core, 3_000);
    core.resize(20, 24);

    let stable_before = {
        let snapshot = core.snapshot().expect("snapshot");
        snapshot.first_stable_row + u64::from(snapshot.blocks[0].first_row)
    };
    core.touch_rows(0..80);
    let snapshot = core.snapshot().expect("snapshot");
    let stable_after = snapshot.first_stable_row + u64::from(snapshot.blocks[0].first_row);
    assert_eq!(
        snapshot.block_command(0),
        "first",
        "the block lost its command across the lazy pass"
    );
    assert!(
        stable_after >= stable_before,
        "a block moved backwards across a lazy rewrap: {stable_before} -> {stable_after}"
    );
    let (first, count) = (snapshot.blocks[0].first_row, snapshot.blocks[0].row_count);
    assert!(
        (first as usize) + (count as usize) <= snapshot.row_count(),
        "the block escaped the row space after the lazy pass"
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn a_lazy_pass_reports_the_row_the_export_must_re_read_from() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    let _ = core.take_delta();

    core.touch_rows(0..50);
    let delta = core.take_delta();
    assert_eq!(delta.history_rewritten_from, Some(0));
    assert!(
        delta.remap.as_ref().is_some_and(|pairs| !pairs.is_empty()),
        "a lazy pass produced no remap"
    );
}

fn fill_fixed(core: &mut TerminalCore, rows: usize) {
    for index in 0..rows {
        core.feed(format!("{}{index:05}\r\n", "x".repeat(50)).as_bytes());
    }
}

#[test]
fn a_band_left_hot_by_a_touch_is_re_marked_by_the_next_width_change() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill_fixed(&mut core, 3_000);
    core.resize(30, 24);
    assert!(core.stale_row_count() > 0);

    core.touch_rows(400..450);
    assert!(
        row_text(&core, 400).chars().count() <= 30,
        "the touched band was not rewrapped to 30: {:?}",
        row_text(&core, 400)
    );

    core.resize(15, 24);
    core.touch_rows(400..500);
    assert!(
        row_text(&core, 400).chars().count() <= 15,
        "a band that was hot at 30 and cold at 15 stayed cut at 30: {:?}",
        row_text(&core, 400)
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}
