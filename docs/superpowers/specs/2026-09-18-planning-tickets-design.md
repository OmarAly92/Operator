# Planning tickets: spec + plan documents assigned to agents from the board

**Date:** 2026-09-18
**Decision owner:** Omar Aly
**Status:** approved design, not yet implemented

## Why

Today a session starts from a prompt typed at spawn time. Planning happens in a
session too, but the artefacts it produces (a design spec and one or more
implementation plans under `docs/superpowers/`) are invisible to the product:
nothing lists them, nothing links a running agent to the plan it executes, and
assigning the next phase means finding the file, opening a spawn dialog and
pasting a prompt.

The target workflow: spend a day planning eight features with an agent, then for
days afterwards do nothing but drag a plan onto the board. The agent implements
it in a worktree, the existing reviewer and PR flow take it to merge, and the
next plan is one more drag. Plans must be readable and editable in the app, the
way Obsidian shows markdown.

Operator has no users yet ([[operator-has-no-users-yet]]); breaking changes and
fresh data are free, so this design picks the cleanest model rather than the
most compatible one.

## Decisions made in conversation (2026-09-18)

| Decision | Choice |
|---|---|
| Where ticket docs live | **In the repo, on the default branch**, one folder per ticket. Versioned with the code; every worktree sees them by path. |
| Runtime state (assignments, planning session, archive) | **SQLite**, never frontmatter. The daemon writes into the repo only when creating a ticket stub and when the app editor saves. |
| Drop target behaviour | **Prefilled confirm sheet**, Enter to start. |
| Plan ordering | **Ordered by filename prefix, soft gate**: assigning a later phase while an earlier one is not merged warns but is allowed. |
| Editor | **CodeMirror 6 source editor + react-markdown preview**, Edit / Preview / Split. |
| Board placement | **New leftmost column PLANNED.** |
| Planning session workspace | **In place on the project root** (`workspaceMode: in_place`). |
| Ticket birth | **Title + brief creates the folder; `Plan with agent` spawns the planning session.** Docs can also be written by hand. |
| Plan status | **Derived from the linked session and its PR**, plus a manual `done` for hand-done work. |
| Ticket completion | **Done when every plan is merged or marked done**; the ticket then shows in the Archive bar. Folder stays in the repo. |

## Vocabulary

- **Ticket**: a folder under `.operator/tickets/<slug>/` in a project's repo,
  holding one spec and zero or more plans. One ticket may have one planning
  session.
- **Plan**: a file `plans/NN-<phase>.md` inside a ticket. The unit that is
  dragged and assigned. One plan may have many assignments over time; the
  latest wins.
- **Planning session**: an ordinary worker session, spawned in place at the
  project root, whose task is to write or revise the ticket's docs.
- **Implementing session**: an ordinary worker session, spawned in a worktree,
  whose task is one plan.

## 1. Data model

### 1.1 On disk (per project, default branch)

```
.operator/tickets/<slug>/
  ticket.md            # frontmatter: title, brief, created; body: free notes
  spec.md              # the design spec
  plans/01-<phase>.md  # one file per phase; frontmatter: title
  plans/02-<phase>.md
```

- `slug` is kebab-case, derived from the title at create time; collisions get
  `-2`, `-3`. The response to create returns the slug actually used.
- Order of plans is the numeric prefix. A plan file without a numeric prefix
  is listed last with a warning badge, never rejected.
- A ticket is valid with only `ticket.md`.
- Frontmatter is YAML between `---` fences. Missing `title` falls back to the
  first `# ` heading, then the filename.

### 1.2 SQLite

`tickets`

| column | notes |
|---|---|
| project_id | FK projects |
| slug | text; PK with project_id |
| planning_session_id | nullable FK sessions |
| archived_at | nullable |
| created_at | |

`plan_assignments`

| column | notes |
|---|---|
| id | PK |
| project_id, slug | ticket |
| plan_file | e.g. `plans/02-editor.md` |
| session_id | FK sessions |
| assigned_at | |
| done_at | nullable; set by manual "mark done" (session_id may then be null) |

