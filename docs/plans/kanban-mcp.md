# Operator MCP server: board-aware sessions

**Status:** accepted

**Date:** 2026-09-24

**Surfaces:** daemon (`backend/`), `opr` CLI, agent adapters, desktop board, mobile (read-only fallout)

## Problem

A spawned session knows almost nothing about the board it sits on. Its standing
instructions (`buildSystemPromptText`, `backend/internal/session_manager/prompt.go`)
are only the PR-branch naming convention plus, for workspace projects, the repo list.
The board is derived entirely from facts the agent never sees:

| Column | Source today |
| --- | --- |
| Idle / Working | activity hooks (`opr hooks <agent> <event>` → `POST /sessions/{id}/activity`) |
| Needs you | hooks report `waiting_input`/`blocked`, the process exited, or no hook for 90s (`deriveStatus`, `backend/internal/service/session/status.go`) |
| In review | SCM poller: PR open, draft, or review pending |
| Ready to merge | SCM poller: PR approved or mergeable |
| Planned | ticket files |

The flow runs one way: from the agent to the daemon. The consequences:

- An agent that ends its turn with a question reads **Idle**, not Needs you. Claude's
  `Stop` hook maps to idle (`adapters/agent/claudecode/activity.go`).
- An agent in a project with no remote (Scratch) can never reach In review.
- An agent cannot see its own status, its PRs' CI/review state, or the other sessions
  in its project.
- The only agent→board action is the `curl` baked into the ticket reviewer prompt
  (`service/ticket/prompt.go`, `reviewPrompt`).

## Decision

Ship an Operator MCP server that every MCP-capable agent gets at launch. The server:

- reads the board and the session's own state,
- performs a small set of actions **scoped to the calling session**,
- carries the board's rules in its MCP `instructions`, so no standing prompt text is
  added for this.

Agents without MCP support get nothing. There is no prompt or CLI fallback.

| Concern | Decision |
| --- | --- |
| Transport | stdio, `opr mcp` subcommand (same binary the hooks already pin via PATH) |
| SDK | `github.com/modelcontextprotocol/go-sdk` (official, v1.8.0) |
| Backend access | loopback daemon HTTP through the existing CLI client (`internal/cli/client.go`), per AGENTS.md "CLI is a thin client" |
| Caller identity | `OPERATOR_SESSION_ID` / `OPERATOR_PROJECT_ID` from the launch env; action tools take no session id argument |
| Board rules | MCP server `instructions` + tool descriptions |
| Registration | per-launch config written under `<dataDir>/prompts/<session>/`, never in the worktree |
| Non-MCP harnesses | unsupported, no fallback |
| Agent-driven column moves | new durable fact `agent_report` that `deriveStatus` reads; status itself stays derived |

### Scoping is a guardrail, not a security boundary

The loopback listener is unauthenticated by rule (AGENTS.md), so any local process can
already call every route. The MCP server enforces self-scope so a well-meaning agent
cannot kill, restore, or move another card by mistake. Do not add auth to loopback
for this.

## Tool surface

The server name is `operator`, so Claude sees these as `mcp__operator__<tool>`.

### Read tools

| Tool | Input | Returns | Backed by |
| --- | --- | --- | --- |
| `board_get` | `project_id?` (default: own project) | columns in board order, each with cards: `session_id`, `name`, `status`, `column`, `status_reason`, `branch`, `prs[]` (number, url, state, ci, review, mergeability), `last_activity_at`, `agent_report`, `ticket`, `is_self`; plus planned tickets for single-repo projects | `GET /projects/{id}`, `GET /sessions?projectId=`, `GET /projects/{id}/tickets` |
| `session_get` | `session_id?` (default: self) | full card plus PR summary (title, head SHA, checks, unresolved comment flag), `workspace_path`, `harness` | `GET /sessions/{id}`, `GET /sessions/{id}/pr` |
| `ticket_get` | `slug?` (default: own ticket from `Session.Ticket`) | ticket title/brief, spec path, plans with status, this session's role | `GET /projects/{id}/tickets/{slug}` |

Reading other sessions is allowed. It lets agents avoid duplicate work across a project.

### Action tools (self only, no `session_id` parameter)

