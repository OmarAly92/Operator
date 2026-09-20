# Agent-TUI Plan C — Long Sessions Edges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopening a Claude Code pane recovers the whole session (not the mirror's last screen), a width change at 200,000 rows costs the debounce plus one frame instead of a walk over every row, and a slow client throttles the child instead of queueing the session in memory.

**Architecture:** Three independent edges of the long-session work, over the model Plan B built. **G (reopen):** `vt_replay` becomes a five-part stream — an `OSC 7000;v=1;origin=` mark naming the stable row its first row sits at, the child's modes, the live frame, an `OSC 7000;v=1;ready=1` READY mark the client paints at, then history newest→oldest in 512-row chunks each framed by `OSC 7000;v=1;history=<first_stable_row>,<count>`. The receiving `vt-core` adopts that origin, recognises the chunk marks and *prepends* the rows below everything it already holds, which is why `Content` grows a downward allocation region: rows must stay offset-ordered or every trim, style lookup and integrity check breaks. History is opt-in per client, so a client that cannot read the chunks (the mobile xterm fork) still gets exactly today's attach. **F (lazy rewrap):** a width change rewraps the screen and the newest `HOT_ROWS = 2_000` completed rows eagerly and marks the rest stale with the width it is cut at; a stale run is rewrapped once, on first access, through `RowIndex::rows_for`, which emits the same stable-row remap pairs an eager rewrap does, so the scroll anchor, blocks and find hits follow it. **H (flow control):** the mux client acks every 5,000 bytes and the pty-host stops reading the pty at 100,000 unacknowledged bytes for its slowest acking client.

**Tech Stack:** Rust (`vt-core`, `crates/marks`, `vt-wasm` via wasm-bindgen, `vt-host` C-ABI wasm run by wazero), Go (`backend/internal/adapters/runtime/ptyhost`, `backend/internal/terminal`, `backend/internal/httpd`), TypeScript (`ts/core`, `ts/renderer-dom`, `frontend/`), Dart (`packages/mobile`), Vite + Playwright benches (`bench/agent-session`).

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` — Plan C is Part 1.3 items **F**, **G** and **H**, and nothing else. Survey entries cited: `docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §1.9 (Ghostty READY-first snapshot), §3.11 (xterm.js `SerializeAddon`), §3.13 (xterm.js `write(data, cb)` flow control), §4.2 (WezTerm, the shape of "rows by stable id" only), §5.8 (Kitty lazy pagerhist rewrap), §6.3 (VS Code flow-control constants and replay with command state). Read `TERMINAL.md` end to end before starting.

**Review applied.** This plan was reviewed at commit `05881c5b9` against the tree at `ba6dd6d35` (`docs/superpowers/plans/2026-09-20-agent-tui-plan-c-review-fixes.md`). Every **Required** item (R1–R6) and every **Recommended** item is applied here, with one deliberate exception:

- **Recommended: carry the `wrapped` flag across a reopen.** *Not applied — the loss is documented instead* (Task 13 Step 6 writes it into `TERMINAL.md` §5). Carrying it means emitting wrapped rows without `\r\n` and sizing the receiver's scratch screen to the mirror's width, which would make the chunk mark carry `cols=<n>` and make the receiver's row count depend on its own wrapping rather than on the mark's `count` — the one invariant the whole chunk protocol rests on (`HistoryReceiver::consume` ends a chunk at the `count`-th `\n`). The cost of not carrying it is bounded and visible: a reopened pane's *prepended* rows do not rejoin into logical lines on a later widening, while every row the pane produces after the reopen does. Revisit it with a `cols=` chunk field once the row-count invariant has a second anchor.

**Gate — Plan B must be executed first.** Plan C consumes Plan B's interfaces: `Limits` in both cores (B Tasks 2–3), stable rows and `BlockGrid::origin` (B Tasks 4–5), `Delta`/`take_delta`/`remap` and the incremental export (B Tasks 6–8), and the stable-row scroll anchor with remap handling (B Task 9). As of writing, Plan B has landed on `development` in `ba6dd6d35` (merge, 2026-09-20) and every line number below was verified against that tree. If you are reading this on a tree where `git log --oneline | grep -i "Plan B"` finds no such merge, **stop and execute Plan B first** — every task here fails without it.

From Plan B's "Deviations", carried into this plan verbatim and never re-decided:

- `Block.first_row` is a `usize` holding the **stable** row; `BlockGrid::origin` is the stable row of flat row 0 and equals `Parser::trimmed_total`; callers cross the seam with `BlockGrid::flat_extent(&Block) -> (usize, usize)`.
- `Delta.remap` pairs are `(u64, u64)` **stable** rows. Every remap this plan produces uses that same type.
- The incremental export keeps trimmed rows as a dead prefix until `compact()`.
- Dirty rows accumulate in wasm across `sync()` calls until `ack_dirty`.

## Global Constraints

