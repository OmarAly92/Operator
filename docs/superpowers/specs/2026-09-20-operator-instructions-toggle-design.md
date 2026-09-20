# Operator instructions toggle for user-created sessions — design

Date: 2026-09-20. Scope: `backend/` (session manager, session service, HTTP
DTOs, CLI, sqlite store) and `frontend/` (New Task composer). The Flutter client
is untouched. Approved in chat on 2026-09-20; this file records the decision.

## 1. Problem

Every session Operator launches receives an appended system prompt built in
[`buildSystemPromptText`](../../../backend/internal/session_manager/prompt.go)
(`prompt.go:70`): the Operator Worker/Orchestrator role, session lifecycle rules,
task-source and PR/MR rules, git rules, branch-namespace convention, Docker
container labels, the standing-instruction confidentiality guard, an optional
workspace prompt, and the `opr` skill pointer + Browser-panel section from
[`operatorSkillPointer`](../../../backend/internal/session_manager/manager.go)
(`manager.go:2971`). Claude Code receives it via `--append-system-prompt` /
`--append-system-prompt-file`
([`claudecode.go:198-211`](../../../backend/internal/adapters/agent/claudecode/claudecode.go));
every other harness receives the same text through its own mechanism.

The user wants a session they create from the New Task dialog to be able to run
the agent **exactly as if they had launched it themselves**: the harness's own
system prompt, nothing appended, no knowledge of `opr`. Activity tracking must
keep working, so the desktop sidebar, blocks, mux and the mobile client see the
session as they do today.

Sessions spawned by an orchestrator must keep everything: workers need `opr send`,
the branch convention and the rest to be coordinated.

## 2. Decision

A per-session boolean **`operatorInstructions`**, default **`false`** for
sessions created from the New Task dialog.

When it is `false` for a worker that no orchestrator requested, the manager
produces an **empty system prompt**. Because every harness adapter reads the
prompt from the same two `LaunchConfig`/`RestoreConfig` fields
(`SystemPrompt`, `SystemPromptFile`) and every adapter already has an
"if empty, emit nothing" branch, an empty prompt means no harness receives any
Operator-authored instruction text. No per-adapter code changes.

Everything that is not instruction text is unchanged:

- Workspace hooks (`opr hooks <harness> <event>`) are still installed by
  `GetAgentHooks` ([`manager.go:3333`](../../../backend/internal/session_manager/manager.go));
  for Claude Code that is the ten managed hooks in
  [`hooks.go:37-48`](../../../backend/internal/adapters/agent/claudecode/hooks.go).
  They report activity to the daemon; they give the agent nothing.
- PATH pinning of the daemon's `opr` binary (`manager.go:3127-3139`) stays, because
  the hooks need it. The agent is simply never told `opr` exists.
- Worktree, branch, session id, permission mode, model, Claude account, pane
  grid, attachments and the initial user prompt are unchanged.

## 3. Semantics

`effectiveOperatorInstructions(rec)` is true when **any** of:

| Condition | Why |
|---|---|
| `rec.Kind == orchestrator` | An orchestrator without `opr board`/`spawn`/`send` is useless. The dialog only creates workers, so this is a backend guard. |
| `rec.SpawnedBy != ""` | An orchestrator requested this worker; it must follow the coordination rules. `SpawnedBy` is set from `SpawnConfig.RequestedBy` at `manager.go:2743`, after the service has validated the claim (`service.go:239-254`), so it is the trustworthy signal, not the raw request field. |
| `rec.Metadata.OperatorInstructions == true` | The user opted in. |

Otherwise it is false and `buildSystemPrompt` returns `""`.

Consequences of `""`:

- `writeSystemPromptFile` (`manager.go:3021`) already returns `"", nil` for an
  empty prompt, so no `system.md` is written under the session's data dir.
- `buildSpawnTexts` (`manager.go:2905`) returns an empty `systemPrompt`; the
  user prompt is unaffected.
- Restore (`manager.go:1508`) and agent switch (`agent_switching.go:747`,
  `:910`) recompute the prompt through `buildSystemPrompt`, so they get the
  same `""`. This is why the flag must be persisted on the session record rather
  than living only in the spawn request.

**Agent-switch handoff.** `systemPromptForNativeRestore`
(`agent_switching.go:868`) appends the finalized handoff continuation to the
base prompt when a session is restored after a completed switch. That
continuation is the user's own conversation carried across harnesses, not an
Operator standing instruction, so it is **still appended** on top of the empty
base. Without it, switch-agent would land the new harness with no context.
This is the one case where a flag-off session receives appended text, and only
after the user has switched its agent. Flagged here so the choice is visible;
the user may override it.

## 4. Data model and wire

### `ports.SpawnConfig`

Add `OperatorInstructions bool` next to `RequestedBy`
([`ports/session.go:21-56`](../../../backend/internal/ports/session.go)).
Doc comment states the three-way rule in §3.

### `domain.SessionMetadata`

Add `OperatorInstructions bool \`json:"operatorInstructions,omitempty"\``
([`domain/session.go:27`](../../../backend/internal/domain/session.go)).
`seedRecord` (`manager.go:2731`) copies it from `SpawnConfig` at spawn.

### sqlite

Migration `0116_sessions_operator_instructions.sql`, modelled on
[`0107_sessions_spawned_by.sql`](../../../backend/internal/storage/sqlite/migrations/0107_sessions_spawned_by.sql):