| Tool | Input | Effect | Backed by |
| --- | --- | --- | --- |
| `session_report` | `state: needs_you \| ready_for_review \| clear`, `reason` (≤ 280 chars, required unless clear) | moves own card; reason shows on the card and in the Needs you alert | **new** `PUT/DELETE /sessions/{id}/agent-report` |
| `session_rename` | `name` (≤ 20 chars) | sets the card title | `PATCH /sessions/{id}` |
| `pr_claim` | `pr` (number or URL) | attributes a PR opened off-convention to this session | `POST /sessions/{id}/pr/claim` |
| `pr_resolve_comments` | `pr`, `comment_ids?` | resolves review threads after addressing them; rejected unless the PR belongs to this session | `POST /prs/{id}/resolve-comments` |
| `review_request` | none | asks Operator's internal reviewer to review own PR(s) | `POST /sessions/{id}/reviews/trigger` |
| `ticket_mark_merge_ready` | `summary` | reviewer role only: reports the plan branch ready; replaces the `curl` in `reviewPrompt` | `POST /projects/{id}/tickets/{slug}/plans/{plan}/merge-ready` |

### Deliberately excluded

These stay the user's decision on the board: kill, restore, spawn/delegate, PR merge,
ticket merge approval, moving or editing other sessions, and changing project config.

### How the agent learns to use it (no skill)

The agent uses these tools without the user asking. Three layers deliver that, all
automatic:

1. **Tool list.** A connected MCP server's tools appear in the agent's tool list with
   their descriptions. Nine small tools stay well under Claude Code's threshold for
   deferring MCP tools behind tool search.
2. **Server `instructions`.** Claude Code adds a connected server's `instructions` to
   the system prompt, so the rules below are always in context. No user prompt and no
   Operator prompt text are needed.
3. **Tool descriptions** carry the when-to-call rule a second time at the point of use.
   For example, `session_report`: "Call this before ending a turn in which you are
   waiting on the user…".

**No skill.**
- A skill loads on demand when its description matches the task, but "report before
  you stop and wait" must be always on.
- Skills are Claude Code only, and injecting one means writing into the worktree or
  `~/.claude`.
- The MCP `instructions` field is the standard, per-launch, cross-harness place for
  always-on rules.

**Per-harness check (phases 4 and 5).** Confirm that each harness's MCP client puts
server `instructions` in context. Where one drops them, the adapter adds the same text
(one Go constant, `mcpBoardInstructions`) to that harness's standing system prompt. The
text only goes to sessions that also have the MCP server, so it is a delivery channel,
not a non-MCP fallback.

**Residual risk.** Reads are pulled when useful. `session_report` depends on the model
following the rule; nothing in the hooks can tell "idle, done" from "idle, waiting on
you". Phase 2's real-app check measures this with no hint in the user prompt. If
compliance is poor, tighten the wording first. Only then consider a Claude Code `Stop`
hook that blocks once per turn when the final message ends in a question and no report
was made.

### Server instructions (draft)

> You are running inside an Operator session. Operator shows every session as a card on
> a kanban board: Working/Idle, Needs you, In review, Ready to merge. Your card moves
> automatically from your activity and your pull requests. Call `session_get` to see
> your column and why you are in it. When you end a turn waiting on the user (a
> question, a decision, missing access), call `session_report` with `needs_you` and a
> one-line reason first, otherwise your card reads Idle and nobody is alerted. When the
> work is complete and there is no PR to review, call `session_report` with
> `ready_for_review`. Use `board_get` before starting broad work to see what other
> sessions in the project are doing. Never try to move another session's card.

## Backend changes

### 1. Board column mapping moves into Go

Today the status→column map exists only in TypeScript (`attentionZone`,
`frontend/src/renderer/lib/session-presentation.ts`). The MCP server needs the same
map in Go.

- Add `domain.BoardColumn` (`working`, `needs_you`, `in_review`, `ready_to_merge`, `archive`)
  and `domain.BoardColumnFor(SessionStatus)`, mirroring `attentionZone`:
  `merge→ready_to_merge`, `action→needs_you`, `pending→in_review`, `working→working`,
  `done→archive`.
- Add a shared fixture `testdata/board-columns.json` (`status → column`). A Go test and
  a vitest both assert their mapping against it, so the two maps cannot drift.
- Expose `boardColumn` on `SessionView`. The frontend can keep `attentionZone` for now.

### 2. `statusReason`, derived at read time

Add `deriveStatusReason(rec, prs, now, signalCapable) string` next to `deriveStatus`,
returning one line that explains the status, for example:

