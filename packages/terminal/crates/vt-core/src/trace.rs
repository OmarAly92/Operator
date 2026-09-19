use std::collections::VecDeque;

pub const TRACE_CAP: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TraceAction {
    Print(char),
    Execute(u8),
    Csi {
        params: Vec<Vec<u16>>,
        intermediates: Vec<u8>,
        action: char,
    },
    Esc {
        intermediates: Vec<u8>,
        byte: u8,
    },
    Osc(Vec<Vec<u8>>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceEntry {
    pub offset: u64,
    pub action: TraceAction,
}

#[derive(Default)]
pub(crate) struct Trace {
    entries: VecDeque<TraceEntry>,
    pub(crate) offset: u64,
}

impl Trace {
    pub(crate) fn record(&mut self, action: TraceAction) {
        if self.entries.len() == TRACE_CAP {
            self.entries.pop_front();
        }
        self.entries.push_back(TraceEntry {
            offset: self.offset,
            action,
        });
    }

    pub(crate) fn entries(&mut self) -> &[TraceEntry] {
        self.entries.make_contiguous()
    }

    pub(crate) fn clear(&mut self) {
        self.entries.clear();
    }
}