Every task inherits these. They are the spec's "Global constraints" plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator import, path, default or concept inside it. `HOT_ROWS = 2_000` and `HISTORY_CHUNK_ROWS = 512` are **package** constants (`crates/vt-core/src/row_index.rs`, `crates/vt-host/src/lib.rs`). The flow-control watermarks `readHighWatermark = 100_000` and `readLowWatermark = 5_000` live in **`backend/internal/adapters/runtime/ptyhost/host.go`**, and the client cadence `ACK_EVERY_BYTES = 5_000` lives in the two products (`frontend/src/renderer/hooks/useTerminalSession.ts`, `packages/mobile/lib/core/mux/mux_client.dart`).
- No comments in new code (user's global instruction). Existing comments may be corrected when they become false. A code comment that cites a reference names the repository and path (`ghostty/src/terminal/PageList.zig`, `xterm.js/src/common/addons/SerializeAddon.ts`, `kitty/kitty/history.c`, `vscode/src/vs/platform/terminal/common/terminal.ts`, `wezterm/term/src/screen.rs`) the way `styles.css` cites Warp — such citations are the one kind of new comment permitted.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`npm run build:wasm -- --force` for the renderer; `cargo build --release -p vt-host --target wasm32-unknown-unknown` copied into `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`) and the daemon is rebuilt (`npm --prefix frontend run build:daemon`). Old pty-host processes keep the old wasm for the life of the session; every such task ends with "restart the daemon and the app".
- TDD: failing test first with real test code, run it and see it fail, minimal real implementation, run it and see it pass, commit. Every `TERMINAL.md` §4 guard keeps passing — in particular §4.7 (replay rows clipped to the grid) and §4.15 (the process-boundary mark).
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` from `/Users/omaraly/development/AI/Operator/packages/terminal`. TS: `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/react`; `npx tsc --noEmit -p .` in `frontend/`. Go: `go test ./internal/adapters/runtime/ptyhost/...` from `/Users/omaraly/development/AI/Operator/backend` (the pre-existing `TestProcessEnvironmentLetsOverridesWin` failure is not yours, `TERMINAL.md` §5). Dart: `flutter analyze` and `flutter test` from `/Users/omaraly/development/AI/Operator/packages/mobile`.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per behaviour change. Commits go to `development` with the `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` trailer.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash calls share the working directory).
- Feel gate: every task ends with `npm run bench:feel` and it must report `PASS feel gate: zero pixel diff`. **No task in Plan C declares a pixel change.**
- Do not change behaviour the spec does not ask for: no resize-debounce change (`TERMINAL.md` §4.6 — "do not re-add a leading edge or a max-wait"), no scrollback-cap change (Plan B owns `Limits`), no mux protocol change beyond the `ack` message, no pixel change, no persistence to disk (spec Decision 2), no §4.8 de-dup heuristic (spec Decision 3). The §4.2 server-owned model is out of scope; G is rows-with-marks over the existing byte channel precisely so §4.2 can replace the transport later without touching the core.
- Code blocks in this plan occasionally contain `// the existing body of …` lines. Those are instructions to the reader and are never typed into the tree.

## Names and constants fixed once, used everywhere

| Name | Value / type | Home |
|---|---|---|
| `HOT_ROWS` | `usize = 2_000` | `crates/vt-core/src/row_index.rs` |
| `HISTORY_CHUNK_ROWS` | `u32 = 512` | `crates/vt-host/src/lib.rs` |
| `CONTENT_BASE` | `u64 = 1 << 48` | `crates/vt-core/src/content.rs` |
| origin mark bytes | `\x1b]7000;v=1;origin=<first_stable_row>\x1b\\` | emitted by `vt_replay` as **part 0**, decoded by `crates/marks` |
| READY mark bytes | `\x1b]7000;v=1;ready=1\x1b\\` | emitted by `vt_replay`, decoded by `crates/marks` |
| history mark bytes | `\x1b]7000;v=1;history=<first_stable_row>,<count>\x1b\\` | emitted by `vt_history_chunk`, decoded by `crates/marks` |
| history chunk row shape | `<block open mark?><row bytes><exit mark?>\r\n`, **the exit mark inside the row, before its CR-LF** | `crates/vt-host/src/lib.rs` |
| `MarkEvent::ReplayOrigin` | `(u64)` newtype variant | `crates/marks/src/event.rs` |
| `MarkEvent::ReplayReady` | unit variant | `crates/marks/src/event.rs` |
| `MarkEvent::HistoryChunk` | `{ first_stable_row: u64, rows: usize }` | `crates/marks/src/event.rs` |
| history opt-in | `ResizePayload.History bool` (`json:"history,omitempty"`) on the **opening** `MsgResize`; `{ch:'terminal', type:'open', history:true}` on the mux | `backend/.../ptyhost/proto.go`, `backend/internal/terminal/protocol.go` |
| `ports.HistoryAttacher` | `AttachWithHistory(ctx, handle, rows, cols uint16, history bool) (Stream, error)` | `backend/internal/ports/outbound.go` |
| remap pair | `(u64, u64)` stable rows | `crates/vt-core/src/delta.rs` |
| `Delta.history_rewritten_from` | `Option<usize>` (completed-row index) | `crates/vt-core/src/delta.rs` |
| `MsgAck` | `byte = 0x11` | `backend/internal/adapters/runtime/ptyhost/proto.go` |
| `AckPayload` | `{ Bytes int \`json:"bytes"\` }` | same file |
| `readHighWatermark` | `int = 100_000` | `backend/internal/adapters/runtime/ptyhost/host.go` |
| `readLowWatermark` | `int = 5_000` | same file |
| `msgAck` | `"ack"` | `backend/internal/terminal/protocol.go` |
| `ACK_EVERY_BYTES` | `5_000` | `frontend/src/renderer/hooks/useTerminalSession.ts` |
| `_ackEveryBytes` | `5000` | `packages/mobile/lib/core/mux/mux_client.dart` |

## File structure

| Task | Files |
|---|---|
| 1 | `crates/marks/src/{event.rs,scanner.rs}`, `crates/marks/tests/vectors.rs` |
| 2 | `crates/vt-core/src/{content.rs,attribute_map.rs,row_index.rs,block_grid.rs,parser.rs,integrity.rs,lib.rs}`, `crates/vt-core/tests/replay.rs`, `CHANGELOG.md` |
| 3 | `crates/vt-core/src/{history.rs,lib.rs,event_bridge.rs}`, `crates/vt-core/tests/replay.rs`, `CHANGELOG.md` |
| 4 | `crates/vt-host/src/lib.rs`, `backend/.../ptyhost/vtwasm/{replay_test.go,assets/vt_host.wasm}`, `CHANGELOG.md` |
| 5 | `crates/vt-host/src/lib.rs`, `backend/.../ptyhost/vtwasm/{vtwasm.go,replay_test.go,assets/vt_host.wasm}`, `CHANGELOG.md` |
| 6 | `backend/.../ptyhost/{proto.go,host.go,attach.go,attach_replay_test.go}`, `backend/internal/ports/outbound.go`, `CHANGELOG.md` |
| 7 | `packages/terminal/ts/core/src/{terminal-core.ts,terminal-core.test.ts}`, `frontend/src/renderer/hooks/{useTerminalSession.ts,useTerminalSession.test.tsx}`, `frontend/src/renderer/components/BlockTerminal.tsx`, `CHANGELOG.md` |
| 8 | `crates/vt-core/src/{row_index.rs,parser.rs,delta.rs,integrity.rs,lib.rs}`, `crates/vt-core/tests/{lazy_rewrap.rs,integrity.rs}`, `CHANGELOG.md` |
| 9 | `crates/vt-wasm/src/{lib.rs,export.rs}`, `ts/core/src/{terminal-core.ts,terminal-core.test.ts,types.ts}`, `ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts}`, `CHANGELOG.md` |
| 10 | `backend/.../ptyhost/{proto.go,host.go,attach.go,host_test.go,proto_test.go}`, `CHANGELOG.md` |
| 11 | `backend/internal/ports/outbound.go`, `backend/internal/terminal/{protocol.go,manager.go,attachment.go,manager_test.go}`, `frontend/src/renderer/hooks/{useTerminalSession.ts,useTerminalSession.test.tsx}`, `frontend/src/renderer/lib/terminal-mux.ts`, `CHANGELOG.md` |
| 12 | `packages/mobile/lib/core/mux/mux_client.dart`, `packages/mobile/test/core/mux/mux_client_test.dart` |
| 13 | `bench/agent-session/{main.ts,run.mjs,scroll-gate.mjs}`, `backend/.../ptyhost/vtwasm/agent_session_test.go`, the spec's baseline table ("After Plan C" column, the Part 1.4 rows Plan C owns), `TERMINAL.md`, `CHANGELOG.md` |

**Task order and why.** G's vt-core half first (Tasks 1–3): the receiving model has the largest blast radius — it changes the offset space every other subsystem rests on — and nothing else can be tested end to end until a prepended row exists. Then G's vt-host/Go half (4–6), then G's client half (7), so each layer is exercised by the one below it. F (8–9) follows because its remap reuses the stable-pair plumbing Task 2 leaves in `Delta` and its export window is the same `sync()` seam. H (10–12) is last before measurement because it touches no model at all — proto, watermarks, two clients — and would otherwise sit under every other task's Go test runs. Task 11 also carries G's history opt-in across the mux, because it is the same `clientMsg`/`protocol.go`/`terminal-mux.ts` edit and splitting it would mean touching those three files twice.

**Two forward references, both deliberate and both named at the point they occur.** Task 6's `streamHistory` wants `cs.delivered`, `h.readCond` and `readLowWatermark`, which Task 10 creates; Task 6 says to omit those two lines and Task 10 Step 4 says to add them, so every commit in between still compiles and passes. Task 6's daemon-side opt-in has no caller until Task 11 wires the desktop's `open` frame, which is why `TestAClientWithoutHistoryOptInGetsNoChunks` (Task 6) is the test that runs in the gap — it asserts the default, which is the state the tree is in until Task 11. Task 13 measures.

---

### Task 1: `origin`, `ready` and `history` marks in `crates/marks`

**Files:**
- Modify: `packages/terminal/crates/marks/src/event.rs:14-37` (the `MarkEvent` enum)
- Modify: `packages/terminal/crates/marks/src/scanner.rs:166-193` (`extension_events`)
- Test: `packages/terminal/crates/marks/src/scanner.rs` (module `tests`), `packages/terminal/crates/marks/tests/vectors.rs`

**Interfaces:**
- Consumes: `crate::extension::decode(payload) -> Option<ExtensionFields>` (`extension.rs:11`), which already splits `7000;k=v;k=v` into `pairs` and drops a higher major version.
- Produces:
  ```rust
  pub enum MarkEvent {
      // the existing variants, unchanged
      ReplayOrigin(u64),
      ReplayReady,
      HistoryChunk { first_stable_row: u64, rows: usize },
  }
  ```
  `origin=<u64>` yields `MarkEvent::ReplayOrigin`, `ready=1` yields `MarkEvent::ReplayReady`, `history=<first_stable_row>,<count>` yields `MarkEvent::HistoryChunk`. All three are consumed by the key-matching loop in `scanner.rs::extension_events`, exactly like `input-ready`, so none of the keys reaches `BlockGrid::set_meta_field` as block metadata.

- [ ] **Step 1: Write the failing test**

Append to the `tests` module at the end of `packages/terminal/crates/marks/src/scanner.rs`:

```rust
    #[test]
    fn an_origin_mark_decodes_to_replay_origin() {
        let mut s = Scanner::new();
        let events = events_only(s.feed(b"\x1b]7000;v=1;origin=5000\x1b\\"));
        assert_eq!(events, vec![MarkEvent::ReplayOrigin(5000)]);
    }

    #[test]
    fn a_malformed_origin_mark_emits_nothing() {
        let mut s = Scanner::new();
        assert_eq!(events_only(s.feed(b"\x1b]7000;v=1;origin=nope\x1b\\")), vec![]);
    }

    #[test]
    fn an_origin_mark_is_not_block_metadata() {
        let mut s = Scanner::new();
        let events = events_only(s.feed(b"\x1b]7000;v=1;origin=12\x1b\\"));
        assert!(
            !events.iter().any(|event| matches!(event, MarkEvent::Extension(_))),
            "origin must not reach the block grid as a meta field: {events:?}"
        );
    }

    #[test]
    fn a_ready_mark_decodes_to_replay_ready() {
        let mut s = Scanner::new();
        let events = events_only(s.feed(b"\x1b]7000;v=1;ready=1\x1b\\"));
        assert_eq!(events, vec![MarkEvent::ReplayReady]);
    }

    #[test]
    fn a_history_mark_carries_its_first_stable_row_and_count() {
        let mut s = Scanner::new();
        let events = events_only(s.feed(b"\x1b]7000;v=1;history=4096,512\x1b\\"));
        assert_eq!(
            events,
            vec![MarkEvent::HistoryChunk {
                first_stable_row: 4096,
                rows: 512
            }]
        );
    }

    #[test]
    fn a_malformed_history_mark_emits_nothing() {
        let mut s = Scanner::new();
        assert_eq!(events_only(s.feed(b"\x1b]7000;v=1;history=nope\x1b\\")), vec![]);
        assert_eq!(events_only(s.feed(b"\x1b]7000;v=1;history=1\x1b\\")), vec![]);
    }

    #[test]
    fn a_history_mark_is_not_block_metadata() {
        let mut s = Scanner::new();
        let events = events_only(s.feed(b"\x1b]7000;v=1;history=0,8\x1b\\"));
        assert!(
            !events.iter().any(|event| matches!(event, MarkEvent::Extension(_))),
            "history must not reach the block grid as a meta field: {events:?}"
        );
    }

    #[test]
    fn a_history_mark_split_across_two_feeds_still_decodes() {
        let mut s = Scanner::new();
        assert_eq!(events_only(s.feed(b"\x1b]7000;v=1;hist")), vec![]);
        assert_eq!(
            events_only(s.feed(b"ory=7,3\x1b\\")),
            vec![MarkEvent::HistoryChunk {
                first_stable_row: 7,
                rows: 3
            }]
        );
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p terminal-marks an_origin_mark_decodes_to_replay_origin
```
Expected: FAIL — `no variant named ReplayOrigin found for enum MarkEvent`.

- [ ] **Step 3: Add the three variants**

In `packages/terminal/crates/marks/src/event.rs`, inside `pub enum MarkEvent`, after `AltScreenLeave`:

```rust
    ReplayOrigin(u64),
    ReplayReady,
    HistoryChunk { first_stable_row: u64, rows: usize },
```

- [ ] **Step 4: Recognise the keys in `extension_events`**

Replace the body of `extension_events` in `packages/terminal/crates/marks/src/scanner.rs`:

```rust
fn extension_events(fields: ExtensionFields) -> Vec<MarkEvent> {
    let mut out = Vec::new();
    let mut remaining = ExtensionFields::default();
    let mut ready = false;
    let mut released = false;
    let mut has_extension_field = false;
    let mut replay_ready = false;
    let mut origin: Option<u64> = None;
    let mut history: Option<(u64, usize)> = None;
    for (key, value) in fields.pairs {
        match key.as_str() {
            "input-ready" => ready = true,
            "input-released" => released = true,
            "ready" => replay_ready = value == "1",
            "origin" => origin = value.parse::<u64>().ok(),
            "history" => history = parse_history(&value),
            _ => {
                if key != "v" {
                    has_extension_field = true;
                }
                remaining.pairs.push((key, value));
            }
        }
    }
    if !remaining.pairs.is_empty() && (!ready && !released || has_extension_field) {
        out.push(MarkEvent::Extension(remaining));
    }
    if released {
        out.push(MarkEvent::InputReleased);
    } else if ready {
        out.push(MarkEvent::InputReady);
    }
    if let Some(origin) = origin {
        out.push(MarkEvent::ReplayOrigin(origin));
    }
    if replay_ready {
        out.push(MarkEvent::ReplayReady);
    }
    if let Some((first_stable_row, rows)) = history {
        out.push(MarkEvent::HistoryChunk {
            first_stable_row,
            rows,
        });
    }
    out
}

fn parse_history(value: &str) -> Option<(u64, usize)> {
    let (first, count) = value.split_once(',')?;
    let first = first.parse::<u64>().ok()?;
    let count = count.parse::<usize>().ok()?;
    if count == 0 {
        return None;
    }
    Some((first, count))
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p terminal-marks
```
Expected: PASS, including the existing `vectors.rs` suite (no vector uses `ready=` or `history=`).

- [ ] **Step 6: Make the rest of the workspace exhaustive again**

`crates/vt-core/src/event_bridge.rs:14` matches `MarkEvent` exhaustively. Add the two new variants to its arm list as no-ops for now (Task 3 gives them bodies):

```rust
        MarkEvent::ReplayOrigin(_) | MarkEvent::ReplayReady | MarkEvent::HistoryChunk { .. } => {}
```
directly before the `MarkEvent::AltScreenEnter` arm.

- [ ] **Step 7: Run the full Rust gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/marks packages/terminal/crates/vt-core/src/event_bridge.rs && git commit -m "$(cat <<'MSG'
marks: decode the replay origin, ready and history-chunk marks

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Prepend primitives — `Content`, `AttributeMap`, `RowIndex`, `BlockGrid`, `Parser::adopt_origin`, `Parser::apply_history_chunk`

**Why the origin mark exists.** Chunks are numbered in the **mirror's** stable row space, but a reopened renderer core is fresh: `Parser::trimmed_total` starts at 0 (`crates/vt-core/src/parser.rs:66`) and the replayed frame's rows land at stable `0..lines`. Without a shared origin, `apply_history_chunk`'s abutment test compares the mirror's `first_stable + lines` against 0 and drops every chunk. So `vt_replay` states the frame's own first stable row as **part 0** of the stream and `Parser::adopt_origin` moves `trimmed_total` and `BlockGrid::origin` there together — once, before any row exists.

**Why this shape.** `verify_integrity` (`crates/vt-core/src/integrity.rs:17-69`) requires that completed rows tile the content **contiguously and in ascending offset order** (`RowsNotContiguous`), that every row lies inside `[content.start_offset(), content.end_offset()]` (`RowOutsideContent`), and that `rows.open_start() == content.end_offset()` (`OpenRowDetached`). `Parser::trim_to` (`parser.rs:494-519`) releases bytes with `content.drop_before(new_start)` where `new_start` is the **front** row's start. Every one of those breaks if prepended rows point at bytes appended past the live frame. So prepended bytes are allocated **downward**, below `Content::start_offset()`, and a fresh `Parser` bases its content at `CONTENT_BASE = 1 << 48` to leave room — 281 TB of offset space under a 128 MiB cap, so the base can never be reached.

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/content.rs:25-41` (add `with_base`, `prepend`), `attribute_map.rs:9-20` (add `with_base`, `prepend_runs`), `row_index.rs:69-98` (add `prepend`), `block_grid.rs:45-62` (add `retreat_origin`, `prepend_blocks`), `parser.rs:45-75` (base the content), `parser.rs:494` (add `adopt_origin` and `apply_history_chunk`), `lib.rs:336` (expose `adopt_origin`)
- Test: `packages/terminal/crates/vt-core/src/content.rs` (tests module), `packages/terminal/crates/vt-core/tests/replay.rs` (new)

**Interfaces:**
- Consumes: `BlockGrid::origin()`/`advance_origin(dropped)` (`block_grid.rs:45,52` — `advance_origin` also lifts `next_row` to the new origin, `:61`), `Parser::trimmed_total()` (`parser.rs:95`), `Parser::mark_full()` (`parser.rs:111`), `RowRange { start, end, wrapped, indent }` (`row_index.rs:8`), `Block { id, first_row, row_count, state, source, meta }` (`block.rs`).
- Produces:
  ```rust
  // content.rs
  pub(crate) const CONTENT_BASE: u64 = 1 << 48;
  impl Content {
      pub fn with_base(base: u64) -> Self;
      /// Allocates `bytes` immediately below `start_offset()` and returns the
      /// offset the region begins at.
      pub fn prepend(&mut self, bytes: &[u8]) -> u64;
  }
  // attribute_map.rs
  impl<A: Copy + Eq> AttributeMap<A> {
      pub fn with_base(initial: A, base: u64) -> Self;
      /// `runs` are (end_offset, value) pairs ascending inside [start, end).
      pub fn prepend_runs(&mut self, runs: &[(u64, A)]);
  }
  // row_index.rs
  impl RowIndex {
      pub fn prepend(&mut self, rows: Vec<RowRange>);
  }
  // block_grid.rs
  impl BlockGrid {
      pub fn retreat_origin(&mut self, prepended: usize);
      pub fn prepend_blocks(&mut self, blocks: Vec<Block>);
  }
  // parser.rs
  pub struct HistoryRow {
      pub bytes: Vec<u8>,
      pub wrapped: bool,
      pub indent: u16,
      pub styles: Vec<(u32, CellStyle)>,
  }
  pub struct HistoryBlock {
      pub first_row: usize,   // index inside the chunk
      pub row_count: usize,
      pub command: String,
      pub exit_code: Option<i32>,
  }
  impl Parser {
      /// Adopts the replaying host's stable row space. Ignored unless this
      /// parser is untouched (`trimmed_total == 0` and no completed rows), so
      /// a stray origin mark mid-session can never renumber a live pane.
      pub fn adopt_origin(&mut self, origin: u64) -> bool;
      /// Prepends a chunk of history below flat row 0. Ignored unless
      /// `first_stable_row + rows.len() == trimmed_total`.
      pub fn apply_history_chunk(
          &mut self,
          first_stable_row: u64,
          rows: Vec<HistoryRow>,
          blocks: Vec<HistoryBlock>,
      ) -> bool;
  }
  ```
  `apply_history_chunk` returns `false` for a chunk that does not abut the current front (a duplicate or out-of-order chunk), leaving the model untouched.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/crates/vt-core/tests/replay.rs`:

```rust
use vt_core::TerminalCore;

fn rows_of(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|index| snapshot.row_text(index).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

/// The shape of a real attach: origin, then the frame's rows, then history
/// newest→oldest. `origin` is what makes the mirror's and the renderer's
/// stable row spaces the same space.
fn attach(core: &mut TerminalCore, origin: u64, frame: &str) {
    core.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    core.feed(frame.as_bytes());
}

#[test]
fn an_origin_mark_adopts_the_replaying_hosts_row_space() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    assert_eq!(core.first_stable_row(), 0);
    attach(&mut core, 1000, "live\r\n");
    assert_eq!(core.first_stable_row(), 1000);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn an_origin_mark_after_rows_exist_is_ignored() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"live\r\n");
    core.feed(b"\x1b]7000;v=1;origin=9999\x1b\\");
    assert_eq!(core.first_stable_row(), 0);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn replay_prepends_history_without_moving_the_frame() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live one\r\nlive two\r\n");
    let before = rows_of(&core);
    assert_eq!(core.first_stable_row(), 1000);

    core.feed(b"\x1b]7000;v=1;history=");
    core.feed(b"998,2\x1b\\");
    core.feed(b"older one\r\nolder two\r\n");

    assert_eq!(core.first_stable_row(), 998);
    let after = rows_of(&core);
    assert_eq!(&after[..2], &["older one".to_string(), "older two".to_string()]);
    assert_eq!(&after[2..], &before[..]);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn a_history_chunk_that_does_not_abut_the_front_is_ignored() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");
    let before = rows_of(&core);

    core.feed(b"\x1b]7000;v=1;history=1050,2\x1b\\");
    core.feed(b"bogus one\r\nbogus two\r\n");

    assert_eq!(core.first_stable_row(), 1000);
    assert_eq!(rows_of(&core), before);
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn two_history_chunks_prepend_oldest_last() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");

    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"middle\r\n");
    core.feed(b"\x1b]7000;v=1;history=998,1\x1b\\");
    core.feed(b"oldest\r\n");

    assert_eq!(
        rows_of(&core),
        vec![
            "oldest".to_string(),
            "middle".to_string(),
            "live".to_string()
        ]
    );
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(core.verify_integrity(), Ok(()));
}
```

`attach`'s `origin` is `1000` in every test so the underflow that a fresh core's `first_stable_row() == 0` would produce cannot hide a bug: a chunk numbered below the origin is a real out-of-order chunk and must be dropped, which `a_history_chunk_that_does_not_abut_the_front_is_ignored` pins from the other side.

The first three tests need Task 3's receiver to pass; this task makes the **primitives** they rest on, and pins those directly. Add, to the `tests` module at the end of `packages/terminal/crates/vt-core/src/content.rs`:

```rust
    #[test]
    fn prepend_allocates_below_the_current_start() {
        let mut c = Content::with_base(1024);
        c.push_char("b");
        let start = c.prepend(b"aa");
        assert_eq!(start, 1022);
        assert_eq!(c.start_offset(), 1022);
        assert_eq!(c.copy_range(1022, 1025), b"aab");
    }

    #[test]
    fn two_prepends_stay_offset_ordered() {
        let mut c = Content::with_base(1024);
        c.push_char("c");
        let second = c.prepend(b"b");
        let first = c.prepend(b"a");
        assert!(first < second);
        assert_eq!(c.copy_range(first, c.end_offset()), b"abc");
    }

    #[test]
    fn drop_before_still_releases_only_whole_chunks_after_a_prepend() {
        let mut c = Content::with_base(1024);
        c.push_char("z");
        let start = c.prepend(b"yy");
        c.drop_before(start + 2);
        assert_eq!(c.start_offset(), 1024);
        assert_eq!(c.copy_range(1024, 1025), b"z");
    }
```

and to the `tests` module at the end of `packages/terminal/crates/vt-core/src/attribute_map.rs`:

```rust
    #[test]
    fn prepended_runs_read_back_in_their_own_region() {
        let mut map = AttributeMap::with_base(0u8, 100);
        map.set_from(100, 7);
        map.set_from(102, 9);
        map.prepend_runs(&[(98, 3u8), (100, 4u8)]);
        assert_eq!(map.runs(96, 100), vec![(2, 3u8), (4, 4u8)]);
        assert_eq!(map.runs(100, 102), vec![(2, 7u8)]);
    }
```

and to the `tests` module at the end of `packages/terminal/crates/vt-core/src/block_grid.rs`:

```rust
    #[test]
    fn retreat_origin_keeps_existing_blocks_at_their_stable_rows() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(4);
        grid.push_synthetic(0, 4, BlockState::Finished, Some(0));
        let stable_before = grid.get(0).expect("block").first_row;
        grid.retreat_origin(3);
        assert_eq!(grid.origin(), 0);
        assert_eq!(grid.get(0).expect("block").first_row, stable_before);
        assert_eq!(grid.flat_extent(grid.get(0).expect("block")), (3, 4));
    }

    #[test]
    fn prepended_blocks_sort_before_the_existing_ones() {
        let mut grid = BlockGrid::new();
        grid.sync_next_row(2);
        grid.push_synthetic(0, 2, BlockState::Finished, Some(0));
        grid.retreat_origin(2);
        grid.prepend_blocks(vec![Block {
            id: 900,
            first_row: 0,
            row_count: 2,
            state: BlockState::Finished,
            source: BlockSource::Synthetic,
            meta: BlockMeta::default(),
        }]);
        let ids: Vec<_> = grid.blocks().map(|block| block.id).collect();
        assert_eq!(ids, vec![900, 0]);
    }
```

`BlockGrid`'s test module already imports `BlockState`; add `Block`, `BlockMeta` and `BlockSource` to that `use` line if they are not there, and check `BlockSource::Synthetic`'s real name with `grep -n "enum BlockSource" -A 8 /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/src/block.rs` — use whatever variant `push_synthetic` assigns.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core prepend
```
Expected: FAIL — `no function or associated item named with_base found for struct Content`.

- [ ] **Step 3: `Content::with_base` and `Content::prepend`**

In `packages/terminal/crates/vt-core/src/content.rs`, add the constant next to `CHUNK_SIZE` and the two methods inside `impl Content`:

```rust
pub(crate) const CONTENT_BASE: u64 = 1 << 48;
```

```rust
    pub fn with_base(base: u64) -> Self {
        Self {
            chunks: VecDeque::new(),
            next_offset: base,
        }
    }

    pub fn prepend(&mut self, bytes: &[u8]) -> u64 {
        if bytes.is_empty() {
            return self.start_offset();
        }
        let start = self.start_offset() - bytes.len() as u64;
        self.chunks.push_front(Chunk {
            start,
            bytes: bytes.to_vec(),
        });
        start
    }
```

- [ ] **Step 4: `AttributeMap::with_base` and `prepend_runs`**

In `packages/terminal/crates/vt-core/src/attribute_map.rs`, inside `impl<A: Copy + Eq> AttributeMap<A>`:

```rust
    pub fn with_base(initial: A, base: u64) -> Self {
        Self {
            ends: BTreeMap::new(),
            tail: initial,
            run_start: base,
        }
    }

    pub fn prepend_runs(&mut self, runs: &[(u64, A)]) {
        for (end, value) in runs {
            self.ends.insert(*end, *value);
        }
    }
```

`prepend_runs` deliberately never touches `run_start` or `tail`: those track the *append* cursor, and a prepended region lies entirely below it.

- [ ] **Step 5: `RowIndex::prepend`**

In `packages/terminal/crates/vt-core/src/row_index.rs`, inside `impl RowIndex`:

```rust
    pub fn prepend(&mut self, rows: Vec<RowRange>) {
        for row in rows.into_iter().rev() {
            self.completed.push_front(row);
        }
    }
```

- [ ] **Step 6: `BlockGrid::retreat_origin` and `prepend_blocks`**

In `packages/terminal/crates/vt-core/src/block_grid.rs`, inside `impl BlockGrid`, next to `advance_origin`:

```rust
    pub fn retreat_origin(&mut self, prepended: usize) {
        self.origin = self.origin.saturating_sub(prepended);
    }

    pub fn prepend_blocks(&mut self, blocks: Vec<Block>) {
        if blocks.is_empty() {
            return;
        }
        let existing: Vec<Block> = self.closed.iter().cloned().collect();
        self.closed = BlockTree::new();
        for block in blocks.into_iter().chain(existing) {
            self.closed.push(block);
        }
    }
```

`prepend_blocks` rebuilds the closed tree because `BlockTree` is a B-tree with an append-only `push`; a real `push_front` would be a second insertion path for a call that runs at most once per 512-row chunk over a few thousand blocks. If `Block` is not `Clone`, derive it — `BlockMeta` and `BlockSource` already are.

- [ ] **Step 7: Base the parser's content and styles**

In `packages/terminal/crates/vt-core/src/parser.rs`, in `Parser::new` (`:48-74`), replace the two initialisers:

```rust
            content: Content::with_base(crate::content::CONTENT_BASE),
            rows: RowIndex::new(crate::content::CONTENT_BASE),
            styles: AttributeMap::with_base(CellStyle::DEFAULT, crate::content::CONTENT_BASE),
```

- [ ] **Step 8: `Parser::adopt_origin`**

Add to `packages/terminal/crates/vt-core/src/parser.rs`, next to `trim_to`:

```rust
    pub fn adopt_origin(&mut self, origin: u64) -> bool {
        if self.trimmed_total != 0 || !self.rows.completed().is_empty() {
            return false;
        }
        self.trimmed_total = origin;
        self.grid.advance_origin(origin as usize);
        self.note_mutation();
        true
    }
```

`advance_origin` (`block_grid.rs:52`) both moves `origin` and pushes `next_row` up to it, which is what keeps `verify_integrity`'s `OriginMismatch` (`integrity.rs:57-62`) and `NextRowPastEnd` satisfied — the two counters move together by construction. Expose it on `TerminalCore` in `lib.rs` next to `first_stable_row` (`:336`):

```rust
    pub fn adopt_origin(&mut self, origin: u64) -> bool {
        let adopted = self.parser.adopt_origin(origin);
        self.debug_check();
        adopted
    }
```

- [ ] **Step 9: `Parser::apply_history_chunk`**

Add to `packages/terminal/crates/vt-core/src/parser.rs`, and the two structs above `impl Parser` (they are public API, so re-export them from `lib.rs` next to `pub use grid::ExportedRow;` as `pub use parser::{HistoryBlock, HistoryRow};`):

```rust
pub struct HistoryRow {
    pub bytes: Vec<u8>,
    pub wrapped: bool,
    pub indent: u16,
    pub styles: Vec<(u32, CellStyle)>,
}

pub struct HistoryBlock {
    pub first_row: usize,
    pub row_count: usize,
    pub command: String,
    pub exit_code: Option<i32>,
}
```

```rust
    pub fn apply_history_chunk(
        &mut self,
        first_stable_row: u64,
        rows: Vec<HistoryRow>,
        blocks: Vec<HistoryBlock>,
    ) -> bool {
        if rows.is_empty() || first_stable_row + rows.len() as u64 != self.trimmed_total {
            return false;
        }
        let mut bytes = Vec::new();
        let mut lengths = Vec::with_capacity(rows.len());
        for row in &rows {
            bytes.extend_from_slice(&row.bytes);
            lengths.push(row.bytes.len() as u64);
        }
        let base = self.content.prepend(&bytes);
        let mut runs: Vec<(u64, CellStyle)> = Vec::new();
        let mut ranges = Vec::with_capacity(rows.len());
        let mut cursor = base;
        for (row, length) in rows.iter().zip(lengths) {
            for (end, style) in &row.styles {
                runs.push((cursor + u64::from(*end), *style));
            }
            ranges.push(RowRange {
                start: cursor,
                end: cursor + length,
                wrapped: row.wrapped && length > 0,
                indent: row.indent,
            });
            cursor += length;
        }
        self.styles.prepend_runs(&runs);
        let count = ranges.len();
        self.rows.prepend(ranges);
        self.trimmed_total = first_stable_row;
        self.grid.retreat_origin(count);
        self.grid.prepend_blocks(
            blocks
                .into_iter()
                .map(|block| self.history_block(first_stable_row, block))
                .collect(),
        );
        self.history_exported_rows = 0;
        self.mark_full();
        self.note_mutation();
        true
    }

    fn history_block(&mut self, first_stable_row: u64, block: HistoryBlock) -> Block {
        let id = self.grid.next_id();
        self.grid.reserve_id();
        let mut meta = BlockMeta::default();
        meta.command = block.command;
        Block {
            id,
            first_row: (first_stable_row as usize) + block.first_row,
            row_count: block.row_count,
            state: BlockState::Finished,
            source: BlockSource::Extension,
            meta,
        }
    }
```

`BlockGrid::next_id()` already exists (`block_grid.rs:157`); add the one-line `pub fn reserve_id(&mut self) { self.next_id += 1; }` next to it so a prepended block's id can never collide with a live one. If `BlockMeta`'s command field is not a bare `String`, set it through the same path `set_meta_field("cmd", …)` uses — check `block_grid.rs:198-264` and mirror it exactly. `RowRange`, `Block`, `BlockMeta`, `BlockState` and `BlockSource` must be in `parser.rs`'s `use` list.

`history_exported_rows = 0` is the honest consequence of a prepend: every exported history row index shifted, so the whole history section must be re-exported. That is what `mark_full` says too; the pair is what makes `verify_integrity`'s `ExportPrefixPastRows` stay true.

- [ ] **Step 10: Extend the integrity checker**

In `packages/terminal/crates/vt-core/src/integrity.rs`, the existing `OriginMismatch` check (`:57-62`) already pins `grid.origin() as u64 == trimmed_total`, which a prepend must preserve — `retreat_origin(count)` and `trimmed_total = first_stable_row` move both by the same `count`. Add no new variant here; Task 8 adds the stale-width one.

- [ ] **Step 11: Run the unit tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core prepend && cargo test -p vt-core retreat_origin
```
Expected: PASS. `tests/replay.rs` still fails — Task 3 wires the receiver.

- [ ] **Step 12: Run the full Rust gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test -- --skip replay
```
Expected: PASS. Every existing test must survive the content rebase: nothing outside `content.rs`'s own unit tests asserts an absolute parser-level offset (verified on `ba6dd6d35`), and `build_snapshot` (`grid.rs:93-124`) builds row ranges relative to a fresh buffer. If a test does fail on an absolute offset, fix the test to read `content.start_offset()` rather than reverting the base.

- [ ] **Step 13: CHANGELOG**

Add under `## Unreleased` in `packages/terminal/CHANGELOG.md`:

```markdown
- vt-core: scrollback content is allocated from a base offset so a reopened pane can prepend history rows below the rows it already holds; `Parser::adopt_origin` puts a fresh core into the replaying host's stable row space and `Parser::apply_history_chunk` prepends rows, styles and blocks, moving `trimmed_total`/`BlockGrid::origin` together.
```

- [ ] **Step 14: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core packages/terminal/CHANGELOG.md && git commit -m "$(cat <<'MSG'
vt-core: adopt a replay origin and prepend history rows below flat row 0

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: `HistoryReceiver` — chunk bytes become prepended rows

**Why a second parser.** The chunk's bytes are a styled repaint of rows that are *not* the live screen, and they carry re-emitted `id=`/`cmd=`/`exit=` marks. Feeding them through `TerminalCore::feed_raw` would print them at the cursor and open blocks in the live grid — worse, a trailing `exit=` would reach `BlockGrid::close_block` (`crates/vt-core/src/block_grid.rs:118-127`) and close whatever block the live agent has open. The receiver therefore owns its own `vte::Parser`, its own `ScreenGrid` sized to the chunk, and its own `MarkDecoder`, and hands the finished rows to `Parser::apply_history_chunk`.

**Why the chunk's last byte is a row terminator.** The receiver ends a chunk at the `count`-th `\n` and hands everything after it back to the live path. Task 5 therefore writes a block's closing `exit=` mark **inside** the row it closes — `<row bytes><exit mark>\r\n` — so no chunk byte can ever fall through. A mark written after the final `\r\n` is exactly the leak this ordering exists to prevent.

**Files:**
- Create: `packages/terminal/crates/vt-core/src/history.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:59-70` (field), `:111-159` (`feed_at` routing), `:191-235` (`feed_raw`), `:1-40` (module + re-exports)
- Modify: `packages/terminal/crates/vt-core/src/event_bridge.rs` (the `ReplayReady`/`HistoryChunk` arm)
- Test: `packages/terminal/crates/vt-core/tests/replay.rs`

**Interfaces:**
- Consumes: Task 1's `MarkEvent::{ReplayOrigin, ReplayReady, HistoryChunk}`; Task 2's `Parser::adopt_origin`, `Parser::apply_history_chunk`, `HistoryRow`, `HistoryBlock`; `ScreenGrid::new(rows, cols)`, `ScreenGrid::row_cells(row)` and `ScreenGrid::content_rows()` (`screen.rs`; if `row_cells` is named differently, use whatever `grid::export_screen_row` reads at `grid.rs`).
- Produces:
  ```rust
  pub(crate) struct HistoryReceiver { /* private */ }
  impl HistoryReceiver {
      pub fn new() -> Self;
      pub fn is_active(&self) -> bool;
      /// Arms the receiver for `rows` rows starting at `first_stable_row`.
      pub fn begin(&mut self, first_stable_row: u64, rows: usize, cols: usize);
      /// Consumes as much of `bytes` as belongs to the open chunk and returns
      /// the count consumed. A complete chunk leaves `take()` ready.
      pub fn consume(&mut self, bytes: &[u8]) -> usize;
      pub fn take(&mut self) -> Option<(u64, Vec<HistoryRow>, Vec<HistoryBlock>)>;
  }
  // TerminalCore
  pub fn replay_ready(&self) -> bool;   // true once a READY mark has been seen
  ```
  `TerminalCore::replay_ready()` exists so a host embedding the core (and the bench harness in Task 13) can assert the ordering; the renderer does not read it.

- [ ] **Step 1: Write the failing test**

`packages/terminal/crates/vt-core/tests/replay.rs` already holds the three tests from Task 2's Step 1. Append two more:

```rust
#[test]
fn modes_are_replayed() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b[?1049h\x1b[?1006h\x1b[?1002h\x1b[?2004h\x1b[?1004h\x1b[?1h\x1b[?25l");
    assert!(core.alt_screen_active());
    assert!(core.sgr_mouse());
    assert_eq!(core.mouse_tracking_level(), 2);
    assert!(core.bracketed_paste());
    assert!(core.focus_reporting());
    assert!(core.application_cursor_keys());
}

#[test]
fn blocks_survive_reopen() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");
    core.feed(b"\x1b]7000;v=1;history=998,2\x1b\\");
    core.feed(b"\x1b]7000;v=1;id=b1;cmd=ls\x1b\\old one\r\nold two\x1b]7000;v=1;exit=0\x1b\\\r\n");

    let snapshot = core.snapshot().expect("snapshot");
    assert!(
        snapshot.blocks.iter().any(|block| block.row_count == 2),
        "the prepended block did not span both of its rows: {:?}",
        snapshot.blocks
    );
    assert_eq!(snapshot.block_command(0), "ls");
    assert_eq!(core.verify_integrity(), Ok(()));
}

// The chunk's closing `exit=` mark must never reach the live grid: in a real
// Claude session there IS an open block, and closing it is a visible defect
// (BlockGrid::close_block, crates/vt-core/src/block_grid.rs:118-127).
#[test]
fn a_history_chunks_marks_never_touch_the_live_block_grid() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    attach(&mut core, 1000, "");
    core.feed(b"\x1b]7000;v=1;id=live;cmd=claude\x1b\\");
    core.feed(b"live\r\n");
    let before = core.snapshot().expect("snapshot");
    let before_blocks = before.blocks.len();
    let open_before = before
        .blocks
        .iter()
        .filter(|block| block.state == BlockState::Running)
        .count();
    assert_eq!(open_before, 1, "the fixture did not leave a live block open");

    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b]7000;v=1;id=b9;cmd=pwd\x1b\\old\x1b]7000;v=1;exit=3\x1b\\\r\n");
    core.feed(b"after\r\n");

    let after = core.snapshot().expect("snapshot");
    assert_eq!(
        after.blocks.len(),
        before_blocks + 1,
        "the chunk's marks changed the live block count"
    );
    assert_eq!(
        after
            .blocks
            .iter()
            .filter(|block| block.state == BlockState::Running)
            .count(),
        1,
        "the chunk's exit mark closed the live block"
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}
```

`BlockRecord.state` is the `BlockState` enum itself, not a wire word (`crates/vt-core/src/block.rs:72-84`; `as_u32` at `:21-29` is only used by the wasm export), so the comparison above is direct. Add `use vt_core::BlockState;` to the test file's imports. `assert_eq!(open_before, 1, …)` runs before the interesting assertion on purpose: if the fixture ever stops leaving a block open, this test would otherwise pass for the wrong reason — which is exactly how the pre-review version of it passed.

`modes_are_replayed` is the spec's name for the vt-core half of G's part 1; it pins that the core tracks every mode `vt_replay` will emit in Task 4, so Task 4 has something to read. `?1002h` reports `mouse_tracking_level() == 2` only if `note_private_mode` maps it that way — run the test first and record the level the tree actually reports for 1000/1002/1003, then assert that.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test replay
```
Expected: FAIL — `replay_prepends_history_without_moving_the_frame` reports `first_stable_row` unchanged; the history bytes were printed on the live screen.

- [ ] **Step 3: Write `history.rs`**

Create `packages/terminal/crates/vt-core/src/history.rs`:

```rust
use terminal_marks::{MarkDecoder, MarkEvent};
use vte::Parser as VteParser;

use crate::parser::{HistoryBlock, HistoryRow};
use crate::screen::ScreenGrid;

#[derive(Default)]
struct OpenBlock {
    first_row: usize,
    command: String,
}

pub(crate) struct HistoryReceiver {
    first_stable_row: u64,
    wanted: usize,
    seen_rows: usize,
    vte: VteParser,
    screen: Option<ScreenGrid>,
    marks: MarkDecoder,
    open: Option<OpenBlock>,
    blocks: Vec<HistoryBlock>,
    done: bool,
}

impl HistoryReceiver {
    pub fn new() -> Self {
        Self {
            first_stable_row: 0,
            wanted: 0,
            seen_rows: 0,
            vte: VteParser::new(),
            screen: None,
            marks: MarkDecoder::new(),
            open: None,
            blocks: Vec::new(),
            done: false,
        }
    }

    pub fn is_active(&self) -> bool {
        self.screen.is_some()
    }

    pub fn begin(&mut self, first_stable_row: u64, rows: usize, cols: usize) {
        let mut screen = ScreenGrid::new(rows.max(1), cols.max(1));
        screen.set_records_eviction(false);
        self.first_stable_row = first_stable_row;
        self.wanted = rows;
        self.seen_rows = 0;
        self.vte = VteParser::new();
        self.screen = Some(screen);
        self.marks = MarkDecoder::new();
        self.open = None;
        self.blocks.clear();
        self.done = false;
    }

    pub fn consume(&mut self, bytes: &[u8]) -> usize {
        let Some(screen) = self.screen.as_mut() else {
            return 0;
        };
        let mut consumed = 0usize;
        for (index, byte) in bytes.iter().enumerate() {
            for (_, event) in self.marks.feed_with_offsets(std::slice::from_ref(byte)) {
                note_mark(&mut self.open, &mut self.blocks, self.seen_rows, event);
            }
            self.vte.advance(screen, std::slice::from_ref(byte));
            consumed = index + 1;
            if *byte == b'\n' {
                self.seen_rows += 1;
                if self.seen_rows == self.wanted {
                    self.done = true;
                    break;
                }
            }
        }
        consumed
    }

    pub fn take(&mut self) -> Option<(u64, Vec<HistoryRow>, Vec<HistoryBlock>)> {
        if !self.done {
            return None;
        }
        let screen = self.screen.take()?;
        self.done = false;
        let rows = (0..self.wanted)
            .map(|row| history_row(&screen, row))
            .collect();
        if let Some(open) = self.open.take() {
            self.blocks.push(HistoryBlock {
                first_row: open.first_row,
                row_count: self.wanted - open.first_row,
                command: open.command,
                exit_code: None,
            });
        }
        Some((
            self.first_stable_row,
            rows,
            std::mem::take(&mut self.blocks),
        ))
    }
}

// `row` is `seen_rows`: the index of the row the mark sits in, because Task 5
// writes a block's closing mark before that row's CR-LF. The block therefore
// spans `first_row..=row`, which is `row + 1 - first_row` rows.
fn note_mark(
    open: &mut Option<OpenBlock>,
    blocks: &mut Vec<HistoryBlock>,
    row: usize,
    event: MarkEvent,
) {
    let MarkEvent::Extension(fields) = event else {
        return;
    };
    let mut exit: Option<Option<i32>> = None;
    let mut command: Option<String> = None;
    let mut opens = false;
    for (key, value) in fields.pairs {
        match key.as_str() {
            "id" => opens = true,
            "cmd" => command = Some(value),
            "exit" => exit = Some(value.parse::<i32>().ok()),
            _ => {}
        }
    }
    if opens {
        *open = Some(OpenBlock {
            first_row: row,
            command: command.unwrap_or_default(),
        });
        return;
    }
    if let Some(exit_code) = exit {
        if let Some(started) = open.take() {
            blocks.push(HistoryBlock {
                first_row: started.first_row,
                row_count: (row + 1).saturating_sub(started.first_row).max(1),
                command: started.command,
                exit_code,
            });
        }
    }
}

fn history_row(screen: &ScreenGrid, row: usize) -> HistoryRow {
    let exported = crate::grid::export_screen_row(screen, row);
    HistoryRow {
        bytes: exported.bytes,
        wrapped: false,
        indent: exported.indent,
        styles: exported.styles,
    }
}
```

`export_screen_row` (`crates/vt-core/src/grid.rs`) is already the one place that turns a screen row into `ExportedRow { bytes, indent, styles }`; reusing it is what keeps a prepended row byte-identical to the row the live core would have produced from the same cells. Make it `pub(crate)` if it is private.

- [ ] **Step 4: Route the bytes in `TerminalCore`**

In `packages/terminal/crates/vt-core/src/lib.rs`: add `mod history;` to the module list, add two fields to `TerminalCore` (`:59-70`) and their initialisers in `with_limits` (`:84-95`):

```rust
    history: history::HistoryReceiver,
    replay_ready: bool,
```
```rust
            history: history::HistoryReceiver::new(),
            replay_ready: false,
```

Then, at the very top of `feed_raw` (`:191`), before `self.sync.note_parsed(bytes)`, drain the receiver:

```rust
    fn feed_raw(&mut self, bytes: &[u8]) {
        let mut bytes = bytes;
        if self.history.is_active() {
            let consumed = self.history.consume(bytes);
            self.drain_history();
            bytes = &bytes[consumed..];
            if bytes.is_empty() {
                return;
            }
        }
        // the existing body of feed_raw, unchanged, operating on `bytes`
    }

    fn drain_history(&mut self) {
        if let Some((first_stable_row, rows, blocks)) = self.history.take() {
            self.parser.apply_history_chunk(first_stable_row, rows, blocks);
            self.debug_check();
        }
    }
```

The `MarkEvent` loop inside `feed_raw` (`:202-227`) is where a `HistoryChunk` arms the receiver. Because the loop applies each event only after the bytes *before* it have been parsed (the stream-order rule `TERMINAL.md` §4.15 depends on), arming there is exactly right: the rest of the chunk is what follows the mark. Add, in the `match event` block next to `MarkEvent::InputReady`:

```rust
                MarkEvent::ReplayOrigin(origin) => {
                    self.parser.adopt_origin(origin);
                    parsed = upto;
                    continue;
                }
                MarkEvent::ReplayReady => {
                    self.replay_ready = true;
                    parsed = upto;
                    continue;
                }
                MarkEvent::HistoryChunk {
                    first_stable_row,
                    rows,
                } => {
                    let cols = self.parser.columns();
                    self.history.begin(first_stable_row, rows, cols);
                    let rest = &bytes[upto..];
                    let consumed = self.history.consume(rest);
                    self.drain_history();
                    parsed = upto + consumed;
                    continue;
                }
```

`continue` skips `apply_event` for all three variants, so none of them ever reaches the block grid. `ReplayOrigin` is applied at exactly the point in the stream where the mark sat, which matters: the bytes before it have been parsed (there are none on a fresh attach) and `adopt_origin` refuses to act once any row exists, so the only stream position where it can succeed is the one `vt_replay` puts it in. The `MarkEvent::ReplayOrigin(_) | MarkEvent::ReplayReady | MarkEvent::HistoryChunk { .. } => {}` arm added to `event_bridge.rs` in Task 1 stays as the belt-and-braces no-op.

Finally add the accessor next to `synchronized_output` (`:169`):

```rust
    pub fn replay_ready(&self) -> bool {
        self.replay_ready
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test replay
```
Expected: PASS — all six tests.

- [ ] **Step 6: Run the guards that own this path**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test process_boundary --test integrity --test blocks_from_marks --test synchronized_output
```
Expected: PASS. `tests/integrity.rs`'s proptest must stay clean; if it finds a case, fix the model, never the invariant.

- [ ] **Step 7: Run the full Rust gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
```
Expected: PASS.

- [ ] **Step 8: Rebuild both wasm artifacts and the daemon**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: every command PASS; `npm run bench:feel` prints `PASS feel gate: zero pixel diff`.

- [ ] **Step 9: CHANGELOG and commit**

Add under `## Unreleased`:

```markdown
- vt-core: an `origin=` mark puts a fresh core into the replaying host's stable row space; a `history=` mark routes the bytes that follow it into a chunk receiver that prepends them as scrollback rows and blocks instead of printing them at the cursor, and no chunk byte — including a block's closing `exit=` — reaches the live block grid; a `ready=1` mark is recorded as `TerminalCore::replay_ready()`.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "$(cat <<'MSG'
vt-core: apply replayed history chunks below the live frame

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 4: `vt_replay` emits the origin, the modes, the frame, then READY

**Files:**
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:248-358` (`vt_replay`)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go` (the two assertions that pin the replay's tail)
- Test: `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`

**Interfaces:**
- Consumes: `TerminalCore::{alt_screen_active, sgr_mouse, mouse_tracking_level, bracketed_paste, focus_reporting, application_cursor_keys}` (`vt-core/src/lib.rs:375,441-463`), `GridSnapshot::{cursor_visible, first_stable_row, row_count}`, Task 3's `modes_are_replayed` pinning that those accessors track the modes.
- Produces: the replay byte stream, in this order and no other:
  0. `\x1b]7000;v=1;origin=<frame_first_stable>\x1b\\`, where `frame_first_stable = snapshot.first_stable_row + total.saturating_sub(lines)` — the stable row of the **first row this replay emits**, and the same value `vt_history_chunk` resolves `HistoryBefore` to in Task 5;
  1. `\x1b[?1049h` when the alternate screen is active;
  2. one mode per **bit** of `mouse_tracking_level()`: `& 1 → \x1b[?1000h`, `& 2 → \x1b[?1002h`, `& 4 → \x1b[?1003h`; then `\x1b[?1006h` when `sgr_mouse`;
  3. `\x1b[?2004h` when `bracketed_paste`, `\x1b[?1004h` when `focus_reporting`, `\x1b[?1h` when `application_cursor_keys`;
  4. the clipped frame exactly as today (`TERMINAL.md` §4.7);
  5. `\x1b[?25l` when the cursor is hidden — unchanged, still after the cursor placement;
  6. the still-buffered sync bytes — unchanged (Plan A);
  7. `\x1b]7000;v=1;ready=1\x1b\\`.

  The origin mark is **first** because `Parser::adopt_origin` refuses to act once any row exists, so it must precede the frame's first row. READY is **last** so a client that paints at it has the whole frame, including the pending sync tail. An empty terminal still returns 0 bytes: a replay of nothing plus an origin and a READY mark is two marks with no frame, and the host reads 0 as "no replay frame to send".

  **`mouse_tracking_level()` is a bitmask, not an enum** (`crates/vt-core/src/parser.rs:341-343`: `1000 => 0b001`, `1002 => 0b010`, `1003 => 0b100`, OR-ed at `:346-350`). Matching it as `1 | 2 | 3` would never replay `?1003h` and would replay a child holding 1000+1002 as `?1003h`.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`:

```go
// The replay states the stable row its first row sits at, so the receiving
// core can adopt the host's row space. Without it the two stable spaces never
// meet and every history chunk is dropped as out of order.
func TestReplayOpensWithTheOriginMark(t *testing.T) {
	p := newTestParser(t, 20, 4)
	for i := 0; i < 40; i++ {
		feed(t, p, fmt.Sprintf("row %02d\r\n", i))
	}

	out, err := p.Replay(4)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasPrefix(out, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the replay does not open with an origin mark:\n%q", out)
	}
	origin := out[len("\x1b]7000;v=1;origin="):strings.Index(out, "\x1b\\")]
	if origin != "37" {
		t.Fatalf("origin = %q, want 37 (40 rows of history and screen, a 4-row frame)", origin)
	}
}

// The replay opens with the modes the child had set, so a reattached client
// encodes the mouse and paste the same way the child expects. xterm.js's
// SerializeAddon writes its mode list first for the same reason
// (xterm.js/src/common/addons/SerializeAddon.ts).
func TestReplayEmitsTheModesTheChildSet(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h\x1b[?2004h\x1b[?1004h\x1b[?1h")
	feed(t, p, "hello\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	// mouse_tracking_level is a bitmask: all three tracking modes are set, so
	// all three must be replayed (crates/vt-core/src/parser.rs:341-350).
	for _, mode := range []string{"\x1b[?1000h", "\x1b[?1002h", "\x1b[?1003h", "\x1b[?1006h", "\x1b[?2004h", "\x1b[?1004h", "\x1b[?1h"} {
		if !strings.Contains(out, mode) {
			t.Fatalf("replay is missing %q:\n%q", mode, out)
		}
		if strings.Index(out, mode) > strings.Index(out, "hello") {
			t.Fatalf("mode %q came after the frame:\n%q", mode, out)
		}
	}
}

// The client paints at READY, so READY must be the last byte of the frame —
// everything before it is one complete screen (Ghostty's READY-first snapshot,
// ghostty/src/termio/Termio.zig).
func TestReplayEndsWithTheReadyMark(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "done\r\n> hi")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(out, readyMark) {
		t.Fatalf("replay does not end at READY:\n%q", out)
	}
	if !strings.HasSuffix(strings.TrimSuffix(out, readyMark), "\r\x1b[4C") {
		t.Fatalf("the cursor placement must still be the last thing before READY:\n%q", out)
	}
}

// A terminal that has drawn nothing replays nothing — a READY mark alone is a
// mark with no frame, and the host reads an empty replay as "send nothing".
func TestAnEmptyTerminalStillReplaysNothing(t *testing.T) {
	p := newTestParser(t, 80, 24)
	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if out != "" {
		t.Fatalf("an untouched terminal replayed %q", out)
	}
}
```

Add at the top of the file, under the imports, and add `"fmt"` to them:

```go
const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"
```

`origin != "37"` above is the value for *this* fixture: 40 rows written on a 4-row grid leaves 40 completed-plus-screen rows in a mirror that has trimmed nothing, and a 4-row frame starts at row 36 — run the test once and use the number it reports, then assert that number, so the test pins the arithmetic rather than restating it.

- [ ] **Step 2: Update the guard that pins the old tail**

`TestReplayRestoresCursorColumn` (`replay_test.go:62-73`) asserts `strings.HasSuffix(out, "\r\x1b[4C")`. READY now follows the cursor placement. Change its assertion to:

```go
	if !strings.HasSuffix(strings.TrimSuffix(out, readyMark), "\r\x1b[4C") {
		t.Fatalf("want the cursor parked at column 4, got:\n%q", out)
	}
```

This is the only existing replay assertion that pins the byte at the very end; `grep -n 'HasSuffix' /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go` before assuming so, and give any other one the same `TrimSuffix` treatment.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'TestReplayEmitsTheModes|TestReplayEndsWithTheReadyMark' -v
```
Expected: FAIL — the replay contains neither the modes nor the mark.

- [ ] **Step 4: Emit the modes and READY**

In `packages/terminal/crates/vt-host/src/lib.rs`, add the constant next to `RENDER_ERR`:

```rust
const READY_MARK: &str = "\x1b]7000;v=1;ready=1\x1b\\";
```

and a helper that resolves the frame's first stable row — **the one function Task 5 also calls**, so the origin mark and `HistoryBefore` can never disagree:

```rust
fn frame_first_stable(snapshot: &vt_core::GridSnapshot, lines: u32) -> u64 {
    snapshot.first_stable_row + snapshot.row_count().saturating_sub(lines as usize) as u64
}
```

and a helper above `vt_replay`:

```rust
fn write_modes(text: &mut String, core: &TerminalCore, alt: bool) {
    if alt {
        text.push_str("\x1b[?1049h");
    }
    // mouse_tracking_level is a bitmask, not an enum
    // (crates/vt-core/src/parser.rs:341-350).
    let tracking = core.mouse_tracking_level();
    if tracking & 0b001 != 0 {
        text.push_str("\x1b[?1000h");
    }
    if tracking & 0b010 != 0 {
        text.push_str("\x1b[?1002h");
    }
    if tracking & 0b100 != 0 {
        text.push_str("\x1b[?1003h");
    }
    if core.sgr_mouse() {
        text.push_str("\x1b[?1006h");
    }
    if core.bracketed_paste() {
        text.push_str("\x1b[?2004h");
    }
    if core.focus_reporting() {
        text.push_str("\x1b[?1004h");
    }
    if core.application_cursor_keys() {
        text.push_str("\x1b[?1h");
    }
}
```

The bit values are `note_private_mode`'s own (`crates/vt-core/src/parser.rs:341-343`); verify them before typing the helper, and if the tree assigns different bits use those.

In `vt_replay`, replace the alt branch's opening `text.push_str("\x1b[?1049h\x1b[H");` with:

```rust
            text.push_str(&format!(
                "\x1b]7000;v=1;origin={}\x1b\\",
                frame_first_stable(&snapshot, lines)
            ));
            write_modes(&mut text, core, true);
            text.push_str("\x1b[H");
```

and, in the normal branch, insert the same two statements immediately after the `blank`/`total == 0` early return and before the `let cols = core.columns();` line:

```rust
            text.push_str(&format!(
                "\x1b]7000;v=1;origin={}\x1b\\",
                frame_first_stable(&snapshot, lines)
            ));
            write_modes(&mut text, core, false);
```

Both go **after** the early return, so an empty terminal still returns 0 or the bare pending-sync bytes, unchanged.

Finally, at the end of `vt_replay`, after `out.extend_from_slice(core.pending_sync_bytes());` and the `if out.is_empty() { return 0; }` guard:

```rust
        out.extend_from_slice(READY_MARK.as_bytes());
```

The `is_empty` check stays **before** the READY append so an empty terminal is still an empty replay.

- [ ] **Step 5: Rebuild the host wasm and run the tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
```
Expected: PASS, including `TestReplayAfterAShrinkFitsTheGridAndKeepsEveryCell` (§4.7's guard), `TestReplayNeverStartsInsideASyncBlock` (§4.16's) and every `attach_replay_test.go` test.

- [ ] **Step 6: Run the Rust gate and rebuild the renderer wasm and daemon**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` reports zero pixel diff.

- [ ] **Step 7: CHANGELOG and commit**

```markdown
- vt-host: the attach replay opens with an `OSC 7000;v=1;origin=` mark naming the stable row of its first row, then the DEC modes the child set (`?1049`, each bit of the mouse-tracking mask as `?1000/1002/1003`, `?1006`, `?2004`, `?1004`, `?1`), and closes with an `OSC 7000;v=1;ready=1` mark, so a reattaching client shares the host's row space and paints the complete frame at a known point.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost && git commit -m "$(cat <<'MSG'
vt-host: replay the origin and the child's modes, and mark the frame ready

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 5: `vt_history_chunk` — history newest→oldest in 512-row chunks

**Files:**
- Modify: `packages/terminal/crates/vt-host/src/lib.rs` (new export, the chunk writer)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:247-249` (the `Replay` neighbourhood)
- Test: `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`

**Interfaces:**
- Consumes: Task 4's `READY_MARK` and clipped-row writer (`write_styled_row_with`, `clip_row`, `write_indent`, all in `vt-host/src/lib.rs`); `TerminalCore::{snapshot, first_stable_row, columns}`; `GridSnapshot::{row_count, row_text, row_indent, row_style_pairs, blocks, block_command, first_stable_row}`; `BlockRecord` (whatever `first_row`/`row_count`/`exit_code` fields `crates/vt-core/src/block.rs` gives it — read them, they are flat rows in the snapshot).
- Produces:
  ```rust
  pub const HISTORY_CHUNK_ROWS: u32 = 512;
  /// `before == u64::MAX` means "start just above the frame of `lines` rows".
  /// Writes one chunk and stores the chunk's own first stable row at
  /// `next_ptr` as 8 little-endian bytes. Returns the byte count written,
  /// 0 when no history remains, or RENDER_ERR / RENDER_TOO_BIG.
  #[no_mangle]
  pub extern "C" fn vt_history_chunk(
      handle: u32,
      before: u64,
      lines: u32,
      max_rows: u32,
      out_ptr: u32,
      out_cap: u32,
      next_ptr: u32,
  ) -> u32;
  ```
  ```go
  // vtwasm.go
  const HistoryChunkRows = 512
  // HistoryChunk returns one chunk of replay history and the stable row it
  // starts at, which is the `before` for the next call. ok is false once no
  // history remains above `before`.
  func (p *Parser) HistoryChunk(before uint64, lines, maxRows int) (chunk string, next uint64, ok bool, err error)
  // HistoryBefore is the sentinel that starts at the row just above the frame.
  const HistoryBefore = ^uint64(0)
  ```
  Each chunk is `\x1b]7000;v=1;history=<first>,<count>\x1b\\` followed by exactly `count` rows. A row is `<block open mark?><row bytes><exit mark?>\r\n`: **every row is CR-LF terminated including the last, and a block's closing `exit=` mark goes inside the row it closes, before that row's CR-LF.** The receiver in Task 3 consumes exactly `count` LFs and hands the remainder back to the live path, so any byte written after the final `\r\n` — a trailing `exit=` above all — falls through to the live parser and closes the live agent's open block (`BlockGrid::close_block`, `crates/vt-core/src/block_grid.rs:118-127`). That is R2; the ordering is the fix.

  `HistoryBefore` resolves through Task 4's `frame_first_stable(&snapshot, lines)` — **the same function that wrote the origin mark** — so the first chunk abuts the frame's first row exactly and `apply_history_chunk`'s abutment test passes on the first try.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`:

```go
// The whole replay, in order: modes, the live frame, READY, then history
// newest→oldest. A client can paint at READY and prepend the rest behind it.
func TestReplayOrderIsModesFrameReadyHistory(t *testing.T) {
	p := newTestParser(t, 20, 4)
	feed(t, p, "\x1b[?1006h")
	for i := 0; i < 40; i++ {
		feed(t, p, fmt.Sprintf("row %02d\r\n", i))
	}

	frame, err := p.Replay(4)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if !strings.HasSuffix(frame, readyMark) {
		t.Fatalf("the frame does not end at READY:\n%q", frame)
	}
	if !strings.HasPrefix(frame, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the origin mark is not the first bytes of the frame:\n%q", frame)
	}
	if strings.Index(frame, "\x1b[?1006h") > strings.Index(frame, "row 3") {
		t.Fatalf("the modes did not come first:\n%q", frame)
	}
	origin := frame[len("\x1b]7000;v=1;origin="):strings.Index(frame, "\x1b\\")]

	var chunks []string
	before := HistoryBefore
	for i := 0; i < 20; i++ {
		chunk, next, ok, err := p.HistoryChunk(before, 4, 8)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		if !strings.HasPrefix(chunk, "\x1b]7000;v=1;history=") {
			t.Fatalf("chunk %d is not framed by a history mark:\n%q", i, chunk)
		}
		if !strings.HasSuffix(chunk, "\r\n") {
			t.Fatalf("chunk %d does not terminate its last row:\n%q", i, chunk)
		}
		chunks = append(chunks, chunk)
		before = next
	}
	if len(chunks) == 0 {
		t.Fatal("no history chunk was produced for a 40-row session on a 4-row grid")
	}
	if !strings.Contains(chunks[0], "row 3") {
		t.Fatalf("the first chunk is not the newest history:\n%q", chunks[0])
	}
	if !strings.Contains(chunks[len(chunks)-1], "row 00") {
		t.Fatalf("the last chunk is not the oldest history:\n%q", chunks[len(chunks)-1])
	}
	// The first chunk must abut the frame: its history mark's first stable row
	// plus its count is the origin the frame declared.
	first, count := parseHistoryMark(t, chunks[0])
	if got := strconv.FormatUint(first+uint64(count), 10); got != origin {
		t.Fatalf("the first chunk ends at stable row %s, but the frame starts at %s", got, origin)
	}
}

// A block's closing mark belongs inside its last row. Anything written after a
// chunk's final CR-LF falls through to the live parser, where an exit mark
// closes the live agent's block (BlockGrid::close_block,
// crates/vt-core/src/block_grid.rs:118-127).
func TestAHistoryChunkEndsAtARowTerminator(t *testing.T) {
	p := newTestParser(t, 20, 2)
	feed(t, p, "\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x1b\\")
	for i := 0; i < 8; i++ {
		feed(t, p, fmt.Sprintf("out %02d\r\n", i))
	}
	feed(t, p, "\x1b]133;D;0\x07")
	for i := 0; i < 20; i++ {
		feed(t, p, fmt.Sprintf("tail %02d\r\n", i))
	}

	before := HistoryBefore
	for {
		chunk, next, ok, err := p.HistoryChunk(before, 2, HistoryChunkRows)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		if !strings.HasSuffix(chunk, "\r\n") {
			t.Fatalf("a chunk ends past its last row terminator:\n%q", chunk)
		}
		if strings.Contains(chunk, "\x1b\\\r\n\x1b]7000;v=1;exit=") {
			t.Fatalf("an exit mark was written after a row terminator:\n%q", chunk)
		}
		before = next
	}
}

func parseHistoryMark(t *testing.T, chunk string) (uint64, int) {
	t.Helper()
	const prefix = "\x1b]7000;v=1;history="
	end := strings.Index(chunk, "\x1b\\")
	if !strings.HasPrefix(chunk, prefix) || end < 0 {
		t.Fatalf("not a history chunk: %q", chunk)
	}
	parts := strings.Split(chunk[len(prefix):end], ",")
	if len(parts) != 2 {
		t.Fatalf("malformed history mark: %q", chunk[:end])
	}
	first, err := strconv.ParseUint(parts[0], 10, 64)
	if err != nil {
		t.Fatalf("history mark first row: %v", err)
	}
	count, err := strconv.Atoi(parts[1])
	if err != nil {
		t.Fatalf("history mark count: %v", err)
	}
	return first, count
}

// The common case: a fresh session whose mirror holds less than the frame.
// Nothing about its attach may change.
func TestAFreshSessionProducesNoHistoryChunk(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "just started\r\n")
	_, _, ok, err := p.HistoryChunk(HistoryBefore, 1000, HistoryChunkRows)
	if err != nil {
		t.Fatalf("history chunk: %v", err)
	}
	if ok {
		t.Fatal("a session smaller than one replayed frame produced a history chunk")
	}
}

// Every replayed row is clipped to the grid, history included: a row wider
// than the client's grid wraps into two and shifts every row below it
// (TERMINAL.md §4.7).
func TestHistoryChunkRowsAreClippedToTheGrid(t *testing.T) {
	p := newTestParser(t, 10, 2)
	for i := 0; i < 12; i++ {
		feed(t, p, "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n")
	}
	chunk, _, ok, err := p.HistoryChunk(HistoryBefore, 2, HistoryChunkRows)
	if err != nil || !ok {
		t.Fatalf("history chunk: %v ok=%v", err, ok)
	}
	body := chunk[strings.Index(chunk, "\x1b\\")+2:]
	for _, row := range strings.Split(strings.TrimSuffix(body, "\r\n"), "\r\n") {
		plain := stripSGR(row)
		if len([]rune(plain)) > 10 {
			t.Fatalf("a history row is %d columns wide on a 10-column grid: %q", len([]rune(plain)), plain)
		}
	}
}
```

`stripSGR` is a three-line helper (`regexp.MustCompile("\x1b\\[[0-9;]*m")` with `ReplaceAllString`); add it next to `feed` if the file has no equivalent. Add `"fmt"`, `"regexp"` and `"strconv"` to the imports.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'TestReplayOrderIsModesFrameReadyHistory|TestAFreshSession|TestHistoryChunkRows' -v
```
Expected: FAIL — `p.HistoryChunk undefined`.

- [ ] **Step 3: Write `vt_history_chunk`**

In `packages/terminal/crates/vt-host/src/lib.rs`:

```rust
pub const HISTORY_CHUNK_ROWS: u32 = 512;

#[no_mangle]
pub extern "C" fn vt_history_chunk(
    handle: u32,
    before: u64,
    lines: u32,
    max_rows: u32,
    out_ptr: u32,
    out_cap: u32,
    next_ptr: u32,
) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Ok(snapshot) = core.snapshot() else {
            return RENDER_ERR;
        };
        let first_stable = snapshot.first_stable_row;
        let bound_stable = if before == u64::MAX {
            frame_first_stable(&snapshot, lines)
        } else {
            before
        };
        if bound_stable <= first_stable {
            return 0;
        }
        let bound = (bound_stable - first_stable) as usize;
        let count = bound.min(max_rows.max(1) as usize);
        let start = bound - count;
        let chunk_first_stable = first_stable + start as u64;

        let mut text = format!(
            "\x1b]7000;v=1;history={},{}\x1b\\",
            chunk_first_stable, count
        );
        let cols = core.columns();
        for row in start..bound {
            write_block_open(&mut text, &snapshot, row);
            let indent = snapshot.row_indent(row).min(cols.saturating_sub(1));
            let (row_bytes, pairs) = clip_row(
                snapshot.row_text(row).as_bytes(),
                snapshot.row_style_pairs(row),
                cols - indent,
            );
            write_indent(&mut text, indent);
            // The closing mark is the row's terminator, not a separate line:
            // a byte after the chunk's final CR-LF falls through to the live
            // parser (Task 3's receiver ends the chunk at the count-th LF).
            let mut terminator = String::new();
            write_block_close(&mut terminator, &snapshot, row);
            terminator.push_str("\r\n");
            write_styled_row_with(&mut text, row_bytes, &pairs, &terminator);
        }

        let out = text.into_bytes();
        if out.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
            std::ptr::copy_nonoverlapping(
                chunk_first_stable.to_le_bytes().as_ptr(),
                next_ptr as *mut u8,
                8,
            );
        }
        out.len() as u32
    })
}
```

`write_block_open(text, snapshot, row)` emits, before a row that is some block's flat `first_row`, `\x1b]7000;v=1;id=<index>;cmd=<percent-encoded command>\x1b\\`. `write_block_close(text, snapshot, row)` emits `\x1b]7000;v=1;exit=<code>\x1b\\` when `row` is the **last** row of a block that has an exit code (`first_row + row_count - 1`), and nothing otherwise — no `pending_exit` state is needed, because the mark now belongs to a row rather than to the gap after it. Percent-encode `;`, `=`, `%` and every byte below 0x20 in the command — `crates/marks/src/extension.rs:74-98` is the decoder those escapes must survive. Write both as small private helpers in the same file; a linear scan of `snapshot.blocks` per row is fine at 512 rows, but if the block count makes it quadratic, build one `Vec<Option<&BlockRecord>>` indexed by row before the loop.

`write_styled_row_with` (`crates/vt-host/src/lib.rs:392`) writes `\x1b[0m` then the terminator, so passing `<exit mark>\r\n` as the terminator puts the mark after the row's SGR reset and before its CR-LF — exactly where Task 3's `note_mark` expects it, at `seen_rows == row`.

- [ ] **Step 4: Wire the Go side**

In `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go`, after `Replay`:

```go
const (
	HistoryChunkRows = 512
	HistoryBefore    = ^uint64(0)
)

const historyNextBytes = 8

func (p *Parser) HistoryChunk(before uint64, lines, maxRows int) (string, uint64, bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, renderBufferBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc history buffer: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), renderBufferBytes) }()
	res, err = p.module.ExportedFunction("vt_alloc").Call(p.ctx, historyNextBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc history cursor: %w", err)
	}
	next := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(next), historyNextBytes) }()

	res, err = p.module.ExportedFunction("vt_history_chunk").
		Call(p.ctx, uint64(p.handle), before, uint64(lines), uint64(maxRows), uint64(out), renderBufferBytes, uint64(next))
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: history_chunk: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", 0, false, nil
	case renderErr:
		return "", 0, false, fmt.Errorf("vtwasm: history_chunk failed for handle %d", p.handle)
	case renderTooBig:
		return "", 0, false, fmt.Errorf("vtwasm: history_chunk exceeds %d bytes", renderBufferBytes)
	default:
		body, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		cursor, ok := p.module.Memory().Read(next, historyNextBytes)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read history cursor out of range")
		}
		return string(body), binary.LittleEndian.Uint64(cursor), true, nil
	}
}
```

If a 512-row chunk of heavily styled rows can exceed `renderBufferBytes` (1 MiB), `HistoryChunk` returns the `renderTooBig` error; Task 6's caller treats an error as "stop streaming history" and logs it, never as a reason to drop the client.

- [ ] **Step 5: Rebuild the host wasm and run the tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
```
Expected: PASS.

