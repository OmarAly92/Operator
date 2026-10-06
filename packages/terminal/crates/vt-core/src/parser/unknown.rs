use std::collections::VecDeque;
use std::fmt::Write;

use vte::Params;

use super::Parser;

pub const UNKNOWN_SEQUENCES_CAP: usize = 64;
pub const UNKNOWN_TEXT_BYTES: usize = 48;
pub const UNKNOWN_FEED_BUDGET: usize = 128;
const OSC_NUMBER_DIGITS: usize = 5;
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
    scratch: String,
    spent: usize,
}

impl UnknownRing {
    pub(crate) fn begin_feed(&mut self) {
        self.spent = 0;
    }

    fn record(&mut self, write: impl FnOnce(&mut String)) {
        if self.spent >= UNKNOWN_FEED_BUDGET {
            return;
        }
        self.spent += 1;
        let mut text = std::mem::take(&mut self.scratch);
        text.clear();
        write(&mut text);
        cap_in_place(&mut text);
        self.note(&text);
        self.scratch = text;
    }

    fn note(&mut self, text: &str) {
        if let Some(last) = self.entries.back_mut() {
            if last.text == text {
                last.count = last.count.saturating_add(1);
                return;
            }
        }
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
        self.entries.push_back(UnknownSequence {
            text: text.to_owned(),
            count: 1,
        });
    }
}

pub(crate) fn private_modes_known(params: &Params) -> bool {
    params.iter().all(|group| {
        group
            .first()
            .is_none_or(|mode| KNOWN_PRIVATE_MODES.contains(mode))
    })
}

fn cap_in_place(text: &mut String) {
    if text.len() > UNKNOWN_TEXT_BYTES {
        let mut end = UNKNOWN_TEXT_BYTES;
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        text.truncate(end);
    }
}

fn write_sequence(
    text: &mut String,
    kind: &str,
    params: &Params,
    intermediates: &[u8],
    ignore: bool,
    action: char,
) {
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
            .record(|text| write_sequence(text, "CSI", params, intermediates, ignore, action));
    }

    pub(crate) fn note_unknown_dcs(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        ignore: bool,
        action: char,
    ) {
        self.unknown
            .record(|text| write_sequence(text, "DCS", params, intermediates, ignore, action));
    }

    pub(crate) fn note_esc(&mut self, intermediates: &[u8], byte: u8) {
        if intermediates.is_empty() && KNOWN_ESC_FINALS.contains(&byte) {
            return;
        }
        self.unknown.record(|text| {
            text.push_str("ESC ");
            text.extend(intermediates.iter().map(|byte| char::from(*byte)));
            text.push(char::from(byte));
        });
    }

    pub(crate) fn note_other_osc(&mut self, params: &[&[u8]]) {
        let first = params.first().copied().unwrap_or_default();
        if MARK_OSCS.contains(&first) {
            return;
        }
        let numeric = !first.is_empty()
            && first.len() <= OSC_NUMBER_DIGITS
            && first.iter().all(u8::is_ascii_digit);
        self.unknown.record(|text| {
            text.push_str("OSC ");
            if numeric {
                text.extend(first.iter().map(|byte| char::from(*byte)));
            } else {
                text.push('?');
            }
        });
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
