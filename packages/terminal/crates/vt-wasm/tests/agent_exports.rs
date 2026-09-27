use vt_wasm::{detects_high_confidence_input_pattern, WasmTerminalCore};

#[test]
fn the_wasm_core_reports_a_question_at_the_cursor() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    assert!(core.resize(80, 24).is_ok());
    assert!(core.feed(b"Overwrite greet.py? (y/n) ", 0.0).is_ok());
    assert!(core.cursor_line_prompts());
    assert!(detects_high_confidence_input_pattern("Continue? [Y/n] "));
    assert!(!detects_high_confidence_input_pattern("❯ "));
}
