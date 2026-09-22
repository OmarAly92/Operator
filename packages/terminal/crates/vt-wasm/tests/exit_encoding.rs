use vt_core::{BlockRecord, BlockSource, BlockState, TextSpan};
use vt_wasm::ExportBuffers;

fn record(exit: Option<i32>) -> BlockRecord {
    BlockRecord {
        id: 1,
        first_row: 0,
        row_count: 1,
        state: BlockState::Finished,
        source: BlockSource::Osc133,
        exit_code: exit,
        duration_ms: None,
        started_at_ms: None,
        finished_at_ms: None,
        command: TextSpan::default(),
        cwd: TextSpan::default(),
        git_branch: TextSpan::default(),
        bookmarked: false,
    }
}

fn record_at(started: Option<u64>, finished: Option<u64>) -> BlockRecord {
    BlockRecord {
        started_at_ms: started,
        finished_at_ms: finished,
        ..record(None)
    }
}

fn empty_snapshot() -> vt_core::GridSnapshot {
    vt_core::GridSnapshot {
        content: Vec::new(),
        rows: Vec::new(),
        row_indents: Vec::new(),
        row_wrapped: Vec::new(),
        run_ranges: Vec::new(),
        style_pairs: Vec::new(),
        span_ranges: Vec::new(),
        cell_spans: Vec::new(),
        blocks: Vec::new(),
        block_text: Vec::new(),
        line_editor_state: 0,
        cursor_row: 0,
        cursor_col: 0,
        cursor_visible: true,
        history_rows: 0,
        first_stable_row: 0,
        alt: None,
        link_text: Vec::new(),
        link_ranges: Vec::new(),
    }
}

fn encode_record(record: BlockRecord) -> Vec<u32> {
    let snapshot = vt_core::GridSnapshot {
        blocks: vec![record],
        ..empty_snapshot()
    };
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&snapshot).unwrap();
    buffers.blocks().to_vec()
}

fn encode(exit: Option<i32>) -> Vec<u32> {
    encode_record(record(exit))
}

#[test]
fn negative_one_must_not_decode_as_absent() {
    assert_ne!(
        encode(Some(-1))[5],
        encode(None)[5],
        "Some(-1) collides with None"
    );
}

#[test]
fn a_hostile_exit_parameter_must_not_panic() {
    let _ = encode(Some(i32::MAX));
}

#[test]
fn timestamps_take_words_fourteen_to_seventeen_with_max_pairs_for_none() {
    let words = encode_record(record_at(Some(0x1_0000_0002), None));
    assert_eq!(words.len(), vt_wasm::BLOCK_RECORD_WORDS);
    assert_eq!(&words[14..18], &[2, 1, u32::MAX, u32::MAX]);
    let none = encode_record(record_at(None, Some(7)));
    assert_eq!(&none[14..18], &[u32::MAX, u32::MAX, 7, 0]);
}
