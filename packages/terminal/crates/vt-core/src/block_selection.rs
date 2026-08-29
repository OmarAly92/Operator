use crate::block::BlockId;

/// A position inside one block. The renderer hits the screen on the
/// browser side and hands us coordinates that already carry a `BlockId`,
/// so this struct is the seam: the model never decides which block a
/// (row, column) belongs to.
///
/// `Ord` is the field-declaration order — `(block, row, column)`. The
/// block field is monotonic and blocks are appended, so lexicographic
/// comparison matches the on-screen order without consulting the tree.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct SelectionPoint {
    pub block: BlockId,
    pub row: usize,
    pub column: usize,
}

/// A user text selection expressed in block coordinates.
///
/// The struct holds at most one anchor and one head; `extend_to` is the
/// only mutator that introduces an extent. The renderer's mouse and
/// keyboard paths both call `set_anchor` first, then `extend_to` on
/// every move, so storing two points is enough — we never need to
/// thread a list of intermediate cells through the model.
///
/// Ordering is lexicographic on `(block, row, column)`. `BlockId` is
/// monotonic and blocks are appended, so comparing ids orders blocks
/// correctly without consulting the tree. `normalized` is what the
/// renderer queries when it needs to walk left-to-right, top-to-bottom.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct BlockSelection {
    anchor: Option<SelectionPoint>,
    head: Option<SelectionPoint>,
}

impl BlockSelection {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_anchor(&mut self, point: SelectionPoint) {
        self.anchor = Some(point);
    }

    pub fn extend_to(&mut self, point: SelectionPoint) {
        self.head = Some(point);
    }

    pub fn clear(&mut self) {
        self.anchor = None;
        self.head = None;
    }

    pub fn is_empty(&self) -> bool {
        // A selection with only an anchor has no extent, so it does not
        // select anything yet. `extend_to` will materialise the head.
        match (self.anchor, self.head) {
            (None, _) => true,
            (Some(_), None) => true,
            (Some(a), Some(b)) => a == b,
        }
    }

    /// `(start, end)` with `start <= end` under lexicographic order, or
    /// `None` when the selection has no extent.
    pub fn normalized(&self) -> Option<(SelectionPoint, SelectionPoint)> {
        let (anchor, head) = (self.anchor?, self.head?);
        if anchor <= head {
            Some((anchor, head))
        } else {
            Some((head, anchor))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(block: u64, row: usize, column: usize) -> SelectionPoint {
        SelectionPoint { block, row, column }
    }

    #[test]
    fn a_backwards_selection_normalizes_to_forwards() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(5, 2, 4));
        selection.extend_to(point(3, 0, 1));
        let (start, end) = selection.normalized().unwrap();
        assert_eq!(start, point(3, 0, 1));
        assert_eq!(end, point(5, 2, 4));
    }

    #[test]
    fn a_selection_within_one_block_normalizes_by_row_then_column() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 3, 9));
        selection.extend_to(point(1, 3, 2));
        let (start, end) = selection.normalized().unwrap();
        assert_eq!(start, point(1, 3, 2));
        assert_eq!(end, point(1, 3, 9));
    }

    #[test]
    fn an_anchor_with_no_extent_is_empty() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 0, 0));
        assert!(selection.is_empty());
        assert!(selection.normalized().is_none());
    }

    #[test]
    fn clear_discards_the_anchor() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 0, 0));
        selection.extend_to(point(2, 0, 0));
        selection.clear();
        assert!(selection.is_empty());
    }
}
