# Glyph probe evidence (Plan D Task 1)

Measured 2026-09-21T22:52:01.122Z on the default configuration (every RendererFeatures flag off), font Hack 14px, lineHeight 1.2 (`ts/renderer-dom/src/default-font.ts:7`), cell 8.4375×16.796875 px.

| Item | Measurement | Verdict |
|---|---|---|
| Box drawing (spec Part 4 "only if the baseline shows hairline gaps between `│` rows") | `boxGapPx` = 0 between the `│ box` and `│ rows` rows at the bar's x (`box-zoom.png`) | not needed |
| Width cache (spec Part 4 "only if a baseline screenshot of an emoji/CJK row shows drift") | `wideDriftPx` = -5.36 (🚀✅😀), `cjkDriftPx` = -28.38 (漢字テスト中文): distance of the column-40 `|` marker from 40 × cellWidth | needed |
| Grapheme clusters (not conditional; evidence for Task 5) | `seqDriftPx` = -46.36 on the ❤️ 👨‍👩‍👧 👋🏽 🇪🇬 row | Task 5 re-measures with `--features graphemes` |

Rule: `needed` when the measured gap or drift is ≥ 1 px (`NEEDED_PX` in `glyph-probe.mjs`); sub-pixel amounts cannot be corrected by `letter-spacing` or a CSS border.
Task 10 runs only if the first row says needed; Task 11 only if the second row says needed.
