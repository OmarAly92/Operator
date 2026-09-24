use crate::style::StyleCode;

/// Reads an extended-colour introducer (`38`/`48`/`58`) and reports how many
/// parameter groups it consumed, itself included.
///
/// Both spellings reach here. The colon form (`38:5:196`) is self-contained in
/// one group; the semicolon form (`38;5;196`) spreads across the groups that
/// follow, and consuming them is what stops `48;5;31` from being read as SGR 31
/// and repainting the foreground. A truncated or unrecognised selector consumes
/// only the introducer, so parsing always advances.
pub(crate) fn read_extended_colour(
    groups: &[Vec<u16>],
    index: usize,
) -> (Option<StyleCode>, usize) {
    let group = &groups[index];
    if group.len() > 1 {
        return (colour_from_subparameters(group), 1);
    }
    let selector = groups.get(index + 1).and_then(|next| next.first()).copied();
    match selector {
        Some(5) => {
            let colour = groups
                .get(index + 2)
                .and_then(|value| value.first())
                .map(|value| StyleCode::indexed(narrow(*value)));
            (colour, 3.min(groups.len() - index))
        }
        Some(2) => {
            let channel = |offset: usize| {
                groups
                    .get(index + offset)
                    .and_then(|value| value.first())
                    .copied()
            };
            let colour = match (channel(2), channel(3), channel(4)) {
                (Some(r), Some(g), Some(b)) => {
                    Some(StyleCode::rgb(narrow(r), narrow(g), narrow(b)))
                }
                _ => None,
            };
            (colour, 5.min(groups.len() - index))
        }
        _ => (None, 1),
    }
}

/// The colon form carries its selector and channels as sub-parameters of one
/// group. Truecolour is often written `38:2::r:g:b`, where the empty
/// colour-space id parses as a zero and shifts the channels along by one.
fn colour_from_subparameters(group: &[u16]) -> Option<StyleCode> {
    match group.get(1)? {
        5 => group.get(2).map(|value| StyleCode::indexed(narrow(*value))),
        2 => {
            let start = if group.len() >= 6 { 3 } else { 2 };
            let r = *group.get(start)?;
            let g = *group.get(start + 1)?;
            let b = *group.get(start + 2)?;
            Some(StyleCode::rgb(narrow(r), narrow(g), narrow(b)))
        }
        _ => None,
    }
}

fn narrow(value: u16) -> u8 {
    value.min(255) as u8
}