- [ ] **Step 6: Round-trip the chunk through the receiving core**

Add to `packages/terminal/crates/vt-core/tests/replay.rs` — the one test that proves the two halves agree without a live daemon:

```rust
#[test]
fn a_chunk_shaped_like_the_hosts_prepends_cleanly() {
    let mut core = TerminalCore::new(12, 10_000).expect("core");
    attach(&mut core, 1000, "live\r\n");
    core.feed(
        b"\x1b]7000;v=1;history=998,2\x1b\\\x1b[0mold one\x1b[0m\r\n\x1b[0mold two\x1b[0m\x1b]7000;v=1;exit=0\x1b\\\r\n",
    );
    core.feed(b"next\r\n");

    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(rows_of(&core), vec!["old one", "old two", "live", "next"]);
    assert_eq!(core.verify_integrity(), Ok(()));
}
```

The chunk above is byte-for-byte the shape Task 5 emits, closing mark included: an `exit=` inside the last row, before its CR-LF. If the receiver ever regresses to ending a chunk early, `next` lands in the wrong place and this test says so.

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test replay
```
Expected: PASS.

- [ ] **Step 7: Full gate, rebuild both wasm artifacts and the daemon**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` zero pixel diff.

- [ ] **Step 8: CHANGELOG and commit**

