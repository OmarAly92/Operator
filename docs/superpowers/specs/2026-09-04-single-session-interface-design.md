# One session kind, two client views

Status: Phase 1 implemented; Phases 2–4 unimplemented
Date: 2026-09-04
Scope: `backend/internal`, `frontend/src/renderer`, `packages/mobile`
Supersedes: the dual-mode session model established by
[`2026-08-27-session-blocks-design.md`](2026-08-27-session-blocks-design.md), which
kept both modes alive and decided the block source per session. That spec's Step 10,
transcript enrichment, is delivered here as Phase 2.

A session no longer chooses an interface. Every session is a TUI agent in a pty.
**Desktop is the terminal, always.** **Mobile is the blocks view by default**, with a
device-local toggle to the raw terminal. Nothing about a session records which surface
anyone picked.

The bar for this design is **the best experience the one-process constraint allows**,
not the cheapest one that removes the question. Concretely: the phone sees everything
the agent says and does, at the fidelity chat mode had; every action the phone can
take is deterministic where the terminal makes that possible and honest about being
observed rather than acknowledged where it does not; and the desktop is the agent's
own TUI with nothing layered over it.

## Why

Operator asks the user, at spawn, whether a session is `chat` or `tui`. That question
is unwanted and, on reflection, unanswerable by the person being asked: it is not a
view preference, it is a choice of *which process runs the agent*.

- `tui`: the provider's CLI runs in a pty. The terminal is the agent.
- `chat`: `claude-agent-acp` runs headless over JSON-RPC. The terminal, if opened, is
  a plain worktree shell — never a second copy of the agent.

Both surfaces are views over one durable conversation. For Claude Code they share the
native session UUID (`--session-id claudeSessionUUID(cfg.SessionID)`,
[`claudecode.go:183`](../../../backend/internal/adapters/agent/claudecode/claudecode.go)),
the JSONL transcript under `<CLAUDE_CONFIG_DIR|~/.claude>/projects/<key>/<uuid>.jsonl`,
the config dir, and the worktree. `NativeConversationID` states it directly: *"Both use
the same native Claude session UUID."*

What they cannot share is the **live process**. The transcript is append-only state
with exactly one writer; `claude --resume` reads it once at startup and never tails it.
Two processes on one UUID diverge immediately and interleave their writes. This is the
invariant [`sessionmode.go`](../../../backend/internal/domain/sessionmode.go) exists to
protect, and it is a property of the provider, not of Operator.

Therefore "the native TUI on desktop" and "full ACP on mobile" cannot both hold for one
conversation. One surface must be the real one. **We choose the TUI**, because the
desktop terminal is the product's centre of gravity and because the TUI leaves two
read-only channels — its hooks and its transcript — that together carry everything a
phone client needs to *see*.

### Control is exclusive; observation is not

The one-writer invariant is about who drives the conversation. It says nothing about
who reads it. A TUI session exposes three channels, and this design uses all of them:

| channel | direction | carries | latency |
|---|---|---|---|
| hooks (`opr hooks`) | agent → daemon | lifecycle: prompt submitted, tool started/finished, permission pending, stop, notifications | immediate |
| transcript (JSONL) | agent → disk → daemon | content: every assistant message, thinking, tool input and result, question options, model | per content block, not per token |
| pty | daemon → agent | keystrokes: text, Enter, Esc, dialog answers | immediate, unacknowledged |

Hooks are the **status** source and the transcript is the **body** source. The
[blocks spec](2026-08-27-session-blocks-design.md) already states the merge rule —
transcript wins on body, hook wins on status — and already names transcript records
as the TUI block source alongside hooks. It was never built. Phase 2 builds it, for
the two harnesses that matter: **Claude Code and Codex**.

### What this gives up, permanently

These are ACP-protocol facts that neither hooks nor the transcript expose, and they
go away for good:

- rewind / rollback to a turn (`POST /conversation/turns/{id}/rollback`)
- editing a past message (`.../edit`)
- branch / fork (`.../branches/{id}/activate`)
- elicitation forms and consented URL interactions (`.../inputs/{id}/resolve`)
- native image content in a prompt (attachments degrade to a worktree path)
- token-level streaming: the transcript is written when a content block completes
- a real turn protocol: every phone action becomes keystrokes into a pty, and
  delivery is confirmed by watching what the agent does next, not acknowledged

