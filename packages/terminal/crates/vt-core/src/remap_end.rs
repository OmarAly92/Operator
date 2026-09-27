impl crate::TerminalCore {
    pub fn take_remap_end(&mut self) -> Option<(u64, u64)> {
        self.parser.take_remap_end()
    }
}
