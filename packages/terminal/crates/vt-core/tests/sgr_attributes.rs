use vt_core::{Attrs, CellStyle, StyleCode, TerminalCore};

fn style_of(bytes: &[u8]) -> CellStyle {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(bytes);
    core.alt_grid().expect("alt").cell(0, 0).style
}

fn attrs_of(bytes: &[u8]) -> Attrs {
    style_of(bytes).attrs
}

#[test]
fn italic_strike_blink_hidden_overline_set_and_reset() {
    assert!(attrs_of(b"\x1b[3mA").contains(Attrs::ITALIC));
    assert!(!attrs_of(b"\x1b[3m\x1b[23mA").contains(Attrs::ITALIC));
    assert!(attrs_of(b"\x1b[9mA").contains(Attrs::STRIKE));
    assert!(!attrs_of(b"\x1b[9m\x1b[29mA").contains(Attrs::STRIKE));
    assert!(attrs_of(b"\x1b[5mA").contains(Attrs::BLINK));
    assert!(attrs_of(b"\x1b[6mA").contains(Attrs::BLINK));
    assert!(!attrs_of(b"\x1b[5m\x1b[25mA").contains(Attrs::BLINK));
    assert!(attrs_of(b"\x1b[8mA").contains(Attrs::HIDDEN));
    assert!(!attrs_of(b"\x1b[8m\x1b[28mA").contains(Attrs::HIDDEN));
    assert!(attrs_of(b"\x1b[53mA").contains(Attrs::OVERLINE));
    assert!(!attrs_of(b"\x1b[53m\x1b[55mA").contains(Attrs::OVERLINE));
}

#[test]
fn every_underline_style_is_exclusive_and_24_clears_all_of_them() {
    assert_eq!(attrs_of(b"\x1b[4mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:2mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[21mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3mA").bits(), Attrs::CURLY_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:4mA").bits(), Attrs::DOTTED_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:5mA").bits(), Attrs::DASHED_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3m\x1b[4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4;4:2mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:2;4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3m\x1b[24mA").bits(), 0);
    assert_eq!(attrs_of(b"\x1b[4m\x1b[4:0mA").bits(), 0);
    assert_eq!(attrs_of(b"\x1b[4:9mA").bits(), 0);
}

#[test]
fn an_underline_colour_is_read_in_both_spellings_and_59_restores_the_default() {
    assert_eq!(
        style_of(b"\x1b[58;2;255;0;255mA").underline,
        StyleCode::rgb(255, 0, 255)
    );
    assert_eq!(
        style_of(b"\x1b[58:5:196mA").underline,
        StyleCode::indexed(196)
    );
    assert_eq!(
        style_of(b"\x1b[58;5;196;4mA").attrs.bits(),
        Attrs::UNDERLINE
    );
    assert_eq!(
        style_of(b"\x1b[58;5;196m\x1b[59mA").underline,
        StyleCode::DEFAULT
    );
    assert_eq!(style_of(b"\x1b[58;5;196mA").fg, StyleCode::DEFAULT);
}

#[test]
fn sgr_0_clears_attributes_and_the_underline_colour_with_the_colours() {
    let style = style_of(b"\x1b[3;4:3;9;5;8;53;58;5;196;31;42m\x1b[0mA");
    assert_eq!(style, CellStyle::DEFAULT);
    assert!(style.attrs.is_empty());
}

#[test]
fn attributes_survive_reverse_resolution_and_a_colour_change() {
    let style = style_of(b"\x1b[7;3;4m\x1b[38;5;196mA");
    assert!(style.attrs.contains(Attrs::ITALIC));
    assert!(style.attrs.contains(Attrs::UNDERLINE));
    assert!(!style.fg.is_reverse());
    assert_eq!(style.bg, StyleCode::indexed(196));
}

#[test]
fn attributes_survive_the_trip_into_scrollback() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 2);
    core.feed(b"\x1b[3;4:3;58;2;1;2;3mabc\x1b[0m\r\nsecond\r\nthird\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    let row = (0..snapshot.row_count())
        .find(|index| snapshot.row_text(*index) == "abc")
        .expect("the styled row was committed");
    let (end, style) = snapshot.row_style_pairs(row)[0];
    assert_eq!(end, 3);
    assert!(style.attrs.contains(Attrs::ITALIC));
    assert!(style.attrs.contains(Attrs::CURLY_UNDERLINE));
    assert_eq!(style.underline, StyleCode::rgb(1, 2, 3));
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn attributes_round_trip_through_a_history_chunk() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b[9;4:2;58:5:196mold\x1b[0m\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "old");
    let style = snapshot.row_style_pairs(0)[0].1;
    assert!(style.attrs.contains(Attrs::STRIKE));
    assert!(style.attrs.contains(Attrs::DOUBLE_UNDERLINE));
    assert_eq!(style.underline, StyleCode::indexed(196));
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn an_underlined_trailing_blank_is_still_trimmed_from_the_export() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"ab\x1b[4m  \x1b[0m");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab");
}

#[test]
fn a_private_m_sequence_is_not_sgr() {
    for bytes in [
        &b"\x1b[>4mA"[..],
        b"\x1b[?4mA",
        b"\x1b[>4;2mA",
        b"\x1b[>0m\x1b[38;2;1;2;3mA",
    ] {
        let style = style_of(bytes);
        assert!(
            style.attrs.is_empty(),
            "{:?} set {:?}",
            String::from_utf8_lossy(bytes),
            style.attrs
        );
        assert_eq!(style.underline, StyleCode::DEFAULT);
    }
    assert_eq!(
        style_of(b"\x1b[>0m\x1b[38;2;1;2;3mA").fg,
        StyleCode::rgb(1, 2, 3)
    );
}

#[test]
fn a_private_m_sequence_in_a_history_chunk_is_not_sgr_either() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b[>4mold\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "old");
    assert!(snapshot.row_style_pairs(0)[0].1.attrs.is_empty());
}

#[test]
fn the_claude_code_recording_carries_no_attribute_bits() {
    let dir = std::path::Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/ref/claude_spinner_10s"
    ));
    let recording = std::fs::read(dir.join("recording")).expect("recording");
    let mut core = TerminalCore::new(120, 10_000).expect("core");
    core.resize(120, 40);
    core.set_agent_tui_mode(true);
    core.feed(&recording);
    let snapshot = core.snapshot().expect("snapshot");
    for row in 0..snapshot.row_count() {
        for (end, style) in snapshot.row_style_pairs(row) {
            assert!(
                style.attrs.is_empty() && style.underline == StyleCode::DEFAULT,
                "row {row} run ending at {end} carries {:?}: XTMODKEYS (CSI > 4;2 m) must not reach the SGR path",
                style.attrs
            );
        }
    }
}
