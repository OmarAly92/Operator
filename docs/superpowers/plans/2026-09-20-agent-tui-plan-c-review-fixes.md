# Plan C review — fixes required before execution

Review of `docs/superpowers/plans/2026-09-20-agent-tui-plan-c-long-sessions-edges.md`
(commit `05881c5b9`) against the tree at `ba6dd6d35`. Every claim below was checked
against the cited file and line; plan line numbers are those of `05881c5b9`.

The plan's structure, task order and its three design decisions (downward
`Content` allocation from `CONTENT_BASE`, `Delta.history_rewritten_from`, a
prepend forcing `Full`) are sound and stay. `CONTENT_BASE = 1 << 48` is safe:
no absolute content offset crosses the wasm boundary — export row ranges are
buffer-relative `u32` (`crates/vt-wasm/src/export.rs:206-218`), find hits are
block-relative (`crates/vt-core/src/find.rs:36-43`).

Apply every item under "Required" by editing the plan in place, then re-run the
writing-plans self-review and commit the plan again. Do not start executing.

## Required

### R1. The stable-row spaces never meet — no history chunk is ever prepended (G, Tasks 2, 3, 4, 5)

`apply_history_chunk` (plan :615) accepts a chunk only when
`first_stable_row + rows.len() == self.trimmed_total`. Chunks are numbered in the
**mirror's** stable space (`chunk_first_stable = mirror.first_stable + start`,
plan :1459). The receiving renderer core is fresh: `trimmed_total` starts at 0
(`crates/vt-core/src/parser.rs:66`) and the frame's rows land at stable
`0..lines`. So the first chunk (e.g. `history=4488,512` from a mirror holding
5,000 rows) compares `5000 != 0`, is dropped, and so is every later one.

The plan's tests hide this by hand-writing `first_before - 2`; on a fresh core
`first_before == 0`, so that is a `u64` underflow that panics in a debug test
build (`replay_prepends_history_without_moving_the_frame`,
`two_history_chunks_prepend_oldest_last`, `blocks_survive_reopen`,
`a_history_chunks_marks_never_touch_the_live_block_grid`).

Fix:
- `vt_replay` emits, as part 0 **before the modes**,
  `\x1b]7000;v=1;origin=<mirror.first_stable + frame_first>\x1b\\` where
  `frame_first = total.saturating_sub(lines)` is the same value
  `vt_history_chunk` uses for `HistoryBefore`. An empty terminal still returns
  0 bytes.
- `crates/marks` decodes `origin=<u64>` into `MarkEvent::ReplayOrigin(u64)`,
  consumed by the key-matching loop like `ready`/`history` so it never reaches
  `BlockGrid::set_meta_field`.
- `Parser::adopt_origin(origin: u64)` sets `trimmed_total = origin` and
  `grid.advance_origin(origin as usize)` **only when** `trimmed_total == 0` and
  `rows.completed().is_empty()`; otherwise it is ignored. `verify_integrity`'s
  `OriginMismatch` keeps holding because both move together.
- Add the fixed-name table row (`origin` mark bytes, `MarkEvent::ReplayOrigin`).
- Rewrite the four tests: feed `\x1b]7000;v=1;origin=1000\x1b\\` first, then
  the live rows, then `history=998,2`; assert `first_stable_row() == 998`.
  Add `an_origin_mark_after_rows_exist_is_ignored`.
- Task 5's Go test `TestReplayOrderIsModesFrameReadyHistory` asserts the
  origin mark is the first bytes of the frame.
- Task 6's `TestClientPaintsAtReadyBeforeHistory` feeds the whole stream into
  a `vtwasm` parser and asserts `row 00` is the first row of its snapshot —
  i.e. an end-to-end prepend, not just "a history chunk arrived".

### R2. The chunk's trailing `exit=` mark leaks into the live block grid (G, Tasks 3, 5)

`HistoryReceiver::consume` stops at the `wanted`-th `\n` (plan :880-887), but
`write_block_close` emits `\x1b]7000;v=1;exit=<code>\x1b\\` **after** the last
row's `\r\n` (plan :1478). Those bytes fall through to the live parser, where
`BlockGrid::close_block` (`crates/vt-core/src/block_grid.rs:118-127`) closes
whatever block is open — in a Claude session, the live agent block. The plan's
`a_history_chunks_marks_never_touch_the_live_block_grid` passes only because no
live block is open (`close_block` on `None` returns).

