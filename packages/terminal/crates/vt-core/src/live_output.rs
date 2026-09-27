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

    pub(crate) fn count_live_output(&mut self, bytes: &[u8]) {
        if !self.parser.program().agent().replaying() {
            self.live_output = self.live_output.wrapping_add(visible_len(bytes));
        }
    }
}

fn visible_len(bytes: &[u8]) -> u64 {
    let mut count = 0u64;
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == 0x1b && bytes.get(index + 1) == Some(&b']') {
            match osc_len(&bytes[index + 2..]) {
                Some(len) => index += 2 + len,
                None => return count + (bytes.len() - index) as u64,
            }
            continue;
        }
        count += 1;
        index += 1;
    }
    count
}

fn osc_len(rest: &[u8]) -> Option<usize> {
    rest.iter().enumerate().find_map(|(at, &byte)| match byte {
        0x07 => Some(at + 1),
        0x1b if rest.get(at + 1) == Some(&b'\\') => Some(at + 2),
        0x1b => Some(at),
        _ => None,
    })
}
