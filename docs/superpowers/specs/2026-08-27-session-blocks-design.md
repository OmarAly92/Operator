# Session blocks — one screen, two sources

Status: proposed
Date: 2026-08-27
Supersedes: the mobile-only and desktop-parity drafts of this file, 2026-08-27
Scope: `packages/mobile`, `frontend/src/renderer`, `backend/internal` hook,
shell and stream paths

A session is shown as a **list of blocks**, on one screen, on both clients. What
varies underneath is where the blocks come from, and that is decided by the
session's mode. Both modes survive; both clients get the same screen.

## Problem

Three problems, one shape.

**Mobile is unusable.** The phone renders the same character grid the desktop
renders. `largestGrid` (`backend/internal/terminal/manager.go:307`) picks one
client's `cols` and `rows` as a pair, skipping non-primaries whenever a primary
has reported. The desktop is primary, so its grid is pushed to the phone and the
phone renders a desktop-shaped screen on a phone-shaped display. A 120-column
grid is unreadable at any font size that also fits 30 rows, so no styling fixes
it. The fix must be a view with no grid.

Note that the phone does **not** degrade the desktop while the desktop is
attached; an earlier framing claimed it did, and the code says otherwise.

**The desktop has no structure.** Its grid is correct, but an agent's work is a
wall of repainting TUI rather than a list of steps that can be scrolled,
collapsed, copied or searched.

**Chat and terminal are converging into duplication.** Both would render
near-identical block lists from different sources, with two model layers, two
sets of widgets and two timelines to keep consistent. Mobile chat is ~1100 lines
of data layer plus a large presentation layer; desktop chat is 38 components.
Duplicating block rendering across that boundary is the expensive mistake, and it
is cheap to avoid only while neither block view exists.

## The constraint everything follows from

`domain/sessionmode.go:14` states it:

> **SessionModeChat**: Operator owns a structured provider controller and the
> terminal, if opened, is a plain worktree shell — never a second copy of the
> agent.

`tui` and `chat` are two ways of **running** the agent, not two ways of showing
it. In `tui` the agent runs as its native TUI under tmux and no ACP driver
exists. In `chat` the agent runs as an ACP server and no agent terminal exists.
Switching is a real transition with a handoff (`ports.AgentInterfaceHandoff`,
`NativeConversationID`), not a view toggle.

Therefore the terminal cannot be fed by ACP, and chat cannot show a raw grid.
Any design that assumes otherwise is incoherent.

|  | `tui` | `chat` |
| --- | --- | --- |
| Harnesses | ~30 | 4 — codex, claude-code, opencode, droid |
| Agent's native UI | full | does not exist |
| Block source | hook events + transcript | native ACP stream |
| Raw grid | **yes**, behind a toggle | nothing to show |
| Interaction | keystrokes to a PTY | steer, rollback, resolve approval, attachments, config |

## Approach

**One screen renders blocks. The session's mode selects the source and the
available actions.** Neither mode is removed.

This is the same shape as Warp's single pane input, which carries an
`InputConfig { input_type, is_locked }` (`app/src/ai/blocklist/input_model.rs`)
deciding what the one input does rather than having two inputs.

### What Warp actually does, verified

Read from `warpdotdev/warp` at `/Users/omaraly/development/AI/warp`. Warp is
AGPL-3.0 (`warp_terminal`); nothing here derives from its source.

**Warp does not render CLI agent sessions as blocks.** This is the finding that
matters most and it corrects earlier drafts. `handle_cli_agent_sessions_event`
(`app/src/workspace/view.rs:3743`) handles `Started`, `StatusChanged`, `Ended`
and `SessionUpdated`, and its whole body is `ctx.notify()`. The OSC 777 plugin
events drive the **tab title, agent icon, right panel, notifications and a status
badge**. Running Claude Code inside Warp shows Claude Code's TUI in the alt
screen, exactly as any terminal would.

So block-listing agent activity is not Warp parity — it **exceeds** Warp. Parity
is a floor here, not a ceiling.

**Warp's real blocks are shell blocks, and they carry real output.** A private
OSC 9278 / DCS channel carries hex-encoded JSON
(`app/assets/bundled/bootstrap/zsh_init_shell.sh`) with a vocabulary defined in
`crates/warp_terminal/src/model/ansi/dcs_hooks.rs`: `Preexec` carries the
command, `CommandFinished` carries the exit code, `PromptMetadata` carries `pwd`,
`git_branch`, `virtual_env`. Warp owns the PTY stream and segments the **actual
bytes** between marks, rendering them through its blockgrid with full ANSI. A
shell block is not a summary of a command; it is the command's output.

**Full-screen TUIs are never blocked.** `app/src/terminal/alt_screen/` suspends
the block list and hands the display to a full-screen element.

**Failure is designed for.** An `Unknown(String)` variant, a schema version in
both the payload (`v`) and the module path (`event/v1.rs`), and the plugin
version recorded per session.

### What paseo does, verified

Read from `getpaseo/paseo` at `/Users/omaraly/development/AI/paseo`, Apache-2.0.
Paseo is a voice-driven front end for local coding agents, and it has shipped the
subsystem this spec's steps 6 through 10 describe. Nothing here derives from its
source; the design decisions below are adopted deliberately and named so a
reviewer can check them against the original.

The comparison is asymmetric and worth stating up front. **Paseo is ACP-only** —
no hooks, no shell blocks, no `tui` mode, and no secret redaction anywhere in its
timeline pipeline (`redact` appears only in `logger.ts` and the diagnostics
report). On redaction, source precedence and grid arbitration this spec is ahead
of it. What paseo is ahead on is everything downstream of "an event arrived":
storage shape, streaming pressure, pagination, and the render split.

