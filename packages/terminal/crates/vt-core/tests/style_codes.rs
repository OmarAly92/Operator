use vt_core::{StyleCode, TerminalCore};

fn alt_cell_style(bytes: &[u8]) -> StyleCode {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(bytes);
    core.alt_grid().expect("alt").cell(0, 0).style
}

#[test]
fn the_sixteen_ansi_colours_keep_their_existing_codes() {
    assert_eq!(alt_cell_style(b"\x1b[31mA"), StyleCode::ansi(1));
    assert_eq!(alt_cell_style(b"\x1b[97mA"), StyleCode::ansi(15));
    assert_eq!(alt_cell_style(b"\x1b[39mA"), StyleCode::DEFAULT);
    assert_eq!(StyleCode::DEFAULT.value(), 255);
}

#[test]
fn a_256_colour_index_survives_instead_of_falling_back_to_default() {
    let style = alt_cell_style(b"\x1b[38;5;196mA");
    assert_ne!(style, StyleCode::DEFAULT);
    assert_eq!(style, StyleCode::indexed(196));
}

#[test]
fn a_256_index_inside_the_ansi_range_maps_onto_the_themed_ansi_slot() {
    assert_eq!(alt_cell_style(b"\x1b[38;5;9mA"), StyleCode::ansi(9));
}

#[test]
fn truecolour_survives_and_carries_all_three_channels() {
    let style = alt_cell_style(b"\x1b[38;2;205;214;244mA");
    assert_ne!(style, StyleCode::DEFAULT);
    assert_eq!(style, StyleCode::rgb(205, 214, 244));
    assert_ne!(StyleCode::rgb(205, 214, 244), StyleCode::rgb(205, 214, 245));
}

#[test]
fn the_colon_form_is_read_the_same_as_the_semicolon_form() {
    assert_eq!(alt_cell_style(b"\x1b[38:5:196mA"), StyleCode::indexed(196));
    assert_eq!(
        alt_cell_style(b"\x1b[38:2::205:214:244mA"),
        StyleCode::rgb(205, 214, 244)
    );
}

#[test]
fn a_background_or_underline_colour_does_not_repaint_the_foreground() {
    assert_eq!(
        alt_cell_style(b"\x1b[31m\x1b[48;5;31mA"),
        StyleCode::ansi(1)
    );
    assert_eq!(
        alt_cell_style(b"\x1b[31m\x1b[58;2;1;2;3mA"),
        StyleCode::ansi(1)
    );
}

#[test]
fn a_truncated_extended_colour_does_not_hang_or_repaint() {
    assert_eq!(alt_cell_style(b"\x1b[38mA"), StyleCode::DEFAULT);
    assert_eq!(alt_cell_style(b"\x1b[38;5mA"), StyleCode::DEFAULT);
}

#[test]
fn a_reset_clears_an_extended_colour() {
    assert_eq!(
        alt_cell_style(b"\x1b[38;2;1;2;3m\x1b[0mA"),
        StyleCode::DEFAULT
    );
}

#[test]
fn the_recorded_agent_cli_colours_all_survive() {
    assert_eq!(
        alt_cell_style(b"\x1b[38;2;167;167;167mA"),
        StyleCode::rgb(167, 167, 167)
    );
    assert_eq!(alt_cell_style(b"\x1b[38;5;244mA"), StyleCode::indexed(244));
    assert_eq!(alt_cell_style(b"\x1b[38;5;174mA"), StyleCode::indexed(174));
}
