# Server-owned terminal model: the mirror as the model of record

**Date:** 2026-09-22
**Decision owner:** Omar Aly
**Status:** not pursued — its implementation was dropped by the user on 2026-09-22. Kept as a record of the design and of why it was not taken forward; see "Why not pursued" below.
**Derived from:** `docs/terminal/2026-09-19-terminal-reference-survey.md` §4.2
(with §4.5 for width, §1.9 and §3.1 for what it subsumes), and
`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` Part 6.
**Motivated by:** `docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`.
**Prerequisites, all landed:** Plan B `ba6dd6d35` (stable rows, incremental
export), Plan C `7412050f4` (attach/replay with history, flow control), Plan D
`b4c3067b2` (text and glyphs), Plan E `7336d8150` (wrapped and link exports).
Confirm with `git log --oneline | grep -i "merge: Plan"`.

**Why not pursued.** The phone's problem is that it shows a picture drawn for
the desktop's width. This design would deliver that picture as rows instead of
bytes, and §7 assumed a narrower client could rewrap scrollback from the
exported `wrapped` flags. That does not hold for Claude Code: it lays out every
row itself with cursor motion instead of printing lines for the terminal to
wrap (`packages/terminal/bench/agent-session/fixtures/claude-long-50k/recording`:
rows advanced by `\r ESC[1B`, 10,252 rows filled to 110–120 of 120 columns),
so no row is flagged `wrapped` and there are no logical lines to rejoin. The
live frame could never be rewrapped either (§7). The design is therefore
recorded, not scheduled, and nothing below is an open commitment.

A note on citations. Every `path:line` here is repo-relative (or absolute, for
the WezTerm checkout at `/Users/omaraly/development/AI/wezterm`) and was opened
at that line in the tree this spec was written against. Files the design
proposes creating are written `path (new)` with no line. `TERMINAL.md` §2 cites
several of the same functions by older line numbers (lib.rs 291 and 340,
parser.rs 529, block_grid.rs 27); the code has moved since, and the lines
below are the current ones. `scripts/check-spec-citations.mjs` checks that
every cited line exists.

## Why

The measurement
([`2026-09-22-remote-typing-latency-measurement.md`](2026-09-22-remote-typing-latency-measurement.md))
settled what this is **not**. Its headline rows:

| Leg | first byte median | visible median | visible p95 |
|---|---|---|---|
| loopback | 6.6 ms | 6.7 ms | 17.6 ms |
| public tunnel | 106.7 ms | 111.7 ms | 146.8 ms |
| Claude's trivial turn (Enter → answer on screen) | — | 1240.3 ms | range 1071.8–1567.0 ms |

A keystroke echo costs ~107 ms over the public tunnel and ~7 ms locally;
Claude's cheapest possible turn is 1.07–1.57 s (median 1.24 s), and any real
prompt is tens of seconds. The phone's felt wait after send is Claude's turn —
the network is ~8 % of the floor and under 1 % of a real prompt.

**§4.2 does not improve either number.** Rows instead of bytes do not shorten a
tunnel round trip, and they do not make Claude think faster. Nobody should read
this spec as a latency fix, and a plan that promises latency from it is
mis-scoped (agent-TUI spec, "Plans this spec produces", last paragraph).

What §4.2 changes is **what the phone is**. Today the phone is a second, weaker
terminal: it runs its own VT engine — the vendored Dart `xterm` fork — which
cannot know about blocks, has none of Plans D and E's affordances, keeps 5,000
lines, and never asks for Plan C's history. Every client re-derives the same
model from the same bytes. The pty-host mirror already holds the one model that
saw every byte from the child's first; this spec makes it the model of record
and has clients read rows from it.

## Today

**The byte channel.** The mux protocol is one JSON stream tagged by channel
(`backend/internal/terminal/protocol.go:21-27`); the terminal channel's
message types include `data` in both directions and `ack` from the client
(`backend/internal/terminal/protocol.go:30-39`). Output leaves the daemon as
`serverMsg{Ch: "terminal", Type: "data", Data: base64}`
(`backend/internal/terminal/protocol.go:93-110`). The HTTP mount is
`backend/internal/httpd/terminal_mux.go:24` (`mountTerminalMux`); the channel
logic lives in `backend/internal/terminal/manager.go`.