Only three harnesses have block mappers — `claude-code`, `grok`, `codex` — and Phase 2
parses the Claude Code and Codex transcripts. `grok` is deferred (see
[`todo_without_tmux.md`](../../../todo_without_tmux.md) §15). Every other harness
contributes hook blocks at best and nothing at worst, so on mobile they are
raw-terminal or thin. That is a regression for the four ACP harnesses (`opencode` and
`droid` lose chat entirely) and no change for the other twenty. **This makes mobile a
Claude Code and Codex feature in practice.** That is a product boundary this design
accepts, not a risk it hopes to avoid.

## Target state

One kind of session. `SessionMode` does not exist. `POST /api/v1/sessions` does not
accept `mode`. There is no daemon-wide default interface, no interface-transition
coordinator, and no per-session record of any surface choice.

| | surface | toggle |
|---|---|---|
| desktop | raw pty | none |
| mobile | blocks by default | to raw pty, per session, device-local |

**Desktop has no blocks view.** The agent's own TUI is the product on the desktop, and
nothing is layered over it. `TuiSessionBlocksPane` and the hook-derived block list it
renders are unreachable today (`SessionView` reaches `SessionBlocksPane` only when
`mode === "chat"`), and the blocks spec's status note already says "either that path
comes back or it is deleted". It is deleted in Phase 1.

**Mobile's toggle already exists and works.**
[`SessionViewCubit`](../../../packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart)
switches raw/blocks and `defaultViewMode` already picks blocks for a covered harness
and raw for a shell-only target. The user's choice is persisted per session in
`shared_preferences` and never leaves the device.

A message sent from mobile reaches the agent through `POST /sessions/{id}/send`, which
types into the pty. The desktop terminal shows it, and the agent working, because it
is literally the same terminal. While a permission dialog is pending, `send` is refused
with a 409 (`ErrAwaitingDecision`) so a paste can never answer the dialog by accident;
Phase 3 adds the one write that is allowed to.

### What the phone sees, after Phase 2

| block | source | today (hooks only) | after Phase 2 |
|---|---|---|---|
| user prompt | hook `prompt_submit` | ✓ | ✓ |
| assistant text | transcript | last message per turn, at Stop | every message, as each completes |
| reasoning | transcript | — | ✓, collapsed with a one-line preview |
| tool call | hook + transcript | name + input preview (Claude Code); nothing (Codex) | full input, both harnesses |
| tool result | transcript | — | ✓, inside the tool block |
| todo list | transcript | — | ✓, when the harness uses a todo tool |
| question | hook + transcript | "Waiting on you" | the question and its options, answerable |
| permission | hook `permission-request` | ✓ | ✓, answerable |
| compaction | transcript | — | ✓ |
| model | transcript | — | per turn |

### What the phone can do, after Phase 3

| action | mechanism | confirmed by |
|---|---|---|
| send | typed into the pty, Enter | `prompt_submit` hook carrying the text |
| send during a turn | typed into the harness's own queue, if the spike proves it safe | `prompt_submit` when the queue drains |
| approve / deny | one key into the visible dialog, screen-verified | tool's `PostToolUse` (allow) or next hook signal (deny) |
| answer a question | arrow keys and Enter, screen-verified | the question tool's result in the transcript |
| stop | Esc while active | `stop` hook |
| `/compact`, `/model` | typed while idle | transcript compaction record / next turn's model |

Every action has three client states: **sending**, **sent**, **confirmed**. Nothing is
shown as done before its confirming signal arrives, and a signal that never arrives
within the action's budget is shown as *unconfirmed*, with the raw terminal one tap
away. That honesty is a feature: the phone never claims more than it knows.

## Phase 1 — collapse the choice

Ships the target flow. Touches no ACP code; the chat subsystem goes dormant but stays
compilable and intact, so this phase is reversible by revert.

