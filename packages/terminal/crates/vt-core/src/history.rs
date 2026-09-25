use terminal_marks::{MarkDecoder, MarkEvent};
use vte::Parser as VteParser;
use vte::{Params, Perform};

use crate::hyperlink::HyperlinkRegistry;
use crate::parser::{HistoryBlock, HistoryRow};
use crate::screen::ScreenGrid;
use crate::style::CellStyle;
use crate::width::WidthMode;

#[derive(Default)]
struct OpenBlock {
    first_row: usize,
    command: String,
}

pub(crate) struct HistoryReceiver {
    first_stable_row: u64,
    wanted: usize,
    cols: usize,
    seen_rows: usize,
    vte: VteParser,
    screen: Option<ScreenGrid>,
    marks: MarkDecoder,
    open: Option<OpenBlock>,
    blocks: Vec<HistoryBlock>,
    done: bool,
    pending_style: CellStyle,
}

impl HistoryReceiver {
    pub fn new() -> Self {
        Self {
            first_stable_row: 0,
            wanted: 0,
            cols: 0,
            seen_rows: 0,
            vte: VteParser::new(),
            screen: None,
            marks: MarkDecoder::new(),
            open: None,
            blocks: Vec::new(),
            done: false,
            pending_style: CellStyle::DEFAULT,
        }
    }

    pub fn is_active(&self) -> bool {
        self.screen.is_some()
    }

    pub fn begin(&mut self, first_stable_row: u64, rows: usize, cols: usize, mode: WidthMode) {
        let mut screen = ScreenGrid::new(rows.max(1) + 1, cols.max(1));
        self.cols = screen.cols();
        screen.set_records_eviction(false);
        screen.set_width_mode(mode);
        self.first_stable_row = first_stable_row;
        self.wanted = rows;
        self.seen_rows = 0;
        self.vte = VteParser::new();
        self.screen = Some(screen);
        self.marks = MarkDecoder::new();
        self.open = None;
        self.blocks.clear();
        self.done = false;
        self.pending_style = CellStyle::DEFAULT;
    }

    pub fn consume(&mut self, bytes: &[u8], links: &mut HyperlinkRegistry) -> usize {
        let Some(screen) = self.screen.as_mut() else {
            return 0;
        };
        let mut consumed = 0usize;
        for (index, byte) in bytes.iter().enumerate() {
            for (_, event) in self.marks.feed_with_offsets(std::slice::from_ref(byte)) {
                note_mark(&mut self.open, &mut self.blocks, self.seen_rows, event);
            }
            let mut perform = ScreenPerform {
                screen,
                style: &mut self.pending_style,
                links,
            };
            self.vte.advance(&mut perform, std::slice::from_ref(byte));
            consumed = index + 1;
            if *byte == b'\n' {
                self.seen_rows += 1;
                if self.seen_rows == self.wanted {
                    self.done = true;
                    break;
                }
            }
        }
        consumed
    }

    pub fn take(&mut self) -> Option<(u64, Vec<HistoryRow>, Vec<HistoryBlock>, usize)> {
        if !self.done {
            return None;
        }
        let screen = self.screen.take()?;
        self.done = false;
        let rows = (0..self.wanted)
            .map(|row| history_row(&screen, row))
            .collect();
        if let Some(open) = self.open.take() {
            self.blocks.push(HistoryBlock {
                first_row: open.first_row,
                row_count: self.wanted - open.first_row,
                command: open.command,
                exit_code: None,
            });
        }
        Some((
            self.first_stable_row,
            rows,
            std::mem::take(&mut self.blocks),
            self.cols,
        ))
    }
}

impl crate::TerminalCore {
    pub(crate) fn drain_history(&mut self) {
        if let Some((first_stable_row, rows, blocks, cols)) = self.history.take() {
            let count = rows.len();
            if self
                .parser
                .apply_history_chunk(first_stable_row, rows, blocks)
                && cols > self.parser.columns()
            {
                self.parser.mark_history_stale(count, cols);
            }
            self.debug_check();
        }
    }
}

struct ScreenPerform<'a> {
    screen: &'a mut ScreenGrid,
    style: &'a mut CellStyle,
    links: &'a mut HyperlinkRegistry,
}

impl Perform for ScreenPerform<'_> {
    fn print(&mut self, c: char) {
        self.screen.print(c, self.style.resolved());
    }

    fn execute(&mut self, byte: u8) {
        match byte {
            0x08 => self.screen.move_by(0, -1),
            0x09 => self.screen.tab(),
            0x0A..=0x0C => self.screen.line_feed(),
            0x0D => self.screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
        if c == 'm' && intermediates.is_empty() {
            crate::sgr::apply(self.style, params);
            self.screen.set_erase_background(self.style.bg);
            return;
        }
        self.screen.csi(params, intermediates, c);
    }

    fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
        self.screen.esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if crate::program::OscKind::of(params) == crate::program::OscKind::Hyperlink {
            let id =
                crate::hyperlink::parse_osc8(&params[1..]).and_then(|link| self.links.intern(link));
            self.style.link = id.unwrap_or(0);
        }
    }
}

fn note_mark(
    open: &mut Option<OpenBlock>,
    blocks: &mut Vec<HistoryBlock>,
    row: usize,
    event: MarkEvent,
) {
    let MarkEvent::Extension(fields) = event else {
        return;
    };
    let mut exit: Option<Option<i32>> = None;
    let mut command: Option<String> = None;
    let mut opens = false;
    for (key, value) in fields.pairs {
        match key.as_str() {
            "id" => opens = true,
            "cmd" => command = Some(value),
            "exit" => exit = Some(value.parse::<i32>().ok()),
            _ => {}
        }
    }
    if opens {
        *open = Some(OpenBlock {
            first_row: row,
            command: command.unwrap_or_default(),
        });
        return;
    }
    if let Some(exit_code) = exit {
        if let Some(started) = open.take() {
            blocks.push(HistoryBlock {
                first_row: started.first_row,
                row_count: (row + 1).saturating_sub(started.first_row).max(1),
                command: started.command,
                exit_code,
            });
        }
    }
}

fn history_row(screen: &ScreenGrid, row: usize) -> HistoryRow {
    let exported = crate::grid::export_screen_row(screen, row);
    HistoryRow {
        bytes: exported.bytes,
        wrapped: false,
        indent: exported.indent,
        styles: exported.styles,
    }
}
