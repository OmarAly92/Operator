use crate::block::Block;

mod node;
use node::{summary_of_blocks, BlockIter, Node};

const TREE_BASE: usize = 6;
const LEAF_CAPACITY: usize = 2 * TREE_BASE;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BlockSummary {
    pub blocks: usize,
    pub rows: usize,
    pub start_row: usize,
    pub end_row: usize,
}

impl BlockSummary {
    fn of(block: &Block) -> Self {
        Self {
            blocks: 1,
            rows: block.row_count,
            start_row: block.first_row,
            end_row: block.first_row + block.row_count,
        }
    }

    fn add(self, other: Self) -> Self {
        if other.blocks == 0 {
            return self;
        }
        if self.blocks == 0 {
            return other;
        }
        Self {
            blocks: self.blocks + other.blocks,
            rows: self.rows + other.rows,
            start_row: self.start_row,
            end_row: other.end_row,
        }
    }
}

pub struct BlockTree {
    nodes: Vec<Node>,
    root: Option<usize>,
}

impl BlockTree {
    pub fn new() -> Self {
        Self {
            nodes: Vec::new(),
            root: None,
        }
    }

    pub fn len(&self) -> usize {
        self.summary().blocks
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn summary(&self) -> BlockSummary {
        match self.root {
            Some(idx) => self.nodes[idx].summary(),
            None => BlockSummary::default(),
        }
    }

    pub fn push(&mut self, block: Block) {
        if self.root.is_none() {
            let root_idx = self.alloc_node(Node::Leaf {
                summary: BlockSummary::of(&block),
                blocks: vec![block],
                parent: None,
            });
            self.root = Some(root_idx);
            return;
        }

        let path = self.find_leaf_path_for_push();
        let leaf_idx = *path.last().unwrap();
        let leaf_full = matches!(&self.nodes[leaf_idx], Node::Leaf { blocks, .. } if blocks.len() >= LEAF_CAPACITY);

        if leaf_full {
            self.push_with_split(block, &path);
        } else {
            self.append_to_leaf(leaf_idx, block);
            self.propagate_summary_up(&path);
        }

        self.propagate_from_last_leaf_to_root();
    }

    pub fn pop_front(&mut self) -> Option<Block> {
        let root = self.root?;
        let leaf_idx = self.first_leaf_idx(root);
        let removed = {
            let leaf = &mut self.nodes[leaf_idx];
            match leaf {
                Node::Leaf { blocks, .. } => {
                    if blocks.is_empty() {
                        return None;
                    }
                    blocks.remove(0)
                }
                Node::Internal { .. } => unreachable!("first_leaf_idx returned an internal node"),
            }
        };
        self.recompute_summary(leaf_idx);
        let leaf_now_empty =
            matches!(&self.nodes[leaf_idx], Node::Leaf { blocks, .. } if blocks.is_empty());
        let path_to_root = self.path_to_root(leaf_idx);
        if leaf_now_empty && self.root != Some(leaf_idx) {
            self.collapse_or_remove_leaf(leaf_idx);
        }
        self.propagate_summary_up(&path_to_root);
        self.propagate_from_first_leaf_to_root();
        Some(removed)
    }

    pub fn find_by_row(&self, row: usize) -> Option<&Block> {
        let root = self.root?;
        let root_summary = self.nodes[root].summary();
        if row < root_summary.start_row || row >= root_summary.end_row {
            return None;
        }
        let mut idx = root;
        loop {
            match &self.nodes[idx] {
                Node::Internal { .. } => {
                    idx = self.descend_for_row(idx, row);
                }
                Node::Leaf { blocks, .. } => {
                    for block in blocks {
                        if row >= block.first_row && row < block.first_row + block.row_count {
                            return Some(block);
                        }
                    }
                    return None;
                }
            }
        }
    }

    pub fn get(&self, index: usize) -> Option<&Block> {
        let root = self.root?;
        let total = self.nodes[root].summary().blocks;
        if index >= total {
            return None;
        }
        let mut idx = root;
        let mut remaining = index;
        loop {
            match &self.nodes[idx] {
                Node::Internal { children, .. } => {
                    let mut next = None;
                    for &child_idx in children {
                        let child_blocks = self.nodes[child_idx].summary().blocks;
                        if remaining < child_blocks {
                            next = Some(child_idx);
                            break;
                        }
                        remaining -= child_blocks;
                    }
                    idx = next?;
                }
                Node::Leaf { blocks, .. } => {
                    return blocks.get(remaining);
                }
            }
        }
    }

    pub fn iter(&self) -> BlockIter<'_> {
        BlockIter {
            nodes: &self.nodes,
            leaf_idx: self.first_leaf(),
            cursor: 0,
        }
    }