**One attachment per mux connection per pane.** `connState.handleTerminal`
(`backend/internal/terminal/manager.go:401-435`) dispatches `open`, `data`,
`resize`, `close` and `ack`. `openTerminal` builds a fresh `attachment` for the
connection (`backend/internal/terminal/manager.go:456`) whose `onData` wraps
every chunk as a base64 `data` frame
(`backend/internal/terminal/manager.go:460-467`). The attachment's run loop
dials its own pty-host stream on every attach and re-attach
(`backend/internal/terminal/attachment.go:99-199`, the dial at
`backend/internal/adapters/runtime/ptyhost/attach.go:27-38`) and copies bytes
out unchanged (`backend/internal/terminal/attachment.go:202-215`). The fan-out
to several viewers therefore happens in the pty-host, which writes every batch
to every connection (`backend/internal/adapters/runtime/ptyhost/host.go:707`
`broadcastLocked`, called from `deliver`,
`backend/internal/adapters/runtime/ptyhost/host.go:593`). **Every client parses
every byte.**

**The desktop feeds its own `vt-core`.** `mux.onData`
(`frontend/src/renderer/hooks/useTerminalSession.ts:575`) hands bytes to
`BlockTerminal`'s `feedToCore`
(`frontend/src/renderer/components/BlockTerminal.tsx:158-162`), which enqueues
them on the renderer core; the budgeted drain calls `TerminalCore.feed`
(`packages/terminal/ts/core/src/terminal-core.ts:152`), which is
`inner.feed(bytes, Date.now())`
(`packages/terminal/ts/core/src/terminal-core.ts:114-118`). The DOM renderer
reads `snapshot()` (`packages/terminal/ts/core/src/terminal-core.ts:234`) and
`takeDirty()` (`packages/terminal/ts/core/src/terminal-core.ts:357`). Acks go
every `ACK_EVERY_BYTES` of consumed bytes
(`frontend/src/renderer/hooks/useTerminalSession.ts:591-597`); the frame
builders are `frontend/src/renderer/lib/terminal-mux.ts:52-83` (`openFrame`
with the `history` flag, `data`, `ack`).

**The phone feeds a second VT engine.** `MuxClient` decodes a `data` frame and
counts it for acks (`packages/mobile/lib/core/mux/mux_client.dart:222-225`,
`_noteConsumed` at `packages/mobile/lib/core/mux/mux_client.dart:314-321`).
`TerminalCubit._onEvent` pushes the bytes through a chunked UTF-8 decoder
(`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:152-156`,
`:133-134`) into `Terminal.write`
(`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:66`)
— the vendored Dart `xterm` at `packages/mobile/packages/xterm`, constructed
with `maxLines: 5000`
(`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:117`).
Keystrokes go the other way through `terminal.onOutput`
(`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:99`).
The phone opens as `role: 'secondary'` and never sends `history`
(`packages/mobile/lib/core/mux/mux_client.dart:300-303`), so a reopened phone
pane gets the mirror's frame and none of Plan C's history chunks.

**The mirror already runs `vt-core` server-side, but only for the replay.**
`vt_new` builds the mirror with reflow off and query answering on
(`packages/terminal/crates/vt-host/src/lib.rs:24-33`); the Go side wraps it in
`backend/internal/adapters/runtime/ptyhost/vtwasm` (`Replay`,
`backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:247`;
`TouchHistory`, `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:262`;
`HistoryChunk`, `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:274`).
Every batch is fed to it after the broadcast (`feedParserLocked`,
`backend/internal/adapters/runtime/ptyhost/host.go:673`). On attach,
`handleConn` (`backend/internal/adapters/runtime/ptyhost/host.go:744`) renders
the frame (`replayFrameLocked`,
`backend/internal/adapters/runtime/ptyhost/host.go:911`), reads the origin back
out of it (`replayOrigin`,
`backend/internal/adapters/runtime/ptyhost/host.go:941`) and streams history
from that bound (`streamHistory`,
`backend/internal/adapters/runtime/ptyhost/host.go:979`) — `TERMINAL.md` §1,
§4.19–§4.21. The pty-host already sizes the pty to the largest attached grid
(`applyLargestLocked`,
`backend/internal/adapters/runtime/ptyhost/host.go:316`); smaller clients scale.