```sql
-- +goose Up
ALTER TABLE sessions ADD COLUMN operator_instructions INTEGER NOT NULL DEFAULT 0;

-- +goose Down
ALTER TABLE sessions DROP COLUMN operator_instructions;
```

Thread the column through `queries/sessions.sql`, regenerate `gen/` with sqlc
(`backend/sqlc.yaml`), and map it in `session_store.go` both ways (row → record
at `session_store.go:419`, and the insert). Rows that predate the column read as
`false`; Operator has no released users, so no backfill.

### HTTP

- `DelegateTaskRequest` ([`dto.go:721`](../../../backend/internal/httpd/controllers/dto.go)):
  add `OperatorInstructions bool \`json:"operatorInstructions,omitempty"\`` with a
  description: "Append Operator's standing instructions and opr skill pointer to
  the agent's system prompt. Omit or false for the harness's own prompt only.
  Ignored for orchestrator-requested spawns, which always receive them."
- `SpawnSessionRequest` (`dto.go:203`): same field, same description.
- `DelegateTaskInput` (`delegation.go:26`) carries it to `SpawnConfig` in
  `DelegateTask` (`delegation.go:64`).
- The `/sessions` spawn controller maps it into `SpawnConfig` beside
  `RequestedBy`.
- Regenerate `openapi.yaml` (`go generate` in `apispec`, per `gen.go:6`) and
  the renderer's `src/api/schema.ts` (`npm run api:ts`).

### CLI

`opr spawn` ([`cli/spawn.go`](../../../backend/internal/cli/spawn.go)) gains
`--operator-instructions` defaulting to **`true`**, so `opr spawn` from a
terminal keeps today's behaviour; `--operator-instructions=false` opts out. An
orchestrator's `opr spawn` always carries `RequestedBy` from
`OPERATOR_SESSION_ID` (`spawn.go:130`), so the flag is moot there by §3.

## 5. Frontend

[`TaskComposer.tsx`](../../../frontend/src/renderer/components/TaskComposer.tsx):

- New state `const [operatorInstructions, setOperatorInstructions] = useState(false);`
- A second `Checkbox` row beside the worktree one (`TaskComposer.tsx:414-419`),
  same markup and classes, always rendered (not gated on project kind):
  label `t("newTask.operatorInstructions")`.
- `createTask` (`TaskComposer.tsx:95-103`) sends
  `operatorInstructions: input.operatorInstructions` in the delegate body;
  `CreateTaskInput` gets the field.
- i18n: `"newTask.operatorInstructions": "Operator instructions"` in `en.json`
  next to `newTask.createWorktree` (`en.json:413`), with the same key added to
  `de`, `es`, `fr`, `ja` (English fallback text is acceptable for the other
  locales if no translation is supplied; follow whatever the repo does for the
  worktree key).
- Not shown anywhere else. No toggle on an existing session: changing standing
  instructions mid-conversation would need a resend and a restart; a new
  session is the right tool.

## 6. Tests

Backend (`go test ./...`):

- `prompt_test.go` / `manager_test.go`:
  - worker, `SpawnedBy == ""`, flag false → `buildSystemPrompt` returns `""`;
    `buildSpawnTexts` returns the user prompt unchanged.
  - worker, flag true → output byte-identical to today's.
  - orchestrator kind, flag false → full orchestrator prompt.
  - worker, `SpawnedBy` set, flag false → full worker prompt including the
    `## Orchestrator Coordination` section.
- Spawn: with flag false, no `system.md` exists under the session's prompt dir
  after `Spawn`; with flag true it does.
- Restore and agent switch: a persisted flag-false record restores with
  `SystemPrompt == ""` and `SystemPromptFile == ""`; after a completed switch,
  the restore prompt is exactly the handoff continuation (protocol + artifact),
  nothing else.
- **Registry-wide table test** over every harness in
  `adapters/agent/registry`: for a worker `LaunchConfig`/`RestoreConfig` with
  empty `SystemPrompt`/`SystemPromptFile`, each adapter's argv and any env or
  config it emits equal what it produces for the same config with no prompt —
  and specifically contain none of: `--append-system-prompt`,
  `--append-system-prompt-file`, `-s <text>`, `--sys-prompt`,
  `developer_instructions=`, `model_instructions_file=`, `--read <system.md>`,
  a generated `opr-<id>` agent (Copilot, Kilo Code). This pins the
  "empty means nothing" property so a future adapter cannot regress it.
- Service: `DelegateTask` forwards the flag to `SpawnConfig`
  (`delegation_test.go`), and the `/sessions` spawn path does too.
- Controller DTO round-trip for both request bodies; OpenAPI contains the field.
- Store: migration test in the `migrate_*_test.go` style; the column round-trips
  through `CreateSession`/`GetSession`.

Frontend (`npm run lint`, `npm test`):

- `TaskComposer.test.tsx`: the checkbox renders unchecked by default; the
  delegate body carries `operatorInstructions: false`; checking it sends `true`.

Real-app verification (per the repo's verify recipe): spawn one Claude Code
session with the box unchecked, read the daemon-side launch argv from the logs
and confirm it is
`claude --session-id <uuid> [--permission-mode …] [--model …] [-- <prompt>]`
with no `--append-system-prompt*`; confirm the sidebar activity state still
flips (hooks alive) and the session appears normally on mobile.

## 7. Out of scope

- Exposing the flag in the session read model, Session Inspector or mobile UI.
- A per-project default for the checkbox.
- Removing `opr` from PATH or the hook files from the workspace: tracking
  depends on both.
- Any change to orchestrator sessions or orchestrator-requested workers.
