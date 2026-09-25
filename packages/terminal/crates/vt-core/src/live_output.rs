impl crate::TerminalCore {
    pub(crate) fn open_replay_window(&mut self, bytes: &[u8], parsed: usize, upto: usize) -> usize {
        let from = parsed.min(upto);
        let parsed = match bytes[from..upto]
            .windows(2)
            .rposition(|pair| pair == b"\x1b]")
        {
            Some(start) => {
                self.advance_vte(&bytes[from..from + start]);
                from + start
            }
            None => {
                self.live_output = self.live_output.wrapping_sub(self.open_osc_live);
                parsed
            }
        };
        self.parser.program_mut().agent_mut().set_replaying(true);
        parsed
    }

    pub(crate) fn note_open_osc(&mut self) {
        self.open_osc_live = if self.parser.program().agent().replaying() {
            0
        } else {
            self.mark_decoder
                .open_osc_bytes()
                .saturating_sub(self.answer_gate.held_len()) as u64
        };
    }
}
