use crate::event::MarkEvent;

/// Hard cap on an in-flight OSC payload. Past this we abandon the sequence
/// rather than buffer it forever — the spec says a decoder "MUST handle an OSC
/// that never terminates" by giving up and resuming on the next byte, and
/// the 4096-byte cap is the concrete ceiling we picked. The plan's
/// "things that are easy to get wrong" section calls this out by name.
const PENDING_CAP: usize = 4096;

const ESC: u8 = 0x1B;
const BEL: u8 = 0x07;
const BRACKET: u8 = b']';
const BACKSLASH: u8 = b'\\';
const CSI: u8 = b'[';
const QUESTION: u8 = b'?';

#[derive(Debug, Eq, PartialEq)]
enum State {
    /// Outside any escape sequence; scanning for the next one.
    Ground,
    /// Just saw ESC; the next byte decides whether it is an OSC (`]`) or a
    /// CSI (`[`) or some other sequence we ignore.
    AfterEsc,
    /// Inside an OSC payload, terminated by BEL or `ESC \`.
    Osc,
    /// We just saw ESC inside an OSC; the next byte decides whether it is
    /// a real ST (`\`) or an abort (anything else).
    OscSawEsc,
    /// Inside a DEC private-mode CSI sequence (we only model `?1049h`/`l`).
    CsiPrivate,
}

/// Stateful, allocation-free byte scanner. It recognises:
/// - OSC sequences (`ESC ] payload BEL` and `ESC ] payload ESC \`);
/// - DEC private-mode CSI sequences, and emits `AltScreenEnter` / `AltScreenLeave`
///   for `?1049h` / `?1049l` (the alt-screen toggle the protocol §8 names);
/// - nothing else — every other escape is a passthrough.
pub struct Scanner {
    state: State,
    pending: Vec<u8>,
    private_question: bool,
    private_digits: Vec<u8>,
}

impl Scanner {
    pub fn new() -> Self {
        Self {
            state: State::Ground,
            pending: Vec::new(),
            private_question: false,
            private_digits: Vec::new(),
        }
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Vec<MarkEvent> {
        let mut events = Vec::new();
        for &byte in bytes {
            self.step(byte, &mut events);
        }
        events
    }

    fn step(&mut self, byte: u8, events: &mut Vec<MarkEvent>) {
        match self.state {
            State::Ground => {
                if byte == ESC {
                    self.state = State::AfterEsc;
                }
            }
            State::AfterEsc => match byte {
                BRACKET => {
                    self.pending.clear();
                    self.state = State::Osc;
                }
                CSI => {
                    self.private_question = false;
                    self.private_digits.clear();
                    self.state = State::CsiPrivate;
                }
                // Some other escape (e.g. `ESC c` for full reset). Drop it
                // and resume scanning — a stray ESC never opens an OSC.
                _ => self.state = State::Ground,
            },
            State::Osc => {
                if byte == BEL {
                    self.flush_osc(events);
                    self.state = State::Ground;
                } else if byte == ESC {
                    // Defer the ST-or-abort decision to the next byte.
                    self.state = State::OscSawEsc;
                } else {
                    self.push_pending(byte);
                }
            }
            State::OscSawEsc => {
                if byte == BACKSLASH {
                    // Real ST — close the OSC.
                    self.flush_osc(events);
                    self.state = State::Ground;
                } else {
                    // A bare ESC inside an OSC is what shells send when they
                    // abort a half-written prompt. The
                    // `malformed-truncated-sequence` vector is the regression:
                    // drop the OSC payload, then re-process the new byte as
                    // if we had just seen ESC. That way a `]` following the
                    // abort opens a fresh OSC, matching the expected output.
                    self.pending.clear();
                    self.state = State::AfterEsc;
                    self.step(byte, events);
                }
            }
            State::CsiPrivate => {
                if !self.private_question && byte == QUESTION && self.private_digits.is_empty() {
                    self.private_question = true;
                } else if self.private_question && (byte.is_ascii_digit() || byte == b';') {
                    if byte != b';' {
                        self.private_digits.push(byte);
                    }
                } else if byte == b'h' {
                    if self.private_digits == b"1049" {
                        events.push(MarkEvent::AltScreenEnter);
                    }
                    self.state = State::Ground;
                } else if byte == b'l' {
                    if self.private_digits == b"1049" {
                        events.push(MarkEvent::AltScreenLeave);
                    }
                    self.state = State::Ground;
                } else {
                    // Some other CSI we don't model. Abort cleanly.
                    self.state = State::Ground;
                }
            }
        }
    }

    fn push_pending(&mut self, byte: u8) {
        self.pending.push(byte);
        if self.pending.len() > PENDING_CAP {
            // Spec: "give up on the unterminated sequence and resume on the
            // next byte." This is the only allocation bound we need.
            self.pending.clear();
            self.state = State::Ground;
        }
    }

    fn flush_osc(&mut self, events: &mut Vec<MarkEvent>) {
        // An empty OSC payload is meaningless; both decoders must ignore it.
        let payload = std::mem::take(&mut self.pending);
        if let Some(event) = crate::osc::decode(&payload) {
            events.push(event);
        } else if let Some(fields) = crate::extension::decode(&payload) {
            events.push(MarkEvent::Extension(fields));
        }
    }
}

impl Default for Scanner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pending_cap_abandons_unterminated_osc() {
        let mut s = Scanner::new();
        s.feed(b"\x1b]");
        let pad = vec![b'x'; PENDING_CAP + 16];
        s.feed(&pad);
        let events = s.feed(b"\x1b]133;A\x07");
        assert_eq!(
            events,
            vec![MarkEvent::PromptStart {
                tier: crate::event::MarkTier::Osc133
            }]
        );
    }

    #[test]
    fn alt_screen_enter_and_leave() {
        let mut s = Scanner::new();
        assert_eq!(s.feed(b"\x1b[?1049h"), vec![MarkEvent::AltScreenEnter]);
        assert_eq!(s.feed(b"\x1b[?1049l"), vec![MarkEvent::AltScreenLeave]);
    }

    #[test]
    fn other_csi_passes_through() {
        let mut s = Scanner::new();
        // `?25h` (show cursor) is not in our vocabulary; the scanner must
        // consume it without emitting anything.
        assert_eq!(s.feed(b"\x1b[?25h"), vec![]);
    }
}
