mod common;

use vt_core::{Limits, TerminalCore, OLDER_CHUNK_ROWS};

fn source() -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 10,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.set_reflow_on_resize(false);
    core.resize(40, 3);
    core.set_cold_ring_bytes(1 << 20);
    for index in 0..40 {
        core.feed(format!("old {index:05}\r\n").as_bytes());
    }
    core
}

fn pane(origin: u64) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 10_000,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(40, 3);
    core.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\live\r\n").as_bytes());
    core
}

fn texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    (0..snapshot.row_count())
        .map(|index| snapshot.row_text(index).to_string())
        .collect()
}

fn landed_whole(prefix: &[u8], suffix: &[u8], byte_by_byte: bool) {
    let source = source();
    let origin = source.first_stable_row();
    let chunk = source
        .older_chunk(origin, OLDER_CHUNK_ROWS, 1 << 20)
        .expect("older rows");
    let mut stream = prefix.to_vec();
    stream.extend_from_slice(&chunk.bytes);
    stream.extend_from_slice(&source.older_mark().expect("ring is on"));
    stream.extend_from_slice(suffix);

    let mut target = pane(origin);
    if byte_by_byte {
        for byte in &stream {
            target.feed(std::slice::from_ref(byte));
        }
    } else {
        target.feed(&stream);
    }
    let mut reference = pane(origin);
    reference.feed(prefix);
    reference.feed(suffix);

    let label = format!(
        "{:?} + answer + {:?}",
        String::from_utf8_lossy(prefix),
        String::from_utf8_lossy(suffix)
    );
    assert_eq!(target.first_stable_row(), chunk.first_stable_row, "{label}");
    let got = texts(&target);
    let want = texts(&reference);
    assert_eq!(&got[chunk.rows..], &want[..], "{label}");
    let target_snapshot = target.snapshot().expect("snapshot");
    let reference_snapshot = reference.snapshot().expect("snapshot");
    for row in 0..want.len() {
        assert_eq!(
            target_snapshot.row_style_pairs(chunk.rows + row),
            reference_snapshot.row_style_pairs(row),
            "{label} row {row}"
        );
    }
    common::check(&target);
}

#[test]
fn an_answer_inside_a_csi_leaves_the_sequence_whole() {
    landed_whole(b"\x1b[3", b"1mRED\r\n", false);
}

#[test]
fn an_answer_right_after_csi_introducer_leaves_the_sequence_whole() {
    landed_whole(b"\x1b[", b"31mRED\r\n", false);
}

#[test]
fn an_answer_inside_a_private_mode_leaves_the_sequence_whole() {
    landed_whole(b"\x1b[?10", b"49h\x1b[?1049lafter\r\n", false);
}

#[test]
fn an_answer_right_after_a_bare_escape_leaves_the_sequence_whole() {
    landed_whole(b"\x1b", b"[32mGREEN\r\n", false);
}

#[test]
fn an_answer_inside_a_utf8_character_leaves_the_character_whole() {
    landed_whole(b"caf\xc3", b"\xa9\r\n", false);
}

#[test]
fn an_answer_split_across_feeds_still_lands_whole() {
    landed_whole(b"\x1b[3", b"1mRED\r\n", true);
    landed_whole(b"caf\xc3", b"\xa9\r\n", true);
}

#[test]
fn an_attach_history_chunk_inside_a_csi_leaves_the_sequence_whole() {
    let mut target = pane(500);
    target.feed(b"\x1b[3\x1b]7000;v=1;history=498,2\x1b\\one\r\ntwo\r\n1mRED\r\n");
    let mut reference = pane(500);
    reference.feed(b"\x1b[31mRED\r\n");
    assert_eq!(target.first_stable_row(), 498);
    let got = texts(&target);
    assert_eq!(&got[..2], ["one", "two"]);
    assert_eq!(&got[2..], &texts(&reference)[..]);
    common::check(&target);
}