**What the model already has that §4.2 needs.**

- Stable rows: `stable_row(flat)` and `flat_row(stable)`
  (`packages/terminal/crates/vt-core/src/lib.rs:435`,
  `packages/terminal/crates/vt-core/src/lib.rs:439`) over
  `Parser::trimmed_total` (`packages/terminal/crates/vt-core/src/parser.rs:50`,
  read at `packages/terminal/crates/vt-core/src/parser.rs:140`), and the block
  grid's `origin` (`packages/terminal/crates/vt-core/src/block_grid.rs:29`,
  accessor `packages/terminal/crates/vt-core/src/block_grid.rs:51`). The
  exporter carries `first_stable_row` per snapshot
  (`packages/terminal/crates/vt-wasm/src/export.rs:548`).
- A generation counter: `TerminalCore::generation`
  (`packages/terminal/crates/vt-core/src/lib.rs:364`) is
  `Parser::note_mutation`'s `wrapping_add(1)`
  (`packages/terminal/crates/vt-core/src/parser.rs:144-149`). It is **one
  counter per core**. No row records the generation at which it last changed.
- A dirty-row delta: `take_delta`
  (`packages/terminal/crates/vt-core/src/lib.rs:368`) drains a `Delta`
  (`packages/terminal/crates/vt-core/src/delta.rs:10-18`: `generation`, `kind`,
  `trimmed_rows`, `appended_history`, `screen_rows`, `remap`,
  `history_rewritten_from`). Screen dirty bits are set by the cell writers
  (`packages/terminal/crates/vt-core/src/screen.rs:240` `mark_dirty`, drained at
  `packages/terminal/crates/vt-core/src/screen.rs:250`) and by cursor moves
  (`packages/terminal/crates/vt-core/src/screen.rs:378`). `ExportBuffers::apply`
  (`packages/terminal/crates/vt-wasm/src/export.rs:201`) already turns one
  `Delta` into an in-place update of the exported buffers.
- Blocks and per-row fields the phone lacks: blocks, `rowWrapped`,
  `rowIndents`, style runs, cell spans and the OSC 8 link table, all in the
  snapshot (`TERMINAL.md` §2, "Snapshot").
- History prepend: `Parser::adopt_origin`
  (`packages/terminal/crates/vt-core/src/parser.rs:567`) and
  `Parser::apply_history_chunk`
  (`packages/terminal/crates/vt-core/src/parser.rs:580`).

## The gap

The mirror is the only party that sees every byte from the child's first. That
is already load-bearing: it answers XTVERSION, DA1 and DECRQM because a
renderer would answer once per attached client and would miss the probes sent
before it attached (`TERMINAL.md` §4.16). Yet it is treated as a replay
source. Each client re-derives the same model from the same bytes, so:

- the phone needs a VT engine to show a terminal at all, and it runs a
  different one from the desktop;
- every affordance Plans D and E built — blocks, SGR attributes, grapheme
  clusters, logical-line copy, OSC 8 links, hover links, hint mode, secret
  redaction, block timestamps — lives in `packages/terminal/ts/renderer-dom`,
  which the phone never loads;
- a reattach re-parses a byte replay whose correctness rests on four orderings
  that each broke once (`TERMINAL.md` §4.19–§4.21);
- a slow link delivers every intermediate byte, not the latest frame.

