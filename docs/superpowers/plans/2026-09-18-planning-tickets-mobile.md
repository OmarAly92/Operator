# Planning Tickets — Mobile Implementation Plan (plan 4 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put planning tickets on the Flutter client: a `Planned` section on the Agents board, a ticket detail screen with a read-only markdown preview, and the plan / assign / review / merge / done / archive actions over the daemon API that plans 1–3 shipped.

**Architecture:** Tickets ride the board snapshot. `SessionsRemoteDataSource.getBoard()` fetches `GET /api/v1/projects/{id}/tickets` for every `single_repo` project after `/sessions` has answered, exactly as it already does for projects and Claude accounts (`packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart:21-51`), so the board keeps one loading state, one emit and the sequential-auth rule. Live refresh comes from the mux WebSocket: the daemon's `ticket_updated` CDC events (`backend/internal/storage/sqlite/migrations/0114_tickets.sql:39-73`) already arrive on the `sessions` channel (`backend/internal/terminal/manager.go:521-534`); the mobile `MuxClient` merely has to count `ticket_` as a board change (`packages/mobile/lib/core/mux/mux_client.dart:199-200`). A new `tickets` feature owns the models, data source, repository, pure presentation logic, the detail screen and the action sheets; the `sessions` feature gains a ticket list, a `Planned` filter, ticket cards and a session badge.

**Tech Stack:** Flutter 3.44.5 (CI pin), `flutter_bloc` Cubits, `equatable`, `dio` through `ApiConsumer`, `mocktail` + `bloc_test`, `flutter_markdown_plus ^1.0.12` (already a dependency, `packages/mobile/pubspec.yaml:77`), `expressive_sheet` + `AppSheetChrome` for every sheet. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` (§1.3 statuses, §2.4 assign, §2.6 roles/review/merge, §3.1 column, §3.3 ticket page preview half, §3.4 session links, §3.5 archive, §3.7 mobile, §4 edge cases, §5 testing). Read it with the three shipped reports: `2026-09-18-planning-tickets-daemon-report.md` ("Curl verification"), `…-board-report.md` and `…-assign-report.md` ("Planner review" sections).

**Baseline commit:** `origin/development` at `6fddf1dc0` or later (plans 1–3 merged; `dffea9c3a` at the time of writing). Run `git fetch origin` first.

**Where the shipped code overrules the spec (and the authoring prompt):**

- §3.7 says "the API is the seam: list, preview and assign first; the editor later". This plan ships list, preview and every action; **no editor on the phone**. `PUT …/file` is not called anywhere in this plan.
- The daemon exposes five assign warnings, not four: `plan_order`, `ticket_repo_dirty`, `ticket_not_on_default_branch`, `planning_active`, `plan_assigned`, in that order (`backend/internal/service/ticket/service.go:543-564`).
- `force: true` does **not** terminate the plan's live session (`service.go:566-621`). "Terminate and start" must `POST /api/v1/sessions/{id}/kill` first, with the session id read from a fresh `GET …/tickets/{slug}` immediately before the kill, and must re-run the dry run right before submitting and stop when a warning appeared that the sheet has not shown yet (plan-3 report, "Planner review").
- The mobile spawn form has no model control and `SpawnSessionParams` has no `model` field (`packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart:3-28`); the desktop's `AgentModelField` reads harness catalogs the phone never fetched. On mobile, **model is a free-text field** (hint `claude-haiku-4-5-20251001`); empty means "use the project's ticket defaults" (`PlanTicketRequest.Model omitempty`, `backend/internal/httpd/controllers/dto.go:1578-1583`).
- An SSE consumer for `GET …/tickets/events` is **forbidden** by `packages/mobile/test/core/no_sse_consumer_test.dart:6-24` (cloudflared buffers SSE). Tickets refresh through the mux `ticket_updated` frames plus the existing 30 s fallback poll (`sessions_cubit.dart:163-170`) and pull-to-refresh. Plain file edits on disk do not produce a CDC event (only the `tickets` and `plan_assignments` tables have triggers), so the detail screen re-reads the selected file on pull-to-refresh and whenever it reloads the ticket.
- The mobile design system has no `Planned` zone; `BoardZone` is the session grouping (`packages/mobile/lib/feature/sessions/logic/agents_view.dart:8-23`). Tickets get their own section rendered **first** (the desktop column is leftmost, spec §3.1), with a `Planned` filter chip inserted after `All` in the fixed chip order from `docs/design/sessions_board/sessions_board.md:63-70`.
- The mobile merge confirmation idiom is `AppDialog.confirm` (`packages/mobile/lib/core/widgets/dialog/app_dialog.dart:13-20`), whose message is capped at four lines (`app_dialog.dart:42-46`). `mergeSummary` may be up to 1000 characters (`MergeReadyRequest.Summary maxLength:"1000"`, `dto.go:1611-1613`), so Merge uses a bottom sheet with a scrollable summary instead.

**Blockers:** none. The session read model's `model` field is the agent's self-report, not the requested model (plan-3 report); the phone displays it as it does today (`session_card.dart:52`) and does not depend on it.

## Global Constraints

- Branch `feat/planning-tickets-mobile` from `development`; worktree **outside** the checkout (`../Operator-planning-tickets-mobile`), never under `.worktrees/` or `.claude/worktrees/` (nested worktrees poison repo-wide search, `CLAUDE.md`).
- Nothing under `backend/` or `frontend/` changes. If the daemon lacks something, write it in the report; do not patch it.
- No code comments in new code (user rule). Doc comments on existing files stay as they are.
- `CLAUDE.md` "Mobile client" conventions, verbatim: Cubit only, never `Bloc` with events; static-only classes are `sealed class X`; no `freezed` or `json_serializable`; models hand-written with all fields nullable and `fromJson` doing the wire→domain mapping; one params class per method under `data/model/params/`, never shared; parameterized paths are static methods on `EndPoints`, interpolating at a call site is forbidden; feature code never imports `flutter_screenutil`; user-facing copy is inline English, no `LocaleKeys`; navigation is `Navigator.of(context)` with `RoutesStrings` names; `GlobalResponse.fromJson(…, withDataKey: false)` for every parse; keep `requestId` from the error envelope; `AppSkin` via `context.skin`; `AppTextStyle.style<Size><Weight>` and `mono*`, sizes 8–13 dominate.
- Sequential auth probing: `getBoard()` awaits `/sessions` alone before any other request (`sessions_remote_data_source.dart:22`; pinned by `test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart:28`). Ticket lists join the fan-out **after** that await.
- Gate after every task, from `packages/mobile`: `flutter analyze` must print `No issues found!` and `flutter test` must pass. Run `flutter pub get` after any pubspec change (this plan makes none).
- No new packages. Every widget uses the existing primitives: `AppSheetChrome`, `showExpressiveSheet`, `SettingsGroup`/`SettingsRow`, `AppTextField`, `PrimaryButton`, `AppPill`, `AppText`, `StatusDot`, `AppContainer`, `AppDialog`, `AppToast`.
- Copy mirrors the desktop English in `frontend/src/renderer/i18n/en.json` (`tickets.*`) character for character: the five warning strings, the plan and ticket status labels, `Plan with agent`, `Open planning session`, `Assign`, `Reassign`, `Terminate and start`, `Start`, `Review`, `Merge`, `Mark done`, `Archive`, `Reopen`, `New ticket`, `Before you start`, `The assignment needs confirmation.`, `Tickets need a single-repository project.`, `Empty fields use the project's ticket defaults.`, `A repeat assignment of the same plan gets a numbered suffix; the session card shows the final branch.`, `request {requestId}`.
- Every failure surface shows `failure.message` and, when present, `request <requestId>` in mono below it (`validationErrors['requestId']`, set by `packages/mobile/lib/core/error_handling/dio_error_handler/dio_error_handler.dart:29-53`).
- Commits: one per task, message in the repo's conventional style, ending with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- `{plan}` in every plan route is the **bare** file name (`dto.go:1510-1512`); the only place that strips `plans/` is `EndPoints.ticketPlan`.

## File map

New, under `packages/mobile/lib/feature/tickets/`:

| File | Responsibility |
|---|---|
| `data/model/plan_model.dart` | `PlanModel` (one `PlanView`) |
| `data/model/ticket_model.dart` | `TicketModel` (one `TicketView`) |
| `data/model/ticket_file_model.dart` | `TicketFileModel` (`TicketFileResponse`) |
| `data/model/ticket_action_results.dart` | `CreateTicketResult`, `AssignPlanResult`, `ReviewPlanResult` |
| `data/model/params/create_ticket_params.dart` | `CreateTicketParams` |
| `data/model/params/plan_ticket_params.dart` | `PlanTicketParams` |
| `data/model/params/assign_plan_params.dart` | `AssignPlanParams` (incl. `dryRun`, `force`) |
| `data/model/params/review_plan_params.dart` | `ReviewPlanParams` |
| `data/data_source/tickets_remote_data_source.dart` | `TicketsRemoteDataSource` + `Imp` |
| `data/repository/tickets_repository.dart` | `TicketsRepository` + `Imp` (network guard, `Result`) |
| `logic/ticket_status.dart` | plan/ticket status → `StatusVisual`, archive predicates |
| `logic/ticket_presentation.dart` | `planNumber`, `planBranchName`, `ticketBadgeLabel`, `ticketFileGroups`, `failureRequestId` |
| `logic/frontmatter.dart` | `Frontmatter`, `splitFrontmatter` (Dart port of `ticket-presentation.ts:138-160`) |
| `logic/assign_rules.dart` | warning labels, `needsForce`, `canAssignPlan`, `canReviewPlan`, `canMergePlan`, `canMarkPlanDone`, `newAssignWarnings`, `assignButtonLabel` |
| `presentation/ticket_actions/logic/ticket_actions_cubit.dart` + `ticket_actions_state.dart` | create / plan / review / merge / done / archive / unarchive |
| `presentation/ticket_actions/logic/assign_plan_cubit.dart` + `assign_plan_state.dart` | dry run → warnings → re-check → kill → assign |
| `presentation/ticket_actions/ui/widgets/ticket_failure_text.dart` | message + `request <id>` |
| `presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart` | Agent / Account / Model / Extra instructions group (wraps `SpawnCubit`) |
| `presentation/ticket_actions/ui/widgets/create_ticket_sheet.dart` | `New ticket` |
| `presentation/ticket_actions/ui/widgets/ticket_actions_sheet.dart` | ticket-level: Plan / Open planning session / Open / Archive / Reopen |
| `presentation/ticket_actions/ui/widgets/plan_ticket_sheet.dart` | `Plan with agent` |
| `presentation/ticket_actions/ui/widgets/assign_plan_sheet.dart` | `Assign` / `Reassign` |
| `presentation/ticket_actions/ui/widgets/review_plan_sheet.dart` | `Review` |
| `presentation/ticket_actions/ui/widgets/merge_plan_sheet.dart` | `Merge` confirmation with `mergeSummary` |
| `presentation/ticket_actions/ui/widgets/plan_actions_sheet.dart` | plan-level: Open session / Assign|Reassign / Review / Merge / Mark done |
| `presentation/ticket_card/ui/ticket_card.dart` | board card (title, project, status, plan rows, footer) |
| `presentation/ticket_card/ui/widgets/plan_row.dart` | one plan row |
| `presentation/ticket_detail_screen/logic/ticket_detail_cubit.dart` + `ticket_detail_state.dart` | ticket + selected file, mux-driven reload |
| `presentation/ticket_detail_screen/ui/ticket_detail_screen.dart` | screen shell |
| `presentation/ticket_detail_screen/ui/widgets/ticket_detail_header.dart` | title, brief, status, warning banner |
| `presentation/ticket_detail_screen/ui/widgets/ticket_file_list.dart` | docs, plans, kickoffs, planning session row |
| `presentation/ticket_detail_screen/ui/widgets/frontmatter_block.dart` | key/value block |
| `presentation/ticket_detail_screen/ui/widgets/ticket_markdown_preview.dart` | `MarkdownBody` styled like `block_markdown.dart` |

Modified:

| File | Change |
|---|---|
| `lib/core/api/api_request_helpers/end_points.dart` | ticket routes |
| `lib/core/app_routes/routes_strings.dart`, `app_router.dart` | `RoutesStrings.ticket` |
| `lib/core/utils/service_locator.dart` | tickets data source, repository, cubits |
| `lib/core/mux/mux_client.dart:199-200` | `ticket_` counts as a board change |
| `lib/feature/sessions/data/model/session_ticket_ref.dart` (new), `session_model.dart` | `SessionModel.ticket` |
| `lib/feature/sessions/data/model/board_snapshot.dart` | `tickets` |
| `lib/feature/sessions/data/data_source/sessions_remote_data_source.dart` | `_fetchTickets` |
| `lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart` | `tickets`, `visibleTickets`, `sessionsById` |
| `lib/feature/sessions/logic/sessions_filter.dart` | `SessionsFilter.planned`, `sessionsFilterShowsPlanned` |
| `lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart` | optional `trailing` |
| `lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart` | Planned section, archive tickets, hint |
| `lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart` | ticket badge |
| `lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:24-51` (`TerminalArgs`), `ui/widgets/terminal_chat_header.dart:135-146`, `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:101-110` | ticket badge in the session header |

Tests mirror `lib/` under `packages/mobile/test/` (`test/feature/tickets/...`, plus the touched `test/core/...` and `test/feature/sessions/...` files).

---