**Backend**
- `SpawnSessionRequest.Mode` ([`dto.go:181`](../../../backend/internal/httpd/controllers/dto.go))
  is removed. A request carrying `mode` on `POST /sessions`, `POST /orchestrators`, or
  `POST /orchestrators/delegate` is rejected `400 SESSION_MODE_REMOVED` rather
  than silently ignored: a caller that asked for chat must not get TUI without being
  told. There are no shipped clients, so this is cheap insurance for a stale mobile
  build on a dev phone, not a compatibility commitment.
- `resolveSessionMode` ([`chat_spawn.go:248`](../../../backend/internal/session_manager/chat_spawn.go))
  and `SessionModeDefaults` go away; new sessions are written as TUI unconditionally,
  and `validateRuntimePrerequisites` runs for every spawn.
- `defaultSessionMode` is dropped from the settings payload and store
  ([`settings.go:75`](../../../backend/internal/httpd/controllers/settings.go)).
- All three `/sessions/{id}/interface-transition` routes — `GET`, `POST`, `DELETE`
  ([`sessions.go:195-197`](../../../backend/internal/httpd/controllers/sessions.go)) —
  are removed.
- **The database is cleared.** A goose migration empties every table except
  `app_settings`, which migrations seed and which holds no session data. Sessions,
  projects, worktrees, conversations, transitions, blocks, reviews, PRs and usage all
  go. The project is pre-release, there is nothing worth carrying, and a clean store
  is simpler to reason about than one with dead chat rows in it. Mobile pairing is not
  in the database and is unaffected. The `mode` column and the transition and
  conversation tables keep their schema until Phase 4, because the dormant ACP code
  still compiles against them.

**Desktop**
- Delete `SessionInterfaceSwitch.tsx` and its test; delete
  `hooks/useSessionInterfaceTransition.ts` and its test; drop the `interfaceSwitch` /
  `interfaceTarget` / `interfaceBusy` machinery from `SessionView.tsx`; remove the
  transition methods from `lib/api-client.ts` and the transition types from
  `types/workspace.ts`; update `i18n/renderer-coverage.test.ts` for the removed strings.
- Delete the session-interface row from `GeneralSettingsSection.tsx`.
- `TaskComposer` stops sending `mode` and loses the `canCreateAsTUI` chat-preflight
  fallback — there is no preflight left to fail.
- `SessionView` always renders `CenterPane`; `showChatSurface` is deleted.
- **Delete the desktop's dead TUI blocks path**: `TuiSessionBlocksPane` in
  [`CenterPane.tsx`](../../../frontend/src/renderer/components/CenterPane.tsx),
  `hooks/useSessionBlocks.ts` and its test, `CenterPane.blocks.test.tsx`, and the two
  e2e specs that click a button that no longer exists, `frontend/e2e/blocks-find.spec.ts`
  and `blocks-viewport.spec.ts`. `ChatSessionBlocksPane` and the block libraries under
  `lib/` that the chat pane still imports stay until Phase 4; anything in `lib/` that
  only the deleted TUI pane used goes now. The shell block terminal
  (`useShellTerminalBlocks`) is the terminal's own and is untouched.

**Mobile**
- Delete the INTERFACE picker and both `_ModeOption`s from
  [`spawn_body.dart:190-230`](../../../packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart),
  the `mode` field and `setMode` from `SpawnCubit`, and `mode` from
  `SpawnSessionParams`. `agents` stops filtering on `chatHarnesses`.
- Delete the mobile half of the transition coordinator:
  `feature/terminal/logic/interface_transition.dart`,
  `presentation/terminal_screen/logic/interface_switch_cubit.dart`,
  `presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart`, the
  `interface-transition` entry in `EndPoints`, the transition calls in
  `terminal_remote_data_source.dart`, and their tests (`interface_transition_test.dart`,
  `interface_switch_cubit_test.dart`, plus the harness and data-source cases that cover
  them).
- `session_route_screen.dart` routes every session to the terminal screen; the
  `mode == 'chat'` branch and its `ChatCubit` / `ConversationBlocksCubit` providers go.
- `defaultViewMode` already returns `blocks` for a covered harness, so mobile's default
  needs no change. Persist the user's toggle per session in `shared_preferences`.

