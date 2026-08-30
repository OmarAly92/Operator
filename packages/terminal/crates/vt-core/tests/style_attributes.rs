use vt_core::{StyleCode, TerminalCore};

fn style_of(bytes: &[u8]) -> StyleCode {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(bytes);
    core.alt_grid().expect("alt").cell(0, 0).style
}

#[test]
fn dim_is_recorded_and_does_not_disturb_the_colour() {
    let style = style_of(b"\x1b[2mA");
    assert!(style.is_dim());
    assert!(!style.is_bold());
    assert_eq!(style.colour(), StyleCode::DEFAULT);
}

#[test]
fn bold_is_recorded_alongside_a_colour() {
    let style = style_of(b"\x1b[1m\x1b[31mA");
    assert!(style.is_bold());
    assert_eq!(style.colour(), StyleCode::ansi(1));
}

#[test]
fn an_attribute_survives_a_later_colour_change() {
    let style = style_of(b"\x1b[2m\x1b[38;2;1;2;3mA");
    assert!(style.is_dim());
    assert_eq!(style.colour(), StyleCode::rgb(1, 2, 3));
}

#[test]
fn a_colour_survives_a_later_attribute_change() {
    let style = style_of(b"\x1b[38;5;196m\x1b[1mA");
    assert!(style.is_bold());
    assert_eq!(style.colour(), StyleCode::indexed(196));
}

#[test]
fn sgr_22_clears_bold_and_dim_but_keeps_the_colour() {
    let style = style_of(b"\x1b[1m\x1b[2m\x1b[31m\x1b[22mA");
    assert!(!style.is_bold());
    assert!(!style.is_dim());
    assert_eq!(style.colour(), StyleCode::ansi(1));
}

#[test]
fn a_reset_clears_attributes_and_colour_together() {
    let style = style_of(b"\x1b[1m\x1b[2m\x1b[31m\x1b[0mA");
    assert_eq!(style, StyleCode::DEFAULT);
}

#[test]
fn the_agent_cli_separator_run_is_dim_default_foreground() {
    let style = style_of(b"\x1b[2m\xe2\x94\x80");
    assert!(style.is_dim());
    assert_eq!(style.colour(), StyleCode::DEFAULT);
}