### Task 1: Ticket endpoints

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart:1-52`
- Test: `packages/mobile/test/core/api/end_points_test.dart`

**Interfaces:**
- Consumes: `EndPoints.projects` (`end_points.dart:4`), the `Uri.encodeComponent` idiom (`end_points.dart:18-21`).
- Produces: `EndPoints.projectTickets(projectId)`, `EndPoints.ticket(projectId, slug)`, `EndPoints.ticketFile(projectId, slug)`, `EndPoints.ticketPlanning(projectId, slug)`, `EndPoints.ticketArchive(projectId, slug)`, `EndPoints.ticketUnarchive(projectId, slug)`, `EndPoints.ticketPlan(projectId, slug, planFile)`, `EndPoints.ticketPlanAssign/Done/Review/MergeReady/Merge(projectId, slug, planFile)`, `EndPoints.bareTicketPlanFile(planFile)`. Routes: `backend/internal/httpd/controllers/tickets.go:41-57`.

- [ ] **Step 1: Write the failing test**

Append to `test/core/api/end_points_test.dart` inside `main()`:

```dart
  group('ticket endpoints', () {
    test('address the daemon ticket routes', () {
      expect(EndPoints.projectTickets('repo'), '/api/v1/projects/repo/tickets');
      expect(EndPoints.ticket('repo', 'search-page'), '/api/v1/projects/repo/tickets/search-page');
      expect(EndPoints.ticketFile('repo', 'search-page'), '/api/v1/projects/repo/tickets/search-page/file');
      expect(EndPoints.ticketPlanning('repo', 'search-page'), '/api/v1/projects/repo/tickets/search-page/plan');
      expect(EndPoints.ticketArchive('repo', 'search-page'), '/api/v1/projects/repo/tickets/search-page/archive');
      expect(EndPoints.ticketUnarchive('repo', 'search-page'), '/api/v1/projects/repo/tickets/search-page/unarchive');
    });

    test('plan routes take the bare plan file name and strip a leading plans/', () {
      expect(
        EndPoints.ticketPlanAssign('repo', 'search-page', 'plans/01-daemon.md'),
        '/api/v1/projects/repo/tickets/search-page/plans/01-daemon.md/assign',
      );
      expect(
        EndPoints.ticketPlanAssign('repo', 'search-page', '01-daemon.md'),
        '/api/v1/projects/repo/tickets/search-page/plans/01-daemon.md/assign',
      );
      expect(EndPoints.ticketPlanDone('repo', 's', 'plans/02-ui.md'), '/api/v1/projects/repo/tickets/s/plans/02-ui.md/done');
      expect(EndPoints.ticketPlanReview('repo', 's', '02-ui.md'), '/api/v1/projects/repo/tickets/s/plans/02-ui.md/review');
      expect(EndPoints.ticketPlanMergeReady('repo', 's', '02-ui.md'), '/api/v1/projects/repo/tickets/s/plans/02-ui.md/merge-ready');
      expect(EndPoints.ticketPlanMerge('repo', 's', '02-ui.md'), '/api/v1/projects/repo/tickets/s/plans/02-ui.md/merge');
      expect(EndPoints.bareTicketPlanFile('plans/01-daemon.md'), '01-daemon.md');
      expect(EndPoints.bareTicketPlanFile('01-daemon.md'), '01-daemon.md');
    });

    test('escape identifiers so a slash cannot spoof a route', () {
      expect(EndPoints.ticket('a/b', 'c d'), '/api/v1/projects/a%2Fb/tickets/c%20d');
      expect(EndPoints.ticketPlan('repo', 's', 'plans/x y.md'), '/api/v1/projects/repo/tickets/s/plans/x%20y.md');
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/api/end_points_test.dart`
Expected: compile error, `The getter 'projectTickets' isn't defined for the type 'EndPoints'`.

- [ ] **Step 3: Add the endpoints**

Insert before `static String _session(...)` at `end_points.dart:51`:

```dart
  static String projectTickets(String projectId) => '$projects/${Uri.encodeComponent(projectId)}/tickets';
  static String ticket(String projectId, String slug) =>
      '${projectTickets(projectId)}/${Uri.encodeComponent(slug)}';
  static String ticketFile(String projectId, String slug) => '${ticket(projectId, slug)}/file';
  static String ticketPlanning(String projectId, String slug) => '${ticket(projectId, slug)}/plan';
  static String ticketArchive(String projectId, String slug) => '${ticket(projectId, slug)}/archive';
  static String ticketUnarchive(String projectId, String slug) => '${ticket(projectId, slug)}/unarchive';

  static String bareTicketPlanFile(String planFile) =>
      planFile.startsWith('plans/') ? planFile.substring('plans/'.length) : planFile;

  static String ticketPlan(String projectId, String slug, String planFile) =>
      '${ticket(projectId, slug)}/plans/${Uri.encodeComponent(bareTicketPlanFile(planFile))}';
  static String ticketPlanAssign(String projectId, String slug, String planFile) =>
      '${ticketPlan(projectId, slug, planFile)}/assign';
  static String ticketPlanDone(String projectId, String slug, String planFile) =>
      '${ticketPlan(projectId, slug, planFile)}/done';
  static String ticketPlanReview(String projectId, String slug, String planFile) =>
      '${ticketPlan(projectId, slug, planFile)}/review';
  static String ticketPlanMergeReady(String projectId, String slug, String planFile) =>
      '${ticketPlan(projectId, slug, planFile)}/merge-ready';
  static String ticketPlanMerge(String projectId, String slug, String planFile) =>
      '${ticketPlan(projectId, slug, planFile)}/merge';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/api/end_points_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib/core/api/api_request_helpers/end_points.dart packages/mobile/test/core/api/end_points_test.dart
git commit -m "feat(mobile): ticket endpoints with bare plan file names

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Ticket models and the session ticket link

**Files:**
- Create: `packages/mobile/lib/feature/tickets/data/model/plan_model.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/ticket_model.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/ticket_file_model.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/ticket_action_results.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/session_ticket_ref.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/model/session_model.dart:5-75`
- Test: `packages/mobile/test/feature/tickets/data/model/ticket_models_test.dart`
- Test: `packages/mobile/test/feature/sessions/data/model/board_models_test.dart` (append)

**Interfaces:**
- Consumes: `SessionModel.fromJson` (`session_model.dart:46-67`), `Equatable`.
- Produces: `PlanModel{file, order, title, status, sessionId, reviewerSessionId, mergeSummary, kickoffFile, unordered, warning}`, `TicketModel{projectId, slug, title, brief, status, planningSessionId, plans, files, warning, createdAt, archivedAt}` with `TicketModel.fromJson` and `TicketModel.listFromJson(Map)`, `TicketFileModel{path, content, modifiedAt}`, `SessionTicketRef{slug, planFile, role}` with `static SessionTicketRef? fromJson(Object?)`, `SessionModel.ticket`, `CreateTicketResult{ticket, warnings}`, `AssignPlanResult{warnings, session}`, `ReviewPlanResult{session, spawned}`. Wire shapes: `backend/internal/httpd/controllers/dto.go:1522-1547, 1557-1561, 1568-1571, 1593-1596, 1606-1609`; `SessionTicketRef` at `backend/internal/domain/ticket.go:66-70`.

- [ ] **Step 1: Write the failing tests**

`test/feature/tickets/data/model/ticket_models_test.dart` — the JSON is the daemon report's curl transcript (`docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md`, "Curl verification") plus the plan-3 report's session `ticket` line:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_ticket_ref.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

const Map<String, dynamic> _createdTicket = {
  'ticket': {
    'projectId': 'repo',
    'slug': 'smoke-ticket',
    'title': 'Smoke ticket',
    'brief': 'daemon smoke',
    'status': 'draft',
    'plans': <dynamic>[],
    'files': ['ticket.md', 'spec.md'],
    'createdAt': '2026-09-18T01:21:37.474578Z',
  },
  'warnings': <dynamic>[],
};

const Map<String, dynamic> _assignedTicket = {
  'projectId': 'repo',
  'slug': 'search-page',
  'title': 'Search page',
  'status': 'in_progress',
  'planningSessionId': 'repo-3',
  'plans': [
    {
      'file': 'plans/01-index.md',
      'order': 1,
      'title': 'Index',
      'status': 'working',
      'sessionId': 'repo-4',
      'kickoffFile': 'plans/01-index.kickoff.md',
    },
    {
      'file': 'plans/02-ui.md',
      'order': 2,
      'title': 'UI',
      'status': 'awaiting_merge',
      'sessionId': 'repo-5',
      'reviewerSessionId': 'repo-3',
      'mergeSummary': 'Two files, tests green.',
    },
    {'file': 'plans/notes.md', 'order': 0, 'title': 'Notes', 'status': 'todo', 'unordered': true, 'warning': 'no NN- prefix'},
  ],
  'files': ['ticket.md', 'spec.md', 'plans/01-index.md', 'plans/01-index.kickoff.md', 'plans/02-ui.md', 'plans/notes.md'],
  'warning': '',
  'createdAt': '2026-09-18T10:00:00Z',
  'archivedAt': null,
};

void main() {
  group('TicketModel', () {
    test('parses the create response shape from the daemon report', () {
      final result = CreateTicketResult.fromJson(_createdTicket);
      expect(result.ticket?.slug, 'smoke-ticket');
      expect(result.ticket?.status, 'draft');
      expect(result.ticket?.plans, isEmpty);
      expect(result.ticket?.files, ['ticket.md', 'spec.md']);
      expect(result.ticket?.brief, 'daemon smoke');
      expect(result.warnings, isEmpty);
    });

    test('parses plans with every optional field present or absent', () {
      final ticket = TicketModel.fromJson(_assignedTicket);
      expect(ticket.planningSessionId, 'repo-3');
      expect(ticket.plans, hasLength(3));
      final first = ticket.plans[0];
      expect(first.file, 'plans/01-index.md');
      expect(first.order, 1);
      expect(first.status, 'working');
      expect(first.sessionId, 'repo-4');
      expect(first.kickoffFile, 'plans/01-index.kickoff.md');
      expect(first.reviewerSessionId, isNull);
      expect(first.unordered, isNull);
      final second = ticket.plans[1];
      expect(second.reviewerSessionId, 'repo-3');
      expect(second.mergeSummary, 'Two files, tests green.');
      final third = ticket.plans[2];
      expect(third.unordered, isTrue);
      expect(third.warning, 'no NN- prefix');
      expect(ticket.archivedAt, isNull);
    });

    test('lists tickets from the {tickets: [...]} envelope and tolerates an empty body', () {
      expect(TicketModel.listFromJson({'tickets': [_assignedTicket]}).single.slug, 'search-page');
      expect(TicketModel.listFromJson(const {}), isEmpty);
    });

    test('is value-equal', () {
      expect(TicketModel.fromJson(_assignedTicket), TicketModel.fromJson(_assignedTicket));
      expect(PlanModel.fromJson(const {'file': 'plans/01.md'}), const PlanModel(file: 'plans/01.md'));
    });
  });

  test('TicketFileModel parses the file response', () {
    final file = TicketFileModel.fromJson(const {
      'path': 'spec.md',
      'content': '# Smoke ticket\n',
      'modifiedAt': '2026-09-18T01:21:37.475141673Z',
    });
    expect(file.path, 'spec.md');
    expect(file.content, '# Smoke ticket\n');
    expect(file.modifiedAt, '2026-09-18T01:21:37.475141673Z');
  });

  group('SessionTicketRef', () {
    test('parses the session ticket link the plan-3 report saw', () {
      final session = SessionModel.fromJson(const {
        'id': 'repo-4',
        'projectId': 'repo',
        'branch': 'opr/search-page-01',
        'ticket': {'slug': 'search-page', 'planFile': 'plans/01-index.md', 'role': 'implementing'},
      });
      expect(session.ticket, const SessionTicketRef(slug: 'search-page', planFile: 'plans/01-index.md', role: 'implementing'));
    });

    test('is null when the session carries no ticket or a malformed one', () {
      expect(SessionModel.fromJson(const {'id': 'a'}).ticket, isNull);
      expect(SessionModel.fromJson(const {'id': 'a', 'ticket': 'nope'}).ticket, isNull);
      expect(SessionTicketRef.fromJson(const {'slug': 'x', 'role': 'planning'}), const SessionTicketRef(slug: 'x', role: 'planning'));
    });
  });

  group('action results', () {
    test('AssignPlanResult carries warnings with or without a session', () {
      expect(AssignPlanResult.fromJson(const {'warnings': ['ticket_repo_dirty']}).warnings, ['ticket_repo_dirty']);
      final started = AssignPlanResult.fromJson(const {
        'warnings': <dynamic>[],
        'session': {'id': 'repo-9', 'projectId': 'repo', 'branch': 'opr/search-page-01'},
      });
      expect(started.session?.id, 'repo-9');
      expect(AssignPlanResult.fromJson(const {}).warnings, isEmpty);
    });

    test('ReviewPlanResult carries the session and the spawned flag', () {
      final result = ReviewPlanResult.fromJson(const {'session': {'id': 'repo-3'}, 'spawned': false});
      expect(result.session?.id, 'repo-3');
      expect(result.spawned, isFalse);
    });
  });
}
```

Append to `test/feature/sessions/data/model/board_models_test.dart` inside `main()`:

```dart
  test('SessionModel props include the ticket link', () {
    const a = SessionModel(id: 's', ticket: SessionTicketRef(slug: 'x', role: 'planning'));
    const b = SessionModel(id: 's', ticket: SessionTicketRef(slug: 'y', role: 'planning'));
    expect(a == b, isFalse);
  });
```

(add `import 'package:operator_mobile/feature/sessions/data/model/session_ticket_ref.dart';` to that file's imports).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/tickets/data/model/ticket_models_test.dart test/feature/sessions/data/model/board_models_test.dart`
Expected: compile errors, the imports do not resolve.

- [ ] **Step 3: Write the models**

`lib/feature/tickets/data/model/plan_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class PlanModel extends Equatable {
  const PlanModel({
    this.file,
    this.order,
    this.title,
    this.status,
    this.sessionId,
    this.reviewerSessionId,
    this.mergeSummary,
    this.kickoffFile,
    this.unordered,
    this.warning,
  });

  final String? file;
  final int? order;
  final String? title;
  final String? status;
  final String? sessionId;
  final String? reviewerSessionId;
  final String? mergeSummary;
  final String? kickoffFile;
  final bool? unordered;
  final String? warning;

  factory PlanModel.fromJson(Map<String, dynamic> json) => PlanModel(
    file: json['file'] as String?,
    order: (json['order'] as num?)?.toInt(),
    title: json['title'] as String?,
    status: json['status'] as String?,
    sessionId: json['sessionId'] as String?,
    reviewerSessionId: json['reviewerSessionId'] as String?,
    mergeSummary: json['mergeSummary'] as String?,
    kickoffFile: json['kickoffFile'] as String?,
    unordered: json['unordered'] as bool?,
    warning: json['warning'] as String?,
  );

  @override
  List<Object?> get props => [file, order, title, status, sessionId, reviewerSessionId, mergeSummary, kickoffFile, unordered, warning];
}
```

`lib/feature/tickets/data/model/ticket_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';

class TicketModel extends Equatable {
  const TicketModel({
    this.projectId,
    this.slug,
    this.title,
    this.brief,
    this.status,
    this.planningSessionId,
    this.plans = const [],
    this.files = const [],
    this.warning,
    this.createdAt,
    this.archivedAt,
  });

  final String? projectId;
  final String? slug;
  final String? title;
  final String? brief;
  final String? status;
  final String? planningSessionId;
  final List<PlanModel> plans;
  final List<String> files;
  final String? warning;
  final String? createdAt;
  final String? archivedAt;

  factory TicketModel.fromJson(Map<String, dynamic> json) => TicketModel(
    projectId: json['projectId'] as String?,
    slug: json['slug'] as String?,
    title: json['title'] as String?,
    brief: json['brief'] as String?,
    status: json['status'] as String?,
    planningSessionId: json['planningSessionId'] as String?,
    plans: (json['plans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanModel.fromJson)
        .toList(),
    files: (json['files'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    warning: json['warning'] as String?,
    createdAt: json['createdAt'] as String?,
    archivedAt: json['archivedAt'] as String?,
  );

  static List<TicketModel> listFromJson(Map<String, dynamic> json) => (json['tickets'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(TicketModel.fromJson)
      .toList();

  @override
  List<Object?> get props => [projectId, slug, title, brief, status, planningSessionId, plans, files, warning, createdAt, archivedAt];
}
```

`lib/feature/tickets/data/model/ticket_file_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class TicketFileModel extends Equatable {
  const TicketFileModel({this.path, this.content, this.modifiedAt});

  final String? path;
  final String? content;
  final String? modifiedAt;

  factory TicketFileModel.fromJson(Map<String, dynamic> json) => TicketFileModel(
    path: json['path'] as String?,
    content: json['content'] as String?,
    modifiedAt: json['modifiedAt'] as String?,
  );

  @override
  List<Object?> get props => [path, content, modifiedAt];
}
```

`lib/feature/tickets/data/model/ticket_action_results.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

List<String> _strings(Object? raw) => (raw as List<dynamic>? ?? const []).whereType<String>().toList();

SessionModel? _session(Object? raw) => raw is Map<String, dynamic> ? SessionModel.fromJson(raw) : null;

class CreateTicketResult extends Equatable {
  const CreateTicketResult({this.ticket, this.warnings = const []});

  final TicketModel? ticket;
  final List<String> warnings;

  factory CreateTicketResult.fromJson(Map<String, dynamic> json) => CreateTicketResult(
    ticket: json['ticket'] is Map<String, dynamic> ? TicketModel.fromJson(json['ticket'] as Map<String, dynamic>) : null,
    warnings: _strings(json['warnings']),
  );

  @override
  List<Object?> get props => [ticket, warnings];
}

class AssignPlanResult extends Equatable {
  const AssignPlanResult({this.warnings = const [], this.session});

  final List<String> warnings;
  final SessionModel? session;

  factory AssignPlanResult.fromJson(Map<String, dynamic> json) =>
      AssignPlanResult(warnings: _strings(json['warnings']), session: _session(json['session']));

  @override
  List<Object?> get props => [warnings, session];
}

class ReviewPlanResult extends Equatable {
  const ReviewPlanResult({this.session, this.spawned});

  final SessionModel? session;
  final bool? spawned;

  factory ReviewPlanResult.fromJson(Map<String, dynamic> json) =>
      ReviewPlanResult(session: _session(json['session']), spawned: json['spawned'] as bool?);

  @override
  List<Object?> get props => [session, spawned];
}
```

`lib/feature/sessions/data/model/session_ticket_ref.dart`:

```dart
import 'package:equatable/equatable.dart';

class SessionTicketRef extends Equatable {
  const SessionTicketRef({this.slug, this.planFile, this.role});

  final String? slug;
  final String? planFile;
  final String? role;

  static SessionTicketRef? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return SessionTicketRef(
      slug: json['slug'] as String?,
      planFile: json['planFile'] as String?,
      role: json['role'] as String?,
    );
  }

  @override
  List<Object?> get props => [slug, planFile, role];
}
```

`session_model.dart`: add `import 'package:operator_mobile/feature/sessions/data/model/session_ticket_ref.dart';`, a constructor parameter `this.ticket,` after `this.model,`, the field `final SessionTicketRef? ticket;`, the `fromJson` line `ticket: SessionTicketRef.fromJson(json['ticket']),` after `model:`, and `ticket` at the end of `props`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets test/feature/sessions/data/model`
Expected: all pass.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib/feature/tickets/data/model packages/mobile/lib/feature/sessions/data/model packages/mobile/test/feature/tickets packages/mobile/test/feature/sessions/data/model
git commit -m "feat(mobile): ticket, plan and file models; sessions parse their ticket link

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Params, remote data source and repository

**Files:**
- Create: `packages/mobile/lib/feature/tickets/data/model/params/create_ticket_params.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/params/plan_ticket_params.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/params/assign_plan_params.dart`
- Create: `packages/mobile/lib/feature/tickets/data/model/params/review_plan_params.dart`
- Create: `packages/mobile/lib/feature/tickets/data/data_source/tickets_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/tickets/data/repository/tickets_repository.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (register after `SessionsRemoteDataSource`, `service_locator.dart:153-155`)
- Test: `packages/mobile/test/feature/tickets/data/data_source/tickets_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/tickets/data/repository/tickets_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer.get/post` (`api_consumer.dart:6-22`), `GlobalResponse.fromJson(withDataKey: false)`, `Result`/`FutureResult` (`core/helpers/result/result.dart`), `NetworkStatus.isConnected`, `ServerFailure.noNetwork()`, `handleDioError` (`dio_error_handler.dart:5-54`; it puts the envelope `code` in `Failure.apiStatus` and `details` + `requestId` in `Failure.validationErrors`).
- Produces: the four params classes (`toJson()`), `TicketsRemoteDataSource` and `TicketsRepository` with these methods: `listTickets(String projectId)`, `getTicket(String projectId, String slug)`, `readFile(String projectId, String slug, String path)`, `createTicket(CreateTicketParams)`, `planTicket(PlanTicketParams)`, `assignPlan(AssignPlanParams)`, `reviewPlan(ReviewPlanParams)`, `markPlanDone(projectId, slug, planFile)`, `mergePlan(projectId, slug, planFile)`, `archiveTicket(projectId, slug)`, `unarchiveTicket(projectId, slug)`. Id-only methods take plain strings like `kill(String id)` does (`sessions_remote_data_source.dart:11-12`); the four methods with bodies each get their own params class.

- [ ] **Step 1: Write the failing data-source test**

`test/feature/tickets/data/data_source/tickets_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/tickets/data/data_source/tickets_remote_data_source.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _json(Map<String, dynamic> body, {int status = 200}) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body, statusCode: status);

void main() {
  late _MockApiConsumer api;
  late TicketsRemoteDataSource dataSource;

  setUp(() {
    api = _MockApiConsumer();
    dataSource = TicketsRemoteDataSourceImp(api);
  });

  test('lists tickets from the project route', () async {
    when(() => api.get(EndPoints.projectTickets('repo'))).thenAnswer(
      (_) async => _json({
        'tickets': [
          {'projectId': 'repo', 'slug': 'smoke-ticket', 'status': 'draft', 'plans': <dynamic>[], 'files': ['ticket.md', 'spec.md']},
        ],
      }),
    );
    final tickets = (await dataSource.listTickets('repo')).data!;
    expect(tickets.single.slug, 'smoke-ticket');
  });

  test('gets one ticket and reads a file by query path', () async {
    when(() => api.get(EndPoints.ticket('repo', 'smoke-ticket')))
        .thenAnswer((_) async => _json({'ticket': {'projectId': 'repo', 'slug': 'smoke-ticket', 'status': 'draft'}}));
    when(() => api.get(EndPoints.ticketFile('repo', 'smoke-ticket'), queryParameters: {'path': 'spec.md'}))
        .thenAnswer((_) async => _json({'path': 'spec.md', 'content': '# Smoke ticket\n', 'modifiedAt': '2026-09-18T01:21:37.475141673Z'}));

    expect((await dataSource.getTicket('repo', 'smoke-ticket')).data?.slug, 'smoke-ticket');
    expect((await dataSource.readFile('repo', 'smoke-ticket', 'spec.md')).data?.content, '# Smoke ticket\n');
  });

  test('creates a ticket with title and brief only', () async {
    when(() => api.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _json({'ticket': {'slug': 'smoke-ticket', 'status': 'draft'}, 'warnings': <dynamic>[]}, status: 201),
    );
    final result = await dataSource.createTicket(const CreateTicketParams(projectId: 'repo', title: 'Smoke ticket', brief: 'daemon smoke'));
    expect(result.data?.ticket?.slug, 'smoke-ticket');
    final body = verify(() => api.post(EndPoints.projectTickets('repo'), body: captureAny(named: 'body'))).captured.single;
    expect(body, {'title': 'Smoke ticket', 'brief': 'daemon smoke'});
  });

  test('plan omits empty fields and parses the session view', () async {
    when(() => api.post(any(), body: any(named: 'body'))).thenAnswer((_) async => _json({'id': 'repo-3', 'projectId': 'repo'}, status: 201));
    final result = await dataSource.planTicket(const PlanTicketParams(projectId: 'repo', slug: 'smoke-ticket', harness: 'claude-code'));
    expect(result.data?.id, 'repo-3');
    final body = verify(() => api.post(EndPoints.ticketPlanning('repo', 'smoke-ticket'), body: captureAny(named: 'body'))).captured.single;
    expect(body, {'harness': 'claude-code'});
  });

  test('assign sends dryRun as a query flag and force only when set', () async {
    when(() => api.post(any(), body: any(named: 'body'), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _json({'warnings': ['ticket_repo_dirty']}));
    final dry = await dataSource.assignPlan(const AssignPlanParams(projectId: 'repo', slug: 's', planFile: 'plans/01-index.md', dryRun: true));
    expect(dry.data?.warnings, ['ticket_repo_dirty']);
    verify(() => api.post(EndPoints.ticketPlanAssign('repo', 's', 'plans/01-index.md'), body: {}, queryParameters: {'dryRun': '1'})).called(1);

    when(() => api.post(any(), body: any(named: 'body'), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _json({'warnings': ['ticket_repo_dirty'], 'session': {'id': 'repo-9'}}, status: 201));
    final started = await dataSource.assignPlan(const AssignPlanParams(
      projectId: 'repo', slug: 's', planFile: 'plans/01-index.md', harness: 'claude-code', model: 'claude-haiku-4-5-20251001', force: true,
    ));
    expect(started.data?.session?.id, 'repo-9');
    verify(() => api.post(
      EndPoints.ticketPlanAssign('repo', 's', 'plans/01-index.md'),
      body: {'harness': 'claude-code', 'model': 'claude-haiku-4-5-20251001', 'force': true},
      queryParameters: null,
    )).called(1);
  });

  test('review sends the reviewer choice; done, merge, archive and unarchive post to their routes', () async {
    when(() => api.post(any(), body: any(named: 'body'))).thenAnswer((_) async => _json({'session': {'id': 'repo-3'}, 'spawned': false}));
    final review = await dataSource.reviewPlan(const ReviewPlanParams(projectId: 'repo', slug: 's', planFile: '02-ui.md', reviewer: 'planner'));
    expect(review.data?.spawned, isFalse);
    verify(() => api.post(EndPoints.ticketPlanReview('repo', 's', '02-ui.md'), body: {'reviewer': 'planner'})).called(1);

    when(() => api.post(any())).thenAnswer((_) async => _json({'ticket': {'slug': 's', 'status': 'done'}}));
    expect((await dataSource.markPlanDone('repo', 's', '02-ui.md')).data?.status, 'done');
    expect((await dataSource.mergePlan('repo', 's', '02-ui.md')).data?.slug, 's');
    expect((await dataSource.archiveTicket('repo', 's')).data?.slug, 's');
    expect((await dataSource.unarchiveTicket('repo', 's')).data?.slug, 's');
    verifyInOrder([
      () => api.post(EndPoints.ticketPlanDone('repo', 's', '02-ui.md')),
      () => api.post(EndPoints.ticketPlanMerge('repo', 's', '02-ui.md')),
      () => api.post(EndPoints.ticketArchive('repo', 's')),
      () => api.post(EndPoints.ticketUnarchive('repo', 's')),
    ]);
  });

  test('a 409 TICKET_ASSIGN_BLOCKED surfaces its warnings and requestId through the failure', () async {
    final error = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 409,
        data: {
          'error': 'conflict',
          'code': 'TICKET_ASSIGN_BLOCKED',
          'message': 'Assignment needs confirmation',
          'requestId': 'req-42',
          'details': {'warnings': ['plan_assigned']},
        },
      ),
    );
    when(() => api.post(any(), body: any(named: 'body'), queryParameters: any(named: 'queryParameters'))).thenThrow(handleDioError(error));

    expect(
      () => dataSource.assignPlan(const AssignPlanParams(projectId: 'repo', slug: 's', planFile: '01.md')),
      throwsA(isA<ServerFailure<dynamic>>()
          .having((f) => f.statusCode, 'statusCode', 409)
          .having((f) => f.apiStatus, 'apiStatus', 'TICKET_ASSIGN_BLOCKED')
          .having((f) => f.message, 'message', 'Assignment needs confirmation')
          .having((f) => (f.validationErrors as Map<String, dynamic>)['warnings'], 'warnings', ['plan_assigned'])
          .having((f) => (f.validationErrors as Map<String, dynamic>)['requestId'], 'requestId', 'req-42')),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/data/data_source/tickets_remote_data_source_test.dart`
Expected: compile errors (missing imports).

- [ ] **Step 3: Write the params, data source and repository**

`lib/feature/tickets/data/model/params/create_ticket_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class CreateTicketParams extends Equatable {
  const CreateTicketParams({required this.projectId, required this.title, this.brief});

  final String projectId;
  final String title;
  final String? brief;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (brief != null && brief!.isNotEmpty) 'brief': brief,
  };

  @override
  List<Object?> get props => [projectId, title, brief];
}
```

`lib/feature/tickets/data/model/params/plan_ticket_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class PlanTicketParams extends Equatable {
  const PlanTicketParams({
    required this.projectId,
    required this.slug,
    this.harness,
    this.model,
    this.claudeAccountId,
    this.extra,
  });

  final String projectId;
  final String slug;
  final String? harness;
  final String? model;
  final String? claudeAccountId;
  final String? extra;

  Map<String, dynamic> toJson() => {
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (claudeAccountId != null && claudeAccountId!.isNotEmpty) 'claudeAccountId': claudeAccountId,
    if (extra != null && extra!.isNotEmpty) 'extra': extra,
  };

  @override
  List<Object?> get props => [projectId, slug, harness, model, claudeAccountId, extra];
}
```

`lib/feature/tickets/data/model/params/assign_plan_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class AssignPlanParams extends Equatable {
  const AssignPlanParams({
    required this.projectId,
    required this.slug,
    required this.planFile,
    this.harness,
    this.model,
    this.claudeAccountId,
    this.extra,
    this.force = false,
    this.dryRun = false,
  });

  final String projectId;
  final String slug;
  final String planFile;
  final String? harness;
  final String? model;
  final String? claudeAccountId;
  final String? extra;
  final bool force;
  final bool dryRun;

  Map<String, dynamic> toJson() => {
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (claudeAccountId != null && claudeAccountId!.isNotEmpty) 'claudeAccountId': claudeAccountId,
    if (extra != null && extra!.isNotEmpty) 'extra': extra,
    if (force) 'force': true,
  };

  Map<String, dynamic>? get queryParameters => dryRun ? const {'dryRun': '1'} : null;

  AssignPlanParams copyWith({bool? force, bool? dryRun}) => AssignPlanParams(
    projectId: projectId,
    slug: slug,
    planFile: planFile,
    harness: harness,
    model: model,
    claudeAccountId: claudeAccountId,
    extra: extra,
    force: force ?? this.force,
    dryRun: dryRun ?? this.dryRun,
  );

  @override
  List<Object?> get props => [projectId, slug, planFile, harness, model, claudeAccountId, extra, force, dryRun];
}
```

`lib/feature/tickets/data/model/params/review_plan_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class ReviewPlanParams extends Equatable {
  const ReviewPlanParams({
    required this.projectId,
    required this.slug,
    required this.planFile,
    required this.reviewer,
    this.harness,
    this.model,
    this.claudeAccountId,
    this.extra,
  });

  final String projectId;
  final String slug;
  final String planFile;
  final String reviewer;
  final String? harness;
  final String? model;
  final String? claudeAccountId;
  final String? extra;

  Map<String, dynamic> toJson() => {
    'reviewer': reviewer,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (claudeAccountId != null && claudeAccountId!.isNotEmpty) 'claudeAccountId': claudeAccountId,
    if (extra != null && extra!.isNotEmpty) 'extra': extra,
  };

  @override
  List<Object?> get props => [projectId, slug, planFile, reviewer, harness, model, claudeAccountId, extra];
}
```

`lib/feature/tickets/data/data_source/tickets_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

abstract class TicketsRemoteDataSource {
  Future<GlobalResponse<List<TicketModel>>> listTickets(String projectId);
  Future<GlobalResponse<TicketModel>> getTicket(String projectId, String slug);
  Future<GlobalResponse<TicketFileModel>> readFile(String projectId, String slug, String path);
  Future<GlobalResponse<CreateTicketResult>> createTicket(CreateTicketParams params);
  Future<GlobalResponse<SessionModel>> planTicket(PlanTicketParams params);
  Future<GlobalResponse<AssignPlanResult>> assignPlan(AssignPlanParams params);
  Future<GlobalResponse<ReviewPlanResult>> reviewPlan(ReviewPlanParams params);
  Future<GlobalResponse<TicketModel>> markPlanDone(String projectId, String slug, String planFile);
  Future<GlobalResponse<TicketModel>> mergePlan(String projectId, String slug, String planFile);
  Future<GlobalResponse<TicketModel>> archiveTicket(String projectId, String slug);
  Future<GlobalResponse<TicketModel>> unarchiveTicket(String projectId, String slug);
}

class TicketsRemoteDataSourceImp implements TicketsRemoteDataSource {
  TicketsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  static Map<String, dynamic> _body(dynamic data) => data as Map<String, dynamic>? ?? const {};

  static GlobalResponse<TicketModel> _ticketResponse(dynamic data) => GlobalResponse<TicketModel>.fromJson(
    _body(data),
    withDataKey: false,
    fromJsonT: (json) => TicketModel.fromJson(json['ticket'] as Map<String, dynamic>? ?? json),
  );

  @override
  Future<GlobalResponse<List<TicketModel>>> listTickets(String projectId) async {
    final response = await _apiConsumer.get(EndPoints.projectTickets(projectId));
    return GlobalResponse<List<TicketModel>>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: TicketModel.listFromJson,
    );
  }

  @override
  Future<GlobalResponse<TicketModel>> getTicket(String projectId, String slug) async {
    final response = await _apiConsumer.get(EndPoints.ticket(projectId, slug));
    return _ticketResponse(response.data);
  }

  @override
  Future<GlobalResponse<TicketFileModel>> readFile(String projectId, String slug, String path) async {
    final response = await _apiConsumer.get(EndPoints.ticketFile(projectId, slug), queryParameters: {'path': path});
    return GlobalResponse<TicketFileModel>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: TicketFileModel.fromJson,
    );
  }

  @override
  Future<GlobalResponse<CreateTicketResult>> createTicket(CreateTicketParams params) async {
    final response = await _apiConsumer.post(EndPoints.projectTickets(params.projectId), body: params.toJson());
    return GlobalResponse<CreateTicketResult>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: CreateTicketResult.fromJson,
    );
  }

  @override
  Future<GlobalResponse<SessionModel>> planTicket(PlanTicketParams params) async {
    final response = await _apiConsumer.post(EndPoints.ticketPlanning(params.projectId, params.slug), body: params.toJson());
    return GlobalResponse<SessionModel>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: (json) => SessionModel.fromJson(json['session'] as Map<String, dynamic>? ?? json),
    );
  }

  @override
  Future<GlobalResponse<AssignPlanResult>> assignPlan(AssignPlanParams params) async {
    final response = await _apiConsumer.post(
      EndPoints.ticketPlanAssign(params.projectId, params.slug, params.planFile),
      body: params.toJson(),
      queryParameters: params.queryParameters,
    );
    return GlobalResponse<AssignPlanResult>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: AssignPlanResult.fromJson,
    );
  }

  @override
  Future<GlobalResponse<ReviewPlanResult>> reviewPlan(ReviewPlanParams params) async {
    final response = await _apiConsumer.post(
      EndPoints.ticketPlanReview(params.projectId, params.slug, params.planFile),
      body: params.toJson(),
    );
    return GlobalResponse<ReviewPlanResult>.fromJson(
      _body(response.data),
      withDataKey: false,
      fromJsonT: ReviewPlanResult.fromJson,
    );
  }

  @override
  Future<GlobalResponse<TicketModel>> markPlanDone(String projectId, String slug, String planFile) async =>
      _ticketResponse((await _apiConsumer.post(EndPoints.ticketPlanDone(projectId, slug, planFile))).data);

  @override
  Future<GlobalResponse<TicketModel>> mergePlan(String projectId, String slug, String planFile) async =>
      _ticketResponse((await _apiConsumer.post(EndPoints.ticketPlanMerge(projectId, slug, planFile))).data);

  @override
  Future<GlobalResponse<TicketModel>> archiveTicket(String projectId, String slug) async =>
      _ticketResponse((await _apiConsumer.post(EndPoints.ticketArchive(projectId, slug))).data);

  @override
  Future<GlobalResponse<TicketModel>> unarchiveTicket(String projectId, String slug) async =>
      _ticketResponse((await _apiConsumer.post(EndPoints.ticketUnarchive(projectId, slug))).data);
}
```

`lib/feature/tickets/data/repository/tickets_repository.dart`:

```dart
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/data_source/tickets_remote_data_source.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

abstract class TicketsRepository {
  FutureResult<GlobalResponse<List<TicketModel>>> listTickets(String projectId);
  FutureResult<GlobalResponse<TicketModel>> getTicket(String projectId, String slug);
  FutureResult<GlobalResponse<TicketFileModel>> readFile(String projectId, String slug, String path);
  FutureResult<GlobalResponse<CreateTicketResult>> createTicket(CreateTicketParams params);
  FutureResult<GlobalResponse<SessionModel>> planTicket(PlanTicketParams params);
  FutureResult<GlobalResponse<AssignPlanResult>> assignPlan(AssignPlanParams params);
  FutureResult<GlobalResponse<ReviewPlanResult>> reviewPlan(ReviewPlanParams params);
  FutureResult<GlobalResponse<TicketModel>> markPlanDone(String projectId, String slug, String planFile);
  FutureResult<GlobalResponse<TicketModel>> mergePlan(String projectId, String slug, String planFile);
  FutureResult<GlobalResponse<TicketModel>> archiveTicket(String projectId, String slug);
  FutureResult<GlobalResponse<TicketModel>> unarchiveTicket(String projectId, String slug);
}

class TicketsRepositoryImp implements TicketsRepository {
  TicketsRepositoryImp(this._remote, this._network);

  final TicketsRemoteDataSource _remote;
  final NetworkStatus _network;

  FutureResult<T> _guard<T>(Future<T> Function() call) async {
    if (!await _network.isConnected) return Result.failure(ServerFailure.noNetwork());
    try {
      return Result.success(await call());
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }

  @override
  FutureResult<GlobalResponse<List<TicketModel>>> listTickets(String projectId) => _guard(() => _remote.listTickets(projectId));

  @override
  FutureResult<GlobalResponse<TicketModel>> getTicket(String projectId, String slug) => _guard(() => _remote.getTicket(projectId, slug));

  @override
  FutureResult<GlobalResponse<TicketFileModel>> readFile(String projectId, String slug, String path) =>
      _guard(() => _remote.readFile(projectId, slug, path));

  @override
  FutureResult<GlobalResponse<CreateTicketResult>> createTicket(CreateTicketParams params) => _guard(() => _remote.createTicket(params));

  @override
  FutureResult<GlobalResponse<SessionModel>> planTicket(PlanTicketParams params) => _guard(() => _remote.planTicket(params));

  @override
  FutureResult<GlobalResponse<AssignPlanResult>> assignPlan(AssignPlanParams params) => _guard(() => _remote.assignPlan(params));

  @override
  FutureResult<GlobalResponse<ReviewPlanResult>> reviewPlan(ReviewPlanParams params) => _guard(() => _remote.reviewPlan(params));

  @override
  FutureResult<GlobalResponse<TicketModel>> markPlanDone(String projectId, String slug, String planFile) =>
      _guard(() => _remote.markPlanDone(projectId, slug, planFile));

  @override
  FutureResult<GlobalResponse<TicketModel>> mergePlan(String projectId, String slug, String planFile) =>
      _guard(() => _remote.mergePlan(projectId, slug, planFile));

  @override
  FutureResult<GlobalResponse<TicketModel>> archiveTicket(String projectId, String slug) => _guard(() => _remote.archiveTicket(projectId, slug));

  @override
  FutureResult<GlobalResponse<TicketModel>> unarchiveTicket(String projectId, String slug) =>
      _guard(() => _remote.unarchiveTicket(projectId, slug));
}
```

`service_locator.dart`: after the `SessionsRemoteDataSource` registration (`:153-155`) add

```dart
    sl.registerLazySingleton<TicketsRemoteDataSource>(() => TicketsRemoteDataSourceImp(sl<ApiConsumer>()));
    sl.registerLazySingleton<TicketsRepository>(
      () => TicketsRepositoryImp(sl<TicketsRemoteDataSource>(), sl<NetworkStatus>()),
    );
```

with the two imports.

- [ ] **Step 4: Write the repository test**

`test/feature/tickets/data/repository/tickets_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/tickets/data/data_source/tickets_remote_data_source.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';

class _MockRemote extends Mock implements TicketsRemoteDataSource {}

class _MockNetwork extends Mock implements NetworkStatus {}

void main() {
  late _MockRemote remote;
  late _MockNetwork network;
  late TicketsRepository repository;

  setUpAll(() => registerFallbackValue(const AssignPlanParams(projectId: 'p', slug: 's', planFile: 'f')));

  setUp(() {
    remote = _MockRemote();
    network = _MockNetwork();
    repository = TicketsRepositoryImp(remote, network);
  });

  test('passes a successful list through', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => remote.listTickets('repo'))
        .thenAnswer((_) async => const GlobalResponse(data: [TicketModel(slug: 'smoke-ticket')]));
    final result = await repository.listTickets('repo');
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull?.data?.single.slug, 'smoke-ticket');
  });

  test('turns a thrown Failure into a failure result that keeps the envelope details', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => remote.assignPlan(any())).thenThrow(ServerFailure<Map<String, dynamic>>(
      error: 'conflict',
      message: 'Assignment needs confirmation',
      statusCode: 409,
      apiStatus: 'TICKET_ASSIGN_BLOCKED',
      validationErrors: const {'warnings': ['plan_assigned'], 'requestId': 'req-42'},
    ));
    final result = await repository.assignPlan(const AssignPlanParams(projectId: 'p', slug: 's', planFile: 'f'));
    expect(result.isFailure, isTrue);
    result.when(
      onSuccess: (_) => fail('expected a failure'),
      onFailure: (failure) {
        expect(failure.apiStatus, 'TICKET_ASSIGN_BLOCKED');
        expect((failure.validationErrors as Map<String, dynamic>)['requestId'], 'req-42');
      },
    );
  });

  test('reports no network without touching the data source', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);
    final result = await repository.getTicket('repo', 's');
    result.when(
      onSuccess: (_) => fail('expected a failure'),
      onFailure: (failure) => expect(failure.statusCode, StatusCode.noInternetConnection),
    );
    verifyNever(() => remote.getTicket(any(), any()));
  });

  test('AssignPlanResult flows through assignPlan', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => remote.assignPlan(any()))
        .thenAnswer((_) async => const GlobalResponse(data: AssignPlanResult(warnings: ['plan_order'])));
    final result = await repository.assignPlan(const AssignPlanParams(projectId: 'p', slug: 's', planFile: 'f', dryRun: true));
    expect(result.valueOrNull?.data?.warnings, ['plan_order']);
  });
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets`
Expected: all pass.

- [ ] **Step 6: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib/feature/tickets/data packages/mobile/lib/core/utils/service_locator.dart packages/mobile/test/feature/tickets/data
git commit -m "feat(mobile): tickets data source and repository over the daemon ticket routes

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Presentation logic — statuses, frontmatter, badges, assign rules

**Files:**
- Create: `packages/mobile/lib/feature/tickets/logic/ticket_status.dart`
- Create: `packages/mobile/lib/feature/tickets/logic/ticket_presentation.dart`
- Create: `packages/mobile/lib/feature/tickets/logic/frontmatter.dart`
- Create: `packages/mobile/lib/feature/tickets/logic/assign_rules.dart`
- Test: `packages/mobile/test/feature/tickets/logic/ticket_status_test.dart`
- Test: `packages/mobile/test/feature/tickets/logic/ticket_presentation_test.dart`
- Test: `packages/mobile/test/feature/tickets/logic/frontmatter_test.dart`
- Test: `packages/mobile/test/feature/tickets/logic/assign_rules_test.dart`

**Interfaces:**
- Consumes: `StatusVisual` and `statusChipTint` (`lib/feature/sessions/logic/status_visual.dart:4-10, 65-73`), `AppSkin` colours, `PlanModel`, `TicketModel`, `SessionTicketRef`, `Failure`.
- Produces:
  - `StatusVisual planStatusVisual(AppSkin skin, String? status)`, `StatusVisual ticketStatusVisual(AppSkin skin, TicketModel ticket)`, `bool isTicketInArchive(TicketModel)`, `int openTicketCount(Iterable<TicketModel>)`.
  - `String planNumber(String file)`, `String planBranchName(String slug, String file)`, `String ticketBadgeLabel(SessionTicketRef ref)`, `TicketFileGroups ticketFileGroups(TicketModel)` with `docs: List<String>` and `plans: List<PlanModel>` (sorted by order then file), `String? failureRequestId(Failure failure)`, `String planTitle(PlanModel plan)`, `bool planningSessionLive(SessionModel? session)` (a session that exists, is not `isTerminated` and whose status is not terminal per `isTerminalStatus`, `lib/feature/sessions/logic/session_status.dart:3-5`).
  - `class Frontmatter { List<(String, String)> fields; String body; }`, `Frontmatter splitFrontmatter(String content)`.
  - `const List<String> assignWarningCodes`, `String assignWarningLabel(String code)`, `bool needsForce(List<String>)`, `bool canAssignPlan(PlanModel)`, `String assignActionLabel(PlanModel)`, `bool canReviewPlan(PlanModel)`, `bool canMergePlan(PlanModel)`, `bool canMarkPlanDone(PlanModel)`, `List<String> newAssignWarnings(List<String> known, List<String> current)`, `String assignButtonLabel(List<String> warnings)`.
- Desktop truth mirrored: `frontend/src/renderer/lib/ticket-presentation.ts:52-160` (status tables, `planNumber`, `ticketBadgeLabel`, `splitFrontmatter`, `ticketFileGroups`), `frontend/src/renderer/lib/ticket-assign.ts:36-54` (`needsForce`, `canAssignPlan`, `assignActionKey`, `planBranchName`), `frontend/src/renderer/components/tickets/PlanRow.tsx:25-30, 59-61` (`canReviewPlan`, merge only on `awaiting_merge`, done hidden on `merged`/`done`), labels from `en.json` `tickets.plan.status.*`, `tickets.status.*`, `tickets.warning.*`, `tickets.mergedCount`.

- [ ] **Step 1: Write the failing tests**

`test/feature/tickets/logic/ticket_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';

void main() {
  const skin = DarkSkin();

  test('every plan status maps to the desktop label and a board colour', () {
    final expected = <String, (String, bool)>{
      'todo': ('To do', false),
      'idle': ('Idle', false),
      'working': ('Working', true),
      'needs_you': ('Needs you', false),
      'in_review': ('In review', false),
      'reviewing': ('Reviewing', true),
      'awaiting_merge': ('Awaiting your merge', false),
      'merging': ('Merging', true),
      'merged': ('Merged', false),
      'done': ('Done', false),
      'terminated': ('Terminated', false),
    };
    for (final entry in expected.entries) {
      final visual = planStatusVisual(skin, entry.key);
      expect(visual.label, entry.value.$1, reason: entry.key);
      expect(visual.breathing, entry.value.$2, reason: entry.key);
    }
    expect(planStatusVisual(skin, 'working').color, skin.orange);
    expect(planStatusVisual(skin, 'needs_you').color, skin.amber);
    expect(planStatusVisual(skin, 'awaiting_merge').color, skin.green);
    expect(planStatusVisual(skin, 'merged').color, skin.green);
    expect(planStatusVisual(skin, 'terminated').color, skin.textFaint);
    expect(planStatusVisual(skin, 'todo').color, skin.textTertiary);
  });

  test('unknown or null plan statuses fall back instead of throwing', () {
    expect(planStatusVisual(skin, 'something_new').label, 'something_new');
    expect(planStatusVisual(skin, null).label, 'unknown');
    expect(planStatusVisual(skin, null).color, skin.textTertiary);
  });

  test('every ticket status maps to the desktop label and colour', () {
    final expected = <String, (String, bool)>{
      'draft': ('Draft', false),
      'planning': ('Planning', true),
      'ready': ('Ready', false),
      'in_progress': ('In progress', true),
      'awaiting_merge': ('Waiting for your confirmation', false),
      'done': ('Done', false),
      'archived': ('Archived', false),
    };
    for (final entry in expected.entries) {
      final visual = ticketStatusVisual(skin, TicketModel(status: entry.key));
      expect(visual.label, entry.value.$1, reason: entry.key);
      expect(visual.breathing, entry.value.$2, reason: entry.key);
    }
    expect(ticketStatusVisual(skin, const TicketModel(status: 'planning')).color, skin.orange);
    expect(ticketStatusVisual(skin, const TicketModel(status: 'awaiting_merge')).color, skin.green);
    expect(ticketStatusVisual(skin, const TicketModel(status: 'archived')).color, skin.textFaint);
    expect(ticketStatusVisual(skin, const TicketModel(status: 'nope')).label, 'nope');
    expect(ticketStatusVisual(skin, const TicketModel()).label, 'unknown');
  });

  test('an in-progress ticket with merged plans reads N/M merged', () {
    const ticket = TicketModel(
      status: 'in_progress',
      plans: [PlanModel(status: 'merged'), PlanModel(status: 'done'), PlanModel(status: 'working'), PlanModel(status: 'todo')],
    );
    expect(ticketStatusVisual(skin, ticket).label, '2/4 merged');
    expect(ticketStatusVisual(skin, const TicketModel(status: 'in_progress', plans: [PlanModel(status: 'working')])).label, 'In progress');
  });

  test('done and archived tickets belong to the archive', () {
    expect(isTicketInArchive(const TicketModel(status: 'done')), isTrue);
    expect(isTicketInArchive(const TicketModel(status: 'archived')), isTrue);
    expect(isTicketInArchive(const TicketModel(status: 'ready')), isFalse);
    expect(openTicketCount(const [TicketModel(status: 'draft'), TicketModel(status: 'done'), TicketModel(status: 'planning')]), 2);
  });
}
```

`test/feature/tickets/logic/ticket_presentation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_ticket_ref.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';

void main() {
  test('planNumber reads the NN prefix of the bare or plans/-prefixed file', () {
    expect(planNumber('plans/01-index.md'), '01');
    expect(planNumber('02-ui.md'), '02');
    expect(planNumber('plans/notes.md'), '');
  });

  test('planBranchName mirrors the daemon: opr/<slug>-<NN>, stem for unordered plans', () {
    expect(planBranchName('search-page', 'plans/01-index.md'), 'opr/search-page-01');
    expect(planBranchName('search-page', 'plans/notes.md'), 'opr/search-page-notes');
  });

  test('ticketBadgeLabel reads slug · NN, or slug · plan for the planner', () {
    expect(ticketBadgeLabel(const SessionTicketRef(slug: 'search-page', planFile: 'plans/01-index.md', role: 'implementing')), 'search-page · 01');
    expect(ticketBadgeLabel(const SessionTicketRef(slug: 'search-page', planFile: 'plans/01-index.md', role: 'reviewing')), 'search-page · 01');
    expect(ticketBadgeLabel(const SessionTicketRef(slug: 'search-page', role: 'planning')), 'search-page · plan');
    expect(ticketBadgeLabel(const SessionTicketRef(slug: 'search-page', planFile: 'plans/notes.md', role: 'implementing')), 'search-page · notes.md');
    expect(ticketBadgeLabel(const SessionTicketRef(role: 'implementing')), '');
  });

  test('planTitle falls back to the file name', () {
    expect(planTitle(const PlanModel(file: 'plans/01-index.md', title: 'Index')), 'Index');
    expect(planTitle(const PlanModel(file: 'plans/01-index.md', title: '')), '01-index.md');
    expect(planTitle(const PlanModel()), '');
  });

  test('ticketFileGroups separates docs from plans and sorts plans by order', () {
    const ticket = TicketModel(
      files: ['ticket.md', 'spec.md', 'plans/02-ui.md', 'plans/01-index.md', 'plans/01-index.kickoff.md', 'notes/extra.md'],
      plans: [
        PlanModel(file: 'plans/02-ui.md', order: 2),
        PlanModel(file: 'plans/01-index.md', order: 1, kickoffFile: 'plans/01-index.kickoff.md'),
      ],
    );
    final groups = ticketFileGroups(ticket);
    expect(groups.docs, ['ticket.md', 'spec.md', 'notes/extra.md']);
    expect(groups.plans.map((p) => p.file), ['plans/01-index.md', 'plans/02-ui.md']);
  });

  test('planningSessionLive is true only for a present, non-terminal session', () {
    expect(planningSessionLive(null), isFalse);
    expect(planningSessionLive(const SessionModel(id: 'a', status: 'working')), isTrue);
    expect(planningSessionLive(const SessionModel(id: 'a', status: 'terminated')), isFalse);
    expect(planningSessionLive(const SessionModel(id: 'a', status: 'working', isTerminated: true)), isFalse);
    expect(planningSessionLive(const SessionModel(id: 'a', status: 'merged')), isFalse);
  });

  test('failureRequestId reads the envelope requestId when present', () {
    final withId = ServerFailure<Map<String, dynamic>>(error: 'x', message: 'm', validationErrors: const {'requestId': 'req-1'});
    final without = ServerFailure<Map<String, dynamic>>(error: 'x', message: 'm');
    expect(failureRequestId(withId), 'req-1');
    expect(failureRequestId(without), isNull);
  });
}
```

`test/feature/tickets/logic/frontmatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/tickets/logic/frontmatter.dart';

void main() {
  test('splits a YAML-ish header into fields and strips the leading blank lines of the body', () {
    final result = splitFrontmatter('---\ntitle: First\nstatus: "draft"\nnoise line\n---\n\n# Body\n');
    expect(result.fields, [('title', 'First'), ('status', 'draft')]);
    expect(result.body, '# Body\n');
  });

  test('keeps the content whole when there is no frontmatter or no closing fence', () {
    expect(splitFrontmatter('# Plain\n').fields, isEmpty);
    expect(splitFrontmatter('# Plain\n').body, '# Plain\n');
    expect(splitFrontmatter('---\ntitle: x\n').fields, isEmpty);
    expect(splitFrontmatter('---\ntitle: x\n').body, '---\ntitle: x\n');
  });

  test('unquotes JSON strings and falls back to trimming quotes on bad escapes', () {
    expect(splitFrontmatter('---\na: "with \\"quotes\\""\nb: "bad \\q"\n---\n').fields, [('a', 'with "quotes"'), ('b', 'bad \\q')]);
  });

  test('matches the daemon report file exactly', () {
    final result = splitFrontmatter('---\ntitle: First\n---\n');
    expect(result.fields, [('title', 'First')]);
    expect(result.body, '');
  });
}
```

`test/feature/tickets/logic/assign_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/logic/assign_rules.dart';

void main() {
  test('the five daemon warning codes have the desktop English copy, in daemon order', () {
    expect(assignWarningCodes, ['plan_order', 'ticket_repo_dirty', 'ticket_not_on_default_branch', 'planning_active', 'plan_assigned']);
    expect(assignWarningLabel('plan_order'), 'An earlier plan in this ticket is not merged or done yet.');
    expect(
      assignWarningLabel('ticket_repo_dirty'),
      'The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.',
    );
    expect(
      assignWarningLabel('ticket_not_on_default_branch'),
      'The project checkout is not on its default branch. The worktree is cut from the default branch, which may not contain these files.',
    );
    expect(assignWarningLabel('planning_active'), 'The planning session is still running.');
    expect(assignWarningLabel('plan_assigned'), 'This plan already has a live session. Starting again terminates it first.');
    expect(assignWarningLabel('brand_new'), 'brand_new');
  });

  test('force is needed exactly when warnings exist', () {
    expect(needsForce(const []), isFalse);
    expect(needsForce(const ['plan_order']), isTrue);
  });

  test('assign is offered on todo, reassign on terminated, nothing otherwise', () {
    expect(canAssignPlan(const PlanModel(status: 'todo')), isTrue);
    expect(canAssignPlan(const PlanModel(status: 'terminated')), isTrue);
    expect(canAssignPlan(const PlanModel(status: 'working')), isFalse);
    expect(assignActionLabel(const PlanModel(status: 'todo')), 'Assign');
    expect(assignActionLabel(const PlanModel(status: 'terminated')), 'Reassign');
  });

  test('review needs a session and a reviewable status; merge needs awaiting_merge; done hides on closed plans', () {
    for (final status in ['idle', 'working', 'needs_you', 'in_review', 'terminated']) {
      expect(canReviewPlan(PlanModel(status: status, sessionId: 'repo-4')), isTrue, reason: status);
    }
    expect(canReviewPlan(const PlanModel(status: 'working')), isFalse);
    expect(canReviewPlan(const PlanModel(status: 'todo', sessionId: 'repo-4')), isFalse);
    expect(canMergePlan(const PlanModel(status: 'awaiting_merge')), isTrue);
    expect(canMergePlan(const PlanModel(status: 'in_review')), isFalse);
    expect(canMarkPlanDone(const PlanModel(status: 'working')), isTrue);
    expect(canMarkPlanDone(const PlanModel(status: 'merged')), isFalse);
    expect(canMarkPlanDone(const PlanModel(status: 'done')), isFalse);
  });

  test('a re-check stops on warnings the sheet has not shown yet', () {
    expect(newAssignWarnings(const ['ticket_repo_dirty'], const ['ticket_repo_dirty']), isEmpty);
    expect(newAssignWarnings(const ['ticket_repo_dirty'], const ['ticket_repo_dirty', 'plan_assigned']), ['plan_assigned']);
    expect(newAssignWarnings(const ['ticket_repo_dirty'], const []), isEmpty);
  });

  test('the button relabels when a live session would be terminated', () {
    expect(assignButtonLabel(const []), 'Start');
    expect(assignButtonLabel(const ['ticket_repo_dirty']), 'Start');
    expect(assignButtonLabel(const ['plan_assigned']), 'Terminate and start');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/tickets/logic`
Expected: compile errors.

- [ ] **Step 3: Write the logic**

`lib/feature/tickets/logic/ticket_status.dart`:

```dart
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

StatusVisual planStatusVisual(AppSkin skin, String? status) => switch (status) {
  'todo' => StatusVisual(color: skin.textTertiary, label: 'To do'),
  'idle' => StatusVisual(color: skin.textTertiary, label: 'Idle'),
  'working' => StatusVisual(color: skin.orange, label: 'Working', breathing: true),
  'needs_you' => StatusVisual(color: skin.amber, label: 'Needs you'),
  'in_review' => StatusVisual(color: skin.textSecondary, label: 'In review'),
  'reviewing' => StatusVisual(color: skin.textSecondary, label: 'Reviewing', breathing: true),
  'awaiting_merge' => StatusVisual(color: skin.green, label: 'Awaiting your merge'),
  'merging' => StatusVisual(color: skin.green, label: 'Merging', breathing: true),
  'merged' => StatusVisual(color: skin.green, label: 'Merged'),
  'done' => StatusVisual(color: skin.green, label: 'Done'),
  'terminated' => StatusVisual(color: skin.textFaint, label: 'Terminated'),
  _ => StatusVisual(color: skin.textTertiary, label: status ?? 'unknown'),
};

const Set<String> _mergedPlanStatuses = {'merged', 'done'};
const Set<String> _archiveTicketStatuses = {'done', 'archived'};

StatusVisual ticketStatusVisual(AppSkin skin, TicketModel ticket) {
  final merged = ticket.plans.where((plan) => _mergedPlanStatuses.contains(plan.status)).length;
  return switch (ticket.status) {
    'draft' => StatusVisual(color: skin.textTertiary, label: 'Draft'),
    'planning' => StatusVisual(color: skin.orange, label: 'Planning', breathing: true),
    'ready' => StatusVisual(color: skin.textTertiary, label: 'Ready'),
    'in_progress' => StatusVisual(
      color: skin.orange,
      label: merged > 0 ? '$merged/${ticket.plans.length} merged' : 'In progress',
      breathing: true,
    ),
    'awaiting_merge' => StatusVisual(color: skin.green, label: 'Waiting for your confirmation'),
    'done' => StatusVisual(color: skin.green, label: 'Done'),
    'archived' => StatusVisual(color: skin.textFaint, label: 'Archived'),
    _ => StatusVisual(color: skin.textTertiary, label: ticket.status ?? 'unknown'),
  };
}

bool isTicketInArchive(TicketModel ticket) => _archiveTicketStatuses.contains(ticket.status);

int openTicketCount(Iterable<TicketModel> tickets) => tickets.where((ticket) => !isTicketInArchive(ticket)).length;
```

`lib/feature/tickets/logic/ticket_presentation.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_ticket_ref.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';

bool planningSessionLive(SessionModel? session) =>
    session != null && session.isTerminated != true && !isTerminalStatus(session.status);

final RegExp _planNumberPattern = RegExp(r'(?:^|/)(\d+)-[^/]*$');

String planNumber(String file) => _planNumberPattern.firstMatch(file)?.group(1) ?? '';

String _fileName(String file) => file.split('/').last;

String planBranchName(String slug, String file) {
  final number = planNumber(file);
  final stem = _fileName(file).replaceFirst(RegExp(r'\.md$'), '');
  return 'opr/$slug-${number.isEmpty ? stem : number}';
}

String ticketBadgeLabel(SessionTicketRef ref) {
  final slug = ref.slug ?? '';
  if (slug.isEmpty) return '';
  final planFile = ref.planFile;
  if (ref.role == 'planning' || planFile == null || planFile.isEmpty) return '$slug · plan';
  final number = planNumber(planFile);
  return '$slug · ${number.isEmpty ? _fileName(planFile) : number}';
}

String planTitle(PlanModel plan) {
  final title = plan.title?.trim() ?? '';
  if (title.isNotEmpty) return title;
  final file = plan.file ?? '';
  return file.isEmpty ? '' : _fileName(file);
}

class TicketFileGroups {
  const TicketFileGroups({required this.docs, required this.plans});

  final List<String> docs;
  final List<PlanModel> plans;
}

TicketFileGroups ticketFileGroups(TicketModel ticket) {
  final planFiles = <String>{
    for (final plan in ticket.plans) ...[if (plan.file != null) plan.file!, if (plan.kickoffFile != null) plan.kickoffFile!],
  };
  final docs = ticket.files.where((file) => !planFiles.contains(file) && !file.startsWith('plans/')).toList();
  final plans = [...ticket.plans]..sort((left, right) {
    final byOrder = (left.order ?? 0).compareTo(right.order ?? 0);
    return byOrder != 0 ? byOrder : (left.file ?? '').compareTo(right.file ?? '');
  });
  return TicketFileGroups(docs: docs, plans: plans);
}

String? failureRequestId(Failure failure) {
  final extras = failure.validationErrors;
  if (extras is Map<String, dynamic> && extras['requestId'] is String) return extras['requestId'] as String;
  return null;
}
```

`lib/feature/tickets/logic/frontmatter.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

class Frontmatter extends Equatable {
  const Frontmatter({required this.fields, required this.body});

  final List<(String, String)> fields;
  final String body;

  @override
  List<Object?> get props => [fields, body];
}

Frontmatter splitFrontmatter(String content) {
  if (!content.startsWith('---\n')) return Frontmatter(fields: const [], body: content);
  final end = content.indexOf('\n---', 4);
  if (end == -1) return Frontmatter(fields: const [], body: content);
  final header = content.substring(4, end);
  final rest = content.substring(end + 4);
  final fields = <(String, String)>[];
  for (final line in header.split('\n')) {
    final colon = line.indexOf(':');
    if (colon == -1) continue;
    final key = line.substring(0, colon).trim();
    var value = line.substring(colon + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      try {
        value = jsonDecode(value) as String;
      } catch (_) {
        value = value.substring(1, value.length - 1);
      }
    }
    if (key.isNotEmpty) fields.add((key, value));
  }
  return Frontmatter(fields: fields, body: rest.replaceFirst(RegExp(r'^\n+'), ''));
}
```

`lib/feature/tickets/logic/assign_rules.dart`:

```dart
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';

const List<String> assignWarningCodes = [
  'plan_order',
  'ticket_repo_dirty',
  'ticket_not_on_default_branch',
  'planning_active',
  'plan_assigned',
];

String assignWarningLabel(String code) => switch (code) {
  'plan_order' => 'An earlier plan in this ticket is not merged or done yet.',
  'ticket_repo_dirty' =>
    'The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.',
  'ticket_not_on_default_branch' =>
    'The project checkout is not on its default branch. The worktree is cut from the default branch, which may not contain these files.',
  'planning_active' => 'The planning session is still running.',
  'plan_assigned' => 'This plan already has a live session. Starting again terminates it first.',
  _ => code,
};

bool needsForce(List<String> warnings) => warnings.isNotEmpty;

const Set<String> _assignableStatuses = {'todo', 'terminated'};
const Set<String> _reviewableStatuses = {'idle', 'working', 'needs_you', 'in_review', 'terminated'};
const Set<String> _closedStatuses = {'merged', 'done'};

bool canAssignPlan(PlanModel plan) => _assignableStatuses.contains(plan.status);

String assignActionLabel(PlanModel plan) => plan.status == 'terminated' ? 'Reassign' : 'Assign';

bool canReviewPlan(PlanModel plan) =>
    plan.sessionId != null && plan.sessionId!.isNotEmpty && _reviewableStatuses.contains(plan.status);

bool canMergePlan(PlanModel plan) => plan.status == 'awaiting_merge';

bool canMarkPlanDone(PlanModel plan) => !_closedStatuses.contains(plan.status);

List<String> newAssignWarnings(List<String> known, List<String> current) =>
    current.where((code) => !known.contains(code)).toList();

String assignButtonLabel(List<String> warnings) => warnings.contains('plan_assigned') ? 'Terminate and start' : 'Start';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets/logic`
Expected: all pass.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib/feature/tickets/logic packages/mobile/test/feature/tickets/logic
git commit -m "feat(mobile): ticket status tables, frontmatter split, badge and assign rules

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Tickets ride the board snapshot and the mux

**Files:**
- Modify: `packages/mobile/lib/feature/sessions/data/model/board_snapshot.dart:6-21`
- Modify: `packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart:20-76`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart:45-53, 98-118, 120-153`
- Modify: `packages/mobile/lib/core/mux/mux_client.dart:199-200`
- Test: `packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart` (append)
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart` (append)
- Test: `packages/mobile/test/core/mux/mux_client_test.dart:347-383` (extend)

**Interfaces:**
- Consumes: `TicketModel.listFromJson`, `EndPoints.projectTickets`, `ProjectModel.kind` (`project_model.dart:6-21`).
- Produces: `BoardSnapshot.tickets: List<TicketModel>`; `SessionsCubit.tickets`, `SessionsCubit.visibleTickets` (filtered by `activeProjectId` like `visibleSessions`, `sessions_cubit.dart:51-53`), `SessionsCubit.sessionsById: Map<String, SessionModel>`; `MuxClient` emits `boardChanges` for `ticket_updated`.

- [ ] **Step 1: Write the failing tests**

Append to `test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart` inside the existing `getBoard` group (read the file's `setUp` first; it stubs `EndPoints.sessions`, `orchestrators`, `projects`, `claudeAccounts` on a `_MockApiConsumer` named `apiConsumer` and keeps a call-order list — reuse its helpers, and add `import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';` only if you assert on the type):

```dart
    test('fetches tickets for single_repo projects only, after /sessions has answered', () async {
      final calls = <String>[];
      Response<dynamic> body(Map<String, dynamic> json) =>
          Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: json);
      when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((invocation) async {
        final path = invocation.positionalArguments.single as String;
        calls.add(path);
        if (path == EndPoints.sessions) return body({'sessions': <dynamic>[]});
        if (path == EndPoints.orchestrators) return body({'sessions': <dynamic>[]});
        if (path == EndPoints.claudeAccounts) return body({'accounts': <dynamic>[]});
        if (path == EndPoints.projects) {
          return body({
            'projects': [
              {'id': 'repo', 'name': 'repo', 'kind': 'single_repo'},
              {'id': 'scratch', 'name': 'scratch', 'kind': 'scratch'},
            ],
          });
        }
        if (path == EndPoints.projectTickets('repo')) {
          return body({'tickets': [{'projectId': 'repo', 'slug': 'smoke-ticket', 'status': 'draft'}]});
        }
        throw StateError('unexpected $path');
      });

      final board = (await dataSource.getBoard()).data!;

      expect(board.tickets.single.slug, 'smoke-ticket');
      expect(calls.first, EndPoints.sessions);
      expect(calls, isNot(contains(EndPoints.projectTickets('scratch'))));
      expect(calls.indexOf(EndPoints.projectTickets('repo')), greaterThan(0));
    });

    test('a failed ticket list degrades to no tickets for that project', () async {
      Response<dynamic> body(Map<String, dynamic> json) =>
          Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: json);
      when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((invocation) async {
        final path = invocation.positionalArguments.single as String;
        if (path == EndPoints.sessions || path == EndPoints.orchestrators) return body({'sessions': <dynamic>[]});
        if (path == EndPoints.claudeAccounts) return body({'accounts': <dynamic>[]});
        if (path == EndPoints.projects) return body({'projects': [{'id': 'repo', 'kind': 'single_repo'}]});
        throw ServerFailure<Map<String, dynamic>>(error: 'boom', message: 'boom', statusCode: 500);
      });

      final board = (await dataSource.getBoard()).data!;
      expect(board.tickets, isEmpty);
      expect(board.projects.single.id, 'repo');
    });
```

(If the existing `get` stubs in that file are written as `apiConsumer.get(EndPoints.sessions)` without the named argument, match that form: the data source calls `get(path)` with no query parameters for every board route, so stub `apiConsumer.get(any())` instead. Keep whichever form the existing "probes /sessions alone" test at `:28` uses.)

Append to `test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart` (its `setUp` builds a `SessionsCubit` from a mocked `SessionsRepository`, `MuxClient` and a stub config source — reuse the file's own `buildCubit`/mock names, and add imports for `BoardSnapshot`, `ProjectModel`, `SessionModel`, `TicketModel`, `GlobalResponse` and `Result` where missing):

```dart
  test('exposes tickets from the snapshot, scoped to the active project', () async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [SessionModel(id: 'repo-4', projectId: 'repo')],
            projects: [ProjectModel(id: 'repo', kind: 'single_repo'), ProjectModel(id: 'other', kind: 'single_repo')],
            tickets: [TicketModel(projectId: 'repo', slug: 'a'), TicketModel(projectId: 'other', slug: 'b')],
          ),
        ),
      ),
    );
    final cubit = buildCubit();
    await cubit.refresh();
    expect(cubit.tickets.map((t) => t.slug), ['a', 'b']);
    expect(cubit.sessionsById['repo-4']?.projectId, 'repo');
    cubit.setActiveProject('repo');
    expect(cubit.visibleTickets.map((t) => t.slug), ['a']);
    cubit.setActiveProject(kAllProjects);
    expect(cubit.visibleTickets, hasLength(2));
    await cubit.close();
  });
