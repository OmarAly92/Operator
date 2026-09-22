use std::path::PathBuf;

use proptest::prelude::*;
use vt_core::{Limits, TerminalCore};
use vt_wasm::{ExportBuffers, STYLE_RUN_WORDS};

fn sync(buffers: &mut ExportBuffers, core: &mut TerminalCore) {
    let delta = core.take_delta();
    buffers.apply(core, &delta).unwrap();
}

fn full_export(core: &TerminalCore) -> ExportBuffers {
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();
    buffers
}

fn projected_rows(buffers: &ExportBuffers) -> Vec<(Vec<u8>, u16, Vec<u32>)> {
    let rows = buffers.rows();
    let indents = buffers.row_indents();
    let runs = buffers.run_ranges();
    let pairs = buffers.style_pairs();
    let content = buffers.content();
    (0..rows.len() / 2)
        .map(|row| {
            let (start, end) = (rows[row * 2] as usize, rows[row * 2 + 1] as usize);
            let (pair_start, pair_end) = (runs[row * 2] as usize, runs[row * 2 + 1] as usize);
            (
                content[start..end].to_vec(),
                indents[row],
                pairs[pair_start * STYLE_RUN_WORDS..pair_end * STYLE_RUN_WORDS].to_vec(),
            )
        })
        .collect()
}

fn assert_projection_equal(incremental: &ExportBuffers, full: &ExportBuffers) {
    assert_eq!(projected_rows(incremental), projected_rows(full));
    assert_eq!(incremental.blocks(), full.blocks());
    assert_eq!(incremental.block_text(), full.block_text());
    assert_eq!(incremental.cursor_row(), full.cursor_row());
    assert_eq!(incremental.cursor_col(), full.cursor_col());
    assert_eq!(incremental.cursor_visible(), full.cursor_visible());
    assert_eq!(incremental.line_editor_state(), full.line_editor_state());
    assert_eq!(incremental.first_stable_row(), full.first_stable_row());
    assert_eq!(incremental.alt_active(), full.alt_active());
    assert_eq!(incremental.alt_content(), full.alt_content());
    assert_eq!(incremental.alt_row_ranges(), full.alt_row_ranges());
    assert_eq!(incremental.alt_run_ranges(), full.alt_run_ranges());
    assert_eq!(incremental.alt_style_pairs(), full.alt_style_pairs());
    assert_eq!(incremental.alt_span_ranges(), full.alt_span_ranges());
    assert_eq!(incremental.alt_cell_spans(), full.alt_cell_spans());
}

fn assert_bytes_equal(incremental: &ExportBuffers, full: &ExportBuffers) {
    assert_eq!(incremental.content(), full.content());
    assert_eq!(incremental.rows(), full.rows());
    assert_eq!(incremental.row_indents(), full.row_indents());
    assert_eq!(incremental.run_ranges(), full.run_ranges());
    assert_eq!(incremental.style_pairs(), full.style_pairs());
    assert_eq!(incremental.span_ranges(), full.span_ranges());
    assert_eq!(incremental.cell_spans(), full.cell_spans());
    assert_projection_equal(incremental, full);
}

#[derive(Clone, Debug)]
enum Op {
    Bytes(Vec<u8>),
    Resize(usize, usize),
}