Rows are append-only; the newest row per (project_id, slug, plan_file) is the
current assignment. Deleting a session does not delete its rows.

Both tables emit rows into `change_log` via triggers like every other table, so
the frontend learns of changes over the existing SSE stream.

### 1.3 Derived status (never stored)

Plan status, from the current assignment row and its session's derived
`SessionStatus`:

| condition | plan status |
|---|---|
| no assignment row | `todo` |
| `done_at` set | `done` |
| session status `working` | `working` |
| session status `needs_input` | `needs_you` |
| session status any PR state before merged | `in_review` |
| session status `merged` | `merged` |
| session status `terminated`, or session missing | `terminated` |
| otherwise (`idle`, `no_signal`) | `idle` |

Ticket status:

| condition | ticket status |
|---|---|
| `archived_at` set | `archived` |
| every plan is `merged` or `done`, and at least one plan exists | `done` |
| any plan has an assignment that is not `terminated` | `in_progress` |
| planning session exists and is not terminated | `planning` |
| at least one plan | `ready` |
| otherwise | `draft` |

`done` tickets render in the Archive bar even with `archived_at` null; archive
is an explicit action that also hides tickets you abandon.

## 2. Daemon

### 2.1 Reading

A ticket scanner reads `<project.Path>/.operator/tickets/` (for `workspace`
projects: each registered repo's path, ticket identity is `repo + slug`; for
`scratch` projects tickets are unsupported and the column shows a hint). It
runs on project load and on file events from the same watcher that feeds the
workspace files view, debounced. It never reads git; it reads the checkout as
it is on disk.

Routes (all under `/api/v1/projects/{projectId}`):

```
GET  /tickets                          list, with derived statuses and plan summaries
GET  /tickets/{slug}                   ticket, plans in order, linked session ids
GET  /tickets/{slug}/files/{path}      raw markdown + mtime
PUT  /tickets/{slug}/files/{path}      body: content, ifUnmodifiedSince (mtime)
POST /tickets                          body: title, brief  → creates folder, commits
POST /tickets/{slug}/plan              spawn planning session (body: harness, claudeAccountId, extra)
POST /tickets/{slug}/plans/{file}/assign   spawn implementing session (body below)
POST /tickets/{slug}/plans/{file}/done     manual mark done
POST /tickets/{slug}/archive           and /unarchive
```

`{path}` is resolved and must stay inside the ticket folder; anything else is
400. `PUT` with a stale `ifUnmodifiedSince` is 409 with the current mtime.

Error envelope is the locked `{error, code, message, requestId}`; new codes:
`ticket_not_found`, `ticket_path_outside`, `ticket_file_stale`,
`ticket_planning_active`, `ticket_unsupported_project` (scratch projects), and
the assign pre-check codes in §2.4.

### 2.2 Create

`POST /tickets` writes `ticket.md` (frontmatter title, brief, created) and an
empty `spec.md` with a `# <title>` heading, then commits on the current branch
of the project root with `ticket: add <slug>`. If the root is not on the
project's default branch the request still succeeds but the response carries
`warnings: ["not_on_default_branch"]`. Editor saves via `PUT` write the file
and do not commit.

### 2.3 Planning session

`POST /tickets/{slug}/plan` spawns a `worker` session with:

- `workspaceMode: in_place`, `projectId`, chosen `harness` and
  `claudeAccountId`, `displayName` = ticket title truncated to 20.
- System prompt addition (appended after the existing worker preamble and
  project rules) stating: ticket slug, absolute folder path, the file layout
  and frontmatter contract from §1.1, that plans get a two-digit numeric
  prefix in dependency order, and to commit the folder when done.
- Task prompt: the brief, then "brainstorm with the user, write `spec.md`,
  then one plan per phase" if no plans exist, or "revise the existing docs"
  if they do, then the user's extra instructions verbatim.
- The prompt is workflow-agnostic: it names no skill, plugin or method. The
  agent uses whatever planning workflow its harness and the user's plugins
  provide (superpowers, speckit, none); only the output contract in §1.1 is
  fixed. The session is an ordinary harness session started in the project
  root, so it loads the repo's and the user's own instructions and plugins as
  a terminal session would.