```

Extend `test/core/mux/mux_client_test.dart:360-366`: add `'ticket_updated'` to the list of forwarded event types and change `expect(invalidations, 6);` at `:377` to `expect(invalidations, 7);`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/sessions test/core/mux`
Expected: the data source and cubit tests fail to compile (`tickets` unknown); the mux test fails with `Expected: <7> Actual: <6>`.

- [ ] **Step 3: Implement**

`board_snapshot.dart`: add `import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';`, constructor parameter `this.tickets = const [],`, field `final List<TicketModel> tickets;`, and `tickets` in `props`.

`sessions_remote_data_source.dart`: add the import for `TicketModel`; in `getBoard()` replace lines 25-29 with

```dart
    final orchestratorsFuture = _apiConsumer.get(EndPoints.orchestrators);
    final projectsFuture = _fetchProjects();
    final accountsFuture = _fetchAccountLabels();
    final orchestratorsResponse = await orchestratorsFuture;
    final projects = await projectsFuture;
    final accountLabels = await accountsFuture;
    final tickets = await _fetchTickets(projects);
```

pass `tickets: tickets,` into the `BoardSnapshot(...)` constructor call, and add after `_fetchProjects`:

```dart
  Future<List<TicketModel>> _fetchTickets(List<ProjectModel> projects) async {
    final lists = await Future.wait(
      projects.where((project) => project.kind == 'single_repo' && project.id != null).map((project) async {
        try {
          final response = await _apiConsumer.get(EndPoints.projectTickets(project.id!));
          return TicketModel.listFromJson(response.data as Map<String, dynamic>? ?? const {});
        } catch (_) {
          return const <TicketModel>[];
        }
      }),
    );
    return [for (final list in lists) ...list];
  }
```

