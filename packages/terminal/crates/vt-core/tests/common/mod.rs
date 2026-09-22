use vt_core::TerminalCore;

pub fn check(core: &TerminalCore) {
    if let Err(error) = core.verify_integrity() {
        panic!("integrity violated: {error:?}");
    }
    let snapshot = core.snapshot().expect("snapshot builds");
    assert_eq!(
        snapshot.row_wrapped.len(),
        snapshot.row_count(),
        "one wrapped flag per row"
    );
    for row in 0..snapshot.row_count() {
        let len = snapshot.row_text(row).len() as u32;
        let mut previous_end = 0u32;
        for span in snapshot.row_cell_spans(row) {
            assert!(
                span.start >= previous_end && span.start < span.end && span.end <= len,
                "row {row} span {span:?} outside {len} bytes or out of order"
            );
            assert!(span.width <= 2, "row {row} span {span:?} width");
            previous_end = span.end;
        }
    }
}
