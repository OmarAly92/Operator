use std::borrow::Cow;

const ESC: u8 = 0x1B;
const BEL: u8 = 0x07;
const SWALLOW_CAP: usize = 4096;
const ANSWER_MARKS: [&[u8]; 2] = [b"\x1b]7000;v=1;history=", b"\x1b]7000;v=1;older="];

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum State {
    #[default]
    Pass,
    Match,
    Swallow,
    SwallowEsc,
}

#[derive(Debug, Default)]
pub(crate) struct AnswerGate {
    state: State,
    held: Vec<u8>,
    swallowed: usize,
}

impl AnswerGate {
    pub(crate) fn filter<'a>(&mut self, bytes: &'a [u8]) -> Cow<'a, [u8]> {
        if self.state == State::Pass && !bytes.contains(&ESC) {
            return Cow::Borrowed(bytes);
        }
        let mut out = Vec::with_capacity(bytes.len() + self.held.len());
        let mut index = 0;
        while index < bytes.len() {
            if self.state == State::Pass {
                let end = bytes[index..]
                    .iter()
                    .position(|byte| *byte == ESC)
                    .map_or(bytes.len(), |at| index + at);
                out.extend_from_slice(&bytes[index..end]);
                index = end;
                if index == bytes.len() {
                    break;
                }
            }
            self.step(bytes[index], &mut out);
            index += 1;
        }
        Cow::Owned(out)
    }

    pub(crate) fn held_len(&self) -> usize {
        self.held.len()
    }

    fn step(&mut self, byte: u8, out: &mut Vec<u8>) {
        match self.state {
            State::Pass => {
                if byte == ESC {
                    self.held.push(byte);
                    self.state = State::Match;
                } else {
                    out.push(byte);
                }
            }
            State::Match => {
                self.held.push(byte);
                if ANSWER_MARKS.contains(&self.held.as_slice()) {
                    self.held.clear();
                    self.swallowed = 0;
                    self.state = State::Swallow;
                } else if !ANSWER_MARKS.iter().any(|mark| mark.starts_with(&self.held)) {
                    self.held.pop();
                    out.append(&mut self.held);
                    self.state = State::Pass;
                    self.step(byte, out);
                }
            }
            State::Swallow => {
                self.swallowed += 1;
                if byte == BEL || self.swallowed > SWALLOW_CAP {
                    self.state = State::Pass;
                } else if byte == ESC {
                    self.state = State::SwallowEsc;
                }
            }
            State::SwallowEsc => {
                self.state = State::Pass;
                if byte != b'\\' {
                    self.step(ESC, out);
                    self.step(byte, out);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(gate: &mut AnswerGate, pieces: &[&[u8]]) -> Vec<u8> {
        pieces
            .iter()
            .flat_map(|piece| gate.filter(piece).into_owned())
            .collect()
    }

    #[test]
    fn plain_output_passes_untouched() {
        let mut gate = AnswerGate::default();
        assert!(matches!(gate.filter(b"plain text\r\n"), Cow::Borrowed(_)));
        assert_eq!(
            run(
                &mut gate,
                &[b"\x1b[31mred\x1b]0;title\x07\x1b]7000;v=1;id=1\x1b\\"]
            ),
            b"\x1b[31mred\x1b]0;title\x07\x1b]7000;v=1;id=1\x1b\\"
        );
    }

    #[test]
    fn answer_marks_never_reach_the_parser() {
        let mut gate = AnswerGate::default();
        assert_eq!(
            run(
                &mut gate,
                &[
                    b"\x1b[3\x1b]7000;v=1;history=1,2;cols=3\x1b\\\x1b]7000;v=1;older=0\x07",
                    b"1m"
                ]
            ),
            b"\x1b[31m"
        );
    }

    #[test]
    fn a_mark_split_anywhere_is_still_held_back() {
        let stream = b"a\x1b\x1b]7000;v=1;older=12\x1b\\\x1b]7000;v=1;o\x1b[0mb";
        let expected = b"a\x1b\x1b]7000;v=1;o\x1b[0mb".to_vec();
        for split in 0..stream.len() {
            let mut gate = AnswerGate::default();
            assert_eq!(
                run(&mut gate, &[&stream[..split], &stream[split..]]),
                expected,
                "split at {split}"
            );
        }
    }

    #[test]
    fn an_unterminated_mark_is_given_up_after_the_cap() {
        let mut gate = AnswerGate::default();
        let mut stream = b"\x1b]7000;v=1;older=".to_vec();
        stream.extend(std::iter::repeat_n(b'9', SWALLOW_CAP + 1));
        stream.extend_from_slice(b"after");
        assert_eq!(run(&mut gate, &[&stream]), b"after");
    }
}
