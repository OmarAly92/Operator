# Grapheme break corpus

`GraphemeBreakTest.json` is the Unicode Character Database's
`GraphemeBreakTest.txt` (Unicode 17.0.0, © Unicode, Inc., used under the
Unicode License v3, https://www.unicode.org/license.txt) in the JSON form
kitty ships at `kitty_tests/GraphemeBreakTest.json` (https://github.com/kovidgoyal/kitty,
commit `719c61a`): each entry's `data` is the list of
extended grapheme clusters the standard defines for that case, and `comment`
is the standard's own annotation. Only the data file is copied; kitty's own
code (GPL-3.0) is not.

`tests/grapheme_break_test.rs` asserts that `vt_core::clusters(text, WidthMode::Grapheme)`
splits every case exactly as `data` does. `unicode-segmentation` 1.13.3 tracks
Unicode 17.0.0 (`src/tables.rs:17`), the same version as the corpus; a
failure after a crate upgrade is version drift and is reported, not patched.
