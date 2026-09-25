use unicode_segmentation::UnicodeSegmentation;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WidthMode {
    #[default]
    Scalar,
    Grapheme,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Cluster {
    pub start: usize,
    pub end: usize,
    pub width: usize,
}

pub fn clusters(text: &str, mode: WidthMode) -> Vec<Cluster> {
    match mode {
        WidthMode::Grapheme => text
            .grapheme_indices(true)
            .map(|(start, grapheme)| Cluster {
                start,
                end: start + grapheme.len(),
                width: cluster_width(grapheme),
            })
            .collect(),
        WidthMode::Scalar => {
            let mut out: Vec<Cluster> = Vec::new();
            for (start, ch) in text.char_indices() {
                let end = start + ch.len_utf8();
                let width = UnicodeWidthChar::width(ch).unwrap_or(0);
                match out.last_mut() {
                    Some(last) if width == 0 => last.end = end,
                    _ => out.push(Cluster { start, end, width }),
                }
            }
            out
        }
    }
}

pub(crate) fn cluster_width(text: &str) -> usize {
    UnicodeWidthStr::width(text)
}

pub(crate) fn joins_previous(previous: &str, ch: char) -> bool {
    if previous.is_empty() || (ch.is_ascii() && previous.is_ascii()) {
        return false;
    }
    let total = previous.len() + ch.len_utf8();
    let mut stack = [0u8; 64];
    if total <= stack.len() {
        stack[..previous.len()].copy_from_slice(previous.as_bytes());
        ch.encode_utf8(&mut stack[previous.len()..total]);
        let joined = std::str::from_utf8(&stack[..total]).expect("two strs joined are utf-8");
        return joined.graphemes(true).nth(1).is_none();
    }
    let mut joined = String::with_capacity(total);
    joined.push_str(previous);
    joined.push(ch);
    joined.graphemes(true).nth(1).is_none()
}