Two settings also keep the mirror from being the *same* model a client renders
today: it always runs with reflow off (`packages/terminal/crates/vt-host/src/lib.rs:32`)
while a shell pane's renderer core reflows, and it always runs in scalar width
mode while the renderer may run in grapheme mode (`TERMINAL.md` §2, "Width
mode"). A model of record must run with the settings its clients would have
chosen.

## The design

### 1. Rows addressed by `(stable row, generation)`

The mirror stamps every row with the generation at which it last changed and
answers two questions:

- `changed_since(generation) -> ranges` — the stable-row ranges whose stamp is
  newer than `generation`;
- `rows(stable range) -> rows` — the row records for a range, in the shape the
  snapshot already exports (content, style runs, cell spans, `wrapped`,
  `indent`, link ids).

This is WezTerm's design. Each `Line` carries a seqno and answers
`changed_since`
(`/Users/omaraly/development/AI/wezterm/wezterm-surface/src/line/line.rs:283-300`);
every screen mutation stamps its line through `dirty_line`
(`/Users/omaraly/development/AI/wezterm/term/src/screen.rs:342-345`); the pane
exposes `get_current_seqno` and `get_changed_since(range, seqno)`
(`/Users/omaraly/development/AI/wezterm/mux/src/pane.rs:179-192`); the server's
`PerPane::compute_changes` remembers each client's last seqno and cursor and
turns them into a push
(`/Users/omaraly/development/AI/wezterm/wezterm-mux-server-impl/src/sessionhandler.rs:39-145`);
the client keeps a `LineEntry` cache of `Line`, `Fetching`, `LineAndFetching`
and `Stale` (`/Users/omaraly/development/AI/wezterm/wezterm-client/src/pane/renderable.rs:31-43`),
applies a push in `apply_changes_to_surface`
(`/Users/omaraly/development/AI/wezterm/wezterm-client/src/pane/renderable.rs:305-370`)
and batches fetches in `schedule_fetch_lines`
(`/Users/omaraly/development/AI/wezterm/wezterm-client/src/pane/renderable.rs:495`).

**What our `generation()` is and is not.** It is per core
(`packages/terminal/crates/vt-core/src/parser.rs:144-149`), bumped once per
mutating feed. It says "something changed", never "this row changed at g". The
`Delta` says which rows changed since the *last drain*, which is per consumer
and destructive — one `take_delta` per core, so it cannot serve two clients at
different points. A per-row stamp is **new work**:

- screen rows: stamped wherever `mark_dirty` is called today
  (`packages/terminal/crates/vt-core/src/screen.rs:240`), with the generation
  the feed will publish;
- scrollback rows: immutable after eviction except for rewrap, trim and
  prepend, so a row's stamp is its commit generation, restamped when a rewrap
  rewrites it (`history_rewritten_from` in `Delta` already identifies the
  first rewritten row);
- trim is not a stamp: rows off the front simply stop existing, and the push
  carries the new first stable row.

**A width change renumbers rows.** A stable row is `trimmed_total + flat
index`; a rewrap changes how many rows a logical line occupies and so moves
every stable row below it. `Delta.remap` exists for exactly this. The protocol
therefore carries a **layout epoch**: a push after a rewrap names the new
epoch and the first affected stable row, and a client drops (marks `Stale`)
every cached row at or below it, the way WezTerm's `make_all_stale` does after
a reconnect. A respawn resets the mirror (`TERMINAL.md` §4.15), which is also a
new epoch.

### 2. What replaces the byte channel, and what stays

For a row-mode attachment the terminal channel gains:

- **`render_changes`** (server push): `{epoch, generation, firstStableRow,
  cursor, dims, modes, blocks, bonusRows, dirtyRanges}`. `bonusRows` are the
  changed rows of the viewport plus the cursor row, sent eagerly
  (`compute_changes` sends the viewport the same way and always includes the
  cursor row); `dirtyRanges` are the remaining changed ranges, which a client
  fetches only if it is looking at them. `blocks` are block records, not
  marks.
- **`get_rows`** (client request): `{epoch, ranges}` → `rows {epoch,
  generation, rows}`. This is how scrollback, reattach and history are read.
- **`ack`** becomes "I have applied generation g", not "I have consumed n
  bytes" (§6 below).

What stays byte-shaped:

- **Input.** Keystrokes and pastes are bytes to a pty; `data` client→server is
  unchanged, and so are `resize` and `close`.
- **Byte-mode attachments.** A shell pane using the line editor, any client
  that does not opt in, and any non-daemon host of `packages/terminal` keep
  `type: 'data'` exactly as today. Row mode is opted into per `open`, the way
  `history` is today (`frontend/src/renderer/lib/terminal-mux.ts:52-59`).
- **The alternate screen, possibly.** The renderer already exports an
  `AltSnapshot` (`TERMINAL.md` §2), so serving the alt grid as rows is
  mechanically the same shape; whether the first cut does so is Decision 2.

**Where the push is computed.** In the pty-host, because it owns the mirror
and already has one `clientState` per connection — which, per the tree today,
is one per daemon attachment, which is one per mux connection per pane. Each
`clientState` gains `{epoch, generation}` for row mode. Pushes are scheduled
from the pump's flush (`backend/internal/adapters/runtime/ptyhost/host.go:439`
`pumpPTY`) and coalesced: a client whose previous push is unacknowledged gets
the next one computed against its last acknowledged generation, so a slow link
receives the latest frame rather than every intermediate one.

