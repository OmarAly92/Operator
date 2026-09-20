# Remove the orchestrator subsystem — design

Date: 2026-09-20. Scope: `backend/`, `frontend/`, `packages/mobile`.
Approved in chat on 2026-09-20.

**Supersedes** [`2026-09-20-operator-instructions-toggle-design.md`](2026-09-20-operator-instructions-toggle-design.md).
That spec added a per-session opt-out for Operator's standing instructions. This
one removes most of those instructions outright and deletes the orchestrator, so
the toggle has nothing left to toggle. Delete the toggle spec when this lands.

## 1. Intent

Operator should create **ordinary agent sessions on any harness** — a session the
user starts from New Task runs the harness the way they would have run it
themselves, with no orchestration layer above it and almost no Operator-authored
system prompt.

### 1.1 Non-goals, stated as hard requirements

This change is a removal. Three user-visible systems **must behave exactly as they
do today**, and every one of them was verified against the removal list in §11
before this spec was written:

1. **Mobile normal-session chat.** Sending a message, receiving blocks, the
   terminal stream, and session liveness on `packages/mobile` must be unaffected.
2. **Desktop session states.** `working`, `needs_input` ("needs you") and the
   PR/review states must be derived and displayed exactly as today.
3. **The Kanban board**, on desktop *and* mobile. A session that needs the user
   must still land in the "Needs you" column; a session in review must still land
   in "In review".

If an implementation step cannot preserve all three, stop and re-open the design
rather than shipping a regression. §11 is the evidence that they are preservable;
§9 is the test set that proves they were preserved.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | The appended system prompt reduces to two sections: the PR branch-namespace block and, for workspace projects, the workspace layout block. |
| D2 | Delete `opr orchestrator`, `board`, `inbox`, `send`, `spawn`. Keep every other command. **CLI wrappers are deleted; their HTTP routes are not.** |
| D3 | Delete `domain.SessionKind` entirely, with a destructive migration. |
| D4 | Mobile removes its orchestrator feature and drops to a 4-tab bar, in the same branch. |
| D5 | Only the orchestrator is removed. Tickets/plans, auto-review and tracker intake keep spawning sessions. |
| D6 | Drop the container-label, project-rules and confidentiality sections from the prompt, and delete the config they served. |

The user was shown the cost of D1's browser half, D6's container leak and D6's
project-rules removal, and accepted each (§10).

## 3. What is removed

**Backend**

- `domain.SessionKind`, `KindWorker`, `KindOrchestrator` (`domain/session.go:16-22`).
- `orchestratorSystemPrompt`, `workerSystemPrompt`, `workerOrchestratorPrompt`,
  `workerContainerLabelPrompt`, `systemPromptGuard`, `buildProjectRules`,
  `projectRelativeFile`, `projectContextSection`, the `sessionPromptRole` type
  (`session_manager/prompt.go`).
- `Manager.operatorSkillPointer` (`session_manager/manager.go:2971`),
  `workspaceOrchestratorPrompt`, `activeOrchestratorSessionID` (`manager.go:3008`),
  `orchestratorBranch` (`manager.go:2775`), and the `kind` parameter of
  `defaultSessionBranch` (`manager.go:2748`).
- `ports.SpawnConfig.Kind` and `RequestedBy`; `SessionRecord.Kind` and `SpawnedBy`.
- `ProjectConfig.Worker`, `.Orchestrator`, the `RoleOverride` type,
  `.OrchestratorPolicy`, `.AgentRules`, `.AgentRulesFile`, `.ContainerReap`
  (`domain/projectconfig.go`), and their validation at `:199` and `:212`.
- `adapters/container/dockerreap/**`, `ports.ContainerReaper`,
  `lifecycle.WithContainerReaper` (`lifecycle/manager.go:136`).
- The `orchestrator_inbox` table (`migrations/0106_orchestrator_inbox.sql`).
- CLI: `cli/orchestrator.go`, `board.go`, `inbox.go`, `send.go`, `spawn.go` and
  their tests; their `root.AddCommand` lines (`cli/root.go:189,190,202,203,204`).
- `skillassets/using-opr/commands/{orchestrator,spawn,send}.md`.
- `telemetrymeta` entries for the deleted commands.