`sessions_cubit.dart`: add `import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';`; after `Map<String, String> accountLabels = const {};` (`:48`) add

```dart
  List<TicketModel> tickets = [];

  List<TicketModel> get visibleTickets => activeProjectId == kAllProjects
      ? tickets
      : tickets.where((ticket) => ticket.projectId == activeProjectId).toList();

  Map<String, SessionModel> get sessionsById => {
    for (final session in sessions)
      if (session.id != null) session.id!: session,
  };
```

In `_onConfigChanged` after `projects = [];` add `tickets = [];`. In `_loadBoard`'s `onSuccess` after `accountLabels = board.accountLabels;` add `tickets = board.tickets;`.

`mux_client.dart:199-200`: extend the condition to

```dart
            (eventType.startsWith('session_') ||
                eventType.startsWith('project_') ||
                eventType.startsWith('pr_') ||
                eventType.startsWith('ticket_'))) {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/sessions test/core/mux`
Expected: all pass, including the pre-existing "probes /sessions alone before fanning out" test.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): tickets join the board snapshot; ticket CDC frames refresh the board

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Ticket actions cubit, failure text, New ticket, Archive / Reopen, ticket actions sheet

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/logic/ticket_actions_state.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/create_ticket_sheet.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_actions_sheet.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart` (add `static const String ticket = '/ticket';`)
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (register `TicketActionsCubit` as a factory)
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/create_ticket_sheet_test.dart`

**Interfaces:**
- Consumes: `TicketsRepository`, `Result.when`, `TelemetryRuntime.featureUsed(name, succeeded:)` (as `sessions_cubit.dart:193`), `AppSheetChrome`, `showExpressiveSheet`, `AppTextField`, `PrimaryButton`, `AppToast.show`, `AppDialog.confirm`, `showProjectPickerSheet(context, projects:, selected:, includeAll: false, title:, subtitle:)` (`core/widgets/pickers/project_picker_sheet.dart:13-20`), `sl<SessionsCubit>()` for `projects`, `activeProjectId`, `refresh()` (as `spawn_body.dart:54-67, 141`).
- Produces:
  - `TicketActionsCubit(TicketsRepository)` with `create(CreateTicketParams)`, `plan(PlanTicketParams)`, `review(ReviewPlanParams)`, `merge(projectId, slug, planFile)`, `markDone(projectId, slug, planFile)`, `archive(projectId, slug)`, `unarchive(projectId, slug)`.
  - States: `TicketActionsInitialState`, `TicketActionBusyState`, `TicketCreatedState(ticket, warnings)`, `TicketSessionStartedState(session)`, `TicketUpdatedState(ticket)`, `TicketActionFailureState(failure)`.
  - `TicketFailureText(failure)` widget; `Future<void> showCreateTicketSheet(BuildContext, {String? projectId})`; `Future<void> showTicketActionsSheet(BuildContext, TicketModel ticket, {required SessionModel? planningSession, required VoidCallback onOpen, required VoidCallback onPlan, required void Function(String sessionId) onOpenSession})`.
  - Later tasks call `cubit.plan(...)`, `cubit.review(...)`, `cubit.merge(...)`, `cubit.markDone(...)` from their sheets.

- [ ] **Step 1: Write the failing cubit test**

`test/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';

class _MockTicketsRepository extends Mock implements TicketsRepository {}

void main() {
  late _MockTicketsRepository repository;

  setUpAll(() {
    registerFallbackValue(const CreateTicketParams(projectId: 'p', title: 't'));
    registerFallbackValue(const PlanTicketParams(projectId: 'p', slug: 's'));
    registerFallbackValue(const ReviewPlanParams(projectId: 'p', slug: 's', planFile: 'f', reviewer: 'planner'));
  });

  setUp(() => repository = _MockTicketsRepository());

  final failure = ServerFailure<Map<String, dynamic>>(
    error: 'x',
    message: 'This ticket already has a running planning session.',
    statusCode: 409,
    apiStatus: 'TICKET_PLANNING_ACTIVE',
    validationErrors: const {'requestId': 'req-7'},
  );

  blocTest<TicketActionsCubit, TicketActionsState>(
    'create emits busy then created with the daemon warnings',
    build: () {
      when(() => repository.createTicket(any())).thenAnswer(
        (_) async => Result.success(const GlobalResponse(
          data: CreateTicketResult(ticket: TicketModel(slug: 'smoke-ticket'), warnings: ['ticket_not_on_default_branch']),
        )),
      );
      return TicketActionsCubit(repository);
    },
    act: (cubit) => cubit.create(const CreateTicketParams(projectId: 'repo', title: 'Smoke ticket')),
    expect: () => [
      const TicketActionBusyState(),
      const TicketCreatedState(TicketModel(slug: 'smoke-ticket'), ['ticket_not_on_default_branch']),
    ],
  );

  blocTest<TicketActionsCubit, TicketActionsState>(
    'plan emits the started session',
    build: () {
      when(() => repository.planTicket(any()))
          .thenAnswer((_) async => Result.success(const GlobalResponse(data: SessionModel(id: 'repo-3'))));
      return TicketActionsCubit(repository);
    },
    act: (cubit) => cubit.plan(const PlanTicketParams(projectId: 'repo', slug: 's', harness: 'claude-code')),
    expect: () => [const TicketActionBusyState(), const TicketSessionStartedState(SessionModel(id: 'repo-3'))],
  );

  blocTest<TicketActionsCubit, TicketActionsState>(
    'plan surfaces the envelope failure',
    build: () {
      when(() => repository.planTicket(any())).thenAnswer((_) async => Result.failure(failure));
      return TicketActionsCubit(repository);
    },
    act: (cubit) => cubit.plan(const PlanTicketParams(projectId: 'repo', slug: 's')),
    expect: () => [const TicketActionBusyState(), TicketActionFailureState(failure)],
  );

  blocTest<TicketActionsCubit, TicketActionsState>(
    'review emits the reviewer session',
    build: () {
      when(() => repository.reviewPlan(any())).thenAnswer(
        (_) async => Result.success(const GlobalResponse(data: ReviewPlanResult(session: SessionModel(id: 'repo-3'), spawned: false))),
      );
      return TicketActionsCubit(repository);
    },
    act: (cubit) => cubit.review(const ReviewPlanParams(projectId: 'repo', slug: 's', planFile: '01.md', reviewer: 'planner')),
    expect: () => [const TicketActionBusyState(), const TicketSessionStartedState(SessionModel(id: 'repo-3'))],
  );

  blocTest<TicketActionsCubit, TicketActionsState>(
    'merge, mark done, archive and unarchive emit the updated ticket',
    build: () {
      when(() => repository.mergePlan('repo', 's', '01.md'))
          .thenAnswer((_) async => Result.success(const GlobalResponse(data: TicketModel(slug: 's', status: 'in_progress'))));
      when(() => repository.markPlanDone('repo', 's', '01.md'))
          .thenAnswer((_) async => Result.success(const GlobalResponse(data: TicketModel(slug: 's', status: 'done'))));
      when(() => repository.archiveTicket('repo', 's'))
          .thenAnswer((_) async => Result.success(const GlobalResponse(data: TicketModel(slug: 's', status: 'archived'))));
      when(() => repository.unarchiveTicket('repo', 's'))
          .thenAnswer((_) async => Result.success(const GlobalResponse(data: TicketModel(slug: 's', status: 'done'))));
      return TicketActionsCubit(repository);
    },
    act: (cubit) async {
      await cubit.merge('repo', 's', '01.md');
      await cubit.markDone('repo', 's', '01.md');
      await cubit.archive('repo', 's');
      await cubit.unarchive('repo', 's');
    },
    expect: () => [
      const TicketActionBusyState(),
      const TicketUpdatedState(TicketModel(slug: 's', status: 'in_progress')),
      const TicketActionBusyState(),
      const TicketUpdatedState(TicketModel(slug: 's', status: 'done')),
      const TicketActionBusyState(),
      const TicketUpdatedState(TicketModel(slug: 's', status: 'archived')),
      const TicketActionBusyState(),
      const TicketUpdatedState(TicketModel(slug: 's', status: 'done')),
    ],
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit_test.dart`
Expected: compile error, `ticket_actions_cubit.dart` does not exist.

- [ ] **Step 3: Write the cubit**

`ticket_actions_state.dart`:

```dart
part of 'ticket_actions_cubit.dart';

sealed class TicketActionsState extends Equatable {
  const TicketActionsState();

  @override
  List<Object?> get props => [];
}

final class TicketActionsInitialState extends TicketActionsState {
  const TicketActionsInitialState();
}

final class TicketActionBusyState extends TicketActionsState {
  const TicketActionBusyState();
}

final class TicketCreatedState extends TicketActionsState {
  const TicketCreatedState(this.ticket, this.warnings);

  final TicketModel ticket;
  final List<String> warnings;

  @override
  List<Object?> get props => [ticket, warnings];
}

final class TicketSessionStartedState extends TicketActionsState {
  const TicketSessionStartedState(this.session);

  final SessionModel session;

  @override
  List<Object?> get props => [session];
}

final class TicketUpdatedState extends TicketActionsState {
  const TicketUpdatedState(this.ticket);

  final TicketModel ticket;

  @override
  List<Object?> get props => [ticket];
}

final class TicketActionFailureState extends TicketActionsState {
  const TicketActionFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
```

`ticket_actions_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';

part 'ticket_actions_state.dart';

class TicketActionsCubit extends Cubit<TicketActionsState> {
  TicketActionsCubit(this._repository) : super(const TicketActionsInitialState());

  final TicketsRepository _repository;

  Future<void> create(CreateTicketParams params) async {
    emit(const TicketActionBusyState());
    final result = await _repository.createTicket(params);
    TelemetryRuntime.featureUsed('ticket_create', succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) {
        final created = response.data;
        if (created?.ticket == null) {
          emit(TicketActionFailureState(_missing('ticket')));
          return;
        }
        emit(TicketCreatedState(created!.ticket!, created.warnings));
      },
      onFailure: (failure) => emit(TicketActionFailureState(failure)),
    );
  }

  Future<void> plan(PlanTicketParams params) async {
    emit(const TicketActionBusyState());
    final result = await _repository.planTicket(params);
    TelemetryRuntime.featureUsed('ticket_plan', succeeded: result.isSuccess);
    _emitSession(result, (response) => response.data);
  }

  Future<void> review(ReviewPlanParams params) async {
    emit(const TicketActionBusyState());
    final result = await _repository.reviewPlan(params);
    TelemetryRuntime.featureUsed('ticket_review', succeeded: result.isSuccess);
    _emitSession(result, (response) => response.data?.session);
  }

  Future<void> merge(String projectId, String slug, String planFile) =>
      _updateTicket('ticket_merge', () => _repository.mergePlan(projectId, slug, planFile));

  Future<void> markDone(String projectId, String slug, String planFile) =>
      _updateTicket('ticket_done', () => _repository.markPlanDone(projectId, slug, planFile));

  Future<void> archive(String projectId, String slug) =>
      _updateTicket('ticket_archive', () => _repository.archiveTicket(projectId, slug));

  Future<void> unarchive(String projectId, String slug) =>
      _updateTicket('ticket_unarchive', () => _repository.unarchiveTicket(projectId, slug));

  Future<void> _updateTicket(String feature, FutureResult<GlobalResponse<TicketModel>> Function() call) async {
    emit(const TicketActionBusyState());
    final result = await call();
    TelemetryRuntime.featureUsed(feature, succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) {
        final ticket = response.data;
        emit(ticket == null ? TicketActionFailureState(_missing('ticket')) : TicketUpdatedState(ticket));
      },
      onFailure: (failure) => emit(TicketActionFailureState(failure)),
    );
  }

  void _emitSession<T>(Result<GlobalResponse<T>, Failure> result, SessionModel? Function(GlobalResponse<T>) pick) {
    result.when(
      onSuccess: (response) {
        final session = pick(response);
        emit(session == null ? TicketActionFailureState(_missing('session')) : TicketSessionStartedState(session));
      },
      onFailure: (failure) => emit(TicketActionFailureState(failure)),
    );
  }

  static Failure _missing(String what) =>
      ServerFailure<Map<String, dynamic>>(error: 'missing $what', message: 'The daemon answered without a $what.');
}
```

`service_locator.dart`: `sl.registerFactory<TicketActionsCubit>(() => TicketActionsCubit(sl<TicketsRepository>()));` next to the other cubit factories (`:159-161` area), with the import.

`routes_strings.dart`: add `static const String ticket = '/ticket';` after `usage`. (The router case lands in Task 11; until then the board's `Open` action is not wired.)

- [ ] **Step 4: Run the cubit test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit_test.dart`
Expected: all pass.

- [ ] **Step 5: Write the failing sheet test**

`test/feature/tickets/presentation/ticket_actions/ui/create_ticket_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/create_ticket_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';

class _MockTicketActionsCubit extends MockCubit<TicketActionsState> implements TicketActionsCubit {}

void main() {
  late _MockTicketActionsCubit cubit;

  setUpAll(() => registerFallbackValue(const CreateTicketParams(projectId: 'p', title: 't')));

  setUp(() {
    cubit = _MockTicketActionsCubit();
    when(() => cubit.state).thenReturn(const TicketActionsInitialState());
    when(() => cubit.create(any())).thenAnswer((_) async {});
  });

  Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(body: BlocProvider<TicketActionsCubit>.value(value: cubit, child: child)),
      ),
    ),
  );

  testWidgets('Create is disabled until a title is typed, then sends title and brief', (tester) async {
    await tester.pumpWidget(host(const CreateTicketSheetBody(projectId: 'repo', projectName: 'repo')));

    expect(find.text('New ticket'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Create')).enabled, isFalse);

    await tester.enterText(find.byKey(const Key('ticket-title')), 'Search page');
    await tester.enterText(find.byKey(const Key('ticket-brief')), 'Full-text search over docs');
    await tester.pump();
    await tester.tap(find.text('Create'));

    verify(() => cubit.create(const CreateTicketParams(projectId: 'repo', title: 'Search page', brief: 'Full-text search over docs'))).called(1);
  });

  testWidgets('a failure shows the message and the request id', (tester) async {
    when(() => cubit.state).thenReturn(TicketActionFailureState(ServerFailure<Map<String, dynamic>>(
      error: 'x',
      message: 'Tickets need a single-repository project.',
      validationErrors: const {'requestId': 'req-9'},
    )));
    await tester.pumpWidget(host(const CreateTicketSheetBody(projectId: 'scratch', projectName: 'scratch')));

    expect(find.byType(TicketFailureText), findsOneWidget);
    expect(find.text('Tickets need a single-repository project.'), findsOneWidget);
    expect(find.text('request req-9'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run the sheet test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/ui/create_ticket_sheet_test.dart`
Expected: compile error, `CreateTicketSheetBody` not found.

- [ ] **Step 7: Write the failure text, the create sheet and the ticket actions sheet**

`ticket_failure_text.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';

class TicketFailureText extends StatelessWidget {
  const TicketFailureText({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final requestId = failureRequestId(failure);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(failure.message, style: AppTextStyle.style13Regular.copyWith(color: skin.red), maxLines: 4),
        if (requestId != null) ...[
          const VerticalSpace(2),
          AppText('request $requestId', style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint)),
        ],
      ],
    );
  }
}
```

`create_ticket_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_toast.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/create_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/logic/assign_rules.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';

Future<void> showCreateTicketSheet(BuildContext context, {String? projectId}) async {
  final sessions = sl<SessionsCubit>();
  final repos = sessions.projects.where((project) => project.kind == 'single_repo').toList();
  var chosen = projectId ?? (sessions.activeProjectId == kAllProjects ? null : sessions.activeProjectId);
  if (chosen == null && repos.length == 1) chosen = repos.first.id;
  if (chosen == null) {
    chosen = await showProjectPickerSheet(
      context,
      projects: repos,
      selected: '',
      includeAll: false,
      title: 'Project',
      subtitle: 'Tickets need a single-repository project.',
    );
  }
  if (chosen == null || !context.mounted) return;
  final name = repos.where((project) => project.id == chosen).firstOrNull?.name ?? chosen;
  final actions = sl<TicketActionsCubit>();
  await showExpressiveSheet<void>(
    context: context,
    builder: (_) => BlocProvider<TicketActionsCubit>.value(
      value: actions,
      child: AppSheetChrome(child: CreateTicketSheetBody(projectId: chosen!, projectName: name)),
    ),
  );
  await actions.close();
}

class CreateTicketSheetBody extends StatefulWidget {
  const CreateTicketSheetBody({super.key, required this.projectId, required this.projectName});

  final String projectId;
  final String projectName;

  @override
  State<CreateTicketSheetBody> createState() => _CreateTicketSheetBodyState();
}

class _CreateTicketSheetBodyState extends State<CreateTicketSheetBody> {
  final _title = TextEditingController();
  final _brief = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _brief.dispose();
    super.dispose();
  }

  void _submit() {
    Haptics.tap();
    context.read<TicketActionsCubit>().create(
      CreateTicketParams(projectId: widget.projectId, title: _title.text.trim(), brief: _brief.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocConsumer<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketCreatedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          final warnings = state.warnings.map(assignWarningLabel).join(' ');
          AppToast.show(context, message: warnings.isEmpty ? 'Created ${state.ticket.title ?? state.ticket.slug}' : warnings);
          Navigator.of(context).pop();
        }
        if (state is TicketActionFailureState) Haptics.error();
      },
      builder: (context, state) {
        final busy = state is TicketActionBusyState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('New ticket', style: AppTextStyle.style17SemiBold),
            const VerticalSpace(4),
            AppText(
              'A ticket is a folder in the repository holding a spec and its implementation plans.',
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 3,
            ),
            const VerticalSpace(6),
            AppText(widget.projectName, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
            const VerticalSpace(14),
            AppTextField(key: const Key('ticket-title'), controller: _title, label: 'TITLE', hintText: 'What are we building?', enabled: !busy),
            const VerticalSpace(12),
            AppTextField(
              key: const Key('ticket-brief'),
              controller: _brief,
              label: 'BRIEF',
              hintText: 'One paragraph the planning agent starts from',
              minLines: 2,
              maxLines: 5,
              enabled: !busy,
            ),
            if (state is TicketActionFailureState) ...[const VerticalSpace(10), TicketFailureText(failure: state.failure)],
            const VerticalSpace(16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
                  ),
                ),
                const HorizontalSpace(10),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _title,
                    builder: (context, value, _) => TextButton(
                      onPressed: busy || value.text.trim().isEmpty ? null : _submit,
                      child: AppText(busy ? 'Creating…' : 'Create', style: AppTextStyle.style15SemiBold.copyWith(color: skin.accent)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

`ticket_actions_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_toast.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';

Future<void> showTicketActionsSheet(
  BuildContext context,
  TicketModel ticket, {
  required SessionModel? planningSession,
  required VoidCallback onOpen,
  required VoidCallback onPlan,
  required void Function(String sessionId) onOpenSession,
}) {
  final actions = sl<TicketActionsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => BlocProvider<TicketActionsCubit>.value(
      value: actions,
      child: TicketActionsSheet(
        ticket: ticket,
        planningSession: planningSession,
        onOpen: onOpen,
        onPlan: onPlan,
        onOpenSession: onOpenSession,
      ),
    ),
  ).whenComplete(actions.close);
}

class TicketActionsSheet extends StatelessWidget {
  const TicketActionsSheet({
    super.key,
    required this.ticket,
    required this.planningSession,
    required this.onOpen,
    required this.onPlan,
    required this.onOpenSession,
  });

  final TicketModel ticket;
  final SessionModel? planningSession;
  final VoidCallback onOpen;
  final VoidCallback onPlan;
  final void Function(String sessionId) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TicketActionsCubit>();
    final archived = isTicketInArchive(ticket);
    final planning = planningSessionLive(planningSession);
    final projectId = ticket.projectId ?? '';
    final slug = ticket.slug ?? '';

    return BlocListener<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketUpdatedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          Navigator.of(context).pop();
        }
        if (state is TicketActionFailureState) {
          Haptics.error();
          AppToast.show(context, message: state.failure.message, destructive: true);
          Navigator.of(context).pop();
        }
      },
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: AppText(ticket.title ?? slug, style: AppTextStyle.style14SemiBold),
              subtitle: AppText(slug, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
            ),
            ListTile(
              leading: Icon(Icons.description_outlined, color: skin.textSecondary),
              title: const AppText('Open'),
              onTap: () {
                Haptics.tap();
                Navigator.of(context).pop();
                onOpen();
              },
            ),
            if (!archived)
              planning
                  ? ListTile(
                      leading: Icon(Icons.terminal, color: skin.orange),
                      title: const AppText('Open planning session'),
                      onTap: () {
                        Haptics.tap();
                        Navigator.of(context).pop();
                        onOpenSession(planningSession!.id!);
                      },
                    )
                  : ListTile(
                      leading: Icon(Icons.auto_awesome_outlined, color: skin.accent),
                      title: const AppText('Plan with agent'),
                      onTap: () {
                        Haptics.tap();
                        Navigator.of(context).pop();
                        onPlan();
                      },
                    ),
            if (archived && ticket.status == 'archived')
              ListTile(
                leading: Icon(Icons.unarchive_outlined, color: skin.accent),
                title: const AppText('Reopen'),
                onTap: () {
                  Haptics.tap();
                  cubit.unarchive(projectId, slug);
                },
              )
            else if (ticket.status != 'archived')
              ListTile(
                leading: Icon(Icons.archive_outlined, color: skin.red),
                title: AppText('Archive', style: AppTextStyle.style14Regular.copyWith(color: skin.red)),
                onTap: () async {
                  Haptics.tap();
                  final confirmed = await AppDialog.confirm(
                    context,
                    title: 'Archive ticket?',
                    message: 'Hides ${ticket.title ?? slug} from the board. You can reopen it from the archive.',
                    confirmLabel: 'Archive',
                    destructive: true,
                  );
                  if (!context.mounted || !confirmed) return;
                  cubit.archive(projectId, slug);
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets`
Expected: all pass.

- [ ] **Step 9: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): ticket actions cubit, New ticket sheet, Archive and Reopen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Spawn fields and the `Plan with agent` sheet

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/plan_ticket_sheet.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/ticket_spawn_fields_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/plan_ticket_sheet_test.dart`

**Interfaces:**
- Consumes: `SpawnCubit` (`spawn_cubit.dart:14-134`: `agents`, `harness`, `claudeAccounts`, `claudeAccountId`, `setHarness`, `setClaudeAccount`, `loadCatalog`, `refreshCatalog`, states `CatalogLoadingState`/`CatalogReadyState`/`CatalogFailureState`), `showAgentPickerSheet` (`agent_picker_sheet.dart:14-21`), `showClaudeAccountPickerSheet` (`claude_account_picker_sheet.dart:12-16`), `SettingsGroup`/`SettingsRow`, `AgentLogo`, `AppTextField`, `TicketActionsCubit.plan`, `RoutesStrings.session`.
- Produces: `TicketSpawnFields({required SpawnCubit spawn, required TextEditingController model, required TextEditingController extra, bool enabled})`, `TicketSpawnChoice ticketSpawnChoice(SpawnCubit spawn, TextEditingController model, TextEditingController extra)` where `typedef TicketSpawnChoice = ({String? harness, String? claudeAccountId, String? model, String? extra})` (empty strings become null), `Future<void> showPlanTicketSheet(BuildContext context, TicketModel ticket)`, `PlanTicketSheetBody(ticket:)`.

- [ ] **Step 1: Write the failing tests**

`test/feature/tickets/presentation/ticket_actions/ui/ticket_spawn_fields_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

class _MockSpawnCubit extends MockCubit<SpawnState> implements SpawnCubit {}

const _ranked = [
  RankedAgent(id: 'claude-code', label: 'Claude Code', availability: AgentAvailability.authorized, status: '', selectable: true),
];

void main() {
  late _MockSpawnCubit spawn;
  late TextEditingController model;
  late TextEditingController extra;

  setUp(() {
    spawn = _MockSpawnCubit();
    when(() => spawn.state).thenReturn(const CatalogReadyState(1));
    when(() => spawn.agents).thenReturn(_ranked);
    when(() => spawn.harness).thenReturn('claude-code');
    when(() => spawn.claudeAccounts).thenReturn(const [ClaudeAccountModel(id: 'default', label: 'Default', loggedIn: true, subscriptionType: 'max')]);
    when(() => spawn.claudeAccountId).thenReturn('default');
    model = TextEditingController();
    extra = TextEditingController();
  });

  tearDown(() {
    model.dispose();
    extra.dispose();
  });

  Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(body: SingleChildScrollView(child: BlocProvider<SpawnCubit>.value(value: spawn, child: child))),
      ),
    ),
  );

  testWidgets('shows agent, account, model and extra fields with the defaults hint', (tester) async {
    await tester.pumpWidget(host(TicketSpawnFields(spawn: spawn, model: model, extra: extra)));

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Default · Max'), findsOneWidget);
    expect(find.text('MODEL'), findsOneWidget);
    expect(find.text('EXTRA INSTRUCTIONS'), findsOneWidget);
    expect(find.text("Empty fields use the project's ticket defaults."), findsOneWidget);
  });

  testWidgets('hides the account row for a non-Claude harness', (tester) async {
    when(() => spawn.harness).thenReturn('codex');
    await tester.pumpWidget(host(TicketSpawnFields(spawn: spawn, model: model, extra: extra)));
    expect(find.text('Account'), findsNothing);
  });

  test('ticketSpawnChoice trims and nulls empty fields, sends the account only for claude-code', () {
    model.text = '  claude-haiku-4-5-20251001 ';
    expect(
      ticketSpawnChoice(spawn, model, extra),
      (harness: 'claude-code', claudeAccountId: 'default', model: 'claude-haiku-4-5-20251001', extra: null),
    );
    when(() => spawn.harness).thenReturn('codex');
    extra.text = 'be brief';
    expect(ticketSpawnChoice(spawn, model, extra), (harness: 'codex', claudeAccountId: null, model: 'claude-haiku-4-5-20251001', extra: 'be brief'));
    when(() => spawn.harness).thenReturn('');
    expect(ticketSpawnChoice(spawn, model, extra).harness, isNull);
  });
}
```

`test/feature/tickets/presentation/ticket_actions/ui/plan_ticket_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/plan_ticket_sheet.dart';

class _MockSpawnCubit extends MockCubit<SpawnState> implements SpawnCubit {}

class _MockTicketActionsCubit extends MockCubit<TicketActionsState> implements TicketActionsCubit {}

void main() {
  late _MockSpawnCubit spawn;
  late _MockTicketActionsCubit actions;

  setUpAll(() => registerFallbackValue(const PlanTicketParams(projectId: 'p', slug: 's')));

  setUp(() {
    spawn = _MockSpawnCubit();
    actions = _MockTicketActionsCubit();
    when(() => spawn.state).thenReturn(const CatalogReadyState(1));
    when(() => spawn.agents).thenReturn(const [
      RankedAgent(id: 'codex', label: 'Codex', availability: AgentAvailability.authorized, status: '', selectable: true),
    ]);
    when(() => spawn.harness).thenReturn('codex');
    when(() => spawn.claudeAccounts).thenReturn(const []);
    when(() => spawn.claudeAccountId).thenReturn('default');
    when(() => actions.state).thenReturn(const TicketActionsInitialState());
    when(() => actions.plan(any())).thenAnswer((_) async {});
  });

  testWidgets('Start sends the ticket, harness, model and extra to plan()', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SpawnCubit>.value(value: spawn),
                  BlocProvider<TicketActionsCubit>.value(value: actions),
                ],
                child: const SingleChildScrollView(
                  child: PlanTicketSheetBody(ticket: TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Plan with agent'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ticket-model')), 'claude-haiku-4-5-20251001');
    await tester.enterText(find.byKey(const Key('ticket-extra')), 'Keep the spec short.');
    await tester.tap(find.text('Start'));

    verify(() => actions.plan(const PlanTicketParams(
      projectId: 'repo',
      slug: 'search-page',
      harness: 'codex',
      model: 'claude-haiku-4-5-20251001',
      extra: 'Keep the spec short.',
    ))).called(1);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/ui`
Expected: compile errors for the two new files.

- [ ] **Step 3: Write the widgets**

`ticket_spawn_fields.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/agent_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/claude_account_picker_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

typedef TicketSpawnChoice = ({String? harness, String? claudeAccountId, String? model, String? extra});

String? _nullIfEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

TicketSpawnChoice ticketSpawnChoice(SpawnCubit spawn, TextEditingController model, TextEditingController extra) => (
  harness: _nullIfEmpty(spawn.harness),
  claudeAccountId: spawn.harness == 'claude-code' ? _nullIfEmpty(spawn.claudeAccountId) : null,
  model: _nullIfEmpty(model.text),
  extra: _nullIfEmpty(extra.text),
);

class TicketSpawnFields extends StatelessWidget {
  const TicketSpawnFields({
    super.key,
    required this.spawn,
    required this.model,
    required this.extra,
    this.enabled = true,
  });

  final SpawnCubit spawn;
  final TextEditingController model;
  final TextEditingController extra;
  final bool enabled;

  RankedAgent? _selected() {
    for (final agent in spawn.agents) {
      if (agent.id == spawn.harness) return agent;
    }
    return null;
  }

  String _accountValue() {
    for (final account in spawn.claudeAccounts) {
      if (account.id == spawn.claudeAccountId) return account.displayLabel;
    }
    return 'Default';
  }

  Future<void> _pickAgent(BuildContext context, SpawnState state) async {
    final chosen = await showAgentPickerSheet(
      context,
      agents: spawn.agents,
      selected: spawn.harness,
      onRefresh: spawn.refreshCatalog,
      error: state is CatalogFailureState ? 'Could not reach your Operator server' : null,
    );
    if (chosen != null) spawn.setHarness(chosen);
  }

  Future<void> _pickAccount(BuildContext context) async {
    final chosen = await showClaudeAccountPickerSheet(context, accounts: spawn.claudeAccounts, selected: spawn.claudeAccountId);
    if (chosen != null) spawn.setClaudeAccount(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpawnCubit, SpawnState>(
      bloc: spawn,
      builder: (context, state) {
        final selected = _selected();
        final agentValue = selected?.label ?? (state is CatalogLoadingState ? 'Loading…' : 'Choose an agent');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsGroup(
              footer: "Empty fields use the project's ticket defaults.",
              children: [
                SettingsRow(
                  label: 'Agent',
                  value: agentValue,
                  leading: AgentLogo(harness: spawn.harness.isEmpty ? null : spawn.harness, size: 20),
                  disabled: !enabled,
                  onTap: enabled ? () => _pickAgent(context, state) : null,
                ),
                if (spawn.harness == 'claude-code' && spawn.claudeAccounts.isNotEmpty)
                  SettingsRow(
                    icon: Icons.person_outline,
                    label: 'Account',
                    value: _accountValue(),
                    disabled: !enabled,
                    onTap: enabled ? () => _pickAccount(context) : null,
                  ),
              ],
            ),
            const VerticalSpace(14),
            AppTextField(
              key: const Key('ticket-model'),
              controller: model,
              label: 'MODEL',
              hintText: 'claude-haiku-4-5-20251001',
              autocorrect: false,
              enabled: enabled,
            ),
            const VerticalSpace(12),
            AppTextField(
              key: const Key('ticket-extra'),
              controller: extra,
              label: 'EXTRA INSTRUCTIONS',
              hintText: 'Optional notes appended to the prompt',
              minLines: 2,
              maxLines: 5,
              enabled: enabled,
            ),
          ],
        );
      },
    );
  }
}
```

`plan_ticket_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/plan_ticket_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

Future<void> showPlanTicketSheet(BuildContext context, TicketModel ticket) async {
  final actions = sl<TicketActionsCubit>();
  final spawn = sl<SpawnCubit>()..loadCatalog();
  await showExpressiveSheet<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider<TicketActionsCubit>.value(value: actions),
        BlocProvider<SpawnCubit>.value(value: spawn),
      ],
      child: AppSheetChrome(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: PlanTicketSheetBody(ticket: ticket),
        ),
      ),
    ),
  );
  await actions.close();
  await spawn.close();
}