**Testing.** A spawn carrying `mode` is rejected. A spawn without one is TUI. The
clearing migration leaves every table empty except `app_settings`, and a daemon that
starts on the cleared store lists no sessions and no projects. Desktop renders
`CenterPane` for every session and no code path references the deleted blocks pane.
Mobile's spawn body has no interface control, routes to the terminal screen, and the
per-session view toggle survives an app restart. The mobile `session_route` widget
test that asserts chat routing is deleted, not skipped.

## Phase 2 — transcript enrichment: the phone sees everything

Independent of Phase 1's merge. This is the blocks spec's Step 10, and it is the
phase that decides whether the phone is a real client or a permission remote with tool
names on it. It comes before the control phase because the phone must see before it
acts: question options, in particular, exist only here.

### Mechanism, shared by both harnesses

A **transcript tailer** per live session, owned by the session manager next to the
usage observer but not inside it — usage accounting must not couple to block
projection, and the two read the same file for different reasons.

- It opens the session's native transcript, seeks to a persisted byte offset, and
  reads new complete lines on each fsnotify write. The usage observer already tails
  these files
  ([`observe/usage/watcher.go`](../../../backend/internal/observe/usage/watcher.go)),
  so the watch mechanics are proven; the tailer reuses them without sharing state.
- The offset is persisted per session so a daemon restart resumes without
  re-emitting. An unknown or changed path (agent switching rewrites it through
  `safeNativeTranscriptPath`) resets the offset to zero for the new file.
- Each record is mapped by a **per-harness transcript mapper** living in that
  harness's adapter package, a sibling of its hook mapper, into zero or more block
  event records. A mapper is a handler that may drop records, as the blocks spec asks
  for; it is not a renamer. An unrecognised record produces nothing and is counted, so
  a harness upgrade degrades to fewer blocks, never to a crash.
- Records go through the same `redact` pass and the same text caps as hook events,
  with a larger budget for tool results and `truncatedLines` set when a body is cut.
  Exact budgets are a plan decision; the rule is that a capped body is marked, never
  silent.
- The block event `Record` ([`blockevent/types.go`](../../../backend/internal/service/blockevent/types.go))
  gains a `Source` field, `hook` or `transcript`, so the projection can apply
  precedence and a client can tell which channel a fact came from.

New block event kinds, harness-independent: `assistant_text`, `reasoning`,
`tool_start`, `tool_result`, `todo`, `turn_model`, `compaction`. `question_asked`
already exists and is enriched.

### Claude Code

The daemon already knows the path: the `Stop` hook carries `transcript_path`,
`opr hooks` forwards it, and lifecycle records it as `Metadata.NativeTranscriptPath`
([`lifecycle/manager.go:1281`](../../../backend/internal/lifecycle/manager.go)). The
usage observer already parses the record envelope
([`parser.go:240`](../../../backend/internal/observe/usage/parser.go)).

Real transcripts from this machine, sampled for shape only, contain the record types
`user`, `assistant`, `system`, `attachment`, `queue-operation` and several
bookkeeping types; content blocks `assistant/text`, `assistant/thinking`,
`assistant/tool_use` and `user/tool_result`; `isSidechain` on subagent records;
`toolUseResult` beside tool results; and `system` subtypes including
`compact_boundary` and `turn_duration`.

| transcript record | block event | `SourceID` | notes |
|---|---|---|---|
| `assistant` / `text` | `assistant_text` | record `uuid` | one block per text content block |
| `assistant` / `thinking` | `reasoning` | record `uuid` | body is the thinking text |
| `assistant` / `tool_use` | `tool_start` | `tool_use.id` | full `input`; merges with the hook's `pre-tool-use` on the same id |
| `user` / `tool_result` | `tool_result` | `tool_use_id` | body is the result text; `is_error` sets `errorType` |
| `tool_use` named `TodoWrite` | `todo` | `tool_use.id` | body is the todo list JSON; only builds that ship the tool produce it |
| `tool_use` named `AskUserQuestion` | `question_asked` | `tool_use.id` | `ToolInput` carries the questions and options; merges with the hook's `notification` |
| `assistant` with `message.model` | `turn_model` | record `uuid` | first assistant record of a turn |
| `system` subtype `compact_boundary` | `compaction` | record `uuid` | |
| `isSidechain: true` | dropped | | nesting under the Task block is deferred, `todo_without_tmux.md` §15 |
| everything else | dropped | | bookkeeping types carry no user-facing content |