**What `connState.handleTerminal` becomes.** A relay. For a row-mode
attachment the `onData` closure
(`backend/internal/terminal/manager.go:460-467`) is replaced by one that
forwards `render_changes` and `rows` frames, and `get_rows` joins `data`,
`resize` and `ack` as a client message forwarded onto the attachment's
pty-host stream. The daemon keeps no terminal state of its own, as today.

**DEC 2026.** The mirror only ever exposes parsed state, and an open sync
block's bytes sit in front of its parser (`TERMINAL.md` §4.16), so a push can
never carry half a frame. The pump's hold-until-terminator exists to stop a
byte client from receiving a frame split across two messages; row clients do
not need it, byte clients keep it.

### 3. Plan C's attach, replay and history under rows

Today an attach streams, in this order: the origin mark, modes, the live
frame, `READY`, then history newest→oldest in 512-row chunks framed by
`history=<first_stable_row>,<count>` marks, then live bytes
(`TERMINAL.md` §1, §4.19; `backend/internal/adapters/runtime/ptyhost/host.go:744`;
the receiver is `Parser::adopt_origin`,
`packages/terminal/crates/vt-core/src/parser.rs:567`, and
`Parser::apply_history_chunk`,
`packages/terminal/crates/vt-core/src/parser.rs:580`).

Under rows, an attach is a `render_changes` computed against generation 0:
the viewport rows, cursor, modes, blocks and `firstStableRow` now; the rest on
scroll through `get_rows`, in whatever order and granularity the client
needs. `READY` is implicit — the first push *is* the paintable frame. A
reattaching client that states a stale generation gets the viewport as bonus
rows and the rest as `dirtyRanges`, exactly as WezTerm does after
`make_all_stale`.

What happens to each trap `TERMINAL.md` §4.19–§4.22 records:

- **§4.19 (a), origin before any row — disappears.** No client parser is
  planted into another core's stable-row space; rows arrive labelled with
  their stable row. It survives only as the epoch rule: rows from an old
  epoch are never mixed with rows from a new one.
- **§4.19 (b), the `exit=` mark inside the chunk's last row — disappears.**
  Blocks are records in the push, not marks in a byte stream, so there is no
  trailing byte to fall through into the live parser.
- **§4.20, lazy rewrap truncated cold history — survives in a new form.** A
  `get_rows` for a range the mirror still holds stale must rewrap that range
  before exporting it, and a rewrap renumbers rows. The rule becomes: the
  mirror touches the requested range under its lock, cuts the response at one
  generation, and a response whose epoch the client has already left is
  discarded, never spliced. This is the same seam — rewrap moves rows out from
  under an anchor — addressed by tagging instead of by ordering.
