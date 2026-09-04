# One session kind, two client views

Status: design approved, unimplemented
Date: 2026-09-04
Scope: `backend/internal`, `frontend/src/renderer`, `packages/mobile`
Supersedes: the dual-mode session model established by
[`2026-08-27-session-blocks-design.md`](2026-08-27-session-blocks-design.md), which
kept both modes alive and decided the block source per session

A session no longer chooses an interface. Every session is a TUI agent in a pty.
What a client shows is a **local view preference** — desktop defaults to the raw
terminal, mobile defaults to the blocks view — and nothing about a session records
which surface anyone picked.

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
desktop terminal is the product's centre of gravity and because the TUI's structured
event stream is good enough to build a phone client on.

### What this gives up, permanently

The block stream is driven by **agent hooks**, not by scraping terminal bytes
([`dispatch.go`](../../../backend/internal/adapters/agent/blockdispatch/dispatch.go)),
so a TUI session already reports `prompt_submit`, `tool_complete`, `permission_request`,
`permission_replied`, `stop` and `question_asked`. Phase 2 recovers approve, stop,
`/compact` and `/model` on top of that.

These are ACP-protocol facts that no hook exposes, and they go away for good:

- rewind / rollback to a turn (`POST /conversation/turns/{id}/rollback`)
- editing a past message (`.../edit`)
- branch / fork (`.../branches/{id}/activate`)
- elicitation forms and consented URL interactions (`.../inputs/{id}/resolve`)
- structured `usage`, `rate_limits`, `diffs`, `plans`, `nested_agents` metadata
- native image content in a prompt (attachments degrade to a worktree path)

Only three harnesses have block mappers — `claude-code`, `grok`, `codex`. Every other
harness contributes no blocks, so on mobile they are raw-terminal only. That is a
regression for the four ACP harnesses (`opencode` and `droid` lose chat entirely) and
no change for the other twenty.

## Target state

One kind of session. `SessionMode` does not exist. `POST /api/v1/sessions` does not
accept `mode`. There is no daemon-wide default interface, no interface-transition
coordinator, and no per-session record of any surface choice.

Each client owns its own view preference, persisted locally:

| | default view | toggle to |
|---|---|---|
| desktop | raw pty | blocks |
| mobile | blocks | raw pty |

Both toggles already exist —
[`SessionViewCubit`](../../../packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart)
on mobile, `TuiSessionBlocksPane` in
[`CenterPane.tsx`](../../../frontend/src/renderer/components/CenterPane.tsx) on desktop.
Because the preference is local, the two clients can never disagree and there is
nothing to transition.

A message sent from mobile reaches the agent through `POST /sessions/{id}/send`, which
types into the pty. The desktop terminal shows it, and the agent working, because it is
literally the same terminal.

## Phase 1 — collapse the choice

Ships the target flow. Touches no ACP code; the chat subsystem goes dormant but stays
compilable and intact, so this phase is reversible by revert.

**Backend**
- `CreateSessionRequest.Mode` ([`dto.go:181`](../../../backend/internal/httpd/controllers/dto.go))
  is removed. A request carrying `mode` is rejected `400 SESSION_MODE_REMOVED` rather
  than silently ignored: a caller that asked for chat must not get TUI without being
  told. Mobile builds in the wild will send it until they update.
- `resolveSessionMode` ([`chat_spawn.go:248`](../../../backend/internal/session_manager/chat_spawn.go))
  and `SessionModeDefaults` go away; new sessions are written as TUI unconditionally.
- `defaultSessionMode` is dropped from the settings payload and store
  ([`settings.go:75`](../../../backend/internal/httpd/controllers/settings.go)).
- `POST`/`GET /sessions/{id}/interface-transition` are removed
  ([`sessions.go:195-196`](../../../backend/internal/httpd/controllers/sessions.go)).
- The `mode` column and `session_interface_transitions` /
  `session_interface_transition_messages` tables stay in place this phase; only writes
  stop. Dropping them is Phase 3.

**Desktop**
- Delete `SessionInterfaceSwitch.tsx` and its test; drop `useSessionInterfaceTransition`
  and the `interfaceSwitch` / `interfaceTarget` / `interfaceBusy` machinery from
  `SessionView.tsx`.
- Delete the session-interface row from `GeneralSettingsSection.tsx`.
- `TaskComposer` stops sending `mode` and loses the `canCreateAsTUI` chat-preflight
  fallback — there is no preflight left to fail.
- `SessionView` always renders `CenterPane`; `showChatSurface` is deleted. Add a
  terminal/blocks view toggle to the session topbar, persisted in `localStorage`,
  defaulting to terminal.

**Mobile**
- Delete the INTERFACE picker and both `_ModeOption`s from
  [`spawn_body.dart:190-230`](../../../packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart),
  the `mode` field and `setMode` from `SpawnCubit`, and `mode` from
  `SpawnSessionParams`. `agents` stops filtering on `chatHarnesses`.
