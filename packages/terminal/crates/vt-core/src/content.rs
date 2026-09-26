use std::collections::VecDeque;

const CHUNK_SIZE: usize = 4096;
pub(crate) const CONTENT_BASE: u64 = 1 << 48;

#[derive(Clone)]
pub(crate) struct Chunk {
    pub start: u64,
    pub bytes: Vec<u8>,
}

pub(crate) struct Content {
    chunks: VecDeque<Chunk>,
    next_offset: u64,
    truncations: u64,
    cuts: Vec<(u64, u64)>,
}

impl Clone for Content {
    fn clone(&self) -> Self {
        Self {
            chunks: self.chunks.clone(),
            next_offset: self.next_offset,
            truncations: self.truncations,
            cuts: self.cuts.clone(),
        }
    }
}

impl Content {
    #[cfg(test)]
    pub fn new() -> Self {
        Self {
            chunks: VecDeque::new(),
            next_offset: 0,
            truncations: 0,
            cuts: Vec::new(),
        }
    }

    pub fn with_base(base: u64) -> Self {
        Self {
            chunks: VecDeque::new(),
            next_offset: base,
            truncations: 0,
            cuts: Vec::new(),
        }
    }

    pub fn prepend(&mut self, bytes: &[u8]) -> u64 {
        if bytes.is_empty() {
            return self.start_offset();
        }
        let start = self.start_offset() - bytes.len() as u64;
        self.chunks.push_front(Chunk {
            start,
            bytes: bytes.to_vec(),
        });
        start
    }

    pub fn end_offset(&self) -> u64 {
        self.next_offset
    }

    pub fn start_offset(&self) -> u64 {
        self.chunks
            .front()
            .map_or(self.next_offset, |chunk| chunk.start)
    }

    pub fn push_char(&mut self, scalar: &str) {
        let bytes = scalar.as_bytes();
        let bytes_len = bytes.len();

        let need_new = match self.chunks.back() {
            None => true,
            Some(c) => c.bytes.len() + bytes_len > CHUNK_SIZE,
        };

        if need_new {
            self.chunks.push_back(Chunk {
                start: self.next_offset,
                bytes: Vec::new(),
            });
        }

        let chunk = self.chunks.back_mut().expect("chunk just created");
        chunk.bytes.extend_from_slice(bytes);
        self.next_offset += bytes_len as u64;
    }

    pub fn copy_range(&self, start: u64, end: u64) -> Vec<u8> {
        if start >= end {
            return Vec::new();
        }
        let mut result = Vec::with_capacity((end - start) as usize);
        let (front, back) = self.chunks.as_slices();
        let first = front.partition_point(|c| c.start + c.bytes.len() as u64 <= start);
        for chunk in front
            .iter()
            .skip(first)
            .take_while(|c| c.start < end)
            .chain(back.iter().take_while(|c| c.start < end))
        {
            let local_start = start.saturating_sub(chunk.start) as usize;
            let local_end = ((end - chunk.start) as usize).min(chunk.bytes.len());
            if local_start < local_end {
                result.extend_from_slice(&chunk.bytes[local_start..local_end]);
            }
        }
        result
    }

    pub fn drop_before(&mut self, offset: u64) {
        while let Some(front) = self.chunks.front() {
            let chunk_end = front.start + front.bytes.len() as u64;
            if chunk_end <= offset {
                self.chunks.pop_front();
            } else {
                break;
            }
        }
    }

    pub fn trim_front_to(&mut self, offset: u64) {
        self.drop_before(offset);
        if let Some(front) = self.chunks.front_mut() {
            if front.start < offset {
                let cut = ((offset - front.start) as usize).min(front.bytes.len());
                front.bytes.drain(..cut);
                front.start += cut as u64;
            }
        }
    }

    pub fn truncate_to(&mut self, offset: u64) {
        while self
            .chunks
            .back()
            .is_some_and(|chunk| chunk.start >= offset)
        {
            self.chunks.pop_back();
        }
        if let Some(back) = self.chunks.back_mut() {
            let keep = ((offset - back.start) as usize).min(back.bytes.len());
            back.bytes.truncate(keep);
        }
        self.next_offset = offset;
    }

    pub fn note_reuse(&mut self, cut: u64) {
        self.truncations += 1;
        while self.cuts.last().is_some_and(|&(_, lower)| lower >= cut) {
            self.cuts.pop();
        }
        self.cuts.push((self.truncations, cut));
        let start = self.start_offset();
        let trimmed = self.cuts.partition_point(|&(_, lower)| lower < start);
        if trimmed > 1 {
            let oldest = self.cuts[0].1;
            self.cuts.drain(..trimmed - 1);
            self.cuts[0].1 = oldest;
        }
    }

    pub fn lowest_cut_since(&self, seen: u64) -> Option<u64> {
        let first = self.cuts.partition_point(|&(count, _)| count <= seen);
        self.cuts.get(first).map(|&(_, cut)| cut)
    }

    pub fn truncations(&self) -> u64 {
        self.truncations
    }

