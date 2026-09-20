#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    pub rows: usize,
    pub bytes: usize,
}

impl Limits {
    pub const DEFAULT: Limits = Limits {
        rows: 200_000,
        bytes: 128 * 1024 * 1024,
    };

    pub const fn rows_only(rows: usize) -> Limits {
        Limits {
            rows,
            bytes: usize::MAX,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MemoryStats {
    pub content_bytes: usize,
    pub style_entries: usize,
    pub rows: usize,
    pub blocks: usize,
}