Fix:
- `vt_history_chunk` writes the block-close mark **before** the closing row's
  `\r\n`: `<row bytes><exit mark>\r\n`. State this ordering in Task 5's
  "Produces" block and in the fixed-name table.
- `note_mark` in `history.rs` records `exit` against `seen_rows` (the row the
  mark sits in), so `row_count = row + 1 - first_row`.
- The test opens a live block first (`\x1b]7000;v=1;id=live;cmd=claude\x1b\\`),
  feeds the chunk, then asserts the live block is still open
  (`snapshot.blocks` has a block with `state == Running`, or whatever
  `BlockState` the tree names) and that `after.blocks.len() == before + 1`.

### R3. History must be opt-in per client (G, Tasks 6, 11, 12)

Nothing gates history per client. The mobile client renders with the xterm fork
(`packages/mobile/packages/xterm`) which knows nothing of OSC 7000 history
marks: it will print up to 200k rows newest→oldest after the live frame. The
prompt's rule "an old client keeps working" applies to G exactly as it does to
H.

Fix:
- The desktop attach declares `history: true` on the mux attach message
  (`backend/internal/terminal/protocol.go`, `frontend/src/renderer/lib/terminal-mux.ts`);
  the manager forwards it to the pty-host at registration (a field on the
  existing register/resize message in `proto.go`, not a new message type).
- `clientState.wantsHistory bool`; `handleConn` calls `go h.streamHistory(cs)`
  only when it is set. Every other client receives exactly today's replay
  (origin mark, modes, frame, READY are harmless to xterm — verify READY and
  origin are ignored by the xterm fork's OSC handler and say so in Task 6).
- Task 12 (mobile) does **not** set the flag. Add
  `TestAClientWithoutHistoryOptInGetsNoChunks` to `attach_replay_test.go`.
- Verify whether the capture stream (`backend/internal/terminal/capture.go` →
  `BlockAssembler`) is a pty-host client that receives attach replays. If it is,
  it must not opt in, or the re-emitted `id=`/`cmd=`/`exit=` marks create
  duplicate blocks in Operator's block store. Record the answer in Task 6.

### R4. H never throttles after a replay; history streaming can pause the child (H, Tasks 6, 10, 11)

`cs.delivered` counts only `deliver` batches (plan :2896). The replay frame and
history chunks are enqueued uncounted. The renderer acks a cumulative count of
**every** byte `mux.onData` hands it (plan :3012), replay included. The host
clamps `acked` to `delivered` (plan :2914), so after any reopen the client's
count is permanently ahead, unacked stays ≈ 0, and that client can never pause
the child. Every pane opens with a replay, so H is defeated in practice.

Separately, if `delivered` did count history, a 200k-row history (tens of MB)
streamed to one client would push it past `readHighWatermark` and pause the
child for every other attached pane.

Fix:
- Count into `cs.delivered` every `MsgTerminalData` payload enqueued for that
  client: the replay frame in the registration hold, each history chunk in
  `streamHistory`, and `deliver` batches. Both sides then count the same byte
  stream.
- `streamHistory` paces on the ack watermark for an acking client: before each
  chunk, wait (on `h.readCond`, under `h.mu`) while
  `cs.everAcked && cs.delivered - cs.acked > readLowWatermark`; keep
  `awaitCapacity()` for the socket queue. A client that never acks is paced by
  `awaitCapacity()` alone, as today.
- Add `TestHistoryStreamingNeverPausesTheChild` (`host_test.go`): an acking
  client attaches to a 5,000-row session, acks as it reads, and
  `f.pty.readsPaused()` is never observed true.
- `TestReadPausesPastHighWatermarkAndResumesOnAck` must attach to a session
  that has a replay frame, so the test would have caught this.

### R5. Lazy rewrap bookkeeping (F, Task 8)

In `rewrap_hot` / `mark_stale` / `rows_for` (plan :2225-2337):

- `mark_stale` returns early on any overlap. After a second width change with
  rows appended between the two, the band `[old_cold_end, new_hot_start)` —
  rows hot at W1, now cold — is never marked and stays cut at W1 forever. Fix:
  mark only the non-overlapping tail `[existing_run_end, hot_start)` with
  `cut_at`. Extend `two_width_changes_before_access_rewrap_once` to append
  3,000 rows between the two changes and assert those rows rewrap on touch.
- `self.completed.insert(run.start + offset, row)` in a loop is
  O(rows × HOT_ROWS) on a `VecDeque` (~4×10⁸ element moves at 200k rows) — the
  exact cost the task exists to remove. Fix: `let tail = completed.split_off(run.start + run.len); completed.truncate(run.start); completed.extend(piece); completed.extend(tail)`.
- `RowIndex::prepend` (Task 2) never shifts stale-run `start`s; only `trim_to`
  does (plan :2337). A resize while history chunks are still arriving corrupts
  every run. Fix: `prepend` adds the prepended count to every run's `start`.
  Add `stale_runs_follow_a_prepend` to `tests/lazy_rewrap.rs` and have the
  integrity invariant catch it.
- `hot_start = total - HOT_ROWS` can fall mid-logical-line
  (`completed[hot_start - 1].wrapped == true`); the piece rewrap then treats a
  fragment as a line start and computes a hanging indent from it. Fix: walk
  `hot_start` down to the nearest row with `wrapped == false` before draining.
  Same rule for a stale run's boundaries in `rows_for` (they inherit it if
  runs are only ever created at such boundaries — say so).

