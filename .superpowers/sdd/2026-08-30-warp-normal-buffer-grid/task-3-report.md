# Task 3 report: pure `commit_row`

## Status

Implemented and verified on 2026-08-30.

## TDD outputs

RED command, run from `packages/terminal`:

```text
$ cargo test -p vt-core scrollback
   Compiling vt-core v0.1.0 (.../packages/terminal/crates/vt-core)
error[E0432]: unresolved import `super::commit_row`
 --> crates/vt-core/src/scrollback.rs:3:9
  |
3 |     use super::commit_row;
  |         ^^^^^^^^^^^^^^^^^ no `commit_row` in `scrollback`
error: could not compile `vt-core` (lib test) due to 1 previous error
```

GREEN focused command:

```text
$ cargo test -p vt-core scrollback
test result: ok. 6 passed; 0 failed; 0 ignored; 0 measured; 31 filtered out
```

GREEN full command:

```text
$ cargo test -p vt-core
test result: ok. 37 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 41 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 20 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 6 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 11 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

`cargo fmt --all -- --check` passed after formatting, and `git diff --check` passed.

## Files

- `packages/terminal/crates/vt-core/src/scrollback.rs` — added `commit_row` and six unit tests.
- `packages/terminal/crates/vt-core/src/lib.rs` — registered the private `scrollback` module.

## Implementation

`commit_row` finds the last non-space cell, sets each cell's style using `AttributeMap::set_from` at the current byte offset before pushing its UTF-8 bytes, and completes the row at the resulting content offset. It emits no newline byte; an all-blank row remains an empty range as defined by `RowIndex::complete_row`.

## Self-review

- Uses the required `set_from` ordering and byte offsets.
- Trims only trailing spaces while preserving interior spaces.
- Handles multibyte characters through `encode_utf8` and `Content::push_char`.
- Does not depend on `Parser`, snapshots, or integration state.
- No inline code comments added.

## Concerns

The new function is currently unused outside its unit tests, so Rust emits the expected `dead_code` warning until the parser integration task consumes it. No functional concerns found.