**Renderer**

`OrchestratorActivityIndicator.tsx`, `OrchestratorReplacementDialog.tsx`,
`lib/spawn-orchestrator.ts`, `lib/restart-orchestrator.ts`, and the orchestrator
branches in `Sidebar`, `ShellTopbar`, `routes/_shell.tsx`, `stores/ui-store.ts`,
`CommandPalette`, `KeyboardShortcutsDialog`, `SessionsBoard`, `BoardEmptyStates`,
`DashboardSubhead`, `CreateProjectAgentSheet`, `ProjectSettingsForm`, plus
`isOrchestratorSession`, `workerSessions`, `newestActiveOrchestrator`,
`orchestratorHealth`, `hasConfiguredOrchestratorAgent` (`types/workspace.ts`),
the `kind` and `orchestratorAgent` mapping in `hooks/useWorkspaceQuery.ts:73,94`,
and the synthetic orchestrator session in `e2e/support/fake-bridge.ts:259-268`.

**Mobile**

`lib/feature/orchestrator/**` (9 source files) and `test/feature/orchestrator/**`
(6 test files); `lib/feature/sessions/data/model/orchestrator_model.dart`; the
Orchestrator tab (`core/app_routes/home_shell.dart:50,88`); the `/orchestrators`
future and the `kind` filter in `sessions_remote_data_source.dart:24,27,42`;
orchestrator entries in `service_locator.dart`, `app_constants.dart`,
`app_skin.dart`; the orchestrator fallback loop in
`session_route_screen.dart:76-84`; `orchestrators` on `sessions_cubit.dart:46`.

## 4. What is explicitly kept

Each of these looks deletable to a `grep` for "orchestrator" or "kind" and is not.

| Kept | Why | Evidence |
|---|---|---|
| `POST /sessions/{id}/send` | Desktop, mobile and the API all send through it. Only the `opr send` **CLI wrapper** is deleted. | `cli/send.go:55` and `end_points.dart:35` hit the same route |
| The `/orchestrators/delegate` **handler** | This is the New Task dialog's endpoint. It is renamed, not deleted — see §6. | `TaskComposer.tsx:95` |
| `sessions_cdc_insert/update/delete` triggers | They drive **all** session liveness, desktop and mobile, despite the `0108_board_cdc` filename. | `db.go:739-767` → `change_log` → `cdc.Poller` |
| `packages/mobile/.../board_snapshot.dart` | Carries `sessions`, `projects`, `accountLabels` as well as `orchestrators`. Only the `orchestrators` field is removed. | `board_snapshot.dart:8-15` |
| `SessionsBoard.tsx:116` `w.kind === "single_repo"` | **Project** kind, not session kind. | `migrations/0009_workspace_projects.sql:3` |
| `projects.kind` column | Same: project kind. | as above |
| `buildTaskPrompt` and `issueContextTrustBoundary` | The task prompt is a separate builder from the system prompt, and the trust boundary is the prompt-injection guard for tracker-intake issue text, which stays live per D5. | `prompt.go:47`, `:155-159` |
| `opr hooks` and the ten managed hooks | Every session state in both UIs originates here. | `claudecode/hooks.go:37-48` |
| `opr` on PATH | The hooks invoke it. | `manager.go:3142`, `:3189-3207` |
| `browser`, `preview`, `pr`, `review`, `session`, `project`, `status`, `agent` | Kept as deliberate tools even though no prompt mentions them. | D2 |
| Tickets/plans, auto-review, tracker intake | D5. They keep calling `Spawn`. | `ticket/service.go:492,605,747,828`; `review/review.go:343`; `trackerintake/observer.go:206` |

## 5. Prompt

`buildSystemPromptText` (`prompt.go:70`) collapses to:

```
## Pull Requests for This Session      <- workerMultiPRPrompt(), prompt.go:309
## Workspace project                   <- workspace-kind projects only, manager.go:3090
```

`systemPromptConfig` reduces to `AdditionalSections`; the role switch and every
other field go. `writeSystemPromptFile` (`manager.go:3021`) is unchanged — it
already returns `"", nil` for an empty prompt.

