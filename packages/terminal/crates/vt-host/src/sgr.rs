use vt_core::{Attrs, CellStyle, StyleCode};

pub(crate) fn write_styled_row<'a>(
    text: &mut String,
    row_bytes: &[u8],
    pairs: &[(u32, CellStyle)],
    link_uri: &dyn Fn(u16) -> Option<&'a str>,
) {
    write_styled_row_with(text, row_bytes, pairs, link_uri, "\n");
}

pub(crate) fn write_styled_row_with<'a>(
    text: &mut String,
    row_bytes: &[u8],
    pairs: &[(u32, CellStyle)],
    link_uri: &dyn Fn(u16) -> Option<&'a str>,
    terminator: &str,
) {
    let mut start = 0usize;
    for (end, style) in pairs {
        let end = *end as usize;
        text.push_str("\x1b[0m");
        if let Some(params) = style_sgr_params(*style) {
            text.push_str("\x1b[");
            text.push_str(&params);
            text.push('m');
        }
        let uri = if style.link == 0 {
            None
        } else {
            link_uri(style.link)
        };
        if let Some(uri) = uri {
            text.push_str("\x1b]8;;");
            text.push_str(uri);
            text.push_str("\x1b\\");
        }
        text.push_str(std::str::from_utf8(&row_bytes[start..end]).unwrap_or(""));
        if uri.is_some() {
            text.push_str("\x1b]8;;\x1b\\");
        }
        start = end;
    }
    text.push_str("\x1b[0m");
    text.push_str(terminator);
}

// Mirrors the bit layout in vt-core's `style.rs` (`TAG_INDEXED`/`TAG_RGB`,
// neither exported) since only `StyleCode`'s public accessors cross the
// crate boundary.
const TAG_INDEXED: u32 = 0x0100_0000;
const TAG_RGB: u32 = 0x0200_0000;

fn colour_params(colour: StyleCode, base: u32, extended: u32) -> String {
    let value = colour.value();
    if value & TAG_RGB != 0 {
        let rgb = value & 0x00ff_ffff;
        format!(
            "{};2;{};{};{}",
            extended,
            (rgb >> 16) & 0xff,
            (rgb >> 8) & 0xff,
            rgb & 0xff
        )
    } else if value & TAG_INDEXED != 0 {
        format!("{};5;{}", extended, value & 0xff)
    } else if value < 8 {
        format!("{}", base + value)
    } else {
        format!("{}", base + 60 + (value - 8))
    }
}

fn underline_colour_params(colour: StyleCode) -> String {
    let value = colour.value();
    if value & TAG_RGB != 0 {
        let rgb = value & 0x00ff_ffff;
        format!(
            "58;2;{};{};{}",
            (rgb >> 16) & 0xff,
            (rgb >> 8) & 0xff,
            rgb & 0xff
        )
    } else {
        format!("58;5;{}", value & 0xff)
    }
}

fn style_sgr_params(style: CellStyle) -> Option<String> {
    let mut params = Vec::new();
    if style.fg.is_bold() {
        params.push("1".to_string());
    }
    if style.fg.is_dim() {
        params.push("2".to_string());
    }
    let attrs = style.attrs;
    if attrs.contains(Attrs::ITALIC) {
        params.push("3".to_string());
    }
    let underline = [
        (Attrs::UNDERLINE, "4:1"),
        (Attrs::DOUBLE_UNDERLINE, "4:2"),
        (Attrs::CURLY_UNDERLINE, "4:3"),
        (Attrs::DOTTED_UNDERLINE, "4:4"),
        (Attrs::DASHED_UNDERLINE, "4:5"),
    ]
    .into_iter()
    .find(|(flag, _)| attrs.contains(*flag));
    if let Some((_, code)) = underline {
        params.push(code.to_string());
    }
    if attrs.contains(Attrs::BLINK) {
        params.push("5".to_string());
    }
    if attrs.contains(Attrs::HIDDEN) {
        params.push("8".to_string());
    }
    if attrs.contains(Attrs::STRIKE) {
        params.push("9".to_string());
    }
    if attrs.contains(Attrs::OVERLINE) {
        params.push("53".to_string());
    }
    if style.underline != StyleCode::DEFAULT {
        params.push(underline_colour_params(style.underline));
    }
    let foreground = style.fg.colour();
    if foreground != StyleCode::DEFAULT.colour() {
        params.push(colour_params(foreground, 30, 38));
    }
    let background = style.bg.colour();
    if background != StyleCode::DEFAULT_BACKGROUND.colour() {
        params.push(colour_params(background, 40, 48));
    }
    if params.is_empty() {
        None
    } else {
        Some(params.join(";"))
    }
}