- `"Waiting on a permission prompt"` (blocked)
- `"Agent: <report reason>"` (agent report)
- `"CI failing on #12 (lint, test)"`
- `"Changes requested on #12"`
- `"Merge conflict on #12"`
- `"No hook signal since launch"`

It is never stored (AGENTS.md: do not store derived status). It is exposed as
`statusReason` on `SessionView` and used by `board_get`/`session_get` and the card.

### 3. Agent report: a durable fact, not a stored status

**Migration `0118_session_agent_report.sql`:**

```sql
ALTER TABLE sessions ADD COLUMN agent_report_state  TEXT NOT NULL DEFAULT ''
    CHECK (agent_report_state IN ('', 'needs_you', 'ready_for_review'));
ALTER TABLE sessions ADD COLUMN agent_report_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE sessions ADD COLUMN agent_report_at     TEXT;
```

Recreate `sessions_cdc_update` (latest definition is in `0101_drop_conversations.sql`)
with `OR OLD.agent_report_state <> NEW.agent_report_state OR OLD.agent_report_reason <>
NEW.agent_report_reason`, and add both to the `session_updated` payload. Without that,
the board and mobile never see the change. Do not edit merged migrations. Add
`migrate_agent_report_test.go` in the existing `migrate_*_test.go` style, covering the
trigger firing.

**Queries:** `SetSessionAgentReport`, `ClearSessionAgentReport` in
`storage/sqlite/queries/`, then `npm run sqlc`.

**Domain:** `SessionRecord.AgentReport{State, Reason, At}`.

**`deriveStatus` precedence** (only additions are marked ★):

1. terminated → `merged`/`terminated`
2. activity `active` → `working`
3. activity `exited` → `exited`
4. activity `waiting_input`/`blocked` → `needs_input`
5. ★ report `needs_you` → `needs_input`
6. SCM status (open/merged PR wins over a self-report of ready)
7. ★ report `ready_for_review` → `review_pending`
8. no signal → `no_signal`
9. `idle`

Reusing `needs_input`/`review_pending` keeps the `SessionStatus` enum unchanged. The
mobile client, notifications and the TS zone map therefore need no enum work, and the
card is told apart by `agentReport` being present.

A report made mid-turn has no effect while the agent is `active` (step 2). It takes
effect when the turn ends, which is the intended moment.

**Clearing.** In `lifecycle.Manager.ApplyActivitySignal`
(`backend/internal/lifecycle/manager.go`), clear the report on:

- the harness's user-prompt-submitted event (Claude `UserPromptSubmit`, Codex
  equivalent). This fires when the user answers, and also on Operator nudges, which
  are pasted user turns.
- terminate. A restore keeps the report (see Decisions).
- an explicit `session_report clear`.

Do not clear on every transition into `active`: a permission dialog
(`blocked`→`active`) mid-turn would wipe a fresh report. For a harness whose hooks have
no prompt-submitted event, clear on a transition from `idle`/`waiting_input` into
`active` instead. A new turn can only start from there. Each adapter declares which
rule applies.

**Notifications.** Raise the alert when the report *takes effect*, not when it is
written. The agent usually reports mid-turn while it is still `active`, and alerting
then would ping the user before the agent has stopped.
- In `ApplyActivitySignal`, when a session leaves `active` with report `needs_you` set,
  raise a `NotificationNeedsInput` intent through `sessionIntent` with the reason as
  the body.
- Suppress the `turn_finished` intent for that same stop, so the user gets one alert,
  not two.
- A report written while the session is already idle alerts immediately.
- `needsInputResolutions` resolves the alert when the report clears.
- Phone alerts (ntfy) and desktop alerts follow for free.

**Route.** Add `PUT /api/v1/sessions/{sessionId}/agent-report` with body
`{state, reason}`, and `DELETE` for the same path.

- Validation: `state` enum; `reason` required for `needs_you`, ≤ 280 runes, passed
  through `domain.SanitizeControlChars`.
- Errors use the standard envelope: `SESSION_NOT_FOUND`, `SESSION_TERMINATED`,
  `INVALID_AGENT_REPORT`.
- DTOs go in `controllers/dto.go`, registered in `apispec/specgen/build.go`, then
  `npm run api`. Commit `openapi.yaml` and `frontend/src/api/schema.ts`.

**Read model.** `SessionView` gains `agentReport?: {state, reason, at}`, `boardColumn`
and `statusReason`.

### 4. `opr mcp`