class PlanTicketSheetBody extends StatefulWidget {
  const PlanTicketSheetBody({super.key, required this.ticket});

  final TicketModel ticket;

  @override
  State<PlanTicketSheetBody> createState() => _PlanTicketSheetBodyState();
}

class _PlanTicketSheetBodyState extends State<PlanTicketSheetBody> {
  final _model = TextEditingController();
  final _extra = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    _extra.dispose();
    super.dispose();
  }

  void _start() {
    Haptics.tap();
    final choice = ticketSpawnChoice(context.read<SpawnCubit>(), _model, _extra);
    context.read<TicketActionsCubit>().plan(PlanTicketParams(
      projectId: widget.ticket.projectId ?? '',
      slug: widget.ticket.slug ?? '',
      harness: choice.harness,
      model: choice.model,
      claudeAccountId: choice.claudeAccountId,
      extra: choice.extra,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocConsumer<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketSessionStartedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.pushNamed(RoutesStrings.session, arguments: {'sessionId': state.session.id});
        }
        if (state is TicketActionFailureState) Haptics.error();
      },
      builder: (context, state) {
        final busy = state is TicketActionBusyState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('Plan with agent', style: AppTextStyle.style17SemiBold),
            const VerticalSpace(4),
            AppText(
              'Starts the planning session in place at the project root. It writes the spec and the implementation plans into the ticket folder.',
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 4,
            ),
            const VerticalSpace(6),
            AppText(widget.ticket.title ?? widget.ticket.slug ?? '', style: AppTextStyle.style13SemiBold),
            const VerticalSpace(14),
            TicketSpawnFields(spawn: context.read<SpawnCubit>(), model: _model, extra: _extra, enabled: !busy),
            if (state is TicketActionFailureState) ...[const VerticalSpace(10), TicketFailureText(failure: state.failure)],
            const VerticalSpace(16),
            PrimaryButton.expand(
              text: busy ? 'Starting…' : 'Start',
              isLoading: busy,
              fixedSize: const Size.fromHeight(46),
              onPressed: busy ? null : _start,
            ),
            const VerticalSpace(4),
            Center(
              child: TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/ui`
Expected: all pass. If `PrimaryButton` renders its `text` inside a widget the finder cannot see while `isLoading` is false, check `primary_button.dart:95-160` and use `find.widgetWithText(PrimaryButton, 'Start')`.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib/feature/tickets packages/mobile/test/feature/tickets
git commit -m "feat(mobile): shared spawn fields and the Plan with agent sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Assign / Reassign — cubit and sheet

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/logic/assign_plan_state.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/assign_plan_sheet.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (register `AssignPlanCubit` with `registerFactoryParam<AssignPlanCubit, AssignPlanTarget, void>`)
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/assign_plan_sheet_test.dart`

**Interfaces:**
- Consumes: `TicketsRepository.assignPlan/getTicket`, `SessionsRepository.kill` (`sessions_repository.dart:10`), `assign_rules.dart`, `ticket_presentation.dart` (`planBranchName`, `planNumber`, `planTitle`), `TicketSpawnFields`, `ticketSpawnChoice`, `SpawnCubit`.
- Produces: `class AssignPlanTarget { String projectId; String slug; PlanModel plan; }`; `AssignPlanCubit(TicketsRepository, SessionsRepository, AssignPlanTarget)` with `List<String> warnings`, `Future<void> check()`, `Future<void> start(TicketSpawnChoice choice)`; states `AssignPlanInitialState`, `AssignPlanCheckingState`, `AssignPlanReadyState(warnings)`, `AssignPlanSubmittingState`, `AssignPlanBlockedState(warnings)`, `AssignPlanStartedState(session)`, `AssignPlanFailureState(failure)`; `Future<void> showAssignPlanSheet(BuildContext, {required TicketModel ticket, required PlanModel plan, required String projectName})`; `AssignPlanSheetBody(ticket:, plan:, projectName:)`.
- Daemon contract: dry run `POST …/assign?dryRun=1` → `200 {warnings}`; live `POST …/assign` → `409 TICKET_ASSIGN_BLOCKED` with `details.warnings` unless `force` (`backend/internal/service/ticket/service.go:566-621`, `:580`); `force` never kills (`service.go:566-621`); kill is `POST /api/v1/sessions/{id}/kill` (`EndPoints.sessionKill`).

- [ ] **Step 1: Write the failing cubit test**

`test/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_action_results.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit.dart';

class _MockTicketsRepository extends Mock implements TicketsRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

const _plan = PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo');
const _target = AssignPlanTarget(projectId: 'repo', slug: 'search-page', plan: _plan);
const _choice = (harness: 'claude-code', claudeAccountId: 'default', model: 'claude-haiku-4-5-20251001', extra: null);

final _dryRun = isA<AssignPlanParams>().having((p) => p.dryRun, 'dryRun', isTrue);
final _live = isA<AssignPlanParams>().having((p) => p.dryRun, 'dryRun', isFalse);

void main() {
  late _MockTicketsRepository tickets;
  late _MockSessionsRepository sessions;

  setUpAll(() => registerFallbackValue(const AssignPlanParams(projectId: 'p', slug: 's', planFile: 'f')));

  setUp(() {
    tickets = _MockTicketsRepository();
    sessions = _MockSessionsRepository();
    when(() => sessions.kill(any())).thenAnswer((_) async => Result.success(true));
    when(() => tickets.getTicket('repo', 'search-page')).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: TicketModel(slug: 'search-page', plans: [_plan]))),
    );
  });

  void dryRunReturns(List<List<String>> sequence) {
    var index = 0;
    when(() => tickets.assignPlan(any(that: _dryRun))).thenAnswer((_) async {
      final warnings = sequence[index < sequence.length ? index : sequence.length - 1];
      index++;
      return Result.success(GlobalResponse(data: AssignPlanResult(warnings: warnings)));
    });
  }

  void liveReturnsSession() {
    when(() => tickets.assignPlan(any(that: _live))).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: AssignPlanResult(session: SessionModel(id: 'repo-9', branch: 'opr/search-page-01')))),
    );
  }

  AssignPlanCubit build() => AssignPlanCubit(tickets, sessions, _target);

  blocTest<AssignPlanCubit, AssignPlanState>(
    'check runs the dry run and exposes its warnings',
    build: () {
      dryRunReturns([['ticket_repo_dirty']]);
      return build();
    },
    act: (cubit) => cubit.check(),
    expect: () => [const AssignPlanCheckingState(), const AssignPlanReadyState(['ticket_repo_dirty'])],
    verify: (cubit) => expect(cubit.warnings, ['ticket_repo_dirty']),
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'a clean start re-checks, sends no force and no kill, and reports the session',
    build: () {
      dryRunReturns([[]]);
      liveReturnsSession();
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    expect: () => [
      const AssignPlanCheckingState(),
      const AssignPlanReadyState([]),
      const AssignPlanSubmittingState(),
      const AssignPlanStartedState(SessionModel(id: 'repo-9', branch: 'opr/search-page-01')),
    ],
    verify: (_) {
      final params = verify(() => tickets.assignPlan(captureAny(that: _live))).captured.single as AssignPlanParams;
      expect(params.force, isFalse);
      expect(params.harness, 'claude-code');
      expect(params.model, 'claude-haiku-4-5-20251001');
      expect(params.claudeAccountId, 'default');
      expect(params.planFile, 'plans/01-index.md');
      verifyNever(() => sessions.kill(any()));
      verify(() => tickets.assignPlan(any(that: _dryRun))).called(2);
    },
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'warnings shown at check time are forced through on start',
    build: () {
      dryRunReturns([['ticket_repo_dirty']]);
      liveReturnsSession();
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    verify: (_) {
      final params = verify(() => tickets.assignPlan(captureAny(that: _live))).captured.single as AssignPlanParams;
      expect(params.force, isTrue);
      verifyNever(() => sessions.kill(any()));
    },
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'a 409 TICKET_ASSIGN_BLOCKED is adopted as the new warning list',
    build: () {
      dryRunReturns([[]]);
      when(() => tickets.assignPlan(any(that: _live))).thenAnswer(
        (_) async => Result.failure(ServerFailure<Map<String, dynamic>>(
          error: 'conflict',
          message: 'Assignment needs confirmation',
          statusCode: 409,
          apiStatus: 'TICKET_ASSIGN_BLOCKED',
          validationErrors: const {'warnings': ['plan_assigned'], 'requestId': 'req-1'},
        )),
      );
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    expect: () => [
      const AssignPlanCheckingState(),
      const AssignPlanReadyState([]),
      const AssignPlanSubmittingState(),
      const AssignPlanBlockedState(['plan_assigned']),
    ],
    verify: (cubit) => expect(cubit.warnings, ['plan_assigned']),
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'a warning that appears at submit time stops the spawn instead of forcing past it',
    build: () {
      dryRunReturns([[], ['plan_assigned']]);
      liveReturnsSession();
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    expect: () => [
      const AssignPlanCheckingState(),
      const AssignPlanReadyState([]),
      const AssignPlanSubmittingState(),
      const AssignPlanBlockedState(['plan_assigned']),
    ],
    verify: (_) {
      verifyNever(() => tickets.assignPlan(any(that: _live)));
      verifyNever(() => sessions.kill(any()));
    },
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'Terminate and start kills the freshly fetched live session before the forced assign',
    build: () {
      dryRunReturns([['plan_assigned']]);
      liveReturnsSession();
      when(() => tickets.getTicket('repo', 'search-page')).thenAnswer(
        (_) async => Result.success(const GlobalResponse(
          data: TicketModel(
            slug: 'search-page',
            plans: [PlanModel(file: 'plans/01-index.md', order: 1, status: 'working', sessionId: 'repo-10')],
          ),
        )),
      );
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    expect: () => [
      const AssignPlanCheckingState(),
      const AssignPlanReadyState(['plan_assigned']),
      const AssignPlanSubmittingState(),
      const AssignPlanStartedState(SessionModel(id: 'repo-9', branch: 'opr/search-page-01')),
    ],
    verify: (_) {
      verifyInOrder([
        () => tickets.getTicket('repo', 'search-page'),
        () => sessions.kill('repo-10'),
        () => tickets.assignPlan(any(that: _live.having((p) => p.force, 'force', isTrue))),
      ]);
    },
  );

  blocTest<AssignPlanCubit, AssignPlanState>(
    'a failed kill stops before the assign',
    build: () {
      dryRunReturns([['plan_assigned']]);
      liveReturnsSession();
      when(() => tickets.getTicket('repo', 'search-page')).thenAnswer(
        (_) async => Result.success(const GlobalResponse(
          data: TicketModel(slug: 'search-page', plans: [PlanModel(file: 'plans/01-index.md', status: 'working', sessionId: 'repo-10')]),
        )),
      );
      when(() => sessions.kill('repo-10')).thenAnswer(
        (_) async => Result.failure(ServerFailure<Map<String, dynamic>>(error: 'x', message: 'Session no longer exists', statusCode: 404)),
      );
      return build();
    },
    act: (cubit) async {
      await cubit.check();
      await cubit.start(_choice);
    },
    verify: (cubit) {
      expect(cubit.state, isA<AssignPlanFailureState>());
      verifyNever(() => tickets.assignPlan(any(that: _live)));
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit_test.dart`
Expected: compile error.

- [ ] **Step 3: Write the cubit**

`assign_plan_state.dart`:

```dart
part of 'assign_plan_cubit.dart';

sealed class AssignPlanState extends Equatable {
  const AssignPlanState();

  @override
  List<Object?> get props => [];
}

final class AssignPlanInitialState extends AssignPlanState {
  const AssignPlanInitialState();
}

final class AssignPlanCheckingState extends AssignPlanState {
  const AssignPlanCheckingState();
}

final class AssignPlanReadyState extends AssignPlanState {
  const AssignPlanReadyState(this.warnings);

  final List<String> warnings;

  @override
  List<Object?> get props => [warnings];
}

final class AssignPlanSubmittingState extends AssignPlanState {
  const AssignPlanSubmittingState();
}

final class AssignPlanBlockedState extends AssignPlanState {
  const AssignPlanBlockedState(this.warnings);

  final List<String> warnings;

  @override
  List<Object?> get props => [warnings];
}

final class AssignPlanStartedState extends AssignPlanState {
  const AssignPlanStartedState(this.session);

  final SessionModel session;

  @override
  List<Object?> get props => [session];
}

final class AssignPlanFailureState extends AssignPlanState {
  const AssignPlanFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
```

`assign_plan_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/assign_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';
import 'package:operator_mobile/feature/tickets/logic/assign_rules.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

part 'assign_plan_state.dart';

class AssignPlanTarget extends Equatable {
  const AssignPlanTarget({required this.projectId, required this.slug, required this.plan});

  final String projectId;
  final String slug;
  final PlanModel plan;

  @override
  List<Object?> get props => [projectId, slug, plan];
}

class AssignPlanCubit extends Cubit<AssignPlanState> {
  AssignPlanCubit(this._tickets, this._sessions, this.target) : super(const AssignPlanInitialState());

  final TicketsRepository _tickets;
  final SessionsRepository _sessions;
  final AssignPlanTarget target;

  List<String> warnings = const [];

  AssignPlanParams _params({TicketSpawnChoice? choice, bool dryRun = false, bool force = false}) => AssignPlanParams(
    projectId: target.projectId,
    slug: target.slug,
    planFile: target.plan.file ?? '',
    harness: choice?.harness,
    model: choice?.model,
    claudeAccountId: choice?.claudeAccountId,
    extra: choice?.extra,
    force: force,
    dryRun: dryRun,
  );

  Future<void> check() async {
    emit(const AssignPlanCheckingState());
    final result = await _tickets.assignPlan(_params(dryRun: true));
    result.when(
      onSuccess: (response) {
        warnings = response.data?.warnings ?? const [];
        emit(AssignPlanReadyState(warnings));
      },
      onFailure: (failure) => emit(AssignPlanFailureState(failure)),
    );
  }

  Future<void> start(TicketSpawnChoice choice) async {
    emit(const AssignPlanSubmittingState());
    final current = await _recheck();
    if (newAssignWarnings(warnings, current).isNotEmpty) {
      warnings = current;
      emit(AssignPlanBlockedState(current));
      return;
    }
    if (current.contains('plan_assigned')) {
      final liveId = await _liveSessionId();
      if (liveId != null) {
        final killed = await _sessions.kill(liveId);
        if (killed.isFailure) {
          killed.when(onSuccess: (_) {}, onFailure: (failure) => emit(AssignPlanFailureState(failure)));
          return;
        }
      }
    }
    final result = await _tickets.assignPlan(_params(choice: choice, force: needsForce(current)));
    TelemetryRuntime.featureUsed('ticket_assign', succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) {
        final session = response.data?.session;
        if (session == null) {
          emit(AssignPlanFailureState(ServerFailure<Map<String, dynamic>>(error: 'missing session', message: 'The daemon answered without a session.')));
          return;
        }
        emit(AssignPlanStartedState(session));
      },
      onFailure: (failure) {
        final adopted = _blockedWarnings(failure);
        if (adopted == null) {
          emit(AssignPlanFailureState(failure));
          return;
        }
        warnings = adopted;
        emit(AssignPlanBlockedState(adopted));
      },
    );
  }

  Future<List<String>> _recheck() async {
    final result = await _tickets.assignPlan(_params(dryRun: true));
    return result.valueOrNull?.data?.warnings ?? warnings;
  }

  Future<String?> _liveSessionId() async {
    final result = await _tickets.getTicket(target.projectId, target.slug);
    final plans = result.valueOrNull?.data?.plans ?? const <PlanModel>[];
    for (final plan in plans) {
      if (plan.file == target.plan.file && plan.sessionId != null && plan.sessionId!.isNotEmpty) return plan.sessionId;
    }
    final fallback = target.plan.sessionId;
    return fallback != null && fallback.isNotEmpty ? fallback : null;
  }

  static List<String>? _blockedWarnings(Failure failure) {
    if (failure.apiStatus != 'TICKET_ASSIGN_BLOCKED') return null;
    final details = failure.validationErrors;
    if (details is! Map<String, dynamic>) return const [];
    return (details['warnings'] as List<dynamic>? ?? const []).whereType<String>().toList();
  }
}
```

`service_locator.dart`:

```dart
    sl.registerFactoryParam<AssignPlanCubit, AssignPlanTarget, void>(
      (target, _) => AssignPlanCubit(sl<TicketsRepository>(), sl<SessionsRepository>(), target),
    );
```

- [ ] **Step 4: Run the cubit test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit_test.dart`
Expected: all seven pass.

- [ ] **Step 5: Write the failing sheet test**

`test/feature/tickets/presentation/ticket_actions/ui/assign_plan_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/assign_plan_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

class _MockSpawnCubit extends MockCubit<SpawnState> implements SpawnCubit {}

class _MockAssignPlanCubit extends MockCubit<AssignPlanState> implements AssignPlanCubit {}

const _ticket = TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page');
const _plan = PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo');

void main() {
  late _MockSpawnCubit spawn;
  late _MockAssignPlanCubit assign;

  setUpAll(() => registerFallbackValue<TicketSpawnChoice>((harness: null, claudeAccountId: null, model: null, extra: null)));

  setUp(() {
    spawn = _MockSpawnCubit();
    assign = _MockAssignPlanCubit();
    when(() => spawn.state).thenReturn(const CatalogReadyState(1));
    when(() => spawn.agents).thenReturn(const [
      RankedAgent(id: 'codex', label: 'Codex', availability: AgentAvailability.authorized, status: '', selectable: true),
    ]);
    when(() => spawn.harness).thenReturn('codex');
    when(() => spawn.claudeAccounts).thenReturn(const []);
    when(() => spawn.claudeAccountId).thenReturn('default');
    when(() => assign.start(any())).thenAnswer((_) async {});
  });

  Widget host() => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SpawnCubit>.value(value: spawn),
              BlocProvider<AssignPlanCubit>.value(value: assign),
            ],
            child: const SingleChildScrollView(child: AssignPlanSheetBody(ticket: _ticket, plan: _plan, projectName: 'repo')),
          ),
        ),
      ),
    ),
  );

  testWidgets('shows the read-only rows, the branch hint and Checking… while the dry run runs', (tester) async {
    when(() => assign.state).thenReturn(const AssignPlanCheckingState());
    when(() => assign.warnings).thenReturn(const []);
    await tester.pumpWidget(host());

    expect(find.text('Assign 01 Index'), findsOneWidget);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('01 Index'), findsOneWidget);
    expect(find.text('repo'), findsOneWidget);
    expect(find.text('opr/search-page-01'), findsOneWidget);
    expect(find.textContaining('numbered suffix'), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);
  });

  testWidgets('lists each warning in human copy and starts with Start', (tester) async {
    when(() => assign.state).thenReturn(const AssignPlanReadyState(['ticket_repo_dirty', 'plan_order']));
    when(() => assign.warnings).thenReturn(const ['ticket_repo_dirty', 'plan_order']);
    await tester.pumpWidget(host());

    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('uncommitted changes'), findsOneWidget);
    expect(find.text('An earlier plan in this ticket is not merged or done yet.'), findsOneWidget);
    await tester.tap(find.text('Start'));
    verify(() => assign.start((harness: 'codex', claudeAccountId: null, model: null, extra: null))).called(1);
  });

  testWidgets('relabels to Terminate and start when the plan already has a live session', (tester) async {
    when(() => assign.state).thenReturn(const AssignPlanBlockedState(['plan_assigned']));
    when(() => assign.warnings).thenReturn(const ['plan_assigned']);
    await tester.pumpWidget(host());

    expect(find.text('Terminate and start'), findsOneWidget);
    expect(find.text('The assignment needs confirmation.'), findsOneWidget);
    expect(find.text('This plan already has a live session. Starting again terminates it first.'), findsOneWidget);
  });

  testWidgets('a terminated plan opens as Reassign', (tester) async {
    when(() => assign.state).thenReturn(const AssignPlanReadyState([]));
    when(() => assign.warnings).thenReturn(const []);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SpawnCubit>.value(value: spawn),
                  BlocProvider<AssignPlanCubit>.value(value: assign),
                ],
                child: const SingleChildScrollView(
                  child: AssignPlanSheetBody(
                    ticket: _ticket,
                    plan: PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'terminated', sessionId: 'repo-4'),
                    projectName: 'repo',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Reassign 01 Index'), findsOneWidget);
    expect(find.text('Before you start'), findsNothing);
  });
}
```

- [ ] **Step 6: Run the sheet test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/ui/assign_plan_sheet_test.dart`
Expected: compile error.

- [ ] **Step 7: Write the sheet**

`assign_plan_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/assign_rules.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/assign_plan_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

Future<void> showAssignPlanSheet(
  BuildContext context, {
  required TicketModel ticket,
  required PlanModel plan,
  required String projectName,
}) async {
  final target = AssignPlanTarget(projectId: ticket.projectId ?? '', slug: ticket.slug ?? '', plan: plan);
  final assign = sl<AssignPlanCubit>(param1: target)..check();
  final spawn = sl<SpawnCubit>()..loadCatalog();
  await showExpressiveSheet<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider<AssignPlanCubit>.value(value: assign),
        BlocProvider<SpawnCubit>.value(value: spawn),
      ],
      child: AppSheetChrome(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: AssignPlanSheetBody(ticket: ticket, plan: plan, projectName: projectName),
        ),
      ),
    ),
  );
  await assign.close();
  await spawn.close();
}

class AssignPlanSheetBody extends StatefulWidget {
  const AssignPlanSheetBody({super.key, required this.ticket, required this.plan, required this.projectName});

  final TicketModel ticket;
  final PlanModel plan;
  final String projectName;

  @override
  State<AssignPlanSheetBody> createState() => _AssignPlanSheetBodyState();
}

class _AssignPlanSheetBodyState extends State<AssignPlanSheetBody> {
  final _model = TextEditingController();
  final _extra = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    _extra.dispose();
    super.dispose();
  }

  String get _planLabel {
    final number = planNumber(widget.plan.file ?? '');
    final title = planTitle(widget.plan);
    return number.isEmpty ? title : '$number $title';
  }

  void _start() {
    Haptics.tap();
    context.read<AssignPlanCubit>().start(ticketSpawnChoice(context.read<SpawnCubit>(), _model, _extra));
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final slug = widget.ticket.slug ?? '';
    return BlocConsumer<AssignPlanCubit, AssignPlanState>(
      listener: (context, state) {
        if (state is AssignPlanStartedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.pushNamed(RoutesStrings.session, arguments: {'sessionId': state.session.id});
        }
        if (state is AssignPlanBlockedState || state is AssignPlanFailureState) Haptics.error();
      },
      builder: (context, state) {
        final cubit = context.read<AssignPlanCubit>();
        final warnings = cubit.warnings;
        final checking = state is AssignPlanCheckingState;
        final busy = state is AssignPlanSubmittingState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('${assignActionLabel(widget.plan)} $_planLabel', style: AppTextStyle.style17SemiBold, maxLines: 2),
            const VerticalSpace(4),
            AppText(
              'Starts an implementing session in a fresh worktree on the branch below. Its prompt says to implement only this plan.',
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 3,
            ),
            const VerticalSpace(14),
            SettingsGroup(
              footer: 'A repeat assignment of the same plan gets a numbered suffix; the session card shows the final branch.',
              children: [
                SettingsRow(icon: Icons.confirmation_number_outlined, label: 'Ticket', value: widget.ticket.title ?? slug),
                SettingsRow(icon: Icons.description_outlined, label: 'Plan', value: _planLabel),
                SettingsRow(icon: Icons.folder_outlined, label: 'Project', value: widget.projectName),
                SettingsRow(icon: Icons.call_split, label: 'Branch', value: planBranchName(slug, widget.plan.file ?? '')),
              ],
            ),
            if (checking || warnings.isNotEmpty) ...[
              const VerticalSpace(14),
              AppText('Before you start', style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6)),
              const VerticalSpace(6),
              if (checking)
                AppText('Checking…', style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary))
              else
                for (final code in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: skin.amber),
                        const HorizontalSpace(6),
                        Expanded(
                          child: AppText(assignWarningLabel(code), style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary), maxLines: 4),
                        ),
                      ],
                    ),
                  ),
            ],
            const VerticalSpace(14),
            TicketSpawnFields(spawn: context.read<SpawnCubit>(), model: _model, extra: _extra, enabled: !busy),
            if (state is AssignPlanBlockedState) ...[
              const VerticalSpace(10),
              AppText('The assignment needs confirmation.', style: AppTextStyle.style13Regular.copyWith(color: skin.red)),
            ],
            if (state is AssignPlanFailureState) ...[const VerticalSpace(10), TicketFailureText(failure: state.failure)],
            const VerticalSpace(16),
            PrimaryButton.expand(
              text: busy ? 'Starting…' : assignButtonLabel(warnings),
              isLoading: busy,
              isDestructive: warnings.contains('plan_assigned'),
              fixedSize: const Size.fromHeight(46),
              onPressed: busy || checking ? null : _start,
            ),
            const VerticalSpace(4),
            Center(
              child: TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

While the dry run runs, the button keeps its `Start` label but is disabled; `Checking…` appears once, in the "Before you start" section.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets`
Expected: all pass.