- **§4.21, origin and first chunk snapshotted apart — disappears as an
  abutment check.** Each `rows` response is self-describing (epoch,
  generation, stable rows), so there is no "first chunk must abut the frame's
  origin exactly" invariant to fall out of. The generation tag replaces it.
- **§4.22, private `CSI … m` reaching SGR — disappears for row clients.** It
  was a parser bug in two dispatchers, one of them the history receiver's
  `ScreenPerform`. A row client runs neither; only the mirror parses.

Two `TERMINAL.md` §5 known gaps close by construction: prepended history rows
losing their `wrapped` flag (rows carry `wrapped`), and a block straddling a
512-row chunk boundary losing its tail (blocks are whole records).

### 4. The renderer's own `vt-core` copy

The `TerminalCore` API stays. For a row-mode session its source changes: `feed`
is replaced by `applyDelta(changes)` and a `getRows` callback, backed by a row
cache with WezTerm's `LineEntry` states. `snapshot()`, `takeDirty()`,
`onRowEvents()` and `logicalLines()` keep their contracts, so
`DomBlockRenderer` and everything above `snapshot()` — selection as grid
points in stable rows, the linkifier, hints, redaction, the scroll anchor — is
untouched. Stable rows are now the server's, so `data-terminal-row` means the
same row on every client.

The natural carrier is the export format the renderer already consumes:
`ExportBuffers` slices, spliced into the renderer core the way
`ExportBuffers::apply` (`packages/terminal/crates/vt-wasm/src/export.rs:201`)
splices a local `Delta` today. The proposed pieces are
`packages/terminal/ts/core/src/row-cache.ts (new)` and a row-delta type in
`packages/terminal/ts/core/src/types.ts` beside `HostCapabilities`
(`packages/terminal/ts/core/src/types.ts:244`), described without any Operator
concept — a second host with its own server could serve the same deltas.

`feed` stays, and must: `packages/terminal` is product-independent
(`TERMINAL.md` §3.1). A shell pane on the line editor
(`packages/terminal/ts/editor`), a byte-mode attachment and any non-daemon host
keep `feed`, the feed budget and the renderer's DEC 2026 handling. A core is in
one mode for its life; it never mixes bytes and rows.

### 5. What it buys

- **One model for desktop and phone.** Both render the mirror's rows; neither
  parses.
- **`packages/mobile/packages/xterm` deleted.** The phone stops carrying a
  second terminal engine.
- **The phone gets Plans D and E with no second implementation** — blocks,
  styles, grapheme clusters, logical-line copy, links, hints, redaction and
  block timestamps — provided it renders through `packages/terminal`
  (Decision 6).
- **The phone gets the whole session.** No 5,000-line cap, no missing history
  on reopen.
- **Predictive echo becomes reachable for the phone at all.** A client that
  owns a cached cursor row can predict into it and drop the prediction when a
  push confirms the input (WezTerm's `input_serial`,
  `/Users/omaraly/development/AI/wezterm/codec/src/lib.rs:927`). Without a row
  model the phone has nothing to predict into.
- **Frames, not bytes, on slow links**, through coalesced pushes.

### 6. What it costs and breaks

- **The mux protocol and both mux clients.**
  `backend/internal/terminal/manager.go` (the relay above),
  `backend/internal/httpd/terminal_mux.go`, the pty-host framing
  (`backend/internal/adapters/runtime/ptyhost/proto.go`),
  `frontend/src/renderer/hooks/useTerminalSession.ts` and
  `frontend/src/renderer/lib/terminal-mux.ts`, and
  `packages/mobile/lib/core/mux/mux_client.dart`.
- **The mirror's settings follow the session.** Reflow and width mode must be
  what the client would have chosen (see `## The gap`), so the mirror stops
  being one fixed configuration.
- **Server cost moves.** The pty-host now exports rows per client push and
  serves `get_rows`; the renderer core stops parsing. Mirror memory is
  unchanged for one mirror and multiplied under a per-grid policy (item 7).
