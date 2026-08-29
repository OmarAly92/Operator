use super::BlockSummary;
use crate::block::Block;

pub(super) enum Node {
    Leaf {
        summary: BlockSummary,
        blocks: Vec<Block>,
        parent: Option<usize>,
    },
    Internal {
        summary: BlockSummary,
        children: Vec<usize>,
        parent: Option<usize>,
    },
}

impl Node {
    pub(super) fn summary(&self) -> BlockSummary {
        match self {
            Node::Leaf { summary, .. } => *summary,
            Node::Internal { summary, .. } => *summary,
        }
    }
}

pub(super) fn summary_of_blocks(blocks: &[Block]) -> BlockSummary {
    let mut s = BlockSummary::default();
    for b in blocks {
        s = s.add(BlockSummary::of(b));
    }
    s
}

pub(super) fn next_leaf_after(nodes: &[Node], current: usize) -> Option<usize> {
    let mut idx = current;
    loop {
        let parent = match &nodes[idx] {
            Node::Leaf { parent, .. } => *parent,
            Node::Internal { parent, .. } => *parent,
        };
        let parent = parent?;
        let children = match &nodes[parent] {
            Node::Internal { children, .. } => children,
            Node::Leaf { .. } => unreachable!("parent of a leaf cannot be a leaf"),
        };
        let pos = children.iter().position(|c| *c == idx).unwrap();
        if let Some(&next) = children.get(pos + 1) {
            idx = next;
            break;
        }
        idx = parent;
    }
    loop {
        match &nodes[idx] {
            Node::Leaf { .. } => return Some(idx),
            Node::Internal { children, .. } => idx = children[0],
        }
    }
}

pub struct BlockIter<'a> {
    pub(super) nodes: &'a [Node],
    pub(super) leaf_idx: Option<usize>,
    pub(super) cursor: usize,
}

impl<'a> Iterator for BlockIter<'a> {
    type Item = &'a Block;

    fn next(&mut self) -> Option<&'a Block> {
        loop {
            let leaf_idx = self.leaf_idx?;
            let blocks = match &self.nodes[leaf_idx] {
                Node::Leaf { blocks, .. } => blocks,
                Node::Internal { .. } => unreachable!(),
            };
            if self.cursor < blocks.len() {
                let b = &blocks[self.cursor];
                self.cursor += 1;
                return Some(b);
            }
            self.cursor = 0;
            self.leaf_idx = next_leaf_after(self.nodes, leaf_idx);
        }
    }
}