    fn first_leaf(&self) -> Option<usize> {
        self.root.map(|r| self.first_leaf_idx(r))
    }

    fn first_leaf_idx(&self, start: usize) -> usize {
        let mut idx = start;
        loop {
            match &self.nodes[idx] {
                Node::Leaf { .. } => return idx,
                Node::Internal { children, .. } => idx = children[0],
            }
        }
    }

    fn last_leaf_idx(&self, start: usize) -> usize {
        let mut idx = start;
        loop {
            match &self.nodes[idx] {
                Node::Leaf { .. } => return idx,
                Node::Internal { children, .. } => idx = *children.last().unwrap(),
            }
        }
    }

    fn propagate_from_last_leaf_to_root(&mut self) {
        let Some(root) = self.root else {
            return;
        };
        let last_leaf = self.last_leaf_idx(root);
        let path = self.path_to_root(last_leaf);
        self.propagate_summary_up(&path);
    }

    fn propagate_from_first_leaf_to_root(&mut self) {
        let Some(root) = self.root else {
            return;
        };
        let first_leaf = self.first_leaf_idx(root);
        let path = self.path_to_root(first_leaf);
        self.propagate_summary_up(&path);
    }

    fn path_to_root(&self, leaf_idx: usize) -> Vec<usize> {
        let mut path = vec![leaf_idx];
        let mut current = leaf_idx;
        loop {
            let parent = match &self.nodes[current] {
                Node::Leaf { parent, .. } => *parent,
                Node::Internal { parent, .. } => *parent,
            };
            match parent {
                Some(p) => {
                    path.push(p);
                    current = p;
                }
                None => break,
            }
        }
        path
    }

    fn set_parent(&mut self, child: usize, parent: usize) {
        match &mut self.nodes[child] {
            Node::Leaf { parent: p, .. } => *p = Some(parent),
            Node::Internal { parent: p, .. } => *p = Some(parent),
        }
    }

    fn propagate_summary_up(&mut self, ancestors: &[usize]) {
        for &idx in ancestors {
            self.recompute_summary(idx);
        }
    }

    fn descend_for_row(&self, parent: usize, row: usize) -> usize {
        let children = match &self.nodes[parent] {
            Node::Internal { children, .. } => children,
            Node::Leaf { .. } => unreachable!("descend_for_row called on leaf"),
        };
        for (i, &child_idx) in children.iter().enumerate() {
            let child_summary = self.nodes[child_idx].summary();
            if row < child_summary.end_row {
                if row < child_summary.start_row {
                    return children[i.saturating_sub(1)];
                }
                return child_idx;
            }
        }
        *children.last().unwrap()
    }

    fn find_leaf_path_for_push(&self) -> Vec<usize> {
        let mut path = Vec::new();
        let mut idx = self.root.expect("root exists");
        path.push(idx);
        loop {
            match &self.nodes[idx] {
                Node::Leaf { .. } => break,
                Node::Internal { children, .. } => {
                    idx = *children.last().expect("internal node has children");
                    path.push(idx);
                }
            }
        }
        path
    }

    fn append_to_leaf(&mut self, leaf_idx: usize, block: Block) {
        let added = BlockSummary::of(&block);
        match &mut self.nodes[leaf_idx] {
            Node::Leaf {
                summary, blocks, ..
            } => {
                *summary = summary.add(added);
                blocks.push(block);
            }
            Node::Internal { .. } => unreachable!("append_to_leaf called on internal node"),
        }
    }

