use super::*;
use vte::Parser as VteParser;

#[test]
fn mouse_tracking_level_distinguishes_the_three_modes() {
    let mut p = Parser::new(80);
    let mut vte = VteParser::new();
    assert_eq!(p.mouse_tracking_level(), 0);
    vte.advance(&mut p, b"\x1b[?1000h");
    assert_eq!(p.mouse_tracking_level(), 0b001);
    vte.advance(&mut p, b"\x1b[?1002h");
    assert_eq!(p.mouse_tracking_level(), 0b011);
    vte.advance(&mut p, b"\x1b[?1003h");
    assert_eq!(p.mouse_tracking_level(), 0b111);
    vte.advance(&mut p, b"\x1b[?1002l");
    assert_eq!(p.mouse_tracking_level(), 0b101);
    assert!(p.mouse_tracking());
    vte.advance(&mut p, b"\x1b[?1000l");
    vte.advance(&mut p, b"\x1b[?1003l");
    assert_eq!(p.mouse_tracking_level(), 0);
    assert!(!p.mouse_tracking());
}

#[test]
fn focus_reporting_mode_is_tracked() {
    let mut p = Parser::new(80);
    let mut vte = VteParser::new();
    assert!(!p.focus_reporting());
    vte.advance(&mut p, b"\x1b[?1004h");
    assert!(p.focus_reporting());
    vte.advance(&mut p, b"\x1b[?1004l");
    assert!(!p.focus_reporting());
}

#[test]
fn apply_history_chunk_prepends_rows_below_the_adopted_origin() {
    let mut p = Parser::new(20);
    assert!(p.adopt_origin(2));
    let rows = vec![
        HistoryRow {
            bytes: b"a\r\n".to_vec(),
            wrapped: false,
            indent: 0,
            styles: Vec::new(),
        },
        HistoryRow {
            bytes: b"b\r\n".to_vec(),
            wrapped: false,
            indent: 0,
            styles: Vec::new(),
        },
    ];
    assert!(p.apply_history_chunk(0, rows, Vec::new()));
    assert_eq!(p.trimmed_total(), 0);
    assert_eq!(p.rows().completed().len(), 2);
}