New `backend/internal/cli/mcp.go` and `mcp_tools.go`:

- A hidden Cobra command `opr mcp` that serves stdio with `mcp.NewServer(&mcp.Implementation{Name: "operator", Version: version}, &mcp.ServerOptions{Instructions: ...})`.
- Startup requires `OPERATOR_SESSION_ID` (validated with the existing `sessionIDPattern`).
  If it is missing, exit with a usage error, because the server is meaningless outside
  a session.
- Each tool is a typed handler (`mcp.AddTool` with input/output structs, so the SDK
  generates the JSON schemas) that calls the daemon through the shared client helpers.
  Mirror DTOs in the CLI as the rest of `internal/cli` does. Do not import `controllers`.
- Daemon errors become MCP tool errors (`IsError: true`) that carry the envelope
  `code`, `message` and `requestId`, so the agent can react and requestIds survive.
- The daemon being unreachable is a tool error, not a server crash. An agent that
  starts before the daemon is ready then recovers on the next call.
- `pr_resolve_comments` and `ticket_mark_merge_ready` check ownership/role against
  `session_get` before calling the route.

### 5. Registering the server at launch

**Ports.** Add `MCPServers []MCPServerSpec` to `ports.LaunchConfig`,
`ports.RestoreConfig` and `ports.WorkspaceHookConfig`. The last one matters because
most adapters already configure their CLI through files written by `GetAgentHooks`,
and the MCP entry belongs in the same file:

```go
type MCPServerSpec struct {
    Name    string            // "operator"
    Command string            // absolute path of the daemon's own opr executable
    Args    []string          // ["mcp"]
    Env     map[string]string // OPERATOR_SESSION_ID, OPERATOR_PROJECT_ID, OPERATOR_RUN_FILE, OPERATOR_DATA_DIR
}
```

Do not reuse `AllowedTools`. For some adapters it means *restrict to*, and the
reviewer relies on that (see the `LaunchConfig` comment).

**Session manager.** `buildSpawnTexts`' siblings (spawn, restore at `manager.go` ~1350
and ~3247, and agent switching `agent_switching.go` ~744/914) fill `MCPServers` for
every worker session.

- `Command` is the same absolute executable the hooks PATH pin resolves to
  (`augmentRuntimePATHForLaunchBinary`, the warning at `manager.go:2813`), so the MCP
  server and the hooks are always the same `opr` as the daemon.
- Env is set explicitly in the spec rather than relying on the agent passing its env
  through.
- Reviewer sessions (`internal/review/launcher.go`) get no MCP server. They are
  read-only by contract.

**Adapters.** Each supported adapter maps the spec to its CLI's mechanism, preferring
these in order:

1. **A per-launch flag** in `GetLaunchCommand` and `GetRestoreCommand`. Resume rebuilds
   config from flags, exactly like the system prompt.
2. **An Operator-owned config file** that the adapter already points the CLI at through
   an env var or flag (`OPENCODE_CONFIG`, `CODEX_HOME`, `KILO_CONFIG_CONTENT`,
   `AUTOHAND_CONFIG`, `VIBE_HOME`, `KIMI_CODE_HOME`, …).
3. **The workspace-local config file** the adapter already writes for hooks in
   `GetAgentHooks` (`.claude/settings.local.json`-style), removed by
   `CleanupWorkspace`. Files in a `worktree` workspace are git-excluded with
   `Workspace.AddExclude`. For an `in_place` workspace, write only what the adapter
   already writes there for hooks; never add a new file to the user's own checkout.

| Harness | Mechanism | Pre-approval |
| --- | --- | --- |
| Claude Code | pass the config inline: `--mcp-config '{"mcpServers":{"operator":{...}}}'` (the flag accepts JSON strings), so no file is written or cleaned up. Never `--strict-mcp-config`, which would drop the user's own servers. Never a worktree `.mcp.json`, which dirties git and triggers the project-server approval prompt. | append `mcp__operator` to `--allowedTools` inside the adapter only when the operator server is present |
| Codex | `-c mcp_servers.operator.command=…`, `-c mcp_servers.operator.args=["mcp"]`, `-c mcp_servers.operator.env={…}` via the existing `codexTOMLConfigString` quoting | verify Codex's MCP approval behaviour under each approval mode; document it |
| OpenCode | add `mcp.operator = {type: "local", command: [opr, "mcp"], environment: {…}}` to the generated `opencode.json` that `OPENCODE_CONFIG` already points at | `permission` block if needed |
| Others | phase 5, per the table there | per CLI |

