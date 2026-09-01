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
    assert_eq!(buffers.style_pairs(), &[3, 1, 6, 255, 5, 255]);
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