- **The editor's local-echo path** (`packages/terminal/ts/editor`) is a
  byte-mode path and stays one; this design does not move shells to rows.
- **Offline on the phone.** Today the `xterm` buffer keeps whatever it parsed
  when the socket drops. Under rows the cache holds what was fetched; rows
  never fetched are unavailable until reconnect, and a reconnect is a stale
  generation (viewport as bonus rows). This must be stated in the phone's UI,
  not discovered.
- **Flow control.** Plan C's acks count bytes: the pty-host stops reading the
  pty while any acked connection is too far behind
  (`backend/internal/adapters/runtime/ptyhost/host.go:555-566`
  `unackedLocked`), and an ack is clamped to the connection's `delivered`
  (`backend/internal/adapters/runtime/ptyhost/host.go:1135-1148`).
  `TERMINAL.md` §5 ("Ack accounting is per pty-host CONNECTION, not per mux
  client") records two ways this already fails open. Under rows:
  - **The reattach mode is fixed by construction for row clients.** Today a
    re-attach opens a fresh pty-host connection with `delivered` at 0 while the
    renderer's byte count carries on, so acks clamp and the gate stays open.
    A row client acks a generation, and a fresh connection starts at
    generation 0 and sends the viewport — correct, not open.
  - **The multi-client mode.** For row clients there is nothing per-byte to
    account: a slow client gets a later, coalesced push, so the pty never has
    to be paused on its behalf, and one client's ack cannot stand in for
    another's because each `clientState` holds its own generation. This spec's
    reading of the tree finds one attachment, and so one pty-host connection,
    per mux connection per pane
    (`backend/internal/terminal/manager.go:456`,
    `backend/internal/terminal/attachment.go:141-154`); the case §5 describes,
    several mux clients sharing one pty-host connection, is not confirmed from
    that reading and should be re-checked before anything relies on either
    account.
  - **Byte clients inherit both modes unchanged.** This design does not fix
    byte-mode ack accounting.
- **Harness.** `npm run bench:feel` feeds recorded bytes straight to the
  renderer core. Proving a row-mode pane pixel-identical needs a harness path
  that feeds the fixture to a mirror core and serves its rows to a row-mode
  renderer core.

### 7. Width

Today one pty has one grid: the pty-host sizes it to the largest attached
client (`backend/internal/adapters/runtime/ptyhost/host.go:316`), secondaries
render that grid scaled (`backend/internal/terminal/protocol.go:55-62`), and
the mirror is at that grid. Two policies are possible under rows:

- **One mirror at the largest attached grid, clients rewrap logical lines
  locally** (survey §4.5). Cheap on the server. The client needs `wrapped` and
  `indent` per row (already exported) and its own rewrap of scrollback.
  An agent TUI's *live frame* cannot be rewrapped by anyone — the program drew
  it for the pty's grid — so a narrower client scales or clips it exactly as
  today.
- **One mirror per distinct grid.** Scrollback arrives already wrapped for
  each client, but every byte is parsed once per width and mirror memory
  multiplies (each capped at 128 MiB, `TERMINAL.md` §2 "Limits"), while the
  live frame is still drawn for the one pty grid.

This spec does not decide. It is Decision 1.

## Acceptance

Observable statements a later plan's tests are written against. None of them
is a task.

- Two clients at different generations on one session receive disjoint deltas:
  each receives exactly the rows changed since its own last acknowledged
  generation, and neither receives the other's.
- A reattaching client that states a stale generation receives the current
  viewport and cursor row as bonus rows in its first push, and the remaining
  changed rows as dirty ranges.
- A chunked `get_rows` walk from the viewport to the first stable row
  reconstructs the same rows — content, styles, `wrapped`, `indent`, links and
  block records — that today's byte replay with history produces for the same
  recording.
- A `rows` response cut before a width change and delivered after it is
  discarded by the client, and the rows it re-fetches match the post-rewrap
  mirror.
- A push never carries rows from inside an open DEC 2026 block.
- The phone renders a delta with blocks: block boundaries, exit codes and
  commands match the desktop's for the same session.
- A byte-mode attachment (shell pane, non-opted client) is byte-for-byte
  unchanged.
- The desktop's pixel output is unchanged: `npm run bench:feel` → zero pixel
  diff, for byte mode as today and for row mode through a mirror-in-the-loop
  harness. This is the constraint the whole agent-TUI spec ships under.

## Decisions needed

1. **Width policy** — one mirror at the largest attached grid with clients
   rewrapping logical lines locally, or one mirror per grid. Turns on: the
   cost of a client-side rewrap of `HOT_ROWS` (2,000) rows on the phone, and
   the mirror's memory and CPU per extra core at the 200k-row fixture. Neither
   is measured; both would be.
2. **Alternate screen as rows or bytes** in the first cut. Turns on: whether
   Claude Code's alt-screen views are common enough on the phone to justify
   serving `AltSnapshot` as rows immediately, versus keeping `type: 'data'`
   for the alt screen only and leaving a VT engine on the phone until it moves.
   Keeping bytes for it means the `xterm` fork cannot be deleted yet. One fact
   bears on it: Claude Code's main UI never enters the alternate screen — both
   real recordings (`packages/terminal/bench/agent-session/fixtures/claude-spinner-10s/recording`,
   `claude-long-50k/recording`) contain no `ESC[?1049h`, `?47h` or `?1047h` —
   so rows for the primary screen alone already cover the Claude Code prompt
   and transcript.
3. **`generation` per row or per range.** Per row is WezTerm's shape and makes
   `changed_since` exact; per range (a stamp per run of rows, split on write)
   is smaller for 200k-row scrollback that never changes. Turns on: the memory
   of a `u64` per row at the row cap, against the complexity of splitting
   ranges.
4. **Persist the mirror across app restarts** — the agent-TUI spec's open
   Decision 2. Turns on: whether a row-mode client ever reattaches to a
   mirror that did not see the child's first byte. Under rows the mirror is
   the only copy, so "no" means a restart loses the session's rows on every
   client, where today the renderer's own core at least keeps what it parsed
   until the pane closes.
5. **Delete the mobile `xterm` fork in the same release, or after a soak**
   with both paths present. Turns on: how much the phone is used against
   daemons that have not yet shipped row mode, and whether a byte-mode
   fallback on the phone is worth keeping for one release.
6. **How the Flutter client renders through `packages/terminal`.** A WebView
   hosting `renderer-dom` gives the phone Plans D and E with no second
   implementation; a native Dart renderer over the row protocol gives native
   scrolling and input but re-implements every affordance. Turns on: what the
   user accepts on the phone for touch, scroll and IME feel, and the size of a
   WebView bundle in `packages/mobile`. Only the first matches "no second
   implementation".
7. **Shell panes stay on bytes.** Proposed yes: the line editor is local echo
   by construction and shells gain less from rows. Turns on: whether the phone
   must show shell panes through the same renderer, since a byte-mode shell
   pane on the phone still needs a VT engine there.

## Non-goals

- **Predictive echo.** Plan F builds a desktop-only overlay that touches no
  row and no model (the plan's "Design decisions" section,
  `docs/superpowers/plans/2026-09-22-agent-tui-plan-f-remote-typing.md`); the
  measurement is why it is desktop-only. Echo on the phone is reachable only
  through this model and is designed after it lands, not here.
- **Latency.** Nothing here shortens the tunnel round trip or Claude's turn
  (see `## Why`).
- **Shell-mode behaviour**, and everything in the agent-TUI spec's own
  non-goals (OSC 133 options, prompt redraw on resize, the `vte::ansi`
  refactor, accessibility, remote agents, anything Claude Code does to
  itself).
- **Fixing byte-mode ack accounting.** Row mode avoids the problem; byte mode
  keeps it.
- **Implementation tasks.** None; the implementation was dropped (see "Why not
  pursued").
