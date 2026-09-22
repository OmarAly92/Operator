use vte::Params;

use crate::parser::read_extended_colour;
use crate::style::{Attrs, CellStyle, StyleCode};

pub(crate) fn apply(style: &mut CellStyle, params: &Params) {
    let groups: Vec<Vec<u16>> = params.iter().map(|sub| sub.to_vec()).collect();
    if groups.is_empty() {
        *style = CellStyle::DEFAULT;
        return;
    }
    let mut index = 0;
    while index < groups.len() {
        let group = &groups[index];
        let code = group.first().copied().unwrap_or(0);
        if matches!(code, 38 | 48 | 58) {
            let (colour, consumed) = read_extended_colour(&groups, index);
            if let Some(colour) = colour {
                match code {
                    38 => style.fg = style.fg.with_colour(colour),
                    48 => style.bg = colour,
                    _ => style.underline = colour,
                }
            }
            index += consumed;
            continue;
        }
        match code {
            0 => *style = CellStyle::DEFAULT,
            1 => style.fg = style.fg.with_bold(true),
            2 => style.fg = style.fg.with_dim(true),
            3 => style.attrs = style.attrs.with(Attrs::ITALIC, true),
            4 => {
                let kind = match group.get(1).copied() {
                    None | Some(1) => Attrs::UNDERLINE,
                    Some(0) => 0,
                    Some(2) => Attrs::DOUBLE_UNDERLINE,
                    Some(3) => Attrs::CURLY_UNDERLINE,
                    Some(4) => Attrs::DOTTED_UNDERLINE,
                    Some(5) => Attrs::DASHED_UNDERLINE,
                    Some(_) => 0,
                };
                style.attrs = style.attrs.with_underline(kind);
            }
            5 | 6 => style.attrs = style.attrs.with(Attrs::BLINK, true),
            7 => style.fg = style.fg.with_reverse(true),
            8 => style.attrs = style.attrs.with(Attrs::HIDDEN, true),
            9 => style.attrs = style.attrs.with(Attrs::STRIKE, true),
            21 => style.attrs = style.attrs.with_underline(Attrs::DOUBLE_UNDERLINE),
            22 => style.fg = style.fg.with_bold(false).with_dim(false),
            23 => style.attrs = style.attrs.with(Attrs::ITALIC, false),
            24 => style.attrs = style.attrs.without(Attrs::ALL_UNDERLINES),
            25 => style.attrs = style.attrs.with(Attrs::BLINK, false),
            27 => style.fg = style.fg.with_reverse(false),
            28 => style.attrs = style.attrs.with(Attrs::HIDDEN, false),
            29 => style.attrs = style.attrs.with(Attrs::STRIKE, false),
            30..=37 => style.fg = style.fg.with_colour(StyleCode::ansi((code - 30) as u8)),
            39 => style.fg = style.fg.with_colour(StyleCode::DEFAULT),
            40..=47 => style.bg = StyleCode::ansi((code - 40) as u8),
            49 => style.bg = StyleCode::DEFAULT_BACKGROUND,
            53 => style.attrs = style.attrs.with(Attrs::OVERLINE, true),
            55 => style.attrs = style.attrs.with(Attrs::OVERLINE, false),
            59 => style.underline = StyleCode::DEFAULT,
            90..=97 => style.fg = style.fg.with_colour(StyleCode::ansi((code - 90 + 8) as u8)),
            100..=107 => style.bg = StyleCode::ansi((code - 100 + 8) as u8),
            _ => {}
        }
        index += 1;
    }
}
