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
        command: TextSpan::default(),
        cwd: TextSpan::default(),
        git_branch: TextSpan::default(),
        bookmarked: false,
    }
}

fn encode(exit: Option<i32>) -> Vec<u32> {
    let snapshot = vt_core::GridSnapshot {
        content: Vec::new(),
        rows: Vec::new(),
        run_ranges: Vec::new(),
        style_pairs: Vec::new(),
        blocks: vec![record(exit)],
        block_text: Vec::new(),
        line_editor_state: 0,
        cursor_row: 0,
        cursor_col: 0,
        cursor_visible: true,
        alt: None,
    };
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&snapshot).unwrap();
    buffers.blocks().to_vec()
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