    fn push_with_split(&mut self, block: Block, path: &[usize]) {
        let leaf_idx = *path.last().unwrap();
        let (left_blocks, right_blocks) = {
            let leaf = &mut self.nodes[leaf_idx];
            match leaf {
                Node::Leaf { blocks, .. } => {
                    blocks.push(block);
                    let mid = blocks.len() / 2;
                    let right: Vec<Block> = blocks.drain(mid..).collect();
                    let left = std::mem::take(blocks);
                    (left, right)
                }
                Node::Internal { .. } => unreachable!(),
            }
        };

        let left_summary = summary_of_blocks(&left_blocks);
        let right_summary = summary_of_blocks(&right_blocks);

        let new_leaf = self.alloc_node(Node::Leaf {
            summary: right_summary,
            blocks: right_blocks,
            parent: None,
        });

        {
            let leaf = &mut self.nodes[leaf_idx];
            if let Node::Leaf {
                blocks, summary, ..
            } = leaf
            {
                *blocks = left_blocks;
                *summary = left_summary;
            }
        }

        if path.len() == 1 {
            let new_root = self.alloc_node(Node::Internal {
                summary: left_summary.add(right_summary),
                children: vec![leaf_idx, new_leaf],
                parent: None,
            });
            self.set_parent(leaf_idx, new_root);
            self.set_parent(new_leaf, new_root);
            self.root = Some(new_root);
        } else {
            self.insert_into_parent(leaf_idx, new_leaf, &path[..path.len() - 1]);
        }
    }

    fn insert_into_parent(&mut self, left_idx: usize, right_idx: usize, path: &[usize]) {
        let parent_idx = *path.last().unwrap();
        let parent_full = matches!(&self.nodes[parent_idx], Node::Internal { children, .. } if children.len() >= 2 * TREE_BASE);

        if !parent_full {
            let added = self.nodes[right_idx].summary();
            match &mut self.nodes[parent_idx] {
                Node::Internal {
                    summary, children, ..
                } => {
                    let pos = children.iter().position(|c| *c == left_idx).unwrap();
                    children.insert(pos + 1, right_idx);
                    *summary = summary.add(added);
                }
                Node::Leaf { .. } => unreachable!(),
            }
            self.set_parent(right_idx, parent_idx);
            return;
        }

        let mut children: Vec<usize> = match &self.nodes[parent_idx] {
            Node::Internal { children, .. } => children.clone(),
            Node::Leaf { .. } => unreachable!(),
        };
        let pos = children.iter().position(|c| *c == left_idx).unwrap();
        children.insert(pos + 1, right_idx);

        let mid = children.len() / 2;
        let new_children: Vec<usize> = children.drain(mid..).collect();
        let keep_children = children;
        let new_summary: BlockSummary = new_children
            .iter()
            .map(|i| self.nodes[*i].summary())
            .fold(BlockSummary::default(), |a, s| a.add(s));
        let keep_summary: BlockSummary = keep_children
            .iter()
            .map(|i| self.nodes[*i].summary())
            .fold(BlockSummary::default(), |a, s| a.add(s));

        {
            let parent = &mut self.nodes[parent_idx];
            if let Node::Internal {
                summary, children, ..
            } = parent
            {
                *summary = keep_summary;
                *children = keep_children;
            }
        }

        let new_internal_idx = self.nodes.len();
        for &c in &new_children {
            self.set_parent(c, new_internal_idx);
        }
        let new_internal = self.alloc_node(Node::Internal {
            summary: new_summary,
            children: new_children,
            parent: None,
        });

        if path.len() == 1 {
            let new_root = self.alloc_node(Node::Internal {
                summary: keep_summary.add(new_summary),
                children: vec![parent_idx, new_internal],
                parent: None,
            });
            self.set_parent(parent_idx, new_root);
            self.set_parent(new_internal, new_root);
            self.root = Some(new_root);
        } else {
            self.insert_into_parent(parent_idx, new_internal, &path[..path.len() - 1]);
        }
    }