    pub fn resident_bytes(&self) -> usize {
        self.chunks.iter().map(|chunk| chunk.bytes.len()).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copy_range_spans_chunks() {
        let mut c = Content::new();
        for _ in 0..3000 {
            c.push_char("a");
        }
        for _ in 0..3000 {
            c.push_char("b");
        }
        let r = c.copy_range(2990, 3002);
        assert_eq!(
            r,
            vec![b'a'; 10]
                .into_iter()
                .chain(vec![b'b'; 2])
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn drop_before_removes_only_complete_chunks() {
        let mut c = Content::new();
        for _ in 0..5000 {
            c.push_char("x");
        }
        c.drop_before(4096);
        let r = c.copy_range(4096, 5000);
        assert_eq!(r.len(), 904);
        assert!(r.iter().all(|b| *b == b'x'));
    }

    #[test]
    fn push_char_starts_new_chunk_at_boundary() {
        let mut c = Content::new();
        for _ in 0..4095 {
            c.push_char("a");
        }
        c.push_char("界");
        assert_eq!(c.end_offset(), 4095 + 3);
    }

    #[test]
    fn prepend_allocates_below_the_current_start() {
        let mut c = Content::with_base(1024);
        c.push_char("b");
        let start = c.prepend(b"aa");
        assert_eq!(start, 1022);
        assert_eq!(c.start_offset(), 1022);
        assert_eq!(c.copy_range(1022, 1025), b"aab");
    }

    #[test]
    fn two_prepends_stay_offset_ordered() {
        let mut c = Content::with_base(1024);
        c.push_char("c");
        let second = c.prepend(b"b");
        let first = c.prepend(b"a");
        assert!(first < second);
        assert_eq!(c.copy_range(first, c.end_offset()), b"abc");
    }

    #[test]
    fn drop_before_still_releases_only_whole_chunks_after_a_prepend() {
        let mut c = Content::with_base(1024);
        c.push_char("z");
        let start = c.prepend(b"yy");
        c.drop_before(start + 2);
        assert_eq!(c.start_offset(), 1024);
        assert_eq!(c.copy_range(1024, 1025), b"z");
    }

    #[test]
    fn trim_front_to_cuts_into_the_front_chunk_so_a_prepend_abuts_the_first_row() {
        let mut c = Content::with_base(1024);
        for _ in 0..10 {
            c.push_char("x");
        }
        c.trim_front_to(1030);
        assert_eq!(c.start_offset(), 1030);
        assert_eq!(c.resident_bytes(), 4);
        let start = c.prepend(b"ab");
        assert_eq!(start, 1028);
        assert_eq!(c.copy_range(1028, 1034), b"abxxxx");
    }

    #[test]
    fn truncate_to_drops_the_tail_and_the_next_push_lands_at_the_cut() {
        let mut c = Content::with_base(1024);
        for _ in 0..(CHUNK_SIZE + 10) {
            c.push_char("x");
        }
        c.truncate_to(1030);
        assert_eq!(c.end_offset(), 1030);
        assert_eq!(c.resident_bytes(), 6);
        c.push_char("y");
        assert_eq!(c.copy_range(1024, 1031), b"xxxxxxy");
    }

    #[test]
    fn truncate_to_the_start_empties_a_prepended_content() {
        let mut c = Content::with_base(1024);
        c.push_char("z");
        let start = c.prepend(b"ab");
        c.truncate_to(start);
        assert_eq!(c.resident_bytes(), 0);
        assert_eq!(c.start_offset(), start);
        assert_eq!(c.end_offset(), start);
    }

    #[test]
    fn the_lowest_cut_since_a_count_covers_every_later_reuse_only() {
        let mut c = Content::with_base(1024);
        assert_eq!(c.lowest_cut_since(0), None);
        c.note_reuse(2000);
        c.note_reuse(1500);
        c.note_reuse(1800);
        assert_eq!(c.truncations(), 3);
        assert_eq!(c.lowest_cut_since(0), Some(1500));
        assert_eq!(c.lowest_cut_since(1), Some(1500));
        assert_eq!(c.lowest_cut_since(2), Some(1800));
        assert_eq!(c.lowest_cut_since(3), None);
    }

    #[test]
    fn the_cut_list_stays_bounded_over_alternating_cuts_and_front_trims() {
        let mut c = Content::with_base(1024);
        let mut cuts = Vec::new();
        for _ in 0..1000 {
            for _ in 0..100 {
                c.push_char("a");
            }
            c.truncate_to(c.end_offset() - 10);
            c.note_reuse(c.end_offset());
            cuts.push(c.end_offset());
            c.trim_front_to(c.end_offset() - 20);
        }
        assert!(c.cuts.len() <= 3, "{} cuts", c.cuts.len());
        let count = c.truncations();
        assert_eq!(c.lowest_cut_since(count), None);
        assert_eq!(c.lowest_cut_since(count - 1), cuts.last().copied());
        for seen in 0..count - 1 {
            assert!(c.lowest_cut_since(seen).unwrap() < c.start_offset());
        }
        assert_eq!(c.lowest_cut_since(0), Some(cuts[0]));
    }

    #[test]
    fn trim_front_to_below_the_start_changes_nothing() {
        let mut c = Content::with_base(1024);
        c.push_char("q");
        c.trim_front_to(1000);
        assert_eq!(c.start_offset(), 1024);
        assert_eq!(c.copy_range(1024, 1025), b"q");
    }
}