- `session_route_screen.dart` routes every session to the terminal screen; the
  `mode == 'chat'` branch and its `ChatCubit` / `ConversationBlocksCubit` providers go.
- `defaultViewMode` already returns `blocks` for a covered harness, so mobile's default
  needs no change. Persist the user's toggle per session in `shared_preferences`.

**Testing.** A spawn carrying `mode` is rejected. A spawn without one is TUI. Desktop
renders `CenterPane` for every session and the view toggle survives a reload. Mobile's
spawn body has no interface control and routes to the terminal screen. The mobile
`session_route` widget test that asserts chat routing is deleted, not skipped.

## Phase 2 — close the approval gap

Independent of Phase 1's merge; needs Phase 1 only for its UI placement.

Today `PermissionRequest` is installed and fires, but is one-way. The adapter says so:
*"`opr hooks` writes nothing to stdout, so installing it never injects a permission
decision"* ([`hooks.go:35`](../../../backend/internal/adapters/agent/claudecode/hooks.go)).
The return path already exists — `hookSpecificOutput` is used today to inject
session-start context ([`hooks.go:250`](../../../backend/internal/cli/hooks.go)).

**Mechanism.** `opr hooks claude-code permission-request` registers a pending approval
with the daemon and blocks on it. A client resolves it; the CLI writes
`hookSpecificOutput.permissionDecision` to stdout and exits.

**The 30-second ceiling is load-bearing.** `claudeHookTimeout = 30`
([`hooks.go:15`](../../../backend/internal/adapters/agent/claudecode/hooks.go)). The
hook must return within it, and on expiry must write nothing and exit 0 — Claude's own
dialog is still on screen in the desktop terminal, so an unanswered phone prompt
degrades to answering in the terminal. That is a fallback, not a failure, and it must be
tested as the normal path it will often be. Raising the timeout is a separate decision;
do not raise it as part of this phase.

**Surface.** A new pending-approval resource on the session (not under `/conversation`,
which is going away), streamed to clients like other session state. Mobile renders the
existing `BlockKind.permission` block as actionable; desktop may show it too, though the
terminal dialog remains authoritative there.

**Also in this phase**, driven by keystroke injection into the pty rather than hooks:
stop (Esc), `/compact`, and `/model`. These are best-effort and gated on the same idle
detector `send` already uses
([`message_delivery.go:71`](../../../backend/internal/session_manager/message_delivery.go));
they must be presented as requests, not guarantees.

**Testing.** A decision resolved inside the window reaches stdout in Claude's expected
shape. A decision not resolved in 30s writes nothing and exits 0. A decision for an
already-resolved or unknown request is refused without consuming it. Two clients racing
one approval: one wins, the other is told it was already answered.

## Phase 3 — delete ACP

Only after Phase 1 and 2 have been lived on long enough to confirm the losses listed
above are acceptable. This phase is irreversible in practice.

Removed: `internal/adapters/chatdriver/` (12,574 lines), `internal/service/chat/`
(3,879), `internal/session_manager/interface_transition.go` (1,073), the `conversations`
controller and all eighteen `/conversation/*` routes, the ACP runtime resource and its
`build:acp-runtime` pipeline, `packages/mobile/lib/feature/chat/` (50 files),
`frontend/src/renderer/components/chat/` (16 components), and the `ChatCapability`
vocabulary in `internal/ports/chat.go`.

Schema: drop the `mode` column, `session_interface_transitions`,
`session_interface_transition_messages`, `conversations`, `conversation_turns`,
`conversation_messages`, `conversation_activities`, `conversation_provider_events`,
`conversation_branches`. No data migration — the project is pre-release and a fresh
database is acceptable.

**The window must have an end.** Between Phase 1 and Phase 3 the ACP code is
unreachable, which is exactly the dangling state this repo's conventions forbid. Fix a
date at Phase 1 merge and either delete or reverse the decision on it; do not leave the
window open indefinitely.

## Risks

- **The 30s hook ceiling** makes phone approval a race the user can lose. Mitigated by
  the desktop dialog staying authoritative, but it means mobile-only operation is not
  fully hands-off for a permission-heavy agent.
- **Keystroke injection is heuristic.** `send`, stop, `/compact` and `/model` all wait
  for the screen to *look* idle. This is the weakest joint in the design and it is now
  on the critical path for every mobile interaction, where before chat mode had a real
  turn protocol.
- **Twenty harnesses have no blocks.** Mobile is a raw terminal for them. If mobile use
  broadens beyond Claude Code, this becomes the dominant complaint.
- **Phase 3 is unrecoverable.** If rewind or elicitation turn out to matter, the cost of
  reversing after deletion is rebuilding, not reverting.

## Open questions

1. Does the desktop view toggle belong in the session topbar or the terminal tab strip?
2. Should mobile's per-session view preference sync across devices, or stay device-local
   like every other client preference?
3. Is `grok` reusing `claudeCodeEvents` still correct once the permission hook becomes
   bidirectional, or does it need its own table?
