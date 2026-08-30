use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::row_index::RowIndex;
use crate::screen::Cell;
use crate::style::StyleCode;

pub(crate) fn commit_row(
    cells: &[Cell],
    content: &mut Content,
    rows: &mut RowIndex,
    styles: &mut AttributeMap<StyleCode>,
) {
    let width = cells
        .iter()
        .rposition(|cell| !matches!(cell.ch, ' ' | '\0'))
        .map_or(0, |index| index + 1);
    for cell in &cells[..width] {
        if cell.ch == '\0' {
            continue;
        }
        styles.set_from(content.end_offset(), cell.style);
        let mut buffer = [0u8; 4];
        content.push_char(cell.ch.encode_utf8(&mut buffer));
    }
    rows.complete_row(content.end_offset());
}

#[cfg(test)]
mod tests {
    use super::commit_row;
    use crate::attribute_map::AttributeMap;
    use crate::content::Content;
    use crate::row_index::RowIndex;
    use crate::screen::Cell;
    use crate::style::StyleCode;

    fn row(text: &str, width: usize) -> Vec<Cell> {
        let mut cells = vec![Cell::BLANK; width];
        for (index, ch) in text.chars().enumerate() {
            cells[index] = Cell {
                ch,
                style: StyleCode::DEFAULT,
            };
        }
        cells
    }

    fn commit(cells: &[Cell]) -> (Content, RowIndex, AttributeMap<StyleCode>) {
        let mut content = Content::new();
        let mut rows = RowIndex::new(0);
        let mut styles = AttributeMap::new(StyleCode::DEFAULT);
        commit_row(cells, &mut content, &mut rows, &mut styles);
        (content, rows, styles)
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
    fn an_all_blank_row_commits_as_an_empty_range() {
        let (_, rows, _) = commit(&row("", 40));
        assert_eq!(rows.completed().len(), 0);
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
        cells[0].style = StyleCode::ansi(1);
        let (content, _, styles) = commit(&cells);
        let runs = styles.runs(0, content.end_offset());
        assert_eq!(
            runs.first().map(|(_, style)| *style),
            Some(StyleCode::ansi(1))
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
