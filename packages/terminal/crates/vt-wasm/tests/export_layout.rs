use vt_core::TerminalCore;
use vt_wasm::ExportBuffers;

#[test]
fn flattens_rows_and_runs_as_u32_pairs() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m ok\r\nplain");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.content(), b"red okplain");
    assert_eq!(buffers.rows(), &[0, 6, 6, 11]);
    assert_eq!(buffers.run_ranges(), &[0, 2, 2, 3]);
    assert_eq!(
        buffers.style_pairs(),
        &[3, 1, 254, 0, 255, 6, 255, 254, 0, 255, 5, 255, 254, 0, 255]
    );
}

#[test]
fn exports_cell_spans_beside_the_rows_as_start_end_width_triples() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed("ab\u{6f22}c\r\ne\u{301}".as_bytes());
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.span_ranges(), &[0, 1, 1, 2]);
    assert_eq!(buffers.cell_spans(), &[2, 5, 2, 0, 3, 1]);
}

#[test]
fn offset_overflow_when_u64_exceeds_u32_max() {
    assert_eq!(
        vt_wasm::checked_u32_from_u64(u32::MAX as u64 + 1),
        Err(vt_wasm::ExportError::OffsetOverflow)
    );
    assert_eq!(vt_wasm::checked_u32_from_u64(u32::MAX as u64), Ok(u32::MAX));
    assert_eq!(vt_wasm::checked_u32_from_u64(0), Ok(0));
}

#[test]
fn refresh_clears_previous_buffers() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed(b"first row\r\nsecond");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();
    let first_content = buffers.content().to_vec();
    let first_rows = buffers.rows().to_vec();

    core.feed(b"\r\nshort");
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_ne!(first_content.len(), buffers.content().len());
    assert_ne!(first_rows, buffers.rows());
}

#[test]
fn memory_stats_are_exported_as_four_words() {
    let mut core = TerminalCore::with_limits(
        16,
        vt_core::Limits {
            rows: 10,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    core.resize(16, 1);
    core.feed(b"\x1b[31mred\x1b[0m ok\r\nplain\r\n");
    let stats = core.memory_stats();
    let words = vt_wasm::memory_stats_words(&stats);
    assert_eq!(
        words,
        [
            stats.content_bytes as u32,
            stats.style_entries as u32,
            stats.rows as u32,
            stats.blocks as u32
        ]
    );
    assert_eq!(words[2], 2);
}

#[test]
fn apply_matches_refresh_for_a_partial_delta() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.resize(16, 2);
    let mut incremental = ExportBuffers::default();
    let initial = core.take_delta();
    incremental.apply(&core, &initial).unwrap();
    core.feed(b"first row\r\nsecond\r\n");
    let delta = core.take_delta();
    assert_eq!(delta.kind, vt_core::DeltaKind::Partial);
    incremental.apply(&core, &delta).unwrap();
    let mut full = ExportBuffers::default();
    full.refresh(&core.snapshot().unwrap()).unwrap();
    assert_eq!(incremental.content(), full.content());
    assert_eq!(incremental.rows(), full.rows());
    assert_eq!(incremental.run_ranges(), full.run_ranges());
    assert_eq!(incremental.style_pairs(), full.style_pairs());
    assert_eq!(incremental.blocks(), full.blocks());
}

#[test]
fn exports_one_wrapped_byte_per_row() {
    let mut core = TerminalCore::new(4, 10).unwrap();
    core.feed(b"abc def\r\nx");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.row_wrapped().len(), buffers.rows().len() / 2);
    assert_eq!(&buffers.row_wrapped()[..3], &[1, 0, 0]);
}
