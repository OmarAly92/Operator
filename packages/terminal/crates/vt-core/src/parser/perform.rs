use vte::{Params, Perform};

use super::unknown::private_modes_known;
use super::Parser;
use crate::program::OscKind;

fn first_param(params: &Params) -> u16 {
    params
        .iter()
        .next()
        .and_then(|group| group.first().copied())
        .unwrap_or(0)
}

impl Parser {
    pub(crate) fn flush_run(&mut self) {
        if self.run.is_empty() {
            return;
        }
        let style = self.pending_style.resolved();
        let run = std::mem::take(&mut self.run);
        self.active_screen_mut().print_ascii_run(&run, style);
        self.run = run;
        self.run.clear();
    }

    fn dispatch_csi(&mut self, params: &Params, intermediates: &[u8], c: char) -> bool {
        if c == 'm' && intermediates.is_empty() {
            self.apply_sgr(params);
            return true;
        }
        if intermediates == b"?$" && c == 'p' {
            self.answer_decrqm(params);
            return true;
        }
        if intermediates.is_empty() && c == 'c' && first_param(params) == 0 {
            self.push_reply(b"\x1b[?62;22c");
            return true;
        }
        if intermediates == b">" && c == 'q' && first_param(params) == 0 {
            self.answer_xtversion();
            return true;
        }
        if intermediates.is_empty() && c == 't' {
            return self.xtwinops(params);
        }
        if intermediates.first() == Some(&b'?') && matches!(c, 'h' | 'l') {
            let set = c == 'h';
            for group in params.iter() {
                match group.first().copied() {
                    Some(1) => self.app_cursor = set,
                    Some(mode) => self.note_private_mode(mode, set),
                    None => {}
                }
            }
            self.active_screen_mut().csi(params, intermediates, c);
            return private_modes_known(params);
        }
        self.active_screen_mut().csi(params, intermediates, c)
    }
}

impl Perform for Parser {
    fn print(&mut self, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        if matches!(c, ' '..='~') {
            self.run.push(c as u8);
            return;
        }
        self.flush_run();
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
        self.flush_run();
        let screen = self.active_screen_mut();
        match byte {
            0x08 => screen.move_by(0, -1),
            0x09 => screen.tab(),
            0x0A..=0x0C => screen.line_feed(),
            0x0D => screen.carriage_return(),
            _ => {}
        }
    }

    fn hook(&mut self, params: &Params, intermediates: &[u8], ignore: bool, action: char) {
        self.note_unknown_dcs(params, intermediates, ignore, action);
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], ignore: bool, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Csi {
            params: params.iter().map(|group| group.to_vec()).collect(),
            intermediates: intermediates.to_vec(),
            action: c,
        });
        self.flush_run();
        if !self.dispatch_csi(params, intermediates, c) || ignore {
            self.note_unknown_csi(params, intermediates, ignore, c);
        }
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Esc {
            intermediates: intermediates.to_vec(),
            byte,
        });
        self.flush_run();
        self.active_screen_mut().esc(byte);
        self.note_esc(intermediates, byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        self.flush_run();
        match OscKind::of(params) {
            OscKind::Hyperlink => {
                let id = crate::hyperlink::parse_osc8(&params[1..])
                    .and_then(|link| self.hyperlinks.intern(link));
                self.pending_style.link = id.unwrap_or(0);
            }
            OscKind::IconName => {}
            OscKind::Other => self.note_other_osc(params),
            _ => self.program_osc(params, bell_terminated),
        }
    }
}
