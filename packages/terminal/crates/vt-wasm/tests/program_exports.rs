use vt_core::program::ProgramNotification;
use vt_wasm::flatten_notifications;
use vt_wasm::WasmTerminalCore;

#[test]
fn notifications_flatten_to_title_body_pairs_in_order() {
    let flat = flatten_notifications(vec![
        ProgramNotification {
            title: "Build".to_string(),
            body: "done".to_string(),
        },
        ProgramNotification {
            title: String::new(),
            body: "second".to_string(),
        },
    ]);
    assert_eq!(flat, vec!["Build", "done", "", "second"]);
}

#[test]
fn the_wasm_core_exposes_title_pointer_and_notifications() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    let start = core.program_generation();
    assert!(core
        .feed(
            b"\x1b]0;\xe2\x97\x90 Working\x07\x1b]22;pointer\x07\x1b]9;hi\x07",
            0.0
        )
        .is_ok());
    assert_eq!(core.title(), "\u{25d0} Working");
    assert_eq!(core.pointer_shape(), "pointer");
    assert_eq!(core.take_notifications(), vec!["", "hi"]);
    assert!(core.take_notifications().is_empty());
    assert_eq!(core.program_generation().wrapping_sub(start), 3);
}
