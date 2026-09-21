# Triage of the Alacritty corpus against vt-core (2026-09-19)

Categories: **match** (visible screen identical), **model** (a deliberate
difference of this model — blank-row commits, rewrap, no scroll-region history,
tabs rendered as spaces), **parser** (a vt-core dispatch gap; not fixed here,
listed for a follow-up), **upstream** (the recording itself exercises behaviour
Alacritty defines differently from xterm).

Method: `tools/alacritty-grid-text.py` renders each Alacritty `grid.json`
top-of-history to bottom-of-screen; the last `rows` lines of that are compared
against the last `rows` lines of our `screen.txt`. Every recording's
`config.json` sets `"history_size":0`, so Alacritty's grid never carries more
than `rows` lines; vt-core is replayed with `REF_SCROLLBACK_ROWS=200_000`
(`tests/ref.rs`) and never discards scrolled-off content. Two model behaviours
recur across most rows below:

- **no scroll-region history**: any row that scrolls off, or that `ED2`
  (`\e[2J`)/`DL` clears, is committed to vt-core's scrollback instead of being
  discarded, so our `screen.txt` (scrollback + screen) is longer than
  Alacritty's zero-history grid and the tail-`rows` window picks up leftover
  rows Alacritty never kept.
- **blank-row commits**: `ScreenGrid::content_rows()` is `max_cursor_row + 1`
  (`crates/vt-core/src/screen.rs:199`) — vt-core only renders rows the cursor
  has actually visited, where Alacritty always renders the full configured
  screen height padded with blank rows. Short recordings that never move the
  cursor near the bottom render far fewer lines than Alacritty's padded grid.

Two directories (`colored_underline`, `zerowidth`) are marked **match** with a
caveat: `alacritty-grid-text.py` (verbatim from the brief) reads only
`cell["c"]` from `grid.json`, not `cell["extra"]["zerowidth"]`, so it silently
drops the zero-width combining marks Alacritty stores on the preceding cell.
Our screen.txt correctly includes them; the two texts differ only because the
comparison tool omits them, not because the rendered screens differ.