- [ ] **Step 9: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): assign and reassign plans with dry-run warnings, re-check and terminate-first

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Review, Merge confirmation, Mark done, and the plan actions sheet

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/review_plan_sheet.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/merge_plan_sheet.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_actions/ui/widgets/plan_actions_sheet.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/review_plan_sheet_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/merge_plan_sheet_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_actions/ui/plan_actions_sheet_test.dart`

**Interfaces:**
- Consumes: `TicketActionsCubit.review/merge/markDone`, `showAssignPlanSheet`, `TicketSpawnFields`, `AppPill`, `AppDialog.confirm`, `assign_rules.dart` predicates, `planNumber`/`planTitle`.
- Produces: `Future<void> showReviewPlanSheet(BuildContext, {required TicketModel ticket, required PlanModel plan})`, `ReviewPlanSheetBody(ticket:, plan:)`; `Future<void> showMergePlanSheet(BuildContext, {required TicketModel ticket, required PlanModel plan})`, `MergePlanSheetBody(ticket:, plan:)`; `Future<void> showPlanActionsSheet(BuildContext, {required TicketModel ticket, required PlanModel plan, required String projectName, required void Function(String sessionId) onOpenSession})`, `PlanActionsSheet(...)`; `String planLabel(PlanModel plan)` (`NN Title`) added to `logic/ticket_presentation.dart` in this task with its test, used here and in Task 8's sheet (replace `_planLabel` there with `planLabel(widget.plan)`).
- Spec §2.6: the reviewer is the planning session or a fresh session; Merge is a user confirmation that shows the reviewer's `mergeSummary` and moves the plan to `merging`; daemon `ReviewPlanRequest.reviewer` enum `planner|new` (`dto.go:1598-1604`), `merge` 409 codes `TICKET_NOT_MERGE_READY` / `TICKET_MERGE_APPROVED` (`en.json` `tickets.error.*` copy).

- [ ] **Step 1: Add `planLabel` with its test**

Append to `lib/feature/tickets/logic/ticket_presentation.dart`:

```dart
String planLabel(PlanModel plan) {
  final number = planNumber(plan.file ?? '');
  final title = planTitle(plan);
  return number.isEmpty ? title : '$number $title';
}
```

Append to `test/feature/tickets/logic/ticket_presentation_test.dart` inside `main()`:

```dart
  test('planLabel is NN Title, or the title alone for unordered plans', () {
    expect(planLabel(const PlanModel(file: 'plans/01-index.md', title: 'Index')), '01 Index');
    expect(planLabel(const PlanModel(file: 'plans/notes.md', title: 'Notes')), 'Notes');
  });
```

Replace `_planLabel` in `assign_plan_sheet.dart` (Task 8) with `planLabel(widget.plan)` and delete the private getter.

- [ ] **Step 2: Write the failing sheet tests**

`test/feature/tickets/presentation/ticket_actions/ui/review_plan_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/review_plan_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

class _MockSpawnCubit extends MockCubit<SpawnState> implements SpawnCubit {}

class _MockTicketActionsCubit extends MockCubit<TicketActionsState> implements TicketActionsCubit {}

const _ticket = TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page', planningSessionId: 'repo-3');
const _plan = PlanModel(file: 'plans/02-ui.md', order: 2, title: 'UI', status: 'idle', sessionId: 'repo-5');

void main() {
  late _MockSpawnCubit spawn;
  late _MockTicketActionsCubit actions;

  setUpAll(() => registerFallbackValue(const ReviewPlanParams(projectId: 'p', slug: 's', planFile: 'f', reviewer: 'planner')));

  setUp(() {
    spawn = _MockSpawnCubit();
    actions = _MockTicketActionsCubit();
    when(() => spawn.state).thenReturn(const CatalogReadyState(1));
    when(() => spawn.agents).thenReturn(const [
      RankedAgent(id: 'codex', label: 'Codex', availability: AgentAvailability.authorized, status: '', selectable: true),
    ]);
    when(() => spawn.harness).thenReturn('codex');
    when(() => spawn.claudeAccounts).thenReturn(const []);
    when(() => spawn.claudeAccountId).thenReturn('default');
    when(() => actions.state).thenReturn(const TicketActionsInitialState());
    when(() => actions.review(any())).thenAnswer((_) async {});
  });

  Widget host() => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SpawnCubit>.value(value: spawn),
              BlocProvider<TicketActionsCubit>.value(value: actions),
            ],
            child: const SingleChildScrollView(child: ReviewPlanSheetBody(ticket: _ticket, plan: _plan)),
          ),
        ),
      ),
    ),
  );

  testWidgets('defaults to the planning session and hides the spawn fields', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Review 02 UI'), findsOneWidget);
    expect(find.byType(TicketSpawnFields), findsNothing);
    await tester.tap(find.text('Review'));
    verify(() => actions.review(const ReviewPlanParams(projectId: 'repo', slug: 'search-page', planFile: 'plans/02-ui.md', reviewer: 'planner'))).called(1);
  });

  testWidgets('New session shows the spawn fields and sends reviewer new with the harness', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('New session'));
    await tester.pump();
    expect(find.byType(TicketSpawnFields), findsOneWidget);
    await tester.tap(find.text('Review'));
    verify(() => actions.review(const ReviewPlanParams(projectId: 'repo', slug: 'search-page', planFile: 'plans/02-ui.md', reviewer: 'new', harness: 'codex'))).called(1);
  });
}
```

`test/feature/tickets/presentation/ticket_actions/ui/merge_plan_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/merge_plan_sheet.dart';

class _MockTicketActionsCubit extends MockCubit<TicketActionsState> implements TicketActionsCubit {}

const _ticket = TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page');
const _plan = PlanModel(
  file: 'plans/02-ui.md',
  order: 2,
  title: 'UI',
  status: 'awaiting_merge',
  sessionId: 'repo-5',
  mergeSummary: 'Two files changed, tests green, no conflicts with main.',
);

void main() {
  late _MockTicketActionsCubit actions;

  setUp(() {
    actions = _MockTicketActionsCubit();
    when(() => actions.state).thenReturn(const TicketActionsInitialState());
    when(() => actions.merge(any(), any(), any())).thenAnswer((_) async {});
  });

  Widget host() => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(
          body: BlocProvider<TicketActionsCubit>.value(
            value: actions,
            child: const SingleChildScrollView(child: MergePlanSheetBody(ticket: _ticket, plan: _plan)),
          ),
        ),
      ),
    ),
  );

  testWidgets('shows the reviewer summary and merges on confirm', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Merge 02 UI'), findsOneWidget);
    expect(find.text('Tells the reviewer to merge the branch into the default branch now.'), findsOneWidget);
    expect(find.text('Two files changed, tests green, no conflicts with main.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Merge'));
    verify(() => actions.merge('repo', 'search-page', 'plans/02-ui.md')).called(1);
  });

  testWidgets('shows the daemon message when the merge is refused', (tester) async {
    when(() => actions.state).thenReturn(TicketActionFailureState(ServerFailure<Map<String, dynamic>>(
      error: 'x',
      message: 'The reviewer has not reported this plan as ready to merge.',
      statusCode: 409,
      apiStatus: 'TICKET_NOT_MERGE_READY',
      validationErrors: const {'requestId': 'req-3'},
    )));
    await tester.pumpWidget(host());
    expect(find.text('The reviewer has not reported this plan as ready to merge.'), findsOneWidget);
    expect(find.text('request req-3'), findsOneWidget);
  });
}
```

`test/feature/tickets/presentation/ticket_actions/ui/plan_actions_sheet_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/plan_actions_sheet.dart';

class _MockTicketActionsCubit extends MockCubit<TicketActionsState> implements TicketActionsCubit {}

const _ticket = TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page');

void main() {
  late _MockTicketActionsCubit actions;

  setUp(() {
    actions = _MockTicketActionsCubit();
    when(() => actions.state).thenReturn(const TicketActionsInitialState());
  });

  Future<void> pump(WidgetTester tester, PlanModel plan) => tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: BlocProvider<TicketActionsCubit>.value(
              value: actions,
              child: Builder(
                builder: (parent) => PlanActionsSheet(
                  ticket: _ticket,
                  plan: plan,
                  projectName: 'repo',
                  parentContext: parent,
                  onOpenSession: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a todo plan offers Assign and Mark done only', (tester) async {
    await pump(tester, const PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo'));
    expect(find.text('Assign'), findsOneWidget);
    expect(find.text('Mark done'), findsOneWidget);
    expect(find.text('Open session'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Merge'), findsNothing);
  });

  testWidgets('a working plan offers Open session, Review and Mark done', (tester) async {
    await pump(tester, const PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'working', sessionId: 'repo-4'));
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Mark done'), findsOneWidget);
    expect(find.text('Assign'), findsNothing);
  });

  testWidgets('a terminated plan offers Reassign; an awaiting_merge plan offers Merge; a merged plan offers nothing but Open session', (tester) async {
    await pump(tester, const PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'terminated', sessionId: 'repo-4'));
    expect(find.text('Reassign'), findsOneWidget);
    await pump(tester, const PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'awaiting_merge', sessionId: 'repo-4'));
    expect(find.text('Merge'), findsOneWidget);
    await pump(tester, const PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'merged', sessionId: 'repo-4'));
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Mark done'), findsNothing);
    expect(find.text('Merge'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_actions/ui`
Expected: compile errors for the three new files.

- [ ] **Step 4: Write the sheets**

`review_plan_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_pill.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/params/review_plan_params.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_spawn_fields.dart';

Future<void> showReviewPlanSheet(BuildContext context, {required TicketModel ticket, required PlanModel plan}) async {
  final actions = sl<TicketActionsCubit>();
  final spawn = sl<SpawnCubit>()..loadCatalog();
  await showExpressiveSheet<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider<TicketActionsCubit>.value(value: actions),
        BlocProvider<SpawnCubit>.value(value: spawn),
      ],
      child: AppSheetChrome(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ReviewPlanSheetBody(ticket: ticket, plan: plan),
        ),
      ),
    ),
  );
  await actions.close();
  await spawn.close();
}

class ReviewPlanSheetBody extends StatefulWidget {
  const ReviewPlanSheetBody({super.key, required this.ticket, required this.plan});

  final TicketModel ticket;
  final PlanModel plan;

  @override
  State<ReviewPlanSheetBody> createState() => _ReviewPlanSheetBodyState();
}

class _ReviewPlanSheetBodyState extends State<ReviewPlanSheetBody> {
  final _model = TextEditingController();
  final _extra = TextEditingController();
  String _reviewer = 'planner';

  @override
  void dispose() {
    _model.dispose();
    _extra.dispose();
    super.dispose();
  }

  void _start() {
    Haptics.tap();
    final choice = _reviewer == 'new' ? ticketSpawnChoice(context.read<SpawnCubit>(), _model, _extra) : null;
    context.read<TicketActionsCubit>().review(ReviewPlanParams(
      projectId: widget.ticket.projectId ?? '',
      slug: widget.ticket.slug ?? '',
      planFile: widget.plan.file ?? '',
      reviewer: _reviewer,
      harness: choice?.harness,
      model: choice?.model,
      claudeAccountId: choice?.claudeAccountId,
      extra: choice?.extra,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocConsumer<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketSessionStartedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.pushNamed(RoutesStrings.session, arguments: {'sessionId': state.session.id});
        }
        if (state is TicketActionFailureState) Haptics.error();
      },
      builder: (context, state) {
        final busy = state is TicketActionBusyState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('Review ${planLabel(widget.plan)}', style: AppTextStyle.style17SemiBold, maxLines: 2),
            const VerticalSpace(4),
            AppText(
              'The reviewer checks the branch against the spec and plan, fixes what is wrong, and reports when it is ready to merge.',
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 4,
            ),
            const VerticalSpace(14),
            AppText('Reviewer', style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6)),
            const VerticalSpace(6),
            Row(
              children: [
                AppPill(label: 'Planning session', active: _reviewer == 'planner', onTap: busy ? null : () => setState(() => _reviewer = 'planner')),
                const HorizontalSpace(8),
                AppPill(label: 'New session', active: _reviewer == 'new', onTap: busy ? null : () => setState(() => _reviewer = 'new')),
              ],
            ),
            if (_reviewer == 'new') ...[
              const VerticalSpace(14),
              TicketSpawnFields(spawn: context.read<SpawnCubit>(), model: _model, extra: _extra, enabled: !busy),
            ],
            if (state is TicketActionFailureState) ...[const VerticalSpace(10), TicketFailureText(failure: state.failure)],
            const VerticalSpace(16),
            PrimaryButton.expand(
              text: busy ? 'Starting…' : 'Review',
              isLoading: busy,
              fixedSize: const Size.fromHeight(46),
              onPressed: busy ? null : _start,
            ),
            const VerticalSpace(4),
            Center(
              child: TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

`merge_plan_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_toast.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';

Future<void> showMergePlanSheet(BuildContext context, {required TicketModel ticket, required PlanModel plan}) async {
  final actions = sl<TicketActionsCubit>();
  await showExpressiveSheet<void>(
    context: context,
    builder: (_) => BlocProvider<TicketActionsCubit>.value(
      value: actions,
      child: AppSheetChrome(child: MergePlanSheetBody(ticket: ticket, plan: plan)),
    ),
  );
  await actions.close();
}

class MergePlanSheetBody extends StatelessWidget {
  const MergePlanSheetBody({super.key, required this.ticket, required this.plan});

  final TicketModel ticket;
  final PlanModel plan;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final summary = plan.mergeSummary?.trim() ?? '';
    return BlocConsumer<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketUpdatedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          AppToast.show(context, message: 'Merging…', icon: Icons.call_merge);
          Navigator.of(context).pop();
        }
        if (state is TicketActionFailureState) Haptics.error();
      },
      builder: (context, state) {
        final busy = state is TicketActionBusyState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('Merge ${planLabel(plan)}', style: AppTextStyle.style17SemiBold, maxLines: 2),
            const VerticalSpace(4),
            AppText(
              'Tells the reviewer to merge the branch into the default branch now.',
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 3,
            ),
            const VerticalSpace(14),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: skin.bgColumn,
                border: Border.all(color: skin.borderSubtle),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              ),
              child: SingleChildScrollView(
                child: AppText(
                  summary.isEmpty ? 'The reviewer left no summary.' : summary,
                  style: AppTextStyle.style13Regular.copyWith(color: summary.isEmpty ? skin.textTertiary : skin.textPrimary, height: 1.45),
                  maxLines: 40,
                ),
              ),
            ),
            if (state is TicketActionFailureState) ...[const VerticalSpace(10), TicketFailureText(failure: state.failure)],
            const VerticalSpace(16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: AppText('Cancel', style: AppTextStyle.style15Regular.copyWith(color: skin.textSecondary)),
                  ),
                ),
                const HorizontalSpace(10),
                Expanded(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            Haptics.tap();
                            context.read<TicketActionsCubit>().merge(ticket.projectId ?? '', ticket.slug ?? '', plan.file ?? '');
                          },
                    child: AppText(busy ? 'Merging…' : 'Merge', style: AppTextStyle.style15SemiBold.copyWith(color: skin.green)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

`plan_actions_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_toast.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/assign_rules.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/logic/ticket_actions_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/assign_plan_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/merge_plan_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/review_plan_sheet.dart';

Future<void> showPlanActionsSheet(
  BuildContext context, {
  required TicketModel ticket,
  required PlanModel plan,
  required String projectName,
  required void Function(String sessionId) onOpenSession,
}) {
  final actions = sl<TicketActionsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => BlocProvider<TicketActionsCubit>.value(
      value: actions,
      child: PlanActionsSheet(
        ticket: ticket,
        plan: plan,
        projectName: projectName,
        parentContext: context,
        onOpenSession: onOpenSession,
      ),
    ),
  ).whenComplete(actions.close);
}

class PlanActionsSheet extends StatelessWidget {
  const PlanActionsSheet({
    super.key,
    required this.ticket,
    required this.plan,
    required this.projectName,
    required this.parentContext,
    required this.onOpenSession,
  });

  final TicketModel ticket;
  final PlanModel plan;
  final String projectName;
  final BuildContext parentContext;
  final void Function(String sessionId) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TicketActionsCubit>();
    final sessionId = plan.sessionId;

    void popThen(void Function(BuildContext) next) {
      Haptics.tap();
      Navigator.of(context).pop();
      if (parentContext.mounted) next(parentContext);
    }

    return BlocListener<TicketActionsCubit, TicketActionsState>(
      listener: (context, state) {
        if (state is TicketUpdatedState) {
          Haptics.success();
          sl<SessionsCubit>().refresh();
          Navigator.of(context).pop();
        }
        if (state is TicketActionFailureState) {
          Haptics.error();
          AppToast.show(context, message: state.failure.message, destructive: true);
          Navigator.of(context).pop();
        }
      },
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: AppText(planLabel(plan), style: AppTextStyle.style14SemiBold),
              subtitle: AppText(ticket.title ?? ticket.slug ?? '', style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
            ),
            if (sessionId != null && sessionId.isNotEmpty)
              ListTile(
                leading: Icon(Icons.terminal, color: skin.textSecondary),
                title: const AppText('Open session'),
                onTap: () {
                  Haptics.tap();
                  Navigator.of(context).pop();
                  onOpenSession(sessionId);
                },
              ),
            if (canAssignPlan(plan))
              ListTile(
                leading: Icon(Icons.play_arrow_outlined, color: skin.accent),
                title: AppText(assignActionLabel(plan)),
                onTap: () => popThen((parent) => showAssignPlanSheet(parent, ticket: ticket, plan: plan, projectName: projectName)),
              ),
            if (canReviewPlan(plan))
              ListTile(
                leading: Icon(Icons.rate_review_outlined, color: skin.textSecondary),
                title: const AppText('Review'),
                onTap: () => popThen((parent) => showReviewPlanSheet(parent, ticket: ticket, plan: plan)),
              ),
            if (canMergePlan(plan))
              ListTile(
                leading: Icon(Icons.call_merge, color: skin.green),
                title: AppText('Merge', style: AppTextStyle.style14Regular.copyWith(color: skin.green)),
                onTap: () => popThen((parent) => showMergePlanSheet(parent, ticket: ticket, plan: plan)),
              ),
            if (canMarkPlanDone(plan))
              ListTile(
                leading: Icon(Icons.check_circle_outline, color: skin.textSecondary),
                title: const AppText('Mark done'),
                onTap: () async {
                  Haptics.tap();
                  final confirmed = await AppDialog.confirm(
                    context,
                    title: 'Mark ${planLabel(plan)} done?',
                    message: 'Closes this plan without a merge. The ticket counts it as finished.',
                    confirmLabel: 'Mark done',
                  );
                  if (!context.mounted || !confirmed) return;
                  cubit.markDone(ticket.projectId ?? '', ticket.slug ?? '', plan.file ?? '');
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

`popThen` pops the bottom sheet and opens the follow-up sheet on the caller's context (`parentContext`), which outlives the sheet route: `showModalBottomSheet` pushes a route on the nearest `Navigator`, so after `pop()` the sheet's own `context` is unmounted and cannot host `showExpressiveSheet` (it asserts `debugCheckHasMediaQuery`/`MaterialLocalizations`, `show_expressive_sheet.dart:22-23`).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets`
Expected: all pass. `AppPill` renders its label through `AppText`, so `find.text('New session')` resolves; if `AppPill` requires `count`, pass `count: null` explicitly.

- [ ] **Step 6: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): review, merge confirmation with the reviewer summary, mark done, plan actions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Ticket card, Planned section, Planned filter chip, archive entries

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_card/ui/widgets/plan_row.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_card/ui/ticket_card.dart`
- Modify: `packages/mobile/lib/feature/sessions/logic/sessions_filter.dart:7-26`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart:6-44`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart:62-216`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_card/ticket_card_test.dart`
- Test: `packages/mobile/test/feature/sessions/logic/sessions_filter_test.dart` (create if absent, else append)
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart` (append)

**Interfaces:**
- Consumes: `SessionsCubit.visibleTickets/sessionsById/projects`, `ticketStatusVisual`, `planStatusVisual`, `statusChipTint`, `isTicketInArchive`, `openTicketCount`, `planNumber`, `planTitle`, `ticketFileGroups`, `planningSessionLive` (`logic/ticket_presentation.dart`), `sl` + `TicketActionsCubit` (for `Reopen`), `showCreateTicketSheet`, `showPlanTicketSheet`, `showTicketActionsSheet`, `showPlanActionsSheet`, `RoutesStrings.ticket`, `AppContainer`, `StatusDot`, `FadeUpEntrance`, `AppPill`.
- Produces: `SessionsFilter.planned` (second chip, label `Planned`), `bool sessionsFilterShowsPlanned(SessionsFilter)`, `SessionSectionHeader.trailing`, `TicketCard({ticket, projectName, sessionsById, onOpen, onLongPress, onPlan, onOpenSession, onPlanTap, onPlanLongPress, onReopen, muted})`, `PlanRow({plan, sessionsById, onTap, onLongPress})`.
- Design: card anatomy from `docs/design/sessions_board/sessions_board.md:77-97` (`bgSurface`, `radiusCard`, `borderDefault`, padding 13, `style15SemiBold` title, status chip pill with `StatusDot` 7 + `style11p5SemiBold`), section header idiom `:74-76`, archive muting `:99-102` (opacity 0.72), chips `:63-70`.

- [ ] **Step 1: Write the failing tests**

`test/feature/sessions/logic/sessions_filter_test.dart` (create if it does not exist; otherwise append the tests to its `main()`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/sessions_filter.dart';

void main() {
  test('Planned sits second in the chip order and never admits a session zone', () {
    expect(SessionsFilter.values.map((f) => f.label), ['All', 'Planned', 'Needs you', 'Working', 'Mergeable', 'Archive']);
    for (final zone in BoardZone.values) {
      expect(sessionsFilterAllowsZone(SessionsFilter.planned, zone), isFalse);
    }
    expect(sessionsFilterAllowsZone(SessionsFilter.all, BoardZone.working), isTrue);
  });

  test('the Planned section shows under All and Planned only', () {
    expect(sessionsFilterShowsPlanned(SessionsFilter.all), isTrue);
    expect(sessionsFilterShowsPlanned(SessionsFilter.planned), isTrue);
    expect(sessionsFilterShowsPlanned(SessionsFilter.working), isFalse);
    expect(sessionsFilterShowsPlanned(SessionsFilter.archive), isFalse);
  });
}
```

`test/feature/tickets/presentation/ticket_card/ticket_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_card/ui/ticket_card.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_card/ui/widgets/plan_row.dart';

const _ticket = TicketModel(
  projectId: 'repo',
  slug: 'search-page',
  title: 'Search page',
  status: 'in_progress',
  planningSessionId: 'repo-3',
  plans: [
    PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'merged', sessionId: 'repo-4'),
    PlanModel(file: 'plans/02-ui.md', order: 2, title: 'UI', status: 'working', sessionId: 'repo-5'),
    PlanModel(file: 'plans/03-docs.md', order: 3, title: 'Docs', status: 'todo'),
  ],
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    TicketModel ticket = _ticket,
    Map<String, SessionModel> sessionsById = const {},
    bool muted = false,
    void Function(PlanModel plan)? onPlanTap,
    VoidCallback? onPlan,
    VoidCallback? onOpen,
    VoidCallback? onReopen,
  }) => tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TicketCard(
                ticket: ticket,
                projectName: 'repo',
                sessionsById: sessionsById,
                muted: muted,
                onOpen: onOpen ?? () {},
                onLongPress: () {},
                onPlan: onPlan ?? () {},
                onOpenSession: (_) {},
                onPlanTap: onPlanTap ?? (_) {},
                onPlanLongPress: (_) {},
                onReopen: onReopen,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('renders title, project, merged count, one row per plan with number and status', (tester) async {
    await pumpCard(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('repo'), findsOneWidget);
    expect(find.text('1/3 merged'), findsOneWidget);
    expect(find.byType(PlanRow), findsNWidgets(3));
    expect(find.text('01'), findsOneWidget);
    expect(find.text('Index'), findsOneWidget);
    expect(find.text('Merged'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('Plan with agent'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows Open planning session while the planner runs, and its activity', (tester) async {
    await pumpCard(
      tester,
      ticket: const TicketModel(projectId: 'repo', slug: 's', title: 'S', status: 'planning', planningSessionId: 'repo-3'),
      sessionsById: const {'repo-3': SessionModel(id: 'repo-3', status: 'working', activity: 'Writing the spec')},
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Writing the spec'), findsOneWidget);
    expect(find.text('Open planning session'), findsOneWidget);
    expect(find.text('Plan with agent'), findsNothing);
  });

  testWidgets('tapping a plan row reports the plan; footer buttons report their actions', (tester) async {
    PlanModel? tapped;
    var planned = false;
    var opened = false;
    await pumpCard(tester, onPlanTap: (plan) => tapped = plan, onPlan: () => planned = true, onOpen: () => opened = true);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('UI'));
    expect(tapped?.file, 'plans/02-ui.md');
    await tester.tap(find.text('Plan with agent'));
    expect(planned, isTrue);
    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  testWidgets('an archive entry is muted and offers Reopen', (tester) async {
    var reopened = false;
    await pumpCard(
      tester,
      ticket: const TicketModel(projectId: 'repo', slug: 's', title: 'Old', status: 'archived'),
      muted: true,
      onReopen: () => reopened = true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Plan with agent'), findsNothing);
    await tester.tap(find.text('Reopen'));
    expect(reopened, isTrue);
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.72);
  });
}
```

Append to `test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart` inside `main()` (reuse its `pumpBody`, `settle`; add imports for `TicketModel`, `PlanModel`, `TicketCard`):

```dart
  testWidgets('renders open tickets in a Planned section first, with the chip count', (tester) async {
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [SessionModel(id: 'a', projectId: 'repo', displayName: 'Working one', status: 'working')],
        projects: [ProjectModel(id: 'repo', name: 'repo', kind: 'single_repo')],
        tickets: [
          TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page', status: 'ready', plans: [PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo')]),
          TicketModel(projectId: 'repo', slug: 'old', title: 'Old ticket', status: 'archived'),
        ],
      ),
    );

    expect(find.text('PLANNED'), findsOneWidget);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('Old ticket'), findsNothing);
    final plannedHeader = tester.getTopLeft(find.text('PLANNED'));
    final workingHeader = tester.getTopLeft(find.text('WORKING'));
    expect(plannedHeader.dy, lessThan(workingHeader.dy));
    expect(find.widgetWithText(SessionSectionHeader, 'ARCHIVE'), findsOneWidget);
  });

  testWidgets('the Planned chip filters to tickets only; Archive lists archived tickets with Reopen', (tester) async {
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [SessionModel(id: 'a', projectId: 'repo', displayName: 'Working one', status: 'working')],
        projects: [ProjectModel(id: 'repo', name: 'repo', kind: 'single_repo')],
        tickets: [
          TicketModel(projectId: 'repo', slug: 'search-page', title: 'Search page', status: 'draft'),
          TicketModel(projectId: 'repo', slug: 'old', title: 'Old ticket', status: 'archived'),
        ],
      ),
    );

    await tester.tap(find.text('Planned'));
    await settle(tester);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('Working one'), findsNothing);

    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.text('Old ticket'), findsOneWidget);
    expect(find.text('Reopen'), findsOneWidget);
    expect(find.byType(TicketCard), findsOneWidget);
  });

  testWidgets('without a single-repository project the Planned filter shows the hint and no + button', (tester) async {
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [SessionModel(id: 'a', projectId: 'scratch', displayName: 'Scratch one', status: 'working')],
        projects: [ProjectModel(id: 'scratch', name: 'scratch', kind: 'scratch')],
      ),
    );
    await tester.tap(find.text('Planned'));
    await settle(tester);
    expect(find.text('Tickets need a single-repository project.'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/sessions test/feature/tickets/presentation/ticket_card`
Expected: compile errors (`SessionsFilter.planned`, `TicketCard`, `BoardSnapshot.tickets` already exists from Task 5).

- [ ] **Step 3: Implement**

`sessions_filter.dart`: replace the enum and the two functions with

```dart
enum SessionsFilter { all, planned, needsYou, working, mergeable, archive }

extension SessionsFilterLabel on SessionsFilter {
  String get label => switch (this) {
    SessionsFilter.all => 'All',
    SessionsFilter.planned => 'Planned',
    SessionsFilter.needsYou => 'Needs you',
    SessionsFilter.working => 'Working',
    SessionsFilter.mergeable => 'Mergeable',
    SessionsFilter.archive => 'Archive',
  };
}

bool sessionsFilterAllowsZone(SessionsFilter filter, BoardZone zone) => switch (filter) {
  SessionsFilter.all => true,
  SessionsFilter.planned => false,
  SessionsFilter.needsYou => zone == BoardZone.action,
  SessionsFilter.working => zone == BoardZone.working,
  SessionsFilter.mergeable => zone == BoardZone.merge,
  SessionsFilter.archive => false,
};

bool sessionsFilterShowsPlanned(SessionsFilter filter) => filter == SessionsFilter.all || filter == SessionsFilter.planned;
```

Keep the file's existing doc comment and extend its chip list to mention `Planned`.

`session_section_header.dart`: add `this.trailing,` to the constructor, `final Widget? trailing;`, and change the `row` to

```dart
    final row = Row(
      children: [
        if (expanded != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(expanded! ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: color),
          ),
        AppText(label.toUpperCase(), style: AppTextStyle.style11SemiBold.copyWith(color: color)),
        const SizedBox(width: 6),
        AppText('$count', style: AppTextStyle.mono11Regular.copyWith(color: color)),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
```

`plan_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/main_widgets/status_dot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';

class PlanRow extends StatelessWidget {
  const PlanRow({
    super.key,
    required this.plan,
    required this.sessionsById,
    required this.onTap,
    required this.onLongPress,
  });

  final PlanModel plan;
  final Map<String, SessionModel> sessionsById;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = planStatusVisual(skin, plan.status);
    final number = planNumber(plan.file ?? '');
    final session = plan.sessionId == null ? null : sessionsById[plan.sessionId!];
    final activity = session?.activity?.trim() ?? '';
    final warning = plan.warning?.trim() ?? '';
    return AppInkWell(
      onTap: onTap,
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 22,
                  child: AppText(number.isEmpty ? '—' : number, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
                ),
                const HorizontalSpace(6),
                Expanded(child: AppText(planTitle(plan), style: AppTextStyle.style13Regular, maxLines: 1)),
                const HorizontalSpace(8),
                Container(
                  padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: statusChipTint(skin, visual.color),
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(color: visual.color, size: 6, breathing: visual.breathing),
                      const HorizontalSpace(5),
                      AppText(visual.label, style: AppTextStyle.style11SemiBold.copyWith(color: visual.color)),
                    ],
                  ),
                ),
              ],
            ),
            if (activity.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: AppText(activity, style: AppTextStyle.mono10Regular.copyWith(color: skin.textTertiary), maxLines: 1),
              ),
            if (warning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: AppText(warning, style: AppTextStyle.style10Regular.copyWith(color: skin.amber), maxLines: 2),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
```

`AppInkWell` has no `onLongPress` (`core/widgets/main_widgets/app_ink_well.dart:6-10`), hence the inner `GestureDetector`, the same shape as `session_card.dart:54-62`. Run `dart format` on the file after writing it.

`ticket_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/main_widgets/status_dot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_card/ui/widgets/plan_row.dart';

class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.projectName,
    required this.sessionsById,
    required this.onOpen,
    required this.onLongPress,
    required this.onPlan,
    required this.onOpenSession,
    required this.onPlanTap,
    required this.onPlanLongPress,
    this.onReopen,
    this.muted = false,
  });

  final TicketModel ticket;
  final String projectName;
  final Map<String, SessionModel> sessionsById;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onPlan;
  final void Function(String sessionId) onOpenSession;
  final void Function(PlanModel plan) onPlanTap;
  final void Function(PlanModel plan) onPlanLongPress;
  final VoidCallback? onReopen;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = ticketStatusVisual(skin, ticket);
    final planningSession = ticket.planningSessionId == null ? null : sessionsById[ticket.planningSessionId!];
    final planningLive = planningSessionLive(planningSession);
    final planningActivity = planningLive ? (planningSession?.activity?.trim() ?? '') : '';
    final plans = ticketFileGroups(ticket).plans;
    final warning = ticket.warning?.trim() ?? '';
    final footerStyle = AppTextStyle.style12SemiBold;

    final card = AppContainer(
      onTap: onOpen,
      pressScale: true,
      padding: const EdgeInsets.all(13),
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      border: Border.all(color: skin.borderDefault),
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.confirmation_number_outlined, size: 20, color: skin.textTertiary),
                const HorizontalSpace(9),
                Flexible(child: AppText(ticket.title ?? ticket.slug ?? '', style: AppTextStyle.style15SemiBold, maxLines: 2)),
                const HorizontalSpace(9),
                Expanded(child: AppText(projectName, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary))),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                  decoration: BoxDecoration(
                    color: statusChipTint(skin, visual.color),
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(color: visual.color, size: 7, breathing: visual.breathing),
                      const HorizontalSpace(6),
                      AppText(visual.label, style: AppTextStyle.style11p5SemiBold.copyWith(color: visual.color)),
                    ],
                  ),
                ),
              ],
            ),
            if (planningActivity.isNotEmpty) ...[
              const VerticalSpace(5),
              Padding(
                padding: const EdgeInsets.only(left: 29),
                child: AppText(planningActivity, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary), maxLines: 1),
              ),
            ],
            if (warning.isNotEmpty) ...[
              const VerticalSpace(5),
              Padding(
                padding: const EdgeInsets.only(left: 29),
                child: AppText(warning, style: AppTextStyle.style11Regular.copyWith(color: skin.amber), maxLines: 3),
              ),
            ],
            if (plans.isNotEmpty) ...[
              const VerticalSpace(9),
              Container(height: 1, color: skin.borderSubtle),
              const VerticalSpace(4),
              for (final plan in plans)
                PlanRow(
                  plan: plan,
                  sessionsById: sessionsById,
                  onTap: () => onPlanTap(plan),
                  onLongPress: () => onPlanLongPress(plan),
                ),
            ],
            const VerticalSpace(6),
            Row(
              children: [
                if (muted && onReopen != null)
                  TextButton(
                    onPressed: onReopen,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                    child: AppText('Reopen', style: footerStyle.copyWith(color: skin.accent)),
                  )
                else if (!muted)
                  planningLive
                      ? TextButton(
                          onPressed: () => onOpenSession(planningSession!.id!),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusDot(color: skin.orange, size: 6, breathing: true),
                              const HorizontalSpace(6),
                              AppText('Open planning session', style: footerStyle.copyWith(color: skin.textPrimary)),
                            ],
                          ),
                        )
                      : TextButton(
                          onPressed: onPlan,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                          child: AppText('Plan with agent', style: footerStyle.copyWith(color: skin.textPrimary)),
                        ),
                const Spacer(),
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                  child: AppText('Open', style: footerStyle.copyWith(color: skin.textSecondary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return muted ? Opacity(opacity: 0.72, child: card) : card;
  }
}
```

`sessions_body.dart`: add imports for `TicketModel`, `TicketCard`, `logic/ticket_status.dart`, `showCreateTicketSheet`, `showPlanTicketSheet`, `showTicketActionsSheet`, `showPlanActionsSheet`, `TicketActionsCubit` and `core/utils/service_locator.dart` (`RoutesStrings`, `Haptics`, `AppText`, `AppTextStyle` are already imported). Inside `builder`, after `final grouped = groupSessions(skin, cubit.visibleSessions);` add:

```dart
        final openTickets = cubit.visibleTickets.where((ticket) => !isTicketInArchive(ticket)).toList();
        final archivedTickets = cubit.visibleTickets.where(isTicketInArchive).toList();
        final hasRepoProject = cubit.projects.any((project) => project.kind == 'single_repo');
        final showPlanned = sessionsFilterShowsPlanned(_filter) && (openTickets.isNotEmpty || _filter == SessionsFilter.planned);
        final sessionsById = cubit.sessionsById;
        String projectNameOf(String? id) => cubit.projects.where((project) => project.id == id).firstOrNull?.name ?? id ?? '';

        void openTicket(TicketModel ticket, {String? file}) => Navigator.of(context).pushNamed(
          RoutesStrings.ticket,
          arguments: {'projectId': ticket.projectId, 'slug': ticket.slug, if (file != null) 'file': file},
        );
        void openSession(String sessionId) => Navigator.of(context).pushNamed(RoutesStrings.session, arguments: {'sessionId': sessionId});

        Future<void> reopen(TicketModel ticket) async {
          Haptics.tap();
          final actions = sl<TicketActionsCubit>();
          await actions.unarchive(ticket.projectId ?? '', ticket.slug ?? '');
          await cubit.refresh();
          await actions.close();
        }
