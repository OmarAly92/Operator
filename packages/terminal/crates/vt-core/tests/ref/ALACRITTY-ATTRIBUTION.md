# Reference recordings

The 45 `recording` files listed below are `alacritty.recording` from
`alacritty_terminal/tests/ref/<name>/` in Alacritty
(https://github.com/alacritty/alacritty, commit `d692748d`), used under the
Apache-2.0 / MIT dual licence (`LICENSE-APACHE`, `LICENSE-MIT` beside this file).
Only the byte streams are imported; every `size.json` is rewritten into this
crate's `[{offset, cols, rows}]` layout and every `screen.txt` / `cursor.json`
is generated from `vt-core` (`UPDATE_REF=1 cargo test -p vt-core --test ref`),
so the expectations are this model's, not Alacritty's. `TRIAGE.md` records where
the two differ and why.

`claude_spinner_10s` is this repository's own recording
(`packages/terminal/bench/agent-session/fixtures/claude-spinner-10s`).
