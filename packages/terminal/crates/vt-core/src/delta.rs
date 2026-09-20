use std::ops::Range;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeltaKind {
    Full,
    Partial,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Delta {
    pub generation: u64,
    pub kind: DeltaKind,
    pub trimmed_rows: usize,
    pub appended_history: Range<usize>,
    pub screen_rows: Vec<usize>,
    pub remap: Option<Vec<(u64, u64)>>,
    pub history_rewritten_from: Option<usize>,
}