The branch-namespace block is kept because it is the agent-side half of a real
contract: `matchSession` (`observe/scm/observer.go:848`) attributes a PR to a
session **only** by branch prefix, and `sessionBranchPrefixes` (`:872`) accepts
the session branch plus, for a `<ns>/root` branch, anything under `<ns>/`. A PR
opened on a branch outside that namespace is invisible to the observer: no PR
card, no CI, and no "In review" column for that session.

Note its limit. A session that simply commits and pushes the branch Operator
created for it is attributed with no prompt at all (exact-match case). The block
only earns its place when the agent invents a new branch name.

## 6. HTTP surface

Delete `GET /orchestrators`, `POST /orchestrators`, `GET /orchestrators/{id}`
(`controllers/sessions.go:245,246,248`) and `OrchestratorIDParam` (`dto.go:1007`).

**`POST /orchestrators/delegate` (`sessions.go:247`) is renamed to
`POST /sessions/delegate`, not deleted.** It is the New Task dialog's
session-creation endpoint and happens to live under the orchestrator prefix. Update
`TaskComposer.tsx:95` and regenerate `src/api/schema.ts`. Mobile does not call it —
mobile creates sessions with `POST /api/v1/sessions`
(`spawn_remote_data_source.dart:43`).

Remove `Kind` from `SpawnSessionRequest` and `DelegateTaskRequest`, and
`RequestedBy` from both. Regenerate `openapi.yaml` (`go generate` in `apispec`)
and `schema.ts` (`npm run api:ts`).

Session endpoints decode with the lenient `decodeJSON` (`projects.go:158`), so a
client still sending `"kind":"worker"` is silently ignored rather than rejected.
This is what makes an un-updated mobile build safe against a new daemon
(`spawn_session_params.dart:27` sends exactly that). Do **not** switch these
endpoints to `decodeJSONStrict`.

`projects.go` does use `decodeJSONStrict` (`:58,76,111,129`), so removing
`ProjectConfig` fields 400s any client that still sends them. The renderer ships
in the same branch; mobile never writes project config, so it is unaffected.

## 7. Data model and migration

Migration **0116**, the first free number (`0115_block_events_agent.sql` is the
highest today).

`sessions.kind` carries `CHECK (kind IN ('worker','orchestrator'))`
(`migrations/0001_init.sql:26-27`), and SQLite refuses `ALTER TABLE ... DROP
COLUMN` on a column named in a CHECK constraint.

**No table rebuild is needed.** The repo already has a sanctioned pattern for
editing a CHECK constraint in place — `PRAGMA writable_schema = ON` plus
`UPDATE sqlite_master SET sql = replace(...)`, used for the harness constraint in
`0053`, `0054`, `0082` and `0083`. Dropping only the CHECK clause leaves a plain
`kind TEXT NOT NULL DEFAULT 'worker'` column that a real `ALTER TABLE ... DROP
COLUMN` then removes, rewriting rows properly.

This was verified safe: **no trigger or index on `sessions` references `kind` or
`spawned_by`.** The `OLD.kind IS NOT NEW.kind` at `0108_board_cdc.sql:26` belongs
to `projects_cdc_update` and refers to `projects.kind` — the project kind, not the
session kind. `spawned_by` was added without a CHECK
(`0107_sessions_spawned_by.sql:2`), so it drops directly.

```sql
-- +goose NO TRANSACTION
-- +goose Up
DELETE FROM sessions WHERE kind = 'orchestrator';
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, 'CHECK (kind IN (''worker'', ''orchestrator''))', '')
WHERE type = 'table' AND name = 'sessions';
PRAGMA writable_schema = RESET;
ALTER TABLE sessions DROP COLUMN kind;
ALTER TABLE sessions DROP COLUMN spawned_by;
DROP TABLE orchestrator_inbox;
```

> **Why this matters.** The obvious alternative — rebuilding the table — would
> drop every trigger attached to it, including `sessions_cdc_update`, which writes
> the `session_updated` rows carrying `activity` and `isTerminated` into
> `change_log` (`db.go:739-767`). That is the one way this change could freeze
> both Kanban boards and mobile liveness: sessions stuck in "Working" forever,
> never "Needs you", never terminated, with everything else looking healthy. There
> is no safety net — `reconcileSchema` (`db.go:780`) inspects `pragma_table_info`
> for missing *columns* and never notices a missing *trigger*. The in-place
> approach above never drops a trigger, and §9's first test asserts all three
> still fire after migrating.

