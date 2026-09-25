use std::collections::BTreeMap;

pub(crate) struct AttributeMap<A: Copy> {
    ends: BTreeMap<u64, A>,
    tail: A,
    run_start: u64,
}

impl<A: Copy + Eq> AttributeMap<A> {
    #[cfg(test)]
    pub fn new(initial: A) -> Self {
        Self {
            ends: BTreeMap::new(),
            tail: initial,
            run_start: 0,
        }
    }

    pub fn with_base(initial: A, base: u64) -> Self {
        Self {
            ends: BTreeMap::new(),
            tail: initial,
            run_start: base,
        }
    }

    pub fn prepend_runs(&mut self, runs: &[(u64, A)]) {
        for (end, value) in runs {
            self.ends.insert(*end, *value);
        }
    }

    #[cfg(test)]
    pub fn tail(&self) -> A {
        self.tail
    }

    pub fn set_from(&mut self, offset: u64, value: A) {
        if value == self.tail {
            return;
        }
        if offset <= self.run_start {
            self.tail = value;
            return;
        }
        self.ends.insert(offset, self.tail);
        self.run_start = offset;
        self.tail = value;
    }

    pub fn runs(&self, start: u64, end: u64) -> Vec<(u32, A)> {
        if start >= end {
            return Vec::new();
        }
        let mut result = Vec::new();
        let mut cursor = start;
        for (&k, &v) in self.ends.range((start + 1)..end) {
            result.push(((k - start) as u32, v));
            cursor = k;
        }
        let final_value = match self.ends.range((cursor + 1)..).next() {
            Some((_, v)) => *v,
            None => self.tail,
        };
        result.push(((end - start) as u32, final_value));
        result
    }

    pub fn truncate_to(&mut self, offset: u64) {
        let cut = self.ends.split_off(&offset);
        if let Some(value) = cut.values().next() {
            self.tail = *value;
        }
        self.run_start = self.ends.keys().next_back().copied().unwrap_or(0);
    }

    pub fn drop_before(&mut self, offset: u64) {
        let to_drop: Vec<u64> = self.ends.range(..offset).map(|(k, _)| *k).collect();
        for k in to_drop {
            self.ends.remove(&k);
        }
    }

    pub fn keys(&self) -> impl Iterator<Item = u64> + '_ {
        self.ends.keys().copied()
    }

    pub fn len(&self) -> usize {
        self.ends.len()
    }

    pub fn byte_len(&self) -> usize {
        self.ends.len() * (std::mem::size_of::<u64>() + std::mem::size_of::<A>())
    }

    #[cfg(test)]
    pub(crate) fn insert_key_for_test(&mut self, offset: u64) {
        self.ends.insert(offset, self.tail);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn runs(map: &AttributeMap<u32>, start: u64, end: u64) -> Vec<(u32, u32)> {
        map.runs(start, end)
    }

    #[test]
    fn set_from_at_offset_zero_just_changes_tail() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        assert_eq!(m.tail(), 1);
        assert_eq!(runs(&m, 0, 5), vec![(5, 1)]);
    }

    #[test]
    fn set_from_advances_with_insert() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 0);
        assert_eq!(runs(&m, 0, 9), vec![(3, 1), (9, 0)]);
    }

    #[test]
    fn set_from_coalesces_equal_value() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 1);
        m.set_from(5, 0);
        assert_eq!(runs(&m, 0, 9), vec![(5, 1), (9, 0)]);
    }

    #[test]
    fn runs_at_multibyte_scalar_boundary() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(5, 0);
        m.set_from(7, 1);
        m.set_from(11, 0);
        assert_eq!(runs(&m, 0, 13), vec![(5, 1), (7, 0), (11, 1), (13, 0)]);
    }

    #[test]
    fn runs_ending_exactly_at_row_length() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        assert_eq!(runs(&m, 0, 9), vec![(9, 1)]);
    }

    #[test]
    fn drop_before_removes_early_ends() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 0);
        m.set_from(7, 1);
        m.drop_before(5);
        assert_eq!(runs(&m, 5, 9), vec![(2, 0), (4, 1)]);
    }

    #[test]
    fn equal_value_no_op_does_not_advance_run_start() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 1);
        assert_eq!(m.tail(), 1);
        m.set_from(5, 0);
        assert_eq!(runs(&m, 0, 9), vec![(5, 1), (9, 0)]);
    }

    #[test]
    fn truncate_to_keeps_the_value_of_the_last_kept_byte() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 2);
        m.set_from(7, 0);
        m.truncate_to(5);
        assert_eq!(runs(&m, 0, 5), vec![(3, 1), (5, 2)]);
        m.set_from(5, 4);
        assert_eq!(runs(&m, 0, 8), vec![(3, 1), (5, 2), (8, 4)]);
    }

    #[test]
    fn truncate_to_at_a_run_end_then_the_same_value_extends_it() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 0);
        m.truncate_to(3);
        assert_eq!(runs(&m, 0, 3), vec![(3, 1)]);
        m.set_from(3, 1);
        assert_eq!(runs(&m, 0, 6), vec![(6, 1)]);
    }

    #[test]
    fn prepended_runs_read_back_in_their_own_region() {
        let mut map = AttributeMap::with_base(0u8, 100);
        map.set_from(100, 7);
        map.set_from(102, 9);
        map.prepend_runs(&[(98, 3u8), (100, 4u8)]);
        assert_eq!(map.runs(96, 100), vec![(2, 3u8), (4, 4u8)]);
        assert_eq!(map.runs(100, 102), vec![(2, 7u8)]);
    }
}