```markdown
- vt-host: `vt_history_chunk` serialises scrollback newest→oldest in 512-row chunks, each framed by an `OSC 7000;v=1;history=<first_stable_row>,<count>` mark with its blocks re-emitted as `id=`/`cmd=`/`exit=` inside the rows they span, so a reattaching client recovers the whole session instead of the mirror's last screen and no chunk byte reaches its live block grid.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost && git commit -m "$(cat <<'MSG'
vt-host: serialise scrollback as framed history chunks

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 6: `attach.go` streams the five parts to clients that ask; the handshake returns after READY

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go:36-40` (`ResizePayload.History`)
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go:78-107` (`clientState.wantsHistory`), `:712-721` (the registration hold), `:769-791` (`replayFrameLocked`)
- Modify: `backend/internal/adapters/runtime/ptyhost/attach.go:25-74` (`Attach`/`AttachWithHistory`), `:83-126` (`attachHandshake`), `:185-193` (`writeResize`)
- Modify: `backend/internal/ports/outbound.go:185-206` (`HistoryAttacher`)
- Test: `backend/internal/adapters/runtime/ptyhost/attach_replay_test.go`

**Interfaces:**
- Consumes: Task 4's origin mark and READY-terminated frame from `Parser.Replay(MaxOutputLines)`; Task 5's `Parser.HistoryChunk(before, lines, maxRows)`, `HistoryBefore`, `HistoryChunkRows`.
- Produces:
  ```go
  // proto.go — the opening MsgResize, which is already the registration
  // message, carries the opt-in. No new message type.
  type ResizePayload struct {
      Cols    int  `json:"cols"`
      Rows    int  `json:"rows"`
      History bool `json:"history,omitempty"`
  }
  // ports/outbound.go — optional, asserted at the call site like PaneCapturer,
  // so every other Attacher implementation stays untouched.
  type HistoryAttacher interface {
      AttachWithHistory(ctx context.Context, handle RuntimeHandle, rows, cols uint16, history bool) (Stream, error)
  }
  // attach.go — Attach keeps its signature and means "no history".
  func (r *Runtime) Attach(ctx context.Context, handle ports.RuntimeHandle, rows, cols uint16) (ports.Stream, error)
  func (r *Runtime) AttachWithHistory(ctx context.Context, handle ports.RuntimeHandle, rows, cols uint16, history bool) (ports.Stream, error)
  func attachHandshake(conn net.Conn, rows, cols uint16, history bool) ([][]byte, error)
  // host.go — replayFrameLocked keeps its signature and its meaning: the ONE
  // frame a newly registered client is queued under h.mu. History is queued
  // after the lock is released, and only for a client that asked.
  func (h *host) replayFrameLocked() []byte
  func (h *host) streamHistory(cs *clientState)
  ```
  On `clientState`: `wantsHistory bool`, set from the opening resize. `attachHandshake` returns as soon as it has seen the READY mark *or* the status reply, whichever comes first — a session with no replay never sends READY, and the status reply is still the backstop it is today.

**Why history is opt-in.** The desktop renderer's core understands OSC 7000 history marks after Tasks 1–3. **The mobile client does not**: it renders with the vendored xterm fork (`packages/mobile/packages/xterm`), whose OSC dispatch sends anything it does not recognise to `unknownOSC` → `onPrivateOSC` (`lib/src/core/escape/parser.dart:1079`, `lib/src/terminal.dart:902-905`). So the origin, READY and history **marks** are harmless there — verified, they are not printed — but the history **rows** between them are ordinary text and would print up to 200k rows of session, newest→oldest, after the live frame. The prompt's rule that an old client keeps working applies to G exactly as it does to H, so a client gets history only when it asks. Task 12 (mobile) deliberately does not ask.

**The capture stream is not a client.** `CaptureWorker` (`backend/internal/terminal/capture.go:39-56`) reads a journal on disk through `terminalcapture.Reader`; the journal is fed inside the pty-host by `h.capture.write(batch)` in `deliver` (`host.go:538`), which sees only live PTY batches. It is not an attach client, receives no replay frame and no history chunk, so the re-emitted `id=`/`cmd=`/`exit=` marks can never reach Operator's block store through it. Nothing to opt out of — recorded here because the question is worth not re-asking.

**Why history is queued off the lock.** `handleConn` (`host.go:712-721`) queues the replay under a single `h.mu` hold precisely so no PTY chunk can slip between the replay and the client joining the broadcast set. History is *older* than every byte in that frame, so it has no such race: it can be queued afterwards, from the same goroutine, while `deliver` runs freely. Doing it under the lock would hold `h.mu` for the whole 200k-row serialisation.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/adapters/runtime/ptyhost/attach_replay_test.go`:

```go
// A reattaching client must be able to paint as soon as it has the frame.
// The handshake therefore returns at READY, and the history that follows
// arrives on the live stream behind it.
func TestClientPaintsAtReadyBeforeHistory(t *testing.T) {
	f := startServeParsed(t, 710, 20, 4)
	defer f.cancel()

	for i := 0; i < 60; i++ {
		writeOutput(t, f, fmt.Sprintf("row %02d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 59")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	first := readReplay(t, c)
	if !strings.HasPrefix(first, "\x1b]7000;v=1;origin=") {
		t.Fatalf("the first terminal frame does not open with the origin mark:\n%q", first)
	}
	if !strings.HasSuffix(first, readyMark) {
		t.Fatalf("the first terminal frame is not a READY-terminated replay:\n%q", first)
	}
	if strings.Contains(first, "history=") {
		t.Fatalf("history was packed into the frame the client paints:\n%q", first)
	}

	stream := first
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, "row 00") {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	if !strings.Contains(stream, "\x1b]7000;v=1;history=") {
		t.Fatalf("no history chunk followed the replay:\n%q", stream)
	}

	// End to end: the whole stream, fed to a fresh core, must reconstruct the
	// session with row 00 at the top. "A chunk arrived" is not the property
	// under test — "the chunks were prepended" is.
	mirror, err := vtwasm.New(context.Background(), vtwasm.Module, 20, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new mirror: %v", err)
	}
	defer mirror.Close()
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed the replay stream: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if len(rows) == 0 || !strings.Contains(rows[0], "row 00") {
		t.Fatalf("the replayed history was not prepended; first row = %q", rows[0])
	}
	if !strings.Contains(rows[len(rows)-1], "row 59") {
		t.Fatalf("the live frame did not stay at the bottom; last row = %q", rows[len(rows)-1])
	}
}

// A client that does not ask for history gets exactly today's attach. The
// mobile build renders with an xterm fork that would print the rows.
func TestAClientWithoutHistoryOptInGetsNoChunks(t *testing.T) {
	f := startServeParsed(t, 712, 20, 4)
	defer f.cancel()

	for i := 0; i < 60; i++ {
		writeOutput(t, f, fmt.Sprintf("row %02d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 59")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)

	replay := readReplay(t, c)
	if strings.Contains(replay, "history=") {
		t.Fatalf("a client that did not opt in was sent history:\n%q", replay)
	}
	writeOutput(t, f, "live after attach\r\n")
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		typ, payload := c.readFrame(t)
		if typ != MsgTerminalData {
			continue
		}
		if strings.Contains(string(payload), "history=") {
			t.Fatalf("a history chunk reached a client that did not opt in:\n%q", payload)
		}
		if strings.Contains(string(payload), "live after attach") {
			return
		}
	}
	t.Fatal("the live byte that proves nothing else was queued first never arrived")
}

// A fresh session whose mirror holds less than one replayed frame must attach
// exactly as it does today: one frame, no history, nothing else.
func TestAFreshSessionAttachIsUnchanged(t *testing.T) {
	f := startServeParsed(t, 711, 80, 24)
	defer f.cancel()

	writeOutput(t, f, "hello\r\n")
	waitForParsedOutput(t, f, "hello")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 80, 24)

	replay := readReplay(t, c)
	if !strings.Contains(replay, "hello") {
		t.Fatalf("replay = %q, want the current screen", replay)
	}
	if strings.Contains(replay, "history=") {
		t.Fatalf("a fresh session sent a history chunk:\n%q", replay)
	}
}
```