### R6. Mouse-mode replay uses the wrong encoding (G, Task 4)

Plan :1212 matches `mouse_tracking_level()` as `1 => ?1000h, 2 => ?1002h,
3 => ?1003h`. The level is a bitmask
(`crates/vt-core/src/parser.rs:341-343`: 1000 = 0b001, 1002 = 0b010,
1003 = 0b100). `?1003h` is never replayed and 1000+1002 replays as 1003. Fix:
emit per bit (`& 1 → ?1000h`, `& 2 → ?1002h`, `& 4 → ?1003h`), and have
`TestReplayEmitsTheModesTheChildSet` set `?1003h` and assert it round-trips.

## Recommended (apply unless there is a reason not to; say which)

- **Lift the cover on the core's flag, not a byte scan (Task 7).** Task 3 adds
  `TerminalCore::replay_ready()` and Task 7 then ignores it. Plan A's
  `enqueue`/12 ms drain means the frame may not be parsed when
  `flushReplay(false)` runs, so the cover can lift on an unpainted pane. Expose
  `replayReady()` on `ts/core` `TerminalCore`, surface it through `onChange`,
  and end the gate when it flips. Drop `replay-ready.ts` unless a byte scanner
  is still needed for the pre-core path.
- **Wrapped flags are lost across reopen.** History rows are prepended with
  `wrapped: false` (plan :1082), so a later width change cannot rejoin lines
  the mirror had wrapped. Either carry the flag (emit wrapped rows without
  `\r\n` and let the receiver's own screen wrap them — the receiver must then
  be sized to the mirror's width, which the chunk mark can carry as
  `cols=<n>`) or state the loss explicitly in `TERMINAL.md` §5 in Task 13.
- **Fixture size.** The only long fixture is `claude-long-50k` (~60k rows).
  Task 13 already says every 200k target is measured at ~60k and reports it as
  such; keep that wording.

## Verified as correct (no change)

`ExportedRow`/`export_screen_row` (`grid.rs:21,274`), `set_records_eviction`
(`screen.rs:150`), every mode accessor Task 4 reads (`lib.rs:375,441-463`),
`flushReplay(holdTail)` semantics (`useTerminalSession.ts:516-561`), the
listener-before-gate order in `mux.onData` (`:579-587`), `awaitCapacity`
(`host.go:133`), `close_block` (`block_grid.rs:118`), `RowIndex::rewrap` map
shape (`row_index.rs:100-120`), and the byte-preserving daemon forwarding path
(`terminal/manager.go:458`).
