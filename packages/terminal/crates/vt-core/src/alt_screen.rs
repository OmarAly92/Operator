/// One boolean: are we currently inside the alt screen?
///
/// The alt screen is the full-screen TUI mode toggled by `CSI ? 1049 h/l`.
/// While it's active, the block list must be frozen — a TUI can draw
/// something that looks like a mark sequence without it being one, and
/// routing those bytes into `BlockGrid` would shred the real blocks the
/// shell produced before the TUI took over.
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct AltScreen {
    active: bool,
}

impl AltScreen {
    pub fn new() -> Self {
        Self { active: false }
    }

    pub fn set(&mut self, active: bool) {
        self.active = active;
    }

    pub fn is_active(&self) -> bool {
        self.active
    }
}
