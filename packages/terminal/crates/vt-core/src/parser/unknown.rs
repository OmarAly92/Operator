use std::collections::VecDeque;
use std::fmt::Write;

use vte::Params;

use super::Parser;

pub const UNKNOWN_SEQUENCES_CAP: usize = 64;
pub const UNKNOWN_TEXT_BYTES: usize = 48;
const OSC_PREFIX_BYTES: usize = 16;
const KNOWN_PRIVATE_MODES: [u16; 11] =
    [1, 25, 1000, 1002, 1003, 1004, 1006, 1049, 2004, 2026, 2048];
const KNOWN_ESC_FINALS: &[u8] = b"78DEMc\\";
const MARK_OSCS: [&[u8]; 3] = [b"7", b"133", b"7000"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownSequence {
    pub text: String,
    pub count: u32,
}

#[derive(Debug, Default)]
pub(crate) struct UnknownRing {
    entries: VecDeque<UnknownSequence>,
}

impl UnknownRing {
    fn note(&mut self, text: String) {
        if let Some(index) = self.entries.iter().position(|entry| entry.text == text) {
            if let Some(mut entry) = self.entries.remove(index) {
                entry.count = entry.count.saturating_add(1);
                self.entries.push_back(entry);
            }
            return;
        }
        if self.entries.len() == UNKNOWN_SEQUENCES_CAP {
            self.entries.pop_front();
        }
        self.entries.push_back(UnknownSequence { text, count: 1 });
    }
}

pub(crate) fn private_modes_known(params: &Params) -> bool {
    params.iter().all(|group| {
        group
            .first()
            .is_none_or(|mode| KNOWN_PRIVATE_MODES.contains(mode))
    })
}

fn capped(mut text: String) -> String {
    if text.len() > UNKNOWN_TEXT_BYTES {
        let mut end = UNKNOWN_TEXT_BYTES;
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        text.truncate(end);
    }
    text
}

fn sequence_text(
    kind: &str,
    params: &Params,
    intermediates: &[u8],
    ignore: bool,
    action: char,
) -> String {
    let mut text = String::new();
    if ignore {
        text.push_str("overflow ");
    }
    text.push_str(kind);
    text.push(' ');
    text.extend(intermediates.iter().map(|byte| char::from(*byte)));
    for (index, group) in params.iter().enumerate() {
        if index > 0 {
            text.push(';');
        }
        for (sub, value) in group.iter().enumerate() {
            if sub > 0 {
                text.push(':');
            }
            let _ = write!(text, "{value}");
        }
    }
    text.push(action);
    capped(text)
}

impl Parser {
    pub(crate) fn note_unknown_csi(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        ignore: bool,
        action: char,
    ) {
        self.unknown
            .note(sequence_text("CSI", params, intermediates, ignore, action));
    }

    pub(crate) fn note_unknown_dcs(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        ignore: bool,
        action: char,
    ) {
        self.unknown
            .note(sequence_text("DCS", params, intermediates, ignore, action));
    }

    pub(crate) fn note_esc(&mut self, intermediates: &[u8], byte: u8) {
        if intermediates.is_empty() && KNOWN_ESC_FINALS.contains(&byte) {
            return;
        }
        let mut text = String::from("ESC ");
        text.extend(intermediates.iter().map(|byte| char::from(*byte)));
        text.push(char::from(byte));
        self.unknown.note(capped(text));
    }

    pub(crate) fn note_other_osc(&mut self, params: &[&[u8]]) {
        let first = params.first().copied().unwrap_or_default();
        if MARK_OSCS.contains(&first) {
            return;
        }
        let prefix = &first[..first.len().min(OSC_PREFIX_BYTES)];
        self.unknown
            .note(capped(format!("OSC {}", String::from_utf8_lossy(prefix))));
    }
}

impl crate::TerminalCore {
    pub fn unknown_sequences(&self) -> Vec<UnknownSequence> {
        self.parser.unknown.entries.iter().cloned().collect()
    }

    pub fn clear_unknown_sequences(&mut self) {
        self.parser.unknown.entries.clear();
    }
}