Where a CLI needs a config *file* (option 2), it is written under
`<dataDir>/prompts/<id>/` next to `system.md` and removed by
`cleanupSystemPromptDir`, which already owns that directory.

## Frontend changes (desktop)

Follow DESIGN.md (clone agent-orchestrator verbatim).

- **Card** (`SessionsBoard.tsx`): when `agentReport` is present, render the reason as one
  muted line under the title, prefixed by the column dot colour. Needs you shows the
  question. In review without a PR shows "Ready for review" plus the reason.
- **Card tooltip** on the status line shows `statusReason`.
- **i18n**: new keys in `en.json` and the `zh-CN` catalog.
- **Tests** (vitest): card renders the reason. `attentionZone` matches
  `testdata/board-columns.json`.
- `useWorkspaceQuery` already refetches on `session_updated`, so no transport work is
  needed once the CDC trigger carries the new columns.

## Mobile (`packages/mobile`)

The status enum is unchanged, so columns and alerts are already correct. Optional
follow-up: parse `agentReport` in the hand-written session model and show the reason
on the card (`status_visual.dart`). Gate: `flutter analyze` + `flutter test`.

## Ticket prompt cleanup

- `reviewPrompt`: replace the `mergeReadyCurl` block with "call `ticket_mark_merge_ready`
  with one line describing what was verified". Delete `mergeReadyCurl`.
- `implementPrompt`/`planningPrompt`: no change. The ticket is readable through
  `ticket_get`, but the prompts stay self-contained.

## Delivery: one PR per phase, branched from `development`

Claude Code is the primary harness. It is wired in phase 1, so every tool added in
phases 2 and 3 works in Claude Code as soon as it lands. Each phase's real-app check
runs in a Claude Code session. Phases 4 and 5 only extend the same tools to other
harnesses.

### Phase 1: read-only MCP on Claude Code

- `domain.BoardColumn` + fixture + Go/TS parity tests.
- `boardColumn` and `statusReason` on `SessionView` (+ `npm run api`).
- `opr mcp` with `board_get`, `session_get`, `ticket_get` and the instructions.
- `MCPServers` in ports; Claude Code launch/restore/agent-switch wiring; `mcp__operator`
  pre-approval.
- **Tests**:
  - MCP tools against an `httptest` daemon via the SDK's in-memory transport.
  - Claude argv tests for launch and restore.
  - Missing `OPERATOR_SESSION_ID` → usage error (exit 2).

### Phase 2: agent report (the column move)

- Migration + CDC trigger + queries + domain + `deriveStatus` precedence + route + DTOs.
- Lifecycle clear-on-prompt, notification intent/resolution.
- `session_report` tool.
- Desktop card reason line + tooltip + i18n.
- **Tests**:
  - `deriveStatus` table for every precedence row.
  - Migration/trigger test.
  - Controller tests (happy path, validation, 404, terminated, envelope + requestId).
  - Lifecycle clear tests (prompt clears; blocked→active does not).
  - Notification raised and resolved.

### Phase 3: self-scoped actions

- `session_rename`, `pr_claim`, `pr_resolve_comments` (ownership check),
  `review_request`, `ticket_mark_merge_ready` (role check).
- `reviewPrompt` curl removal.
- **Tests**: each tool's happy path, daemon error mapping, and ownership/role rejection.
- **Real-app check, in a Claude Code session**:
  - Rename the card.
  - Claim an off-convention PR.
  - Resolve own review threads, and get a rejection on another session's PR.
  - Request an internal review.
  - As a ticket reviewer, report merge-ready via the tool; the board shows the merge
    prompt.

### Phase 4: Codex and OpenCode wiring

- Adapter mapping for launch, restore and agent switch (Claude ⇄ Codex keeps the server).
- Confirm each CLI surfaces server `instructions`; if not, set the adapter's
  instructions-in-system-prompt flag.
- Codex tool approval: pre-approve the operator server under every approval mode the
  adapter emits (per-server approval config if the pinned Codex version supports it).
- Prompt-submitted clearing event for each.
- **Tests**: argv/config tests for launch and restore, and an instructions-channel test.
- **Real-app check**: the phase 1–3 checks, repeated in a Codex session and an OpenCode
  session.

### Phase 5: every remaining harness