`tool_use.id` is the same string the hooks call `tool_use_id`, which is what makes the
merge by `SourceID` work; `parentUuid` chains records into turns, so reasoning and
text attach to the prompt that caused them without a heuristic.

### Codex

Codex matters as much as Claude Code here, and it needs the transcript more: its hook
table ([`dispatch.go`](../../../backend/internal/adapters/agent/blockdispatch/dispatch.go))
maps only `session-start`, `user-prompt-submit`, `permission-request` and `stop`, so
**without the transcript a Codex session on the phone has no tool blocks at all.**

The rollout file lives under `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-<ts>-<thread>.jsonl`
and the adapter already locates it by thread id
([`continuation.go:95`](../../../backend/internal/adapters/agent/codex/continuation.go)).
Archived rollouts may be `.zst`-compressed; a live one never is, and the tailer only
ever opens the live file.

Real rollouts from this machine, sampled for shape only, are one `{timestamp, type,
payload}` envelope per line. `type` is one of `session_meta`, `turn_context`,
`response_item`, `event_msg`, `compacted`, and a few others. `response_item` payloads
carry the conversation: `message` with a `role` and `content` array (assistant
messages also carry a `phase`), `reasoning` with a `summary` array, `function_call` /
`function_call_output` and `custom_tool_call` / `custom_tool_call_output` paired by
`call_id`. `event_msg` payloads are UI events — `task_started`, `task_complete`,
`agent_message`, `agent_reasoning`, `exec_command_end`, `patch_apply_end`,
`context_compacted`, `token_count`, `sub_agent_activity`, `turn_aborted` — most of
which duplicate a `response_item` or a hook.

| rollout record | block event | `SourceID` | notes |
|---|---|---|---|
| `response_item` `message` role `assistant` | `assistant_text` | item `id` or line hash | `phase` distinguishes running commentary from the final answer; both render, the final one is marked |
| `response_item` `reasoning` | `reasoning` | item `id` or line hash | body is the joined `summary`; `encrypted_content` is never read |
| `response_item` `function_call` / `custom_tool_call` | `tool_start` | `call_id` | tool name from `name`; input from `arguments` / `input` |
| `response_item` `function_call_output` / `custom_tool_call_output` | `tool_result` | `call_id` | body is `output` |
| `turn_context` | `turn_model` | line hash | carries the model for the turn |
| `compacted` or `event_msg` `context_compacted` | `compaction` | line hash | one block, not two |
| `event_msg` `task_started` / `task_complete` / `user_message` / `agent_message` / `agent_reasoning` | dropped | | duplicates of hooks or of a `response_item` |
| `event_msg` `token_count` | dropped | | the usage observer's business |
| `event_msg` `sub_agent_activity` | dropped | | same deferral as Claude's sidechain |
| everything else | dropped | | |

Codex has no `AskUserQuestion` equivalent in the sampled rollouts, so `question_asked`
for Codex stays hook-driven and unanswerable until a question record is observed.
The mapper is written from fixtures captured on this machine, and **"good and stable"
means the fixtures are refreshed with each Codex release the adapter supports**, not
that the format is assumed frozen.

### Projection

The mobile assembler
([`block_assembly.dart`](../../../packages/mobile/lib/feature/blocks/logic/block_assembly.dart))
already correlates on `SourceID` and already knows the kinds `assistant`, `reasoning`,
`tool`, `todo`, `compaction`, `permission`, `notice` from the chat projection. This
phase extends it; it does not add a second assembler, and there is no desktop
assembler to keep in step after Phase 1.

- Events sharing a `SourceID` collapse into one block. **Transcript wins on body, hook
  wins on status.** A `tool_result` merges into its tool block as the result section;
  a `tool_start` from the transcript upgrades the hook's input preview to the full
  input without changing whether the block is running or blocked. For Codex, where no
  tool hook exists, the transcript's `tool_start` opens the block and `tool_result`
  closes it.
- A transcript record with no hook counterpart projects to its own block. That is the
  normal case for assistant text and reasoning.