    fn collapse_or_remove_leaf(&mut self, leaf_idx: usize) {
        let parent_idx = match &self.nodes[leaf_idx] {
            Node::Leaf { parent, .. } => *parent,
            Node::Internal { parent, .. } => *parent,
        };
        let Some(parent_idx) = parent_idx else {
            return;
        };
        let pos = {
            let parent = &self.nodes[parent_idx];
            match parent {
                Node::Internal { children, .. } => {
                    children.iter().position(|c| *c == leaf_idx).unwrap()
                }
                Node::Leaf { .. } => unreachable!(),
            }
        };

        match &mut self.nodes[parent_idx] {
            Node::Internal { children, .. } => {
                children.remove(pos);
            }
            Node::Leaf { .. } => unreachable!(),
        }
        self.recompute_summary(parent_idx);

        let parent_now_empty = matches!(&self.nodes[parent_idx], Node::Internal { children, .. } if children.is_empty());
        if parent_now_empty {
            if self.root == Some(parent_idx) {
                self.root = None;
            } else {
                self.collapse_or_remove_leaf(parent_idx);
            }
        } else if self.root == Some(parent_idx) {
            let only_one_child = matches!(&self.nodes[parent_idx], Node::Internal { children, .. } if children.len() == 1);
            if only_one_child {
                let only_child = match &self.nodes[parent_idx] {
                    Node::Internal { children, .. } => children[0],
                    Node::Leaf { .. } => unreachable!(),
                };
                match &mut self.nodes[only_child] {
                    Node::Leaf { parent, .. } => *parent = None,
                    Node::Internal { parent, .. } => *parent = None,
                }
                self.root = Some(only_child);
            }
        }
    }

    fn recompute_summary(&mut self, idx: usize) {
        let new_summary = match &self.nodes[idx] {
            Node::Leaf { blocks, .. } => summary_of_blocks(blocks),
            Node::Internal { children, .. } => {
                let mut s = BlockSummary::default();
                for &c in children {
                    s = s.add(self.nodes[c].summary());
                }
                s
            }
        };
        match &mut self.nodes[idx] {
            Node::Leaf { summary, .. } => *summary = new_summary,
            Node::Internal { summary, .. } => *summary = new_summary,
        }
    }

    fn alloc_node(&mut self, node: Node) -> usize {
        let idx = self.nodes.len();
        self.nodes.push(node);
        idx
    }
}

impl Default for BlockTree {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::block::{BlockId, BlockMeta, BlockSource, BlockState};

    fn block(id: BlockId, first_row: usize, row_count: usize) -> Block {
        Block {
            id,
            first_row,
            row_count,
            state: BlockState::Finished,
            source: BlockSource::Osc133,
            meta: BlockMeta::default(),
        }
    }

    #[test]
    fn summary_matches_a_naive_recomputation_after_any_mutation() {
        let mut tree = BlockTree::new();
        for index in 0..500usize {
            tree.push(block(index as u64, index * 3, 3));
        }
        for _ in 0..137 {
            tree.pop_front();
        }
        let naive_rows: usize = tree.iter().map(|b| b.row_count).sum();
        assert_eq!(tree.summary().rows, naive_rows);
        assert_eq!(tree.summary().blocks, tree.len());
        assert_eq!(tree.len(), 363);
    }

    #[test]
    fn find_by_row_returns_the_block_containing_that_row() {
        let mut tree = BlockTree::new();
        tree.push(block(1, 0, 4));
        tree.push(block(2, 4, 1));
        tree.push(block(3, 5, 10));

        assert_eq!(tree.find_by_row(0).map(|b| b.id), Some(1));
        assert_eq!(tree.find_by_row(3).map(|b| b.id), Some(1));
        assert_eq!(tree.find_by_row(4).map(|b| b.id), Some(2));
        assert_eq!(tree.find_by_row(14).map(|b| b.id), Some(3));
        assert_eq!(tree.find_by_row(15).map(|b| b.id), None);
    }

    #[test]
    fn find_by_row_is_correct_after_front_removal() {
        let mut tree = BlockTree::new();
        tree.push(block(1, 0, 4));
        tree.push(block(2, 4, 6));
        tree.pop_front();
        assert_eq!(tree.find_by_row(4).map(|b| b.id), Some(2));
        assert_eq!(tree.find_by_row(0).map(|b| b.id), None);
    }

    #[test]
    fn an_empty_tree_has_a_zero_summary() {
        let tree = BlockTree::new();
        assert_eq!(tree.len(), 0);
        assert_eq!(tree.summary(), BlockSummary::default());
        assert!(tree.find_by_row(0).is_none());
    }

    #[test]
    fn a_hundred_thousand_blocks_answer_row_queries_without_scanning() {
        let mut tree = BlockTree::new();
        for index in 0..100_000usize {
            tree.push(block(index as u64, index, 1));
        }
        assert_eq!(tree.find_by_row(99_999).map(|b| b.id), Some(99_999));
        assert_eq!(tree.summary().rows, 100_000);
    }
}
