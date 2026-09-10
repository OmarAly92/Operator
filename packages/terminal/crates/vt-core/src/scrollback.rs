use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::screen::Cell;
use crate::style::CellStyle;

pub(crate) fn commit_row(
    cells: &[Cell],
    wrapped: bool,
    content: &mut Content,
    rows: &mut RowIndex,
    styles: &mut AttributeMap<CellStyle>,
) {
    let width = if wrapped {
        cells.len()
    } else {
        cells
            .iter()
            .rposition(|cell| !cell.is_blank())
            .map_or(0, |index| index + 1)
    };
    for cell in &cells[..width] {
        if cell.ch == '\0' {
            continue;
        }
        styles.set_from(content.end_offset(), cell.style);
        let mut buffer = [0u8; 4];
        content.push_char(cell.text(&mut buffer));
    }
    rows.complete_row(content.end_offset(), wrapped);
}

#[cfg(test)]
mod tests {
    use super::commit_row;
    use crate::attribute_map::AttributeMap;
    use crate::content::Content;
    use crate::row_index::RowIndex;
    use crate::screen::Cell;
    use crate::style::{CellStyle, StyleCode};

    fn row(text: &str, width: usize) -> Vec<Cell> {
        let mut cells = vec![Cell::BLANK; width];
        for (index, ch) in text.chars().enumerate() {
            cells[index] = Cell::new(ch, CellStyle::DEFAULT);
        }
        cells
    }

    fn commit(cells: &[Cell]) -> (Content, RowIndex, AttributeMap<CellStyle>) {
        commit_with(cells, false)
    }

    fn commit_with(cells: &[Cell], wrapped: bool) -> (Content, RowIndex, AttributeMap<CellStyle>) {
        let mut content = Content::new();
        let mut rows = RowIndex::new(0);
        let mut styles = AttributeMap::new(CellStyle::DEFAULT);
        commit_row(cells, wrapped, &mut content, &mut rows, &mut styles);
        (content, rows, styles)
    }

    #[test]
    fn a_wrapped_row_keeps_its_trailing_blanks() {
        let (content, rows, _) = commit_with(&row("hi", 4), true);
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), b"hi  ");
        assert!(range.wrapped);
    }

    #[test]
    fn trailing_blanks_are_dropped() {
        let (content, rows, _) = commit(&row("hi", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), b"hi");
    }

    #[test]
    fn no_terminator_byte_is_written() {
        let (content, _, _) = commit(&row("hi", 40));
        assert_eq!(content.end_offset(), 2);
    }

    #[test]
    fn an_all_blank_row_commits_as_an_empty_row() {
        let (_, rows, _) = commit(&row("", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!((range.start, range.end), (0, 0));
        assert_eq!(rows.open_start(), 0);
    }

    #[test]
    fn interior_blanks_survive() {
        let (content, rows, _) = commit(&row("a b", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(content.copy_range(range.start, range.end), b"a b");
    }

    #[test]
    fn style_runs_follow_the_cells() {
        let mut cells = row("ab", 40);
        cells[0].style = CellStyle::new(StyleCode::ansi(1), StyleCode::DEFAULT_BACKGROUND);
        let (content, _, styles) = commit(&cells);
        let runs = styles.runs(0, content.end_offset());
        assert_eq!(
            runs.first().map(|(_, style)| *style),
            Some(CellStyle::new(
                StyleCode::ansi(1),
                StyleCode::DEFAULT_BACKGROUND
            ))
        );
    }

    #[test]
    fn a_multibyte_glyph_commits_whole() {
        let (content, rows, _) = commit(&row("\u{2500}", 40));
        let range = rows.completed().front().expect("one committed row");
        assert_eq!(
            content.copy_range(range.start, range.end),
            "\u{2500}".as_bytes()
        );
    }
}
