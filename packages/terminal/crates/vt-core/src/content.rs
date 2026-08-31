use std::collections::VecDeque;

const CHUNK_SIZE: usize = 4096;

#[derive(Clone)]
pub(crate) struct Chunk {
    pub start: u64,
    pub bytes: Vec<u8>,
}

pub(crate) struct Content {
    chunks: VecDeque<Chunk>,
    next_offset: u64,
}

impl Clone for Content {
    fn clone(&self) -> Self {
        Self {
            chunks: self.chunks.clone(),
            next_offset: self.next_offset,
        }
    }
}

impl Content {
    pub fn new() -> Self {
        Self {
            chunks: VecDeque::new(),
            next_offset: 0,
        }
    }

    pub fn end_offset(&self) -> u64 {
        self.next_offset
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
}
