use vte::{Params, Perform};

use super::Parser;

impl Perform for Parser {
    fn print(&mut self, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
        let screen = self.active_screen_mut();
        match byte {
            0x08 => screen.move_by(0, -1),
            0x09 => screen.tab(),
            0x0A..=0x0C => screen.line_feed(),
            0x0D => screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Csi {
            params: params.iter().map(|group| group.to_vec()).collect(),
            intermediates: intermediates.to_vec(),
            action: c,
        });
        if c == 'm' && intermediates.is_empty() {
            self.apply_sgr(params);
            return;
        }
        if intermediates == b"?$" && c == 'p' {
            self.answer_decrqm(params);
            return;
        }
        if intermediates.is_empty()
            && c == 'c'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.push_reply(b"\x1b[?62;22c");
            return;
        }
        if intermediates == b">"
            && c == 'q'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.answer_xtversion();
            return;
        }
        if intermediates.is_empty() && c == 't' {
            self.xtwinops(params);
            return;
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
        }
        self.active_screen_mut().csi(params, intermediates, c);
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Esc {
            intermediates: intermediates.to_vec(),
            byte,
        });
        #[cfg(not(feature = "trace"))]
        let _ = intermediates;
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        match crate::program::OscKind::of(params) {
            crate::program::OscKind::Hyperlink => {
                let id = crate::hyperlink::parse_osc8(&params[1..])
                    .and_then(|link| self.hyperlinks.intern(link));
                self.pending_style.link = id.unwrap_or(0);
            }
            crate::program::OscKind::Other | crate::program::OscKind::IconName => {}
            _ => self.program_osc(params, bell_terminated),
        }
    }
}
