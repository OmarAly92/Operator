# Plan 7 — Shell blocks: historical plan

Status: superseded
Date: 2026-08-28
Replacement: [`2026-08-31-shell-blocks-daemon.md`](2026-08-31-shell-blocks-daemon.md)

## Superseded

Do not implement work from this plan. It described an earlier shell-block design that
used semantic callbacks and session-scoped block history. The production design is the
amended lifecycle plan above.

That plan owns the complete capture path: lossless mark spans, a writer-owned bounded
journal, guarded tmux `pipe-pane` setup, per-handle supervisor serialization and
restart adoption, `terminal_blocks` persistence, terminal-handle-keyed raw history,
history-before-live replay, and final draining before terminal destruction.

The original plan's backend and frontend tasks are retained only in git history. Future
work must extend the amended plan or a new plan that explicitly migrates its
terminal-handle ownership; it must not execute this plan alongside the shipped design.
