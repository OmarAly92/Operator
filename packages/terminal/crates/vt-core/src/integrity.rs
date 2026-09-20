use crate::parser::Parser;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IntegrityError {
    RowOutsideContent { row: usize },
    RowsNotContiguous { row: usize },
    OpenRowDetached,
    WrappedRowEmpty { row: usize },
    BlockPastEnd { block: usize },
    NextRowPastEnd,
    StyleKeyOutsideContent { offset: u64 },
}

impl Parser {
    pub(crate) fn verify_integrity(&self) -> Result<(), IntegrityError> {
        let content_start = self.content().start_offset();
        let content_end = self.content().end_offset();
        let completed = self.rows().completed();
        let mut previous_end: Option<u64> = None;
        for (row, range) in completed.iter().enumerate() {
            if range.start > range.end || range.start < content_start || range.end > content_end {
                return Err(IntegrityError::RowOutsideContent { row });
            }
            if let Some(end) = previous_end {
                if range.start != end {
                    return Err(IntegrityError::RowsNotContiguous { row: row - 1 });
                }
            }
            if range.wrapped && range.end == range.start {
                return Err(IntegrityError::WrappedRowEmpty { row });
            }
            previous_end = Some(range.end);
        }
        if self.rows().open_start() != content_end {
            return Err(IntegrityError::OpenRowDetached);
        }
        let total_rows = completed.len() + self.screen().rows();
        let closed = self.grid().len() - usize::from(self.grid().has_open_block());
        for (index, block) in self.grid().blocks().enumerate() {
            let end = if index < closed {
                block.first_row + block.row_count
            } else {
                block.first_row
            };
            if end > total_rows || block.first_row > total_rows {
                return Err(IntegrityError::BlockPastEnd { block: index });
            }
        }
        if self.grid().next_row() > total_rows {
            return Err(IntegrityError::NextRowPastEnd);
        }
        for offset in self.styles().keys() {
            if offset < content_start || offset > content_end {
                return Err(IntegrityError::StyleKeyOutsideContent { offset });
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::block::BlockState;
    use crate::parser::Parser;
    use crate::row_index::RowRange;
    use vte::Parser as VteParser;

    fn parser_with(text: &[u8]) -> Parser {
        let mut parser = Parser::new(20);
        parser.resize(20, 1);
        let mut vte = VteParser::new();
        vte.advance(&mut parser, text);
        parser.commit_evicted();
        parser
    }

    #[test]
    fn a_healthy_parser_passes() {
        let parser = parser_with(b"one\r\ntwo\r\nthree\r\n");
        assert_eq!(parser.verify_integrity(), Ok(()));
    }

    #[test]
    fn a_row_past_the_content_end_is_reported() {
        let mut parser = parser_with(b"one\r\ntwo\r\n");
        let end = parser.content().end_offset();
        parser.rows_mut().completed_mut()[1].end = end + 5;
        assert_eq!(
            parser.verify_integrity(),
            Err(IntegrityError::RowOutsideContent { row: 1 })
        );
    }

    #[test]
    fn a_gap_between_rows_is_reported() {
        let mut parser = parser_with(b"one\r\ntwo\r\n");
        parser.rows_mut().completed_mut()[1].start += 1;
        assert_eq!(
            parser.verify_integrity(),
            Err(IntegrityError::RowsNotContiguous { row: 0 })
        );
    }

    #[test]
    fn a_wrapped_row_with_no_bytes_is_reported() {
        let mut parser = parser_with(b"one\r\n");
        let end = parser.content().end_offset();
        parser.rows_mut().completed_mut().push_back(RowRange {
            start: end,
            end,
            wrapped: true,
            indent: 0,
        });
        assert_eq!(
            parser.verify_integrity(),
            Err(IntegrityError::WrappedRowEmpty { row: 1 })
        );
    }

    #[test]
    fn a_block_that_starts_above_the_previous_one_is_not_an_error() {
        let mut parser = parser_with(b"one\r\ntwo\r\nthree\r\n");
        parser
            .grid_mut()
            .push_synthetic(0, 2, BlockState::Finished, Some(0));
        parser
            .grid_mut()
            .push_synthetic(1, 3, BlockState::Finished, Some(0));
        assert_eq!(parser.verify_integrity(), Ok(()));
    }

    #[test]
    fn a_block_past_the_last_row_is_reported() {
        let mut parser = parser_with(b"one\r\n");
        parser
            .grid_mut()
            .push_synthetic(0, 500, BlockState::Finished, Some(0));
        assert_eq!(
            parser.verify_integrity(),
            Err(IntegrityError::BlockPastEnd { block: 0 })
        );
    }

    #[test]
    fn a_style_key_before_the_content_start_is_reported() {
        let mut parser = parser_with(b"\x1b[31mred\x1b[0m plain\r\n");
        parser.styles_mut().insert_key_for_test(u64::MAX - 1);
        assert_eq!(
            parser.verify_integrity(),
            Err(IntegrityError::StyleKeyOutsideContent {
                offset: u64::MAX - 1
            })
        );
    }
}