The session id is stored in `tickets.planning_session_id`. Running plan again
while that session is alive is refused with `ticket_planning_active`; the UI
offers to open it instead. Running it after termination replaces the id.

### 2.4 Assign

`POST /tickets/{slug}/plans/{file}/assign` body: `harness`,
`claudeAccountId`, `extra`, `force`.

Spawns a `worker` session with `workspaceMode: worktree`, branch
`opr/<slug>-<NN>` (NN from the plan prefix; a second assignment of the same
plan gets `opr/<slug>-<NN>-2`), `displayName` = `<slug> · NN` truncated. Base
branch is the project's default branch, as today.

Task prompt, built by the daemon:

1. Ticket title and brief.
2. "Read these first": absolute paths (inside the worktree) of `spec.md` and
   the assigned plan.
3. Earlier plans in the ticket, each marked `merged`, `in progress`, or
   `not started`, with paths.
4. "Implement only this phase. Open a pull request when the plan's final
   verification passes."
5. The user's `extra`, verbatim.

Pre-checks, returned as `warnings` on a dry run (`?dryRun=1`, used by the
confirm sheet) and enforced unless `force`:

- an earlier plan is not merged or done → `plan_order`
- the ticket folder has uncommitted changes in the root checkout → `ticket_repo_dirty`
  (the worktree is cut from the committed branch, so the agent would not see them)
- the planning session is still active → `planning_active`
- the plan already has a live assignment → `plan_assigned` (UI asks whether
  to terminate it first; termination uses the existing route)

The response returns the new session id and the assignment row.

### 2.5 Session read model additions

`Session` gains an optional `ticket` object: `{slug, planFile, role}` with role
`planning` or `implementing`, populated by joining the two tables. This is
what the board card badge and the topbar link render. No new session kind is
introduced; sessions stay `worker`.

## 3. Frontend

### 3.1 PLANNED column

Fifth column, leftmost, in `SessionsBoard`, driven by a new `useTicketsQuery`
per visible project and merged across projects like sessions are. Header shows
the count of tickets not `done`/`archived` and a `+` opening the create sheet
(project, title, brief).

Ticket card:

- title, project chip, status line: `Draft`, `Planning` with the planning
  session's activity dot, `Ready`, or `2/4 merged`
- one row per plan in order: `NN`, title, status pill using the board's
  existing status colours; assigned rows show the session's activity dot and
  click through to the session
- footer: `Plan with agent` (or `Open planning session` while it runs), `Open`

Empty state follows `BoardEmptyStates`. Scratch projects show a one-line hint
that tickets need a repo.

### 3.2 Drag and drop

dnd-kit (already a dependency, unused). Draggable: plan rows only. Droppable:
the IDLE/WORKING column, and sidebar project headers of the same project.
During drag, other columns dim; the target shows the dashed highlight already
used for empty lanes. Drop opens the confirm sheet:

- read-only: ticket, plan, project, branch name
- editable: harness, Claude account (defaults from the project's last spawn),
  extra instructions
- warnings from the dry run, each one line
- `Start`; Enter submits; Escape cancels with nothing spawned

`plan_assigned` warning turns `Start` into `Terminate and start`.

### 3.3 Ticket page

Route `/projects/$projectId/tickets/$slug`. Two panes.

Left, fixed width: `ticket.md`, `spec.md`, then plans in order with status
pills, then the planning session entry (activity dot, click opens the
session). A `Plan with agent` button and an archive action live at the bottom.

Right: toolbar with file name, dirty dot, `Edit / Preview / Split` segmented
control, save (Cmd+S). Preview is react-markdown + remark-gfm, styled like
`ReviewMarkdownBody`. Edit is CodeMirror 6 with `@codemirror/lang-markdown`,
line wrapping, the terminal's mono font and the app skin's colours. Split
shows both, preview scroll following the editor's top line. Files reload on
SSE change when the editor is clean; when dirty, a bar offers `Reload` or
`Keep mine`. A 409 on save shows the same bar.

### 3.4 Links from sessions

A session with `ticket` set shows a badge `slug · NN` (or `slug · plan`) on its
board card and in the session topbar; clicking opens the ticket page with that
file selected.

### 3.5 Archive bar

`done` and `archived` tickets appear in the Archive bar beside terminated
sessions, with `Reopen`, which clears `archived_at`. A `done` ticket that is
reopened stays in the bar until a new plan is added, because status is derived.

### 3.6 i18n

All copy goes through the message catalogue; the coverage test extends to the
new keys.

### 3.7 Mobile

Out of scope here. The API is the seam: list, preview and assign first; the
editor later.

## 4. Errors and edge cases

- Unreadable folder or malformed frontmatter: the ticket lists with a warning
  badge; the ticket page shows the parse error above the raw file.
- Linked session deleted: the assignment stays, plan shows `terminated` with
  `Reassign`.
- Ticket folder deleted from the repo: the ticket disappears from the board;
  its rows stay in SQLite and are ignored. Restoring the folder restores it.
- Project root on a non-default branch: create warns (§2.2); assign still cuts
  from the default branch, which may not contain the docs; the dry run reports
  `ticket_not_on_default_branch` as a warning.
- Two projects with the same slug: identity is (project, slug); no conflict.
- Non-Claude harness: `claudeAccountId` is ignored as it is today.

## 5. Testing

Go:

- scanner: layout, ordering, missing prefix, malformed frontmatter, nested
  junk ignored
- status derivation: table test over every `SessionStatus`
- prompt builders for planning and implementing sessions: golden files
- file routes: traversal attempts (`..`, symlinks, absolute paths), stale save
- assignment table: verifier test against real SQLite, latest-row-wins,
  session deletion leaves rows ([[green-gates-from-subagent-builds-are-not-proof]])
- end to end with the `fake` harness: create → plan → assign → session record
  carries `ticket` and branch `opr/<slug>-01`

Frontend (Vitest):

- ticket status → column and pill mapping
- ticket card render for each ticket status
- drag → confirm sheet → assign call with the dry-run warnings shown
- editor: dirty tracking, Cmd+S, 409 bar, SSE reload only when clean
- i18n coverage

## 6. Implementation plans

The work is three implementation plans under `docs/superpowers/plans/`, each
written only after the previous one has merged into `development`
([[land-a-milestone-before-planning-the-next]]), so that each plan targets the
code that actually landed. Each plan must be executable by a fresh session
that has read this spec and nothing else; the pointers below are where that
session starts reading.

### Plan 1: daemon

Scope: everything in §1 and §2 plus §4, with no frontend changes beyond
regenerating the API types.

Deliverables:

- `backend/internal/domain/ticket.go`: `TicketRecord`, `PlanAssignmentRecord`,
  the read models `Ticket` and `Plan` (with derived `TicketStatus` and
  `PlanStatus` enums), and the `SessionTicketRef {Slug, PlanFile, Role}` added
  as an optional field on `domain.Session` (`backend/internal/domain/session.go:125`).
- Migration `backend/internal/storage/sqlite/migrations/0114_tickets.sql`
  creating `tickets` and `plan_assignments` (§1.2) with `change_log`
  triggers matching the existing tables; queries under
  `storage/sqlite/queries/tickets.sql`; regenerate with `npm run sqlc`.
- `backend/internal/service/ticket/`: the scanner (§2.1), frontmatter parser,
  slug derivation, status derivation (§1.3) reusing
  `service/session/status.go` for the session side, and the two prompt
  builders (§2.3, §2.4) placed next to `session_manager/prompt.go` so they
  share the worker preamble.
- Watch: hook the scanner into the workspace file watcher that backs
  `GET /sessions/{id}/workspace/events` (`controllers/sessions.go:258`) or,
  if that watcher is session-scoped, a project-root watcher on
  `.operator/tickets/` only, debounced 250ms.
- Controller `backend/internal/httpd/controllers/tickets.go` with every route
  in §2.1, the dry-run query on assign, and the warning and error codes.
  Routes and schemas added to `httpd/apispec/openapi.yaml`; then
  `npm run api:ts` so `frontend/src/api/schema.ts` matches.
- Spawn integration: planning and implementing sessions go through the
  existing spawn path (`session_manager/manager.go:578-663`), passing the
  extra system prompt text and the built task prompt; branch name override
  via the existing `cfg.Branch` (`adapters/workspace/gitworktree/workspace.go:1368`).
- Session read model: joins so `GET /sessions` and the SSE change stream
  carry `ticket` on sessions that have one.

Acceptance: the Go tests in §5 pass; an end-to-end test with the `fake`
harness creates a ticket, spawns a planning session in place, writes a plan
file by hand, assigns it, and asserts the session has `ticket` set, branch
`opr/<slug>-01`, and the plan reads `working` then `terminated`. `curl`
against a running daemon on port 3002 reproduces the same
([[verify-operator-desktop-through-daemon-api-and-mux]]).

### Plan 2: board and ticket page

Scope: §3.1, §3.3 without editing, §3.4, §3.5, §3.6, plus `Plan with agent`
and the create sheet. No drag, no editor.

Deliverables:

- `frontend/src/renderer/hooks/useTicketsQuery.ts` and `useTicketQuery.ts`
  over the generated client (`lib/api-client.ts`), invalidated from the SSE
  change events in `lib/event-transport.ts` the way sessions are.
- `SessionsBoard.tsx`: a fifth zone `planned` added to
  `boardAttentionZoneOrder` in `lib/session-presentation.ts:190` and to the
  zone labels, rendered by a new `PlannedColumn` and `TicketCard` in
  `components/tickets/`. Column grid becomes five columns.
- `components/tickets/CreateTicketSheet.tsx` (project, title, brief) and
  `PlanWithAgentSheet.tsx` (harness, Claude account, extra), both on shadcn
  primitives from `components/ui/*`, reusing the harness and account pickers
  from the spawn dialog.
- Route `routes/_shell.projects.$projectId_.tickets.$slug.tsx`: file list
  and preview pane. Preview extracts `ReviewMarkdownBody` from
  `SessionInspector.tsx:1744` into `components/MarkdownBody.tsx` and reuses
  it.
- Ticket badge on `SessionCard` (`SessionsBoard.tsx:820`) and in the session
  topbar, linking to the ticket route with the file preselected.
- Archive bar entries for `done` and `archived` tickets with `Reopen`.
- Message keys in every `renderer/i18n/*.json`; the coverage test passes.

Acceptance: Vitest suites in §5 for status mapping, card render, create and
plan sheets; the real app shows a ticket created via curl, its plans, and the
planning session's badge.

### Plan 3: assign and edit

Scope: §3.2 and the editing half of §3.3.

Deliverables:

- dnd-kit context around the board: `PlanRow` draggable, `WorkLaneColumn`
  and sidebar project headers droppable, dimming and the dashed highlight.
- `components/tickets/AssignPlanSheet.tsx`: calls assign with `dryRun=1` on
  open to render warnings, then assign with `force` when confirmed;
  `Terminate and start` uses the existing terminate route first.
- Reassign and mark done actions on plan rows.
- Editor: add `@codemirror/state`, `@codemirror/view`, `@codemirror/lang-markdown`
  and `@codemirror/language`; `components/tickets/MarkdownEditor.tsx` with
  Edit / Preview / Split, Cmd+S to `PUT` with `ifUnmodifiedSince`, dirty
  tracking, the reload-or-keep bar on SSE change and on 409, skin colours
  via the theme tokens used by the terminal.

Acceptance: Vitest suites for drag to sheet to assign call, dry-run warnings,
editor dirty and conflict behaviour; in the real app a drag from PLANNED to
WORKING starts a session whose card carries the badge, and an edit saved
in the app appears in the file on disk.

## Out of scope

- Auto-assigning the next plan when the previous one merges. The data model
  allows it later as a per-ticket toggle; it is deliberately not in v1.
- Importing existing `docs/superpowers/` files as tickets.
- Editing files outside the ticket folder.
- Orchestrator awareness of tickets. The orchestrator keeps its inbox and
  tracker intake; tickets are a user-driven queue.