```

Change the `counts` map: add `SessionsFilter.planned: openTicketCount(cubit.visibleTickets),` and make the archive count `grouped.archived.length + archivedTickets.length`. Change `nothingHere` to `visibleSections.isEmpty && !showPlanned && (!showArchive || (grouped.archived.isEmpty && archivedTickets.isEmpty))`, and the final empty-state condition to `grouped.sections.isEmpty && grouped.archived.isEmpty && cubit.visibleTickets.isEmpty`.

Add a card builder next to `buildCard`:

```dart
        Widget buildTicketCard(TicketModel ticket, {bool muted = false}) {
          final entranceIndex = cardIndex++;
          return FadeUpEntrance(
            index: entranceIndex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TicketCard(
                ticket: ticket,
                projectName: projectNameOf(ticket.projectId),
                sessionsById: sessionsById,
                muted: muted,
                onOpen: () => openTicket(ticket),
                onLongPress: () => showTicketActionsSheet(
                  context,
                  ticket,
                  planningSession: ticket.planningSessionId == null ? null : sessionsById[ticket.planningSessionId!],
                  onOpen: () => openTicket(ticket),
                  onPlan: () => showPlanTicketSheet(context, ticket),
                  onOpenSession: openSession,
                ),
                onPlan: () => showPlanTicketSheet(context, ticket),
                onOpenSession: openSession,
                onPlanTap: (plan) {
                  final sessionId = plan.sessionId;
                  if (sessionId != null && sessionId.isNotEmpty) {
                    openSession(sessionId);
                  } else {
                    openTicket(ticket, file: plan.file);
                  }
                },
                onPlanLongPress: (plan) => showPlanActionsSheet(
                  context,
                  ticket: ticket,
                  plan: plan,
                  projectName: projectNameOf(ticket.projectId),
                  onOpenSession: openSession,
                ),
                onReopen: muted ? () => reopen(ticket) : null,
              ),
            ),
          );
        }
```

(`reopen` uses a throwaway `TicketActionsCubit` and closes it after the board refresh; a failed unarchive surfaces on the next board load, which is why the toast lives in the actions sheet path rather than here.)

In the `ListView` children, insert right after `SessionFilterChipsRow(...)`:

```dart
              if (showPlanned) ...[
                SessionSectionHeader(
                  label: 'Planned',
                  color: skin.blue,
                  count: openTickets.length,
                  trailing: hasRepoProject
                      ? Semantics(
                          label: 'New ticket',
                          button: true,
                          child: IconButton(
                            icon: Icon(Icons.add, size: 18, color: skin.blue),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                            onPressed: () {
                              Haptics.tap();
                              showCreateTicketSheet(context);
                            },
                          ),
                        )
                      : null,
                ),
                if (openTickets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: AppText(
                      hasRepoProject ? 'No tickets yet. Create a ticket, then plan it with an agent.' : 'Tickets need a single-repository project.',
                      style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      maxLines: 2,
                    ),
                  ),
                for (final ticket in openTickets) buildTicketCard(ticket),
              ],
```

and extend the archive block: the header count becomes `grouped.archived.length + archivedTickets.length`, the `if (showArchive && …)` condition becomes `showArchive && (grouped.archived.isNotEmpty || archivedTickets.isNotEmpty)`, and after the archived session cards add `for (final ticket in archivedTickets) buildTicketCard(ticket, muted: true),` under the same `archiveForcedOpen || _archiveExpanded` guard.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/sessions test/feature/tickets`
Expected: all pass. The existing `sessions_body_test.dart` chip-count assertions may enumerate five chips; update them to six (`Planned` with count 0 between `All` and `Needs you`) where they list labels.

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): Planned section, ticket cards and filter chip on the Agents board

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Ticket detail screen with read-only preview

**Files:**
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_state.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/ui/ticket_detail_screen.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_detail_header.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_file_list.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/ui/widgets/frontmatter_block.dart`
- Create: `packages/mobile/lib/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_markdown_preview.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart:158-168` (new case before `default`)
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`registerFactoryParam<TicketDetailCubit, TicketDetailArgs, void>`)
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit_test.dart`
- Test: `packages/mobile/test/feature/tickets/presentation/ticket_detail_screen/ui/ticket_detail_screen_test.dart`
- Test: `packages/mobile/test/core/app_routes/app_router_test.dart` (append one case if the file enumerates routes)

**Interfaces:**
- Consumes: `TicketsRepository.getTicket/readFile`, `MuxClient.boardChanges`, `splitFrontmatter`, `ticketFileGroups`, `planLabel`, `planStatusVisual`, `ticketStatusVisual`, `relativeTime` (`core/utils/relative_time.dart:1`), `BlockMarkdown`'s style sheet (`block_markdown.dart:34-102`, copied — `BlockMarkdown` itself is a blocks widget and stays untouched), `GlobalAppbar.sub(titleText:, actions:)`, `AppScaffold`, `SettingsGroup`/`SettingsRow`, `showTicketActionsSheet`, `showPlanTicketSheet`, `showPlanActionsSheet`, `SessionsCubit` (for `sessionsById` and project names).
- Produces: `class TicketDetailArgs { String projectId; String slug; String? file; }`, `TicketDetailCubit(TicketsRepository, MuxClient, TicketDetailArgs)` with `ticket`, `selectedFile`, `file`, `fileFailure`, `load()`, `refresh()`, `selectFile(String path)`; states `TicketDetailInitialState`, `TicketDetailLoadingState`, `TicketDetailLoadedState(revision)`, `TicketDetailFailureState(failure)`; `TicketDetailScreen()`; `TicketDetailHeader(ticket:, planningSession:, onOpenSession:)`; `TicketFileList(ticket:, selected:, onSelect:, onPlanMore:)`; `FrontmatterBlock(fields:)`; `TicketMarkdownPreview(content:)`; route `RoutesStrings.ticket` with `arguments: {'projectId', 'slug', 'file'?}`.
- Spec §3.3 preview half: file list (`ticket.md`, `spec.md`, plans with status and kickoff files), preview of the selected file with frontmatter shown as a key/value block; §4: unreadable ticket shows `warning` above the raw file.

- [ ] **Step 1: Write the failing cubit test**

`test/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit.dart';

class _MockTicketsRepository extends Mock implements TicketsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

const _ticket = TicketModel(
  projectId: 'repo',
  slug: 'search-page',
  title: 'Search page',
  status: 'ready',
  files: ['ticket.md', 'spec.md', 'plans/01-index.md'],
  plans: [PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo')],
);

void main() {
  late _MockTicketsRepository repository;
  late _MockMuxClient mux;
  late StreamController<void> boardChanges;

  setUp(() {
    repository = _MockTicketsRepository();
    mux = _MockMuxClient();
    boardChanges = StreamController<void>.broadcast();
    when(() => mux.boardChanges).thenAnswer((_) => boardChanges.stream);
    when(() => repository.getTicket('repo', 'search-page')).thenAnswer((_) async => Result.success(const GlobalResponse(data: _ticket)));
    when(() => repository.readFile('repo', 'search-page', any())).thenAnswer((invocation) async {
      final path = invocation.positionalArguments[2] as String;
      return Result.success(GlobalResponse(data: TicketFileModel(path: path, content: '# $path\n', modifiedAt: '2026-09-18T10:00:00Z')));
    });
  });

  tearDown(() => boardChanges.close());

  TicketDetailCubit build({String? file}) =>
      TicketDetailCubit(repository, mux, TicketDetailArgs(projectId: 'repo', slug: 'search-page', file: file));

  blocTest<TicketDetailCubit, TicketDetailState>(
    'load fetches the ticket and previews spec.md by default',
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [const TicketDetailLoadingState(), const TicketDetailLoadedState(1), const TicketDetailLoadedState(2)],
    verify: (cubit) {
      expect(cubit.ticket?.slug, 'search-page');
      expect(cubit.selectedFile, 'spec.md');
      expect(cubit.file?.content, '# spec.md\n');
    },
  );

  blocTest<TicketDetailCubit, TicketDetailState>(
    'an initial file wins over the default and selectFile re-reads',
    build: () => build(file: 'plans/01-index.md'),
    act: (cubit) async {
      await cubit.load();
      await cubit.selectFile('ticket.md');
    },
    verify: (cubit) {
      expect(cubit.selectedFile, 'ticket.md');
      expect(cubit.file?.path, 'ticket.md');
      verifyInOrder([
        () => repository.readFile('repo', 'search-page', 'plans/01-index.md'),
        () => repository.readFile('repo', 'search-page', 'ticket.md'),
      ]);
    },
  );

  blocTest<TicketDetailCubit, TicketDetailState>(
    'a failed ticket read is a failure state; a failed file read keeps the ticket and records fileFailure',
    build: () {
      when(() => repository.getTicket('repo', 'search-page')).thenAnswer(
        (_) async => Result.failure(ServerFailure<Map<String, dynamic>>(error: 'x', message: 'The ticket no longer exists.', statusCode: 404)),
      );
      return build();
    },
    act: (cubit) => cubit.load(),
    verify: (cubit) => expect(cubit.state, isA<TicketDetailFailureState>()),
  );

  blocTest<TicketDetailCubit, TicketDetailState>(
    'a file read failure keeps the ticket and exposes fileFailure',
    build: () {
      when(() => repository.readFile('repo', 'search-page', any())).thenAnswer(
        (_) async => Result.failure(ServerFailure<Map<String, dynamic>>(error: 'x', message: 'That file is not in the ticket folder.', statusCode: 404)),
      );
      return build();
    },
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.ticket, isNotNull);
      expect(cubit.file, isNull);
      expect(cubit.fileFailure?.message, 'That file is not in the ticket folder.');
      expect(cubit.state, isA<TicketDetailLoadedState>());
    },
  );

  blocTest<TicketDetailCubit, TicketDetailState>(
    'a board change reloads the ticket and the selected file after a short debounce',
    build: build,
    act: (cubit) async {
      await cubit.load();
      boardChanges.add(null);
      boardChanges.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    },
    verify: (_) {
      verify(() => repository.getTicket('repo', 'search-page')).called(2);
      verify(() => repository.readFile('repo', 'search-page', 'spec.md')).called(2);
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit_test.dart`
Expected: compile error.

- [ ] **Step 3: Write the cubit**

`ticket_detail_state.dart`:

```dart
part of 'ticket_detail_cubit.dart';

sealed class TicketDetailState extends Equatable {
  const TicketDetailState();

  @override
  List<Object?> get props => [];
}

final class TicketDetailInitialState extends TicketDetailState {
  const TicketDetailInitialState();
}

final class TicketDetailLoadingState extends TicketDetailState {
  const TicketDetailLoadingState();
}

final class TicketDetailLoadedState extends TicketDetailState {
  const TicketDetailLoadedState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class TicketDetailFailureState extends TicketDetailState {
  const TicketDetailFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
```

`ticket_detail_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/data/repository/tickets_repository.dart';

part 'ticket_detail_state.dart';

class TicketDetailArgs extends Equatable {
  const TicketDetailArgs({required this.projectId, required this.slug, this.file});

  final String projectId;
  final String slug;
  final String? file;

  @override
  List<Object?> get props => [projectId, slug, file];
}

class TicketDetailCubit extends Cubit<TicketDetailState> {
  TicketDetailCubit(this._repository, this._muxClient, this.args) : super(const TicketDetailInitialState()) {
    _muxSub = _muxClient.boardChanges.listen((_) {
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 300), () => unawaited(refresh()));
    });
  }

  final TicketsRepository _repository;
  final MuxClient _muxClient;
  final TicketDetailArgs args;

  TicketModel? ticket;
  String? selectedFile;
  TicketFileModel? file;
  Failure? fileFailure;

  StreamSubscription<void>? _muxSub;
  Timer? _reloadTimer;
  int _revision = 0;

  void _emitLoaded() => emit(TicketDetailLoadedState(++_revision));

  Future<void> load() async {
    if (ticket == null) emit(const TicketDetailLoadingState());
    await refresh();
  }

  Future<void> refresh() async {
    final result = await _repository.getTicket(args.projectId, args.slug);
    if (isClosed) return;
    var loaded = false;
    result.when(
      onSuccess: (response) {
        ticket = response.data ?? ticket;
        loaded = ticket != null;
      },
      onFailure: (failure) {
        if (ticket == null) emit(TicketDetailFailureState(failure));
      },
    );
    if (!loaded) return;
    selectedFile ??= args.file ?? _defaultFile(ticket!);
    _emitLoaded();
    if (selectedFile != null) await _readSelected();
  }

  Future<void> selectFile(String path) async {
    selectedFile = path;
    file = null;
    fileFailure = null;
    _emitLoaded();
    await _readSelected();
  }

  Future<void> _readSelected() async {
    final path = selectedFile;
    if (path == null) return;
    final result = await _repository.readFile(args.projectId, args.slug, path);
    if (isClosed || selectedFile != path) return;
    result.when(
      onSuccess: (response) {
        file = response.data;
        fileFailure = null;
      },
      onFailure: (failure) {
        file = null;
        fileFailure = failure;
      },
    );
    _emitLoaded();
  }

  static String? _defaultFile(TicketModel ticket) {
    if (ticket.files.contains('spec.md')) return 'spec.md';
    if (ticket.files.contains('ticket.md')) return 'ticket.md';
    return ticket.files.isEmpty ? null : ticket.files.first;
  }

  @override
  Future<void> close() {
    _reloadTimer?.cancel();
    unawaited(_muxSub?.cancel());
    return super.close();
  }
}
```

`service_locator.dart`:

```dart
    sl.registerFactoryParam<TicketDetailCubit, TicketDetailArgs, void>(
      (args, _) => TicketDetailCubit(sl<TicketsRepository>(), sl<MuxClient>(), args),
    );
```

- [ ] **Step 4: Run the cubit test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit_test.dart`
Expected: all pass. The first test expects three emits: loading, loaded after the ticket, loaded after the file.

- [ ] **Step 5: Write the failing screen test**

`test/feature/tickets/presentation/ticket_detail_screen/ui/ticket_detail_screen_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_file_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/ticket_detail_screen.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/widgets/frontmatter_block.dart';

class _MockTicketDetailCubit extends MockCubit<TicketDetailState> implements TicketDetailCubit {}

class _MockSessionsCubit extends MockCubit<SessionsState> implements SessionsCubit {}

const _ticket = TicketModel(
  projectId: 'repo',
  slug: 'search-page',
  title: 'Search page',
  brief: 'Full-text search over the docs.',
  status: 'planning',
  planningSessionId: 'repo-3',
  files: ['ticket.md', 'spec.md', 'plans/01-index.md', 'plans/01-index.kickoff.md'],
  plans: [PlanModel(file: 'plans/01-index.md', order: 1, title: 'Index', status: 'todo', kickoffFile: 'plans/01-index.kickoff.md')],
);

void main() {
  late _MockTicketDetailCubit detail;
  late _MockSessionsCubit sessions;

  setUp(() {
    detail = _MockTicketDetailCubit();
    sessions = _MockSessionsCubit();
    when(() => detail.state).thenReturn(const TicketDetailLoadedState(2));
    when(() => detail.args).thenReturn(const TicketDetailArgs(projectId: 'repo', slug: 'search-page'));
    when(() => detail.ticket).thenReturn(_ticket);
    when(() => detail.selectedFile).thenReturn('spec.md');
    when(() => detail.fileFailure).thenReturn(null);
    when(() => detail.file).thenReturn(const TicketFileModel(
      path: 'spec.md',
      content: '---\ntitle: Search page\nstatus: "draft"\n---\n\n# Spec body\n\nSome **bold** text.\n',
      modifiedAt: '2026-09-18T10:00:00Z',
    ));
    when(() => detail.selectFile(any())).thenAnswer((_) async {});
    when(() => detail.load()).thenAnswer((_) async {});
    when(() => detail.refresh()).thenAnswer((_) async {});
    when(() => sessions.state).thenReturn(const GetSessionsSuccessState(1));
    when(() => sessions.sessionsById).thenReturn(const {'repo-3': SessionModel(id: 'repo-3', status: 'working', activity: 'Writing the spec')});
    when(() => sessions.projects).thenReturn(const []);
  });

  Widget host() => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TicketDetailCubit>.value(value: detail),
            BlocProvider<SessionsCubit>.value(value: sessions),
          ],
          child: const TicketDetailScreen(),
        ),
      ),
    ),
  );

  testWidgets('renders header, file list, frontmatter block and the markdown body', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Search page'), findsWidgets);
    expect(find.text('Full-text search over the docs.'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Planning session'), findsOneWidget);
    expect(find.text('ticket.md'), findsOneWidget);
    expect(find.text('spec.md'), findsWidgets);
    expect(find.text('01 Index'), findsOneWidget);
    expect(find.text('Kickoff prompt'), findsOneWidget);
    expect(find.byType(FrontmatterBlock), findsOneWidget);
    expect(find.text('title'), findsOneWidget);
    expect(find.text('draft'), findsOneWidget);
    expect(find.text('Spec body'), findsOneWidget);
    expect(find.textContaining('bold'), findsWidgets);
  });

  testWidgets('tapping a file selects it', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('ticket.md'));
    verify(() => detail.selectFile('ticket.md')).called(1);
  });

  testWidgets('a ticket warning renders as a banner', (tester) async {
    when(() => detail.ticket).thenReturn(const TicketModel(projectId: 'repo', slug: 'broken', title: 'Broken', status: 'draft', warning: 'malformed frontmatter in ticket.md'));
    when(() => detail.selectedFile).thenReturn(null);
    when(() => detail.file).thenReturn(null);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('malformed frontmatter in ticket.md'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run the screen test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/tickets/presentation/ticket_detail_screen/ui/ticket_detail_screen_test.dart`
Expected: compile error.

- [ ] **Step 7: Write the screen and widgets**

`frontmatter_block.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class FrontmatterBlock extends StatelessWidget {
  const FrontmatterBlock({super.key, required this.fields});

  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSubtle,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('Frontmatter', style: AppTextStyle.style10SemiBold.copyWith(color: skin.textTertiary, letterSpacing: 0.6)),
          const VerticalSpace(6),
          for (final (key, value) in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, child: AppText(key, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary))),
                  Expanded(child: AppText(value, style: AppTextStyle.mono11Regular.copyWith(color: skin.textPrimary), maxLines: 4)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

`ticket_markdown_preview.dart` (the style sheet is `block_markdown.dart:50-102` verbatim, without the link/image handlers' snackbar plumbing):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketMarkdownPreview extends StatelessWidget {
  const TicketMarkdownPreview({super.key, required this.content});

  final String content;

  Future<void> _openLink(String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null || !const ['https', 'http', 'mailto'].contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = AppTextStyle.style13Regular.copyWith(color: skin.textPrimary, height: 1.4);
    return MarkdownBody(
      data: content,
      fitContent: false,
      onTapLink: (_, href, _) => _openLink(href),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        h1: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary, height: 1.35),
        h2: AppTextStyle.style15SemiBold.copyWith(color: skin.textPrimary, height: 1.4),
        h3: AppTextStyle.style14SemiBold.copyWith(color: skin.textPrimary, height: 1.4),
        h4: body.copyWith(fontWeight: FontWeight.w600),
        h5: body.copyWith(fontWeight: FontWeight.w600),
        h6: body.copyWith(fontWeight: FontWeight.w600),
        a: body.copyWith(color: skin.green, decoration: TextDecoration.underline, decorationColor: skin.green),
        strong: const TextStyle(fontWeight: FontWeight.w600),
        listBullet: body,
        blockSpacing: 8,
        listIndent: 22,
        code: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary, backgroundColor: skin.bgSurface, height: 1.5),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: skin.bgSurface,
          border: Border.all(color: skin.borderSubtle),
          borderRadius: BorderRadius.circular(10),
        ),
        blockquote: body.copyWith(color: skin.textSecondary),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: skin.borderDefault, width: 3))),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tableHead: body.copyWith(fontWeight: FontWeight.w600),
        tableBody: body,
        tableBorder: TableBorder.all(color: skin.borderSubtle),
        tableCellsPadding: const EdgeInsets.all(8),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: skin.borderSubtle))),
      ),
    );
  }
}
```

`ticket_detail_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/main_widgets/status_dot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';

class TicketDetailHeader extends StatelessWidget {
  const TicketDetailHeader({super.key, required this.ticket, required this.planningSession, required this.onOpenSession});

