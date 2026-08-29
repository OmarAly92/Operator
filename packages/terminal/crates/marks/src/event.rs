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
    InputReady,
    InputReleased,
    AltScreenEnter,
    AltScreenLeave,
}

/// Stateful byte-level decoder. It survives across `feed` calls so a mark
/// split across two reads still decodes. The 4096-byte pending cap inside
/// `Scanner` is what stops an unterminated OSC from turning the decoder
/// into a permanent black hole.
pub struct MarkDecoder {
    scanner: Scanner,
}

impl MarkDecoder {
    pub fn new() -> Self {
        Self {
            scanner: Scanner::new(),
        }
    }

    /// Decodes `bytes`, returning every event with the offset just past the
    /// mark that produced it.
    ///
    /// The decoder is deliberately stateless about blocks. Whether a
    /// `CommandEnd` with no open block is meaningful is the block grid's
    /// question, not the decoder's -- spec 7.5 scopes this crate to finding
    /// boundaries and extracting fields, and `BlockGrid::close_block` already
    /// ignores a close it cannot apply. Keeping that state here would also
    /// force the Go decoder to grow a block model it was scoped out of.
    pub fn feed_with_offsets(&mut self, bytes: &[u8]) -> Vec<(usize, MarkEvent)> {
        self.scanner.feed(bytes)
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Vec<MarkEvent> {
        self.feed_with_offsets(bytes)
            .into_iter()
            .map(|(_, event)| event)
            .collect()
    }
}

impl Default for MarkDecoder {
    fn default() -> Self {
        Self::new()
    }
}
