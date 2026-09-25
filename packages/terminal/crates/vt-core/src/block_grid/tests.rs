use super::*;

#[test]
fn opening_a_block_closes_the_previous_one_as_abandoned() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.open_block(BlockSource::Osc133);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks[0].state, BlockState::Abandoned);
    assert_eq!(blocks[1].state, BlockState::Running);
}

#[test]
fn closing_records_the_exit_code_and_marks_finished() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.close_block(Some(3));
    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks[0].state, BlockState::Finished);
    assert_eq!(blocks[0].meta.exit_code, Some(3));
}

#[test]
fn closing_with_no_open_block_is_ignored() {
    let mut grid = BlockGrid::new();
    grid.close_block(Some(0));
    assert_eq!(grid.blocks().count(), 0);
}

#[test]
fn trimming_drops_blocks_whose_rows_are_all_gone() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.note_row_completed();
    grid.close_block(Some(0));
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();

    grid.advance_origin(2);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 1);
    assert_eq!(
        blocks[0].first_row, 2,
        "the open block keeps its stable row"
    );
    assert_eq!(grid.flat_extent(blocks[0]), (0, 1));
    assert_eq!(grid.origin(), 2);
}

#[test]
fn a_partially_trimmed_block_keeps_its_surviving_rows() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    for _ in 0..5 {
        grid.note_row_completed();
    }
    grid.advance_origin(2);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].first_row, 0);
    assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
}

#[test]
fn extension_fields_upgrade_the_open_block_source() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.set_meta_field("cmd", "git status");
    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks[0].source, BlockSource::Extension);
    assert_eq!(blocks[0].meta.command, "git status");
}

#[test]
fn trim_inside_a_closed_block_does_not_underflow() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    for _ in 0..5 {
        grid.note_row_completed();
    }
    grid.close_block(Some(0));
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.advance_origin(2);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 2);
    assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
    assert_eq!(grid.flat_extent(blocks[1]), (3, 1));
}

#[test]
fn trim_after_popping_all_closed_blocks_keeps_open_block_rows() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.note_row_completed();
    grid.close_block(Some(0));
    grid.open_block(BlockSource::Osc133);
    for _ in 0..6 {
        grid.note_row_completed();
    }
    grid.advance_origin(5);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 1);
    assert_eq!(
        grid.flat_extent(blocks[0]),
        (0, 3),
        "rows 5..8 of the open block survive (pre-trim pos 2, 6 rows)"
    );
}

#[test]
fn partial_trim_rebases_an_open_block_after_an_unmarked_prefix() {
    let mut grid = BlockGrid::new();
    grid.sync_next_row(2);
    grid.open_block(BlockSource::Osc133);
    for _ in 0..6 {
        grid.note_row_completed();
    }

    grid.advance_origin(5);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!(blocks.len(), 1);
    assert_eq!(grid.flat_extent(blocks[0]), (0, 3));
}

#[test]
fn remapping_rows_moves_every_block_with_the_rows_it_owns() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.note_row_completed();
    grid.close_block(Some(0));
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();

    grid.remap_rows(&[0, 3, 4, 6]);

    let blocks: Vec<_> = grid.blocks().collect();
    assert_eq!((blocks[0].first_row, blocks[0].row_count), (0, 4));
    assert_eq!(blocks[1].first_row, 4);
    assert_eq!(grid.next_row, 6);
}

#[test]
fn remapping_rows_shifts_a_block_that_starts_on_the_screen() {
    let mut grid = BlockGrid::new();
    grid.sync_next_row(5);
    grid.open_block(BlockSource::Osc133);

    grid.remap_rows(&[0, 2, 4]);

    assert_eq!(grid.blocks().next().unwrap().first_row, 7);
}

#[test]
fn bookmark_round_trips_through_close() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    grid.note_row_completed();
    grid.close_block(Some(0));
    let id = grid.blocks().next().unwrap().id;
    assert!(!grid.block_bookmarked(id), "fresh block is not bookmarked");
    grid.set_block_bookmarked(id, true);
    assert!(grid.block_bookmarked(id), "the close keeps the bookmark");
    grid.set_block_bookmarked(id, false);
    assert!(!grid.block_bookmarked(id), "the bookmark clears");
}

#[test]
fn bookmark_round_trips_through_open() {
    let mut grid = BlockGrid::new();
    grid.open_block(BlockSource::Osc133);
    let id = grid.open.as_ref().unwrap().id;
    assert!(!grid.block_bookmarked(id));
    grid.set_block_bookmarked(id, true);
    assert!(grid.block_bookmarked(id), "open block can be bookmarked");
}

#[test]
fn bookmark_unknown_id_is_a_no_op() {
    let mut grid = BlockGrid::new();
    grid.set_block_bookmarked(99, true);
    assert!(!grid.block_bookmarked(99));
}

#[test]
fn retreat_origin_keeps_existing_blocks_at_their_stable_rows() {
    let mut grid = BlockGrid::new();
    grid.sync_next_row(4);
    grid.push_synthetic(0, 4, BlockState::Finished, Some(0));
    let stable_before = grid.get(0).expect("block").first_row;
    grid.retreat_origin(3);
    assert_eq!(grid.origin(), 0);
    assert_eq!(grid.get(0).expect("block").first_row, stable_before);
    assert_eq!(grid.flat_extent(grid.get(0).expect("block")), (3, 4));
}

#[test]
fn prepended_blocks_sort_before_the_existing_ones() {
    let mut grid = BlockGrid::new();
    grid.sync_next_row(2);
    grid.push_synthetic(0, 2, BlockState::Finished, Some(0));
    grid.retreat_origin(2);
    grid.prepend_blocks(vec![Block {
        id: 900,
        first_row: 0,
        row_count: 2,
        state: BlockState::Finished,
        source: BlockSource::Synthetic,
        meta: BlockMeta::default(),
    }]);
    let ids: Vec<_> = grid.blocks().map(|block| block.id).collect();
    assert_eq!(ids, vec![900, 0]);
}

#[test]
fn open_block_ref_is_the_open_block_and_nothing_after_it_closes() {
    let mut grid = BlockGrid::new();
    assert!(grid.open_block_ref().is_none());
    grid.sync_next_row(3);
    grid.open_block(BlockSource::Osc133);
    let open = grid.open_block_ref().expect("an open block");
    assert_eq!(grid.flat_extent(open).0, 3);
    grid.close_block(Some(0));
    assert!(grid.open_block_ref().is_none());
}
