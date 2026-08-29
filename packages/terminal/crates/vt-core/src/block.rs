pub type BlockId = u64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockState {
    Running,
    Finished,
    Abandoned,
}

/// Which tier of marks produced this block.
///
/// The renderer and the tests both branch on it: a zero-setup OSC 133 session
/// and a fully bootstrapped one must be distinguishable without guessing.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockSource {
    Osc133,
    Extension,
    Synthetic,
}

impl BlockState {
    pub fn as_u32(self) -> u32 {
        match self {
            BlockState::Running => 0,
            BlockState::Finished => 1,
            BlockState::Abandoned => 2,
        }
    }
}

impl BlockSource {
    pub fn as_u32(self) -> u32 {
        match self {
            BlockSource::Osc133 => 0,
            BlockSource::Extension => 1,
            BlockSource::Synthetic => 2,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct BlockMeta {
    pub command: String,
    pub cwd: String,
    pub git_branch: String,
    pub exit_code: Option<i32>,
    pub started_at_ms: Option<u64>,
    pub finished_at_ms: Option<u64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Block {
    pub id: BlockId,
    pub first_row: usize,
    pub row_count: usize,
    pub state: BlockState,
    pub source: BlockSource,
    pub meta: BlockMeta,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TextSpan {
    pub start: u32,
    pub end: u32,
}

/// One block as the snapshot carries it: every field already narrowed to the
/// `u32` the export buffers use, and text hoisted into `block_text` so the
/// record stays fixed width.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BlockRecord {
    pub id: BlockId,
    pub first_row: u32,
    pub row_count: u32,
    pub state: BlockState,
    pub source: BlockSource,
    pub exit_code: Option<i32>,
    pub duration_ms: Option<u64>,
    pub command: TextSpan,
    pub cwd: TextSpan,
    pub git_branch: TextSpan,
}