| dir | category | note |
|---|---|---|
| alt_reset | model | recording ends with `?1049h`/`?1049l` unbalanced (5 enter / 4 leave); `tests/ref.rs`'s `render()` only reads the primary `GridSnapshot` rows, never `snapshot.alt`, so a recording that ends inside the alt screen shows stale primary-screen content instead |
| clear_underline | model | blank-row commits — non-blank content is identical, Alacritty pads with blank rows to `rows` |
| colored_reset | model | no scroll-region history — `\e[H\e[2J` between the two `printf`s discards the first line in Alacritty; vt-core commits it to scrollback instead |
| colored_underline | match | `alacritty-grid-text.py` drops `extra.zerowidth` combining marks (curly/dotted underline test glyphs); the rendered screens agree, see note above |
| csi_rep | model | blank-row commits |
| decaln_reset | parser | `ESC # 8` (DECALN, fill screen with `E`) is never dispatched — `Parser::esc_dispatch` (`crates/vt-core/src/parser.rs:475`) discards `intermediates`, and `ScreenGrid::esc` (`crates/vt-core/src/screen/dispatch.rs:73`) has no `#`/`8` arm |
| deccolm_reset | parser | `CSI ?3h`/`?3l` (DECCOLM, 80/132-column switch) is not in `Parser::note_private_mode` (`crates/vt-core/src/parser.rs:199`), so the screen clear real terminals perform on a column-mode switch never happens |
| delete_chars_reset | model | blank-row commits |
| delete_lines | model | no scroll-region history — `DL` (`\e[1000M`) scrolls rows off; vt-core keeps them in scrollback, Alacritty's zero-history config drops them |
| erase_chars_reset | model | blank-row commits |
| erase_in_line | parser | `EL 0` erases the just-printed last-column cell (`...49a` vs Alacritty's `...49a+`); vt-core does not model the deferred-autowrap "pending wrap" cursor state that keeps the cursor logically past the last column until the next printable character |
| fish_cc | model | blank-row commits |
| grid_reset | model | no scroll-region history |
| history | match | identical after the tail-`rows` window |
| hyperlinks | model | blank-row commits |
| indexed_256_colors | model | blank-row commits |
| insert_blank_reset | model | blank-row commits |
| issue_855 | match | identical after the tail-`rows` window |
| ll | model | blank-row commits |
| newline_with_cursor_beyond_scroll_region | model | blank-row commits |
| origin_goto | model | no scroll-region history — leftover prompt lines above an `\e[2J` remain in vt-core's scrollback; the recording also sets `?6h` (DECOM, origin mode), which `note_private_mode` does not implement at all (no visible effect in this recording, listed as a gap regardless) |
| region_scroll_down | model | blank-row commits — non-blank content matches |
| row_reset | model | no scroll-region history |
| saved_cursor | parser | `ESC ( 0` (G0 charset designation, DEC Special Graphics / line drawing) is never dispatched, for the same reason as DECALN; `test` prints as literal ASCII instead of line-drawing glyphs |
| saved_cursor_alt | parser | same G0 charset gap as `saved_cursor`, compounded by the alt-screen harness limitation (`?1049h` count exceeds `?1049l`) |
| scroll_in_region_up_preserves_history | model | tabs rendered as spaces — `ls` column output uses literal tab stops Alacritty preserves and we expand, shifting alignment |
| scroll_up_reset | model | no scroll-region history |
| selective_erasure | match | identical after the tail-`rows` window |
| sgr | model | blank-row commits |
| tab_rendering | model | tabs rendered as spaces (the directory's own purpose) |
| tmux_git_log | model | alt-screen harness limitation — tmux opens the alt screen and never returns by EOF |
| tmux_htop | model | alt-screen harness limitation — htop opens the alt screen and never returns by EOF |
| underline | model | blank-row commits; `styles.json`'s row for the `4:3;21` line was hand-corrected, see "Style attributes" below |
| vim_24bitcolors_bce | model | alt-screen harness limitation — vim opens the alt screen and never returns by EOF |
| vim_large_window_scroll | model | alt-screen harness limitation — vim opens the alt screen and never returns by EOF |
| vim_simple_edit | model | alt-screen harness limitation — vim opens the alt screen and never returns by EOF |
| vttest_cursor_movement_1 | parser | vttest's test-pattern screen relies on both DECALN (unimplemented, see `decaln_reset`) and DECCOLM (unimplemented, see `deccolm_reset`); stale menu text bleeds through where the pattern should be |
| vttest_insert | parser | same DECCOLM gap as `deccolm_reset` — the 80/132-column switch that should clear the screen leaves the prior vttest menu screen showing |
| vttest_origin_mode_1 | parser | same DECCOLM gap — stale "132 column mode" menu text remains where the origin-mode test screen should be |
| vttest_origin_mode_2 | parser | same DECCOLM gap — stale "80 column mode" menu text remains |
| vttest_scroll | model | blank-row commits — only trailing blank rows differ |
| vttest_tab_clear_set | parser | same DECCOLM gap — stale menu text ("Line speed 38400bd") remains instead of the tab-ruler test screen |
| wrapline_alt_toggle | model | blank-row commits |
| zerowidth | match | `alacritty-grid-text.py` drops `extra.zerowidth` combining marks; the rendered screens agree, see note above |
| zsh_tab_completion | model | blank-row commits |

## Style attributes (`styles.json`, Task 3, 2026-09-22)

`sgr`, `underline`, `colored_underline`, and `clear_underline` also carry a
`styles.json` (generated by `tools/import-alacritty-ref.py --styles`, decision
2026-09-21-agent-tui-plan-d-text-and-glyphs) asserting the SGR attributes and
underline colour vt-core parses per row, cross-checked against Alacritty's own
`grid.json`. One row required a hand correction rather than a straight
regeneration:

- **`underline`, model (SGR 21 is a genuine spec disagreement, not a
  generator bug)**: the recording's fourth line is
  `\e[4:3;21mUNDERLINED\e[21m` — SGR `4:3` (curly underline) followed by bare
  SGR `21` in the same escape. This engine's `sgr.rs` treats bare `21` as
  double-underline (`crates/vt-core/tests/sgr_attributes.rs`,
  `every_underline_style_is_exclusive_and_24_clears_all_of_them`:
  `assert_eq!(attrs_of(b"\x1b[21mA").bits(), Attrs::DOUBLE_UNDERLINE)`),
  matching kitty/foot/wezterm/ghostty. Alacritty's own vendored `vte` crate
  (`vte-0.15.0/src/ansi.rs:1849`, `[21] => Some(Attr::CancelBold)`) treats bare
  `21` as "cancel bold" only and never touches underline state, so its grid
  keeps that row curly. Both are defensible readings of an ECMA-48-ambiguous
  code; this is a decision already encoded in `sgr_attributes.rs`, not
  something introduced by the corpus import. Because of it, row 7 (0-indexed
  6) of `underline/styles.json` was hand-edited from the generator's raw
  output `[[0, 10, 8, 255]]` (Alacritty's curly) to `[[0, 10, 4, 255]]` (this
  engine's double-underline) to match what vt-core is actually supposed to
  produce for these bytes. **Re-running
  `import-alacritty-ref.py --styles underline` will silently regenerate
  Alacritty's disagreeing value and must not be done without re-applying this
  correction.**
- `colored_underline` needed no hand correction — its only discrepancy against
  a naive cell-index mapping was the zero-width combining marks Alacritty
  records in `extra.zerowidth` (same mechanism as the `zerowidth` and
  `colored_underline` `match` entries above); the generator's `char_index`
  accumulation accounts for it, and the generated fixture is used as-is.