Then thread the removal through `queries/sessions.sql`, regenerate `gen/` with
sqlc (`backend/sqlc.yaml`), and drop the mapping in `session_store.go` both ways.
Existing orchestrator rows are deleted; Operator has no released users.

`ProjectConfig` loses the `Worker`/`Orchestrator` pair. Harness selection today
lives **only** on `RoleOverride.Harness` (`projectconfig.go:131`), never on
`ProjectConfig.AgentConfig`, so a new `ProjectConfig.Harness AgentHarness`
(`json:"agent,omitempty"`) replaces the pair, validated with the same
`IsKnown()` check the pair used at `projectconfig.go:200`. Without it the project
has no way to name its harness.

## 8. Frontend and mobile

**Renderer.** `SessionsBoard.tsx:114` becomes `workspaces.flatMap((w) => w.sessions)`
— `workerSessions` only filtered orchestrators (`workspace.ts:286-288`). Delete the
orchestrator header strip (the 44 references at `SessionsBoard.tsx:22-56,127-161,240-256`);
none of it participates in column assignment. `ProjectSettingsForm` drops the
orchestrator agent/model/mode fields and the agent-rules input, keeping one agent
selector. Remove the orchestrator i18n keys from `en.json` — see §8.1, which reduces the
renderer to a single locale. The Kanban keeps
its plan lanes (D5).

**Mobile.** Delete the orchestrator feature and tests; bottom nav 5 → 4 tabs with
every index renumbered (`home_shell.dart:20,50,87-90`); drop the `/orchestrators`
future so the fan-out is 4 calls → 3.

> **Preserve the sequential auth probe.** `sessions_remote_data_source.dart:22`
> awaits `/sessions` **alone** before fanning out. The daemon locks a device out
> for a minute after 5 failed auths, so a stale password under `Future.wait` burns
> 4 failures per poll tick. A test pins the call order. Removing one future must
> not collapse the remaining three into the first await.

Remove the orchestrator fallback in `session_route_screen.dart:76-84`; normal
sessions resolve in the loop above it (`:63-72`), so the change is subtractive.

### 8.1 Single locale

Decided in chat on 2026-09-20, alongside this work: the renderer ships **English
only**. Delete `i18n/{de,es,fr,ja,ko,pt-BR,zh-CN}.json` (~470KB), the key-parity
guard `i18n/renderer-coverage.test.ts`, the language selector in
`components/settings/GeneralSettingsSection.tsx`, and the locale plumbing in
`shared/ui-locale.ts` (`APP_LOCALES`, `DEFAULT_LOCALE`, `coerceLocale`) and
`i18n/locales.ts` (`documentLang`).

**i18next stays, and every `t("key")` call site is untouched** — 1238 of them
across 93 files. Only the resource bundles and the machinery for choosing between
them are removed. Inlining the English strings and dropping i18next entirely is a
separate change, deliberately not bundled here: a 93-file mechanical rewrite would
make this branch unreviewable.

The seven translated READMEs under `translations/` go too, along with the language
switcher row at `README.md:12`. The repository ships English documentation only.

`packages/mobile` is unaffected by the locale change — it already uses inline
English with no key catalogue — but its orchestrator design doc and screenshots
(`packages/mobile/docs/design/orchestrator/`) are deleted with the feature.

## 9. Verification