Add `readyMark` to this package too (a second `const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"` in `attach_replay_test.go`; the constant in `vtwasm` is in a different package), `"fmt"` to the imports, and the resize helper that carries the opt-in:

```go
func sendResizeWithHistory(t *testing.T, c *testClient, cols, rows int, history bool) {
	t.Helper()
	payload, err := json.Marshal(ResizePayload{Cols: cols, Rows: rows, History: history})
	if err != nil {
		t.Fatalf("marshal resize: %v", err)
	}
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("send resize: %v", err)
	}
}
```

`sendResize` (`attach_replay_test.go:140-149`) stays as it is and now means "no history", which is what `TestAClientWithoutHistoryOptInGetsNoChunks` and every pre-existing attach test rely on.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -run 'TestClientPaintsAtReadyBeforeHistory|TestAFreshSessionAttachIsUnchanged' -v
```
Expected: FAIL — no history chunk ever arrives.

- [ ] **Step 3: Carry the opt-in on the opening resize**

In `backend/internal/adapters/runtime/ptyhost/proto.go`, extend `ResizePayload` (`:36-40`):

```go
// ResizePayload is the JSON body for MsgResize. History is read only from a
// connection's OPENING resize, which is its registration message: a client
// that understands OSC 7000 history chunks asks for scrollback there.
type ResizePayload struct {
	Cols    int  `json:"cols"`
	Rows    int  `json:"rows"`
	History bool `json:"history,omitempty"`
}
```

`handleClientMsg`'s later `MsgResize` case (`host.go:803-818`) keeps ignoring the field: history is streamed once, at registration, and a mid-session resize is not a second attach.

In `host.go`, add `wantsHistory bool` to `clientState` and set it in the registration hold (`:712-715`):

```go
	if opening != nil {
		cs.cols, cs.rows, cs.sized = opening.Cols, opening.Rows, true
		cs.wantsHistory = opening.History
	}
```

In `attach.go`, add the capability and make `Attach` the no-history form:

```go
func (r *Runtime) Attach(ctx context.Context, handle ports.RuntimeHandle, rows, cols uint16) (ports.Stream, error) {
	return r.AttachWithHistory(ctx, handle, rows, cols, false)
}

func (r *Runtime) AttachWithHistory(ctx context.Context, handle ports.RuntimeHandle, rows, cols uint16, history bool) (ports.Stream, error) {
	// the existing body of Attach, with the handshake call becoming
	// attachHandshake(conn, rows, cols, history)
}
```

and thread the flag through `writeResize`:

```go
func writeResize(w io.Writer, rows, cols uint16) error {
	return writeResizeWithHistory(w, rows, cols, false)
}

func writeResizeWithHistory(w io.Writer, rows, cols uint16, history bool) error {
	payload, _ := json.Marshal(ResizePayload{Cols: int(cols), Rows: int(rows), History: history})
	frame, err := EncodeMessage(MsgResize, payload)
	if err != nil {
		return err
	}
	_, err = w.Write(frame)
	return err
}
```

`loopbackStream.Resize` keeps calling `writeResize`, so a mid-session resize never re-asks for history. Add the assertion `var _ ports.HistoryAttacher = (*Runtime)(nil)` next to the existing `var _ ports.Attacher = (*Runtime)(nil)` (`attach.go:20`), and the interface itself to `backend/internal/ports/outbound.go` next to `PaneCapturer`:

```go
// HistoryAttacher is an optional Attacher capability: a client that
// understands the runtime's history marks can ask for the session's
// scrollback behind its replay frame. Asserted at the call site, so an
// Attacher without it simply never streams history.
type HistoryAttacher interface {
	AttachWithHistory(ctx context.Context, handle RuntimeHandle, rows, cols uint16, history bool) (Stream, error)
}
```

- [ ] **Step 4: Stream history after registration, only to a client that asked**

In `host.go`, in `handleConn`, immediately after `go h.runWriter(conn, cs)` (`:724`):

```go
	if cs.wantsHistory {
		go h.streamHistory(cs)
	}
```

and add the method next to `replayFrameLocked`:

```go
// streamHistory queues the session's scrollback newest→oldest, behind the
// replay frame the client was already queued. It runs off h.mu: these rows
// are older than every byte in that frame, so nothing can race into the gap
// the way a live chunk could between the replay and registration.
//
// It paces on the SAME ack watermark deliver uses, so a 200k-row history sent
// to one client can never push that client past readHighWatermark and pause
// the child for every other attached pane (Task 10).
func (h *host) streamHistory(cs *clientState) {
	parser := h.currentParser()
	if parser == nil {
		return
	}
	before := vtwasm.HistoryBefore
	for {
		if h.stopping() {
			return
		}
		chunk, next, ok, err := parser.HistoryChunk(before, MaxOutputLines, vtwasm.HistoryChunkRows)
		if err != nil {
			h.logf("stream attach history: %v", err)
			return
		}
		if !ok {
			return
		}
		frame, err := EncodeMessage(MsgTerminalData, []byte(chunk))
		if err != nil {
			h.logf("encode attach history: %v", err)
			return
		}
		h.mu.Lock()
		cs.enqueue(frame)
		cs.delivered += len(chunk)
		h.mu.Unlock()
		cs.awaitCapacity()
		h.awaitAckedHistory(cs)
		before = next
	}
}