  final TicketModel ticket;
  final SessionModel? planningSession;
  final void Function(String sessionId) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = ticketStatusVisual(skin, ticket);
    final brief = ticket.brief?.trim() ?? '';
    final warning = ticket.warning?.trim() ?? '';
    final planningId = ticket.planningSessionId;
    final live = planningSessionLive(planningSession);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: AppText(ticket.title ?? ticket.slug ?? '', style: AppTextStyle.style19SemiBold, maxLines: 3)),
            const HorizontalSpace(10),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
              decoration: BoxDecoration(
                color: statusChipTint(skin, visual.color),
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(color: visual.color, size: 7, breathing: visual.breathing),
                  const HorizontalSpace(6),
                  AppText(visual.label, style: AppTextStyle.style11p5SemiBold.copyWith(color: visual.color)),
                ],
              ),
            ),
          ],
        ),
        const VerticalSpace(4),
        AppText(ticket.slug ?? '', style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
        if (brief.isNotEmpty) ...[
          const VerticalSpace(8),
          AppText(brief, style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary, height: 1.4), maxLines: 8),
        ],
        if (warning.isNotEmpty) ...[
          const VerticalSpace(10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: skin.tintAmber, borderRadius: BorderRadius.circular(10)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: skin.amber),
                const HorizontalSpace(6),
                Expanded(child: AppText(warning, style: AppTextStyle.style12Regular.copyWith(color: skin.amber), maxLines: 6)),
              ],
            ),
          ),
        ],
        if (planningId != null && planningId.isNotEmpty) ...[
          const VerticalSpace(14),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.terminal,
                label: 'Planning session',
                value: live ? (planningSession?.activity?.trim().isNotEmpty == true ? planningSession!.activity!.trim() : 'Running') : 'Ended',
                valueColor: live ? skin.orange : skin.textTertiary,
                onTap: () => onOpenSession(planningId),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

`ticket_file_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/tickets/data/model/plan_model.dart';
import 'package:operator_mobile/feature/tickets/data/model/ticket_model.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_presentation.dart';
import 'package:operator_mobile/feature/tickets/logic/ticket_status.dart';

class TicketFileList extends StatelessWidget {
  const TicketFileList({
    super.key,
    required this.ticket,
    required this.selected,
    required this.onSelect,
    required this.onPlanMore,
  });

  final TicketModel ticket;
  final String? selected;
  final void Function(String path) onSelect;
  final void Function(PlanModel plan) onPlanMore;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final groups = ticketFileGroups(ticket);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Files',
          children: [
            for (final doc in groups.docs)
              SettingsRow(
                icon: Icons.description_outlined,
                label: doc,
                value: doc == selected ? 'Viewing' : null,
                valueColor: skin.accent,
                onTap: () => onSelect(doc),
              ),
          ],
        ),
        if (groups.plans.isNotEmpty) ...[
          const VerticalSpace(14),
          SettingsGroup(
            title: 'Plans',
            children: [
              for (final plan in groups.plans) ...[
                SettingsRow(
                  icon: Icons.checklist_outlined,
                  label: planLabel(plan),
                  value: planStatusVisual(skin, plan.status).label,
                  valueColor: planStatusVisual(skin, plan.status).color,
                  trailing: IconButton(
                    icon: Icon(Icons.more_horiz, size: 18, color: skin.textTertiary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    onPressed: () => onPlanMore(plan),
                  ),
                  onTap: plan.file == null ? null : () => onSelect(plan.file!),
                ),
                if (plan.kickoffFile != null && plan.kickoffFile!.isNotEmpty)
                  SettingsRow(
                    icon: Icons.subdirectory_arrow_right,
                    label: 'Kickoff prompt',
                    value: plan.kickoffFile == selected ? 'Viewing' : null,
                    valueColor: skin.accent,
                    onTap: () => onSelect(plan.kickoffFile!),
                  ),
                if (plan.unordered == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: AppText(
                      'This plan has no NN- prefix and runs after the numbered ones.',
                      style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                      maxLines: 2,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
```

If `SettingsRow` rejects `onTap: null` together with `trailing`, read `settings_group.dart:63-131` and pass whichever combination it supports; the row must stay tappable for selection and carry the `more_horiz` button.

`ticket_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/tickets/logic/frontmatter.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/plan_actions_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/plan_ticket_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_actions_sheet.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_actions/ui/widgets/ticket_failure_text.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/logic/ticket_detail_cubit.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/widgets/frontmatter_block.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_detail_header.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_file_list.dart';
import 'package:operator_mobile/feature/tickets/presentation/ticket_detail_screen/ui/widgets/ticket_markdown_preview.dart';

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<TicketDetailCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TicketDetailCubit>();
    final sessions = context.read<SessionsCubit>();

    void openSession(String sessionId) => Navigator.of(context).pushNamed(RoutesStrings.session, arguments: {'sessionId': sessionId});

    return BlocBuilder<TicketDetailCubit, TicketDetailState>(
      builder: (context, state) {
        final ticket = cubit.ticket;
        final title = ticket?.title ?? cubit.args.slug;
        final planningSession = ticket?.planningSessionId == null ? null : sessions.sessionsById[ticket!.planningSessionId!];
        final projectName = sessions.projects.where((project) => project.id == cubit.args.projectId).firstOrNull?.name ?? cubit.args.projectId;

        Widget body;
        if (ticket == null && state is TicketDetailFailureState) {
          body = AppErrorWidget(failure: state.failure, onPressed: cubit.load);
        } else if (ticket == null) {
          body = const Center(child: AppExpressiveLoader(label: 'Loading ticket…'));
        } else {
          final file = cubit.file;
          final split = file?.content == null ? null : splitFrontmatter(file!.content!);
          body = RefreshIndicator(
            onRefresh: () async {
              Haptics.tap();
              await cubit.refresh();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                TicketDetailHeader(ticket: ticket, planningSession: planningSession, onOpenSession: openSession),
                const VerticalSpace(16),
                TicketFileList(
                  ticket: ticket,
                  selected: cubit.selectedFile,
                  onSelect: (path) {
                    Haptics.select();
                    cubit.selectFile(path);
                  },
                  onPlanMore: (plan) => showPlanActionsSheet(
                    context,
                    ticket: ticket,
                    plan: plan,
                    projectName: projectName,
                    onOpenSession: openSession,
                  ),
                ),
                if (cubit.selectedFile != null) ...[
                  const VerticalSpace(18),
                  Row(
                    children: [
                      Expanded(child: AppText(cubit.selectedFile!, style: AppTextStyle.mono12Bold.copyWith(color: skin.textSecondary))),
                      if (file?.modifiedAt != null)
                        AppText('Modified ${relativeTime(file!.modifiedAt)}', style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint)),
                    ],
                  ),
                  const VerticalSpace(8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: skin.bgSurface,
                      border: Border.all(color: skin.borderDefault),
                      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                    ),
                    child: cubit.fileFailure != null
                        ? TicketFailureText(failure: cubit.fileFailure!)
                        : split == null
                            ? const AppLoader(strokeWidth: 2)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (split.fields.isNotEmpty) ...[FrontmatterBlock(fields: split.fields), const VerticalSpace(12)],
                                  TicketMarkdownPreview(content: split.body),
                                ],
                              ),
                  ),
                ],
              ],
            ),
          );
        }

        return AppScaffold(
          appBar: GlobalAppbar.sub(
            titleText: title,
            actions: [
              if (ticket != null)
                IconButton(
                  icon: Icon(Icons.more_horiz, color: skin.textPrimary),
                  tooltip: 'Ticket actions',
                  onPressed: () => showTicketActionsSheet(
                    context,
                    ticket,
                    planningSession: planningSession,
                    onOpen: () {},
                    onPlan: () => showPlanTicketSheet(context, ticket),
                    onOpenSession: openSession,
                  ),
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
```

`app_router.dart`: add before `default:`

```dart
      case RoutesStrings.ticket:
        final args = settings.arguments as Map<String, dynamic>?;
        final ticketArgs = TicketDetailArgs(
          projectId: args?['projectId'] as String? ?? '',
          slug: args?['slug'] as String? ?? '',
          file: args?['file'] as String?,
        );
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: sl<SessionsCubit>()),
              BlocProvider<TicketDetailCubit>(create: (_) => sl<TicketDetailCubit>(param1: ticketArgs)),
            ],
            child: const TicketDetailScreen(),
          ),
          settings: settings,
        );
```

with the two imports. If `test/core/app_routes/app_router_test.dart` enumerates every route name, add `RoutesStrings.ticket` with `arguments: {'projectId': 'repo', 'slug': 's'}` to its list following the file's pattern.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/tickets test/core/app_routes`
Expected: all pass. `MarkdownBody` renders `# Spec body` as a `Text`/`RichText` with the plain string `Spec body`; if `find.text('Spec body')` misses because the heading is a `RichText`, use `find.textContaining('Spec body', findRichText: true)`.

- [ ] **Step 9: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): ticket detail screen with file list, frontmatter block and markdown preview

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Session ↔ ticket badge on cards and in the session header

**Files:**
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart:18-33, 176-196`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart` (`buildCard`, `:123-141`)
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:24-51` (`TerminalArgs`)
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart:135-146`
- Modify: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:53-88, 101-110`
- Modify: `packages/mobile/test/feature/terminal/terminal_harness.dart:91, 150-155` (optional `ticket` argument on `start`)
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart` (append)
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart` (append)
- Test: `packages/mobile/test/feature/sessions/presentation/session_route/session_route_screen_test.dart` (append if it asserts on `TerminalArgs`)

**Interfaces:**
- Consumes: `SessionModel.ticket`, `ticketBadgeLabel`, `RoutesStrings.ticket`.
- Produces: `SessionCard.onOpenTicket: void Function(SessionTicketRef ref)?`; `TerminalArgs.ticket: SessionTicketRef?` (in `props`); a tappable `slug · NN` chip in `TerminalChatHeader`'s subtitle row.
- Spec §3.4: badge `slug · NN` (or `slug · plan`) on the board card and in the session topbar; tapping opens the ticket page with that file selected. `TerminalArgs` is mobile terminal *feature* state, not the `packages/terminal` renderer or the pty-host that `TERMINAL.md` guards; nothing about resize, attach, replay, selection or copy changes.

- [ ] **Step 1: Write the failing tests**

Append to `session_card_test.dart` inside `main()` (add imports for `SessionTicketRef`):

```dart
  testWidgets('shows the ticket badge and reports a tap on it separately from the card', (tester) async {
    SessionTicketRef? opened;
    var cardTapped = false;
    const session = SessionModel(
      id: 'repo-4',
      projectId: 'repo',
      displayName: 'Index',
      status: 'working',
      ticket: SessionTicketRef(slug: 'search-page', planFile: 'plans/01-index.md', role: 'implementing'),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(
                session: session,
                showProject: true,
                onTap: () => cardTapped = true,
                onLongPress: () {},
                onOpenTicket: (ref) => opened = ref,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('search-page · 01'), findsOneWidget);
    await tester.tap(find.text('search-page · 01'));
    expect(opened?.planFile, 'plans/01-index.md');
    expect(cardTapped, isFalse);
  });

  testWidgets('a planning session reads slug · plan', (tester) async {
    const session = SessionModel(id: 'repo-3', displayName: 'Planner', status: 'working', ticket: SessionTicketRef(slug: 'search-page', role: 'planning'));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(body: SessionCard(session: session, showProject: false, onTap: () {}, onLongPress: () {})),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('search-page · plan'), findsOneWidget);
  });
```

Append to `terminal_screen_test.dart` inside `main()` (the harness's `start` gains an optional `SessionTicketRef? ticket` that it passes into the non-shell `TerminalArgs`):

```dart
  testWidgets('shows the ticket badge in the header when the session belongs to a ticket', (tester) async {
    harness.dispose();
    harness = TerminalHarness()
      ..start(ticket: const SessionTicketRef(slug: 'search-page', planFile: 'plans/02-ui.md', role: 'reviewing'));
    await harness.pump(tester, const TerminalScreen());

    expect(find.text('search-page · 02'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`
Expected: compile errors (`onOpenTicket`, `ticket:`).

- [ ] **Step 3: Implement**

`session_card.dart`: add `this.onOpenTicket,` to the constructor and `final void Function(SessionTicketRef ref)? onOpenTicket;`; import `session_ticket_ref.dart` and `feature/tickets/logic/ticket_presentation.dart`. In `build`, after `final issue = trackerIssueId(session.issueId);` add `final ticket = session.ticket;` and `final ticketLabel = ticket == null ? '' : ticketBadgeLabel(ticket);`. Extend the meta-row condition (`:133-136`) with `|| ticketLabel.isNotEmpty`, and after the issue chip block (`:176-194`) add:

```dart
                    if (ticketLabel.isNotEmpty) ...[
                      const HorizontalSpace(6),
                      GestureDetector(
                        onTap: onOpenTicket == null ? null : () => onOpenTicket!(ticket!),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: skin.tintBlue, borderRadius: BorderRadius.circular(5)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.confirmation_number_outlined, size: 10, color: skin.blue),
                              const HorizontalSpace(3),
                              AppText(ticketLabel, style: AppTextStyle.mono10Regular.copyWith(color: skin.blue)),
                            ],
                          ),
                        ),
                      ),
                    ],
```

`sessions_body.dart` `buildCard`: pass

```dart
                onOpenTicket: (ref) => Navigator.of(context).pushNamed(
                  RoutesStrings.ticket,
                  arguments: {'projectId': session.projectId, 'slug': ref.slug, if (ref.planFile != null) 'file': ref.planFile},
                ),
```

`terminal_cubit.dart` `TerminalArgs`: add `this.ticket,` to the constructor, `final SessionTicketRef? ticket;`, and `ticket` at the end of `props` (`:50`); import `session_ticket_ref.dart`.

`session_route_screen.dart`: add `SessionTicketRef? ticket` to the record type (`:53-60`), fill it with `session.ticket` in the session branch (`:66-73`) and `null` in the orchestrator branch (`:78-84`), and pass `ticket: session.ticket,` into `TerminalArgs(...)` (`:101-110`).

`terminal_chat_header.dart`: replace the subtitle `Text` (`:135-146`) with a `Row`:

```dart
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              [
                                args.harness ?? (args.shellOnly ? 'shell' : 'agent'),
                                if (args.projectName != null) args.projectName!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary, height: 1.4),
                            ),
                          ),
                          if (args.ticket != null && ticketBadgeLabel(args.ticket!).isNotEmpty) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pushNamed(
                                RoutesStrings.ticket,
                                arguments: {
                                  'projectId': args.projectId,
                                  'slug': args.ticket!.slug,
                                  if (args.ticket!.planFile != null) 'file': args.ticket!.planFile,
                                },
                              ),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: skin.tintBlue, borderRadius: BorderRadius.circular(5)),
                                child: Text(
                                  ticketBadgeLabel(args.ticket!),
                                  style: AppTextStyle.mono10Regular.copyWith(color: skin.blue),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
```

with imports for `RoutesStrings` and `ticket_presentation.dart`.

`terminal_harness.dart`: `void start({bool shellOnly = false, String? harness, SessionTicketRef? ticket})` and `ticket: ticket,` in the non-shell `TerminalArgs` (`:150-155`), plus the import.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/sessions test/feature/terminal`
Expected: all pass, including every pre-existing terminal test (the harness change is additive).

- [ ] **Step 5: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): ticket badge on session cards and in the session header

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Simulator verification against an isolated daemon, and the report

**Files:**
- Create: `docs/superpowers/plans/2026-09-18-planning-tickets-mobile-report.md`

**Interfaces:**
- Consumes: everything above; the daemon binary built from this branch's `backend/` (unchanged by this plan); `POST /api/v1/mobile/enable` on the **loopback** listener (`backend/internal/httpd/router.go:143-146`, `controllers/mobile.go:150-166`: returns `{enabled, host, port, password}`; the LAN listener binds `0.0.0.0:3011` or an ephemeral port when 3011 is taken, `backend/internal/httpd/lan_listener.go:143-157`, so always read `port` from the response); the LAN listener serves the same router behind bearer auth (`lan_listener.go:36-41`) with `/api/v1/mobile` blocked (`:62-68`).
- Pairing on the phone: onboarding → scan screen → **Connect manually** (`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart:37-42` pushes `RoutesStrings.manualConnect`); the manual screen has `HOST` (hint `192.168.1.2:3011`) and `PASSWORD` fields (`manual_connect_screen/ui/widgets/manual_connect_body.dart:29-35`); `HOST` accepts `host:port` and defaults the port to `3011` (`lib/feature/pairing/logic/host_address.dart:3, 16-41`); the cubit verifies against that target before saving (`manual_connect_cubit.dart:34-57`). The iOS Simulator shares the Mac's loopback, so `HOST` is `127.0.0.1:<port>`.

Green tests are not proof (`green-gates-from-subagent-builds-are-not-proof`). This task drives the real app against a real daemon. Never touch the user's daemons on ports 3001 and 3002.

- [ ] **Step 1: Build and start the isolated daemon with a scrubbed environment**

```bash
S=/tmp/claude-501/tickets-mobile && mkdir -p $S/data
cd backend && go build -o $S/opr ./cmd/opr && cd ..
env | cut -d= -f1 | grep -i claude    # must print nothing in the shell that starts the daemon
env -i HOME=$HOME PATH=$PATH OPERATOR_DATA_DIR=$S/data OPERATOR_RUN_FILE=$S/data/run.json OPERATOR_PORT=39320 $S/opr daemon > $S/daemon.log 2>&1 &
sleep 2 && curl -s 127.0.0.1:39320/readyz
lsof -nP -iTCP:3001 -iTCP:3002 -sTCP:LISTEN     # record the pids; they must be identical at the end
```

- [ ] **Step 2: Seed a throwaway `single_repo` project with one ticket (as in the plan-3 report)**

```bash
mkdir -p $S/repo && cd $S/repo && git init -q -b main && git commit -q --allow-empty -m init && cd -
curl -s -X POST 127.0.0.1:39320/api/v1/projects -H 'content-type: application/json' -d "{\"path\":\"$S/repo\"}"
B=127.0.0.1:39320/api/v1/projects/repo/tickets
curl -s -X POST $B -H 'content-type: application/json' -d '{"title":"Search page","brief":"Full-text search over the docs."}'
curl -s -X PUT "$B/search-page/file?path=spec.md" -H 'content-type: application/json' \
  -d '{"content":"---\ntitle: Search page\nstatus: \"draft\"\n---\n\n# Spec\n\nOne **bold** paragraph and a list:\n\n- index\n- ui\n"}'
curl -s -X PUT "$B/search-page/file?path=plans/01-index.md" -H 'content-type: application/json' -d '{"content":"---\ntitle: Index\n---\n\n# Index plan\n"}'
curl -s -X PUT "$B/search-page/file?path=plans/02-ui.md" -H 'content-type: application/json' -d '{"content":"---\ntitle: UI\n---\n\n# UI plan\n"}'
cd $S/repo && git add -A && git commit -q -m "ticket" && echo "dirty" >> .operator/tickets/search-page/spec.md && cd -
curl -s "$B/search-page/plans/01-index.md/assign?dryRun=1" -X POST     # expect {"warnings":["ticket_repo_dirty"]}
curl -s -X POST 127.0.0.1:39320/api/v1/mobile/enable                    # note host, port, password
```

- [ ] **Step 3: Run the app in the iOS Simulator and pair**

```bash
xcrun simctl list devices available | grep -i iphone     # pick one, e.g. "iPhone 17 Pro"
open -a Simulator && xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; sleep 5
cd packages/mobile && flutter run -d "iPhone 17 Pro"      # keep this terminal; or: flutter build ios --simulator --debug && xcrun simctl install booted build/ios/iphonesimulator/Runner.app && xcrun simctl launch booted dev.operator.operatorMobile
```

In the app: onboarding → the scan screen → **Connect manually** → `HOST` = `127.0.0.1:<port from Step 2>` → `PASSWORD` = `<password from Step 2>` → Connect. The Agents tab loads with `Syncing agents…` then the board. If the simulator tooling in this session offers `screenshot`/`tap`/`text`, use it for the walk below; otherwise drive the simulator by hand and keep screenshots with `xcrun simctl io booted screenshot $S/NN.png`.

- [ ] **Step 4: Walk the feature and record each result (screenshot + the curl that proves the daemon state)**

1. **Planned section**: the board shows `PLANNED 1` above `WORKING`; the `Search page` card reads `Ready` with rows `01 Index · To do` and `02 UI · To do`; the chip row reads `All · Planned 1 · Needs you · Working · Mergeable · Archive`.
2. **Ticket detail**: tap `Open` → header (`Search page`, brief, `Ready`), `Files` (`ticket.md`, `spec.md` marked `Viewing`), `Plans` (`01 Index`, `02 UI`), the frontmatter block (`title` / `Search page`, `status` / `draft`) above the rendered `Spec` heading, bold text and list. Tap `ticket.md` → the preview switches.
3. **Plan with agent**: from the card footer → sheet → Agent `Claude Code`, Model `claude-haiku-4-5-20251001` → `Start` → the app navigates to the session; back on the board the session card carries `search-page · plan` and the ticket reads `Planning` with the planner's activity; `curl -s 127.0.0.1:39320/api/v1/sessions | jq '.sessions[] | {id, ticket}'` shows `role: "planning"`. Kill it from the session header when done (it is a real Claude session on the user's account, so do this promptly): long-press the title → `Kill session`.
4. **Assign with `ticket_repo_dirty`, forced**: long-press `01 Index` → `Assign` → the sheet shows `Ticket / Plan / Project / Branch opr/search-page-01`, the suffix hint, `Checking…`, then the warning `The ticket folder has uncommitted changes…` and `Start`. Model `claude-haiku-4-5-20251001` → `Start` → session opens; its header badge reads `search-page · 01`; `curl … /sessions | jq` shows `branch: "opr/search-page-01"`, `ticket.role: "implementing"`; the daemon log shows `assign?dryRun=1` twice (open + re-check) then `assign` with `force: true`.
5. **`plan_assigned` race → Terminate and start**: on the board, long-press `02 UI` → `Assign` (clean: no warnings, `Start`). Before tapping, behind its back: `curl -s -X POST "$B/search-page/plans/02-ui.md/assign" -H 'content-type: application/json' -d '{"harness":"claude-code","model":"claude-haiku-4-5-20251001","force":true}'` → session A. Now tap `Start`: the re-check returns `plan_assigned`, the sheet shows `The assignment needs confirmation.` and the warning copy, and the button relabels to `Terminate and start`. Tap it: `curl … /sessions | jq '.sessions[] | {id,status,branch}'` shows session A `terminated` and a new session on `opr/search-page-02-2`. Check the daemon log order: `GET …/tickets/search-page`, `POST /sessions/<A>/kill`, `POST …/assign`.
6. **Review**: long-press `02 UI` → `Review` → `Planning session` (the planner is dead, so the daemon spawns a fresh reviewer, `service.go:722-760`) → `Review` → session opens with badge `search-page · 02`; `curl … /sessions | jq` shows `role: "reviewing"`.
7. **Merge-ready → Merge**: `curl -s -X POST "$B/search-page/plans/02-ui.md/merge-ready" -H 'content-type: application/json' -d '{"summary":"UI plan: two widgets, tests green, no conflicts with main."}'`. The board's `02 UI` row now reads `Awaiting your merge` and the ticket status `Waiting for your confirmation`. Long-press → `Merge` → the sheet shows the summary text → `Merge` → toast `Merging…`, the row reads `Merging`; `curl -s $B/search-page | jq '.ticket.plans[1].status'` prints `"merging"`. A second `Merge` attempt must show `This merge was already approved.` with `request <id>`.
8. **Mark done** on `01 Index` → confirm → row reads `Done`.
9. **Archive → Reopen**: long-press the card → `Archive` → confirm → the card leaves `PLANNED`; the `Archive` chip count rises; open `Archive` → the muted card reads `Archived` with `Reopen` → tap → it returns to `PLANNED`.
10. **Session badge navigation**: from a session card's `search-page · 01` chip → the ticket detail opens with `plans/01-index.md` marked `Viewing` and previewed.
11. **Live refresh**: with the board visible, `curl -s -X POST $B -H 'content-type: application/json' -d '{"title":"Second ticket"}'` — the card appears within a second without pull-to-refresh (mux `ticket_updated`).
12. **Failure envelope**: on the scratch path, `curl -s -X POST 127.0.0.1:39320/api/v1/projects -d '{"kind":"scratch","name":"scratch"}'` (or the request the desktop uses to create a scratch project; if none exists, skip and say so), then `New ticket` from the header with that project → the sheet shows `Tickets need a single-repository project.` with `request <id>`.

- [ ] **Step 5: Tear down**

```bash
curl -s 127.0.0.1:39320/api/v1/sessions | jq -r '.sessions[] | select(.isTerminated != true) | .id' | while read id; do curl -s -X POST 127.0.0.1:39320/api/v1/sessions/$id/kill; done
curl -s -X POST 127.0.0.1:39320/api/v1/mobile/disable
curl -s -X POST 127.0.0.1:39320/shutdown || kill %1
lsof -nP -iTCP:3001 -iTCP:3002 -sTCP:LISTEN     # same pids as Step 1
```

Remove the paired desktop from the app (Settings → Connections) so the simulator does not keep dialling a dead port.

- [ ] **Step 6: Write the report**

`docs/superpowers/plans/2026-09-18-planning-tickets-mobile-report.md`, in the shape of the three earlier reports:

- `## Commit list` — every commit on the branch with its hash and one line.
- `## Gate output summary` — the final `flutter analyze` line and the `flutter test` totals.
- `## Deviations from the plan, and why` — every place the code differs from a task's text (widget API details, test finders, helper placement), each with the reason.
- `## Simulator verification (isolated daemon on port 39320)` — the twelve walk items above, each with what was seen and the curl proof; screenshots listed by path. Anything not reached is written as such with the reason, never as passed.
- `## Anything left undone, and why`.
- `## Do not merge` — the reviewing session merges after its own review.

- [ ] **Step 7: Gate and commit**

```bash
cd packages/mobile && flutter analyze && flutter test
git add docs/superpowers/plans/2026-09-18-planning-tickets-mobile-report.md
git commit -m "docs: planning tickets mobile implementation report

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Do not push and do not merge; report the branch, worktree path, base and head commits, and the report path.

---

## Self-review

**Spec coverage.** §1.3 derived statuses → Task 4 tables (every plan and ticket status, `N/M merged`). §2.4 assign (dry run, five warnings, force, branch name) → Tasks 3, 4, 8. §2.6 roles/review/merge confirmation → Task 9 (reviewer `planner|new`, Merge sheet with `mergeSummary`, `TICKET_MERGE_APPROVED` copy). §3.1 column → Task 10 (Planned first, count, `+`, card anatomy, plan rows with click-through, `Plan with agent` / `Open planning session`, needs-repo hint). §3.3 preview half → Task 11 (file list with plans and kickoffs, frontmatter block, markdown body, warning banner; no editor by §3.7). §3.4 links → Task 12. §3.5 archive → Tasks 6 and 10 (archived tickets in the Archive section, `Reopen`). §3.7 → the header's overrule list. §4 edge cases → warning banner (Task 11), `Reassign` on `terminated` (Tasks 4, 9), `ticket_not_on_default_branch` copy (Task 4), non-Claude harness drops the account (Task 7). §5 testing → the closed-enum table tests (Task 4), curl-shape `fromJson` tests (Task 2), cubit tests for the assign flow (Task 8), widget tests per sheet, simulator walk (Task 13).

**Placeholder scan.** No `TBD`/`TODO`; every code step carries the code; the only conditional instructions are about verifying an existing widget's exact constructor (`PrimaryButton` text rendering, `SettingsRow` with both `onTap` and `trailing`, `AppPill` `count`), each pointing at the file and lines to read.

**Type and name consistency.** `TicketModel`/`PlanModel`/`TicketFileModel`/`SessionTicketRef` (Task 2) are the only model names used later; `TicketsRepository` methods (Task 3) match every cubit call (Tasks 6, 8, 11); `TicketSpawnChoice` (Task 7) is what `AssignPlanCubit.start` (Task 8) and `ReviewPlanSheetBody` (Task 9) consume; `planLabel` is added in Task 9 and used by Tasks 9, 11 and the Task 8 sheet (replaced per Task 9 Step 1); `showTicketActionsSheet`/`showPlanActionsSheet`/`showPlanTicketSheet`/`showCreateTicketSheet` signatures match their call sites in Tasks 10 and 11; `SessionsCubit.visibleTickets/sessionsById` (Task 5) match Tasks 10–12; `RoutesStrings.ticket` is declared in Task 6 and routed in Task 11, with the arguments map `{projectId, slug, file?}` used identically in Tasks 10, 11 and 12.
