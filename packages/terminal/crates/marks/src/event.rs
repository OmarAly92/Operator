use crate::scanner::Scanner;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MarkTier {
    Osc133,
    Extension,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ExtensionFields {
    pub pairs: Vec<(String, String)>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MarkEvent {
    PromptStart {
        tier: MarkTier,
    },
    CommandStart {
        tier: MarkTier,
    },
    OutputStart {
        tier: MarkTier,
    },
    CommandEnd {
        tier: MarkTier,
        exit_code: Option<i32>,
    },
    CwdChanged {
        path: String,
    },
    Extension(ExtensionFields),
    AltScreenEnter,
    AltScreenLeave,
}

/// Stateful byte-level decoder. It survives across `feed` calls so a mark
/// split across two reads still decodes. The 4096-byte pending cap inside
/// `Scanner` is what stops an unterminated OSC from turning the decoder
/// into a permanent black hole.
pub struct MarkDecoder {
    scanner: Scanner,
    /// True once the decoder has seen any mark that "opens" a block (`A`,
    /// `B`, or `C`). Recovery table row 3 says `D` with no open block is
    /// ignored; tracking the flag here means the filter survives the
    /// split-read case the scanner cannot see.
    block_open: bool,
}

impl MarkDecoder {
    pub fn new() -> Self {
        Self {
            scanner: Scanner::new(),
            block_open: false,
        }
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Vec<MarkEvent> {
        let raw = self.scanner.feed(bytes);
        let mut out = Vec::with_capacity(raw.len());
        for event in raw {
            match &event {
                MarkEvent::PromptStart { .. }
                | MarkEvent::CommandStart { .. }
                | MarkEvent::OutputStart { .. } => {
                    self.block_open = true;
                    out.push(event);
                }
                MarkEvent::CommandEnd { .. } => {
                    if self.block_open {
                        out.push(event);
                        self.block_open = false;
                    }
                    // Otherwise recovery row 3: ignore.
                }
                _ => out.push(event),
            }
        }
        out
    }
}

impl Default for MarkDecoder {
    fn default() -> Self {
        Self::new()
    }
}