fn op() -> impl Strategy<Value = Op> {
    prop_oneof![
        8 => proptest::collection::vec(any::<u8>(), 1..64).prop_map(Op::Bytes),
        6 => "[a-z ]{1,40}(\r\n)?".prop_map(|text| Op::Bytes(text.into_bytes())),
        3 => (1u16..=6, 1u16..=40).prop_map(|(n, m)| Op::Bytes(format!("\x1b[{n};{m}H").into_bytes())),
        2 => (0u8..=2).prop_map(|mode| Op::Bytes(format!("\x1b[{mode}J").into_bytes())),
        2 => (0u8..=2).prop_map(|mode| Op::Bytes(format!("\x1b[{mode}K").into_bytes())),
        3 => (30u8..=37).prop_map(|colour| Op::Bytes(format!("\x1b[{colour}mst\x1b[0m").into_bytes())),
        2 => (0u8..=5).prop_map(|k| Op::Bytes(format!("\x1b[3;4:{k};9;58;5;196mat\x1b[0m").into_bytes())),
        1 => Just(Op::Bytes(b"\x1b]133;A\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]133;C\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]133;D;0\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]7000;v=1;boundary=0\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b[?1049h".to_vec())),
        1 => Just(Op::Bytes(b"\x1b[?1049l".to_vec())),
        2 => Just(Op::Bytes("w\u{6f22}e\u{301}\r\n".as_bytes().to_vec())),
        2 => (10usize..=60, 2usize..=8).prop_map(|(cols, rows)| Op::Resize(cols, rows)),
    ]
}

fn run(ops: &[Op], limits: Limits, syncs_every: usize) {
    let mut core = TerminalCore::with_limits(40, limits).unwrap();
    core.resize(40, 4);
    let mut incremental = ExportBuffers::default();
    sync(&mut incremental, &mut core);
    for (index, op) in ops.iter().enumerate() {
        match op {
            Op::Bytes(bytes) => core.feed(bytes),
            Op::Resize(cols, rows) => core.resize(*cols, *rows),
        }
        if index % syncs_every == 0 {
            sync(&mut incremental, &mut core);
            assert_projection_equal(&incremental, &full_export(&core));
        }
    }
    sync(&mut incremental, &mut core);
    let full = full_export(&core);
    assert_projection_equal(&incremental, &full);
    incremental.compact();
    assert_bytes_equal(&incremental, &full);
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn incremental_export_equals_full_rebuild(
        ops in proptest::collection::vec(op(), 1..120),
        rows_cap in 5usize..40,
        bytes_cap in prop_oneof![Just(usize::MAX), Just(600usize), Just(4_096usize)],
        syncs_every in 1usize..5,
    ) {
        run(&ops, Limits { rows: rows_cap, bytes: bytes_cap }, syncs_every);
    }
}

#[test]
fn incremental_export_equals_full_rebuild_over_the_ref_corpus() {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../vt-core/tests/ref");
    for name in ["claude_spinner_10s", "zsh_tab_completion", "vttest_insert"] {
        let recording = std::fs::read(corpus.join(name).join("recording")).expect("recording");
        for chunk in [1usize, 7, 64, 4096] {
            let mut core = TerminalCore::with_limits(
                120,
                Limits {
                    rows: 200,
                    bytes: usize::MAX,
                },
            )
            .unwrap();
            core.resize(120, 40);
            let mut incremental = ExportBuffers::default();
            sync(&mut incremental, &mut core);
            for piece in recording.chunks(chunk) {
                core.feed(piece);
                sync(&mut incremental, &mut core);
                assert_projection_equal(&incremental, &full_export(&core));
            }
            incremental.compact();
            assert_bytes_equal(&incremental, &full_export(&core));
        }
    }
}

#[test]
fn compaction_preserves_offsets() {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(12)).unwrap();
    core.resize(20, 2);
    let mut incremental = ExportBuffers::default();
    sync(&mut incremental, &mut core);
    for i in 0..40 {
        core.feed(format!("\x1b[3{}mrow {i:02}\x1b[0m tail\r\n", i % 8).as_bytes());
        sync(&mut incremental, &mut core);
        let full = full_export(&core);
        assert_projection_equal(&incremental, &full);
        let live_rows = incremental.rows().len() / 2;
        assert!(
            incremental.dead_rows() * vt_wasm::COMPACTION_DIVISOR <= live_rows.max(1),
            "dead prefix is bounded: {} dead, {live_rows} live",
            incremental.dead_rows()
        );
    }
    incremental.compact();
    assert_eq!(incremental.dead_rows(), 0);
    assert_bytes_equal(&incremental, &full_export(&core));
}