- The hook's `stop` still closes the turn and still carries `last_assistant_message`;
  the projection prefers the transcript's `assistant_text` blocks and uses the hook's
  copy only if none arrived, so a session whose transcript is unreadable degrades to
  exactly today's behaviour.
- `reasoning` renders collapsed with a one-line preview, no setting; `tool_result`
  renders inside its tool block, collapsed past a few lines; `todo` renders as a
  checklist and later `todo` blocks in the same turn replace the earlier one rather
  than stacking.

### Latency, honestly

Both harnesses write a record when a content block completes, so assistant text
appears sentence-by-sentence at the earliest and paragraph-by-paragraph in practice;
there is no token streaming. The blocks view shows a lightweight "working" indicator
on the open turn between records, driven by the hook activity state, so the gap
between "tool finished" and "assistant text arrived" reads as thinking rather than as
a stall.

**Testing.** Fixture transcripts and rollouts (captured from real sessions, content
replaced) drive each mapper: every record type produces the documented event or
nothing, and an unknown type is counted, not fatal. Tailing resumes from a persisted
offset across a restart without duplicates. A path change resets the offset. Merge
rules are pure-function tests on the mobile assembler: a hook `permission_request`
plus a transcript `tool_start` on one id yields one blocked block with the full input;
a Codex `tool_start` with no hook yields a running block that `tool_result` closes; a
`tool_result` on an unknown id yields its own block, not a crash. A session with no
readable transcript projects identically to today.

## Phase 3 — control: the phone can act

Independent of Phase 1's merge; needs Phase 1 for UI placement and Phase 2 for
question options. Everything here writes keystrokes into the pty, so everything here
is designed around one rule: **verify the screen before every write, and confirm by
observation after it.**

### Facts the design has to respect

