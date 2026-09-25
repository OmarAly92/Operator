use vte::Params;

use super::Parser;
use crate::program::ProgramState;

impl Parser {
    pub(crate) fn program(&self) -> &ProgramState {
        &self.program
    }

    pub(crate) fn program_mut(&mut self) -> &mut ProgramState {
        &mut self.program
    }

    pub(crate) fn program_osc(&mut self, params: &[&[u8]], bell_terminated: bool) {
        if let Some(reply) = self.program.osc(params, bell_terminated) {
            self.push_reply(&reply);
        }
    }

    pub(crate) fn xtwinops(&mut self, params: &Params) {
        let mut groups = params.iter();
        let kind = groups.next().and_then(|g| g.first().copied()).unwrap_or(0);
        let which = groups.next().and_then(|g| g.first().copied()).unwrap_or(0);
        match kind {
            22 if which != 1 => self.program.push_title(),
            23 if which != 1 => self.program.pop_title(),
            14 | 16 | 18 => {
                if let Some(reply) = self
                    .program
                    .size_report(kind, self.width, self.screen.rows())
                {
                    self.push_reply(&reply);
                }
            }
            _ => {}
        }
    }

    pub(crate) fn note_in_band_resize_mode(&mut self, set: bool) {
        self.program.set_in_band_resize(set);
        if set {
            self.send_in_band_report();
        }
    }

    pub(crate) fn send_in_band_report(&mut self) {
        if let Some(reply) = self.program.in_band_report(self.width, self.screen.rows()) {
            self.push_reply(&reply);
        }
    }
}