Wire every remaining adapter in `backend/internal/adapters/agent/`, one commit per
harness. The "already writes" column is from the adapters' current code. Before wiring
each harness, confirm its MCP config key, instructions support and approval rules
against that CLI's documentation for the version Operator pins.

| Harness | Already writes / points at | Likely MCP channel |
| --- | --- | --- |
| amp | `settings.json` | `amp.mcpServers` in that settings file |
| agy | `hooks.json` | per CLI docs |
| auggie | nothing | per-launch MCP flag, if the CLI has one |
| autohand | `config.json` via `AUTOHAND_CONFIG` | MCP block in that config |
| cline | nothing | per CLI docs |
| continue | `config.yaml` | `mcpServers` in that config |
| copilot | `config.json`, agent profile | additional MCP config flag or the agent profile |
| crush | data dir via `XDG_DATA_HOME` | `mcp` block in its config |
| cursor | `cli-config.json`, `hooks.json` | `mcp.json` alongside the hooks it already writes |
| devin | `config.local.json` | MCP block in that config |
| droid | `settings.json`, `hooks.json` | Factory MCP config next to them |
| goose | `config.yaml` via `XDG_CONFIG_HOME` | an `extensions` entry (stdio) in that config |
| grok | `settings.local.json` | MCP block in that settings file |
| kilocode | `KILO_CONFIG` / `KILO_CONFIG_CONTENT` | `mcp` block in the injected config |
| kimchi | `config.json`, `hooks.local.json` | MCP block in that config (it already speaks `mcp__server__tool` rules) |
| kimi | `config.toml` via `KIMI_CODE_HOME` | MCP config file flag or that config |
| kiro | agent config with `mcpServers: {}` | fill the `mcpServers` map it already writes |
| muse | config via `XDG_CONFIG_HOME` | per CLI docs |
| qwen | `settings.json` | `mcpServers` in that settings file |
| vibe | `config.toml`, `hooks.toml` via `VIBE_HOME` | MCP servers table in that config |
| prime-agent | nothing | per CLI docs |
| aider, pi | nothing | expected no MCP client → recorded as unsupported |

A harness with no MCP client is recorded as unsupported in `docs/architecture.md` and
gets nothing, with no prompt fallback. Per harness, add the same config tests as
phase 4, and run the phase 1 read check in a real session.

### Phase 6 (optional): mobile reason line

## Verification per phase

- `npm run lint` (go test + golangci-lint), `npm run frontend:typecheck`,
  `cd frontend && npm run frontend:lint`, `cd backend && go test ./internal/httpd/...`
  (spec drift).
- **Real app**: `npm run tauri:dev`, spawn a Claude session in Scratch.
  - Phase 1: ask it "what column are you in and why?" It answers from `session_get`.
  - Phase 2, with no mention of Operator in the prompt: give it a task that needs a
    decision from you. The card moves Working → Needs you with the question when the
    turn ends, exactly one alert fires, and answering moves it back. Repeat about 10
    times and record how often it reports; this is the compliance measure from "How the
    agent learns to use it".
  - Phase 2: ask it to finish a task with no remote. The card moves to In review with
    its reason.
  - Phase 3: on a real PR, `pr_resolve_comments` resolves only that PR's threads.

## Rollout notes

- Sessions that are already running get the MCP server only when they are next
  restored or relaunched, because config is applied at launch.
- The config points at the daemon's own `opr` path, the same path the hooks already
  depend on. An app update that replaces the binary in place keeps working. A moved
  install breaks both the hooks and MCP together, and `opr doctor` should check both.
- Add a telemetry event for tool calls (tool name and outcome only, never arguments)
  so compliance can be seen after release.

## Docs to update

- `docs/architecture.md`: the MCP server, the agent-report fact and its precedence.
- `docs/cli/README.md`: `opr mcp` (hidden; launched by agents, not users).
- `docs/STATUS.md` as phases land.

## Decisions

Confirmed by the user on 2026-09-24:

1. **Every `mcp__operator` tool is pre-approved.** All of them are self-scoped and
   reversible, and a permission prompt on `session_report` would itself park the card
   in Needs you.
2. **A report survives restore.** It stays until the next user prompt, because a
   restored session that was waiting on the user is still waiting.
3. **`board_get` may read any project.** Everything is local and read-only.

Out of scope for now: spawning helpers (`/sessions/delegate`). Revisit once agents use
the board.