- **Canonical rows, projected entries.** An immutable append-only
  `AgentTimelineRow{seq, timestamp, item}`, projected into display entries at read
  time (`timeline-projection.ts`). Adopted below.
- **Stream coalescing** with a leading-edge flush (`agent-stream-coalescer.ts`).
  Adopted below.
- **A real pagination envelope** — `epoch`, `staleCursor`, `gap`, `reset`,
  `hasOlder`, `hasNewer` (`agent-timeline-store-types.ts`). Adopted below.
- **Structured tool detail** rather than a formatted string
  (`ToolCallDetail` in `agent-types.ts`, `tool-call-display.ts`). Adopted below.
- **A history/live render split** and partial virtualization above a threshold
  (`agent-stream/model.ts`, `web-virtualization.ts`). Adopted below.
- **A load-test provider** streaming for five minutes at 40ms
  (`mock-load-test-agent.ts`). Adopted below.
- **Field-level forward compatibility** — `z.enum(...).catch("idle")`
  (`terminal-activity.ts`). Adopted below.

**Not adopted: paseo's bottom-anchor controller.** `bottom-anchor-controller.ts`
is 826 lines — a request queue, retry counts, post-layout verification passes and
four `blockedReason` variants — because one abstraction spans React Native and the
web. Mobile's centre-sliver viewport already has the property that controller
works hardest to guarantee, in roughly forty lines. Its one transferable idea is
kept below.

### Why Operator is most of the way there

`opr hooks <agent> <event>` is Warp's plugin mechanism, and Operator's adapters
install it themselves rather than showing the user manual instructions
(`plugin_manager/mod.rs`, `PluginInstructions`). The body already carries
`Event`, `ToolName`, `ToolUseID`, `AgentSessionID`, `LatestUserPrompt`,
`LatestAssistantUpdate`, `TranscriptPath`, `LaunchID` and usage metadata
(`backend/internal/cli/hooks.go`). `activitydispatch/dispatch.go` registers
derivers for eleven harnesses. `observe/usage/watcher.go` already watches
transcripts with fsnotify and `session_manager/handoff_artifact.go` already
parses them with bounded excerpting.

All of it is currently collapsed to `type ActivityState string`
(`domain/activity.go:7`) and the rich fields are dropped.

### Rejected alternatives

**Scraping the agent's TUI for markers**, extending
`adapters/agent/terminalui/composer.go`. Per-harness rules that break on every
agent release, nothing to segment when the harness takes the alt screen, and
silent degradation — the worst failure mode for a terminal.

**On-device grid diffing**, cutting a block when a repainted region goes stable.
Heuristic and quietly wrong.

**Feeding terminal blocks from ACP.** Incoherent; see the constraint above.

**Building a UI framework.** Warp wrote `warpui` / `warpui_core` and a scroll
engine (`block_list_viewport.rs`) because nothing beneath it had one. Flutter's
list and the browser's scroll container do. The quality comes from owning the
list, not the renderer, and the cost would be rewriting every desktop surface —
kanban board, sidebar, PR review, settings — for one pane.

**Replacing the emulators.** `alacritty_terminal` is a grid model with no
renderer, living in the Tauri Rust host rather than where the UI is; adopting it
means bridging every frame or writing a Rust-side renderer. xterm.js stays on
desktop, xterm.dart on mobile, and both matter only in Raw mode.

## Design

### The block model is shared

One block model, one assembly result, one set of rendering components per client.
Sources adapt **into** it; nothing downstream knows which source produced a block.

A block carries: id, sequence, kind (`prompt`, `assistant`, `tool`, `command`,
`permission`, `notice`), title, body, status (`running`, `ok`, `failed`,
`blocked`), timestamps, and an optional action set the source declares. The
action set is how mode-specific capability reaches the UI without the UI
branching on mode.

**The id is minted at the source, never by a consumer.** Warp takes this
seriously enough to shape the id around it: a pty-derived block's id is
`{WARP_SESSION_ID}-{NUM_ID}` handed over by the shell's precmd, with a monotonic
counter rather than a UUID because minting a UUID in a bootstrap script is
expensive; only app-created blocks get `manual-{uuid}` (`block_id.rs`). The same
rule holds here: hook events carry `ToolUseID`, shell marks carry a session-scoped
counter, and ACP carries its own item ids. A consumer that invents ids cannot
deduplicate on reconnect, cannot correlate a `tool_complete` with its
`prompt_submit`, and cannot let two clients agree on what they are looking at.