**Migration (guards §7's hazard).** After running 0116 on a populated database:
`UPDATE sessions SET activity_state = 'active'` must insert exactly one
`session_updated` row into `change_log` whose payload carries `id`, `activity` and
`isTerminated`. Repeat for insert and delete. Assert all three triggers exist in
`sqlite_master`.

**Session states (guards §1.1.2 and §1.1.3).** Table test over `deriveStatus`
(`service/session/status.go:27`) composed with `attentionZone`
(`lib/session-presentation.ts:211`):

| Activity / PR input | Status | Column |
|---|---|---|
| `ActivityActive` | `working` | working |
| `ActivityWaitingInput` | `needs_input` | action ("Needs you") |
| `ActivityBlocked` | `needs_input` | action ("Needs you") |
| open PR, review requested | `review_pending` | pending ("In review") |

Mirror it in `flutter test` over `attentionOf`
(`feature/sessions/logic/session_status.dart:17`) for `needs_input` → `respond`,
`review_pending` → `pending`, default → `working`.

**Mobile chat (guards §1.1.1).** Existing send, blocks, terminal and mux tests must
pass untouched. Add a regression test that `SessionModel.fromJson` on a payload
with **no** `kind` key yields a session that survives the sessions list filter.

**Prompt.** A session spawned from New Task produces a system prompt equal to the
branch-namespace block alone; a workspace project adds the workspace block and
nothing else. No `system.md` content beyond those two.

**Gates.** `go test ./...`; `npm run lint` and `npm test`; `flutter analyze`
("No issues found!") and `flutter test`.

**Real-app verification**, per the repo recipe (verify the renderer in the browser
against an isolated daemon): create a session from New Task; confirm its launch
argv carries no orchestrator flags; drive it to a permission prompt and confirm the
card moves to **Needs you** on desktop *and* mobile; open a PR from it and confirm
it moves to **In review** on both; confirm the mobile session chat sends and
streams.

## 10. Accepted regressions

Raised in chat and accepted by the user. Recorded so they are not re-filed as bugs.

1. **The Browser panel loses its driver prompt.** `manager.go:2981` was the only
   place any agent was told `opr browser` exists or that Codex's in-app browser and
   browser MCPs cannot see Operator's session-owned page. Agents will now reach for
   their own browser tools. The `opr browser` command itself is kept.
2. **Agent-started Docker containers are no longer reaped.** Nothing instructs
   agents to apply `--label opr.session`, so `dockerreap` is unreachable and is
   deleted with it (`dockerreap/reap.go:30`). Containers persist until removed by
   hand.
3. **Per-project agent rules are gone**, not merely undelivered:
   `agentRules`/`agentRulesFile` and their settings UI are deleted.
4. **PR attribution narrows** to branches inside the session namespace, and the
   generic "work on a feature branch" instruction is gone — which in practice makes
   agents *more* likely to stay on Operator's own branch, where attribution is
   exact.

## 11. Evidence: the three protected systems

Traced before this spec was written. Each leg was checked against §3.

**Mobile chat.** Send: handler (`controllers/sessions.go` `send`) → `Service.Send`
(`service/session/service.go:617`) → `Manager.Send` — no kind, orchestrator or
spawned-by reference on any hop. Transport: `httpd/terminal_mux.go` has no kind
reference at all. Blocks: no kind coupling. Screen: `session_route_screen.dart`
`_lookup` matches `cubit.sessions` first. Creation: `POST /api/v1/sessions`, lenient
decoder. Project config: mobile never writes it.

**Session states.** `deriveStatus` takes `(rec, prs, now, signalCapable)` and no
kind; `signalCapable` is a function of harness (`service.go:1023`). `working` comes
from `ActivityActive`; `needs_input` from `ActivityWaitingInput`/`ActivityBlocked`,
fed by the retained `PermissionRequest` and `Notification` hooks
(`claudecode/hooks.go:43,45`); review states from `deriveSCMStatus(prs)`.

**Kanban.** Columns are attention zones
(`boardAttentionZoneOrder = ["working","action","pending","merge"]`), and
`attentionZone()` contains no kind reference. Mobile's parallel `attentionOf()`
keys only off `session.status` and `session.prs`. Liveness on both reaches the UI
through the CDC triggers of §7.

## 12. Out of scope

- Removing tickets/plans, auto-review or tracker intake (D5).
- Any per-project default for harness selection beyond replacing the removed pair.
- Re-pointing agents at the Browser panel by another mechanism (§10.1).
- Backfilling or migrating deleted orchestrator sessions.

Project documentation (`AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/architecture.md`,
`docs/STATUS.md`, `docs/mobile-parity-ledger.md` and the rest) is **in** scope: a
breaking-change budget buys complete removals, not stale prose. The implementation
plan carries it as its final task, working from `git ls-files '*.md'` rather than a
fixed list, and leaving `docs/plans/`, `docs/todo/`, `docs/terminal/` and
`docs/superpowers/` as historical records.
