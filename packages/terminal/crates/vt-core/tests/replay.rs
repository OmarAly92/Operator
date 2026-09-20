use vt_core::TerminalCore;

fn rows_of(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|index| snapshot.row_text(index).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn attach(core: &mut TerminalCore, origin: u64, frame: &str) {
    core.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    core.feed(frame.as_bytes());
}

#[test]
fn an_origin_mark_adopts_the_replaying_hosts_row_space() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    assert_eq!(core.first_stable_row(), 0);
    attach(&mut core, 1000, "live\r\n");
    assert_eq!(core.first_stable_row(), 1000);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn an_origin_mark_after_rows_exist_is_ignored() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"live\r\n");
    core.feed(b"\x1b]7000;v=1;origin=9999\x1b\\");
    assert_eq!(core.first_stable_row(), 0);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn replay_prepends_history_without_moving_the_frame() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live one\r\nlive two\r\n");
    let before = rows_of(&core);
    assert_eq!(core.first_stable_row(), 1000);

    core.feed(b"\x1b]7000;v=1;history=");
    core.feed(b"998,2\x1b\\");
    core.feed(b"older one\r\nolder two\r\n");

    assert_eq!(core.first_stable_row(), 998);
    let after = rows_of(&core);
    assert_eq!(
        &after[..2],
        &["older one".to_string(), "older two".to_string()]
    );
    assert_eq!(&after[2..], &before[..]);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn a_history_chunk_that_does_not_abut_the_front_is_ignored() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");
    let before = rows_of(&core);

    core.feed(b"\x1b]7000;v=1;history=1050,2\x1b\\");
    core.feed(b"bogus one\r\nbogus two\r\n");

    assert_eq!(core.first_stable_row(), 1000);
    assert_eq!(rows_of(&core), before);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn two_history_chunks_prepend_oldest_last() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");

    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"middle\r\n");
    core.feed(b"\x1b]7000;v=1;history=998,1\x1b\\");
    core.feed(b"oldest\r\n");

    assert_eq!(
        rows_of(&core),
        vec![
            "oldest".to_string(),
            "middle".to_string(),
            "live".to_string()
        ]
    );
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(core.verify_integrity(), Ok(()));
}