**A tool block carries a structured detail, not a formatted string.** The kind
list above says what a block *is*; it does not say what a consumer can render from
it. Paseo's `ToolCallDetail` is a discriminated union — `shell{command, output,
exitCode}`, `read{filePath, content, offset, limit}`, `edit{filePath, oldString,
newString, unifiedDiff}`, `write`, `search`, `fetch` — with an `unknown{input}`
variant carrying the raw payload when nothing matched. One shared pure function,
`buildToolCallDisplayModel()`, turns a detail into `{displayName, summary,
errorText}`.

Adopt both. A `title`/`body` pair pushes formatting into each client, which is the
same duplication this design exists to remove — it would retire chat's duplicate
*components* while leaving duplicate *formatting* behind, and a diff would be
rendered by two hand-written formatters that drift. The `unknown` variant is what
makes this safe: a harness whose tool nobody has mapped still produces a block, it
just shows its raw input. The shared fixtures then assert something stronger than
string equality — both clients must derive the same detail from the same event.

Per-source mapping into the detail union lives with the source adapter, not in the
shared model: hooks map from `ToolName` plus `tool_input`, ACP maps from its own
tool-call content, and shell blocks are always `shell`.

**Mobile.** A new `feature/blocks/` owns the model, assembly, widgets, viewport
and the screen. `feature/chat/` keeps its data layer — SSE, repository, params —
and loses its presentation layer. `feature/terminal/` keeps its data layer and
`TerminalSurface` (the Raw grid) and gains no timeline of its own. Each exposes
an adapter mapping its source into the shared model.

**Desktop.** The same split: shared block components under
`frontend/src/renderer/components/blocks/`, with the existing chat components
reduced to a source adapter. This retires most of the 38 files under
`components/chat/`, which is the point.

**This reverses an earlier decision** in the superseded draft to keep terminal
and chat models separate. That call assumed two screens. With one screen, one
model is the only defensible answer.

### Canonical events, projected blocks

**The persisted log is immutable; blocks are a projection of it.** This is the
storage shape paseo settled on, and adopting it removes a rule this spec
previously needed.

A canonical row is `{seq, timestamp, event}` and is never mutated after it is
appended. Blocks are derived by projecting a window of rows: consecutive assistant
text merges into one block, a tool's open/complete pair collapses into one block,
and a transcript record merges into the block its hook event opened. A projected
block records what it was built from — the source `seq` ranges, and which
collapses were applied — following `TimelineProjectionEntry{sourceSeqRanges,
collapsed}`.

Three things follow, and each is a bug avoided:

- **Pagination is over `seq`, not over blocks.** A block's identity can change as
  more events arrive; a sequence number cannot. Paging a window of mutable objects
  is where "scroll back and the list reshuffles" comes from.
- **Refetch is deterministic.** Replaying rows `n..m` produces exactly the blocks
  a live client assembled from the same rows, so a reconnect cannot diverge from a
  session that never dropped. Mutation-in-place gives that guarantee only if every
  mutation is itself replayed in order.
- **Provenance survives.** "Which events produced this block" is answerable, which
  is the difference between debugging assembly and guessing at it.

Assembly on both clients is therefore a **pure function from a row window to
blocks**, which is also what makes the shared fixture contract enforceable: a
fixture is a row list, and the expectation is a block list.

### Secret redaction

`crates/warp_terminal/src/model/secrets.rs` scans block content with regex DFAs
and marks `SecretRange` spans for redaction, with separate enterprise and user
pattern levels.

**This matters more here than it does for Warp.** Warp's blocks stay on the
machine that produced them. Operator's blocks are serialized and pushed over a
WebSocket to a phone, persisted in sqlite, and rendered on a device that may be
lost or shoulder-surfed. A block built from `tool_input` or shell output can
contain an API key, a token in a URL, or an environment dump.

Requirements:

- Redaction happens **daemon-side, before a block is persisted or transmitted**.
  Redacting in the client would mean the secret already crossed the network and
  already sits in the sqlite log.
- Spans are marked rather than deleted, so the UI can show that something was
  redacted instead of silently altering output — an invisible redaction is its own
  bug when someone is debugging.
- A default pattern set, extensible by the user. No enterprise tier here.
- Redaction is asserted by tests over known-secret fixtures, and the failure mode
  is to redact too much rather than too little.

This applies to every source: hook payloads, transcript excerpts, shell block
bytes, and ACP content.

### Backend

**Agent event capture.** A new `agentevent` package retains hook payloads instead
of collapsing them: session id, monotonic sequence, event name, tool name, tool
use id, tool input preview, text, error type, harness, hook schema version,
timestamp. `ActivityState` derivation is unchanged and runs off the same
callback, so existing status behaviour is untouched.

**Vocabulary.** Warp's names as the normalized set — `session_start`,
`prompt_submit`, `tool_complete`, `stop`, `stop_failure`, `permission_request`,
`permission_replied`, `question_asked`, `idle_prompt` — with an explicit unknown
variant carrying the raw name through. Per-harness derivers register alongside
the existing activity derivers.

**Persistence and paging.** Canonical rows are appended to a bounded per-session
log in sqlite so a client joining mid-session gets history, with bounds following
`handoff_artifact.go`.

Reads take a direction and a cursor and return an envelope, following
`AgentTimelineFetchOptions` / `AgentTimelineFetchResult`:

- direction `tail | before | after`, a cursor of `{epoch, seq}`, and a limit;
- the reply carries `epoch`, `window{minSeq, maxSeq, nextSeq}`, `hasOlder`,
  `hasNewer`, and three flags the client must branch on — `staleCursor`, `gap`,
  and `reset`.

**The `epoch` is the part that is easy to skip and expensive to omit.** A bare
sequence number is only meaningful within one numbering; a session restart, a
rollback, or a log trim renumbers or truncates, and a client holding a pre-trim
cursor then asks for rows that no longer mean what it thinks. The epoch makes that
detectable in one comparison instead of surfacing as blocks that quietly do not
line up. `staleCursor` and `gap` are what let the client choose between "fetch the
missing span" and "drop the window and re-tail" rather than guessing.

Operator has an existing renumbering trigger the spec must respect: rollback
(`/api/v1/sessions/{sessionId}/rollback`). A rollback bumps the epoch.

**Transport.** A `blocks` channel on the existing `/mux` socket, alongside
`terminal`, `subscribe`, `sessions` and `system`. Named for what it carries, not
its first source, because shell marks are republished onto it too.

**Coalescing, daemon-side.** A streaming turn produces events far faster than any
list can usefully repaint, and doing nothing about it makes both clients pay —
which is why this belongs on the daemon rather than in each viewport. Paseo's
`AgentStreamCoalescer` is the shape to copy, at a 60ms window:

- **Leading edge**: the first event after an idle window flushes synchronously, so
  the first token of a turn is never delayed by a full window. Delaying it is
  exactly the latency users read as "the agent is stuck".
- **Trailing timer** for sustained bursts, capping the message rate at one per
  window.
- **Terminal states bypass the window entirely** — a tool call reaching
  `completed`, `failed` or `canceled` flushes at once, because a status change is
  the event a waiting user is actually watching for.
- Coalescing merges **text within one stream** (same item id) and merges repeated
  updates to **one tool call**; it never merges across block boundaries.

Coalescing is a transport concern and must not touch the canonical log: every
event is still appended individually and `seq` is still per event. What coalesces
is what goes on the wire.

**Source precedence.** In `tui` mode two sources describe the same session: hook
events, which arrive first and are truncated, and transcript records, which arrive
later and are complete. A precedence rule is required, not optional. Warp faces
the same shape and handles it explicitly: its per-agent handler takes a
`plugin_already_active` flag so that Codex's cruder OSC 9 fallback is **dropped
once the rich OSC 777 plugin is live** (`cli_agent_sessions/listener/mod.rs`).

The rule here, stated as projection rather than mutation: hook events and
transcript records are both appended as canonical rows, and the projection merges
rows sharing an id into one block. Within that merge, the transcript record wins
on **body** and the hook event wins on **status**, because the transcript does not
describe blocking or permission state. A transcript record with no matching hook
event projects to its own block. Nothing is overwritten in storage, so a
projection bug is a bug in one pure function rather than a corrupted log.

**Per-harness handlers, not just parsers.** Warp's `CLIAgentSessionHandler` can
parse, filter and transform per agent, not merely rename events. Operator's
derivers are parse-only today; the same seam is needed so a harness that emits a
duplicate or a useless event can drop it at its own boundary rather than
polluting the shared vocabulary.

**Transcript enrichment.** `TranscriptPath` plus the existing `TranscriptWatcher`
supplies what hook payloads truncate — full assistant text, full tool results,
diffs. Per-harness parsers added one at a time. This is what narrows the fidelity
gap between `tui` blocks and `chat` blocks, and it is the difference between a
block list that summarizes and one that shows the work.

**Shell blocks.** A bootstrap injected into the shell emits marks at prompt,
command start, and command end with exit code — the role of Warp's `Preexec`,
`Precmd`, `CommandFinished`. `service/shellterm/loginshell.go` returns a bare
`[$SHELL]` argv today, so this adds the injection point. Bash, zsh and fish;
an unrecognized shell gets no marks and stays Raw, visibly.

Marks arrive **in-band** on the PTY, unlike `opr hooks`. The daemon parses them
out of the terminal stream and republishes on the `blocks` channel, so clients
consume one uniform stream and never learn two mechanisms produced it. Parsing
server-side also keeps marks from reaching a client's emulator as stray output.

**A shell block carries the real bytes between its marks**, not a description of
them. Anything less is not what Warp does and not worth building.

### Raw grid

Kept, in `tui` mode, reachable by a toggle, unchanged. It is the only way to see
the agent's real interface, the only fallback for harnesses with no hook
coverage, and the only correct answer for a full-screen TUI. `chat` mode has no
raw grid because there is no agent terminal to show.

**Grid arbitration.** In Blocks the client does not join the terminal channel, so
it reports no size and appears in no `members` map. One consequence needs a test:
if the desktop is in Blocks and a phone is in Raw, the phone becomes the sole
sizer and the grid follows it. That is correct — the only client rendering a grid
should choose it — but it inverts today's behaviour.

### Viewport

The parity bar, and the largest single piece. `block_list_viewport.rs` maintains
a `sum_tree` of block heights (`BlockHeightItem`, `BlockHeightSummary`) with
approximate comparisons (`heights_approx_gt`, `HEIGHT_FUDGE_FACTOR_LINES`)
purely to keep scroll correct over a virtualized list of variable-height blocks.
That problem exists in a browser and in Flutter too. An earlier draft claimed
desktop scrolling came free from the DOM; that holds for a short list and fails
for a real session.

Required on both clients:

- **Virtualization.** Thousands of blocks. Rendering all destroys scroll;
  rendering a window requires knowing the heights of what is not rendered.
- **A measured-height cache.** Estimates corrected on measurement with scroll
  position preserved across the correction. Getting this wrong produces the
  drifting scrollbar that makes virtualized lists feel broken.
- **Append anchoring.** Pinned to the bottom, the view follows; scrolled up, the
  view does not move when content arrives below.
- **Sticky block headers**, disabled when the block is taller than the viewport
  (`block_list_element.rs:135`) — without the exception a tall block traps its
  own header.
- **Block-boundary navigation**, and scroll-a-block-into-view.
- **Selection and find across blocks** (`app/src/terminal/find/`).

**Virtualize above a threshold, not always.** Paseo mounts everything until the
list passes `DEFAULT_WEB_PARTIAL_VIRTUALIZATION_THRESHOLD = 100` items and only
then splits. Adopt the threshold. Virtualization buys nothing on a short session
and costs measurement error, height-estimate drift and a class of scroll bugs that
only exist because rows are unmounted — and most sessions are short. Unconditional
virtualization means every session pays a long session's price.

**Split the live tail from the frozen history.** Paseo's
`StreamRenderSegments{historyVirtualized, historyMounted, liveHead}` is the
structural answer to render pressure, and it composes with coalescing rather than
duplicating it: only the actively-streaming tail stays mounted and re-renders as
tokens arrive; everything above it is virtualized and re-renders only when an
explicit revision key changes (`historyRowRevision` — content, per-row display
state, and a global). The middle `historyMounted` band exists so that scrolling
just off the tail does not immediately cross a virtualization boundary.

This is what makes "the list does not re-render during scroll" a structural
property rather than a profiling result. Without it, a single streaming block at
the bottom invalidates the whole list on every frame and no amount of memoization
in leaf components recovers it.

**Own the resize-compensation decision.** The one idea worth taking from paseo's
bottom-anchor work is that the "should a re-measured row shift the scroll offset?"
question is a **pure function** with named inputs, not behaviour buried in a
library — `shouldAdjustScrollForVirtualRowResize({isHistoryStartPrependActive,
rowStart, scrollOffset, remainingDistanceFromBottom, bottomThreshold})`. Two of
its rules matter here: compensation is suppressed entirely while a prepend is in
flight, and it is suppressed when the reader is near the bottom, where following
is the correct behaviour anyway. Making this ours makes it testable and changeable
rather than something the spec can only document as a limitation.

**Height estimates are per-kind and cached by content.** A single estimate for all
blocks guarantees drift. Paseo estimates per item kind — a collapsed tool row at
~40px, a user message at 96 (220 with images), an assistant message from a
content-keyed cache — which is what keeps the scrollbar honest before measurement
lands.

**Block actions**: copy command, copy output, re-run, collapse, and filter the
list (`block_filter.rs` supports a query with configurable context lines). Warp's
block sharing (`share_block_modal.rs`) is a cloud feature with no analogue here
and is not adopted.

**Not adopted: GPU text rendering.** Warp rasterizes glyphs because nothing
beneath it composited. Both our platforms composite. The same smoothness is
available provided the list does not re-render during scroll — a profiling
obligation, and the item most likely to separate parity from nearly-parity.

### Input

**Blocks are output only.** One composer per screen, as in Warp. In `tui` it
sends keystrokes through the existing route (`send_route.dart` on mobile); in
`chat` it sends structured messages. No per-block input field on either client.

### Permission requests

**Rich and notifying, not actionable** — Phase A, both clients, both modes. A
permission request becomes a block naming the tool and its input, with the
session shown blocked. In `tui` acting on it means switching to Raw.

Warp does the same: `cli_agent_sessions/mod.rs` maps `PermissionRequest` to
`Blocked { message: summary }` and clears it on `PermissionReplied`.

Phase A changes nothing about `opr hooks` stdout, so the deliberate guarantee in
`claudecode/hooks.go:34` — that installing the hook never injects a permission
decision — is preserved exactly.

**Permanently rejected: synthesizing keystrokes.** Option ordering and labels are
TUI surface; `claudecode.go:90` already records that a permission-menu selection
is rejected by the empty-composer check gating the guarded send loop. Do not
defeat that guard, in this phase or any later one.

**Phase B is deferred by explicit decision, 2026-08-27.** Nothing in Phase A lays
groundwork for it: no hook blocks and no decision travels. Recorded so it is not
lost — `opr hooks` would block on a decision routed from the daemon, and blocks
would gain approve and deny. It would have to be off by default, live in project
settings only, time out by **falling through to the agent's own prompt** rather
than allowing or denying, and show the wait on both clients. Intended reach is
Claude Code and Codex, with two checks that gate Codex: whether it reads a
decision from hook stdout at all, which nothing in this repo establishes, and
whether `codexHookTimeout` can move off its deliberate 5-second cap
(`codex/hooks.go`) — five seconds cannot cover a human answering on a phone, and
raising it reopens the stall that cap guards against.

Note that `chat` mode already resolves approvals structurally
(`resolve_approval_params.dart`). Phase B is only about closing that gap for
`tui`.

### Error handling

- A harness with no deriver produces no events; the session opens in Raw and the
  toggle says blocks are unavailable for that harness. Absence is visible, never
  a silently empty list.
- An unknown event name is retained and rendered as a generic block, so a harness
  update degrades to less detail rather than a gap.
- A hook schema version newer than the daemon understands is recorded and
  surfaced; known fields still parse.
- A dropped socket refetches the persisted log by cursor, and branches on the
  envelope: `staleCursor` or a changed `epoch` means drop the window and re-tail,
  `gap` means fetch the missing span before rendering across it. Silently
  rendering across a gap is how a timeline acquires missing turns nobody notices.
- **A field whose value the client does not recognize degrades that field, not the
  payload.** Paseo does this at the parse layer — `z.enum(STATES).catch("idle")` —
  so a newer daemon sending an unknown status yields a block with a conservative
  status rather than a dropped message. The spec already handles unknown *event
  names*; this is the same rule one level down, for enum values inside events the
  client does know. The conservative fallback must never be an alarming one: an
  unknown status degrades to the quiet value, never to `failed`.
- **Backward paging cannot retry forever.** A load request that is issued and never
  observed must latch rather than re-fire on every scroll event; paseo's
  `dormant → ready → loading → settling → latched` state machine
  (`history-start-pagination.ts`) exists for exactly this, and the `settling` state
  exists because the frame after a prepend is not yet a valid place to decide
  whether to prepend again.
- Malformed payloads go to the existing `hooks.log` sink and are skipped.
- A shell whose output contains something resembling a mark must not produce a
  spurious block boundary.

**Unbounded output.** A single command can emit hundreds of megabytes. Warp caps
a block's lines and splices a visible marker into the middle rather than dropping
the tail silently — `TRUNCATION_MESSAGE = "\n...(truncated)...\n"`, with
`num_lines_truncated()` kept so the count is known (`blockgrid.rs:495`). The same
applies here, at both ends of the wire: the daemon caps what it persists and
transmits, and the block records how much was dropped so the UI can say so and
offer Raw for the rest.

**Memory.** Warp tracks block memory explicitly
(`estimated_memory_usage_bytes()`, `blockgrid.rs:685`, backed by the `get-size`
crate). A long session on a phone is the constrained case here, so the client
holds a bounded window of blocks and pages older ones back from the persisted log
by sequence. Assembly must therefore work on a window, not on the whole history.

**Stuck states.** The event vocabulary will always be incomplete: an agent that
is killed, crashes, or is interrupted may never emit `stop`, leaving a block
`running` forever. Warp solves the interrupt case by inference — it watches for a
synthesized Ctrl-C write and arms a grace window (`CTRL_C_CANCEL_WINDOW`, two
seconds) after which the session resolves to `Cancelled` unless disarming
activity arrives; a second Ctrl-C reuses the window rather than resetting the
clock. Its distinction is worth copying exactly: **`IdlePrompt` does not disarm,
because idleness is evidence of idleness, not of aliveness.**

The rule here: a block left `running` when its session's process exits resolves
to `failed` with a stated reason, and any block whose session is gone is never
left spinning. Whether to add Warp's Ctrl-C inference is a judgement for
implementation; the invariant that no block spins forever is not.

### Testing

**Backend.** Table tests per deriver mapping native hook names onto the
normalized vocabulary including the unknown case; persistence bounds; mux frame
encoding; shell mark parsing per shell, including output that mimics a mark.
Redaction over known-secret fixtures, asserted **before** persistence and
transmission, not after. Source precedence: a transcript record replaces a hook
body without creating a second block. Truncation preserves the recorded dropped
count. No block remains `running` once its session's process is gone.

**Shared fixtures.** Block assembly exists twice, in Dart and TypeScript. One set
of event-stream fixtures lives in the repo and both suites assert against it, so
a behaviour added on one client without the other is a failing test rather than
silent drift. Both source adapters — hooks and ACP — are asserted to produce the
same block model from equivalent input.

**Mobile.** Unit tests for assembly (correlation by `ToolUseID`, out-of-order
arrival, unknown events, truncation); widget tests per block state; a test
pinning that Blocks does not join the terminal channel. `flutter analyze` clean
and `flutter test` green are the gate.

**Desktop.** Unit tests for the mux client's `blocks` channel and for assembly.
`npm run frontend:typecheck` and `npm test` are the gate.

**Viewport, both clients.** Height estimation and correction with scroll position
preserved; append anchoring at the bottom and while scrolled up; the
sticky-header exception for a block taller than the viewport; the
resize-compensation predicate and the paging state machine as pure-function unit
tests. These decide whether scrolling feels right, so they are pinned rather than
eyeballed.

**A load-generating source, in the product.** "Frame-time profiling under a
synthetic long session" is not a testable instruction. Paseo made it one by
registering `mock-load-test-agent.ts` as a real provider that streams for five
minutes at 40ms intervals — selectable in the UI, drivable from e2e, and
reproducible by hand. Build the equivalent: a source that replays a fixture stream
at a configurable rate onto the `blocks` channel. It is the same fixture format the
shared contract already requires, so the cost is a replayer, not a second corpus.

**Browser e2e is where the viewport is actually testable**, and jsdom is not. The
suite exists — 18 specs under `frontend/e2e/`, run by the separate gate
`npm --prefix frontend run test:e2e` — and blocks must reach it. Two mechanics make
that practical, both borrowed: a **test-only global overriding the virtualization
threshold** (paseo's `__PASEO_E2E_WEB_PARTIAL_VIRTUALIZATION_THRESHOLD`) so a
twelve-block fixture exercises the virtualized path, and a fake `blocks` socket, so
no production code branches on being under test. Append anchoring, prepend
stability and the sticky-header exception are asserted there against a real layout
engine; the jsdom tests keep their value as fast checks of the numeric model.

Native code is covered by none of these gates; nothing here touches `ios/`,
`android/`, or a vendored package's platform code.

## Does this fix the problems?

**Mobile: yes, by construction.** A block list has no columns and no rows. It
reflows to the phone's width at whatever type size the skin specifies. There is
no grid to arbitrate, and in Blocks the phone reports no size at all, so the two
clients stop competing even in the transient case where the phone attaches first.
Both clients are good simultaneously because they no longer render the same
artifact.

**Desktop: parity, item by item.** Scrolling matches Warp's because the
requirements are matched individually rather than assumed free. Agent turns and
shell commands both become blocks that scroll, collapse, copy, filter and search.
On agent sessions this exceeds Warp, which shows a TUI and a status badge.

**Duplication: removed before it exists.** One block model, one set of components
per client, two adapters. Chat's presentation layer retires rather than being
mirrored.

Limits, so this is not oversold:

- **`tui` blocks are what the agent reported, not its screen.** Transcript
  enrichment narrows this a great deal; it does not close it. Spinners, live
  counters and the agent's own layout appear only in Raw.
- **Harnesses without hooks get no blocks in `tui`.** Eleven are registered. The
  rest stay Raw and say so.
- **Shells outside bash, zsh and fish get no marks** and stay Raw.
- **Raw mode is unchanged and unimprovable.** A full-screen TUI owns the screen
  and keeps no scrollback. The three existing paths — local buffer, SGR reports
  to tmux copy-mode, page keys for keyboard-scroll harnesses — remain correct on
  both clients. Warp has the identical limitation in its alt-screen element,
  which is the proof that no renderer or emulator choice removes it.
- **Desktop scroll preservation is narrower than "preserved across the
  correction" suggests.** Established while implementing plan 4b, against
  `@tanstack/virtual-core` 3.17.7. A block re-measured taller only has the scroll
  position compensated when it sits **entirely above the viewport top** and the
  viewport has **settled**. Two cases are deliberately uncompensated upstream: a
  block that merely *spans* the top edge — the long tool output you are reading
  the middle of — because compensating would drag the view down on every token;
  and any growth while the user is still dragging upward, which upstream skips to
  avoid an items-jump cascade (their issue #1218). Both are correct choices, and
  neither is a defect in this design; they are simply not what the requirement
  above promises. Lifting the decision into an owned predicate, per the viewport
  section, is what turns this from a documented limitation into a choice.
  **Mobile has neither limit** — a centre-sliver viewport leaves the read position
  exactly unchanged when a block above it grows, with no compensation logic
  involved, which is pinned by a test.
- **The chat migration is real work.** ~38 desktop components and a large mobile
  presentation layer are retired or rewritten. This is cheap now and expensive
  after both block views exist, which is the argument for doing it in this order.
- **Unverified against a running system.** The design is reasoning from source,
  and plans 1 through 4 are pinned by unit, widget and component tests only.
  Nothing here has been exercised against a live daemon, from a phone, or from
  the desktop app. The desktop's browser e2e suite (`frontend/e2e/`) is the one
  place a real layout engine would test the viewport, and it does not yet cover
  blocks.

## Sequencing

1. Backend agent-event capture, vocabulary and persistence. No UI change.
2. `blocks` channel on the mux and in both mux clients. Shared fixtures land here.
3. Shared block model and assembly, both clients, with the hook adapter.
4. **Mobile** block screen and the Raw toggle, defaulting off, then on. Mobile
   leads: its problem is urgent and its list is simpler.
5. **Desktop** block screen behind the toggle.
6. **Viewport** on both: virtualization, height cache, append anchoring, sticky
   headers, block navigation. Separate from 4 and 5 so blocks are correct before
   they are fast.
7. **ACP adapter**, so `chat` sessions render through the same screen. Chat's
   presentation layer retires here.
8. Cross-block selection, find, and block actions.
9. **Shell blocks**: bootstrap injection, daemon-side mark parsing.
10. Transcript enrichment, per harness.
11. (Deferred) Actionable permissions, as its own spec.

Steps 1 through 4 fix mobile and are the shortest path to a usable phone. Steps 5
and 6 are desktop parity. Step 7 is where the duplication actually dies, and
delaying it past step 8 would mean building block actions twice.

**Two additions from the 2026-08-28 paseo review sit outside this numbering**, so
that the step numbers the plans already reference keep meaning what they meant.
The canonical/projected storage change and the `epoch`/cursor fetch envelope
extend step 1 and must land before step 7, since step 7 adds the second source and
would otherwise be built against the mutation rule they replace. Daemon-side
coalescing extends step 2 and is cheapest before either client is tuned; it is the
one item here that improves both clients without touching either.

**Honest cost.** Steps 6, 7, 8 and 9 are each larger than the original
agent-blocks work. If the bar has to move, cut from the end: 9, then 8. Cutting 7
is not a saving — it re-creates the duplication this design exists to prevent.

## Implementation plans

This spec is delivered as **eight plans**, each producing working, testable
software on its own. Plans live in `docs/superpowers/plans/`.

| # | Plan | Spec steps | File | Status |
| --- | --- | --- | --- | --- |
| 1 | Backend block pipeline | 1, 2 (daemon), fixtures | `2026-08-27-block-pipeline-backend.md` | written |
| 2 | Mobile block screen | 2 (mobile mux), 3, 4 | `2026-08-27-mobile-block-screen.md` | written |
| 3 | Desktop block screen | 2 (desktop mux), 3, 5 | `2026-08-27-desktop-block-screen.md` | written |
| 4a | Viewport, mobile | 6 | `2026-08-27-mobile-block-viewport.md` | written |
| 4b | Viewport, desktop | 6 | `2026-08-27-desktop-block-viewport.md` | written |
| 5 | ACP adapter, chat presentation retires | 7 | — | |
| 6 | Block actions, selection, find | 8 | — | |
| 7 | Shell blocks | 9 | — | |
| 8 | Transcript enrichment | 10 | — | |

Step 11, actionable permissions, is deferred Phase B. It gets its own spec before
it gets a plan and is not counted here.

### Amendments from the paseo review, 2026-08-28

Seven changes were folded into this spec after reading `getpaseo/paseo`, which has
shipped steps 6 through 10 in production. They are listed here against the plans
they affect, because four plans have already landed and a reviewer needs to know
which of those are now behind the spec.

| Change | Where | Plans affected |
| --- | --- | --- |
| Canonical rows, projected blocks | *Canonical events, projected blocks*; *Source precedence* | 1 (additive), 5, 8 |
| Daemon-side coalescing, leading-edge | *Backend / Coalescing* | new, before 5 |
| `epoch`/cursor fetch envelope | *Backend / Persistence and paging* | 1 (additive), 2, 3 |
| Structured `ToolCallDetail` + shared display model | *The block model is shared* | 5, 8 |
| History/live split, threshold virtualization | *Viewport* | 4a, 4b |
| Load-generating source + browser e2e | *Testing* | 4b, then 6 |
| Field-level enum degradation | *Error handling* | 2, 3 |

**None of it invalidates landed work.** Plans 1 through 4 shipped a per-event log,
a `blocks` mux channel, client assembly and two viewports; every change above is an
addition to those or a refinement of behaviour inside them. The canonical/projected
change is the one to make before plan 5, because plan 5 introduces the second
source and the mutation rule it replaces would be load-bearing from then on.

**What paseo does not answer.** Redaction, hook/transcript precedence, shell marks
and grid arbitration have no analogue there — paseo is ACP-only. Those sections
stand on their own reasoning and were not revised.

**Dependencies.** Plan 1 blocks everything. Plans 2 and 3 both depend on 1 and are
independent of each other. Plan 4 depends on whichever client plan it targets.
Plans 5 through 8 depend on 2 and 3.

**Plans 1 and 2 together fix mobile.** Everything after is desktop parity and
depth, and can be re-ordered or cut — except plan 5. Cutting 5 leaves chat's
presentation layer alive beside the block screen, which is the duplication this
design exists to remove, and its cost grows with every block feature that lands
first.

**Plan 4 split, as anticipated.** Mobile and desktop viewports share no code — a
Flutter list versus DOM virtualization — only a requirements list, so it is
written as 4a and 4b. They are independent of each other and either may run
first; both depend only on plans 1-3.

### Writing the remaining plans

These plans are executed by an agent with no prior context, so a plan that says
"read the existing helper and follow it" fails. Quote the real thing.

**Verification gates, by area.** Every plan's steps must run the gate for the
code they touch:

- Backend: `npm run lint` from the repo root (runs `go test ./...` plus
  golangci-lint v2.12.2). During a task, `cd backend && go test ./internal/<pkg>/ -v`.
- Mobile: `flutter analyze` (must print "No issues found!") and `flutter test`,
  both from `packages/mobile`.
- Desktop: `npm run frontend:typecheck` from the root, and
  `npm --prefix frontend run test` (vitest). There is no root alias for the test
  script.
- Anything touching `queries/` or `migrations/`: `npm run sqlc`, and never edit
  `backend/internal/storage/sqlite/gen/` by hand.
- Anything changing the REST surface: `npm run api`, which regenerates the
  OpenAPI spec and the frontend's TypeScript types.

**Test harnesses that already exist.** Name the file and line, quote the helper,
and say not to write a second one:

- Sqlite stores: `newTestStore(t)` at
  `backend/internal/storage/sqlite/store/store_test.go:18`, wrapping
  `sqlitetest.MustOpen(t)` — a fully migrated isolated store with cleanup
  registered.
- HTTP controllers: build a server with
  `httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{...}, httpd.ControlDeps{}))`,
  and issue requests with `doRequest` at
  `backend/internal/httpd/controllers/projects_test.go:522`, signature
  `(t *testing.T, srv *httptest.Server, method, path, body string) ([]byte, int, http.Header)`.
  See `sessions_activity_test.go` for the pattern.
- Mux manager: `newFakeConn()` (no arguments) and
  `recv(t, c, ch, typ string, d time.Duration) serverMsg`, both in
  `backend/internal/terminal/manager_test.go`. Drive a connection with
  `go m.Serve(ctx, conn)` then `conn.in <- clientMsg{...}`. `Serve` reads on its
  own goroutine, so anything published immediately after a subscribe frame races —
  poll for the subscription before asserting.
- Mobile terminal: `packages/mobile/test/feature/terminal/terminal_harness.dart`.

**Conventions a plan must not violate.** These come from `CLAUDE.md` and
`AGENTS.md` and are not negotiable in review:

- Mobile: Cubit only, never `Bloc` with events. No `freezed`, `json_serializable`,
  `drift` or `build_runner` in first-party code — models are hand-written with all
  fields nullable. Static-only classes are `sealed class X`. One params class per
  method under `data/model/params/`, never shared. Parameterized paths get static
  methods on `EndPoints`; interpolating at a call site is forbidden. Feature code
  never imports `flutter_screenutil`. User-facing copy is inline English.
  Navigation is `Navigator.of(context)` with `RoutesStrings` names.
- Mobile theming: `AppSkin` through `context.skin`, type as
  `AppTextStyle.style<Size><Weight>` and the parallel `mono*` set.
- Desktop: build from shadcn primitives in `components/ui/*` where one fits, and
  follow agent-orchestrator's visual language with the refined-blue accent per
  `DESIGN.md`. The terminal palette carve-out applies to Raw mode only.
- Global: no code comments unless the surrounding file already comments heavily.
- App state resolves under `~/.operator` only.

**Two mobile behaviours that look like inefficiencies and must not be
"optimized"**, both documented in `CLAUDE.md`: the 12-second Dio timeouts, and the
sequential auth probing in `sessions_remote_data_source.dart`.

**The shared fixture contract.** `testdata/blocks/` holds the event-stream
fixtures both clients assert against. A plan that adds block-assembly behaviour on
one client adds the fixture and the other client's assertion in the same plan. A
failing fixture is never fixed by editing the fixture.

**Plan 1 is the reference for depth.** It names every file and line it touches,
quotes every helper it uses, spells out every signature its neighbours depend on
in an `Interfaces` block, and predicts where generated code will disagree with the
plan's guesses. Match that level. A step that describes what to do without showing
how is a plan failure, not a shortcut.

## Open questions

- Whether Blocks becomes the default on desktop once parity lands, or stays
  opt-in while Raw remains familiar.
- Whether the merged screen keeps two entry points in navigation, or one entry
  whose content follows the session's mode.