// awaitAckedHistory parks the history stream while this client is more than
// readLowWatermark bytes behind its own acks. A client that never acks is
// paced by awaitCapacity alone, exactly as it is today.
func (h *host) awaitAckedHistory(cs *clientState) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for cs.everAcked && cs.delivered-cs.acked > readLowWatermark && !h.stopping() {
		h.readCond.Wait()
	}
}
```

`cs.delivered += len(chunk)` is R4: the client acks every byte `mux.onData` hands it, replay and history included, so the host must count the same stream or `acked` runs permanently ahead of `delivered` and the watermark never fires again for that pane. `h.stopping()`, `h.readCond`, `cs.delivered`/`cs.acked`/`cs.everAcked` and `readLowWatermark` all land in Task 10; **until Task 10 is executed, write `streamHistory` without the two lines that touch them** (`cs.delivered += …` and the `h.awaitAckedHistory(cs)` call) and add them in Task 10 Step 4, which is where this plan's Step-by-step ordering puts them. Task 10's steps say so explicitly.

`cs.awaitCapacity()` between chunks is what keeps a 200k-row history from materialising in the client's queue: it parks this goroutine exactly as `deliver` parks the pump.

- [ ] **Step 5: Return the handshake at READY**

In `backend/internal/adapters/runtime/ptyhost/attach.go`, change `attachHandshake`'s signature to `attachHandshake(conn net.Conn, rows, cols uint16, history bool)`, make its first line `writeResizeWithHistory(conn, rows, cols, history)`, and change the parser callback and the loop condition:

```go
	var (
		replay  [][]byte
		applied bool
		ready   bool
	)
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		switch msgType {
		case MsgTerminalData:
			// payload aliases buf, which the next Read overwrites.
			replay = append(replay, append([]byte(nil), payload...))
			if bytes.Contains(payload, readyMarkBytes) {
				ready = true
			}
		case MsgStatusRes:
			applied = true
		}
	})
	buf := make([]byte, 4096)
	for !applied && !ready {
```

and add, next to `attachResizeAckTimeout`:

```go
// readyMarkBytes ends the replay frame a client can paint (vt-host's
// OSC 7000 ready mark). The handshake returns here so history streams behind
// a pane that is already drawing.
var readyMarkBytes = []byte("\x1b]7000;v=1;ready=1\x1b\\")
```

Add `"bytes"` to the imports. `applied` stays as the backstop: a session with nothing to replay sends no READY and the status reply is what ends the wait, exactly as today.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -count=1
```
Expected: PASS. `TestAttachReplayDoesNotDuplicateRedrawnFrames`, `TestAttachAppliesOpeningGridBeforeReplaying`, `TestAttachReplaysAClientThatNeverResizes` and `TestAttachReplaySurvivesAWidthChangeUnderWrappedRedraws` must all still pass unchanged — `readReplay` returns the first `MsgTerminalData`, which is still the frame.

- [ ] **Step 7: Full gate and daemon rebuild**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` zero pixel diff.

- [ ] **Step 8: CHANGELOG and commit**

```markdown
- pty-host: an attach now streams five parts — the origin mark, the child's modes, the live frame, the READY mark, then scrollback newest→oldest — and the handshake returns at READY so the pane paints while history is still arriving. History is sent only to a client that asks for it on its opening resize, so a client that cannot read history chunks is unaffected.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add backend/internal/adapters/runtime/ptyhost packages/terminal/CHANGELOG.md && git commit -m "$(cat <<'MSG'
ptyhost: stream attach history behind the replayed frame, on request

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 7: The renderer lifts its cover when the core reports the frame parsed

**Files:**
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:169-205` (`replayReady`, the change notification), `types.ts`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs` (the `replay_ready` getter)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:138-142` (surface the flag to the host)
- Modify: `frontend/src/renderer/hooks/useTerminalSession.ts:109-155` (the gate's constants), `:213-228` (the gate's runtime fields), `:564-604` (`mux.onData`)
- Test: `packages/terminal/ts/core/src/terminal-core.test.ts`, `frontend/src/renderer/hooks/useTerminalSession.test.tsx`

**Why the core's flag and not a byte scan.** Task 3 already records the READY mark as `TerminalCore::replay_ready()`. Scanning the mux bytes for the mark instead would lift the cover when the bytes *arrive*, not when they are *parsed* — and since Plan A the renderer feeds through `enqueue` with a 12 ms `drain` budget per animation frame, a 1 MiB replay can arrive several frames before its last row is parsed. The cover would come off an unpainted pane. The core's flag flips inside `feed`, on the same byte, and is therefore the honest signal. No `replay-ready.ts` byte scanner is built.

**Why so little else changes.** The block renderer's core is fed from `r.byteListeners` unconditionally (`useTerminalSession.ts:579`), *before* the replay gate is consulted — the gate has only ever controlled the cover and the (now no-op) xterm writes. So "paint at READY" is exactly: end the gate when the core says the frame is parsed, instead of at `REPLAY_QUIET_MS` / `REPLAY_CAP_MS` after the last history chunk. `TERMINAL.md` §4.6's first-grid leading edge (`publishGrid`, `gridPublished`) is untouched: the pty-host still holds the replay until a grid arrives.

**Interfaces:**
- Consumes: Task 3's `TerminalCore::replay_ready()`; Plan A's `enqueue`/`drain`; `TerminalCore.onChange(listener)` (`terminal-core.ts:405`), which already fires once per generation change.
- Produces:
  ```rust
  // vt-wasm/src/lib.rs
  #[wasm_bindgen]
  impl WasmTerminalCore {
      pub fn replay_ready(&self) -> bool;
  }
  ```
  ```ts
  // ts/core/src/terminal-core.ts
  /** True once a replay READY mark has been parsed on this core. */
  replayReady(): boolean;
  ```
  ```ts
  // frontend/src/renderer/components/BlockTerminal.tsx — a new optional prop
  onReplayReady?: () => void; // fired once, on the first change where replayReady() is true
  ```

- [ ] **Step 1: Write the failing test**

Append to `packages/terminal/ts/core/src/terminal-core.test.ts`:

```ts
	it("reports the replay as ready only once the mark is parsed", () => {
		const core = makeCore({ columns: 20 });
		expect(core.replayReady()).toBe(false);
		core.enqueue(new TextEncoder().encode("frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		expect(core.replayReady()).toBe(false);
		core.drain();
		expect(core.replayReady()).toBe(true);
	});

	it("notifies a change on the feed that parses the ready mark", () => {
		const core = makeCore({ columns: 20 });
		let ready = false;
		core.onChange(() => {
			ready = ready || core.replayReady();
		});
		core.feed(new TextEncoder().encode("frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		expect(ready).toBe(true);
	});
```

`makeCore` is the file's existing helper — read it and use its options shape. The second test is the load-bearing one: the hook learns about READY through `onChange`, so a READY-only feed must notify. Plan A already made a sync-only feed notify (`terminal-core.ts:74-80`); this pins the same property for a mark-only feed.

Append to `frontend/src/renderer/hooks/useTerminalSession.test.tsx`:

```tsx
	it("paints at READY", async () => {
		const harness = mountSession();
		await harness.opened();
		harness.deliver(new TextEncoder().encode("frame row\r\n"));
		await harness.frame();
		expect(harness.replaySettled()).toBe(false);
		harness.deliver(new TextEncoder().encode("\x1b]7000;v=1;ready=1\x1b\\"));
		await harness.frame();
		expect(harness.replaySettled()).toBe(true);
	});

	it("keeps feeding the core while history streams behind the lifted cover", async () => {
		const harness = mountSession();
		await harness.opened();
		harness.deliver(new TextEncoder().encode("frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		await harness.frame();
		const before = harness.fedBytes();
		harness.deliver(new TextEncoder().encode("\x1b]7000;v=1;history=0,1\x1b\\old\r\n"));
		expect(harness.fedBytes()).toBeGreaterThan(before);
		expect(harness.replaySettled()).toBe(true);
	});

	it("still lifts the cover for a host that never sends READY", async () => {
		const harness = mountSession();
		await harness.opened();
		harness.deliver(new TextEncoder().encode("frame row\r\n"));
		await harness.advanceTimers(REPLAY_QUIET_MS + 1);
		expect(harness.replaySettled()).toBe(true);
	});
```

`mountSession`, `opened`, `deliver`, `replaySettled`, `frame`, `fedBytes` and `advanceTimers` are whatever the existing file's harness calls them — read `frontend/src/renderer/hooks/useTerminalSession.test.tsx` first and use its names verbatim. If the file has no harness, build these on the same fake mux the neighbouring tests use; `replaySettled` is the hook's returned `replaySettled` flag, `fedBytes` is a counter on the fake terminal's byte listener, and the third test's fake terminal must report `replayReady()` as `false` forever. The third test is the guard that an older pty-host — or the `Ring` fallback in `replayFrameLocked` — still uncovers its pane.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run src/terminal-core.test.ts
```
Expected: FAIL — `core.replayReady is not a function`.

- [ ] **Step 3: Export the flag from wasm and `ts/core`**

In `packages/terminal/crates/vt-wasm/src/lib.rs`, next to the other `&self` getters:

```rust
    pub fn replay_ready(&self) -> bool {
        self.core.replay_ready()
    }
```

In `packages/terminal/ts/core/src/terminal-core.ts`, next to `synchronizedOutput()` (`:170`):

```ts
	replayReady(): boolean {
		return this.inner.replay_ready();
	}
```

No change is needed to the notification path: `Parser::note_mutation` runs on every `feed_raw` that reached the parser (Plan B's rule), a READY mark is such a feed, and `TerminalCore.feed` already notifies on a generation change.

- [ ] **Step 4: Surface it to the host**

In `frontend/src/renderer/components/BlockTerminal.tsx`, add an optional `onReplayReady?: () => void` prop and fire it once, from the core's existing change subscription, the first time `core.replayReady()` is true:

```tsx
	const replayReadyFired = useRef(false);
	useEffect(() => core.onChange(() => {
		if (replayReadyFired.current || !core.replayReady()) return;
		replayReadyFired.current = true;
		onReplayReady?.();
	}), [core, onReplayReady]);
```

Match the file's existing subscription idiom rather than this sketch — `BlockTerminal` already subscribes to the core; add the check there if so, and keep the one-shot ref either way.

- [ ] **Step 5: End the gate on the flag**

In `frontend/src/renderer/hooks/useTerminalSession.ts`, add one runtime field next to `replayBuffering` (`:214`):

```ts
			replayReadySeen: false,
```

reset it where `r.replayBuffering = coverInitialReplay;` is set (`:726`), and add a callback the pane hands to `BlockTerminal` as `onReplayReady`:

```ts
	const onReplayReady = useCallback(() => {
		const r = runtime.current;
		if (r.replayReadySeen) return;
		r.replayReadySeen = true;
		r.flushReplay?.();
	}, []);
```

`r.flushReplay` is the published flush (`:560`), which calls `flushReplay(false, false)` — `holdTail = false` is deliberate: `holdTail = true` keeps the cover up for another `REPLAY_TAIL_QUIET_MS` of stream, which is precisely the history that must now stream *behind* a painted pane. The quiet, cap and first-byte timers stay exactly as they are, so a host that sends no READY uncovers on them as it does today.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/hooks/useTerminalSession.test.tsx
```
Expected: PASS.

- [ ] **Step 7: Full frontend gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel && npm run bench:selection
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` zero pixel diff.

- [ ] **Step 8: CHANGELOG and commit**

```markdown
- renderer: the initial-replay cover lifts when the core reports the replay's READY mark parsed, instead of after the whole replay goes quiet, so a reopened pane paints its live frame while its scrollback is still streaming in behind it. A host that sends no READY mark still uncovers on the existing quiet and cap timers.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal frontend/src/renderer && git commit -m "$(cat <<'MSG'
renderer: lift the replay cover when the core parses the READY mark

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

### Task 8: Lazy rewrap in `vt-core` — hot rows eagerly, cold runs on first access

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/row_index.rs:100-120` (`rewrap`), plus the stale-run state
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:455-479` (`commit_evicted`), `:115-163` (`note_remap`, `take_delta`), `:494-519` (`trim_to`)
- Modify: `packages/terminal/crates/vt-core/src/delta.rs`, `integrity.rs`, `lib.rs`
- Test: `packages/terminal/crates/vt-core/tests/lazy_rewrap.rs` (new), `packages/terminal/crates/vt-core/tests/integrity.rs`

**The model.** A width change rewraps the screen and the newest `HOT_ROWS = 2_000` completed rows immediately, and records the rest as **stale runs**: `StaleRun { start, len, cols }` over completed-row indices, where `cols` is the width the run is still *cut at*. A second width change before the run is touched does not change that `cols` — the run is still cut at the same old width — so the run is rewrapped exactly once, straight to whatever the width is when it is finally accessed. `rows_for(range)` rewraps every stale run the range touches, splices the new rows into `completed`, shifts every later run's `start` by the row-count delta, and emits stable `(u64, u64)` remap pairs for the rows it moved. **The total completed-row count is an estimate until every run is touched** — that is not a separate counter, it is simply `completed.len()` with stale runs still cut at their old widths, and it corrects itself as runs are rewrapped. The scroll anchor (Plan B Task 9) holds a stable row, so it re-resolves against the corrected geometry and the viewport does not move. Selection and find hold content offsets, which rewrap never moves (`TERMINAL.md` §4.2). The 100 ms trailing debounce is unchanged (`TERMINAL.md` §4.6). This is Kitty's deferred pagerhist reflow (`kitty/kitty/history.c`) and Ghostty's deferred-reflow TODO (`ghostty/src/terminal/PageList.zig:1263-1265`).

**Interfaces:**
- Consumes: `RowIndex::rewrap(content, cols) -> Vec<usize>` (the old→new map, last element = new length), `Parser::note_remap(&[usize])` (`parser.rs:115`), `BlockGrid::remap_rows(&[usize])` (`block_grid.rs:312`), Plan B's `Delta`.
- Produces:
  ```rust
  // row_index.rs
  pub(crate) const HOT_ROWS: usize = 2_000;
  #[derive(Clone, Debug, PartialEq, Eq)]
  pub(crate) struct StaleRun { pub start: usize, pub len: usize, pub cols: usize }
  impl RowIndex {
      /// Rewraps the newest HOT_ROWS rows to `cols` and marks everything
      /// older stale at the width it is currently cut at. Returns the old→new
      /// map for the hot region only, in `rewrap`'s shape.
      pub fn rewrap_hot(&mut self, content: &Content, cols: usize, cut_at: usize) -> Vec<usize>;
      /// Rewraps every stale run `range` touches. Returns the old→new map in
      /// `rewrap`'s shape (indices over the pre-pass completed list) and the
      /// lowest completed-row index it rewrote, or None when nothing was stale.
      pub fn rows_for(&mut self, content: &Content, cols: usize, range: Range<usize>)
          -> Option<(Vec<usize>, usize)>;
      pub fn stale_runs(&self) -> &[StaleRun];
      /// Task 2's `prepend`, extended here: prepended rows shift every stale
      /// run's `start` by the count prepended.
      pub fn prepend(&mut self, rows: Vec<RowRange>);
  }
  // delta.rs
  pub struct Delta {
      // the existing fields, unchanged
      /// Completed-row index from which the export must re-read history.
      pub history_rewritten_from: Option<usize>,
  }
  // parser.rs / lib.rs
  impl Parser  { pub fn touch_rows(&mut self, range: Range<usize>); }
  impl TerminalCore {
      pub fn touch_rows(&mut self, range: Range<usize>);
      pub fn stale_row_count(&self) -> usize;
  }
  // its TS name, added in Task 13 Step 2: TerminalCore.staleRowCount(): number
  // integrity.rs
  pub enum IntegrityError {
      // the existing variants
      StaleRunOutsideRows { start: usize, len: usize },
      StaleRunsOverlap { first: usize },
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/crates/vt-core/tests/lazy_rewrap.rs`:

```rust
use vt_core::TerminalCore;

fn fill(core: &mut TerminalCore, rows: usize) {
    for index in 0..rows {
        core.feed(format!("the quick brown fox jumps over the lazy dog {index:05}\r\n").as_bytes());
    }
}

fn row_text(core: &TerminalCore, index: usize) -> String {
    core.snapshot().expect("snapshot").row_text(index).to_string()
}

#[test]
fn hot_rows_are_rewrapped_eagerly() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    let history = core.history_rows();
    core.resize(20, 24);

    let last = core.history_rows() - 1;
    assert!(
        row_text(&core, last).chars().count() <= 20,
        "the newest row was not rewrapped: {:?}",
        row_text(&core, last)
    );
    assert!(
        core.stale_row_count() > 0,
        "nothing was left cold on a {history}-row session"
    );
}

#[test]
fn cold_rows_are_rewrapped_on_access() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    assert!(core.stale_row_count() > 0);

    core.touch_rows(0..50);
    assert!(
        row_text(&core, 0).chars().count() <= 20,
        "row 0 is still cut at the old width: {:?}",
        row_text(&core, 0)
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn two_width_changes_before_access_rewrap_once() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(30, 24);
    // Rows written between the two changes were hot at 30 columns and are
    // pushed out of the hot region by this fill. They must still be marked.
    fill(&mut core, 3_000);
    core.resize(20, 24);

    let before = core.generation();
    core.touch_rows(0..50);
    let after_first = core.generation();
    core.touch_rows(0..50);
    let after_second = core.generation();

    assert!(after_first > before, "the first access did not rewrap");
    assert_eq!(
        after_second, after_first,
        "the range was rewrapped a second time"
    );
    assert!(row_text(&core, 0).chars().count() <= 20);

    // The band that was hot at 30 columns and cold at 20 must rewrap too.
    let middle = core.history_rows() / 2;
    core.touch_rows(middle..middle + 50);
    assert!(
        row_text(&core, middle).chars().count() <= 20,
        "a row hot at the first width and cold at the second stayed cut at 30: {:?}",
        row_text(&core, middle)
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn stale_runs_follow_a_prepend() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=100000\x1b\\");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    let stale_before = core.stale_row_count();
    assert!(stale_before > 0);

    let first = core.first_stable_row();
    core.feed(format!("\x1b]7000;v=1;history={},2\x1b\\", first - 2).as_bytes());
    core.feed(b"\x1b[0mprepended one\x1b[0m\r\n\x1b[0mprepended two\x1b[0m\r\n");

    assert_eq!(core.first_stable_row(), first - 2);
    assert_eq!(core.stale_row_count(), stale_before);
    assert_eq!(core.verify_integrity(), Ok(()));

    // The prepended rows are not stale; the cold band still is, two rows
    // further down than it was.
    core.touch_rows(0..4);
    assert_eq!(row_text(&core, 0), "prepended one");
    assert!(core.stale_row_count() > 0, "touching the prepended rows rewrapped the cold band");
}

#[test]
fn blocks_and_pins_follow_lazy_remap() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    core.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=first\x1b\\");
    fill(&mut core, 40);
    core.feed(b"\x1b]133;D;0\x07");
    fill(&mut core, 3_000);
    core.resize(20, 24);

    let stable_before = {
        let snapshot = core.snapshot().expect("snapshot");
        snapshot.first_stable_row + u64::from(snapshot.blocks[0].first_row)
    };
    core.touch_rows(0..80);
    let snapshot = core.snapshot().expect("snapshot");
    let stable_after = snapshot.first_stable_row + u64::from(snapshot.blocks[0].first_row);
    assert_eq!(
        snapshot.block_command(0),
        "first",
        "the block lost its command across the lazy pass"
    );
    assert!(
        stable_after >= stable_before,
        "a block moved backwards across a lazy rewrap: {stable_before} -> {stable_after}"
    );
    let (first, count) = (snapshot.blocks[0].first_row, snapshot.blocks[0].row_count);
    assert!(
        (first as usize) + (count as usize) <= snapshot.row_count(),
        "the block escaped the row space after the lazy pass"
    );
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn a_lazy_pass_reports_the_row_the_export_must_re_read_from() {
    let mut core = TerminalCore::new(60, 200_000).expect("core");
    fill(&mut core, 3_000);
    core.resize(20, 24);
    let _ = core.take_delta();

    core.touch_rows(0..50);
    let delta = core.take_delta();
    assert_eq!(delta.history_rewritten_from, Some(0));
    assert!(
        delta.remap.as_ref().is_some_and(|pairs| !pairs.is_empty()),
        "a lazy pass produced no remap"
    );
}
```

`snapshot.blocks[0].first_row` is a flat `u32` in the export (`BlockRecord`); if the field is named differently, read `crates/vt-core/src/block.rs` and use the real name. `core.generation()` is Plan B's mutation counter.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test lazy_rewrap
```
Expected: FAIL — `no method named stale_row_count found for struct TerminalCore`.

- [ ] **Step 3: Stale runs in `RowIndex`**

In `packages/terminal/crates/vt-core/src/row_index.rs`, add the constant, the struct, a `stale: Vec<StaleRun>` field on `RowIndex` (cloned by its `Clone` impl, initialised empty in `new`), and the three methods:

```rust
pub(crate) const HOT_ROWS: usize = 2_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct StaleRun {
    pub start: usize,
    pub len: usize,
    pub cols: usize,
}
```

```rust
    pub fn stale_runs(&self) -> &[StaleRun] {
        &self.stale
    }

    pub fn rewrap_hot(&mut self, content: &Content, cols: usize, cut_at: usize) -> Vec<usize> {
        let total = self.completed.len();
        let hot_start = self.line_start_at_or_below(total.saturating_sub(HOT_ROWS));
        if hot_start > 0 {
            self.mark_stale(0, hot_start, cut_at);
        }
        let mut hot = RowIndex {
            completed: self.completed.drain(hot_start..).collect(),
            open_start: self.open_start,
            stale: Vec::new(),
        };
        let hot_map = hot.rewrap(content, cols);
        self.completed.extend(hot.completed);
        let mut map: Vec<usize> = (0..hot_start).collect();
        map.extend(hot_map.iter().map(|new| hot_start + new));
        map
    }

    // Marks only the part of [start, end) that no run already covers — the
    // band between the last existing run's end and `end`. Returning early on
    // any overlap would leave the rows that were hot at the PREVIOUS width,
    // and have since been pushed out of the hot region by new output, cut at
    // that previous width forever.
    fn mark_stale(&mut self, start: usize, end: usize, cols: usize) {
        let covered_end = self
            .stale
            .last()
            .map_or(start, |run| run.start + run.len)
            .max(start);
        if end <= covered_end {
            return;
        }
        let len = end - covered_end;
        if let Some(last) = self.stale.last_mut() {
            if last.start + last.len == covered_end && last.cols == cols {
                last.len += len;
                return;
            }
        }
        self.stale.push(StaleRun {
            start: covered_end,
            len,
            cols,
        });
    }

    // The nearest row at or below `row` that starts a logical line. A cut
    // taken mid-line hands `push_line` a fragment, which then computes a
    // hanging indent from the middle of a sentence (TERMINAL.md §4.4).
    fn line_start_at_or_below(&self, row: usize) -> usize {
        let mut index = row.min(self.completed.len());
        while index > 0 && self.completed[index - 1].wrapped {
            index -= 1;
        }
        index
    }

    pub fn rows_for(
        &mut self,
        content: &Content,
        cols: usize,
        range: std::ops::Range<usize>,
    ) -> Option<(Vec<usize>, usize)> {
        let touched: Vec<usize> = self
            .stale
            .iter()
            .enumerate()
            .filter(|(_, run)| run.start < range.end && range.start < run.start + run.len)
            .map(|(index, _)| index)
            .collect();
        if touched.is_empty() {
            return None;
        }
        let before = self.completed.len();
        let mut map: Vec<usize> = (0..before).collect();
        map.push(before);
        let mut lowest = usize::MAX;
        for index in touched.into_iter().rev() {
            let run = self.stale.remove(index);
            // split_off / extend, never a per-row insert: inserting into a
            // VecDeque is O(len) per row, which at 200k rows and a 2,000-row
            // run is ~4x10^8 element moves — the cost this task exists to
            // remove.
            let mut tail = self.completed.split_off(run.start + run.len);
            let slice: VecDeque<RowRange> = self.completed.split_off(run.start);
            let mut piece = RowIndex {
                completed: slice,
                open_start: self.open_start,
                stale: Vec::new(),
            };
            let piece_map = piece.rewrap(content, cols);
            let added = piece.completed.len();
            self.completed.append(&mut piece.completed);
            self.completed.append(&mut tail);
            let delta = added as isize - run.len as isize;
            for entry in map.iter_mut() {
                if *entry >= run.start + run.len {
                    *entry = (*entry as isize + delta) as usize;
                } else if *entry >= run.start {
                    let local = *entry - run.start;
                    *entry = run.start + piece_map.get(local).copied().unwrap_or(0);
                }
            }
            for later in self.stale.iter_mut() {
                if later.start >= run.start + run.len {
                    later.start = (later.start as isize + delta) as usize;
                }
            }
            lowest = lowest.min(run.start);
        }
        Some((map, lowest))
    }
```

`hot_map`'s last element is the hot region's new length, so offsetting every element by `hot_start` turns it into the whole index's map *and* its correct trailing total in one pass. The contract the rest of the tree reads is `map[old] == new` for every old row and `map.last() == Some(&completed.len())` — that is what `Parser::note_remap` (`parser.rs:115-138`) and `BlockGrid::remap_rows` (`block_grid.rs:312`) both consume, and `row_index.rs`'s existing `rewrap_*` unit tests pin it. Add a unit test in `row_index.rs` asserting exactly that after a `rewrap_hot` on a list longer than `HOT_ROWS`.

**Both ends of the row space move stale runs, and both must be handled.**

`RowIndex::trim_to` (`row_index.rs:189`) drops rows off the front: after the pop loop, subtract the dropped count from every run's `start`, shorten or remove a run the cut reached into, and clamp `start` to 0.

`RowIndex::prepend` (Task 2 Step 5) adds rows to the front, which shifts every existing row's index up by the same count. Without the matching shift, a resize while history chunks are still arriving leaves every run pointing at the wrong rows — silently rewrapping live text and leaving the real cold rows cold. Extend it:

```rust
    pub fn prepend(&mut self, rows: Vec<RowRange>) {
        let count = rows.len();
        for row in rows.into_iter().rev() {
            self.completed.push_front(row);
        }
        for run in self.stale.iter_mut() {
            run.start += count;
        }
    }
```

Prepended rows are never themselves stale: they arrive already cut at the width the replaying host rendered them for, and the receiving core's width is the grid it asked for. A stale run therefore always starts at or after `count`.

**Run boundaries are line starts by construction.** `rewrap_hot` cuts at `line_start_at_or_below(...)` and `mark_stale` only ever extends a run up to that same cut, so a run's start and end both fall on rows whose predecessor is not `wrapped`. `rows_for` inherits the property and does not re-derive it; `trim_to`'s front cut is the one place that can violate it, and a trim that lands mid-line drops a fragment whose logical line is already partly gone — which is the pre-existing behaviour of `trim_to`, not something lazy rewrap changes.

- [ ] **Step 4: Route `commit_evicted` through `rewrap_hot`, and add `touch_rows`**

In `packages/terminal/crates/vt-core/src/parser.rs`, add a `last_width: usize` field (initialised to `width` in `new`, updated in `resize` *before* `self.width = columns`), and replace the rewrap block in `commit_evicted` (`:469-476`):

```rust
        if std::mem::take(&mut self.rewrap_pending) {
            let cut_at = std::mem::replace(&mut self.last_width, self.width);
            let map = self.rows.rewrap_hot(&self.content, self.width, cut_at);
            self.grid.remap_rows(&map);
            self.note_remap(&map);
            self.history_exported_rows = self
                .history_exported_rows
                .min(self.rows.completed().len())
                .min(self.rows.completed().len().saturating_sub(crate::row_index::HOT_ROWS));
            self.pending_rewritten_from = Some(
                self.pending_rewritten_from
                    .unwrap_or(usize::MAX)
                    .min(self.rows.completed().len().saturating_sub(crate::row_index::HOT_ROWS)),
            );
            self.mark_full();
        }
```

and add, next to `trim_to`:

```rust
    pub fn touch_rows(&mut self, range: std::ops::Range<usize>) {
        let Some((map, lowest)) =
            self.rows.rows_for(&self.content, self.width, range)
        else {
            return;
        };
        self.grid.remap_rows(&map);
        self.note_remap(&map);
        self.history_exported_rows = self.history_exported_rows.min(lowest);
        self.pending_rewritten_from =
            Some(self.pending_rewritten_from.unwrap_or(usize::MAX).min(lowest));
        self.note_mutation();
    }

    pub fn stale_row_count(&self) -> usize {
        self.rows.stale_runs().iter().map(|run| run.len).sum()
    }
```

Add `pending_rewritten_from: Option<usize>` to `Parser` (initialised `None`) and drain it in `take_delta` (`:140-163`) into the new `Delta` field:

```rust
            history_rewritten_from: self.pending_rewritten_from.take(),
```

Add the field to `Delta` in `delta.rs` with a doc-free declaration, and expose `touch_rows`/`stale_row_count` on `TerminalCore` in `lib.rs` next to `history_rows` (`:299`):

```rust
    pub fn touch_rows(&mut self, range: Range<usize>) {
        self.parser.touch_rows(range);
        self.debug_check();
    }

    pub fn stale_row_count(&self) -> usize {
        self.parser.stale_row_count()
    }
```

- [ ] **Step 5: Keep `mark_full` honest**

`mark_full()` after a hot rewrap is correct today because the export rebuilds. Once `history_rewritten_from` exists, Task 9's exporter uses it to re-read only from that row on, and `mark_full` becomes the fallback for a core whose exporter does not yet understand the field. **Leave `mark_full()` in place in this task** — the export is Task 9's half, and every commit must stay green.

- [ ] **Step 6: Extend the integrity checker**

In `packages/terminal/crates/vt-core/src/integrity.rs`, add the two variants and, at the end of `verify_integrity` before `Ok(())`:

```rust
        let completed_len = completed.len();
        let mut previous_end = 0usize;
        for run in self.rows().stale_runs() {
            if run.len == 0 || run.start + run.len > completed_len {
                return Err(IntegrityError::StaleRunOutsideRows {
                    start: run.start,
                    len: run.len,
                });
            }
            if run.start < previous_end {
                return Err(IntegrityError::StaleRunsOverlap { first: run.start });
            }
            previous_end = run.start + run.len;
        }
```

That is the stale-width bookkeeping invariant the plan owes Plan A's checker: **stale runs are non-overlapping, ascending, non-empty, and entirely inside the completed rows.** It is also what catches a `prepend` that forgets to shift them: prepending rows without the shift leaves the last run's `start + len` past `completed.len()` as soon as the trim cap bites, and `StaleRunOutsideRows` fires. The proptest in `tests/integrity.rs` runs `verify_integrity` after every operation, so a resize followed by a trim now exercises it for free — add a resize with a *narrower* width to the proptest's operation set if it has none, so cold runs actually appear:

```rust
        // in the operation enum used by every_operation_leaves_the_model_consistent
        Operation::Narrow => core.resize(12, 8),
        Operation::Widen => core.resize(96, 24),
        Operation::Touch(start) => core.touch_rows(start..start + 32),
```

Read `crates/vt-core/tests/integrity.rs` and add these in whatever shape its generator already uses.

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test lazy_rewrap --test integrity --test rewrap
```
Expected: PASS, including the existing `tests/rewrap.rs` guards (§4.2, §4.3, §4.4) — a session under `HOT_ROWS` rows is entirely hot, so every one of those tests takes the eager path unchanged.

- [ ] **Step 8: Full Rust gate and both wasm artifacts**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` zero pixel diff; `bench:agent:scroll` exits 0.

- [ ] **Step 9: CHANGELOG and commit**

```markdown
- vt-core: a width change rewraps the screen and the newest 2,000 completed rows immediately and marks older rows stale at the width they are cut at; a stale run is rewrapped once, on first access through `touch_rows`, and emits the same stable-row remap an eager rewrap does. The integrity checker pins that stale runs stay non-overlapping and inside the row space.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "$(cat <<'MSG'
vt-core: lazy rewrap for cold scrollback

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 9: The export asks for its window, and the anchor holds it still

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs` (`sync`, the new window setter), `export.rs:141` (`ExportBuffers::apply` honours `history_rewritten_from`)
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:205-235` (`snapshot`), `types.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (the repaint's window call)
- Test: `packages/terminal/ts/core/src/terminal-core.test.ts`, `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`

**Interfaces:**
- Consumes: Task 8's `TerminalCore::touch_rows(range)`, `Delta.history_rewritten_from`; Plan B's `ExportBuffers::apply(&Delta)`, `WasmTerminalCore::sync() -> u32`, `TerminalCore.snapshot()` memoised per `{ generation, memory.buffer }`, `DomBlockRenderer.scrollAnchor()` / `computeWindow` (`viewport.ts:53`) and `OVERSCAN_ROWS = 6` (`dom-block-renderer.ts:45`).
- Produces:
  ```rust
  // vt-wasm/src/lib.rs
  #[wasm_bindgen]
  impl WasmTerminalCore {
      /// The flat history rows the next sync() must have rewrapped. Cleared
      /// by sync(); a window that is never set leaves every cold row cold.
      pub fn set_export_window(&mut self, first_row: u32, last_row: u32);
  }
  ```
  ```ts
  // ts/core/src/terminal-core.ts
  /** Declares the history rows the next snapshot must have rewrapped. */
  setExportWindow(firstRow: number, lastRow: number): void;
  ```
  `sync()` calls `core.touch_rows(first..last)` before taking the delta, so a lazy pass and the export that consumes it happen in one call — the renderer never sees a snapshot whose rows the delta has not described.

- [ ] **Step 1: Write the failing test**

Append to `packages/terminal/ts/core/src/terminal-core.test.ts`:

```ts
	it("rewraps the declared window before the snapshot it hands back", () => {
		const core = makeCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		for (let index = 0; index < 3000; index += 1) {
			core.feed(new TextEncoder().encode(`the quick brown fox jumps over the lazy dog ${index}\r\n`));
		}
		core.resize(20, 24);
		const cold = core.snapshot();
		expect(decodeRow(cold, 0).length).toBeGreaterThan(20);

		core.setExportWindow(0, 40);
		const warm = core.snapshot();
		expect(decodeRow(warm, 0).length).toBeLessThanOrEqual(20);
	});

	it("does not re-rewrap a window it has already served", () => {
		const core = makeCore({ columns: 60, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		for (let index = 0; index < 3000; index += 1) {
			core.feed(new TextEncoder().encode(`the quick brown fox jumps over the lazy dog ${index}\r\n`));
		}
		core.resize(20, 24);
		core.setExportWindow(0, 40);
		const first = core.snapshot().generation;
		core.setExportWindow(0, 40);
		expect(core.snapshot().generation).toBe(first);
	});
```

`makeCore` and `decodeRow` are the existing helpers in that file — read it and use its names; if `decodeRow` does not exist, decode with `new TextDecoder().decode(snapshot.content.subarray(snapshot.rows[2 * index], snapshot.rows[2 * index + 1]))` the way `bench/agent-session/main.ts:280` does.

Append to `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`, in the existing `"scroll anchor"` describe block:

```ts
		it("keeps the row under the top edge when a cold range rewraps", async () => {
			const { renderer, core, container } = mountLongSession({ columns: 60, rows: 3000 });
			core.resize(20, 24);
			await frame();
			container.scrollTop = Math.floor(container.scrollHeight / 2);
			container.dispatchEvent(new Event("scroll"));
			await frame();
			const before = renderer.renderedRows()[0];

			renderer.repaint();
			await frame();
			const after = renderer.renderedRows()[0];
			expect(after.stableRow).toBe(before.stableRow);
		});
```

`mountLongSession`, `frame` and `renderedRows()[0].stableRow` are Plan B Task 9's helpers in that file; read the `"scroll anchor"` block and reuse whatever it already calls. If the helper is named `mountRenderer`, use that and feed it 3,000 rows inline.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run src/terminal-core.test.ts
```
Expected: FAIL — `core.setExportWindow is not a function`.

- [ ] **Step 3: The wasm window**

In `packages/terminal/crates/vt-wasm/src/lib.rs`, add a field `export_window: Option<(usize, usize)>` to `WasmTerminalCore` (initialised `None`), the setter, and the `sync` prelude:

```rust
    pub fn set_export_window(&mut self, first_row: u32, last_row: u32) {
        self.export_window = Some((first_row as usize, last_row as usize));
    }
```

and at the top of `sync`, before it takes the delta:

```rust
        if let Some((first, last)) = self.export_window.take() {
            if last > first {
                self.core.touch_rows(first..last);
            }
        }
```

- [ ] **Step 4: The export honours `history_rewritten_from`**

In `packages/terminal/crates/vt-wasm/src/export.rs`, in `ExportBuffers::apply`, before the existing `appended_history` append and after the `trimmed_rows` prefix advance: when `delta.history_rewritten_from` is `Some(from)`, truncate the history section at row `from` (rows, indents, run_ranges, style_pairs and the content those rows own) and re-append rows `from..core.history_rows()` from `core.export_history_rows(from..)`. That replaces the `DeltaKind::Full` rebuild for a rewrap, so a hot rewrap re-reads 2,000 rows and a lazy pass re-reads from the run it touched — not the whole session.

Then remove the `self.mark_full();` line Task 8 Step 4 left in `Parser::commit_evicted`'s rewrap block and in `Parser::touch_rows`, so the delta stays `Partial` with `history_rewritten_from` set. **Run the byte-identity property test immediately after** — it is the gate that says the incremental path still equals a full rebuild:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-wasm --test incremental_export
```
If `incremental_export_equals_full_rebuild` fails, the truncate-and-re-append is dropping or double-counting content; fix the exporter, never the property.

- [ ] **Step 5: The TS seam**

In `packages/terminal/ts/core/src/terminal-core.ts`, next to `snapshot()` (`:205`):

```ts
	setExportWindow(firstRow: number, lastRow: number): void {
		this.inner.set_export_window(Math.max(0, firstRow), Math.max(0, lastRow));
	}
```

The snapshot cache keyed on `{ generation, memory.buffer }` needs no change: `touch_rows` bumps the generation only when it actually rewrapped something, which is exactly what "does not re-rewrap a window it has already served" asserts.

- [ ] **Step 6: The renderer declares its window**

In `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`, in `repaint`, immediately **before** the `core.snapshot()` call (`:371`), declare the window the paint is about to read — the computed window plus `OVERSCAN_ROWS` on each side, converted to flat history rows:

```ts
		const anchor = this.scrollAnchor();
		const firstRow = Math.max(0, this.flatRowFor(anchor) - OVERSCAN_ROWS);
		this.core.setExportWindow(firstRow, firstRow + this.visibleRowCapacity() + 2 * OVERSCAN_ROWS);
```

`flatRowFor(anchor)` converts the anchor's stable row through `snapshot.firstStableRow` (Plan B Task 5's `row-geometry.ts` already does this — reuse its helper rather than writing a second converter), and `visibleRowCapacity()` is `Math.ceil(container.clientHeight / rowHeight)`. If `repaint` already computes a window before the snapshot, use its numbers; if it computes the window *after* (`computeWindow` at `:426`), the anchor-derived estimate above is what the first snapshot of the frame is given, and the next frame corrects it — which is exactly the spec's "the total row count above the viewport is an estimate until touched; the anchor keeps the viewport still while it corrects".

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
```
Expected: PASS, including Plan B's `"scroll anchor"` tests ("survives a trim", "survives a rewrap") and `"an unchanged row is not rebuilt when another row changed"`.

- [ ] **Step 8: Full gate and both wasm artifacts**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` zero pixel diff.

- [ ] **Step 9: CHANGELOG and commit**

```markdown
- terminal: the wasm export rewraps the rows the renderer is about to paint (its window plus overscan) before handing back a snapshot, and applies a rewrap by re-reading history from the first row that moved instead of rebuilding the whole export. The scroll anchor keeps the viewport still while the row count above it corrects.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "$(cat <<'MSG'
terminal: export the paint window and re-read history from the first moved row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 10: `MsgAck` and the pty-host read watermarks

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go:15-32` (the message table), `:34-76` (payload structs)
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go:78-107` (`clientState`), `:369-373` (constants), `:480-494` (`readPTY`), `:498-541` (`deliver`), `:712-721` (registration), `:795-906` (`handleClientMsg`), `:326-367` (`shutdown`)
- Modify: `backend/internal/adapters/runtime/ptyhost/attach.go` (`loopbackStream.Ack`)
- Test: `backend/internal/adapters/runtime/ptyhost/host_test.go`, `proto_test.go`

**Safety with a client that never acks.** The pre-Plan-C mobile build sends no ack, ever. A client is therefore **unlimited until its first ack**: `clientState.everAcked` starts false and such a client is excluded from the slowest-client computation entirely. Only clients that have proved they ack are allowed to pause the pty. This is the whole reason the watermark is computed over "clients that have acked at least once" rather than over all of them.

**Both sides must count the same byte stream.** The client acks a cumulative count of every byte `mux.onData` hands it — replay frame and history chunks included. If `cs.delivered` counted only `deliver` batches, then after any reopen the client's count would be permanently ahead of the host's, `acked` would clamp to `delivered` on every ack, unacked would sit at ≈ 0, and that pane could never pause the child again. Every pane opens with a replay, so H would be defeated in practice while every test that attaches to an empty session still passed. So **every `MsgTerminalData` payload enqueued for a client is counted**: the replay frame in the registration hold, each history chunk in `streamHistory`, and each `deliver` batch.

**Interfaces:**
- Consumes: `clientState.enqueue/awaitCapacity` (`host.go:118,133`) — the per-client socket queue stays exactly as it is; this adds end-to-end back-pressure to the *child*, which `awaitCapacity` cannot reach.
- Produces:
  ```go
  // proto.go
  const MsgAck byte = 0x11 // client -> host: JSON {bytes}
  type AckPayload struct {
      Bytes int `json:"bytes"`
  }
  // host.go
  const (
      readHighWatermark = 100_000 // vscode/src/vs/platform/terminal/common/terminal.ts
      readLowWatermark  = 5_000
  )
  // attach.go
  func (s *loopbackStream) Ack(bytes uint64) error
  ```
  On `clientState`: `acked int` (bytes this client has confirmed), `delivered int` (every `MsgTerminalData` payload byte enqueued for it since it registered), `everAcked bool`. Unacked = `delivered - acked`. `readPTY` parks before each `pty.Read` while the **maximum** unacked across acking clients exceeds `readHighWatermark`, and resumes once it falls below `readLowWatermark`. Task 6's `streamHistory`/`awaitAckedHistory` pace on the same `h.readCond` and the same `readLowWatermark`, so a long history never pushes its own client past the high watermark and pauses the child for every other pane.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/adapters/runtime/ptyhost/host_test.go`:

```go
// The child is throttled by the slowest client that actually acks: past
// 100,000 unacknowledged bytes the host stops reading the PTY, and an ack
// that brings the backlog under 5,000 starts it again (VS Code's
// vscode/src/vs/platform/terminal/common/terminal.ts flow-control constants).
func TestReadPausesPastHighWatermarkAndResumesOnAck(t *testing.T) {
	f := startServeParsed(t, 720, 80, 24)
	defer f.cancel()

	// Attach to a session that HAS a replay frame. A client acks every byte
	// it consumes, replay included; if the host counted only live batches,
	// its acked count would run permanently ahead of delivered and the
	// watermark would never fire again for this pane.
	writeOutput(t, f, "existing screen\r\n")
	waitForParsedOutput(t, f, "existing screen")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 80, 24)
	replay := readReplay(t, c)
	sendAck(t, c, len(replay))
	waitForAckingClient(t, f)

	blob := bytes.Repeat([]byte("x"), 32*1024)
	for i := 0; i < 8; i++ {
		if _, err := f.pty.WriteOutput(blob); err != nil {
			t.Fatalf("write pty output: %v", err)
		}
	}
	waitFor(t, 3*time.Second, func() bool { return f.readsPaused() })

	sendAck(t, c, len(replay)+8*32*1024)
	waitFor(t, 3*time.Second, func() bool { return !f.readsPaused() })
}

// Streaming a long history to one client must never pause the child for the
// other panes: streamHistory paces on the same ack watermark deliver does.
func TestHistoryStreamingNeverPausesTheChild(t *testing.T) {
	f := startServeParsed(t, 722, 20, 4)
	defer f.cancel()

	for i := 0; i < 5000; i++ {
		writeOutput(t, f, fmt.Sprintf("row %04d\r\n", i))
	}
	waitForParsedOutput(t, f, "row 4999")

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	paused := false
	consumed := 0
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		typ, payload := c.readFrame(t)
		if typ != MsgTerminalData {
			continue
		}
		consumed += len(payload)
		sendAck(t, c, consumed)
		if f.readsPaused() {
			paused = true
			break
		}
		if strings.Contains(string(payload), "row 0000") {
			break
		}
	}
	if paused {
		t.Fatal("streaming history to one client paused the child")
	}
}

// A client that has never acked is unlimited: the pre-Plan-C mobile build
// sends no ack and must keep working.
func TestAClientThatNeverAcksNeverPausesTheChild(t *testing.T) {
	f := startServe(t, 721, 80, 24)
	defer f.cancel()

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 80, 24)

	blob := bytes.Repeat([]byte("y"), 32*1024)
	for i := 0; i < 16; i++ {
		if _, err := f.pty.WriteOutput(blob); err != nil {
			t.Fatalf("write pty output: %v", err)
		}
	}
	time.Sleep(300 * time.Millisecond)
	if f.readsPaused() {
		t.Fatal("a client that never acked paused the child")
	}
}

func sendAck(t *testing.T, c *testClient, bytesAcked int) {
	t.Helper()
	payload, err := json.Marshal(AckPayload{Bytes: bytesAcked})
	if err != nil {
		t.Fatalf("marshal ack: %v", err)
	}
	if err := c.send(MsgAck, payload); err != nil {
		t.Fatalf("send ack: %v", err)
	}
}
```

Add `waitFor(t, d, cond)` (poll every 2 ms until `cond()` or the deadline, then `t.Fatal`) and `waitForAckingClient(t, f)` (poll until the host has recorded the ack) next to the file's other helpers. `f.readsPaused()` reads the host's own gate: `serveFixture` must keep the `*host` `Serve` built (add a field and set it from `Serve`, or expose `host.readPaused()` through a small test-only accessor in the same package) and `f.readsPaused()` forwards to `h.readPaused()` from Step 4. Do **not** put the flag on the fake PTY: the gate lives in `readPTY`, above the PTY, and asserting on the PTY would pass while the gate did nothing. Add `"bytes"`, `"encoding/json"`, `"fmt"` and `"strings"` to the imports if absent; `startServeParsed`, `writeOutput`, `waitForParsedOutput`, `readReplay`, `sendResize` and `sendResizeWithHistory` come from `attach_replay_test.go` in the same package.

Also append to `proto_test.go`:

```go
func TestAckFrameRoundTrips(t *testing.T) {
	payload, err := json.Marshal(AckPayload{Bytes: 5000})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	frame, err := EncodeMessage(MsgAck, payload)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	var got AckPayload
	var typ byte
	p := NewMessageParser(func(msgType byte, body []byte) {
		typ = msgType
		_ = json.Unmarshal(body, &got)
	})
	p.Feed(frame)
	if typ != MsgAck || got.Bytes != 5000 {
		t.Fatalf("round trip = %#x %+v", typ, got)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -run 'TestReadPauses|TestAClientThatNeverAcks|TestAckFrameRoundTrips' -v
```
Expected: FAIL — `undefined: MsgAck`.

- [ ] **Step 3: The protocol message**

In `backend/internal/adapters/runtime/ptyhost/proto.go`, add to the const block:

```go
	MsgAck             byte = 0x11 // client -> host: JSON {bytes}
```

and the payload struct next to `ResizePayload`:

```go
// AckPayload is the JSON body for MsgAck. Bytes is the cumulative count of
// terminal bytes this client has consumed since it attached.
type AckPayload struct {
	Bytes int `json:"bytes"`
}
```

`0x11` is the next free value after `MsgRespawnRes = 0x10`; `EncodeMessage`/`MessageParser` are type-agnostic, so nothing else in the codec changes.

- [ ] **Step 4: The accounting and the gate**

In `backend/internal/adapters/runtime/ptyhost/host.go`, add to `clientState`:

```go
	// Flow control. delivered counts every MsgTerminalData payload byte
	// enqueued for this client since it registered -- the replay frame and
	// the history chunks as well as the live batches, because the client acks
	// every byte it consumes. acked is what it has confirmed. A client that
	// has never acked is unlimited (everAcked false) so a client build that
	// predates acks keeps working.
	acked     int
	delivered int
	everAcked bool
```

add the constants next to `syncHoldTimeout`:

```go
	// Flow-control watermarks, from VS Code's
	// vscode/src/vs/platform/terminal/common/terminal.ts.
	readHighWatermark = 100_000
	readLowWatermark  = 5_000
```

add a `readCond *sync.Cond` and `readParked bool` to `host` (`readCond = sync.NewCond(&h.mu)` in `Serve`'s constructor), and the gate plus its helpers:

```go
// awaitReadCapacity parks the PTY reader while the slowest acking client is
// more than readHighWatermark bytes behind, and resumes it once that falls
// under readLowWatermark. A client that has never acked is not counted, so a
// client build without acks never throttles the child.
func (h *host) awaitReadCapacity() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.unackedLocked() <= readHighWatermark {
		return
	}
	h.readParked = true
	for h.unackedLocked() > readLowWatermark && !h.stopping() {
		h.readCond.Wait()
	}
	h.readParked = false
}

func (h *host) unackedLocked() int {
	worst := 0
	for _, cs := range h.clients {
		if !cs.everAcked {
			continue
		}
		if behind := cs.delivered - cs.acked; behind > worst {
			worst = behind
		}
	}
	return worst
}

func (h *host) readPaused() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.readParked
}

func (h *host) stopping() bool {
	select {
	case <-h.shutdownC:
		return true
	default:
		return false
	}
}
```

Call it at the top of `readPTY`'s loop (`:483`):

```go
	for {
		h.awaitReadCapacity()
		n, err := pty.Read(buf)
```

Count the bytes in `deliver`, inside the existing `h.mu` hold, right after `broadcastLocked` returns (`:509`):

```go
		for _, cs := range states {
			cs.delivered += len(batch)
		}
```

Count the replay frame too, in the registration hold (`:718-720`), which is the same `h.mu` hold:

```go
	if frame := h.replayFrameLocked(); frame != nil {
		cs.enqueue(frame)
		cs.delivered += len(frame) - frameHeaderBytes
	}
```

with `const frameHeaderBytes = 5` next to `EncodeMessage` in `proto.go` (`[1-byte type][4-byte length]`, `proto.go:5`) — the client acks *payload* bytes, not framing, so the host must subtract the header. Use the same subtraction nowhere else: `deliver` counts `len(batch)`, which is already the payload, and `streamHistory` counts `len(chunk)`, likewise.

Finally, add the two lines Task 6 Step 4 deferred to this task, now that `delivered`, `everAcked`, `readLowWatermark`, `h.readCond` and `h.stopping()` all exist: `cs.delivered += len(chunk)` inside `streamHistory`'s `h.mu` hold, and the `h.awaitAckedHistory(cs)` call after `cs.awaitCapacity()`, with `awaitAckedHistory` itself as Task 6 Step 4 writes it.

Record the ack in `handleClientMsg` (`:795`):

```go
	case MsgAck:
		var ack AckPayload
		if err := json.Unmarshal(payload, &ack); err != nil || ack.Bytes < 0 {
			return
		}
		h.mu.Lock()
		if cs := h.clients[conn]; cs != nil {
			cs.everAcked = true
			if ack.Bytes > cs.acked {
				cs.acked = ack.Bytes
			}
			if cs.acked > cs.delivered {
				cs.acked = cs.delivered
			}
		}
		h.readCond.Broadcast()
		h.mu.Unlock()
```

Broadcast the condition wherever the client set changes or the host stops, so a parked reader can never be stranded: at the end of `dropClient` (`:225-237`, under the lock), in `handleConn`'s deferred removal (`:726-735`), and in `shutdown` right after `close(h.shutdownC)` (`:340`) — the last one needs its own `h.mu.Lock(); h.readCond.Broadcast(); h.mu.Unlock()`.

A dropped client's `delivered`/`acked` vanish with its `clientState`, so `unackedLocked` immediately stops counting it. That is the behaviour we want: a client that disconnects must never keep the child throttled.

- [ ] **Step 5: `loopbackStream.Ack`**

In `backend/internal/adapters/runtime/ptyhost/attach.go`, next to `Resize`:

```go
func (s *loopbackStream) Ack(bytes uint64) error {
	payload, err := json.Marshal(AckPayload{Bytes: int(bytes)})
	if err != nil {
		return err
	}
	frame, err := EncodeMessage(MsgAck, payload)
	if err != nil {
		return err
	}
	_, err = s.conn.Write(frame)
	return err
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -count=1 -race
```
Expected: PASS, with no race reports. `-race` matters here: `readCond` is the first condition variable on `h.mu` and the lock-order rule (`h.mu` → `outMu`, never the reverse — `host.go:100-101`) must hold, so never call `enqueue`/`awaitCapacity` while parked in `awaitReadCapacity` or `awaitAckedHistory`. `streamHistory` obeys it: it enqueues under `h.mu`, releases, then parks.

- [ ] **Step 7: Full gate and daemon rebuild**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: PASS; zero pixel diff.

- [ ] **Step 8: CHANGELOG and commit**

```markdown
- pty-host: a client may acknowledge the terminal bytes it has consumed (`MsgAck`); the host counts every payload it sends that client — replay frame, history chunks and live batches alike — stops reading the pty once its slowest acking client is 100,000 bytes behind, and resumes at 5,000, so a slow link throttles the child instead of queueing the session. Streaming history paces on the same watermark, and a client that never acks is unlimited.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add backend/internal/adapters/runtime/ptyhost packages/terminal/CHANGELOG.md && git commit -m "$(cat <<'MSG'
ptyhost: pause the pty read past the unacked high watermark

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 11: The ack and the history opt-in cross the mux, and the desktop client sends both

**Files:**
- Modify: `backend/internal/ports/outbound.go:185-195` (a new optional interface next to `PaneCapturer`)
- Modify: `backend/internal/terminal/protocol.go:29-38` (`msgAck`), `:67-83` (`clientMsg.Bytes`), `manager.go:401-428` (`handleTerminal`), `attachment.go:260-268` (`ack`)
- Modify: `frontend/src/renderer/lib/terminal-mux.ts` (a `ack(handle, bytes)` sender), `frontend/src/renderer/hooks/useTerminalSession.ts:564-604`
- Test: `backend/internal/terminal/manager_test.go`, `frontend/src/renderer/hooks/useTerminalSession.test.tsx`

**Interfaces:**
- Consumes: Task 10's `loopbackStream.Ack(bytes uint64) error`; Task 6's `ports.HistoryAttacher` and `Runtime.AttachWithHistory`.
- Produces:
  ```go
  // ports/outbound.go — optional, asserted at the call site exactly like
  // PaneCapturer, so every other Stream implementation stays untouched.
  type FlowControlled interface {
      Ack(bytes uint64) error
  }
  // terminal/protocol.go
  const msgAck = "ack" // ch "terminal", client -> server
  type clientMsg struct {
      // the existing fields
      Bytes   int  `json:"bytes,omitempty"`
      History bool `json:"history,omitempty"` // ch "terminal", type "open"
  }
  // terminal/attachment.go
  func (a *attachment) ack(bytes uint64) error
  ```
  The `history` flag rides the terminal **open** message, is stored on the attachment, and is what `attachment.run` passes to Task 6's `ports.HistoryAttacher`. A client that omits it gets today's attach.
  ```ts
  // frontend/src/renderer/lib/terminal-mux.ts
  ack(handle: string, bytes: number): void;                              // {ch:'terminal', id, type:'ack', bytes}
  open(handle: string, rows: number, cols: number, history: boolean): void; // adds history:true to the existing open frame
  // frontend/src/renderer/hooks/useTerminalSession.ts
  const ACK_EVERY_BYTES = 5_000;
  ```
  The renderer counts every byte `mux.onData` hands it and sends a cumulative ack each time the count has grown by `ACK_EVERY_BYTES` since the last one. Cumulative, not incremental, so a dropped ack self-heals on the next one.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/terminal/manager_test.go`:

```go
// An ack from the client reaches the attach Stream, which is what lets the
// pty-host throttle the child (xterm.js write(data, cb) flow control,
// xterm.js/src/common/services/CoreService.ts).
func TestTerminalAckReachesTheStream(t *testing.T) {
	h := newManagerHarness(t)
	defer h.close()
	h.open("pane-1")

	h.send(clientMsg{Ch: chTerminal, ID: "pane-1", Type: msgAck, Bytes: 5000})

	waitFor(t, time.Second, func() bool { return h.stream("pane-1").ackedBytes() == 5000 })
}

// The desktop declares that it can read history chunks; the daemon forwards
// that to the runtime, which is what makes the pty-host stream scrollback.
func TestTerminalOpenForwardsTheHistoryOptIn(t *testing.T) {
	h := newManagerHarness(t)
	defer h.close()

	h.send(clientMsg{Ch: chTerminal, ID: "pane-3", Type: msgOpen, Rows: 24, Cols: 80, History: true})

	waitFor(t, time.Second, func() bool { return h.attachedWithHistory("pane-3") })
}

// A client that omits the flag gets today's attach.
func TestTerminalOpenWithoutHistoryAttachesPlainly(t *testing.T) {
	h := newManagerHarness(t)
	defer h.close()

	h.send(clientMsg{Ch: chTerminal, ID: "pane-4", Type: msgOpen, Rows: 24, Cols: 80})

	waitFor(t, time.Second, func() bool { return h.attached("pane-4") })
	if h.attachedWithHistory("pane-4") {
		t.Fatal("a client that did not ask was attached with history")
	}
}

// A Stream that does not implement FlowControlled must not break: the ack is
// dropped, not an error.
func TestTerminalAckOnAStreamWithoutFlowControlIsIgnored(t *testing.T) {
	h := newManagerHarness(t)
	defer h.close()
	h.openPlainStream("pane-2")

	h.send(clientMsg{Ch: chTerminal, ID: "pane-2", Type: msgAck, Bytes: 5000})
	h.send(clientMsg{Ch: chTerminal, ID: "pane-2", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("x"))})

	waitFor(t, time.Second, func() bool { return h.stream("pane-2").written() == "x" })
}
```

`newManagerHarness`, `open`, `send`, `stream` and `close` are `manager_test.go`'s existing fixture names — read the file and use them verbatim; `ackedBytes()` is a counter added to the fake stream in `fakes_test.go`, `openPlainStream` mounts a fake that deliberately does **not** implement `Ack`, and `attached(id)`/`attachedWithHistory(id)` record which of the fake runtime's two attach methods was called (the fake implements both `ports.Attacher` and `ports.HistoryAttacher`).

Append to `frontend/src/renderer/hooks/useTerminalSession.test.tsx`:

```tsx
	it("acks the transport every 5,000 bytes", async () => {
		const harness = mountSession();
		await harness.opened();
		const chunk = new Uint8Array(2_000);
		harness.deliver(chunk);
		expect(harness.acks()).toEqual([]);
		harness.deliver(chunk);
		harness.deliver(chunk);
		expect(harness.acks()).toEqual([6_000]);
		harness.deliver(chunk);
		harness.deliver(chunk);
		expect(harness.acks()).toEqual([6_000, 10_000]);
	});
```

`harness.acks()` records every `mux.ack(handle, bytes)` the fake mux receives. The expected values are cumulative totals at the moment the threshold was crossed: 6,000 after three 2,000-byte chunks, then 10,000 after two more.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/terminal/ -run TestTerminalAck -v
cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/hooks/useTerminalSession.test.tsx
```
Expected: FAIL — `undefined: msgAck`; `harness.acks is not a function`.

- [ ] **Step 3: The port and the daemon plumbing**

In `backend/internal/ports/outbound.go`, next to `PaneCapturer`:

```go
// FlowControlled is an optional Stream capability: a client that reports the
// bytes it has consumed lets the runtime throttle the child. Asserted at the
// call site, so a Stream without it simply has no flow control.
type FlowControlled interface {
	Ack(bytes uint64) error
}
```

In `backend/internal/terminal/protocol.go`, add `msgAck = "ack"` to the client-message const block and two fields to `clientMsg`:

```go
	// Bytes is the client's cumulative consumed-byte count for ch "terminal"
	// / type "ack". History is the client's declaration, on type "open", that
	// it understands the runtime's history marks.
	Bytes   int  `json:"bytes,omitempty"`
	History bool `json:"history,omitempty"`
```

In `backend/internal/terminal/attachment.go`, next to `resize` (`:260`):

```go
func (a *attachment) ack(bytes uint64) error {
	a.mu.Lock()
	pty := a.pty
	a.mu.Unlock()
	if pty == nil {
		return nil
	}
	flow, ok := pty.(ports.FlowControlled)
	if !ok {
		return nil
	}
	return flow.Ack(bytes)
}
```

Mirror whatever locking `resize` (`:260-268`) uses rather than inventing new locking.

In `backend/internal/terminal/manager.go`, carry the flag from `open` to the attachment: `handleTerminal`'s `msgOpen` case (`:403-404`) passes `msg.History` into `c.openTerminal`, which stores it on the attachment; `attachment.run` (`:143`) then prefers the capability when it is set:

```go
	if a.wantsHistory {
		if src, ok := a.src.(ports.HistoryAttacher); ok {
			p, err = src.AttachWithHistory(ctx, a.handle, rows, cols, true)
		} else {
			p, err = a.src.Attach(ctx, a.handle, rows, cols)
		}
	} else {
		p, err = a.src.Attach(ctx, a.handle, rows, cols)
	}
```

Match `attachment.run`'s existing error handling and retry shape rather than this sketch; the only new thing is which method is called.

Then, in `handleTerminal` (`:401`):

```go
	case msgAck:
		if msg.Bytes <= 0 {
			return
		}
		if a := c.lookup(msg.ID); a != nil {
			_ = a.ack(uint64(msg.Bytes))
		}
```

- [ ] **Step 4: The renderer's ack**

In `frontend/src/renderer/lib/terminal-mux.ts`, add an `ack` sender next to `resize` — the same frame shape, `{ ch: "terminal", id, type: "ack", bytes }` — and add it to the `TerminalMux` type. In the same file, add `history: true` to the `open` frame the desktop sends: the renderer's core understands history chunks after Tasks 1–3, so it is the one client that asks. Update the `TerminalMux` type's `open` signature and every call site; there is one, in `useTerminalSession`'s connect path.

In `frontend/src/renderer/hooks/useTerminalSession.ts`, add the constant next to `RESIZE_DEBOUNCE_MS`:

```ts
// Flow control. The renderer confirms the bytes it has consumed so the
// pty-host can throttle the child rather than queue the session
// (vscode/src/vs/platform/terminal/common/terminal.ts).
const ACK_EVERY_BYTES = 5_000;
```

two runtime fields next to `replayBuffering`:

```ts
			consumedBytes: 0,
			ackedBytes: 0,
```

reset both where `r.replayBuffering` is reset per connect, and in `mux.onData` (`:579`), immediately after `for (const listener of [...r.byteListeners]) listener(bytes);`:

```ts
					r.consumedBytes += bytes.length;
					if (r.consumedBytes - r.ackedBytes >= ACK_EVERY_BYTES) {
						r.ackedBytes = r.consumedBytes;
						mux.ack(handle, r.ackedBytes);
					}
```

The ack goes after the listeners, never before: an ack is a claim that the bytes are consumed, and the listeners are what consumes them.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/terminal/ ./internal/httpd/ -count=1
cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run
```
Expected: PASS.

- [ ] **Step 6: End-to-end gate and daemon rebuild**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/... -count=1
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; zero pixel diff. No API schema regeneration is needed: the mux is not part of `apispec`.

- [ ] **Step 7: CHANGELOG and commit**

```markdown
- terminal mux: a client may send `{ch:'terminal', type:'ack', bytes}` and the daemon forwards it to the attach stream, and may declare `history: true` when it opens a pane to receive the session's scrollback behind its replay; the desktop renderer does both and acks every 5,000 bytes it consumes.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add backend/internal frontend/src/renderer packages/terminal/CHANGELOG.md && git commit -m "$(cat <<'MSG'
terminal: carry consumption acks and the history opt-in to the pty-host

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app.**

---

### Task 12: The mobile client acks

**Files:**
- Modify: `packages/mobile/lib/core/mux/mux_client.dart:213-233` (the terminal `data` case), `:297-308` (the senders)
- Test: `packages/mobile/test/core/mux/mux_client_test.dart`

**The mobile client deliberately does not ask for history.** It renders with the vendored xterm fork, which routes OSC 7000 to `unknownOSC` → `onPrivateOSC` (`packages/mobile/packages/xterm/lib/src/core/escape/parser.dart:1079`, `lib/src/terminal.dart:902-905`) — so the origin, READY and history *marks* are ignored, but the history *rows* between them would print as ordinary text, newest→oldest, after the live frame. `openTerminal` therefore stays exactly as it is: no `history` key. The second test below is the guard that keeps it that way.

**Interfaces:**
- Consumes: Task 11's `{ch:'terminal', id, type:'ack', bytes}` frame and its `history` opt-in, which this client does **not** send.
- Produces:
  ```dart
  /// Bytes between acks. The daemon throttles the child once a client is
  /// 100,000 bytes behind; 5,000 is the resume watermark
  /// (vscode/src/vs/platform/terminal/common/terminal.ts).
  const int _ackEveryBytes = 5000;
  void ackTerminal(String id, int bytes, {String? projectId});
  ```
  `MuxClient` keeps `_consumed` and `_acked` maps keyed by terminal id, counts bytes as it emits each `TerminalDataEvent`, and sends a cumulative ack each time the gap reaches `_ackEveryBytes`. Both maps are cleared in `closeTerminal` and on reconnect, so a reattached pane starts its count at zero — which matches the host, where `clientState.delivered` starts at zero for a fresh connection.

- [ ] **Step 1: Write the failing test**

Append to `packages/mobile/test/core/mux/mux_client_test.dart`, inside the existing top-level `group`:

```dart
  test('acks the terminal every 5,000 bytes consumed', () async {
    final socket = _FakeMuxSocket();
    final client = MuxClient(serverConfigStore, socket: (_) => socket);
    await client.connect();
    client.openTerminal('pane-1');

    String payload(int bytes) => base64Encode(List<int>.filled(bytes, 0x78));
    socket.pushMessage({'ch': 'terminal', 'id': 'pane-1', 'type': 'data', 'data': payload(2000)});
    socket.pushMessage({'ch': 'terminal', 'id': 'pane-1', 'type': 'data', 'data': payload(2000)});
    await Future<void>.delayed(Duration.zero);
    expect(socket.sent.where((raw) => raw.contains('"type":"ack"')), isEmpty);

    socket.pushMessage({'ch': 'terminal', 'id': 'pane-1', 'type': 'data', 'data': payload(2000)});
    await Future<void>.delayed(Duration.zero);
    final acks = socket.sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((msg) => msg['type'] == 'ack')
        .toList();
    expect(acks, hasLength(1));
    expect(acks.single['id'], 'pane-1');
    expect(acks.single['bytes'], 6000);

    await client.disconnect();
  });

  test('does not ask the daemon for session history', () async {
    final socket = _FakeMuxSocket();
    final client = MuxClient(serverConfigStore, socket: (_) => socket);
    await client.connect();
    client.openTerminal('pane-1');

    final opens = socket.sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((msg) => msg['ch'] == 'terminal' && msg['type'] == 'open')
        .toList();
    expect(opens, isNotEmpty);
    for (final open in opens) {
      expect(open['history'], isNot(true), reason: 'the xterm fork would print the history rows as text');
    }

    await client.disconnect();
  });

  test('a closed terminal restarts its ack count', () async {
    final socket = _FakeMuxSocket();
    final client = MuxClient(serverConfigStore, socket: (_) => socket);
    await client.connect();
    client.openTerminal('pane-1');

    String payload(int bytes) => base64Encode(List<int>.filled(bytes, 0x78));
    socket.pushMessage({'ch': 'terminal', 'id': 'pane-1', 'type': 'data', 'data': payload(6000)});
    await Future<void>.delayed(Duration.zero);
    client.closeTerminal('pane-1');
    client.openTerminal('pane-1');
    socket.pushMessage({'ch': 'terminal', 'id': 'pane-1', 'type': 'data', 'data': payload(6000)});
    await Future<void>.delayed(Duration.zero);

    final acks = socket.sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((msg) => msg['type'] == 'ack')
        .map((msg) => msg['bytes'] as int)
        .toList();
    expect(acks, [6000, 6000]);

    await client.disconnect();
  });
```

`MuxClient(serverConfigStore, socket: (_) => socket)` is whatever constructor the file's existing tests use — read them and copy the call verbatim, including how they await `connect()`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile && flutter test test/core/mux/mux_client_test.dart --plain-name 'acks the terminal'
```
Expected: FAIL — no `"type":"ack"` frame is ever sent.

- [ ] **Step 3: Count and ack**

In `packages/mobile/lib/core/mux/mux_client.dart`, add the constant at file scope next to the other top-level declarations, two maps as fields on `MuxClient`:

```dart
const int _ackEveryBytes = 5000;
```
```dart
  final Map<String, int> _consumedBytes = {};
  final Map<String, int> _ackedBytes = {};
```

extend the `'data'` case (`:216-217`):

```dart
        case 'data':
          final bytes = base64Decode(msg['data'] as String? ?? '');
          _terminalEventsController.add(TerminalDataEvent(id, bytes));
          _noteConsumed(id, bytes.length);
```

and add the two methods next to `resize`:

```dart
  void _noteConsumed(String id, int bytes) {
    if (id.isEmpty || bytes <= 0) return;
    final consumed = (_consumedBytes[id] ?? 0) + bytes;
    _consumedBytes[id] = consumed;
    if (consumed - (_ackedBytes[id] ?? 0) < _ackEveryBytes) return;
    _ackedBytes[id] = consumed;
    ackTerminal(id, consumed, projectId: _openTerminals[id]);
  }

  void ackTerminal(String id, int bytes, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'ack', 'bytes': bytes, 'projectId': projectId});
  }
```

Clear both maps for the pane in `closeTerminal` (`:305-308`):

```dart
    _consumedBytes.remove(id);
    _ackedBytes.remove(id);
```

and clear both entirely wherever the client reopens its terminals after a reconnect (`:168`, the `_openTerminals` replay loop) — a reconnect is a fresh host connection whose `delivered` starts at zero, so a carried-over cumulative ack would immediately look like an over-ack. The host clamps `acked` to `delivered` anyway (Task 10 Step 4), so this is belt and braces, but it keeps the two sides' arithmetic honest.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile && flutter test test/core/mux/mux_client_test.dart
```
Expected: PASS.

- [ ] **Step 5: Full mobile gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile && flutter analyze && flutter test
```
Expected: `No issues found!` and a green suite.

- [ ] **Step 6: CHANGELOG and commit**

`packages/mobile` has no `CHANGELOG.md`; the behaviour entry for this pair of clients was already written in Task 11. Add one line to `packages/terminal/CHANGELOG.md` under the same "Unreleased" heading only if you changed the wire shape — you did not.

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/mobile && git commit -m "$(cat <<'MSG'
mobile: ack terminal bytes every 5,000 consumed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 13: Measurement — the "After Plan C" column, the Part 1.4 rows Plan C owns, `TERMINAL.md`

**Files:**
- Modify: `packages/terminal/bench/agent-session/main.ts` (the session API this task needs), `run.mjs` (the new rows), `scroll-gate.mjs` (the width-change phase)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go` (history rows recovered)
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (the baseline table's new column, the Part 1.4 paragraph)
- Modify: `TERMINAL.md` (§1, §4, §5, §6)

**Interfaces:**
- Consumes: every row `run.mjs` already prints (`feedCost`, `feedSyncCost`, `spinner.*`, `tearing`, `longTask`, `reopen`, `rendererMemoryBytes`, `idlePanes`, `selectionRepaint`), `bench:agent:scroll`'s coverage and trim phases, `bench:feel`, `TestAgentSessionReplayReport`.
- Produces:
  ```ts
  // bench/agent-session/main.ts, added to window.__agentSession
  /** Feeds a full four-part replay (frame + every history chunk) and returns
   *  the ms to the first paint and the ms to the last chunk applied. */
  reopenFromReplay(frame: Uint8Array, chunks: Uint8Array[]): Promise<{ firstPaintMs: number; allRowsMs: number; rows: number }>;
  /** Resizes the core and returns the ms until the next paint settles and the
   *  stable row under the top edge before and after. */
  widthChange(cols: number): Promise<{ settleMs: number; before: number; after: number; staleRows: number }>;
  staleRowCount(): number;
  ```
  ```go
  // agent_session_test.go — added to the REPORT map
  "historyChunks", "historyBytes", "historyRows", "historyRenderMs"
  ```

- [ ] **Step 1: Extend the Go reopen report with the history parts**

In `backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go`, in `TestAgentSessionReplayReport`, after the existing `p.Replay(1000)` block, stream the history off the **capped** mirror (the one built at `productMirrorLimits`, which holds the whole fixture) and record it:

```go
	historyStart := time.Now()
	var historyBytes, historyRows, historyChunks int
	var historyOut []byte
	before := HistoryBefore
	for {
		chunk, next, ok, err := capped.HistoryChunk(before, 1000, HistoryChunkRows)
		if err != nil {
			t.Fatalf("history chunk: %v", err)
		}
		if !ok {
			break
		}
		historyChunks++
		historyBytes += len(chunk)
		historyRows += strings.Count(chunk, "\r\n")
		historyOut = append(historyOut, chunk...)
		before = next
	}
	historyMs := float64(time.Since(historyStart).Microseconds()) / 1000
```

add `"historyChunks": historyChunks, "historyBytes": historyBytes, "historyRows": historyRows, "historyRenderMs": historyMs` to the `report` map, and write `historyOut` beside the replay when `OPERATOR_AGENT_REPLAY_OUT` is set (as `<out>.history`) so `run.mjs` can feed it.

- [ ] **Step 2: Extend the harness**

In `packages/terminal/bench/agent-session/main.ts`, add the three entries to `window.__agentSession` and to the `AgentSession` type. `reopenFromReplay` feeds the frame, waits for the first paint (the loop `reopenReport` already uses at `run.mjs:205-212`), then feeds each chunk and waits for the paint that follows the last one; `widthChange` records `session.visibleRows()[0].row`, calls `core.resize(cols, rows)`, waits two frames past the settle, and records the top-edge row again; `staleRowCount` reads Task 8's `core.staleRowCount()` through the TS wrapper (add `staleRowCount(): number` to `ts/core/src/terminal-core.ts`, forwarding to `inner.stale_row_count()`, and export it from `vt-wasm` as a `#[wasm_bindgen]` getter).

- [ ] **Step 3: Add the rows to `run.mjs` and the width phase to `scroll-gate.mjs`**

In `run.mjs`, extend `reopenReport` to read the `.history` file and call `reopenFromReplay`, so the reopen row reports `{ firstPaintMs, allRowsMs, rows, historyChunks, historyBytes }`. Add a `widthChange` row that runs `widthChange(40)` on `claude-long-50k` at full length and prints `{ settleMs, before, after, staleRows }`.

In `scroll-gate.mjs`, add a third phase after the trim phase, on its own page:

```js
	const widthPage = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await widthPage.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
	await widthPage.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	const width = await widthPage.evaluate(async () => {
		const session = window.__agentSession;
		await session.feedAll();
		await session.setScrollTop(Math.floor(session.scrollHeight() / 2));
		const result = await session.widthChange(40);
		const rows = [];
		let top = session.scrollTop();
		for (let step = 0; step < 40 && top > 0; step += 1) {
			top = Math.max(0, top - 450);
			await session.setScrollTop(top);
			rows.push(session.visibleRows()[0]?.row ?? null);
		}
		return { ...result, scrolledRows: rows.filter((row) => row !== null).length };
	});
	await widthPage.close();
	if (width.before !== width.after) throw new Error(`top-edge row moved across a width change: ${width.before} -> ${width.after}`);
	if (width.staleRows === 0) throw new Error("the width change rewrapped every row eagerly; lazy rewrap is not engaged");
	process.stdout.write(`${JSON.stringify({ fixture, width })}\n`);
```

- [ ] **Step 4: Run every measurement and record what it prints**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
```
Paste the literal JSON each command prints into the spec. **Do not invent numbers and do not tune anything to make a target hit** — a missed target is reported as a miss, with what was measured and where the time went if you know.

- [ ] **Step 5: Fill the spec's "After Plan C" column**

In `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`, add an **After Plan C** column to the baseline table and fill every row from Step 4's output. Rows Plan C does not touch are filled with the measured value plus "unchanged within run-to-run noise" — measure them, do not copy Plan B's numbers across.

Then add a "Plan C landed" paragraph after the Plan B one, answering the **four Part 1.4 rows Plan C owns**, each with its measured evidence:

1. **Width change at 200k rows: the viewport is correct within the debounce plus one frame; older rows rewrap on scroll without a jump.** Evidence: `bench:agent:scroll`'s width phase (`settleMs`, `before === after`, `staleRows > 0`, `scrolledRows`), measured at the fixture's 60k rows — say so, the spec's target is 200k.
2. **Reopen after 200k rows: first paint < 200 ms on localhost; all rows reachable; blocks identical (ids, exit codes, commands) to the live pane.** Evidence: `reopen.firstPaintMs`, `reopen.allRowsMs`, `reopen.rows` against the mirror's `mirrorCapRows`, and a block comparison. For the block half, add one assertion to `TestAgentSessionReplayReport`: feed the frame and every history chunk into a *second* `vtwasm` parser and compare its rendered block list to the source mirror's. If the two differ, report the difference rather than relaxing the check.
3. **Renderer core and mirror each < 128 MiB at 200k rows.** Evidence: `rendererMemoryBytes` and the Go report's `mirrorCapWasmBytes`, which `TestAgentSessionReplayReport` already fails on above 128 MiB.
4. **A slow-link burst (H).** Evidence: a short paragraph from `TestReadPausesPastHighWatermarkAndResumesOnAck` and `TestHistoryStreamingNeverPausesTheChild`, plus one real-app observation if you can get it — how long the child stayed paused and that output resumed intact. If you cannot get a real-app number, say so; do not manufacture one. State explicitly that the pause test attaches to a session **with** a replay frame, since a test that attached to an empty one would pass while flow control was dead for every real pane.

Note explicitly which measurements were taken at the fixture's ~60k rows rather than the spec's 200k, and that the `claude-long-50k` fixture is the only long recording in the tree.

- [ ] **Step 6: Update `TERMINAL.md`**

- **§1** (the pipeline): the attach line becomes "handshake: client states its grid (and whether it can read history), host replays origin + modes + the mirror's screen + READY, returns, then — for a client that asked — streams history newest→oldest in 512-row chunks, then live bytes".
- **§2** (vt-core model in one page): one bullet for prepended history (`Content` allocates downward from `CONTENT_BASE`; rows stay offset-ordered, which is what every trim, style lookup and integrity check rests on; `adopt_origin` is what puts a fresh core into the replaying host's stable row space, and without it the two spaces never meet and every chunk is dropped) and one for stale runs (`HOT_ROWS = 2_000`, `rows_for`, the estimate that corrects on touch, and the rule that a run boundary is always a line start).
- **§4**: a new entry **§4.19 Reopening a long session recovered only the mirror's last screen** — symptom, cause (`Replay(MaxOutputLines)` was the whole attach), and the two traps the fix has to keep clear, because both were live defects in the first draft of the plan: (a) the mirror and the reopened core number rows in different stable spaces, so the replay states its origin **first** and `Parser::adopt_origin` refuses to act once a row exists; (b) a chunk's closing `exit=` mark must sit **inside** its last row, before the CR-LF, or it falls through to the live parser and closes the live agent's open block. Guards: `TestReplayOpensWithTheOriginMark`, `TestReplayOrderIsModesFrameReadyHistory`, `TestAHistoryChunkEndsAtARowTerminator`, `TestClientPaintsAtReadyBeforeHistory`, `TestAClientWithoutHistoryOptInGetsNoChunks`, `TestAFreshSessionAttachIsUnchanged`, `vt-core/tests/replay.rs`, the useTerminalSession "paints at READY" test.
- **§5** (known gaps): **delete** the "Rewrap walks all scrollback rows on every width change … lazy rewrap is Plan C 1.3.F" bullet and replace it with what is true now — the hot region is still walked eagerly on every width change, a cold run is walked once on first access, and the row count above the viewport is an estimate until touched. Add two new gaps:

  - **A reopened pane's prepended rows lose their `wrapped` flag.** `vt_history_chunk` emits every history row CR-LF terminated and `Parser::apply_history_chunk` prepends them with `wrapped: false`, so a later width change cannot rejoin a logical line the mirror had soft-wrapped — those rows rewrap as independent lines. Rows the pane produces *after* the reopen are unaffected. Carrying the flag means emitting wrapped rows without `\r\n` and sizing the receiver's scratch screen to the mirror's width (a `cols=<n>` field on the chunk mark), which would make the chunk's row count depend on the receiver's own wrapping instead of on the mark's `count` — the invariant `HistoryReceiver::consume` ends a chunk on. Revisit with a second anchor for that invariant; do not "fix" it by loosening the row count.
  - Any gap Step 4's measurements exposed.
- **§6**: add `npm run bench:agent:scroll` to the recipe if it is not there, since its width phase is now a gate.

- [ ] **Step 7: Run the complete §6 recipe one last time**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/packages/mobile && flutter analyze && flutter test
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all PASS; `bench:feel` reports `PASS feel gate: zero pixel diff`.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend docs TERMINAL.md && git commit -m "$(cat <<'MSG'
bench/docs: Plan C numbers, the width-change gate, TERMINAL.md §1/§2/§4.19/§5

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

Tell the user: **restart the daemon and the app**, and report every Part 1.4 row with its measured value — including any that missed.

---

## Verification summary

Run what the task touched; every task runs the feel gate. All paths absolute (`TERMINAL.md` §6: parallel Bash calls share the working directory).

| Layer touched | Commands |
|---|---|
| Any Rust crate | `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` |
| `vt-core` or `vt-host` | the above, **plus** `cargo build --release -p vt-host --target wasm32-unknown-unknown` copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **plus** `npm run build:wasm -- --force && npm run build:ts`, **plus** `npm --prefix frontend run build:daemon` — and ends with "restart the daemon and the app" |
| Go (`ptyhost`, `terminal`, `httpd`) | `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... -count=1` (add `-race` for Task 10) |
| `ts/*` | `cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done` |
| `frontend/` | `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run && npx tsc --noEmit -p .` |
| `packages/mobile` | `cd /Users/omaraly/development/AI/Operator/packages/mobile && flutter analyze && flutter test` |
| **Every task** | `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel` → must print `PASS feel gate: zero pixel diff` |
| Renderer or model | `npm run bench:selection`, `npm run bench:agent:gate`, `npm run bench:agent:scroll` |
| Bench rows Plan C owns | reopen time-to-first-paint and rows recovered at 1k/5k/50k; width change at 50k; a slow-link burst (Task 10's Go test) |