These are Claude Code's documented semantics
([hooks reference](https://code.claude.com/docs/en/hooks.md)) plus what Operator's own
adapter already relies on. Codex's dialogs are driven the same way through its own
key map; its hook semantics differ only in having no tool hooks.

- **The permission dialog waits indefinitely.** There is no ceiling on how long the
  user may take to notice and answer it in the terminal.
- **The `PermissionRequest` hook fires *before* the dialog.** An `allow` decision from
  the hook suppresses the dialog entirely, so the dialog cannot render until the hook
  has exited. While a hook is blocking, the desktop user is looking at a terminal that
  has not yet asked them anything.
- **A hook's timeout is Operator's choice.** Claude Code's default is 600 seconds;
  `claudeHookTimeout = 30` ([`hooks.go:15`](../../../backend/internal/adapters/agent/claudecode/hooks.go))
  is what Operator writes into every managed hook. On timeout the hook's output is
  discarded and the normal permission flow proceeds. Exit code 2 is not honoured for
  this event; a deny must go through the `decision` object.
- **Answering the dialog fires no hook.** Operator infers an approval from the
  `PostToolUse` of the blocked `tool_use_id`
  ([`activity.go`](../../../backend/internal/adapters/agent/claudecode/activity.go)).
  A denial has no signal until the agent does something else.
- **`send` is refused while blocked.** `ErrAwaitingDecision` exists precisely so that
  an injected paste cannot answer a dialog on the user's behalf.
- **The daemon can read the screen.** Pane capture is behind `ports.PaneCapturer`,
  driven by `service/terminalcapture`, and the idle detector already uses it
  ([`message_delivery.go:77`](../../../backend/internal/session_manager/message_delivery.go)).

### Screen-verified key driving

A **dialog driver** in the session manager, with a per-harness key map in the
adapter beside the nudge-safety rules. Before writing any dialog key it captures the
pane and checks that the expected dialog is on screen; after writing it captures again
and checks the screen moved. If the first check fails the action is refused with a
409 and the client is told the dialog is gone; if the second check fails the action is
reported *unconfirmed* and nothing further is written. The keys are chosen so that a
key which lands on an idle prompt anyway is harmless.

This is what turns "best-effort keystroke injection" into something a user can trust:
the daemon never types into a screen it has not just looked at.

### Approve and deny

`opr hooks <harness> permission-request` keeps doing what it does today — report the
request to the daemon — and additionally registers a **pending approval** carrying
`tool_use_id`, `tool_name` and `tool_input`. It then exits 0 with nothing on stdout,
immediately. The dialog renders in the desktop terminal at once, exactly as it does now.

A client resolves it with a deliberate write:

```
POST /sessions/{id}/decision   { "requestId": "...", "behavior": "allow" | "deny" }
```

The daemon checks the session is still blocked on that request, verifies the dialog
on screen, and drives the harness's answer key. This is **the one write the blocked
guard admits**; `send` stays refused. Because the phone answers the *dialog*, not the
*hook*, there is no time limit: the request is still there an hour later.

Resolution is **observed**. An `allow` is confirmed when the tool's `PostToolUse`
lifts the block (Claude Code) or the transcript's `tool_result` arrives (Codex). A
`deny` is confirmed by the next hook signal of any kind — the agent either tries
another tool or ends the turn — which is faster and more accurate than waiting for
`Stop`. Two clients, or a client and the terminal, racing one approval: the screen
check makes one win and tells the other the dialog is gone.

### Answering a question

The transcript's `AskUserQuestion` input (Phase 2) gives the phone the questions, the
options and whether each is multi-select. The client renders them as real controls and
posts the selection:

```
POST /sessions/{id}/answer   { "requestId": "<tool_use_id>", "selections": [[0], [2, 3]] }
```

The driver navigates the on-screen menu with the harness's keys — arrows, space for
multi-select, Enter — verifying the highlighted row from the pane capture before each
Enter rather than counting presses blind. Free-text "Other" answers are typed after
selecting that row. Confirmation is the question tool's `tool_result` in the
transcript, which carries the chosen answers and lets the client show what the agent
actually received.

### Send, and the queued-send spike

`send` keeps its current path — write, then confirm by watching the session go active
— with the confirmation made visible: the client shows *sent* on write and *confirmed*
when a `prompt_submit` hook arrives whose text matches. `ErrAgentNotResponding`
surfaces as *unconfirmed* with a retry, not as silence.

**The goal is the terminal's own behaviour: type during a turn and it queues.**
Claude Code queues a message typed mid-turn (the transcript records `queue-operation`
for exactly this) and Codex has an equivalent. If injecting into that queue is safe,
the phone can follow up without waiting for idle, like a person at the keyboard. The
idle gate exists because a paste mid-render can be swallowed, so this is settled by a
**spike run during this phase**, on a real session of each harness: send during an
active turn, watch whether the text lands in the queue intact and submits when the
turn ends. If it does, the gate is relaxed for that harness and the client shows the
message as *queued* until its `prompt_submit` arrives. If it does not, the daemon
holds the message and delivers it at idle, and the client still shows *queued* — the
user-visible behaviour is the same either way; only the reliability differs.

### Stop, compact, model

- **stop** writes Esc while the session is *active*, confirmed by the `stop` hook. It
  is the one action that must not wait for idle; Esc at an idle prompt is a no-op.
- **`/compact`** and **`/model`** are typed like `send`, gated on idle, confirmed by the
  transcript's `compaction` record and the next turn's `turn_model` respectively.

### Rejected: a blocking hook that returns the decision

The obvious design — the hook registers the approval, blocks until a client resolves
it, and writes `hookSpecificOutput.decision` to stdout — is rejected. It hides the
dialog for the whole time it blocks, so every permission prompt becomes a hang on the
desktop terminal until either the phone answers or the hook times out. Raising the
timeout towards Claude's 600-second default makes that worse, not better. It would
also give the phone a deadline the dialog itself does not have, and it buys nothing
the screen-verified driver does not already provide: a verified dialog answer is as
deterministic as a hook decision.

### Surface

A **pending-interaction resource** on the session — approvals and questions, one
shape — streamed like other session state and never under `/conversation`, which is
going away. Mobile renders `BlockKind.permission` and the question block as actionable
with the three-state confirmation. The desktop has no blocks view; its terminal dialog
*is* the interaction, and nothing is added there.

**Not in this phase.** Push notifications for a pending interaction. The registrar and
status plumbing exist behind `PushTokenSource` and stay unwired until there is a
Firebase project and an APNs key. The pending-interaction stream is the event a push
would carry, so nothing here has to change when that lands.

**Testing.** The hook exits 0 immediately with empty stdout and registers the approval.
A decision while blocked, with the dialog on screen, drives exactly one key. A decision
with the dialog absent is refused with 409 and writes nothing. A decision whose second
capture shows no change is reported unconfirmed. `send` stays refused while an approval
is pending. An `allow` confirms on the matching `PostToolUse` or `tool_result`; a `deny`
confirms on the next hook signal. A question answer navigates to the verified row
before Enter and confirms on the tool result. Stop writes Esc while active and nothing
while idle. A send during an active turn is shown as queued and confirms on its
`prompt_submit`, whichever delivery path the spike selected for that harness.

## Phase 4 — delete ACP

**Starts when Phase 3 merges.** There is no living-with window: between Phase 1 and
Phase 4 the ACP code is unreachable, which is exactly the dangling state this repo's
conventions forbid, and the decision to lose the ACP-only features was made with this
spec, not deferred to it. This phase is irreversible in practice.

Removed: `internal/adapters/chatdriver/` (12,574 lines), `internal/service/chat/`
(3,879), `internal/session_manager/interface_transition.go` (1,073), the `conversations`
controller and all eighteen `/conversation/*` routes, the ACP runtime resource and its
`build:acp-runtime` pipeline, `packages/mobile/lib/feature/chat/` (50 files),
`frontend/src/renderer/components/chat/` (16 components), `ChatSessionBlocksPane` and
whatever remains of the desktop block libraries under `lib/` once it is gone, and the
`ChatCapability` vocabulary in `internal/ports/chat.go`.

Schema: drop the `mode` column, `session_interface_transitions`,
`session_interface_transition_messages`, `conversations`, `conversation_turns`,
`conversation_messages`, `conversation_activities`, `conversation_provider_events`,
`conversation_branches`. The store was already emptied in Phase 1, so this is schema
only.

## Risks

- **Keystroke injection is the entire mobile control plane.** `send`, stop, `/compact`,
  `/model`, approval and answers all write into a pty. Screen verification and
  observed confirmation make each write checkable, but a harness that redraws its
  dialog differently after an update breaks the key map until it is updated. The
  send-confirmation work in progress (`ErrAgentNotResponding`) is evidence the
  heuristics are still being hardened.
- **Both transcript formats are undocumented.** Claude Code and Codex can add, rename
  or drop record types in any release. Each mapper degrades to fewer blocks, never to
  a crash, and the hook-only projection is the floor — but a silent fidelity regression
  after an upgrade is likely at some point and needs a fixture refresh, not a hotfix.
  For Codex the floor is lower: no tool blocks at all.
- **Two sources can disagree.** A hook says a tool is running; the transcript already
  has its result. Precedence is defined, but every new kind is a new place for the
  projection to show a block in the wrong state.
- **Twenty harnesses have no transcript mapper and most have no hooks.** Mobile is a
  raw terminal for them. If mobile use broadens beyond Claude Code and Codex, this
  becomes the dominant complaint.
- **Phase 4 is unrecoverable.** If rewind or elicitation turn out to matter, the cost of
  reversing after deletion is rebuilding, not reverting.

## Decisions recorded

Answered by the user on 2026-09-04; kept here so the reasoning is not lost.

- **Desktop is always the terminal.** No blocks view, no toggle. The dead TUI blocks
  path is deleted in Phase 1 rather than revived.
- **Mobile's view choice is device-local**, per session, in `shared_preferences`.
- **Grok is deferred.** Its transcript shape is unverified and the user does not use
  it. Tracked in `todo_without_tmux.md` §15.
- **Codex is in scope for Phase 2**, at the same standard as Claude Code.
- **Subagent records are dropped**; nesting them is tracked in `todo_without_tmux.md` §15.
- **The database is cleared in Phase 1**, not selectively migrated.
- **Queued send is a spike in Phase 3**, with the terminal's own queue behaviour as
  the target and idle-gated delivery as the fallback.
- **Phase 4 starts when Phase 3 merges.** No observation window.
- **Reasoning renders collapsed with a preview**, no setting.
