# Planning Tickets: Board and Ticket Page Implementation Plan (plan 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show planning tickets in a leftmost PLANNED board column and on a ticket page with read-only markdown preview, with the plan, review, merge-confirmation, done, archive and reopen actions as plain buttons, wired live to the daemon routes that plan 1 shipped.

**Architecture:** Frontend only. New hooks (`useTicketsQuery`, `useTicketMutations`) sit over the generated openapi-fetch client and invalidate on the `ticket_updated` CDC event plus a per-project `tickets_changed` SSE stream. A `lib/ticket-presentation.ts` module maps the daemon's derived ticket and plan statuses to the board's existing status tokens. New components live under `components/tickets/`; `SessionsBoard` gains a fifth grid cell, `SessionCard` and `ShellTopbar` gain a ticket badge, the archive bar gains ticket entries, and a new file route renders the ticket page. Two existing internals are extracted so the tickets UI can reuse them: `ReviewMarkdownBody` becomes `components/MarkdownBody.tsx` and `TaskModelPicker` moves out of `TaskComposer.tsx`.

**Tech Stack:** React 19, TanStack Router (file routes, `validateSearch`), TanStack Query 5 (`useQueries`, `useMutation`), openapi-fetch typed client, react-markdown + remark-gfm, shadcn primitives in `components/ui/*`, i18next catalogues, Vitest + Testing Library.

**Spec:** `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` — §1.3 (statuses), §2.6 (roles, review, merge confirmation), §3.1, §3.3 (preview only), §3.4, §3.5, §3.6, §4, §5 (frontend bullets), §6 "Plan 2". Where §3 and §2.6 disagree because §2.6 was written later, §2.6 wins: the plan row statuses `reviewing`, `awaiting_merge`, `merging` and the Merge confirmation are in scope here.

**Baseline:** `development` at commit `25b6ebe24` (plan 1 merged). The daemon contract this plan consumes is in `backend/internal/httpd/controllers/tickets.go:40-57` (routes), `backend/internal/httpd/controllers/dto.go:1522-1613` (DTOs) and the generated `frontend/src/api/schema.ts` (`TicketView` at 3076, `PlanView` at 2488, `SessionTicketRef` at 2820, ticket paths at 642-845). Do not change anything under `backend/`.

## Global Constraints

- Branch `feat/planning-tickets-board` cut from `development`; never commit to `development` or `master` directly (`CLAUDE.md` "Branches").
- No comments in new code (user rule). Existing files keep the comments they have; moved code keeps its comments.
- Every visual decision follows `DESIGN.md` and the "clone agent-orchestrator verbatim" banner; new UI is built from `components/ui/*` shadcn primitives and the board's existing tokens (`text-status-*`, `bg-status-*`, `var(--color-status-*)`, `settings-field-*`, `settingsDialog*Class`). No new UI dependency. dnd-kit stays unused (plan 3).
- All user-visible copy goes through `t("...")`; `frontend/src/renderer/i18n/renderer-coverage.test.ts` fails on hardcoded JSX text, and `frontend/src/renderer/i18n/instance.test.ts:149-159` fails when any of the eight locales (`en`, `zh-CN`, `ja`, `ko`, `es`, `fr`, `de`, `pt-BR`) misses a key. Keys are flat, dotted, and inserted in alphabetical order in each JSON.
- Plan statuses (verbatim from `dto.go:1526`): `todo, idle, working, needs_you, in_review, reviewing, awaiting_merge, merging, merged, done, terminated`. Ticket statuses (`dto.go:1540`): `draft, planning, ready, in_progress, awaiting_merge, done, archived`.
- Error envelope is `{error, code, message, requestId}`; UI branches on `code` and keeps `requestId` in every error line (`lib/api-client.ts:258-289` has `apiErrorCode`, `apiErrorRequestId`, `apiErrorMessage`).
- Gates, run from `frontend/` after every task: `npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`. `npm run typecheck` rebuilds `packages/terminal` first (`frontend/package.json:33`); if it touches `packages/terminal/package-lock.json`, revert that file before committing.
- Frontend tests run with `npx vitest run --config vite.renderer.config.ts <path>`; the i18n gates are `src/renderer/i18n/renderer-coverage.test.ts` and `src/renderer/i18n/instance.test.ts`.
- Commit messages end with the `Co-Authored-By` trailer your session's attribution reminder gives.

## File map

Create:
- `frontend/src/renderer/lib/ticket-presentation.ts` (+ `.test.ts`): schema type aliases, status → label/tone mapping, badge label, frontmatter split, file grouping.
- `frontend/src/renderer/lib/ticket-events.ts` (+ `.test.ts`): per-project `tickets_changed` SSE subscription with ref counting, modelled on `lib/workspace-file-events.ts`.
- `frontend/src/renderer/hooks/useTicketsQuery.ts`: query keys, list/one/file queries, live subscription.
- `frontend/src/renderer/hooks/useTicketMutations.ts` (+ `.test.tsx`): create, plan, review, merge, done, archive/unarchive mutations and `ticketErrorMessage`.
- `frontend/src/renderer/components/MarkdownBody.tsx` (+ `.test.tsx`): extracted from `SessionInspector.tsx:1744-1775`.
- `frontend/src/renderer/components/TaskModelPicker.tsx`: moved from `TaskComposer.tsx:459-638`.
- `frontend/src/renderer/components/tickets/TicketBadge.tsx`
- `frontend/src/renderer/components/tickets/TicketRoleFields.tsx`
- `frontend/src/renderer/components/tickets/CreateTicketSheet.tsx` (+ `.test.tsx`)
- `frontend/src/renderer/components/tickets/PlanWithAgentSheet.tsx` (+ `.test.tsx`)
- `frontend/src/renderer/components/tickets/ReviewPlanSheet.tsx`
- `frontend/src/renderer/components/tickets/MergeConfirmDialog.tsx`
- `frontend/src/renderer/components/tickets/PlanRow.tsx`
- `frontend/src/renderer/components/tickets/TicketCard.tsx` (+ `.test.tsx`)
- `frontend/src/renderer/components/tickets/PlannedColumn.tsx`
- `frontend/src/renderer/components/tickets/ArchiveTicketItem.tsx`
- `frontend/src/renderer/components/tickets/TicketPage.tsx` (+ `.test.tsx`)
- `frontend/src/renderer/routes/_shell.projects.$projectId_.tickets.$slug.tsx`

Modify:
- `frontend/src/renderer/i18n/{en,zh-CN,ja,ko,es,fr,de,pt-BR}.json`: `tickets.*` keys.
- `frontend/src/renderer/lib/api-client.ts:69-101` (`ROUTE_TEMPLATES`) and `api-client.test.ts`.
- `frontend/src/renderer/lib/event-transport.ts:39-46` (`refreshWorkspaces`) and its test.
- `frontend/src/renderer/types/workspace.ts:124-185` (`WorkspaceSession.ticket`).
- `frontend/src/renderer/hooks/useWorkspaceQuery.ts:84-115` (map `session.ticket`) and its test.
- `frontend/src/renderer/components/SessionsBoard.tsx`: fifth column, archive entries, ticket badge, sessions index.
- `frontend/src/renderer/components/SessionsBoard.test.tsx`: mock the ticket hooks; lane count 5; badge test.
- `frontend/src/renderer/components/ShellTopbar.tsx:159-167`: ticket badge beside the branch.
- `frontend/src/renderer/components/SessionInspector.tsx`: import `MarkdownBody`.
- `frontend/src/renderer/components/TaskComposer.tsx`: import `TaskModelPicker`.
- `frontend/e2e/smoke-t0.spec.ts:154-164`: five columns.
- `frontend/src/renderer/routeTree.gen.ts`: regenerated by `TanStackRouterVite` (`frontend/vite.renderer.config.ts:111-116`) whenever vitest or vite loads that config; run the vitest gate before `npm run typecheck` in Task 6 and commit the regenerated file.

---

### Task 1: Message catalogue for the tickets UI

**Files:**
- Modify: `frontend/src/renderer/i18n/en.json`, `zh-CN.json`, `ja.json`, `ko.json`, `es.json`, `fr.json`, `de.json`, `pt-BR.json`
- Test: `frontend/src/renderer/i18n/instance.test.ts` (existing parity tests), `frontend/src/renderer/i18n/renderer-coverage.test.ts` (existing)

**Interfaces:**
- Produces: every `tickets.*` `MessageKey` used by Tasks 2-9. `MessageKey` is `keyof typeof enMessages` (`frontend/src/renderer/i18n/messages.ts:21`), so a key missing from `en.json` is a type error at the call site, and a key missing from any other locale fails `instance.test.ts:149-159`.

All eight files are flat JSON objects with dotted keys whose order is not enforced by any test. Insert the block below in each file as one contiguous block immediately before the `"time.daysAgo"` line (`en.json:925`; the other locales carry the same key in the same relative position). The JSON must stay valid: keep the trailing comma on the previous entry and none after the last entry of the file.

- [ ] **Step 1: Run the parity test to see it pass before the change**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/i18n/instance.test.ts`
Expected: PASS (baseline).

- [ ] **Step 2: Add the English keys**

Add to `frontend/src/renderer/i18n/en.json`:

```json
	"tickets.account": "Claude account",
	"tickets.archive": "Archive",
	"tickets.archiveAria": "Archive ticket {{title}}",
	"tickets.archiveFailed": "Could not archive the ticket",
	"tickets.badgeAria": "Open ticket {{label}}",
	"tickets.brief": "Brief",
	"tickets.briefPlaceholder": "One paragraph the planning agent starts from",
	"tickets.column": "Planned",
	"tickets.columnAria": "Planned tickets",
	"tickets.columnCountAria": "{{count}} open tickets",
	"tickets.create": "New ticket",
	"tickets.createDescription": "A ticket is a folder in the repository holding a spec and its implementation plans.",
	"tickets.createFailed": "Could not create the ticket",
	"tickets.creating": "Creating…",
	"tickets.defaultsHint": "Empty fields use the project's ticket defaults.",
	"tickets.empty": "No tickets yet",
	"tickets.emptyHint": "Create a ticket, then plan it with an agent.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "That file is not in the ticket folder.",
	"tickets.error.TICKET_MERGE_APPROVED": "This merge was already approved.",
	"tickets.error.TICKET_NOT_FOUND": "The ticket no longer exists.",
	"tickets.error.TICKET_NOT_MERGE_READY": "The reviewer has not reported this plan as ready to merge.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "That plan is not in the ticket folder.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "Assign the plan to a session first.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "This ticket already has a running planning session.",
	"tickets.error.TICKET_REVIEWER_INVALID": "The reviewer must be the planning session or a new session.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "Tickets need a single-repository project.",
	"tickets.extra": "Extra instructions",
	"tickets.extraPlaceholder": "Optional notes appended to the prompt",
	"tickets.fileLoadFailed": "Could not load the file",
	"tickets.fileModified": "Modified {{time}}",
	"tickets.files": "Files",
	"tickets.filesAria": "Ticket files",
	"tickets.frontmatter": "Frontmatter",
	"tickets.harness": "Agent",
	"tickets.kickoff": "Kickoff prompt",
	"tickets.loadFailed": "Could not load tickets",
	"tickets.markDone": "Mark done",
	"tickets.markDoneFailed": "Could not mark the plan done",
	"tickets.merge": "Merge",
	"tickets.mergeDescription": "Tells the reviewer to merge the branch into the default branch now.",
	"tickets.mergeFailed": "Could not approve the merge",
	"tickets.mergeTitle": "Merge {{plan}}",
	"tickets.mergedCount": "{{merged}}/{{total}} merged",
	"tickets.merging": "Merging…",
	"tickets.model": "Model",
	"tickets.needsRepo": "Tickets need a single-repository project.",
	"tickets.notFound": "Ticket not found",
	"tickets.open": "Open",
	"tickets.openPlanningSession": "Open planning session",
	"tickets.openSessionAria": "Open the session for {{plan}}",
	"tickets.plan.status.awaiting_merge": "Awaiting your merge",
	"tickets.plan.status.done": "Done",
	"tickets.plan.status.idle": "Idle",
	"tickets.plan.status.in_review": "In review",
	"tickets.plan.status.merged": "Merged",
	"tickets.plan.status.merging": "Merging",
	"tickets.plan.status.needs_you": "Needs you",
	"tickets.plan.status.reviewing": "Reviewing",
	"tickets.plan.status.terminated": "Terminated",
	"tickets.plan.status.todo": "To do",
	"tickets.plan.status.working": "Working",
	"tickets.planDescription": "Starts the planning session in place at the project root. It writes the spec and the implementation plans into the ticket folder.",
	"tickets.planFailed": "Could not start the planning session",
	"tickets.planWithAgent": "Plan with agent",
	"tickets.planningSession": "Planning session",
	"tickets.plans": "Plans",
	"tickets.plansAria": "Plans of {{title}}",
	"tickets.project": "Project",
	"tickets.reopen": "Reopen",
	"tickets.reopenAria": "Reopen ticket {{title}}",
	"tickets.reopenFailed": "Could not reopen the ticket",
	"tickets.requestId": "request {{requestId}}",
	"tickets.review": "Review",
	"tickets.reviewDescription": "The reviewer checks the branch against the spec and plan, fixes what is wrong, and reports when it is ready to merge.",
	"tickets.reviewFailed": "Could not start the review",
	"tickets.reviewTitle": "Review {{plan}}",
	"tickets.reviewer": "Reviewer",
	"tickets.reviewer.new": "New session",
	"tickets.reviewer.planner": "Planning session",
	"tickets.sessionMissing": "Session no longer exists",
	"tickets.start": "Start",
	"tickets.starting": "Starting…",
	"tickets.status.archived": "Archived",
	"tickets.status.awaiting_merge": "Waiting for your confirmation",
	"tickets.status.done": "Done",
	"tickets.status.draft": "Draft",
	"tickets.status.in_progress": "In progress",
	"tickets.status.planning": "Planning",
	"tickets.status.ready": "Ready",
	"tickets.title": "Title",
	"tickets.titlePlaceholder": "What are we building?",
	"tickets.unorderedPlan": "This plan has no NN- prefix and runs after the numbered ones.",
```

- [ ] **Step 3: Run the parity test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/i18n/instance.test.ts`
Expected: FAIL with `zh-CN is missing tickets.account` (and the other locales).

- [ ] **Step 4: Add the seven translations**

`zh-CN.json`:

```json
	"tickets.account": "Claude 账户",
	"tickets.archive": "归档",
	"tickets.archiveAria": "归档工单 {{title}}",
	"tickets.archiveFailed": "无法归档工单",
	"tickets.badgeAria": "打开工单 {{label}}",
	"tickets.brief": "简述",
	"tickets.briefPlaceholder": "规划代理起步所需的一段话",
	"tickets.column": "已规划",
	"tickets.columnAria": "已规划的工单",
	"tickets.columnCountAria": "{{count}} 个进行中的工单",
	"tickets.create": "新建工单",
	"tickets.createDescription": "工单是仓库中的一个文件夹，包含规格说明及其实现计划。",
	"tickets.createFailed": "无法创建工单",
	"tickets.creating": "正在创建…",
	"tickets.defaultsHint": "留空的字段使用项目的工单默认值。",
	"tickets.empty": "尚无工单",
	"tickets.emptyHint": "创建一个工单，然后让代理进行规划。",
	"tickets.error.TICKET_FILE_NOT_FOUND": "该文件不在工单文件夹中。",
	"tickets.error.TICKET_MERGE_APPROVED": "此合并已获批准。",
	"tickets.error.TICKET_NOT_FOUND": "该工单已不存在。",
	"tickets.error.TICKET_NOT_MERGE_READY": "审阅者尚未报告此计划可以合并。",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "该计划不在工单文件夹中。",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "请先将计划分配给一个会话。",
	"tickets.error.TICKET_PLANNING_ACTIVE": "此工单已有一个正在运行的规划会话。",
	"tickets.error.TICKET_REVIEWER_INVALID": "审阅者必须是规划会话或新会话。",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "工单需要单仓库项目。",
	"tickets.extra": "附加说明",
	"tickets.extraPlaceholder": "附加到提示词末尾的可选备注",
	"tickets.fileLoadFailed": "无法加载文件",
	"tickets.fileModified": "修改于 {{time}}",
	"tickets.files": "文件",
	"tickets.filesAria": "工单文件",
	"tickets.frontmatter": "元数据",
	"tickets.harness": "代理",
	"tickets.kickoff": "启动提示词",
	"tickets.loadFailed": "无法加载工单",
	"tickets.markDone": "标记完成",
	"tickets.markDoneFailed": "无法将计划标记为完成",
	"tickets.merge": "合并",
	"tickets.mergeDescription": "通知审阅者立即将分支合并到默认分支。",
	"tickets.mergeFailed": "无法批准合并",
	"tickets.mergeTitle": "合并 {{plan}}",
	"tickets.mergedCount": "已合并 {{merged}}/{{total}}",
	"tickets.merging": "正在合并…",
	"tickets.model": "模型",
	"tickets.needsRepo": "工单需要单仓库项目。",
	"tickets.notFound": "未找到工单",
	"tickets.open": "打开",
	"tickets.openPlanningSession": "打开规划会话",
	"tickets.openSessionAria": "打开 {{plan}} 的会话",
	"tickets.plan.status.awaiting_merge": "等待你合并",
	"tickets.plan.status.done": "完成",
	"tickets.plan.status.idle": "空闲",
	"tickets.plan.status.in_review": "审阅中",
	"tickets.plan.status.merged": "已合并",
	"tickets.plan.status.merging": "正在合并",
	"tickets.plan.status.needs_you": "需要你",
	"tickets.plan.status.reviewing": "正在审阅",
	"tickets.plan.status.terminated": "已终止",
	"tickets.plan.status.todo": "待办",
	"tickets.plan.status.working": "进行中",
	"tickets.planDescription": "在项目根目录就地启动规划会话。它会把规格说明和实现计划写入工单文件夹。",
	"tickets.planFailed": "无法启动规划会话",
	"tickets.planWithAgent": "用代理规划",
	"tickets.planningSession": "规划会话",
	"tickets.plans": "计划",
	"tickets.plansAria": "{{title}} 的计划",
	"tickets.project": "项目",
	"tickets.reopen": "重新打开",
	"tickets.reopenAria": "重新打开工单 {{title}}",
	"tickets.reopenFailed": "无法重新打开工单",
	"tickets.requestId": "请求 {{requestId}}",
	"tickets.review": "审阅",
	"tickets.reviewDescription": "审阅者对照规格说明和计划检查分支，修正问题，并在可以合并时报告。",
	"tickets.reviewFailed": "无法启动审阅",
	"tickets.reviewTitle": "审阅 {{plan}}",
	"tickets.reviewer": "审阅者",
	"tickets.reviewer.new": "新会话",
	"tickets.reviewer.planner": "规划会话",
	"tickets.sessionMissing": "会话已不存在",
	"tickets.start": "开始",
	"tickets.starting": "正在启动…",
	"tickets.status.archived": "已归档",
	"tickets.status.awaiting_merge": "等待你的确认",
	"tickets.status.done": "完成",
	"tickets.status.draft": "草稿",
	"tickets.status.in_progress": "进行中",
	"tickets.status.planning": "规划中",
	"tickets.status.ready": "就绪",
	"tickets.title": "标题",
	"tickets.titlePlaceholder": "我们要构建什么？",
	"tickets.unorderedPlan": "此计划没有 NN- 前缀，将在编号计划之后运行。",
```

`ja.json`:

```json
	"tickets.account": "Claude アカウント",
	"tickets.archive": "アーカイブ",
	"tickets.archiveAria": "チケット {{title}} をアーカイブ",
	"tickets.archiveFailed": "チケットをアーカイブできませんでした",
	"tickets.badgeAria": "チケット {{label}} を開く",
	"tickets.brief": "概要",
	"tickets.briefPlaceholder": "計画エージェントの出発点となる一段落",
	"tickets.column": "計画済み",
	"tickets.columnAria": "計画済みのチケット",
	"tickets.columnCountAria": "{{count}} 件の未完了チケット",
	"tickets.create": "新しいチケット",
	"tickets.createDescription": "チケットは仕様書と実装計画を収めたリポジトリ内のフォルダーです。",
	"tickets.createFailed": "チケットを作成できませんでした",
	"tickets.creating": "作成中…",
	"tickets.defaultsHint": "空の項目にはプロジェクトのチケット既定値が使われます。",
	"tickets.empty": "チケットはまだありません",
	"tickets.emptyHint": "チケットを作成し、エージェントに計画させましょう。",
	"tickets.error.TICKET_FILE_NOT_FOUND": "そのファイルはチケットフォルダーにありません。",
	"tickets.error.TICKET_MERGE_APPROVED": "このマージはすでに承認されています。",
	"tickets.error.TICKET_NOT_FOUND": "チケットはもう存在しません。",
	"tickets.error.TICKET_NOT_MERGE_READY": "レビュアーはこの計画をマージ可能と報告していません。",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "その計画はチケットフォルダーにありません。",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "先に計画をセッションに割り当ててください。",
	"tickets.error.TICKET_PLANNING_ACTIVE": "このチケットには実行中の計画セッションがあります。",
	"tickets.error.TICKET_REVIEWER_INVALID": "レビュアーは計画セッションか新しいセッションのいずれかです。",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "チケットには単一リポジトリのプロジェクトが必要です。",
	"tickets.extra": "追加の指示",
	"tickets.extraPlaceholder": "プロンプトの末尾に追加する任意のメモ",
	"tickets.fileLoadFailed": "ファイルを読み込めませんでした",
	"tickets.fileModified": "{{time}} に更新",
	"tickets.files": "ファイル",
	"tickets.filesAria": "チケットのファイル",
	"tickets.frontmatter": "フロントマター",
	"tickets.harness": "エージェント",
	"tickets.kickoff": "キックオフプロンプト",
	"tickets.loadFailed": "チケットを読み込めませんでした",
	"tickets.markDone": "完了にする",
	"tickets.markDoneFailed": "計画を完了にできませんでした",
	"tickets.merge": "マージ",
	"tickets.mergeDescription": "レビュアーにブランチを今すぐ既定ブランチへマージするよう伝えます。",
	"tickets.mergeFailed": "マージを承認できませんでした",
	"tickets.mergeTitle": "{{plan}} をマージ",
	"tickets.mergedCount": "{{merged}}/{{total}} マージ済み",
	"tickets.merging": "マージ中…",
	"tickets.model": "モデル",
	"tickets.needsRepo": "チケットには単一リポジトリのプロジェクトが必要です。",
	"tickets.notFound": "チケットが見つかりません",
	"tickets.open": "開く",
	"tickets.openPlanningSession": "計画セッションを開く",
	"tickets.openSessionAria": "{{plan}} のセッションを開く",
	"tickets.plan.status.awaiting_merge": "マージ待ち",
	"tickets.plan.status.done": "完了",
	"tickets.plan.status.idle": "待機中",
	"tickets.plan.status.in_review": "レビュー中",
	"tickets.plan.status.merged": "マージ済み",
	"tickets.plan.status.merging": "マージ中",
	"tickets.plan.status.needs_you": "対応が必要",
	"tickets.plan.status.reviewing": "レビュー実行中",
	"tickets.plan.status.terminated": "終了",
	"tickets.plan.status.todo": "未着手",
	"tickets.plan.status.working": "作業中",
	"tickets.planDescription": "プロジェクトルートでその場で計画セッションを開始します。仕様書と実装計画をチケットフォルダーに書き出します。",
	"tickets.planFailed": "計画セッションを開始できませんでした",
	"tickets.planWithAgent": "エージェントで計画",
	"tickets.planningSession": "計画セッション",
	"tickets.plans": "計画",
	"tickets.plansAria": "{{title}} の計画",
	"tickets.project": "プロジェクト",
	"tickets.reopen": "再開",
	"tickets.reopenAria": "チケット {{title}} を再開",
	"tickets.reopenFailed": "チケットを再開できませんでした",
	"tickets.requestId": "リクエスト {{requestId}}",
	"tickets.review": "レビュー",
	"tickets.reviewDescription": "レビュアーは仕様書と計画に照らしてブランチを確認し、問題を修正し、マージ可能になったら報告します。",
	"tickets.reviewFailed": "レビューを開始できませんでした",
	"tickets.reviewTitle": "{{plan}} をレビュー",
	"tickets.reviewer": "レビュアー",
	"tickets.reviewer.new": "新しいセッション",
	"tickets.reviewer.planner": "計画セッション",
	"tickets.sessionMissing": "セッションはもう存在しません",
	"tickets.start": "開始",
	"tickets.starting": "開始中…",
	"tickets.status.archived": "アーカイブ済み",
	"tickets.status.awaiting_merge": "あなたの確認待ち",
	"tickets.status.done": "完了",
	"tickets.status.draft": "下書き",
	"tickets.status.in_progress": "進行中",
	"tickets.status.planning": "計画中",
	"tickets.status.ready": "準備完了",
	"tickets.title": "タイトル",
	"tickets.titlePlaceholder": "何を作りますか？",
	"tickets.unorderedPlan": "この計画には NN- 接頭辞がなく、番号付きの計画の後に実行されます。",
```

`ko.json`:

```json
	"tickets.account": "Claude 계정",
	"tickets.archive": "보관",
	"tickets.archiveAria": "티켓 {{title}} 보관",
	"tickets.archiveFailed": "티켓을 보관할 수 없습니다",
	"tickets.badgeAria": "티켓 {{label}} 열기",
	"tickets.brief": "요약",
	"tickets.briefPlaceholder": "계획 에이전트가 시작할 한 단락",
	"tickets.column": "계획됨",
	"tickets.columnAria": "계획된 티켓",
	"tickets.columnCountAria": "진행 중인 티켓 {{count}}개",
	"tickets.create": "새 티켓",
	"tickets.createDescription": "티켓은 사양과 구현 계획을 담은 저장소 안의 폴더입니다.",
	"tickets.createFailed": "티켓을 만들 수 없습니다",
	"tickets.creating": "만드는 중…",
	"tickets.defaultsHint": "비워 둔 항목에는 프로젝트의 티켓 기본값이 사용됩니다.",
	"tickets.empty": "아직 티켓이 없습니다",
	"tickets.emptyHint": "티켓을 만든 뒤 에이전트로 계획하세요.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "해당 파일이 티켓 폴더에 없습니다.",
	"tickets.error.TICKET_MERGE_APPROVED": "이 병합은 이미 승인되었습니다.",
	"tickets.error.TICKET_NOT_FOUND": "티켓이 더 이상 존재하지 않습니다.",
	"tickets.error.TICKET_NOT_MERGE_READY": "리뷰어가 이 계획을 병합 가능으로 보고하지 않았습니다.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "해당 계획이 티켓 폴더에 없습니다.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "먼저 계획을 세션에 할당하세요.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "이 티켓에는 이미 실행 중인 계획 세션이 있습니다.",
	"tickets.error.TICKET_REVIEWER_INVALID": "리뷰어는 계획 세션 또는 새 세션이어야 합니다.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "티켓에는 단일 저장소 프로젝트가 필요합니다.",
	"tickets.extra": "추가 지시",
	"tickets.extraPlaceholder": "프롬프트 끝에 덧붙일 선택적 메모",
	"tickets.fileLoadFailed": "파일을 불러올 수 없습니다",
	"tickets.fileModified": "{{time}} 수정",
	"tickets.files": "파일",
	"tickets.filesAria": "티켓 파일",
	"tickets.frontmatter": "프런트매터",
	"tickets.harness": "에이전트",
	"tickets.kickoff": "킥오프 프롬프트",
	"tickets.loadFailed": "티켓을 불러올 수 없습니다",
	"tickets.markDone": "완료로 표시",
	"tickets.markDoneFailed": "계획을 완료로 표시할 수 없습니다",
	"tickets.merge": "병합",
	"tickets.mergeDescription": "리뷰어에게 지금 브랜치를 기본 브랜치에 병합하도록 알립니다.",
	"tickets.mergeFailed": "병합을 승인할 수 없습니다",
	"tickets.mergeTitle": "{{plan}} 병합",
	"tickets.mergedCount": "{{merged}}/{{total}} 병합됨",
	"tickets.merging": "병합하는 중…",
	"tickets.model": "모델",
	"tickets.needsRepo": "티켓에는 단일 저장소 프로젝트가 필요합니다.",
	"tickets.notFound": "티켓을 찾을 수 없습니다",
	"tickets.open": "열기",
	"tickets.openPlanningSession": "계획 세션 열기",
	"tickets.openSessionAria": "{{plan}}의 세션 열기",
	"tickets.plan.status.awaiting_merge": "병합 확인 대기",
	"tickets.plan.status.done": "완료",
	"tickets.plan.status.idle": "대기",
	"tickets.plan.status.in_review": "리뷰 중",
	"tickets.plan.status.merged": "병합됨",
	"tickets.plan.status.merging": "병합하는 중",
	"tickets.plan.status.needs_you": "확인 필요",
	"tickets.plan.status.reviewing": "리뷰 진행 중",
	"tickets.plan.status.terminated": "종료됨",
	"tickets.plan.status.todo": "할 일",
	"tickets.plan.status.working": "작업 중",
	"tickets.planDescription": "프로젝트 루트에서 계획 세션을 바로 시작합니다. 사양과 구현 계획을 티켓 폴더에 씁니다.",
	"tickets.planFailed": "계획 세션을 시작할 수 없습니다",
	"tickets.planWithAgent": "에이전트로 계획",
	"tickets.planningSession": "계획 세션",
	"tickets.plans": "계획",
	"tickets.plansAria": "{{title}}의 계획",
	"tickets.project": "프로젝트",
	"tickets.reopen": "다시 열기",
	"tickets.reopenAria": "티켓 {{title}} 다시 열기",
	"tickets.reopenFailed": "티켓을 다시 열 수 없습니다",
	"tickets.requestId": "요청 {{requestId}}",
	"tickets.review": "리뷰",
	"tickets.reviewDescription": "리뷰어가 사양과 계획에 따라 브랜치를 점검하고 문제를 고친 뒤 병합 준비가 되면 보고합니다.",
	"tickets.reviewFailed": "리뷰를 시작할 수 없습니다",
	"tickets.reviewTitle": "{{plan}} 리뷰",
	"tickets.reviewer": "리뷰어",
	"tickets.reviewer.new": "새 세션",
	"tickets.reviewer.planner": "계획 세션",
	"tickets.sessionMissing": "세션이 더 이상 존재하지 않습니다",
	"tickets.start": "시작",
	"tickets.starting": "시작하는 중…",
	"tickets.status.archived": "보관됨",
	"tickets.status.awaiting_merge": "확인을 기다리는 중",
	"tickets.status.done": "완료",
	"tickets.status.draft": "초안",
	"tickets.status.in_progress": "진행 중",
	"tickets.status.planning": "계획 중",
	"tickets.status.ready": "준비됨",
	"tickets.title": "제목",
	"tickets.titlePlaceholder": "무엇을 만들까요?",
	"tickets.unorderedPlan": "이 계획에는 NN- 접두사가 없어 번호가 붙은 계획 뒤에 실행됩니다.",
```

`es.json`:

```json
	"tickets.account": "Cuenta de Claude",
	"tickets.archive": "Archivar",
	"tickets.archiveAria": "Archivar el ticket {{title}}",
	"tickets.archiveFailed": "No se pudo archivar el ticket",
	"tickets.badgeAria": "Abrir el ticket {{label}}",
	"tickets.brief": "Resumen",
	"tickets.briefPlaceholder": "Un párrafo del que parte el agente de planificación",
	"tickets.column": "Planificado",
	"tickets.columnAria": "Tickets planificados",
	"tickets.columnCountAria": "{{count}} tickets abiertos",
	"tickets.create": "Nuevo ticket",
	"tickets.createDescription": "Un ticket es una carpeta del repositorio con una especificación y sus planes de implementación.",
	"tickets.createFailed": "No se pudo crear el ticket",
	"tickets.creating": "Creando…",
	"tickets.defaultsHint": "Los campos vacíos usan los valores predeterminados de tickets del proyecto.",
	"tickets.empty": "Todavía no hay tickets",
	"tickets.emptyHint": "Crea un ticket y luego planifícalo con un agente.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "Ese archivo no está en la carpeta del ticket.",
	"tickets.error.TICKET_MERGE_APPROVED": "Esta fusión ya fue aprobada.",
	"tickets.error.TICKET_NOT_FOUND": "El ticket ya no existe.",
	"tickets.error.TICKET_NOT_MERGE_READY": "El revisor no ha informado que este plan esté listo para fusionar.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "Ese plan no está en la carpeta del ticket.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "Asigna el plan a una sesión primero.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "Este ticket ya tiene una sesión de planificación en marcha.",
	"tickets.error.TICKET_REVIEWER_INVALID": "El revisor debe ser la sesión de planificación o una sesión nueva.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "Los tickets necesitan un proyecto de repositorio único.",
	"tickets.extra": "Instrucciones adicionales",
	"tickets.extraPlaceholder": "Notas opcionales añadidas al final del prompt",
	"tickets.fileLoadFailed": "No se pudo cargar el archivo",
	"tickets.fileModified": "Modificado {{time}}",
	"tickets.files": "Archivos",
	"tickets.filesAria": "Archivos del ticket",
	"tickets.frontmatter": "Metadatos",
	"tickets.harness": "Agente",
	"tickets.kickoff": "Prompt de arranque",
	"tickets.loadFailed": "No se pudieron cargar los tickets",
	"tickets.markDone": "Marcar como hecho",
	"tickets.markDoneFailed": "No se pudo marcar el plan como hecho",
	"tickets.merge": "Fusionar",
	"tickets.mergeDescription": "Indica al revisor que fusione la rama en la rama predeterminada ahora.",
	"tickets.mergeFailed": "No se pudo aprobar la fusión",
	"tickets.mergeTitle": "Fusionar {{plan}}",
	"tickets.mergedCount": "{{merged}}/{{total}} fusionados",
	"tickets.merging": "Fusionando…",
	"tickets.model": "Modelo",
	"tickets.needsRepo": "Los tickets necesitan un proyecto de repositorio único.",
	"tickets.notFound": "Ticket no encontrado",
	"tickets.open": "Abrir",
	"tickets.openPlanningSession": "Abrir la sesión de planificación",
	"tickets.openSessionAria": "Abrir la sesión de {{plan}}",
	"tickets.plan.status.awaiting_merge": "Esperando tu fusión",
	"tickets.plan.status.done": "Hecho",
	"tickets.plan.status.idle": "Inactivo",
	"tickets.plan.status.in_review": "En revisión",
	"tickets.plan.status.merged": "Fusionado",
	"tickets.plan.status.merging": "Fusionando",
	"tickets.plan.status.needs_you": "Te necesita",
	"tickets.plan.status.reviewing": "Revisando",
	"tickets.plan.status.terminated": "Terminado",
	"tickets.plan.status.todo": "Pendiente",
	"tickets.plan.status.working": "Trabajando",
	"tickets.planDescription": "Inicia la sesión de planificación en el directorio raíz del proyecto. Escribe la especificación y los planes de implementación en la carpeta del ticket.",
	"tickets.planFailed": "No se pudo iniciar la sesión de planificación",
	"tickets.planWithAgent": "Planificar con un agente",
	"tickets.planningSession": "Sesión de planificación",
	"tickets.plans": "Planes",
	"tickets.plansAria": "Planes de {{title}}",
	"tickets.project": "Proyecto",
	"tickets.reopen": "Reabrir",
	"tickets.reopenAria": "Reabrir el ticket {{title}}",
	"tickets.reopenFailed": "No se pudo reabrir el ticket",
	"tickets.requestId": "solicitud {{requestId}}",
	"tickets.review": "Revisar",
	"tickets.reviewDescription": "El revisor comprueba la rama contra la especificación y el plan, corrige lo que esté mal e informa cuando está lista para fusionar.",
	"tickets.reviewFailed": "No se pudo iniciar la revisión",
	"tickets.reviewTitle": "Revisar {{plan}}",
	"tickets.reviewer": "Revisor",
	"tickets.reviewer.new": "Sesión nueva",
	"tickets.reviewer.planner": "Sesión de planificación",
	"tickets.sessionMissing": "La sesión ya no existe",
	"tickets.start": "Iniciar",
	"tickets.starting": "Iniciando…",
	"tickets.status.archived": "Archivado",
	"tickets.status.awaiting_merge": "Esperando tu confirmación",
	"tickets.status.done": "Hecho",
	"tickets.status.draft": "Borrador",
	"tickets.status.in_progress": "En curso",
	"tickets.status.planning": "Planificando",
	"tickets.status.ready": "Listo",
	"tickets.title": "Título",
	"tickets.titlePlaceholder": "¿Qué vamos a construir?",
	"tickets.unorderedPlan": "Este plan no tiene prefijo NN- y se ejecuta después de los numerados.",
```

`fr.json`:

```json
	"tickets.account": "Compte Claude",
	"tickets.archive": "Archiver",
	"tickets.archiveAria": "Archiver le ticket {{title}}",
	"tickets.archiveFailed": "Impossible d'archiver le ticket",
	"tickets.badgeAria": "Ouvrir le ticket {{label}}",
	"tickets.brief": "Résumé",
	"tickets.briefPlaceholder": "Un paragraphe dont part l'agent de planification",
	"tickets.column": "Planifié",
	"tickets.columnAria": "Tickets planifiés",
	"tickets.columnCountAria": "{{count}} tickets ouverts",
	"tickets.create": "Nouveau ticket",
	"tickets.createDescription": "Un ticket est un dossier du dépôt contenant une spécification et ses plans d'implémentation.",
	"tickets.createFailed": "Impossible de créer le ticket",
	"tickets.creating": "Création…",
	"tickets.defaultsHint": "Les champs vides utilisent les valeurs par défaut des tickets du projet.",
	"tickets.empty": "Aucun ticket pour l'instant",
	"tickets.emptyHint": "Créez un ticket, puis planifiez-le avec un agent.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "Ce fichier n'est pas dans le dossier du ticket.",
	"tickets.error.TICKET_MERGE_APPROVED": "Cette fusion a déjà été approuvée.",
	"tickets.error.TICKET_NOT_FOUND": "Le ticket n'existe plus.",
	"tickets.error.TICKET_NOT_MERGE_READY": "Le relecteur n'a pas signalé ce plan comme prêt à fusionner.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "Ce plan n'est pas dans le dossier du ticket.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "Assignez d'abord le plan à une session.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "Ce ticket a déjà une session de planification en cours.",
	"tickets.error.TICKET_REVIEWER_INVALID": "Le relecteur doit être la session de planification ou une nouvelle session.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "Les tickets nécessitent un projet à dépôt unique.",
	"tickets.extra": "Instructions supplémentaires",
	"tickets.extraPlaceholder": "Notes facultatives ajoutées à la fin du prompt",
	"tickets.fileLoadFailed": "Impossible de charger le fichier",
	"tickets.fileModified": "Modifié {{time}}",
	"tickets.files": "Fichiers",
	"tickets.filesAria": "Fichiers du ticket",
	"tickets.frontmatter": "Métadonnées",
	"tickets.harness": "Agent",
	"tickets.kickoff": "Prompt de lancement",
	"tickets.loadFailed": "Impossible de charger les tickets",
	"tickets.markDone": "Marquer comme terminé",
	"tickets.markDoneFailed": "Impossible de marquer le plan comme terminé",
	"tickets.merge": "Fusionner",
	"tickets.mergeDescription": "Demande au relecteur de fusionner la branche dans la branche par défaut maintenant.",
	"tickets.mergeFailed": "Impossible d'approuver la fusion",
	"tickets.mergeTitle": "Fusionner {{plan}}",
	"tickets.mergedCount": "{{merged}}/{{total}} fusionnés",
	"tickets.merging": "Fusion…",
	"tickets.model": "Modèle",
	"tickets.needsRepo": "Les tickets nécessitent un projet à dépôt unique.",
	"tickets.notFound": "Ticket introuvable",
	"tickets.open": "Ouvrir",
	"tickets.openPlanningSession": "Ouvrir la session de planification",
	"tickets.openSessionAria": "Ouvrir la session de {{plan}}",
	"tickets.plan.status.awaiting_merge": "En attente de votre fusion",
	"tickets.plan.status.done": "Terminé",
	"tickets.plan.status.idle": "Inactif",
	"tickets.plan.status.in_review": "En relecture",
	"tickets.plan.status.merged": "Fusionné",
	"tickets.plan.status.merging": "Fusion en cours",
	"tickets.plan.status.needs_you": "Vous attend",
	"tickets.plan.status.reviewing": "Relecture en cours",
	"tickets.plan.status.terminated": "Arrêté",
	"tickets.plan.status.todo": "À faire",
	"tickets.plan.status.working": "En cours",
	"tickets.planDescription": "Démarre la session de planification sur place à la racine du projet. Elle écrit la spécification et les plans d'implémentation dans le dossier du ticket.",
	"tickets.planFailed": "Impossible de démarrer la session de planification",
	"tickets.planWithAgent": "Planifier avec un agent",
	"tickets.planningSession": "Session de planification",
	"tickets.plans": "Plans",
	"tickets.plansAria": "Plans de {{title}}",
	"tickets.project": "Projet",
	"tickets.reopen": "Rouvrir",
	"tickets.reopenAria": "Rouvrir le ticket {{title}}",
	"tickets.reopenFailed": "Impossible de rouvrir le ticket",
	"tickets.requestId": "requête {{requestId}}",
	"tickets.review": "Relire",
	"tickets.reviewDescription": "Le relecteur vérifie la branche par rapport à la spécification et au plan, corrige ce qui ne va pas et signale quand elle est prête à fusionner.",
	"tickets.reviewFailed": "Impossible de démarrer la relecture",
	"tickets.reviewTitle": "Relire {{plan}}",
	"tickets.reviewer": "Relecteur",
	"tickets.reviewer.new": "Nouvelle session",
	"tickets.reviewer.planner": "Session de planification",
	"tickets.sessionMissing": "La session n'existe plus",
	"tickets.start": "Démarrer",
	"tickets.starting": "Démarrage…",
	"tickets.status.archived": "Archivé",
	"tickets.status.awaiting_merge": "En attente de votre confirmation",
	"tickets.status.done": "Terminé",
	"tickets.status.draft": "Brouillon",
	"tickets.status.in_progress": "En cours",
	"tickets.status.planning": "Planification",
	"tickets.status.ready": "Prêt",
	"tickets.title": "Titre",
	"tickets.titlePlaceholder": "Que construisons-nous ?",
	"tickets.unorderedPlan": "Ce plan n'a pas de préfixe NN- et s'exécute après les plans numérotés.",
```

`de.json`:

```json
	"tickets.account": "Claude-Konto",
	"tickets.archive": "Archivieren",
	"tickets.archiveAria": "Ticket {{title}} archivieren",
	"tickets.archiveFailed": "Ticket konnte nicht archiviert werden",
	"tickets.badgeAria": "Ticket {{label}} öffnen",
	"tickets.brief": "Kurzbeschreibung",
	"tickets.briefPlaceholder": "Ein Absatz, mit dem der Planungsagent beginnt",
	"tickets.column": "Geplant",
	"tickets.columnAria": "Geplante Tickets",
	"tickets.columnCountAria": "{{count}} offene Tickets",
	"tickets.create": "Neues Ticket",
	"tickets.createDescription": "Ein Ticket ist ein Ordner im Repository mit einer Spezifikation und ihren Umsetzungsplänen.",
	"tickets.createFailed": "Ticket konnte nicht erstellt werden",
	"tickets.creating": "Wird erstellt…",
	"tickets.defaultsHint": "Leere Felder verwenden die Ticket-Standardwerte des Projekts.",
	"tickets.empty": "Noch keine Tickets",
	"tickets.emptyHint": "Erstelle ein Ticket und lass es dann von einem Agenten planen.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "Diese Datei liegt nicht im Ticket-Ordner.",
	"tickets.error.TICKET_MERGE_APPROVED": "Dieser Merge wurde bereits freigegeben.",
	"tickets.error.TICKET_NOT_FOUND": "Das Ticket existiert nicht mehr.",
	"tickets.error.TICKET_NOT_MERGE_READY": "Der Reviewer hat diesen Plan noch nicht als merge-bereit gemeldet.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "Dieser Plan liegt nicht im Ticket-Ordner.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "Weise den Plan zuerst einer Sitzung zu.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "Dieses Ticket hat bereits eine laufende Planungssitzung.",
	"tickets.error.TICKET_REVIEWER_INVALID": "Der Reviewer muss die Planungssitzung oder eine neue Sitzung sein.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "Tickets benötigen ein Projekt mit einem einzelnen Repository.",
	"tickets.extra": "Zusätzliche Anweisungen",
	"tickets.extraPlaceholder": "Optionale Notizen, die an den Prompt angehängt werden",
	"tickets.fileLoadFailed": "Datei konnte nicht geladen werden",
	"tickets.fileModified": "Geändert {{time}}",
	"tickets.files": "Dateien",
	"tickets.filesAria": "Ticket-Dateien",
	"tickets.frontmatter": "Frontmatter",
	"tickets.harness": "Agent",
	"tickets.kickoff": "Kickoff-Prompt",
	"tickets.loadFailed": "Tickets konnten nicht geladen werden",
	"tickets.markDone": "Als erledigt markieren",
	"tickets.markDoneFailed": "Plan konnte nicht als erledigt markiert werden",
	"tickets.merge": "Mergen",
	"tickets.mergeDescription": "Weist den Reviewer an, den Branch jetzt in den Standard-Branch zu mergen.",
	"tickets.mergeFailed": "Merge konnte nicht freigegeben werden",
	"tickets.mergeTitle": "{{plan}} mergen",
	"tickets.mergedCount": "{{merged}}/{{total}} gemergt",
	"tickets.merging": "Wird gemergt…",
	"tickets.model": "Modell",
	"tickets.needsRepo": "Tickets benötigen ein Projekt mit einem einzelnen Repository.",
	"tickets.notFound": "Ticket nicht gefunden",
	"tickets.open": "Öffnen",
	"tickets.openPlanningSession": "Planungssitzung öffnen",
	"tickets.openSessionAria": "Sitzung für {{plan}} öffnen",
	"tickets.plan.status.awaiting_merge": "Wartet auf deinen Merge",
	"tickets.plan.status.done": "Erledigt",
	"tickets.plan.status.idle": "Inaktiv",
	"tickets.plan.status.in_review": "In Review",
	"tickets.plan.status.merged": "Gemergt",
	"tickets.plan.status.merging": "Wird gemergt",
	"tickets.plan.status.needs_you": "Braucht dich",
	"tickets.plan.status.reviewing": "Review läuft",
	"tickets.plan.status.terminated": "Beendet",
	"tickets.plan.status.todo": "Offen",
	"tickets.plan.status.working": "In Arbeit",
	"tickets.planDescription": "Startet die Planungssitzung direkt im Projektstamm. Sie schreibt die Spezifikation und die Umsetzungspläne in den Ticket-Ordner.",
	"tickets.planFailed": "Planungssitzung konnte nicht gestartet werden",
	"tickets.planWithAgent": "Mit Agent planen",
	"tickets.planningSession": "Planungssitzung",
	"tickets.plans": "Pläne",
	"tickets.plansAria": "Pläne von {{title}}",
	"tickets.project": "Projekt",
	"tickets.reopen": "Wieder öffnen",
	"tickets.reopenAria": "Ticket {{title}} wieder öffnen",
	"tickets.reopenFailed": "Ticket konnte nicht wieder geöffnet werden",
	"tickets.requestId": "Anfrage {{requestId}}",
	"tickets.review": "Review",
	"tickets.reviewDescription": "Der Reviewer prüft den Branch gegen Spezifikation und Plan, behebt Fehler und meldet, wenn er merge-bereit ist.",
	"tickets.reviewFailed": "Review konnte nicht gestartet werden",
	"tickets.reviewTitle": "{{plan}} reviewen",
	"tickets.reviewer": "Reviewer",
	"tickets.reviewer.new": "Neue Sitzung",
	"tickets.reviewer.planner": "Planungssitzung",
	"tickets.sessionMissing": "Sitzung existiert nicht mehr",
	"tickets.start": "Starten",
	"tickets.starting": "Wird gestartet…",
	"tickets.status.archived": "Archiviert",
	"tickets.status.awaiting_merge": "Wartet auf deine Bestätigung",
	"tickets.status.done": "Erledigt",
	"tickets.status.draft": "Entwurf",
	"tickets.status.in_progress": "In Arbeit",
	"tickets.status.planning": "Planung",
	"tickets.status.ready": "Bereit",
	"tickets.title": "Titel",
	"tickets.titlePlaceholder": "Was bauen wir?",
	"tickets.unorderedPlan": "Dieser Plan hat kein NN-Präfix und läuft nach den nummerierten Plänen.",
```

`pt-BR.json`:

```json
	"tickets.account": "Conta Claude",
	"tickets.archive": "Arquivar",
	"tickets.archiveAria": "Arquivar o ticket {{title}}",
	"tickets.archiveFailed": "Não foi possível arquivar o ticket",
	"tickets.badgeAria": "Abrir o ticket {{label}}",
	"tickets.brief": "Resumo",
	"tickets.briefPlaceholder": "Um parágrafo de onde o agente de planejamento parte",
	"tickets.column": "Planejado",
	"tickets.columnAria": "Tickets planejados",
	"tickets.columnCountAria": "{{count}} tickets abertos",
	"tickets.create": "Novo ticket",
	"tickets.createDescription": "Um ticket é uma pasta no repositório com uma especificação e seus planos de implementação.",
	"tickets.createFailed": "Não foi possível criar o ticket",
	"tickets.creating": "Criando…",
	"tickets.defaultsHint": "Campos vazios usam os padrões de tickets do projeto.",
	"tickets.empty": "Nenhum ticket ainda",
	"tickets.emptyHint": "Crie um ticket e depois planeje com um agente.",
	"tickets.error.TICKET_FILE_NOT_FOUND": "Esse arquivo não está na pasta do ticket.",
	"tickets.error.TICKET_MERGE_APPROVED": "Este merge já foi aprovado.",
	"tickets.error.TICKET_NOT_FOUND": "O ticket não existe mais.",
	"tickets.error.TICKET_NOT_MERGE_READY": "O revisor ainda não informou que este plano está pronto para merge.",
	"tickets.error.TICKET_PLAN_NOT_FOUND": "Esse plano não está na pasta do ticket.",
	"tickets.error.TICKET_PLAN_UNASSIGNED": "Atribua o plano a uma sessão primeiro.",
	"tickets.error.TICKET_PLANNING_ACTIVE": "Este ticket já tem uma sessão de planejamento em execução.",
	"tickets.error.TICKET_REVIEWER_INVALID": "O revisor deve ser a sessão de planejamento ou uma nova sessão.",
	"tickets.error.TICKET_UNSUPPORTED_PROJECT": "Tickets precisam de um projeto de repositório único.",
	"tickets.extra": "Instruções extras",
	"tickets.extraPlaceholder": "Notas opcionais anexadas ao fim do prompt",
	"tickets.fileLoadFailed": "Não foi possível carregar o arquivo",
	"tickets.fileModified": "Modificado {{time}}",
	"tickets.files": "Arquivos",
	"tickets.filesAria": "Arquivos do ticket",
	"tickets.frontmatter": "Metadados",
	"tickets.harness": "Agente",
	"tickets.kickoff": "Prompt de início",
	"tickets.loadFailed": "Não foi possível carregar os tickets",
	"tickets.markDone": "Marcar como concluído",
	"tickets.markDoneFailed": "Não foi possível marcar o plano como concluído",
	"tickets.merge": "Fazer merge",
	"tickets.mergeDescription": "Diz ao revisor para fazer o merge do branch no branch padrão agora.",
	"tickets.mergeFailed": "Não foi possível aprovar o merge",
	"tickets.mergeTitle": "Merge de {{plan}}",
	"tickets.mergedCount": "{{merged}}/{{total}} com merge",
	"tickets.merging": "Fazendo merge…",
	"tickets.model": "Modelo",
	"tickets.needsRepo": "Tickets precisam de um projeto de repositório único.",
	"tickets.notFound": "Ticket não encontrado",
	"tickets.open": "Abrir",
	"tickets.openPlanningSession": "Abrir a sessão de planejamento",
	"tickets.openSessionAria": "Abrir a sessão de {{plan}}",
	"tickets.plan.status.awaiting_merge": "Aguardando seu merge",
	"tickets.plan.status.done": "Concluído",
	"tickets.plan.status.idle": "Ocioso",
	"tickets.plan.status.in_review": "Em revisão",
	"tickets.plan.status.merged": "Merge feito",
	"tickets.plan.status.merging": "Fazendo merge",
	"tickets.plan.status.needs_you": "Precisa de você",
	"tickets.plan.status.reviewing": "Revisando",
	"tickets.plan.status.terminated": "Encerrado",
	"tickets.plan.status.todo": "A fazer",
	"tickets.plan.status.working": "Trabalhando",
	"tickets.planDescription": "Inicia a sessão de planejamento no diretório raiz do projeto. Ela escreve a especificação e os planos de implementação na pasta do ticket.",
	"tickets.planFailed": "Não foi possível iniciar a sessão de planejamento",
	"tickets.planWithAgent": "Planejar com um agente",
	"tickets.planningSession": "Sessão de planejamento",
	"tickets.plans": "Planos",
	"tickets.plansAria": "Planos de {{title}}",
	"tickets.project": "Projeto",
	"tickets.reopen": "Reabrir",
	"tickets.reopenAria": "Reabrir o ticket {{title}}",
	"tickets.reopenFailed": "Não foi possível reabrir o ticket",
	"tickets.requestId": "requisição {{requestId}}",
	"tickets.review": "Revisar",
	"tickets.reviewDescription": "O revisor confere o branch contra a especificação e o plano, corrige o que estiver errado e informa quando estiver pronto para merge.",
	"tickets.reviewFailed": "Não foi possível iniciar a revisão",
	"tickets.reviewTitle": "Revisar {{plan}}",
	"tickets.reviewer": "Revisor",
	"tickets.reviewer.new": "Nova sessão",
	"tickets.reviewer.planner": "Sessão de planejamento",
	"tickets.sessionMissing": "A sessão não existe mais",
	"tickets.start": "Iniciar",
	"tickets.starting": "Iniciando…",
	"tickets.status.archived": "Arquivado",
	"tickets.status.awaiting_merge": "Aguardando sua confirmação",
	"tickets.status.done": "Concluído",
	"tickets.status.draft": "Rascunho",
	"tickets.status.in_progress": "Em andamento",
	"tickets.status.planning": "Planejando",
	"tickets.status.ready": "Pronto",
	"tickets.title": "Título",
	"tickets.titlePlaceholder": "O que vamos construir?",
	"tickets.unorderedPlan": "Este plano não tem prefixo NN- e roda depois dos numerados.",
```

- [ ] **Step 5: Run the i18n tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/i18n`
Expected: PASS, including `keeps interpolation variables aligned between locales` (every translation above keeps the same `{{...}}` names as English).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/i18n/en.json frontend/src/renderer/i18n/zh-CN.json frontend/src/renderer/i18n/ja.json frontend/src/renderer/i18n/ko.json frontend/src/renderer/i18n/es.json frontend/src/renderer/i18n/fr.json frontend/src/renderer/i18n/de.json frontend/src/renderer/i18n/pt-BR.json
git commit -m "feat(tickets): message catalogue for the planning tickets UI"
```

### Task 2: Ticket presentation module and API route templates

**Files:**
- Create: `frontend/src/renderer/lib/ticket-presentation.ts`
- Test: `frontend/src/renderer/lib/ticket-presentation.test.ts`
- Modify: `frontend/src/renderer/lib/api-client.ts:69-101`
- Test: `frontend/src/renderer/lib/api-client.test.ts:213-225`

**Interfaces:**
- Consumes: `components["schemas"]["TicketView" | "PlanView" | "SessionTicketRef"]` from `frontend/src/api/schema.ts`; `MessageKey`, `appI18n` from `../i18n`; the CSS tokens already used by `lib/session-presentation.ts:96-118`.
- Produces (used by every later task):
  - `type TicketView`, `type PlanView`, `type PlanStatus`, `type TicketStatus`, `type SessionTicketRef`, `type TicketWithProject = TicketView & { projectName: string }`
  - `getPlanStatusView(status: PlanStatus, t?: TFunction): PlanStatusView` where `PlanStatusView = { label: string; tone: string; className: string; dotClassName: string; breathe: boolean }`
  - `getTicketStatusView(ticket: TicketView, t?: TFunction): TicketStatusView` where `TicketStatusView = { label: string; tone: string; className: string; breathe: boolean }`
  - `isTicketInArchive(ticket: Pick<TicketView, "status">): boolean`
  - `planNumber(file: string): string`
  - `ticketBadgeLabel(ref: SessionTicketRef): string`
  - `splitFrontmatter(content: string): { fields: Array<[string, string]>; body: string }`
  - `ticketFileGroups(ticket: TicketView): { docs: string[]; plans: Array<{ plan: PlanView; kickoff?: string }> }`
  - `openTicketCount(tickets: readonly Pick<TicketView, "status">[]): number`
  - `PLAN_STATUS_MESSAGE_KEYS`, `TICKET_STATUS_MESSAGE_KEYS` (records used by tests and Task 2 keys)

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/lib/ticket-presentation.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	getPlanStatusView,
	getTicketStatusView,
	isTicketInArchive,
	openTicketCount,
	planNumber,
	splitFrontmatter,
	ticketBadgeLabel,
	ticketFileGroups,
	type PlanStatus,
	type PlanView,
	type TicketView,
} from "./ticket-presentation";

function plan(overrides: Partial<PlanView>): PlanView {
	return { file: "plans/01-daemon.md", order: 1, title: "Daemon", status: "todo", ...overrides };
}

function ticket(overrides: Partial<TicketView>): TicketView {
	return {
		projectId: "p1",
		slug: "planning-tickets",
		title: "Planning tickets",
		status: "draft",
		plans: [],
		files: ["ticket.md", "spec.md"],
		...overrides,
	};
}

const everyPlanStatus: PlanStatus[] = [
	"todo",
	"idle",
	"working",
	"needs_you",
	"in_review",
	"reviewing",
	"awaiting_merge",
	"merging",
	"merged",
	"done",
	"terminated",
];

describe("getPlanStatusView", () => {
	it("gives every daemon plan status a label and a colour token", () => {
		for (const status of everyPlanStatus) {
			const view = getPlanStatusView(status);
			expect(view.label, status).not.toBe("");
			expect(view.tone, status).toMatch(/^var\(--color-status-/);
			expect(view.className, status).toMatch(/^text-status-/);
		}
	});

	it("breathes only while an agent is actively doing something", () => {
		expect(getPlanStatusView("working").breathe).toBe(true);
		expect(getPlanStatusView("merging").breathe).toBe(true);
		expect(getPlanStatusView("reviewing").breathe).toBe(true);
		expect(getPlanStatusView("awaiting_merge").breathe).toBe(false);
		expect(getPlanStatusView("todo").breathe).toBe(false);
	});

	it("reads the awaiting merge status as the user's confirmation", () => {
		expect(getPlanStatusView("awaiting_merge").label).toBe("Awaiting your merge");
		expect(getPlanStatusView("awaiting_merge").tone).toBe("var(--color-status-ready)");
	});
});

describe("getTicketStatusView", () => {
	it("labels plain statuses", () => {
		expect(getTicketStatusView(ticket({ status: "draft" })).label).toBe("Draft");
		expect(getTicketStatusView(ticket({ status: "planning" })).label).toBe("Planning");
		expect(getTicketStatusView(ticket({ status: "ready" })).label).toBe("Ready");
		expect(getTicketStatusView(ticket({ status: "done" })).label).toBe("Done");
		expect(getTicketStatusView(ticket({ status: "archived" })).label).toBe("Archived");
	});

	it("counts merged plans while work is in progress", () => {
		const view = getTicketStatusView(
			ticket({
				status: "in_progress",
				plans: [
					plan({ status: "merged" }),
					plan({ file: "plans/02-board.md", order: 2, status: "done" }),
					plan({ file: "plans/03-assign.md", order: 3, status: "working" }),
					plan({ file: "plans/04-mobile.md", order: 4, status: "todo" }),
				],
			}),
		);
		expect(view.label).toBe("2/4 merged");
	});

	it("says in progress when nothing has merged yet", () => {
		const view = getTicketStatusView(ticket({ status: "in_progress", plans: [plan({ status: "working" })] }));
		expect(view.label).toBe("In progress");
		expect(view.breathe).toBe(true);
	});

	it("asks for confirmation when a plan awaits merge", () => {
		const view = getTicketStatusView(ticket({ status: "awaiting_merge", plans: [plan({ status: "awaiting_merge" })] }));
		expect(view.label).toBe("Waiting for your confirmation");
		expect(view.tone).toBe("var(--color-status-ready)");
	});
});

describe("helpers", () => {
	it("puts done and archived tickets in the archive", () => {
		expect(isTicketInArchive({ status: "done" })).toBe(true);
		expect(isTicketInArchive({ status: "archived" })).toBe(true);
		expect(isTicketInArchive({ status: "in_progress" })).toBe(false);
		expect(openTicketCount([{ status: "draft" }, { status: "done" }, { status: "archived" }, { status: "ready" }])).toBe(2);
	});

	it("extracts the plan number from the file name", () => {
		expect(planNumber("plans/01-daemon.md")).toBe("01");
		expect(planNumber("plans/12-mobile.kickoff.md")).toBe("12");
		expect(planNumber("plans/notes.md")).toBe("");
	});

	it("builds the session badge label", () => {
		expect(ticketBadgeLabel({ slug: "tickets", role: "planning" })).toBe("tickets · plan");
		expect(ticketBadgeLabel({ slug: "tickets", role: "implementing", planFile: "plans/02-board.md" })).toBe("tickets · 02");
		expect(ticketBadgeLabel({ slug: "tickets", role: "reviewing", planFile: "plans/02-board.md" })).toBe("tickets · 02");
		expect(ticketBadgeLabel({ slug: "tickets", role: "implementing", planFile: "plans/odd.md" })).toBe("tickets · odd.md");
	});

	it("splits YAML frontmatter from the body", () => {
		const parsed = splitFrontmatter('---\ntitle: "Daemon"\nstatus: ready\n---\n\n# Plan\n\nBody');
		expect(parsed.fields).toEqual([
			["title", "Daemon"],
			["status", "ready"],
		]);
		expect(parsed.body).toBe("# Plan\n\nBody");
	});

	it("leaves content without frontmatter alone", () => {
		expect(splitFrontmatter("# Just markdown\n")).toEqual({ fields: [], body: "# Just markdown\n" });
		expect(splitFrontmatter("---\nnot closed")).toEqual({ fields: [], body: "---\nnot closed" });
	});

	it("groups docs and plans with their kickoff files", () => {
		const groups = ticketFileGroups(
			ticket({
				files: ["ticket.md", "spec.md", "plans/01-daemon.md", "plans/01-daemon.kickoff.md", "plans/02-board.md"],
				plans: [plan({ kickoffFile: "plans/01-daemon.kickoff.md" }), plan({ file: "plans/02-board.md", order: 2, title: "Board" })],
			}),
		);
		expect(groups.docs).toEqual(["ticket.md", "spec.md"]);
		expect(groups.plans.map((entry) => [entry.plan.file, entry.kickoff])).toEqual([
			["plans/01-daemon.md", "plans/01-daemon.kickoff.md"],
			["plans/02-board.md", undefined],
		]);
	});
});
```

Add to `frontend/src/renderer/lib/api-client.test.ts`, after the `keeps workspace file routes aligned with the generated API schema` case (line 213-225):

```ts
	it("normalizes ticket slugs and plan files, which are user-chosen strings", () => {
		expect(normalizeApiOperation("GET", "/api/v1/projects/my-app/tickets")).toBe("GET /api/v1/projects/:id/tickets");
		expect(normalizeApiOperation("GET", "/api/v1/projects/my-app/tickets/planning-tickets")).toBe(
			"GET /api/v1/projects/:id/tickets/:id",
		);
		expect(normalizeApiOperation("GET", "/api/v1/projects/my-app/tickets/events")).toBe(
			"GET /api/v1/projects/:id/tickets/events",
		);
		expect(normalizeApiOperation("GET", "/api/v1/projects/my-app/tickets/planning-tickets/file")).toBe(
			"GET /api/v1/projects/:id/tickets/:id/file",
		);
		expect(normalizeApiOperation("POST", "/api/v1/projects/my-app/tickets/planning-tickets/plans/01-daemon.md/merge")).toBe(
			"POST /api/v1/projects/:id/tickets/:id/plans/:id/merge",
		);
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-presentation.test.ts src/renderer/lib/api-client.test.ts`
Expected: FAIL. `ticket-presentation.test.ts` cannot resolve `./ticket-presentation`; the api-client case fails on `"GET /api/v1/projects/:id/tickets/planning-tickets"` (the fallback in `api-client.ts:141-150` only normalizes the segment after `projects`).

- [ ] **Step 3: Write the presentation module**

`frontend/src/renderer/lib/ticket-presentation.ts`:

```ts
import type { TFunction } from "i18next";
import type { components } from "../../api/schema";
import { appI18n, type MessageKey } from "../i18n";

export type TicketView = components["schemas"]["TicketView"];
export type PlanView = components["schemas"]["PlanView"];
export type PlanStatus = PlanView["status"];
export type TicketStatus = TicketView["status"];
export type SessionTicketRef = components["schemas"]["SessionTicketRef"];
export type TicketWithProject = TicketView & { projectName: string };

export type PlanStatusView = {
	label: string;
	tone: string;
	className: string;
	dotClassName: string;
	breathe: boolean;
};

export type TicketStatusView = {
	label: string;
	tone: string;
	className: string;
	breathe: boolean;
};

type Tone = { tone: string; className: string; dotClassName: string };

const tones = {
	unknown: { tone: "var(--color-status-unknown)", className: "text-status-unknown", dotClassName: "bg-status-unknown" },
	idle: { tone: "var(--color-status-idle)", className: "text-status-idle", dotClassName: "bg-status-idle" },
	working: { tone: "var(--color-status-working)", className: "text-status-working", dotClassName: "bg-status-working" },
	needsYou: {
		tone: "var(--color-status-needs-you)",
		className: "text-status-needs-you",
		dotClassName: "bg-status-needs-you",
	},
	inReview: {
		tone: "var(--color-status-in-review)",
		className: "text-status-in-review",
		dotClassName: "bg-status-in-review",
	},
	ready: { tone: "var(--color-status-ready)", className: "text-status-ready", dotClassName: "bg-status-ready" },
	merged: { tone: "var(--color-status-merged)", className: "text-status-merged", dotClassName: "bg-status-merged" },
	terminated: {
		tone: "var(--color-status-terminated)",
		className: "text-status-terminated-foreground",
		dotClassName: "bg-status-terminated",
	},
} satisfies Record<string, Tone>;

export const PLAN_STATUS_MESSAGE_KEYS: Record<PlanStatus, MessageKey> = {
	todo: "tickets.plan.status.todo",
	idle: "tickets.plan.status.idle",
	working: "tickets.plan.status.working",
	needs_you: "tickets.plan.status.needs_you",
	in_review: "tickets.plan.status.in_review",
	reviewing: "tickets.plan.status.reviewing",
	awaiting_merge: "tickets.plan.status.awaiting_merge",
	merging: "tickets.plan.status.merging",
	merged: "tickets.plan.status.merged",
	done: "tickets.plan.status.done",
	terminated: "tickets.plan.status.terminated",
};

const planStatusBases: Record<PlanStatus, Tone & { breathe: boolean }> = {
	todo: { ...tones.unknown, breathe: false },
	idle: { ...tones.idle, breathe: false },
	working: { ...tones.working, breathe: true },
	needs_you: { ...tones.needsYou, breathe: false },
	in_review: { ...tones.inReview, breathe: false },
	reviewing: { ...tones.inReview, breathe: true },
	awaiting_merge: { ...tones.ready, breathe: false },
	merging: { ...tones.ready, breathe: true },
	merged: { ...tones.merged, breathe: false },
	done: { ...tones.merged, breathe: false },
	terminated: { ...tones.terminated, breathe: false },
};

export function getPlanStatusView(status: PlanStatus, t: TFunction = appI18n.t): PlanStatusView {
	const base = planStatusBases[status] ?? planStatusBases.todo;
	const key = PLAN_STATUS_MESSAGE_KEYS[status] ?? PLAN_STATUS_MESSAGE_KEYS.todo;
	return { ...base, label: t(key) };
}

export const TICKET_STATUS_MESSAGE_KEYS: Record<TicketStatus, MessageKey> = {
	draft: "tickets.status.draft",
	planning: "tickets.status.planning",
	ready: "tickets.status.ready",
	in_progress: "tickets.status.in_progress",
	awaiting_merge: "tickets.status.awaiting_merge",
	done: "tickets.status.done",
	archived: "tickets.status.archived",
};

const ticketStatusBases: Record<TicketStatus, Tone & { breathe: boolean }> = {
	draft: { ...tones.unknown, breathe: false },
	planning: { ...tones.working, breathe: true },
	ready: { ...tones.idle, breathe: false },
	in_progress: { ...tones.working, breathe: true },
	awaiting_merge: { ...tones.ready, breathe: false },
	done: { ...tones.merged, breathe: false },
	archived: { ...tones.terminated, breathe: false },
};

const mergedPlanStatuses = new Set<PlanStatus>(["merged", "done"]);

export function getTicketStatusView(ticket: TicketView, t: TFunction = appI18n.t): TicketStatusView {
	const base = ticketStatusBases[ticket.status] ?? ticketStatusBases.draft;
	const merged = ticket.plans.filter((plan) => mergedPlanStatuses.has(plan.status)).length;
	if (ticket.status === "in_progress" && merged > 0) {
		return { ...base, label: t("tickets.mergedCount", { merged, total: ticket.plans.length }) };
	}
	return { ...base, label: t(TICKET_STATUS_MESSAGE_KEYS[ticket.status] ?? TICKET_STATUS_MESSAGE_KEYS.draft) };
}

const archiveStatuses = new Set<TicketStatus>(["done", "archived"]);

export function isTicketInArchive(ticket: Pick<TicketView, "status">): boolean {
	return archiveStatuses.has(ticket.status);
}

export function openTicketCount(tickets: readonly Pick<TicketView, "status">[]): number {
	return tickets.filter((ticket) => !isTicketInArchive(ticket)).length;
}

export function planNumber(file: string): string {
	const match = /(?:^|\/)(\d+)-[^/]*$/.exec(file);
	return match?.[1] ?? "";
}

export function ticketBadgeLabel(ref: SessionTicketRef): string {
	if (ref.role === "planning" || !ref.planFile) return `${ref.slug} · plan`;
	const number = planNumber(ref.planFile);
	return `${ref.slug} · ${number || ref.planFile.split("/").pop() || ref.planFile}`;
}

export function splitFrontmatter(content: string): { fields: Array<[string, string]>; body: string } {
	if (!content.startsWith("---\n")) return { fields: [], body: content };
	const end = content.indexOf("\n---", 4);
	if (end === -1) return { fields: [], body: content };
	const header = content.slice(4, end);
	const rest = content.slice(end + 4);
	const fields: Array<[string, string]> = [];
	for (const line of header.split("\n")) {
		const colon = line.indexOf(":");
		if (colon === -1) continue;
		const key = line.slice(0, colon).trim();
		let value = line.slice(colon + 1).trim();
		if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
			try {
				value = JSON.parse(value) as string;
			} catch {
				value = value.slice(1, -1);
			}
		}
		if (key) fields.push([key, value]);
	}
	return { fields, body: rest.replace(/^\n+/, "") };
}

export function ticketFileGroups(ticket: TicketView): { docs: string[]; plans: Array<{ plan: PlanView; kickoff?: string }> } {
	const planFiles = new Set(ticket.plans.flatMap((plan) => [plan.file, plan.kickoffFile ?? ""]));
	const docs = ticket.files.filter((file) => !planFiles.has(file) && !file.startsWith("plans/"));
	const plans = [...ticket.plans]
		.sort((left, right) => left.order - right.order || left.file.localeCompare(right.file))
		.map((plan) => ({ plan, kickoff: plan.kickoffFile || undefined }));
	return { docs, plans };
}
```

Every `tickets.*` key used here was added in Task 1, so `npm run typecheck` accepts the `MessageKey` literals.

- [ ] **Step 4: Add the ticket templates to `ROUTE_TEMPLATES`**

In `frontend/src/renderer/lib/api-client.ts`, after the line `"/api/v1/projects/{id}/config",` (line 78), insert:

```ts
	"/api/v1/projects/{id}/tickets",
	"/api/v1/projects/{id}/tickets/events",
	"/api/v1/projects/{id}/tickets/{slug}",
	"/api/v1/projects/{id}/tickets/{slug}/archive",
	"/api/v1/projects/{id}/tickets/{slug}/file",
	"/api/v1/projects/{id}/tickets/{slug}/plan",
	"/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign",
	"/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done",
	"/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge",
	"/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge-ready",
	"/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review",
	"/api/v1/projects/{id}/tickets/{slug}/unarchive",
```

`matchRouteTemplate` (`api-client.ts:118-139`) scores literal segments, so `/tickets/events` beats `/tickets/{slug}` for the events path, as the test expects.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-presentation.test.ts src/renderer/lib/api-client.test.ts`
Expected: PASS. The label assertions pass because vitest loads the real `en.json` through `appI18n` (`src/renderer/i18n/index.ts`).

- [ ] **Step 6: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/lib/ticket-presentation.ts frontend/src/renderer/lib/ticket-presentation.test.ts frontend/src/renderer/lib/api-client.ts frontend/src/renderer/lib/api-client.test.ts
git commit -m "feat(tickets): plan and ticket status presentation, ticket route templates"
```

### Task 3: Ticket queries, live updates and mutations

**Files:**
- Create: `frontend/src/renderer/lib/ticket-events.ts`
- Test: `frontend/src/renderer/lib/ticket-events.test.ts`
- Create: `frontend/src/renderer/hooks/useTicketsQuery.ts`
- Create: `frontend/src/renderer/hooks/useTicketMutations.ts`
- Test: `frontend/src/renderer/hooks/useTicketMutations.test.ts`
- Modify: `frontend/src/renderer/lib/event-transport.ts:39-46`
- Test: `frontend/src/renderer/lib/event-transport.test.ts:127-141`

**Interfaces:**
- Consumes: `apiClient`, `apiErrorCode`, `apiErrorRequestId`, `apiErrorMessage`, `getApiBaseUrl`, `hasTrustedApiBaseUrl`, `subscribeApiBaseUrl` from `lib/api-client.ts`; `workspaceQueryKey` from `hooks/useWorkspaceQuery.ts:31`; types from Task 2.
- Produces:
  - `subscribeTicketChanges(projectId: string, queryClient: QueryClient): () => void` — ref-counted `EventSource` on `GET /api/v1/projects/{id}/tickets/events`, invalidates `["tickets", projectId]` on `tickets_changed` and on open, retries after 5 s when closed.
  - `ticketsQueryRoot = ["tickets"]`, `ticketsQueryKey(projectId)`, `ticketQueryKey(projectId, slug)`, `ticketFileQueryKey(projectId, slug, path)`
  - `type TicketProject = { id: string; name: string }`, `type TicketFile = components["schemas"]["TicketFileResponse"]`
  - `useTicketsQuery(projects: readonly TicketProject[]): { tickets: TicketWithProject[]; isError: boolean; isSuccess: boolean }` — one query per project, live-subscribed while mounted.
  - `useTicketQuery(projectId: string, slug: string): UseQueryResult<TicketView>` — live-subscribed while mounted.
  - `useTicketFileQuery(projectId: string, slug: string, path: string | undefined): UseQueryResult<TicketFile>`
  - `type TicketRoleInput = { harness?: string; model?: string; claudeAccountId?: string; extra?: string }`
  - `type TicketRef = { projectId: string; slug: string }`, `type PlanRef = TicketRef & { plan: string }`
  - `useTicketMutations()` returning `{ createTicket, planTicket, reviewPlan, approveMerge, markPlanDone, setArchived }` with the variable types below.
  - `ticketErrorMessage(error: unknown, t: TFunction, fallbackKey: MessageKey): string` — known `TICKET_*` codes map to `tickets.error.<CODE>`, others fall back to the envelope message, and a `requestId` is appended as ` · request <id>`.

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/lib/ticket-events.test.ts`:

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { getApiBaseUrlMock, hasTrustedApiBaseUrlMock, subscribeApiBaseUrlMock, unsubscribeBaseUrlMock } = vi.hoisted(
	() => ({
		getApiBaseUrlMock: vi.fn(() => "http://127.0.0.1:3001"),
		hasTrustedApiBaseUrlMock: vi.fn(() => true),
		subscribeApiBaseUrlMock: vi.fn(),
		unsubscribeBaseUrlMock: vi.fn(),
	}),
);

vi.mock("./api-client", () => ({
	getApiBaseUrl: getApiBaseUrlMock,
	hasTrustedApiBaseUrl: hasTrustedApiBaseUrlMock,
	subscribeApiBaseUrl: subscribeApiBaseUrlMock,
}));

import { subscribeTicketChanges } from "./ticket-events";

class EventSourceStub {
	static instances: EventSourceStub[] = [];
	url: string;
	closed = false;
	readyState = 0;
	onopen: (() => void) | null = null;
	onerror: (() => void) | null = null;
	listeners = new Map<string, Set<() => void>>();

	constructor(url: string) {
		this.url = url;
		EventSourceStub.instances.push(this);
	}

	addEventListener(type: string, listener: () => void) {
		const listeners = this.listeners.get(type) ?? new Set();
		listeners.add(listener);
		this.listeners.set(type, listeners);
	}

	dispatch(type: string) {
		for (const listener of this.listeners.get(type) ?? []) listener();
	}

	close() {
		this.closed = true;
		this.readyState = 2;
	}
}

function fakeQueryClient() {
	return { invalidateQueries: vi.fn() } as unknown as Parameters<typeof subscribeTicketChanges>[1];
}

beforeEach(() => {
	EventSourceStub.instances = [];
	getApiBaseUrlMock.mockReset().mockReturnValue("http://127.0.0.1:3001");
	hasTrustedApiBaseUrlMock.mockReset().mockReturnValue(true);
	subscribeApiBaseUrlMock.mockReset().mockReturnValue(unsubscribeBaseUrlMock);
	unsubscribeBaseUrlMock.mockReset();
	(globalThis as unknown as { EventSource: unknown }).EventSource = EventSourceStub;
	vi.useFakeTimers();
});

afterEach(() => {
	vi.useRealTimers();
});

describe("subscribeTicketChanges", () => {
	it("opens the project's ticket stream and invalidates the ticket queries on change", () => {
		const queryClient = fakeQueryClient();
		const unsubscribe = subscribeTicketChanges("my app", queryClient);
		expect(EventSourceStub.instances).toHaveLength(1);
		expect(EventSourceStub.instances[0].url).toBe("http://127.0.0.1:3001/api/v1/projects/my%20app/tickets/events");

		EventSourceStub.instances[0].dispatch("tickets_changed");
		vi.advanceTimersByTime(200);
		expect(queryClient.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["tickets", "my app"] });

		unsubscribe();
		expect(EventSourceStub.instances[0].closed).toBe(true);
		expect(unsubscribeBaseUrlMock).toHaveBeenCalledTimes(1);
	});

	it("shares one stream per project across subscribers", () => {
		const queryClient = fakeQueryClient();
		const first = subscribeTicketChanges("p1", queryClient);
		const second = subscribeTicketChanges("p1", queryClient);
		expect(EventSourceStub.instances).toHaveLength(1);
		first();
		expect(EventSourceStub.instances[0].closed).toBe(false);
		second();
		expect(EventSourceStub.instances[0].closed).toBe(true);
	});

	it("reconnects after the stream closes", () => {
		const queryClient = fakeQueryClient();
		const unsubscribe = subscribeTicketChanges("p1", queryClient);
		const source = EventSourceStub.instances[0];
		source.readyState = 2;
		source.onerror?.();
		vi.advanceTimersByTime(5_000);
		expect(EventSourceStub.instances).toHaveLength(2);
		unsubscribe();
	});

	it("does nothing while the daemon base URL is untrusted", () => {
		hasTrustedApiBaseUrlMock.mockReturnValue(false);
		const unsubscribe = subscribeTicketChanges("p1", fakeQueryClient());
		expect(EventSourceStub.instances).toHaveLength(0);
		unsubscribe();
	});
});
```

`frontend/src/renderer/hooks/useTicketMutations.test.ts`:

```ts
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { appI18n } from "../i18n";

const { postMock } = vi.hoisted(() => ({ postMock: vi.fn() }));

vi.mock("../lib/api-client", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../lib/api-client")>();
	return { ...actual, apiClient: { POST: (...args: unknown[]) => postMock(...args), GET: vi.fn() } };
});

import { ticketErrorMessage, useTicketMutations } from "./useTicketMutations";

function wrapper(queryClient: QueryClient) {
	return ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
	);
}

beforeEach(() => {
	postMock.mockReset();
});

describe("useTicketMutations", () => {
	it("creates a ticket and invalidates the ticket and workspace queries", async () => {
		const queryClient = new QueryClient();
		const invalidate = vi.spyOn(queryClient, "invalidateQueries");
		postMock.mockResolvedValue({
			data: { ticket: { projectId: "p1", slug: "new-thing", title: "New thing", status: "draft", plans: [], files: [] }, warnings: [] },
		});
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const created = await act(() =>
			result.current.createTicket.mutateAsync({ projectId: "p1", title: "New thing", brief: "Because" }),
		);

		expect(created.ticket.slug).toBe("new-thing");
		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets", {
			params: { path: { id: "p1" } },
			body: { title: "New thing", brief: "Because" },
		});
		await waitFor(() => expect(invalidate).toHaveBeenCalledWith({ queryKey: ["tickets"] }));
		expect(invalidate).toHaveBeenCalledWith({ queryKey: ["workspaces"] });
	});

	it("sends the reviewer choice and role fields to the review route", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({ data: { session: { id: "s-9", projectId: "p1" }, spawned: true } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await act(() =>
			result.current.reviewPlan.mutateAsync({
				projectId: "p1",
				slug: "t",
				plan: "plans/01-daemon.md",
				reviewer: "new",
				harness: "claude-code",
				model: "claude-opus-5",
				claudeAccountId: "",
				extra: "",
			}),
		);

		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", {
			params: { path: { id: "p1", slug: "t", plan: "plans/01-daemon.md" } },
			body: { reviewer: "new", harness: "claude-code", model: "claude-opus-5", claudeAccountId: undefined, extra: undefined },
		});
	});

	it("rejects with the daemon envelope so callers can branch on the code", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({
			error: { error: "conflict", code: "TICKET_NOT_MERGE_READY", message: "not ready", requestId: "req-1" },
		});
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await expect(
			act(() => result.current.approveMerge.mutateAsync({ projectId: "p1", slug: "t", plan: "plans/01-daemon.md" })),
		).rejects.toMatchObject({ code: "TICKET_NOT_MERGE_READY" });
	});
});

describe("ticketErrorMessage", () => {
	it("maps known codes to copy and keeps the request id", () => {
		const message = ticketErrorMessage(
			{ error: "conflict", code: "TICKET_MERGE_APPROVED", message: "already", requestId: "req-7" },
			appI18n.t,
			"tickets.mergeFailed",
		);
		expect(message).toBe("This merge was already approved. · request req-7");
	});

	it("falls back to the envelope message for unknown codes", () => {
		const message = ticketErrorMessage(
			{ error: "internal", code: "SOMETHING_ELSE", message: "boom", requestId: "req-8" },
			appI18n.t,
			"tickets.mergeFailed",
		);
		expect(message).toBe("boom (SOMETHING_ELSE) · request req-8");
	});

	it("uses the fallback copy when there is no envelope", () => {
		expect(ticketErrorMessage(undefined, appI18n.t, "tickets.mergeFailed")).toBe("Could not approve the merge");
	});
});
```

Rename the file to `useTicketMutations.test.tsx` (it contains JSX). Add to `frontend/src/renderer/lib/event-transport.test.ts` inside the `debounces workspace and SCM summary invalidation after a status change` case, after the `["session-usage"]` assertion at line 139:

```ts
			expect(queryClient.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["tickets"] });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-events.test.ts src/renderer/hooks/useTicketMutations.test.tsx src/renderer/lib/event-transport.test.ts`
Expected: FAIL. The first two cannot resolve their modules; the event-transport case fails on the `["tickets"]` assertion.

- [ ] **Step 3: Write the SSE subscription**

`frontend/src/renderer/lib/ticket-events.ts`:

```ts
import type { QueryClient } from "@tanstack/react-query";
import { getApiBaseUrl, hasTrustedApiBaseUrl, subscribeApiBaseUrl } from "./api-client";

const INVALIDATE_DEBOUNCE_MS = 150;
const SSE_RETRY_MS = 5_000;
const EVENTSOURCE_CLOSED = 2;

type TicketStream = {
	refs: number;
	disposed: boolean;
	source?: EventSource;
	sourceBaseUrl?: string;
	debounce?: ReturnType<typeof setTimeout>;
	retry?: ReturnType<typeof setTimeout>;
	disconnectBaseUrl: () => void;
	connect: () => void;
	dispose: () => void;
};

const streams = new Map<string, TicketStream>();

export function subscribeTicketChanges(projectId: string, queryClient: QueryClient): () => void {
	let stream = streams.get(projectId);
	if (!stream) {
		stream = createTicketStream(projectId, queryClient);
		streams.set(projectId, stream);
	}
	stream.refs += 1;
	return () => {
		const current = streams.get(projectId);
		if (!current) return;
		current.refs -= 1;
		if (current.refs > 0) return;
		current.dispose();
		streams.delete(projectId);
	};
}

function createTicketStream(projectId: string, queryClient: QueryClient): TicketStream {
	const stream = {} as TicketStream;
	const invalidate = () => {
		if (stream.debounce) clearTimeout(stream.debounce);
		stream.debounce = setTimeout(() => {
			void queryClient.invalidateQueries({ queryKey: ["tickets", projectId] });
		}, INVALIDATE_DEBOUNCE_MS);
	};
	const scheduleRetry = () => {
		if (stream.disposed || stream.retry) return;
		stream.retry = setTimeout(() => {
			stream.retry = undefined;
			stream.connect();
		}, SSE_RETRY_MS);
	};
	stream.refs = 0;
	stream.disposed = false;
	stream.connect = () => {
		if (stream.disposed || typeof EventSource === "undefined") return;
		if (!hasTrustedApiBaseUrl()) {
			stream.source?.close();
			stream.source = undefined;
			stream.sourceBaseUrl = undefined;
			return;
		}
		const baseUrl = getApiBaseUrl();
		if (stream.source && stream.sourceBaseUrl === baseUrl && stream.source.readyState !== EVENTSOURCE_CLOSED) return;
		stream.source?.close();
		stream.sourceBaseUrl = baseUrl;
		try {
			const source = new EventSource(
				`${baseUrl.replace(/\/+$/, "")}/api/v1/projects/${encodeURIComponent(projectId)}/tickets/events`,
			);
			stream.source = source;
			source.onopen = () => {
				if (!stream.disposed && stream.source === source) invalidate();
			};
			source.onerror = () => {
				if (!stream.disposed && stream.source === source && source.readyState === EVENTSOURCE_CLOSED) scheduleRetry();
			};
			source.addEventListener("tickets_changed", () => {
				if (!stream.disposed && stream.source === source) invalidate();
			});
		} catch {
			stream.source = undefined;
			scheduleRetry();
		}
	};
	stream.disconnectBaseUrl = subscribeApiBaseUrl(stream.connect);
	stream.dispose = () => {
		stream.disposed = true;
		if (stream.debounce) clearTimeout(stream.debounce);
		if (stream.retry) clearTimeout(stream.retry);
		stream.disconnectBaseUrl();
		stream.source?.close();
	};
	stream.connect();
	return stream;
}
```

- [ ] **Step 4: Write the queries**

`frontend/src/renderer/hooks/useTicketsQuery.ts`:

```ts
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import type { components } from "../../api/schema";
import { apiClient } from "../lib/api-client";
import { subscribeTicketChanges } from "../lib/ticket-events";
import type { TicketView, TicketWithProject } from "../lib/ticket-presentation";

export type TicketFile = components["schemas"]["TicketFileResponse"];
export type TicketProject = { id: string; name: string };

export const ticketsQueryRoot = ["tickets"] as const;
export const ticketsQueryKey = (projectId: string) => [...ticketsQueryRoot, projectId] as const;
export const ticketQueryKey = (projectId: string, slug: string) => [...ticketsQueryRoot, projectId, slug] as const;
export const ticketFileQueryKey = (projectId: string, slug: string, path: string) =>
	[...ticketsQueryRoot, projectId, slug, "file", path] as const;

const TICKETS_REFETCH_MS = 30_000;

async function fetchTickets(projectId: string): Promise<TicketView[]> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets", {
		params: { path: { id: projectId } },
	});
	if (error) throw error;
	return data?.tickets ?? [];
}

async function fetchTicket(projectId: string, slug: string): Promise<TicketView> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets/{slug}", {
		params: { path: { id: projectId, slug } },
	});
	if (error || !data) throw error ?? new Error("Ticket response was empty");
	return data.ticket;
}

async function fetchTicketFile(projectId: string, slug: string, path: string): Promise<TicketFile> {
	const { data, error } = await apiClient.GET("/api/v1/projects/{id}/tickets/{slug}/file", {
		params: { path: { id: projectId, slug }, query: { path } },
	});
	if (error || !data) throw error ?? new Error("Ticket file response was empty");
	return data;
}

function useTicketChangeSubscription(projectIds: readonly string[]): void {
	const queryClient = useQueryClient();
	const idsKey = projectIds.join("\n");
	useEffect(() => {
		const unsubscribes = idsKey
			.split("\n")
			.filter((id) => id !== "")
			.map((id) => subscribeTicketChanges(id, queryClient));
		return () => {
			for (const unsubscribe of unsubscribes) unsubscribe();
		};
	}, [idsKey, queryClient]);
}

export function useTicketsQuery(projects: readonly TicketProject[]): {
	tickets: TicketWithProject[];
	isError: boolean;
	isSuccess: boolean;
} {
	useTicketChangeSubscription(projects.map((project) => project.id));
	const results = useQueries({
		queries: projects.map((project) => ({
			queryKey: ticketsQueryKey(project.id),
			queryFn: () => fetchTickets(project.id),
			retry: 1,
			refetchInterval: TICKETS_REFETCH_MS,
		})),
	});
	const tickets = results.flatMap((result, index) =>
		(result.data ?? []).map((ticket) => ({ ...ticket, projectName: projects[index]?.name ?? "" })),
	);
	return {
		tickets,
		isError: results.some((result) => result.isError),
		isSuccess: results.every((result) => result.isSuccess),
	};
}

export function useTicketQuery(projectId: string, slug: string) {
	useTicketChangeSubscription([projectId]);
	return useQuery({
		queryKey: ticketQueryKey(projectId, slug),
		queryFn: () => fetchTicket(projectId, slug),
		retry: 1,
		refetchInterval: TICKETS_REFETCH_MS,
	});
}

export function useTicketFileQuery(projectId: string, slug: string, path: string | undefined) {
	return useQuery({
		queryKey: ticketFileQueryKey(projectId, slug, path ?? ""),
		queryFn: () => fetchTicketFile(projectId, slug, path ?? ""),
		enabled: path !== undefined && path !== "",
		retry: 1,
	});
}
```

`ticket-events.ts` invalidates `["tickets", projectId]`; because every ticket, list and file key starts with that prefix, one invalidation refreshes the board column, the ticket page and the previewed file.

- [ ] **Step 5: Write the mutations**

`frontend/src/renderer/hooks/useTicketMutations.ts`:

```ts
import { useMutation, useQueryClient, type QueryClient } from "@tanstack/react-query";
import type { TFunction } from "i18next";
import type { components } from "../../api/schema";
import type { MessageKey } from "../i18n";
import { apiClient, apiErrorCode, apiErrorMessage, apiErrorRequestId } from "../lib/api-client";
import { ticketsQueryRoot } from "./useTicketsQuery";
import { workspaceQueryKey } from "./useWorkspaceQuery";

type SessionView = components["schemas"]["ControllersSessionView"];
type TicketView = components["schemas"]["TicketView"];
type CreateTicketResponse = components["schemas"]["CreateTicketResponse"];
type ReviewPlanResponse = components["schemas"]["ReviewPlanResponse"];

export type TicketRef = { projectId: string; slug: string };
export type PlanRef = TicketRef & { plan: string };
export type TicketRoleInput = { harness?: string; model?: string; claudeAccountId?: string; extra?: string };
export type CreateTicketInput = { projectId: string; title: string; brief: string };
export type PlanTicketInput = TicketRef & TicketRoleInput;
export type ReviewPlanInput = PlanRef & TicketRoleInput & { reviewer: "planner" | "new" };
export type SetArchivedInput = TicketRef & { archived: boolean };

const ticketErrorKeys: Record<string, MessageKey> = {
	TICKET_FILE_NOT_FOUND: "tickets.error.TICKET_FILE_NOT_FOUND",
	TICKET_MERGE_APPROVED: "tickets.error.TICKET_MERGE_APPROVED",
	TICKET_NOT_FOUND: "tickets.error.TICKET_NOT_FOUND",
	TICKET_NOT_MERGE_READY: "tickets.error.TICKET_NOT_MERGE_READY",
	TICKET_PLAN_NOT_FOUND: "tickets.error.TICKET_PLAN_NOT_FOUND",
	TICKET_PLAN_UNASSIGNED: "tickets.error.TICKET_PLAN_UNASSIGNED",
	TICKET_PLANNING_ACTIVE: "tickets.error.TICKET_PLANNING_ACTIVE",
	TICKET_REVIEWER_INVALID: "tickets.error.TICKET_REVIEWER_INVALID",
	TICKET_UNSUPPORTED_PROJECT: "tickets.error.TICKET_UNSUPPORTED_PROJECT",
};

export function ticketErrorMessage(error: unknown, t: TFunction, fallbackKey: MessageKey): string {
	const code = apiErrorCode(error);
	const known = code ? ticketErrorKeys[code] : undefined;
	const message = known ? t(known) : apiErrorMessage(error, t(fallbackKey));
	const requestId = apiErrorRequestId(error);
	return requestId ? `${message} · ${t("tickets.requestId", { requestId })}` : message;
}

function roleBody(input: TicketRoleInput) {
	return {
		harness: input.harness || undefined,
		model: input.model || undefined,
		claudeAccountId: input.claudeAccountId || undefined,
		extra: input.extra || undefined,
	};
}

function unwrap<T>(result: { data?: T; error?: unknown }): T {
	if (result.error) throw result.error;
	if (result.data === undefined) throw new Error("Empty response");
	return result.data;
}

function invalidateTickets(queryClient: QueryClient): void {
	void queryClient.invalidateQueries({ queryKey: ticketsQueryRoot });
	void queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
}

export function useTicketMutations() {
	const queryClient = useQueryClient();
	const onSettled = () => invalidateTickets(queryClient);

	const createTicket = useMutation({
		mutationFn: async (input: CreateTicketInput): Promise<CreateTicketResponse> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets", {
					params: { path: { id: input.projectId } },
					body: { title: input.title, brief: input.brief },
				}),
			),
		onSettled,
	});

	const planTicket = useMutation({
		mutationFn: async (input: PlanTicketInput): Promise<SessionView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plan", {
					params: { path: { id: input.projectId, slug: input.slug } },
					body: roleBody(input),
				}),
			),
		onSettled,
	});

	const reviewPlan = useMutation({
		mutationFn: async (input: ReviewPlanInput): Promise<ReviewPlanResponse> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/review", {
					params: { path: { id: input.projectId, slug: input.slug, plan: input.plan } },
					body: { reviewer: input.reviewer, ...roleBody(input) },
				}),
			),
		onSettled,
	});

	const approveMerge = useMutation({
		mutationFn: async (input: PlanRef): Promise<TicketView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/merge", {
					params: { path: { id: input.projectId, slug: input.slug, plan: input.plan } },
				}),
			).ticket,
		onSettled,
	});

	const markPlanDone = useMutation({
		mutationFn: async (input: PlanRef): Promise<TicketView> =>
			unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/done", {
					params: { path: { id: input.projectId, slug: input.slug, plan: input.plan } },
				}),
			).ticket,
		onSettled,
	});

	const setArchived = useMutation({
		mutationFn: async (input: SetArchivedInput): Promise<TicketView> => {
			const params = { path: { id: input.projectId, slug: input.slug } };
			const result = input.archived
				? await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/archive", { params })
				: await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/unarchive", { params });
			return unwrap(result).ticket;
		},
		onSettled,
	});

	return { createTicket, planTicket, reviewPlan, approveMerge, markPlanDone, setArchived };
}
```

The test expects `body: { reviewer: "new", harness: "claude-code", model: "claude-opus-5", claudeAccountId: undefined, extra: undefined }`; `toHaveBeenCalledWith` treats an explicit `undefined` property as equal to a missing one, so the spread order above satisfies it. If openapi-fetch's typing rejects the `body` for the `merge`, `done`, `archive` or `unarchive` calls because those operations declare no request body, remove the `body` key (there is none in the code above) and keep `params` only.

- [ ] **Step 6: Invalidate ticket queries on the CDC stream**

In `frontend/src/renderer/lib/event-transport.ts`, add the import after line 7 (`sessionUsageQueryRoot`):

```ts
import { ticketsQueryRoot } from "../hooks/useTicketsQuery";
```

and inside `refreshWorkspaces` (`event-transport.ts:39-46`), after the `sessionUsageQueryRoot` invalidation:

```ts
					void queryClient.invalidateQueries({ queryKey: ticketsQueryRoot });
```

`CDC_EVENT_TYPES` already lists `"ticket_updated"` (`event-transport.ts:35`), so the daemon's CDC row for assignment changes reaches this debounce with no further change.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-events.test.ts src/renderer/hooks/useTicketMutations.test.tsx src/renderer/lib/event-transport.test.ts`
Expected: PASS.

- [ ] **Step 8: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/lib/ticket-events.ts frontend/src/renderer/lib/ticket-events.test.ts frontend/src/renderer/hooks/useTicketsQuery.ts frontend/src/renderer/hooks/useTicketMutations.ts frontend/src/renderer/hooks/useTicketMutations.test.tsx frontend/src/renderer/lib/event-transport.ts frontend/src/renderer/lib/event-transport.test.ts
git commit -m "feat(tickets): ticket queries, mutations and live invalidation"
```

### Task 4: Extract `MarkdownBody` and `TaskModelPicker` for reuse

**Files:**
- Create: `frontend/src/renderer/components/MarkdownBody.tsx`
- Test: `frontend/src/renderer/components/MarkdownBody.test.tsx`
- Modify: `frontend/src/renderer/components/SessionInspector.tsx:6-7` (imports), `:1744-1775` (`ReviewMarkdownBody`), `:1926` (call site)
- Create: `frontend/src/renderer/components/TaskModelPicker.tsx`
- Modify: `frontend/src/renderer/components/TaskComposer.tsx:1-34` (imports), `:459-638` (`TaskModelPicker` definition)

**Interfaces:**
- Produces:
  - `MarkdownBody({ body, clamped = false, testId, className }: { body: string; clamped?: boolean; testId?: string; className?: string })` — the exact element `ReviewMarkdownBody` renders today (`SessionInspector.tsx:1744-1775`), with `className` merged onto the wrapper so the ticket page can raise the type size.
  - `TaskModelPicker` with the unchanged props `{ id, agentId, agentLabel, projectId, value, mode, onModelChange, onModeChange, onWarningChange }` (`TaskComposer.tsx:459-476`).

- [ ] **Step 1: Write the failing test**

`frontend/src/renderer/components/MarkdownBody.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { MarkdownBody } from "./MarkdownBody";

describe("MarkdownBody", () => {
	it("renders GitHub-flavoured markdown with external links opening in a new window", () => {
		render(<MarkdownBody body={"| a | b |\n|---|---|\n| 1 | 2 |\n\n[docs](https://example.com)"} testId="md" />);
		const root = screen.getByTestId("md");
		expect(root.querySelector("table")).not.toBeNull();
		const link = screen.getByRole("link", { name: "docs" });
		expect(link).toHaveAttribute("target", "_blank");
		expect(link).toHaveAttribute("rel", "noopener noreferrer");
	});

	it("clamps when asked and merges extra classes", () => {
		render(<MarkdownBody body="text" clamped className="text-sm" testId="md" />);
		expect(screen.getByTestId("md")).toHaveClass("line-clamp-4", "text-sm");
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/MarkdownBody.test.tsx`
Expected: FAIL, cannot resolve `./MarkdownBody`.

- [ ] **Step 3: Create `MarkdownBody` and point the inspector at it**

`frontend/src/renderer/components/MarkdownBody.tsx`:

```tsx
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { cn } from "../lib/utils";

export function MarkdownBody({
	body,
	clamped = false,
	testId,
	className,
}: {
	body: string;
	clamped?: boolean;
	testId?: string;
	className?: string;
}) {
	return (
		<div
			className={cn(
				"min-w-0 break-words text-2xs leading-relaxed text-muted-foreground",
				"[&_a]:font-medium [&_a]:text-foreground [&_a]:underline [&_a]:underline-offset-2",
				"[&_code]:rounded [&_code]:bg-muted/55 [&_code]:px-1 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-foreground",
				"[&_li]:my-0.5 [&_ol]:my-1.5 [&_ol]:list-decimal [&_ol]:pl-4 [&_p]:my-1.5 [&_pre]:my-2",
				"[&_pre]:overflow-x-auto [&_pre]:rounded-md [&_pre]:border [&_pre]:border-border [&_pre]:bg-muted/35 [&_pre]:p-2",
				"[&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_strong]:text-foreground [&_table]:my-2 [&_table]:w-full",
				"[&_table]:border-collapse [&_td]:border [&_td]:border-border [&_td]:px-2 [&_td]:py-1",
				"[&_th]:border [&_th]:border-border [&_th]:px-2 [&_th]:py-1 [&_th]:text-foreground",
				"[&_ul]:my-1.5 [&_ul]:list-disc [&_ul]:pl-4 [&>*:first-child]:mt-0 [&>*:last-child]:mb-0",
				"[&_h1]:mt-4 [&_h1]:text-base [&_h1]:font-semibold [&_h1]:text-foreground",
				"[&_h2]:mt-4 [&_h2]:text-sm [&_h2]:font-semibold [&_h2]:text-foreground",
				"[&_h3]:mt-3 [&_h3]:font-semibold [&_h3]:text-foreground [&_hr]:my-3 [&_hr]:border-border",
				clamped && "line-clamp-4",
				className,
			)}
			data-testid={testId}
		>
			<ReactMarkdown
				components={{
					a: ({ href, children }) => (
						<a href={href} target="_blank" rel="noopener noreferrer">
							{children}
						</a>
					),
				}}
				remarkPlugins={[remarkGfm]}
			>
				{body}
			</ReactMarkdown>
		</div>
	);
}
```

In `SessionInspector.tsx`:
- delete lines 6-7 (`import ReactMarkdown from "react-markdown";` and `import remarkGfm from "remark-gfm";`) and add `import { MarkdownBody } from "./MarkdownBody";` beside the other `./` component imports;
- delete the `ReviewMarkdownBody` function (`SessionInspector.tsx:1744-1775`);
- change the call at `SessionInspector.tsx:1926` from `<ReviewMarkdownBody body={body} clamped={clamped && !expanded} testId={testId} />` to `<MarkdownBody body={body} clamped={clamped && !expanded} testId={testId} />`.

The heading and `hr` rules are new: review bodies rarely contain headings, and the ticket page needs them to read as a document. `SessionInspector.test.tsx` does not reference `ReviewMarkdownBody` (grep returns nothing), so no test changes.

- [ ] **Step 4: Move `TaskModelPicker` into its own file**

Create `frontend/src/renderer/components/TaskModelPicker.tsx` containing exactly the function at `TaskComposer.tsx:459-638`, made `export function TaskModelPicker`, with these imports at the top (they are the subset of `TaskComposer.tsx:1-34` the function uses):

```tsx
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { cn } from "../lib/utils";
import {
	agentModelsQueryKey,
	agentModelsQueryOptions,
	revalidateAgentModels,
	type AgentModelCatalog,
} from "../hooks/useAgentModelsQuery";
import { AgentModelCombobox } from "./settings/AgentModelCombobox";
import { SettingsOptionMenu } from "./settings/SettingsOptionMenu";
```

Keep the moved function's existing comments as they are. In `TaskComposer.tsx`: delete lines 459-638, add `import { TaskModelPicker } from "./TaskModelPicker";`, and remove the imports that only the moved function used (`Loader2` stays because the submit button at `TaskComposer.tsx:441` uses it; `agentModelsQueryKey`, `revalidateAgentModels`, `AgentModelCatalog`, `AgentModelCombobox`, `SettingsOptionMenu` go; `agentModelsQueryOptions` stays because `TaskComposer.tsx:189` uses it). `npm run frontend:lint` reports any unused import left behind.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/MarkdownBody.test.tsx src/renderer/components/SessionInspector.test.tsx src/renderer/components/TaskComposer.test.tsx src/renderer/components/NewTaskDialog.test.tsx`
Expected: PASS.

- [ ] **Step 6: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/components/MarkdownBody.tsx frontend/src/renderer/components/MarkdownBody.test.tsx frontend/src/renderer/components/SessionInspector.tsx frontend/src/renderer/components/TaskModelPicker.tsx frontend/src/renderer/components/TaskComposer.tsx
git commit -m "refactor(renderer): extract MarkdownBody and TaskModelPicker for reuse"
```

### Task 5: Role fields, create / plan / review sheets and the merge confirmation

**Files:**
- Create: `frontend/src/renderer/components/tickets/TicketRoleFields.tsx`
- Create: `frontend/src/renderer/components/tickets/CreateTicketSheet.tsx`
- Test: `frontend/src/renderer/components/tickets/CreateTicketSheet.test.tsx`
- Create: `frontend/src/renderer/components/tickets/PlanWithAgentSheet.tsx`
- Test: `frontend/src/renderer/components/tickets/PlanWithAgentSheet.test.tsx`
- Create: `frontend/src/renderer/components/tickets/ReviewPlanSheet.tsx`
- Create: `frontend/src/renderer/components/tickets/MergeConfirmDialog.tsx`

**Interfaces:**
- Consumes: `RequiredAgentField` (`components/CreateProjectAgentSheet.tsx:337-365`, props `id, label, placeholder, value, onChange, authorized, installed, supported, disabled, variant`), `ClaudeAccountSelect` (`components/ClaudeAccountSelect.tsx:5-24`), `TaskModelPicker` (Task 4), `agentsQueryOptions`, `agentsQueryKey`, `refreshAgentsIfStale` (`hooks/useAgentsQuery.ts`), `useClaudeAccounts`, `preferredClaudeAccountId` (`hooks/useClaudeAccounts.ts:79,147`), `FieldDefaultHint` (`components/FieldDefaultHint.tsx`), `ConfirmDialog` (`components/ConfirmDialog.tsx:33-45`), `Dialog*` and `settingsDialog*Class` (`components/ui/dialog.tsx:99-126`), `Button` variants `footer` / `footer-primary` (`components/ui/button.tsx:20-23`), `Select*` (`components/ui/select.tsx`), `RadioGroup` from `radix-ui` used the way `components/settings/ReportProblemDialog.tsx:221-235` does, `useTicketMutations` and `ticketErrorMessage` (Task 3).
- Produces:
  - `type TicketRoleValues = { harness: string; model: string; claudeAccountId: string; extra: string }`, `emptyTicketRoleValues`
  - `TicketRoleFields({ projectId, value, onChange, disabled }: { projectId: string; value: TicketRoleValues; onChange: (next: TicketRoleValues) => void; disabled?: boolean })`
  - `CreateTicketSheet({ open, onOpenChange, projects, defaultProjectId }: { open: boolean; onOpenChange: (open: boolean) => void; projects: readonly TicketProject[]; defaultProjectId?: string })` — navigates to `/projects/$projectId/tickets/$slug` on success.
  - `PlanWithAgentSheet({ open, onOpenChange, ticket }: { open: boolean; onOpenChange: (open: boolean) => void; ticket: Pick<TicketView, "projectId" | "slug" | "title"> })` — navigates to the spawned session on success.
  - `ReviewPlanSheet({ open, onOpenChange, ticket, plan }: { open: boolean; onOpenChange: (open: boolean) => void; ticket: Pick<TicketView, "projectId" | "slug" | "title">; plan: Pick<PlanView, "file" | "title"> })` — navigates to the reviewing session on success.
  - `MergeConfirmDialog({ open, onOpenChange, ticket, plan }: { open: boolean; onOpenChange: (open: boolean) => void; ticket: Pick<TicketView, "projectId" | "slug">; plan: Pick<PlanView, "file" | "title" | "mergeSummary"> })`

The route `/projects/$projectId/tickets/$slug` is created in Task 6. Until then `npm run typecheck` rejects the `navigate` calls in this task; Task 5 therefore runs only vitest and lint in its gate, and Task 6 runs the full gate over both.

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/components/tickets/CreateTicketSheet.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, createMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	createMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({
			createTicket: { mutateAsync: createMutateAsync, isPending: false },
		}),
	};
});

import { CreateTicketSheet } from "./CreateTicketSheet";

function renderSheet(projects: Array<{ id: string; name: string }>, defaultProjectId?: string) {
	const onOpenChange = vi.fn();
	render(
		<QueryClientProvider client={new QueryClient()}>
			<CreateTicketSheet open onOpenChange={onOpenChange} projects={projects} defaultProjectId={defaultProjectId} />
		</QueryClientProvider>,
	);
	return { onOpenChange };
}

beforeEach(() => {
	navigateMock.mockReset();
	createMutateAsync.mockReset();
});

describe("CreateTicketSheet", () => {
	it("creates the ticket for the only project and opens its page", async () => {
		createMutateAsync.mockResolvedValue({ ticket: { projectId: "p1", slug: "search-page", title: "Search page" }, warnings: [] });
		const { onOpenChange } = renderSheet([{ id: "p1", name: "app" }]);

		await userEvent.type(screen.getByLabelText("Title"), "Search page");
		await userEvent.type(screen.getByLabelText("Brief"), "Full text search");
		await userEvent.click(screen.getByRole("button", { name: "New ticket" }));

		await waitFor(() =>
			expect(createMutateAsync).toHaveBeenCalledWith({ projectId: "p1", title: "Search page", brief: "Full text search" }),
		);
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: {},
		});
	});

	it("keeps the submit disabled until a title is typed", async () => {
		renderSheet([{ id: "p1", name: "app" }]);
		expect(screen.getByRole("button", { name: "New ticket" })).toBeDisabled();
		await userEvent.type(screen.getByLabelText("Title"), "x");
		expect(screen.getByRole("button", { name: "New ticket" })).toBeEnabled();
	});

	it("shows the daemon's error with its request id and stays open", async () => {
		createMutateAsync.mockRejectedValue({
			error: "bad_request",
			code: "TICKET_UNSUPPORTED_PROJECT",
			message: "nope",
			requestId: "req-3",
		});
		const { onOpenChange } = renderSheet([{ id: "p1", name: "app" }]);

		await userEvent.type(screen.getByLabelText("Title"), "Search page");
		await userEvent.click(screen.getByRole("button", { name: "New ticket" }));

		expect(await screen.findByRole("alert")).toHaveTextContent(
			"Tickets need a single-repository project. · request req-3",
		);
		expect(onOpenChange).not.toHaveBeenCalledWith(false);
	});

	it("offers a project picker when several projects can hold tickets", () => {
		renderSheet(
			[
				{ id: "p1", name: "app" },
				{ id: "p2", name: "api" },
			],
			"p2",
		);
		expect(screen.getByLabelText("Project")).toHaveTextContent("api");
	});
});
```

`frontend/src/renderer/components/tickets/PlanWithAgentSheet.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, planMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	planMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({ planTicket: { mutateAsync: planMutateAsync, isPending: false } }),
	};
});

vi.mock("../../hooks/useAgentsQuery", () => ({
	agentsQueryKey: ["agents"],
	agentsQueryOptions: {
		queryKey: ["agents"],
		queryFn: async () => ({
			supported: [{ id: "claude-code", label: "Claude Code" }],
			installed: [{ id: "claude-code", label: "Claude Code" }],
			authorized: [{ id: "claude-code", label: "Claude Code" }],
		}),
	},
	refreshAgentsIfStale: async () => undefined,
}));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => ({ data: [], isError: false, isLoading: false }) };
});

vi.mock("../TaskModelPicker", () => ({
	TaskModelPicker: ({ id, value, onModelChange }: { id: string; value: string; onModelChange: (v: string) => void }) => (
		<input id={id} aria-label="Model" value={value} onChange={(event) => onModelChange(event.target.value)} />
	),
}));

import { PlanWithAgentSheet } from "./PlanWithAgentSheet";

beforeEach(() => {
	navigateMock.mockReset();
	planMutateAsync.mockReset();
});

describe("PlanWithAgentSheet", () => {
	it("starts the planning session with the chosen role fields and opens it", async () => {
		planMutateAsync.mockResolvedValue({ id: "s-plan", projectId: "p1" });
		const onOpenChange = vi.fn();
		render(
			<QueryClientProvider client={new QueryClient()}>
				<PlanWithAgentSheet
					open
					onOpenChange={onOpenChange}
					ticket={{ projectId: "p1", slug: "search-page", title: "Search page" }}
				/>
			</QueryClientProvider>,
		);

		await userEvent.type(screen.getByLabelText("Model"), "claude-opus-5");
		await userEvent.type(screen.getByLabelText("Extra instructions"), "Keep it small");
		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		await waitFor(() =>
			expect(planMutateAsync).toHaveBeenCalledWith({
				projectId: "p1",
				slug: "search-page",
				harness: "",
				model: "claude-opus-5",
				claudeAccountId: "",
				extra: "Keep it small",
			}),
		);
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-plan" },
		});
	});

	it("reports a running planning session instead of closing", async () => {
		planMutateAsync.mockRejectedValue({
			error: "conflict",
			code: "TICKET_PLANNING_ACTIVE",
			message: "running",
			requestId: "req-9",
		});
		render(
			<QueryClientProvider client={new QueryClient()}>
				<PlanWithAgentSheet
					open
					onOpenChange={vi.fn()}
					ticket={{ projectId: "p1", slug: "search-page", title: "Search page" }}
				/>
			</QueryClientProvider>,
		);

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		expect(await screen.findByRole("alert")).toHaveTextContent(
			"This ticket already has a running planning session. · request req-9",
		);
		expect(navigateMock).not.toHaveBeenCalled();
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets`
Expected: FAIL, modules not found.

- [ ] **Step 3: Write `TicketRoleFields`**

`frontend/src/renderer/components/tickets/TicketRoleFields.tsx`:

```tsx
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { agentsQueryKey, agentsQueryOptions, refreshAgentsIfStale } from "../../hooks/useAgentsQuery";
import { preferredClaudeAccountId, useClaudeAccounts } from "../../hooks/useClaudeAccounts";
import { ClaudeAccountSelect } from "../ClaudeAccountSelect";
import { RequiredAgentField } from "../CreateProjectAgentSheet";
import { FieldDefaultHint } from "../FieldDefaultHint";
import { TaskModelPicker } from "../TaskModelPicker";

export type TicketRoleValues = { harness: string; model: string; claudeAccountId: string; extra: string };

export const emptyTicketRoleValues: TicketRoleValues = { harness: "", model: "", claudeAccountId: "", extra: "" };

export function TicketRoleFields({
	projectId,
	value,
	onChange,
	disabled = false,
}: {
	projectId: string;
	value: TicketRoleValues;
	onChange: (next: TicketRoleValues) => void;
	disabled?: boolean;
}) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const harnessId = useId();
	const modelId = useId();
	const accountId = useId();
	const extraId = useId();
	const agentsQuery = useQuery(agentsQueryOptions);
	useEffect(() => {
		void refreshAgentsIfStale().then((next) => {
			if (next) queryClient.setQueryData(agentsQueryKey, next);
		});
	}, [queryClient]);
	const claudeAccountsQuery = useClaudeAccounts();
	const [modelWarning, setModelWarning] = useState<string | undefined>();
	const accounts = claudeAccountsQuery.data ?? [];
	const catalog = agentsQuery.data;
	const agentLabel = catalog?.supported?.find((item) => item.id === value.harness)?.label || value.harness;
	const showAccount = value.harness === "claude-code" && accounts.length > 1;
	const set = (patch: Partial<TicketRoleValues>) => onChange({ ...value, ...patch });

	return (
		<div className="flex flex-col gap-4">
			<div className="grid gap-4 sm:grid-cols-2">
				<RequiredAgentField
					id={harnessId}
					label={t("tickets.harness")}
					placeholder={t("tickets.harness")}
					value={value.harness}
					authorized={catalog?.authorized}
					installed={catalog?.installed}
					supported={catalog?.supported}
					disabled={disabled || (agentsQuery.isFetching && catalog === undefined)}
					onChange={(harness) => set({ harness, model: "", claudeAccountId: "" })}
				/>
				<div className="flex flex-col gap-1.5">
					<label className="settings-field-label" htmlFor={modelId}>
						{t("tickets.model")}
					</label>
					<TaskModelPicker
						id={modelId}
						agentId={value.harness}
						agentLabel={agentLabel}
						projectId={projectId}
						value={value.model}
						mode=""
						onModelChange={(model) => set({ model })}
						onModeChange={(model) => set({ model })}
						onWarningChange={setModelWarning}
					/>
				</div>
			</div>
			{showAccount ? (
				<div className="flex flex-col gap-1.5">
					<label className="settings-field-label" htmlFor={accountId}>
						{t("tickets.account")}
					</label>
					<ClaudeAccountSelect
						id={accountId}
						ariaLabel={t("tickets.account")}
						value={value.claudeAccountId || preferredClaudeAccountId(accounts)}
						onChange={(claudeAccountId) => set({ claudeAccountId })}
						accounts={accounts}
					/>
				</div>
			) : null}
			<div className="flex flex-col gap-1.5">
				<label className="settings-field-label" htmlFor={extraId}>
					{t("tickets.extra")}
				</label>
				<textarea
					id={extraId}
					className="settings-field-control min-h-(--size-textarea-min) resize-y py-2.5"
					disabled={disabled}
					value={value.extra}
					onChange={(event) => set({ extra: event.target.value })}
					placeholder={t("tickets.extraPlaceholder")}
				/>
			</div>
			{modelWarning ? (
				<p className="text-caption text-warning" role="status">
					{modelWarning}
				</p>
			) : null}
			<FieldDefaultHint text={t("tickets.defaultsHint")} />
		</div>
	);
}
```

`TaskModelPicker` needs a non-empty `agentId` to show a catalogue; with `harness === ""` it renders the free-text input disabled (`TaskModelPicker` branch "Free-text agents keep an input", `disabled={agentId === ""}`). That is the intended reading: pick an agent to override the model, or leave both empty for the project defaults.

- [ ] **Step 4: Write `CreateTicketSheet`**

`frontend/src/renderer/components/tickets/CreateTicketSheet.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketProject } from "../../hooks/useTicketsQuery";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

export function CreateTicketSheet({
	open,
	onOpenChange,
	projects,
	defaultProjectId,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	projects: readonly TicketProject[];
	defaultProjectId?: string;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { createTicket } = useTicketMutations();
	const projectSelectId = useId();
	const titleId = useId();
	const briefId = useId();
	const [projectId, setProjectId] = useState(defaultProjectId ?? projects[0]?.id ?? "");
	const [title, setTitle] = useState("");
	const [brief, setBrief] = useState("");
	const [error, setError] = useState<string | null>(null);
	const busy = createTicket.isPending;
	const selectedProject = projects.find((project) => project.id === projectId) ?? projects[0];
	const canSubmit = !busy && title.trim() !== "" && selectedProject !== undefined;

	useEffect(() => {
		if (!open) {
			setTitle("");
			setBrief("");
			setError(null);
			return;
		}
		setProjectId(defaultProjectId ?? projects[0]?.id ?? "");
	}, [defaultProjectId, open, projects]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (!canSubmit || !selectedProject) return;
		setError(null);
		try {
			const result = await createTicket.mutateAsync({
				projectId: selectedProject.id,
				title: title.trim(),
				brief: brief.trim(),
			});
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/tickets/$slug",
				params: { projectId: result.ticket.projectId, slug: result.ticket.slug },
				search: {},
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.createFailed"));
		}
	};

	return (
		<Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
			<DialogContent showCloseButton={false} className={settingsDialogContentClass}>
				<DialogClose asChild>
					<button
						type="button"
						disabled={busy}
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("confirm.close")}
						title={t("confirm.closeEsc")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				<form onSubmit={(event) => void submit(event)} className="flex min-h-0 flex-col">
					<div className={settingsDialogHeaderClass}>
						<DialogTitle className="settings-dialog-title">{t("tickets.create")}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.createDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						{projects.length > 1 ? (
							<div className="flex flex-col gap-1.5">
								<label className="settings-field-label" htmlFor={projectSelectId}>
									{t("tickets.project")}
								</label>
								<Select value={selectedProject?.id ?? ""} onValueChange={setProjectId}>
									<SelectTrigger id={projectSelectId}>
										<SelectValue>{selectedProject?.name}</SelectValue>
									</SelectTrigger>
									<SelectContent align="start" position="popper">
										{projects.map((project) => (
											<SelectItem key={project.id} value={project.id}>
												{project.name}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
						) : null}
						<div className="flex flex-col gap-1.5">
							<label className="settings-field-label" htmlFor={titleId}>
								{t("tickets.title")}
							</label>
							<input
								id={titleId}
								autoFocus
								className="settings-field-control h-(--size-settings-action-height)"
								disabled={busy}
								maxLength={200}
								value={title}
								onChange={(event) => setTitle(event.target.value)}
								placeholder={t("tickets.titlePlaceholder")}
							/>
						</div>
						<div className="flex flex-col gap-1.5">
							<label className="settings-field-label" htmlFor={briefId}>
								{t("tickets.brief")}
							</label>
							<textarea
								id={briefId}
								className="settings-field-control min-h-(--size-textarea-min) resize-y py-2.5"
								disabled={busy}
								maxLength={4000}
								value={brief}
								onChange={(event) => setBrief(event.target.value)}
								placeholder={t("tickets.briefPlaceholder")}
							/>
						</div>
						{error ? (
							<p role="alert" className="text-caption leading-4 text-error">
								{error}
							</p>
						) : null}
					</div>
					<div className={settingsDialogFooterClass}>
						<DialogClose asChild>
							<Button type="button" variant="footer" disabled={busy}>
								{t("confirm.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" variant="footer-primary" disabled={!canSubmit}>
							{busy ? t("tickets.creating") : t("tickets.create")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`maxLength` 200 and 4000 mirror `CreateTicketRequest` (`dto.go:1563-1566`).

- [ ] **Step 5: Write `PlanWithAgentSheet`, `ReviewPlanSheet` and `MergeConfirmDialog`**

`frontend/src/renderer/components/tickets/PlanWithAgentSheet.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketView } from "../../lib/ticket-presentation";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { emptyTicketRoleValues, TicketRoleFields, type TicketRoleValues } from "./TicketRoleFields";

export function PlanWithAgentSheet({
	open,
	onOpenChange,
	ticket,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug" | "title">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { planTicket } = useTicketMutations();
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [error, setError] = useState<string | null>(null);
	const busy = planTicket.isPending;

	useEffect(() => {
		if (!open) {
			setValues(emptyTicketRoleValues);
			setError(null);
		}
	}, [open]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy) return;
		setError(null);
		try {
			const session = await planTicket.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, ...values });
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/sessions/$sessionId",
				params: { projectId: session.projectId || ticket.projectId, sessionId: session.id },
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.planFailed"));
		}
	};

	return (
		<Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
			<DialogContent showCloseButton={false} className={settingsDialogContentClass}>
				<DialogClose asChild>
					<button
						type="button"
						disabled={busy}
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("confirm.close")}
						title={t("confirm.closeEsc")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				<form onSubmit={(event) => void submit(event)} className="flex min-h-0 flex-col">
					<div className={settingsDialogHeaderClass}>
						<DialogTitle className="settings-dialog-title">{t("tickets.planWithAgent")}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{ticket.title} · {t("tickets.planDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						<TicketRoleFields projectId={ticket.projectId} value={values} onChange={setValues} disabled={busy} />
						{error ? (
							<p role="alert" className="text-caption leading-4 text-error">
								{error}
							</p>
						) : null}
					</div>
					<div className={settingsDialogFooterClass}>
						<DialogClose asChild>
							<Button type="button" variant="footer" disabled={busy}>
								{t("confirm.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" variant="footer-primary" disabled={busy}>
							{busy ? t("tickets.starting") : t("tickets.start")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`frontend/src/renderer/components/tickets/ReviewPlanSheet.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { RadioGroup } from "radix-ui";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { PlanView, TicketView } from "../../lib/ticket-presentation";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { emptyTicketRoleValues, TicketRoleFields, type TicketRoleValues } from "./TicketRoleFields";

type Reviewer = "planner" | "new";

export function ReviewPlanSheet({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug" | "title">;
	plan: Pick<PlanView, "file" | "title">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { reviewPlan } = useTicketMutations();
	const [reviewer, setReviewer] = useState<Reviewer>("planner");
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [error, setError] = useState<string | null>(null);
	const busy = reviewPlan.isPending;

	useEffect(() => {
		if (!open) {
			setReviewer("planner");
			setValues(emptyTicketRoleValues);
			setError(null);
		}
	}, [open]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy) return;
		setError(null);
		try {
			const result = await reviewPlan.mutateAsync({
				projectId: ticket.projectId,
				slug: ticket.slug,
				plan: plan.file,
				reviewer,
				...values,
			});
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/sessions/$sessionId",
				params: { projectId: result.session.projectId || ticket.projectId, sessionId: result.session.id },
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.reviewFailed"));
		}
	};

	const reviewers: Array<{ value: Reviewer; label: string }> = [
		{ value: "planner", label: t("tickets.reviewer.planner") },
		{ value: "new", label: t("tickets.reviewer.new") },
	];

	return (
		<Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
			<DialogContent showCloseButton={false} className={settingsDialogContentClass}>
				<DialogClose asChild>
					<button
						type="button"
						disabled={busy}
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("confirm.close")}
						title={t("confirm.closeEsc")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				<form onSubmit={(event) => void submit(event)} className="flex min-h-0 flex-col">
					<div className={settingsDialogHeaderClass}>
						<DialogTitle className="settings-dialog-title">{t("tickets.reviewTitle", { plan: plan.title })}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.reviewDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						<div className="flex flex-col gap-1.5">
							<span className="settings-field-label">{t("tickets.reviewer")}</span>
							<RadioGroup.Root
								aria-label={t("tickets.reviewer")}
								className="settings-segment self-start"
								value={reviewer}
								onValueChange={(next) => setReviewer(next as Reviewer)}
							>
								{reviewers.map((option) => (
									<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
										{option.label}
									</RadioGroup.Item>
								))}
							</RadioGroup.Root>
						</div>
						<TicketRoleFields projectId={ticket.projectId} value={values} onChange={setValues} disabled={busy} />
						{error ? (
							<p role="alert" className="text-caption leading-4 text-error">
								{error}
							</p>
						) : null}
					</div>
					<div className={settingsDialogFooterClass}>
						<DialogClose asChild>
							<Button type="button" variant="footer" disabled={busy}>
								{t("confirm.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" variant="footer-primary" disabled={busy}>
							{busy ? t("tickets.starting") : t("tickets.review")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

The role fields stay visible for `planner` too: the daemon respawns a terminated planner with these fields (spec §2.6, "If that session is terminated or missing, a new in-place planning session is spawned").

`frontend/src/renderer/components/tickets/MergeConfirmDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { PlanView, TicketView } from "../../lib/ticket-presentation";
import { ConfirmDialog } from "../ConfirmDialog";
import { MarkdownBody } from "../MarkdownBody";

export function MergeConfirmDialog({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug">;
	plan: Pick<PlanView, "file" | "title" | "mergeSummary">;
}) {
	const { t } = useTranslation();
	const { approveMerge } = useTicketMutations();
	const [error, setError] = useState<string | null>(null);
	const confirm = async () => {
		setError(null);
		try {
			await approveMerge.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, plan: plan.file });
			onOpenChange(false);
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.mergeFailed"));
		}
	};
	return (
		<ConfirmDialog
			open={open}
			title={t("tickets.mergeTitle", { plan: plan.title })}
			description={
				<div className="flex flex-col gap-2">
					<span>{t("tickets.mergeDescription")}</span>
					{plan.mergeSummary ? <MarkdownBody body={plan.mergeSummary} testId="merge-summary" /> : null}
				</div>
			}
			confirmLabel={approveMerge.isPending ? t("tickets.merging") : t("tickets.merge")}
			busy={approveMerge.isPending}
			error={error}
			onConfirm={() => void confirm()}
			onOpenChange={(next) => {
				if (!next) setError(null);
				onOpenChange(next);
			}}
		/>
	);
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets src/renderer/i18n`
Expected: PASS.

- [ ] **Step 7: Run lint and commit**

Run: `cd frontend && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: green (typecheck is deferred to Task 6 because of the ticket route).

```bash
git add frontend/src/renderer/components/tickets frontend/src/renderer/i18n
git commit -m "feat(tickets): create, plan and review sheets and the merge confirmation"
```

### Task 6: Plan rows, the ticket page and its route

**Files:**
- Create: `frontend/src/renderer/components/tickets/PlanRow.tsx`
- Create: `frontend/src/renderer/components/tickets/TicketPage.tsx`
- Test: `frontend/src/renderer/components/tickets/TicketPage.test.tsx`
- Create: `frontend/src/renderer/routes/_shell.projects.$projectId_.tickets.$slug.tsx`
- Modify (generated): `frontend/src/renderer/routeTree.gen.ts`

**Interfaces:**
- Consumes: `useTicketQuery`, `useTicketFileQuery` (Task 3), `useTicketMutations`, `ticketErrorMessage` (Task 3), `getPlanStatusView`, `getTicketStatusView`, `isTicketInArchive`, `planNumber`, `splitFrontmatter`, `ticketFileGroups` (Task 2), `MarkdownBody` (Task 4), `PlanWithAgentSheet`, `ReviewPlanSheet`, `MergeConfirmDialog` (Task 5), `useWorkspaceQuery` (`hooks/useWorkspaceQuery.ts:125`), `getAgentActivityView` (`lib/session-presentation.ts:61`), `StatusPill` (`components/StatusPill.tsx:13`), `formatTimeCompact` (`lib/format-time.ts:4`), `useNavigateToSession` (`lib/navigate-to-session.ts:4`), `TopbarButton` (`components/TopbarButton.tsx`, the same control the board header uses at `SessionsBoard.tsx:278-284`), `dotGlow` (`theme/effects.ts:11`), `cn` (`lib/utils.ts`).
- Produces:
  - `PlanRow({ plan, session, onOpenSession, onReview, onMerge, onMarkDone, onOpenFile, selectedFile }: PlanRowProps)` where `PlanRowProps = { plan: PlanView; session?: WorkspaceSession; onOpenSession: (sessionId: string) => void; onReview?: (plan: PlanView) => void; onMerge?: (plan: PlanView) => void; onMarkDone?: (plan: PlanView) => void; onOpenFile?: (file: string) => void; selectedFile?: string }`
  - `canReviewPlan(plan: PlanView): boolean` (exported from `PlanRow.tsx`)
  - `TicketPage({ projectId, slug, file }: { projectId: string; slug: string; file?: string })`
  - Route `/projects/$projectId/tickets/$slug` with search `{ file?: string }`.

- [ ] **Step 1: Write the failing test**

`frontend/src/renderer/components/tickets/TicketPage.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { TooltipProvider } from "../ui/tooltip";

const { navigateMock, ticketQueryMock, ticketFileQueryMock, workspaceQueryMock, mutationsMock } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	ticketQueryMock: vi.fn(),
	ticketFileQueryMock: vi.fn(),
	workspaceQueryMock: vi.fn(),
	mutationsMock: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));
vi.mock("../../hooks/useTicketsQuery", () => ({
	useTicketQuery: ticketQueryMock,
	useTicketFileQuery: ticketFileQueryMock,
}));
vi.mock("../../hooks/useWorkspaceQuery", () => ({
	workspaceQueryKey: ["workspaces"],
	useWorkspaceQuery: workspaceQueryMock,
}));
vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return { ...actual, useTicketMutations: () => mutationsMock() };
});
vi.mock("./PlanWithAgentSheet", () => ({ PlanWithAgentSheet: () => null }));
vi.mock("./ReviewPlanSheet", () => ({ ReviewPlanSheet: () => null }));
vi.mock("./MergeConfirmDialog", () => ({ MergeConfirmDialog: () => null }));

import { TicketPage } from "./TicketPage";

const ticket = {
	projectId: "p1",
	slug: "search-page",
	title: "Search page",
	brief: "Full text search",
	status: "in_progress" as const,
	planningSessionId: "s-plan",
	plans: [
		{ file: "plans/01-index.md", order: 1, title: "Index", status: "merged" as const, sessionId: "s-1" },
		{
			file: "plans/02-ui.md",
			order: 2,
			title: "UI",
			status: "working" as const,
			sessionId: "s-2",
			kickoffFile: "plans/02-ui.kickoff.md",
		},
	],
	files: ["ticket.md", "spec.md", "plans/01-index.md", "plans/02-ui.md", "plans/02-ui.kickoff.md"],
};

function renderPage(file?: string) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>
				<TicketPage projectId="p1" slug="search-page" file={file} />
			</TooltipProvider>
		</QueryClientProvider>,
	);
}

beforeEach(() => {
	navigateMock.mockReset();
	ticketQueryMock.mockReset().mockReturnValue({ data: ticket, isError: false, isSuccess: true });
	ticketFileQueryMock.mockReset().mockReturnValue({
		data: { path: "spec.md", content: '---\ntitle: "Search page"\n---\n\n# Spec\n\nSearch **everything**.', modifiedAt: "2026-09-18T10:00:00Z" },
		isError: false,
	});
	workspaceQueryMock.mockReset().mockReturnValue({
		data: [
			{
				id: "p1",
				name: "app",
				kind: "single_repo",
				path: "/tmp/app",
				sessions: [
					{ id: "s-plan", workspaceId: "p1", workspaceName: "app", title: "plan", provider: "claude-code", status: "idle", updatedAt: "2026-09-18T10:00:00Z", prs: [], activity: { state: "idle", lastActivityAt: "2026-09-18T10:00:00Z" } },
					{ id: "s-2", workspaceId: "p1", workspaceName: "app", title: "ui", provider: "claude-code", status: "working", updatedAt: "2026-09-18T10:00:00Z", prs: [], activity: { state: "active", lastActivityAt: "2026-09-18T10:00:00Z" } },
				],
			},
		],
		isError: false,
		isSuccess: true,
	});
	mutationsMock.mockReset().mockReturnValue({
		markPlanDone: { mutateAsync: vi.fn(), isPending: false },
		setArchived: { mutateAsync: vi.fn(), isPending: false },
	});
});

describe("TicketPage", () => {
	it("lists the docs, the plans with their kickoff files and the planning session", () => {
		renderPage("spec.md");
		const files = screen.getByRole("navigation", { name: "Ticket files" });
		expect(within(files).getByRole("button", { name: "ticket.md" })).toBeInTheDocument();
		expect(within(files).getByRole("button", { name: "spec.md" })).toHaveAttribute("aria-current", "true");
		expect(within(files).getByText("01")).toBeInTheDocument();
		expect(within(files).getByText("Index")).toBeInTheDocument();
		expect(within(files).getByRole("button", { name: "Kickoff prompt" })).toBeInTheDocument();
		expect(within(files).getByText("Merged")).toBeInTheDocument();
		expect(within(files).getByText("Working")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Open planning session" })).toBeInTheDocument();
		expect(screen.getByText("1/2 merged")).toBeInTheDocument();
	});

	it("previews the selected file with its frontmatter above the body", () => {
		renderPage("spec.md");
		expect(ticketFileQueryMock).toHaveBeenCalledWith("p1", "search-page", "spec.md");
		expect(screen.getByRole("heading", { name: "Spec" })).toBeInTheDocument();
		expect(screen.getByText("everything")).toBeInTheDocument();
		expect(screen.getByText("title")).toBeInTheDocument();
		expect(screen.getByText("Search page", { selector: "dd" })).toBeInTheDocument();
	});

	it("defaults to spec.md and navigates when another file is picked", async () => {
		renderPage(undefined);
		expect(ticketFileQueryMock).toHaveBeenCalledWith("p1", "search-page", "spec.md");
		await userEvent.click(screen.getByRole("button", { name: "ticket.md" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: { file: "ticket.md" },
			replace: true,
		});
	});

	it("opens the implementing session from its plan row", async () => {
		renderPage("spec.md");
		await userEvent.click(screen.getByRole("button", { name: "Open the session for UI" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-2" },
		});
	});

	it("shows a warning banner above an unreadable ticket", () => {
		ticketQueryMock.mockReturnValue({
			data: { ...ticket, status: "draft", plans: [], warning: "ticket.md: malformed frontmatter" },
			isError: false,
			isSuccess: true,
		});
		renderPage("ticket.md");
		const banners = screen.getAllByRole("status");
		expect(banners).toHaveLength(2);
		for (const banner of banners) expect(banner).toHaveTextContent("ticket.md: malformed frontmatter");
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketPage.test.tsx`
Expected: FAIL, cannot resolve `./TicketPage`.

- [ ] **Step 3: Write `PlanRow`**

`frontend/src/renderer/components/tickets/PlanRow.tsx`:

```tsx
import { AlertTriangle } from "lucide-react";
import type { KeyboardEvent, MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { getAgentActivityView } from "../../lib/session-presentation";
import { getPlanStatusView, planNumber, type PlanView } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";

export type PlanRowProps = {
	plan: PlanView;
	session?: WorkspaceSession;
	onOpenSession: (sessionId: string) => void;
	onReview?: (plan: PlanView) => void;
	onMerge?: (plan: PlanView) => void;
	onMarkDone?: (plan: PlanView) => void;
	onOpenFile?: (file: string) => void;
	selectedFile?: string;
};

const reviewableStatuses = new Set<PlanView["status"]>(["idle", "working", "needs_you", "in_review", "terminated"]);
const closedStatuses = new Set<PlanView["status"]>(["merged", "done"]);

export function canReviewPlan(plan: PlanView): boolean {
	return Boolean(plan.sessionId) && reviewableStatuses.has(plan.status);
}

const rowActionClass =
	"inline-flex h-control-md shrink-0 items-center rounded-sm px-1.5 font-mono text-micro font-medium uppercase tracking-wide-sm transition-colors hover:bg-interactive-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 disabled:opacity-50";

export function PlanRow({
	plan,
	session,
	onOpenSession,
	onReview,
	onMerge,
	onMarkDone,
	onOpenFile,
	selectedFile,
}: PlanRowProps) {
	const { t } = useTranslation();
	const status = getPlanStatusView(plan.status, t);
	const activity = session ? getAgentActivityView(session.activity, t) : undefined;
	const number = planNumber(plan.file);
	const sessionId = plan.sessionId;
	const openSession = (event: MouseEvent | KeyboardEvent) => {
		event.stopPropagation();
		if (sessionId) onOpenSession(sessionId);
	};
	const stop = (event: MouseEvent<HTMLButtonElement>) => event.stopPropagation();
	const openFile = onOpenFile ? () => onOpenFile(plan.file) : undefined;
	const showMerge = plan.status === "awaiting_merge" && onMerge;
	const showReview = onReview && canReviewPlan(plan);
	const showDone = onMarkDone && !closedStatuses.has(plan.status);
	const selected = selectedFile === plan.file;

	return (
		<div
			className={cn(
				"flex flex-col gap-1 rounded-md px-1.5 py-1 text-2xs",
				selected && "bg-interactive-hover",
			)}
			data-plan-file={plan.file}
			data-testid="ticket-plan-row"
		>
			<div className="flex min-w-0 items-center gap-2">
				<span className="w-5 shrink-0 font-mono text-micro text-passive">{number || "·"}</span>
				{openFile ? (
					<button
						type="button"
						aria-current={selected ? "true" : undefined}
						className="min-w-0 flex-1 truncate text-left text-foreground hover:underline"
						onClick={openFile}
						title={plan.file}
					>
						{plan.title}
					</button>
				) : (
					<span className="min-w-0 flex-1 truncate text-foreground" title={plan.file}>
						{plan.title}
					</span>
				)}
				{plan.unordered ? (
					<AlertTriangle aria-label={t("tickets.unorderedPlan")} className="size-icon-2xs shrink-0 text-warning" />
				) : null}
				<span
					className={cn("inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap font-medium", status.className)}
					style={activity && activity.state === "active" ? { color: activity.tone } : undefined}
				>
					<span
						aria-hidden="true"
						className={cn(
							"size-dot-sm shrink-0 rounded-full",
							activity && activity.state === "active" ? activity.indicatorClassName : status.dotClassName,
							!activity && status.breathe && "animate-status-pulse",
						)}
					/>
					{status.label}
				</span>
			</div>
			{sessionId || showReview || showMerge || showDone ? (
				<div className="flex items-center gap-1 pl-7">
					{sessionId ? (
						<button
							type="button"
							aria-label={t("tickets.openSessionAria", { plan: plan.title })}
							className={cn(rowActionClass, "text-passive hover:text-foreground")}
							onClick={openSession}
							title={session ? session.title : t("tickets.sessionMissing")}
						>
							{session ? session.title : t("tickets.sessionMissing")}
						</button>
					) : null}
					<span className="flex-1" />
					{showReview ? (
						<button
							type="button"
							className={cn(rowActionClass, "text-status-in-review")}
							onClick={(event) => {
								stop(event);
								onReview(plan);
							}}
						>
							{t("tickets.review")}
						</button>
					) : null}
					{showMerge ? (
						<button
							type="button"
							className={cn(rowActionClass, "bg-status-ready/15 text-status-ready")}
							data-testid="plan-merge-button"
							onClick={(event) => {
								stop(event);
								onMerge(plan);
							}}
						>
							{t("tickets.merge")}
						</button>
					) : null}
					{showDone ? (
						<button
							type="button"
							className={cn(rowActionClass, "text-passive hover:text-foreground")}
							onClick={(event) => {
								stop(event);
								onMarkDone(plan);
							}}
						>
							{t("tickets.markDone")}
						</button>
					) : null}
				</div>
			) : null}
			{plan.warning ? (
				<p className="pl-7 text-micro text-warning" role="status">
					{plan.warning}
				</p>
			) : null}
		</div>
	);
}
```

- [ ] **Step 4: Write `TicketPage`**

`frontend/src/renderer/components/tickets/TicketPage.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { AlertTriangle, Archive, ArchiveRestore, FileText } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { useTicketFileQuery, useTicketQuery } from "../../hooks/useTicketsQuery";
import { useWorkspaceQuery } from "../../hooks/useWorkspaceQuery";
import { formatTimeCompact } from "../../lib/format-time";
import { getAgentActivityView } from "../../lib/session-presentation";
import {
	getTicketStatusView,
	isTicketInArchive,
	splitFrontmatter,
	ticketFileGroups,
	type PlanView,
	type TicketView,
} from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { MarkdownBody } from "../MarkdownBody";
import { StatusPill } from "../StatusPill";
import { TopbarButton } from "../TopbarButton";
import { MergeConfirmDialog } from "./MergeConfirmDialog";
import { PlanRow } from "./PlanRow";
import { PlanWithAgentSheet } from "./PlanWithAgentSheet";
import { ReviewPlanSheet } from "./ReviewPlanSheet";

const liveSessionStatuses = new Set<WorkspaceSession["status"]>(["working", "idle", "needs_input", "no_signal"]);

function defaultFile(ticket: TicketView): string | undefined {
	if (ticket.files.includes("spec.md")) return "spec.md";
	return ticket.files[0];
}

export function TicketPage({ projectId, slug, file }: { projectId: string; slug: string; file?: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const ticketQuery = useTicketQuery(projectId, slug);
	const ticket = ticketQuery.data;
	const selectedFile = file ?? (ticket ? defaultFile(ticket) : undefined);
	const fileQuery = useTicketFileQuery(projectId, slug, selectedFile);
	const workspaces = useWorkspaceQuery().data ?? [];
	const sessionsById = new Map<string, WorkspaceSession>();
	for (const workspace of workspaces) {
		if (workspace.id !== projectId) continue;
		for (const session of workspace.sessions) sessionsById.set(session.id, session);
	}
	const { markPlanDone, setArchived } = useTicketMutations();
	const [planOpen, setPlanOpen] = useState(false);
	const [reviewPlan, setReviewPlan] = useState<PlanView | null>(null);
	const [mergePlan, setMergePlan] = useState<PlanView | null>(null);
	const [actionError, setActionError] = useState<string | null>(null);

	const openFile = (next: string) =>
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId, slug },
			search: { file: next },
			replace: true,
		});
	const openSession = (sessionId: string) =>
		void navigate({ to: "/projects/$projectId/sessions/$sessionId", params: { projectId, sessionId } });

	if (ticketQuery.isError) {
		return (
			<p className="py-10 text-center text-xs text-passive" role="alert">
				{ticketErrorMessage(ticketQuery.error, t, "tickets.notFound")}
			</p>
		);
	}
	if (!ticket) return null;

	const status = getTicketStatusView(ticket, t);
	const groups = ticketFileGroups(ticket);
	const planningSession = ticket.planningSessionId ? sessionsById.get(ticket.planningSessionId) : undefined;
	const planningLive = planningSession !== undefined && liveSessionStatuses.has(planningSession.status);
	const planningActivity = planningSession ? getAgentActivityView(planningSession.activity, t) : undefined;
	const inArchive = isTicketInArchive(ticket);
	const runAction = async (action: () => Promise<unknown>, fallbackKey: "tickets.markDoneFailed" | "tickets.archiveFailed" | "tickets.reopenFailed") => {
		setActionError(null);
		try {
			await action();
		} catch (err) {
			setActionError(ticketErrorMessage(err, t, fallbackKey));
		}
	};
	const fileButtonClass = (active: boolean) =>
		cn(
			"flex w-full min-w-0 items-center gap-2 rounded-md px-2 py-1 text-left text-2xs text-foreground transition-colors hover:bg-interactive-hover",
			active && "bg-interactive-hover font-medium",
		);
	const fileContent = fileQuery.data;
	const parsed = fileContent ? splitFrontmatter(fileContent.content) : undefined;
	const selectedPlan = ticket.plans.find((plan) => plan.file === selectedFile);
	const fileWarning = selectedFile === "ticket.md" ? ticket.warning : selectedPlan?.warning;

	return (
		<div className="flex h-full min-h-0 bg-background text-foreground" data-testid="ticket-page">
			<aside className="flex w-72 shrink-0 flex-col border-r border-border-strong">
				<div className="flex flex-col gap-2 border-b border-border-strong px-4 py-3">
					<div className="flex items-start justify-between gap-2">
						<h1 className="min-w-0 text-base font-semibold leading-tight tracking-tight" title={ticket.title}>
							{ticket.title}
						</h1>
						<StatusPill label={status.label} tone={status.tone} breathe={status.breathe} leading="none" />
					</div>
					{ticket.brief ? <p className="text-2xs leading-relaxed text-muted-foreground">{ticket.brief}</p> : null}
					{ticket.warning ? (
						<p className="flex items-start gap-1.5 text-micro text-warning" role="status">
							<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
							<span>{ticket.warning}</span>
						</p>
					) : null}
				</div>
				<nav aria-label={t("tickets.filesAria")} className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-2 py-2">
					<p className="px-2 pb-1 font-mono text-micro uppercase tracking-wide-sm text-passive">{t("tickets.files")}</p>
					{groups.docs.map((doc) => (
						<button
							key={doc}
							type="button"
							aria-current={selectedFile === doc ? "true" : undefined}
							className={fileButtonClass(selectedFile === doc)}
							onClick={() => openFile(doc)}
						>
							<FileText aria-hidden="true" className="size-icon-2xs shrink-0 text-passive" />
							<span className="truncate">{doc}</span>
						</button>
					))}
					<p className="px-2 pb-1 pt-3 font-mono text-micro uppercase tracking-wide-sm text-passive">{t("tickets.plans")}</p>
					<div aria-label={t("tickets.plansAria", { title: ticket.title })} className="flex flex-col gap-0.5" role="list">
						{groups.plans.map(({ plan, kickoff }) => (
							<div key={plan.file} role="listitem">
								<PlanRow
									plan={plan}
									session={plan.sessionId ? sessionsById.get(plan.sessionId) : undefined}
									selectedFile={selectedFile}
									onOpenFile={openFile}
									onOpenSession={openSession}
									onReview={(target) => setReviewPlan(target)}
									onMerge={(target) => setMergePlan(target)}
									onMarkDone={(target) =>
										void runAction(
											() => markPlanDone.mutateAsync({ projectId, slug, plan: target.file }),
											"tickets.markDoneFailed",
										)
									}
								/>
								{kickoff ? (
									<button
										type="button"
										aria-current={selectedFile === kickoff ? "true" : undefined}
										className={cn(fileButtonClass(selectedFile === kickoff), "pl-9")}
										onClick={() => openFile(kickoff)}
										title={kickoff}
									>
										<FileText aria-hidden="true" className="size-icon-2xs shrink-0 text-passive" />
										<span className="truncate">{t("tickets.kickoff")}</span>
									</button>
								) : null}
							</div>
						))}
					</div>
					{planningSession ? (
						<button
							type="button"
							className={cn(fileButtonClass(false), "mt-3")}
							onClick={() => openSession(planningSession.id)}
						>
							<span
								aria-hidden="true"
								className={cn("size-dot-sm shrink-0 rounded-full", planningActivity?.indicatorClassName)}
							/>
							<span className="truncate">{t("tickets.planningSession")}</span>
							<span className="ml-auto truncate font-mono text-micro text-passive">{planningSession.title}</span>
						</button>
					) : null}
				</nav>
				<div className="flex flex-col gap-2 border-t border-border-strong px-3 py-3">
					{actionError ? (
						<p role="alert" className="text-micro text-error">
							{actionError}
						</p>
					) : null}
					<div className="flex items-center gap-2">
						{planningLive && planningSession ? (
							<TopbarButton variant="primary" onClick={() => openSession(planningSession.id)}>
								{t("tickets.openPlanningSession")}
							</TopbarButton>
						) : (
							<TopbarButton variant="primary" onClick={() => setPlanOpen(true)}>
								{t("tickets.planWithAgent")}
							</TopbarButton>
						)}
						<TopbarButton
							aria-label={inArchive ? t("tickets.reopenAria", { title: ticket.title }) : t("tickets.archiveAria", { title: ticket.title })}
							disabled={setArchived.isPending}
							onClick={() =>
								void runAction(
									() => setArchived.mutateAsync({ projectId, slug, archived: !inArchive }),
									inArchive ? "tickets.reopenFailed" : "tickets.archiveFailed",
								)
							}
						>
							{inArchive ? (
								<ArchiveRestore aria-hidden="true" className="size-icon-md" />
							) : (
								<Archive aria-hidden="true" className="size-icon-md" />
							)}
							{inArchive ? t("tickets.reopen") : t("tickets.archive")}
						</TopbarButton>
					</div>
				</div>
			</aside>
			<section className="flex min-w-0 flex-1 flex-col">
				<div className="flex h-toolbar shrink-0 items-center gap-2 border-b border-border-strong px-4">
					<span className="min-w-0 truncate font-mono text-2xs text-foreground">{selectedFile ?? ""}</span>
					<span className="min-w-0 flex-1" />
					{fileContent ? (
						<span className="font-mono text-micro text-passive">
							{t("tickets.fileModified", { time: formatTimeCompact(fileContent.modifiedAt) })}
						</span>
					) : null}
				</div>
				<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-6 py-5">
					{fileWarning ? (
						<p className="mb-4 flex items-start gap-1.5 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-2xs text-warning" role="status">
							<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
							<span>{fileWarning}</span>
						</p>
					) : null}
					{fileQuery.isError ? (
						<p className="text-2xs text-error" role="alert">
							{ticketErrorMessage(fileQuery.error, t, "tickets.fileLoadFailed")}
						</p>
					) : null}
					{parsed && parsed.fields.length > 0 ? (
						<dl
							aria-label={t("tickets.frontmatter")}
							className="mb-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 rounded-md border border-border bg-surface px-3 py-2 font-mono text-micro"
						>
							{parsed.fields.map(([key, value]) => (
								<div key={key} className="contents">
									<dt className="text-passive">{key}</dt>
									<dd className="min-w-0 truncate text-foreground">{value}</dd>
								</div>
							))}
						</dl>
					) : null}
					{parsed ? <MarkdownBody body={parsed.body} className="max-w-3xl text-sm text-foreground" testId="ticket-file-preview" /> : null}
				</div>
			</section>
			<PlanWithAgentSheet open={planOpen} onOpenChange={setPlanOpen} ticket={ticket} />
			{reviewPlan ? (
				<ReviewPlanSheet open onOpenChange={(open) => !open && setReviewPlan(null)} ticket={ticket} plan={reviewPlan} />
			) : null}
			{mergePlan ? (
				<MergeConfirmDialog open onOpenChange={(open) => !open && setMergePlan(null)} ticket={ticket} plan={mergePlan} />
			) : null}
		</div>
	);
}
```

`liveSessionStatuses` mirrors the daemon's `planningLive` (`backend/internal/service/ticket/status.go`, post-review: false for `terminated`, `merged`, `exited`), read from the session's derived status because the ticket status alone cannot tell the page whether the planner still accepts input.

- [ ] **Step 5: Write the route**

`frontend/src/renderer/routes/_shell.projects.$projectId_.tickets.$slug.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { TicketPage } from "../components/tickets/TicketPage";

type TicketSearch = { file?: string };

export const Route = createFileRoute("/_shell/projects/$projectId_/tickets/$slug")({
	validateSearch: (search: Record<string, unknown>): TicketSearch => ({
		file: typeof search.file === "string" && search.file !== "" ? search.file : undefined,
	}),
	component: TicketRoute,
});

function TicketRoute() {
	const { projectId, slug } = Route.useParams();
	const { file } = Route.useSearch();
	return <TicketPage projectId={projectId} slug={slug} file={file} />;
}
```

The route id follows `_shell.projects.$projectId_.settings.tsx:5` (`"/_shell/projects/$projectId_/settings"`), so the public path is `/projects/$projectId/tickets/$slug`. Running vitest (Step 6) makes `TanStackRouterVite` regenerate `routeTree.gen.ts`; commit that file with the route.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets src/renderer/i18n`
Expected: PASS.

- [ ] **Step 7: Run the full gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green; `git status` shows `routeTree.gen.ts` modified.

```bash
git add frontend/src/renderer/components/tickets/PlanRow.tsx frontend/src/renderer/components/tickets/TicketPage.tsx frontend/src/renderer/components/tickets/TicketPage.test.tsx "frontend/src/renderer/routes/_shell.projects.\$projectId_.tickets.\$slug.tsx" frontend/src/renderer/routeTree.gen.ts
git commit -m "feat(tickets): ticket page with file list and markdown preview"
```

### Task 7: Session ticket link and the ticket badge on cards and the topbar

**Files:**
- Modify: `frontend/src/renderer/types/workspace.ts:124-185`
- Modify: `frontend/src/renderer/hooks/useWorkspaceQuery.ts:84-115`
- Test: `frontend/src/renderer/hooks/useWorkspaceQuery.test.tsx`
- Create: `frontend/src/renderer/components/tickets/TicketBadge.tsx`
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:1037-1044` (after the intake issue chip)
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx`
- Modify: `frontend/src/renderer/components/ShellTopbar.tsx:159-167`
- Test: `frontend/src/renderer/components/ShellTopbar.test.tsx`

**Interfaces:**
- Consumes: `SessionTicketRef`, `ticketBadgeLabel` (Task 2); the generated `ControllersSessionView.ticket?: SessionTicketRef` (`schema.ts:2144`, `:2820-2825`); the route from Task 6.
- Produces:
  - `WorkspaceSession.ticket?: SessionTicketRef`
  - `TicketBadge({ projectId, ticket, className }: { projectId: string; ticket: SessionTicketRef; className?: string })` — a button labelled `slug · NN` (or `slug · plan`) that navigates to the ticket page with `search.file` preselected to the plan file, stopping propagation so the card underneath does not also open.

- [ ] **Step 1: Write the failing tests**

Add to `frontend/src/renderer/hooks/useWorkspaceQuery.test.tsx`, after the `maps each session's prs straight from the session list` case (line 196):

```tsx
	it("carries the session's ticket link through unchanged", async () => {
		respondWith({
			projects: { data: { projects: [{ id: "proj-1", name: "my-app", path: "/home/me/my-app" }] }, error: undefined },
			sessions: {
				data: {
					sessions: [
						{
							id: "sess-1",
							projectId: "proj-1",
							harness: "claude-code",
							status: "working",
							isTerminated: false,
							terminateOnPrMerge: false,
							createdAt: "2026-01-01T00:00:00Z",
							updatedAt: "2026-01-01T00:00:00Z",
							ticket: { slug: "search-page", role: "implementing", planFile: "plans/02-ui.md" },
						},
						{
							id: "sess-2",
							projectId: "proj-1",
							harness: "claude-code",
							status: "idle",
							isTerminated: false,
							terminateOnPrMerge: false,
							createdAt: "2026-01-01T00:00:00Z",
							updatedAt: "2026-01-01T00:00:00Z",
						},
					],
				},
				error: undefined,
			},
		});

		const { result } = renderHook(() => useWorkspaceQuery(), { wrapper });
		await waitFor(() => expect(result.current.isSuccess).toBe(true));

		expect(result.current.data?.[0].sessions[0].ticket).toEqual({
			slug: "search-page",
			role: "implementing",
			planFile: "plans/02-ui.md",
		});
		expect(result.current.data?.[0].sessions[1].ticket).toBeUndefined();
	});
```

`respondWith` and `wrapper` are the file's existing helpers (`useWorkspaceQuery.test.tsx:20-36`); the session fields above come from `ControllersSessionView` (`schema.ts:2100-2150`), so copy any required field the existing fixtures include that this list misses.

Add to `frontend/src/renderer/components/SessionsBoard.test.tsx`, inside `describe("SessionsBoard")`:

```tsx
	it("shows the ticket badge on a linked session card and opens the ticket page from it", async () => {
		workspaceQueryMock.mockReturnValue({
			data: [
				workspaceWithSessions([
					boardSession({
						id: "s-impl",
						title: "implement ui",
						status: "working",
						ticket: { slug: "search-page", role: "implementing", planFile: "plans/02-ui.md" },
					}),
				]),
			],
			isError: false,
			isSuccess: true,
		});

		renderBoard("p1");

		const badge = screen.getByRole("button", { name: "Open ticket search-page · 02" });
		expect(badge).toHaveTextContent("search-page · 02");
		await userEvent.click(badge);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: { file: "plans/02-ui.md" },
		});
		expect(navigateMock).not.toHaveBeenCalledWith(
			expect.objectContaining({ to: "/projects/$projectId/sessions/$sessionId" }),
		);
	});
```

Add to `frontend/src/renderer/components/ShellTopbar.test.tsx`, inside the first `describe` beside `does not synthesize branch text for branchless sessions` (line 188):

```tsx
	it("shows the planning ticket badge beside the branch", async () => {
		renderTopbar(sessionWith({ ticket: { slug: "search-page", role: "planning" } }));

		const badge = screen.getByRole("button", { name: "Open ticket search-page · plan" });
		expect(badge).toHaveTextContent("search-page · plan");
		await userEvent.click(badge);
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "proj-1", slug: "search-page" },
			search: { file: undefined },
		});
	});
```

(`ShellTopbar.test.tsx` already imports `userEvent`; if not, add `import userEvent from "@testing-library/user-event";`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useWorkspaceQuery.test.tsx src/renderer/components/SessionsBoard.test.tsx src/renderer/components/ShellTopbar.test.tsx`
Expected: FAIL. The workspace test gets `undefined` for `ticket`; the board and topbar tests find no badge button (and `boardSession({ ticket })` is a type error until Step 3, which vitest ignores).

- [ ] **Step 3: Add the field to the workspace model**

In `frontend/src/renderer/types/workspace.ts`, add after the import on line 1:

```ts
import type { SessionTicketRef } from "../lib/ticket-presentation";
```

and inside `WorkspaceSession` after `prs: PullRequestFacts[];` (line 184):

```ts
	ticket?: SessionTicketRef;
```

Re-export it beside the other type re-exports at the bottom of the file (`workspace.ts:296-297`):

```ts
export type { SessionTicketRef } from "../lib/ticket-presentation";
```

In `frontend/src/renderer/hooks/useWorkspaceQuery.ts`, inside the session mapping object after `prs: (session.prs ?? []).map(toPullRequestFacts),` (line 113):

```ts
						ticket: session.ticket
							? { slug: session.ticket.slug, role: session.ticket.role, planFile: session.ticket.planFile }
							: undefined,
```

- [ ] **Step 4: Write `TicketBadge`**

`frontend/src/renderer/components/tickets/TicketBadge.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { Ticket } from "lucide-react";
import type { MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketBadgeLabel, type SessionTicketRef } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";

export function TicketBadge({
	projectId,
	ticket,
	className,
}: {
	projectId: string;
	ticket: SessionTicketRef;
	className?: string;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const label = ticketBadgeLabel(ticket);
	const open = (event: MouseEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId, slug: ticket.slug },
			search: { file: ticket.planFile },
		});
	};
	return (
		<button
			type="button"
			aria-label={t("tickets.badgeAria", { label })}
			className={cn(
				"inline-flex max-w-branch-chip shrink-0 items-center gap-1 truncate rounded-sm bg-accent/12 px-1.5 py-0.5 font-mono text-micro text-accent transition-colors hover:bg-accent/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60",
				className,
			)}
			data-testid="session-ticket-badge"
			onClick={open}
			title={label}
		>
			<Ticket aria-hidden="true" className="size-icon-2xs shrink-0" />
			<span className="truncate">{label}</span>
		</button>
	);
}
```

The chip reuses the intake-issue chip's classes (`SessionsBoard.tsx:1038-1043`) so the two read as siblings.

- [ ] **Step 5: Render the badge on the card and in the topbar**

In `frontend/src/renderer/components/SessionsBoard.tsx`, import `TicketBadge` beside the other `./` imports:

```tsx
import { TicketBadge } from "./tickets/TicketBadge";
```

and inside `SessionCard`, after the `{issueId && (...)}` block (`SessionsBoard.tsx:1037-1044`), add:

```tsx
				{session.ticket ? (
					<TicketBadge className="self-start" projectId={session.workspaceId} ticket={session.ticket} />
				) : null}
```

In `frontend/src/renderer/components/ShellTopbar.tsx`, import `TicketBadge` beside the other `./` imports and, inside the worker lead (`ShellTopbar.tsx:159-167`), between the branch block and `<SessionStatusPill …/>`, add:

```tsx
							{session?.ticket ? <TicketBadge projectId={session.workspaceId} ticket={session.ticket} /> : null}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useWorkspaceQuery.test.tsx src/renderer/components/SessionsBoard.test.tsx src/renderer/components/ShellTopbar.test.tsx`
Expected: PASS.

- [ ] **Step 7: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/types/workspace.ts frontend/src/renderer/hooks/useWorkspaceQuery.ts frontend/src/renderer/hooks/useWorkspaceQuery.test.tsx frontend/src/renderer/components/tickets/TicketBadge.tsx frontend/src/renderer/components/SessionsBoard.tsx frontend/src/renderer/components/SessionsBoard.test.tsx frontend/src/renderer/components/ShellTopbar.tsx frontend/src/renderer/components/ShellTopbar.test.tsx
git commit -m "feat(tickets): ticket badge on session cards and the session topbar"
```

### Task 8: Ticket cards, the PLANNED column and the five-column board

**Files:**
- Create: `frontend/src/renderer/components/tickets/TicketCard.tsx`
- Test: `frontend/src/renderer/components/tickets/TicketCard.test.tsx`
- Create: `frontend/src/renderer/components/tickets/PlannedColumn.tsx`
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx` (imports; `SessionsBoard` body around lines 100-160 and 350-378)
- Modify: `frontend/src/renderer/components/BoardEmptyStates.tsx:34-86` (`ProjectBoardEmpty`)
- Modify: `frontend/src/renderer/components/SessionsBoard.test.tsx` (mocks at lines 9-72, lane count at 1274)
- Modify: `frontend/e2e/smoke-t0.spec.ts:154-164`

**Interfaces:**
- Consumes: `useTicketsQuery`, `TicketProject` (Task 3), `TicketWithProject`, `getTicketStatusView`, `isTicketInArchive`, `openTicketCount`, `planNumber` (Task 2), `PlanRow` (Task 6), `PlanWithAgentSheet`, `ReviewPlanSheet`, `MergeConfirmDialog`, `CreateTicketSheet` (Task 5), `MarkdownBody` (Task 4), `getAgentActivityView` (`lib/session-presentation.ts:61`), `dotGlow` (`theme/effects.ts:11`), `Plus` icon.
- Produces:
  - `TicketCard({ ticket, sessionsById }: { ticket: TicketWithProject; sessionsById: ReadonlyMap<string, WorkspaceSession> })`
  - `PlannedColumn({ tickets, projects, sessionsById, isError, supportsTickets, defaultProjectId }: { tickets: TicketWithProject[]; projects: readonly TicketProject[]; sessionsById: ReadonlyMap<string, WorkspaceSession>; isError: boolean; supportsTickets: boolean; defaultProjectId?: string })` — renders `<section data-testid="board-column" data-column="planned">`.
  - `ProjectBoardEmpty` gains `onNewTicket?: () => void`.

Design note: the spec's Plan 2 text suggested adding `planned` to `AttentionZone`. That type classifies *sessions* (`lib/session-presentation.ts:211-236`, `lib/command-palette.ts:240,349` sort sessions by it), and a ticket is not a session, so the column is a sibling grid cell rendered before `COLUMNS.map(...)` instead. `boardAttentionZoneOrder` stays four zones.

- [ ] **Step 1: Write the failing test**

`frontend/src/renderer/components/tickets/TicketCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkspaceSession } from "../../types/workspace";
import type { TicketWithProject } from "../../lib/ticket-presentation";
import { TooltipProvider } from "../ui/tooltip";

const { navigateMock, approveMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	approveMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));
vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({
			approveMerge: { mutateAsync: approveMutateAsync, isPending: false },
			planTicket: { mutateAsync: vi.fn(), isPending: false },
			reviewPlan: { mutateAsync: vi.fn(), isPending: false },
		}),
	};
});
vi.mock("./PlanWithAgentSheet", () => ({
	PlanWithAgentSheet: ({ open }: { open: boolean }) => (open ? <div data-testid="plan-sheet" /> : null),
}));
vi.mock("./ReviewPlanSheet", () => ({
	ReviewPlanSheet: ({ open }: { open: boolean }) => (open ? <div data-testid="review-sheet" /> : null),
}));

import { TicketCard } from "./TicketCard";

function ticket(overrides: Partial<TicketWithProject>): TicketWithProject {
	return {
		projectId: "p1",
		projectName: "app",
		slug: "search-page",
		title: "Search page",
		status: "draft",
		plans: [],
		files: ["ticket.md", "spec.md"],
		...overrides,
	};
}

function session(overrides: Partial<WorkspaceSession> & Pick<WorkspaceSession, "id">): WorkspaceSession {
	return {
		workspaceId: "p1",
		workspaceName: "app",
		title: overrides.id,
		provider: "claude-code",
		status: "working",
		updatedAt: "2026-09-18T10:00:00Z",
		prs: [],
		activity: { state: "active", lastActivityAt: "2026-09-18T10:00:00Z" },
		...overrides,
	};
}

function renderCard(data: TicketWithProject, sessions: WorkspaceSession[] = []) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>
				<TicketCard ticket={data} sessionsById={new Map(sessions.map((item) => [item.id, item]))} />
			</TooltipProvider>
		</QueryClientProvider>,
	);
}

beforeEach(() => {
	navigateMock.mockReset();
	approveMutateAsync.mockReset();
});

describe("TicketCard", () => {
	it("renders a draft with Plan with agent and opens the ticket page from the body", async () => {
		renderCard(ticket({}));
		expect(screen.getByText("Draft")).toBeInTheDocument();
		expect(screen.getByText("app")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Plan with agent" }));
		expect(screen.getByTestId("plan-sheet")).toBeInTheDocument();
		await userEvent.click(screen.getByTestId("ticket-card"));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "search-page" },
			search: {},
		});
	});

	it("shows the planning session's activity and an Open planning session action", async () => {
		renderCard(ticket({ status: "planning", planningSessionId: "s-plan" }), [
			session({ id: "s-plan", status: "working" }),
		]);
		expect(screen.getByText("Planning")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Open planning session" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-plan" },
		});
	});

	it("lists plans in order with their status and opens a plan's session", async () => {
		renderCard(
			ticket({
				status: "in_progress",
				plans: [
					{ file: "plans/02-ui.md", order: 2, title: "UI", status: "working", sessionId: "s-2" },
					{ file: "plans/01-index.md", order: 1, title: "Index", status: "merged", sessionId: "s-1" },
				],
			}),
			[session({ id: "s-2" })],
		);
		const rows = screen.getAllByTestId("ticket-plan-row");
		expect(rows.map((row) => row.getAttribute("data-plan-file"))).toEqual(["plans/01-index.md", "plans/02-ui.md"]);
		expect(screen.getByText("1/2 merged")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Open the session for UI" }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-2" },
		});
	});

	it("offers Review on an assigned plan", async () => {
		renderCard(
			ticket({
				status: "in_progress",
				plans: [{ file: "plans/01-index.md", order: 1, title: "Index", status: "in_review", sessionId: "s-1" }],
			}),
		);
		await userEvent.click(screen.getByRole("button", { name: "Review" }));
		expect(screen.getByTestId("review-sheet")).toBeInTheDocument();
	});

	it("asks for the user's confirmation and approves the merge", async () => {
		approveMutateAsync.mockResolvedValue({});
		renderCard(
			ticket({
				status: "awaiting_merge",
				plans: [
					{
						file: "plans/01-index.md",
						order: 1,
						title: "Index",
						status: "awaiting_merge",
						sessionId: "s-1",
						reviewerSessionId: "s-plan",
						mergeSummary: "All gates green, 12 files.",
					},
				],
			}),
		);
		expect(screen.getByText("Waiting for your confirmation")).toBeInTheDocument();
		expect(screen.getByText("All gates green, 12 files.")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Merge" }));
		const dialog = await screen.findByRole("dialog");
		expect(within(dialog).getByText("All gates green, 12 files.")).toBeInTheDocument();
		await userEvent.click(within(dialog).getByRole("button", { name: "Merge" }));
		await waitFor(() =>
			expect(approveMutateAsync).toHaveBeenCalledWith({ projectId: "p1", slug: "search-page", plan: "plans/01-index.md" }),
		);
	});

	it("flags an unreadable ticket", () => {
		renderCard(ticket({ warning: "ticket.md: malformed frontmatter" }));
		expect(screen.getByRole("status")).toHaveTextContent("ticket.md: malformed frontmatter");
	});
});
```

In the merge case the first click opens `MergeConfirmDialog`, whose footer holds the confirming `Merge` button (`ConfirmDialog` at `components/ConfirmDialog.tsx:82-90`); the test scopes the second click to the dialog.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketCard.test.tsx`
Expected: FAIL, cannot resolve `./TicketCard`.

- [ ] **Step 3: Write `TicketCard`**

`frontend/src/renderer/components/tickets/TicketCard.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { AlertTriangle } from "lucide-react";
import { useState, type KeyboardEvent, type MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { getAgentActivityView } from "../../lib/session-presentation";
import { getTicketStatusView, planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { MarkdownBody } from "../MarkdownBody";
import { MergeConfirmDialog } from "./MergeConfirmDialog";
import { PlanRow } from "./PlanRow";
import { PlanWithAgentSheet } from "./PlanWithAgentSheet";
import { ReviewPlanSheet } from "./ReviewPlanSheet";

const liveSessionStatuses = new Set<WorkspaceSession["status"]>(["working", "idle", "needs_input", "no_signal"]);

const footerButtonClass =
	"inline-flex h-control-md items-center rounded-sm px-2 text-2xs font-medium transition-colors hover:bg-interactive-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60";

export function TicketCard({
	ticket,
	sessionsById,
}: {
	ticket: TicketWithProject;
	sessionsById: ReadonlyMap<string, WorkspaceSession>;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const [planOpen, setPlanOpen] = useState(false);
	const [reviewPlan, setReviewPlan] = useState<PlanView | null>(null);
	const [mergePlan, setMergePlan] = useState<PlanView | null>(null);
	const status = getTicketStatusView(ticket, t);
	const planningSession = ticket.planningSessionId ? sessionsById.get(ticket.planningSessionId) : undefined;
	const planningLive = planningSession !== undefined && liveSessionStatuses.has(planningSession.status);
	const planningActivity = planningSession ? getAgentActivityView(planningSession.activity, t) : undefined;
	const showPlanningDot = ticket.status === "planning" && planningActivity !== undefined;
	const plans = [...ticket.plans].sort((left, right) => left.order - right.order || left.file.localeCompare(right.file));
	const awaiting = plans.filter((plan) => plan.status === "awaiting_merge");

	const openTicket = () =>
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: ticket.projectId, slug: ticket.slug },
			search: {},
		});
	const openSession = (sessionId: string) =>
		void navigate({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: ticket.projectId, sessionId },
		});
	const stop = (event: MouseEvent<HTMLButtonElement>) => event.stopPropagation();
	const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (event.currentTarget !== event.target) return;
		if (event.key !== "Enter" && event.key !== " ") return;
		event.preventDefault();
		openTicket();
	};

	return (
		<div
			className="group relative w-full cursor-pointer rounded-xl border border-border bg-surface text-left transition-[border-color,box-shadow] hover:border-border-strong hover:shadow-sm"
			data-testid="ticket-card"
			data-ticket-slug={ticket.slug}
			onClick={openTicket}
			onKeyDown={handleKeyDown}
			role="button"
			tabIndex={0}
		>
			<div className="flex flex-col gap-1.5 px-3.5 pb-2.5 pt-3">
				<div className="line-clamp-2 text-base font-semibold leading-tight tracking-tight text-foreground" title={ticket.title}>
					{ticket.title}
				</div>
				<div className="flex min-w-0 items-center gap-2 font-mono text-micro text-passive">
					<span className="truncate rounded-sm border border-border bg-surface px-1 py-px">{ticket.projectName}</span>
					<span
						className={cn("inline-flex min-w-0 items-center gap-1.5 truncate font-sans text-2xs font-medium", status.className)}
						style={showPlanningDot && planningActivity ? { color: planningActivity.tone } : undefined}
					>
						<span
							aria-hidden="true"
							className={cn(
								"size-dot-sm shrink-0 rounded-full",
								showPlanningDot && planningActivity ? planningActivity.indicatorClassName : "bg-current",
								!showPlanningDot && status.breathe && "animate-status-pulse",
							)}
						/>
						{status.label}
					</span>
				</div>
				{ticket.warning ? (
					<p className="flex items-start gap-1.5 text-micro text-warning" role="status">
						<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
						<span>{ticket.warning}</span>
					</p>
				) : null}
			</div>
			{plans.length > 0 ? (
				<>
					<div aria-hidden="true" className="mx-3.5 my-px h-px bg-border" />
					<div aria-label={t("tickets.plansAria", { title: ticket.title })} className="flex flex-col gap-0.5 px-2 py-1.5" role="list">
						{plans.map((plan) => (
							<div key={plan.file} role="listitem">
								<PlanRow
									plan={plan}
									session={plan.sessionId ? sessionsById.get(plan.sessionId) : undefined}
									onOpenSession={openSession}
									onReview={(target) => setReviewPlan(target)}
								/>
							</div>
						))}
					</div>
				</>
			) : null}
			{awaiting.map((plan) => (
				<div
					key={plan.file}
					className="mx-3.5 mb-2.5 flex flex-col gap-1.5 rounded-md border border-status-ready/40 bg-status-ready/10 px-3 py-2"
					data-testid="ticket-awaiting-merge"
				>
					<span className="text-2xs font-medium text-status-ready">
						{planNumber(plan.file)} {plan.title} · {t("tickets.plan.status.awaiting_merge")}
					</span>
					{plan.mergeSummary ? <MarkdownBody body={plan.mergeSummary} clamped testId={`merge-summary-${plan.order}`} /> : null}
					<button
						type="button"
						className="inline-flex h-control-md items-center self-start rounded-sm bg-status-ready px-2.5 text-2xs font-semibold text-primary-foreground transition-opacity hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
						onClick={(event) => {
							stop(event);
							setMergePlan(plan);
						}}
					>
						{t("tickets.merge")}
					</button>
				</div>
			))}
			<div aria-hidden="true" className="mx-3.5 my-px h-px bg-border" />
			<div className="flex items-center gap-1 px-2 py-1.5">
				{planningLive && planningSession ? (
					<button
						type="button"
						className={cn(footerButtonClass, "text-foreground")}
						onClick={(event) => {
							stop(event);
							openSession(planningSession.id);
						}}
					>
						<span aria-hidden="true" className={cn("mr-1.5 size-dot-sm rounded-full", planningActivity?.indicatorClassName)} />
						{t("tickets.openPlanningSession")}
					</button>
				) : (
					<button
						type="button"
						className={cn(footerButtonClass, "text-accent")}
						onClick={(event) => {
							stop(event);
							setPlanOpen(true);
						}}
					>
						{t("tickets.planWithAgent")}
					</button>
				)}
				<span className="flex-1" />
				<button
					type="button"
					className={cn(footerButtonClass, "text-passive hover:text-foreground")}
					onClick={(event) => {
						stop(event);
						openTicket();
					}}
				>
					{t("tickets.open")}
				</button>
			</div>
			<PlanWithAgentSheet open={planOpen} onOpenChange={setPlanOpen} ticket={ticket} />
			{reviewPlan ? (
				<ReviewPlanSheet open onOpenChange={(open) => !open && setReviewPlan(null)} ticket={ticket} plan={reviewPlan} />
			) : null}
			{mergePlan ? (
				<MergeConfirmDialog open onOpenChange={(open) => !open && setMergePlan(null)} ticket={ticket} plan={mergePlan} />
			) : null}
		</div>
	);
}
```

The card's `PlanRow` gets `onReview` but no `onMerge`: the awaiting block below the rows is the card's Merge affordance (spec §2.6 "the board card shows 'Waiting for your confirmation' with the summary and a Merge button"), so the row does not repeat it. "Waiting for your confirmation" is the ticket status line at the top of the card (`getTicketStatusView` for `awaiting_merge`); the block itself names the plan and reads `Awaiting your merge`, so the two lines do not repeat each other. Dialogs are rendered inside the card but Radix portals them to `body`; clicks inside a dialog do not bubble to the card's `onClick` because the portal content is not a DOM descendant of the card. If the merge test shows `navigateMock` being called on the dialog click, wrap the three dialog elements in `<div onClick={(event) => event.stopPropagation()}>` and record why in the task report.

- [ ] **Step 4: Write `PlannedColumn`**

`frontend/src/renderer/components/tickets/PlannedColumn.tsx`:

```tsx
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import type { TicketProject } from "../../hooks/useTicketsQuery";
import { openTicketCount, type TicketWithProject } from "../../lib/ticket-presentation";
import { dotGlow } from "../../theme/effects";
import type { WorkspaceSession } from "../../types/workspace";
import { CreateTicketSheet } from "./CreateTicketSheet";
import { TicketCard } from "./TicketCard";

const columnTone = "var(--color-status-in-review)";

export function PlannedColumn({
	tickets,
	projects,
	sessionsById,
	isError,
	supportsTickets,
	defaultProjectId,
}: {
	tickets: TicketWithProject[];
	projects: readonly TicketProject[];
	sessionsById: ReadonlyMap<string, WorkspaceSession>;
	isError: boolean;
	supportsTickets: boolean;
	defaultProjectId?: string;
}) {
	const { t } = useTranslation();
	const [createOpen, setCreateOpen] = useState(false);
	const count = openTicketCount(tickets);

	return (
		<section
			aria-label={t("tickets.columnAria")}
			className="flex min-w-0 flex-col overflow-hidden"
			data-column="planned"
			data-testid="board-column"
		>
			<div className="flex h-12 shrink-0 items-center gap-2 px-3">
				<span className="size-dot-sm rounded-full" style={{ background: columnTone, boxShadow: dotGlow(columnTone) }} />
				<span className="font-mono text-2xs font-medium uppercase tracking-wide-sm text-status-in-review">
					{t("tickets.column")}
				</span>
				<span aria-label={t("tickets.columnCountAria", { count })} className="ml-auto font-mono text-2xs leading-none text-passive">
					{count}
				</span>
				<button
					type="button"
					aria-label={t("tickets.create")}
					className="inline-flex size-control-md items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 disabled:opacity-40"
					disabled={!supportsTickets}
					onClick={() => setCreateOpen(true)}
					title={t("tickets.create")}
				>
					<Plus aria-hidden="true" className="size-icon-sm" />
				</button>
			</div>
			<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-3">
				<div className="flex min-h-full flex-col gap-2.5">
					{!supportsTickets ? (
						<p className="px-1 text-2xs leading-relaxed text-passive">{t("tickets.needsRepo")}</p>
					) : isError && tickets.length === 0 ? (
						<p className="px-1 text-2xs leading-relaxed text-error" role="alert">
							{t("tickets.loadFailed")}
						</p>
					) : tickets.length === 0 ? (
						<div className="px-1 text-2xs leading-relaxed text-passive">
							<p className="font-medium text-muted-foreground">{t("tickets.empty")}</p>
							<p>{t("tickets.emptyHint")}</p>
						</div>
					) : (
						tickets.map((ticket) => (
							<TicketCard key={`${ticket.projectId}:${ticket.slug}`} ticket={ticket} sessionsById={sessionsById} />
						))
					)}
				</div>
			</div>
			<CreateTicketSheet open={createOpen} onOpenChange={setCreateOpen} projects={projects} defaultProjectId={defaultProjectId} />
		</section>
	);
}
```

The header mirrors `ZoneColumn` (`SessionsBoard.tsx:513-530`): same `h-12`, dot, mono uppercase title, trailing count, plus the one `+` control the spec asks for.

- [ ] **Step 5: Wire the board**

In `frontend/src/renderer/components/SessionsBoard.tsx`:

1. Imports (beside the other hook and component imports):

```tsx
import { useTicketsQuery } from "../hooks/useTicketsQuery";
import { isTicketInArchive } from "../lib/ticket-presentation";
import { PlannedColumn } from "./tickets/PlannedColumn";
```

2. Inside `SessionsBoard`, after `const sessions = workspaces.flatMap((w) => workerSessions(w.sessions));` (line 105), add:

```tsx
	const ticketProjects = workspaces
		.filter((w) => w.kind === "single_repo")
		.map((w) => ({ id: w.id, name: w.name }));
	const ticketsQuery = useTicketsQuery(ticketProjects);
	const openTickets = ticketsQuery.tickets.filter((ticket) => !isTicketInArchive(ticket));
	const supportsTickets = projectId ? ticketProjects.length > 0 : true;
	const sessionsById = new Map<string, WorkspaceSession>();
	for (const w of workspaces) {
		for (const s of w.sessions) sessionsById.set(s.id, s);
	}
```

3. Change `showProjectEmpty` (line 160) to also require no open tickets:

```tsx
	const showProjectEmpty =
		projectId !== undefined && isLoaded && workspaces.length > 0 && sessions.length === 0 && openTickets.length === 0;
```

4. Column grid (lines 363-378): change `grid-cols-4` to `grid-cols-5` and `min-w-[64rem]` to `min-w-[80rem]`, and render the planned column first:

```tsx
						<div className="relative grid h-full min-w-[80rem] grid-cols-5 divide-x divide-border-strong xl:min-w-0">
							<div
								aria-hidden="true"
								className="pointer-events-none absolute inset-x-0 top-12 z-10 border-t border-border-strong"
							/>
							<PlannedColumn
								key={`${projectId ?? "all"}:planned`}
								tickets={openTickets}
								projects={ticketProjects}
								sessionsById={sessionsById}
								isError={ticketsQuery.isError}
								supportsTickets={supportsTickets}
								defaultProjectId={projectId}
							/>
							{COLUMNS.map((col) => (
```

5. `ProjectBoardEmpty` (line 352-359) gets `onNewTicket`:

```tsx
					<ProjectBoardEmpty
						hasOrchestrator={orchestrator !== undefined}
						isSpawning={isSpawning}
						isProjectRestarting={isProjectRestarting}
						onNewTask={() => projectId && requestNewTask(projectId)}
						onNewTicket={supportsTickets ? () => setCreateTicketOpen(true) : undefined}
						onOpenOrchestrator={() => void openOrchestrator()}
						spawnError={visibleSpawnError}
					/>
```

with `const [createTicketOpen, setCreateTicketOpen] = useState(false);` beside the other `useState` calls and, at the end of the returned tree next to `RestoreUnavailableDialog`:

```tsx
			<CreateTicketSheet
				open={createTicketOpen}
				onOpenChange={setCreateTicketOpen}
				projects={ticketProjects}
				defaultProjectId={projectId}
			/>
```

(import `CreateTicketSheet` from `./tickets/CreateTicketSheet`).

In `frontend/src/renderer/components/BoardEmptyStates.tsx`, add `onNewTicket?: () => void` to `ProjectBoardEmpty`'s props and, after the `New task` button (line 70-73):

```tsx
					{onNewTicket ? (
						<TopbarButton aria-label={t("tickets.create")} disabled={isProjectRestarting} onClick={onNewTicket}>
							<Plus className="size-icon-md" aria-hidden="true" />
							{t("tickets.create")}
						</TopbarButton>
					) : null}
```

- [ ] **Step 6: Update the board tests and the e2e column count**

In `frontend/src/renderer/components/SessionsBoard.test.tsx`:

- add a mock beside the `useWorkspaceQuery` mock (line 34-37):

```tsx
vi.mock("../hooks/useTicketsQuery", () => ({
	ticketsQueryRoot: ["tickets"],
	useTicketsQuery: () => ({ tickets: [], isError: false, isSuccess: true }),
}));
```

- change `expect(laneScrollers).toHaveLength(4);` (line 1274) to `toHaveLength(5)`.
- add a case:

```tsx
	it("renders the planned column first with its create control", () => {
		workspaceQueryMock.mockReturnValue({
			data: [{ ...workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working" })]), kind: "single_repo" }],
			isError: false,
			isSuccess: true,
		});

		renderBoard("p1");

		const columns = screen.getAllByTestId("board-column");
		expect(columns[0]).toHaveAttribute("data-column", "planned");
		expect(within(columns[0]).getByText("Planned")).toBeInTheDocument();
		expect(within(columns[0]).getByRole("button", { name: "New ticket" })).toBeEnabled();
		expect(within(columns[0]).getByText("No tickets yet")).toBeInTheDocument();
	});

	it("tells scratch projects that tickets need a repository", () => {
		workspaceQueryMock.mockReturnValue({
			data: [{ ...workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working" })]), kind: "scratch" }],
			isError: false,
			isSuccess: true,
		});

		renderBoard("p1");

		const planned = screen.getAllByTestId("board-column")[0];
		expect(within(planned).getByText("Tickets need a single-repository project.")).toBeInTheDocument();
		expect(within(planned).getByRole("button", { name: "New ticket" })).toBeDisabled();
	});
```

In `frontend/e2e/smoke-t0.spec.ts:157`, change `toHaveCount(4)` to `toHaveCount(5)` and add before the `working` assertion:

```ts
	await expect(page.locator('[data-testid="board-column"][data-column="planned"]')).toContainText("Planned");
```

`frontend/e2e/smoke-board.spec.ts:11` and `smoke-sessions.spec.ts:15` select by `data-column`, so they need no change. The e2e suite is not part of this plan's gate (it needs the Playwright browser bundle); the edit keeps it truthful.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets src/renderer/components/SessionsBoard.test.tsx src/renderer/i18n`
Expected: PASS.

- [ ] **Step 8: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/components/tickets/TicketCard.tsx frontend/src/renderer/components/tickets/TicketCard.test.tsx frontend/src/renderer/components/tickets/PlannedColumn.tsx frontend/src/renderer/components/SessionsBoard.tsx frontend/src/renderer/components/SessionsBoard.test.tsx frontend/src/renderer/components/BoardEmptyStates.tsx frontend/e2e/smoke-t0.spec.ts
git commit -m "feat(tickets): PLANNED board column with ticket cards"
```

### Task 9: Done and archived tickets in the Archive bar

**Files:**
- Create: `frontend/src/renderer/components/tickets/ArchiveTicketItem.tsx`
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:139-142` (`archived`), `:381-431` (archive bar)
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx`

**Interfaces:**
- Consumes: `isTicketInArchive`, `getTicketStatusView` (Task 2), `useTicketMutations`, `ticketErrorMessage` (Task 3), `Tooltip*` (`components/ui/tooltip.tsx`), `RotateCcw` icon, the `ArchiveRestoreButton` look (`SessionsBoard.tsx:1117-1145`).
- Produces: `ArchiveTicketItem({ ticket }: { ticket: TicketWithProject })` — a non-interactive card with the ticket title, project chip, status label and a `Reopen` control that calls `setArchived({ archived: false })` and then opens the ticket page.

- [ ] **Step 1: Write the failing test**

Add to `frontend/src/renderer/components/SessionsBoard.test.tsx`. First widen the `useTicketsQuery` mock added in Task 8 so cases can feed tickets:

```tsx
const { ticketsQueryMock } = vi.hoisted(() => ({
	ticketsQueryMock: vi.fn(() => ({ tickets: [] as unknown[], isError: false, isSuccess: true })),
}));

vi.mock("../hooks/useTicketsQuery", () => ({
	ticketsQueryRoot: ["tickets"],
	useTicketsQuery: () => ticketsQueryMock(),
}));

vi.mock("../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({
			setArchived: { mutateAsync: setArchivedMock, isPending: false },
			createTicket: { mutateAsync: vi.fn(), isPending: false },
			planTicket: { mutateAsync: vi.fn(), isPending: false },
			reviewPlan: { mutateAsync: vi.fn(), isPending: false },
			approveMerge: { mutateAsync: vi.fn(), isPending: false },
			markPlanDone: { mutateAsync: vi.fn(), isPending: false },
		}),
	};
});
```

with `setArchivedMock: vi.fn()` added to the first `vi.hoisted` block and reset in `beforeEach` (`ticketsQueryMock.mockReset().mockReturnValue({ tickets: [], isError: false, isSuccess: true });`). Then the case:

```tsx
	it("lists done and archived tickets in the archive bar and reopens them", async () => {
		setArchivedMock.mockResolvedValue({});
		workspaceQueryMock.mockReturnValue({
			data: [{ ...workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working" })]), kind: "single_repo" }],
			isError: false,
			isSuccess: true,
		});
		ticketsQueryMock.mockReturnValue({
			tickets: [
				{ projectId: "p1", projectName: "radic", slug: "open-one", title: "Open one", status: "ready", plans: [], files: [] },
				{ projectId: "p1", projectName: "radic", slug: "shipped", title: "Shipped", status: "done", plans: [], files: [] },
				{ projectId: "p1", projectName: "radic", slug: "dropped", title: "Dropped", status: "archived", plans: [], files: [] },
			],
			isError: false,
			isSuccess: true,
		});

		renderBoard("p1");

		const planned = screen.getAllByTestId("board-column")[0];
		expect(within(planned).getByText("Open one")).toBeInTheDocument();
		expect(within(planned).queryByText("Shipped")).not.toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: /archive/i }));
		const archive = screen.getByRole("list", { name: "Archived sessions" });
		expect(within(archive).getByText("Shipped")).toBeInTheDocument();
		expect(within(archive).getByText("Dropped")).toBeInTheDocument();

		await userEvent.click(within(archive).getByRole("button", { name: "Reopen ticket Dropped" }));
		await waitFor(() => expect(setArchivedMock).toHaveBeenCalledWith({ projectId: "p1", slug: "dropped", archived: false }));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: "p1", slug: "dropped" },
			search: {},
		});
	});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test.tsx`
Expected: FAIL: no archive toggle is rendered because `archived.length` counts sessions only.

- [ ] **Step 3: Write `ArchiveTicketItem`**

`frontend/src/renderer/components/tickets/ArchiveTicketItem.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { RotateCcw } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { getTicketStatusView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";

export function ArchiveTicketItem({ ticket }: { ticket: TicketWithProject }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { setArchived } = useTicketMutations();
	const [error, setError] = useState<string | null>(null);
	const status = getTicketStatusView(ticket, t);
	const reopen = async () => {
		setError(null);
		try {
			await setArchived.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, archived: false });
			void navigate({
				to: "/projects/$projectId/tickets/$slug",
				params: { projectId: ticket.projectId, slug: ticket.slug },
				search: {},
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.reopenFailed"));
		}
	};
	return (
		<div
			className="group relative w-full rounded-xl border border-border bg-surface text-left"
			data-testid="archive-ticket-card"
			data-ticket-slug={ticket.slug}
			role="listitem"
		>
			<div className="absolute right-2 top-1.5 z-10">
				<Tooltip>
					<TooltipTrigger asChild>
						<button
							aria-label={t("tickets.reopenAria", { title: ticket.title })}
							className="grid size-control-board-sm shrink-0 place-items-center rounded-md text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50 disabled:cursor-not-allowed disabled:opacity-35"
							disabled={setArchived.isPending}
							onClick={() => void reopen()}
							type="button"
						>
							<RotateCcw className={cn("size-icon-md", setArchived.isPending && "animate-spin")} aria-hidden="true" />
						</button>
					</TooltipTrigger>
					<TooltipContent side="top">{t("tickets.reopen")}</TooltipContent>
				</Tooltip>
			</div>
			<div className="flex flex-col gap-1.5 px-3.5 pb-2.5 pt-3 pr-8">
				<div className="line-clamp-2 text-base font-semibold leading-tight tracking-tight text-foreground" title={ticket.title}>
					{ticket.title}
				</div>
				<div className="flex min-w-0 items-center gap-2 font-mono text-micro text-passive">
					<span className="truncate rounded-sm border border-border bg-surface px-1 py-px">{ticket.projectName}</span>
					<span className={cn("font-sans text-2xs font-medium", status.className)}>{status.label}</span>
				</div>
			</div>
			{error ? (
				<div className="border-t border-border px-2 py-1.5 text-2xs text-destructive" role="alert">
					{error}
				</div>
			) : null}
		</div>
	);
}
```

- [ ] **Step 4: Merge tickets into the archive bar**

In `frontend/src/renderer/components/SessionsBoard.tsx`:

1. Import `ArchiveTicketItem` from `./tickets/ArchiveTicketItem`.
2. After the `openTickets` line added in Task 8, add:

```tsx
	const archivedTickets = ticketsQuery.tickets.filter(isTicketInArchive);
```

3. Replace the two `archived.length` checks that gate and count the bar (`SessionsBoard.tsx:381` `{archived.length > 0 && (` and `:387` `aria-label={t("shell.archiveSessionsAria", { count: archived.length })}` and `:404` `{archived.length}`) with `archivedCount`, defined next to `archivedTickets`:

```tsx
	const archivedCount = archived.length + archivedTickets.length;
```

4. Inside the expanded list (`SessionsBoard.tsx:412-423`), after the `archived.map(...)` block, add:

```tsx
							{archivedTickets.map((ticket) => (
								<ArchiveTicketItem key={`${ticket.projectId}:${ticket.slug}`} ticket={ticket} />
							))}
```

The list keeps its `aria-label={t("shell.archivedSessions")}` so the existing archive tests and the e2e selectors stay valid.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test.tsx src/renderer/i18n`
Expected: PASS.

- [ ] **Step 6: Run the gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: all green.

```bash
git add frontend/src/renderer/components/tickets/ArchiveTicketItem.tsx frontend/src/renderer/components/SessionsBoard.tsx frontend/src/renderer/components/SessionsBoard.test.tsx
git commit -m "feat(tickets): done and archived tickets in the archive bar with Reopen"
```

### Task 10: Whole-branch gates and real-app verification

**Files:**
- Create: `docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md`

**Interfaces:**
- Consumes: everything above; the daemon routes from plan 1.
- Produces: the report the reviewing session reads.

- [ ] **Step 1: Run every gate from a clean tree**

```bash
cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts
cd .. && git status --short
```

Expected: all green; `git status` shows nothing but the report you are about to write. If `packages/terminal/package-lock.json` shows as modified, `git checkout -- packages/terminal/package-lock.json`.

- [ ] **Step 2: Start the desktop app with a clean environment**

Follow the memory notes `scrub-claude-env-before-running-operator-dev` and `verify-operator-desktop-through-daemon-api-and-mux`. From `frontend/`:

```bash
env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') -u OPERATOR_DATA_DIR -u OPERATOR_RUN_FILE -u OPERATOR_PORT npm run tauri:dev
```

Expected: the dev daemon answers on `127.0.0.1:3002` (`curl -s http://127.0.0.1:3002/readyz`), and `ps eww -o command= -p <daemon pid> | tr ' ' '\n' | grep -c '^CLAUDE'` prints `0`. If port 3002 is already served by another dev daemon, stop; do not touch the installed app's daemon on 3001.

- [ ] **Step 3: Create a ticket and plans through the API**

Use a throwaway git repository registered as a `single_repo` project (the plan-1 report's recipe at `docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md`, "Curl verification against a real daemon"). With `P` set to that project's id:

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/projects/$P/tickets -H 'content-type: application/json' -d '{"title":"Board smoke","brief":"UI verification"}'
curl -s -X PUT "http://127.0.0.1:3002/api/v1/projects/$P/tickets/board-smoke/file?path=plans/01-first.md" -H 'content-type: application/json' -d '{"content":"---\ntitle: \"First\"\n---\n\n# First\n\nA plan.\n"}'
curl -s -X PUT "http://127.0.0.1:3002/api/v1/projects/$P/tickets/board-smoke/file?path=plans/01-first.kickoff.md" -H 'content-type: application/json' -d '{"content":"Kickoff body\n"}'
curl -s http://127.0.0.1:3002/api/v1/projects/$P/tickets | jq '.tickets[] | {slug, status, files, plans: [.plans[] | {file, status, kickoffFile}]}'
```

Expected: `status: "ready"`, one plan `todo` with `kickoffFile: "plans/01-first.kickoff.md"`.

- [ ] **Step 4: Verify the board in the window**

Capture the Operator window with `screencapture -x -l<CGWindowID> board.png` (window id via the `CGWindowListCopyWindowInfo` Swift snippet from the memory note, filtered by `pgrep -f target/debug/operator`). The PLANNED column must be the leftmost column, show `Board smoke`, the project chip, `Ready`, and the row `01 First · To do`; the header count must read `1`. Then write a second plan file with `PUT` and confirm, without touching the window, that the card gains the row within a few seconds (this is the `tickets_changed` SSE path). Save both screenshots for the report.

- [ ] **Step 5: Verify the planning session badge**

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/projects/$P/tickets/board-smoke/plan -H 'content-type: application/json' -d '{"harness":"claude-code","model":"claude-haiku-4-5-20251001"}' | jq '{id, ticket}'
```

Expected: 201 with `ticket: {slug: "board-smoke", role: "planning"}`. Screenshot again: the ticket card now reads `Planning` with a live dot and the footer says `Open planning session`; the session's own card in the IDLE / WORKING column carries the badge `board-smoke · plan`. Kill the session afterwards (`POST /api/v1/sessions/<id>/kill`) so no agent keeps running.

- [ ] **Step 6: Ticket page**

The window cannot be clicked from this session (memory note: the computer-use MCP refuses the Operator window and keystrokes are blocked), so the ticket page is verified by the Vitest suite in Task 6 and by you opening the ticket from the board yourself when you review the screenshots. If you find a way to navigate the window (not known at the time of writing), add a screenshot of `/projects/<id>/tickets/board-smoke` showing the file list, the plan rows and the rendered `spec.md`; otherwise write "ticket page: not verified in the window" in the report.

- [ ] **Step 7: Stop and clean up**

Kill the dev shell's process group (`ps -o pgid= -p <npm pid>`), confirm no `pty-host` from the dev data dir survives (`pgrep -f "pty-host .* /Users/omaraly/.operator/dev/data"`), and confirm `curl -s http://127.0.0.1:3001/readyz` still answers (the installed app's daemon was never touched). There is no project delete route (`schema.ts:580-582` lists only `get` and `put` for `/api/v1/projects/{id}`), so the throwaway project stays registered in `~/.operator/dev/data`; record its id and path in the report so the reviewer can remove the folder.

- [ ] **Step 8: Write the report and commit**

`docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md`: commit list, gate output summary, the curl transcript, the screenshot file names and what each shows, every deviation from this plan with the reason (for example a prop renamed to satisfy the linter, a test narrowed with `within`), and anything left undone.

```bash
git add docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md
git commit -m "docs(tickets): board and ticket page implementation report"
git push -u origin feat/planning-tickets-board
```

Do not merge; the reviewing session merges after its own review.

---

## Self-review

**Spec coverage.**
- §3.1 column, header count, `+`, card (title, project chip, status line with planning dot, `N/M merged`, plan rows with pills and activity dots, click-through, footer actions), empty state, scratch hint → Task 8. The spec's "empty state follows `BoardEmptyStates`" is read as: the column's own empty copy plus a `New ticket` action on `ProjectBoardEmpty`.
- §2.6 statuses `reviewing`, `awaiting_merge`, `merging` on plan rows → Tasks 1-2; "Waiting for your confirmation" with summary and Merge → Task 8 card, Task 5 dialog, Task 6 page row; Review with reviewer choice → Task 5 sheet, Tasks 6 and 8 buttons.
- §3.3 without editing: two panes, file list with plans and status pills, planning session entry with dot, Plan with agent and archive at the bottom, preview styled like `ReviewMarkdownBody`, files reload on SSE → Tasks 3, 4, 6. Edit / Split / save / dirty bar are plan 3.
- §3.4 badge on card and topbar, opening the ticket page with the file preselected → Task 7.
- §3.5 archive bar with Reopen → Task 9.
- §3.6 catalogue and coverage test → Task 1.
- §4 warning badge on the card and the parse warning above the file → Tasks 6 and 8. "Linked session deleted: plan shows terminated with Reassign" — Reassign is an assign action and belongs to plan 3; the row shows `Terminated` and `Session no longer exists`.
- §5 frontend: status mapping (Task 2), card render per status (Task 8), create and plan sheets (Task 5), i18n coverage (Task 1). Drag and editor tests are plan 3.
- §6 Plan 2 deliverables: hooks (Task 3), column and card (Task 8), create and plan sheets (Task 5), route with preview (Task 6), badge (Task 7), archive entries (Task 9), catalogue (Task 1), real-app acceptance (Task 10). The deliverable "a fifth zone `planned` added to `boardAttentionZoneOrder`" is deliberately replaced by a sibling grid cell; see the design note in Task 8.

**Placeholder scan.** Every task carries its code and tests. The remaining conditional instructions (openapi-fetch rejecting a `body` key, a dialog click bubbling to the card) each name the exact change to make, not a TBD. Task 10 Step 6 states the known limitation of driving the Tauri window instead of pretending it can be clicked.

**Type consistency.** `TicketWithProject`, `TicketProject`, `PlanRowProps` (no `ticket` prop), `useTicketMutations()` members (`createTicket`, `planTicket`, `reviewPlan`, `approveMerge`, `markPlanDone`, `setArchived`) and their variable shapes (`CreateTicketInput`, `PlanTicketInput`, `ReviewPlanInput`, `PlanRef`, `SetArchivedInput`) are used with the same names in Tasks 3, 5, 6, 8 and 9. Navigation to the ticket route always passes `search` (`{}` or `{ file }`) so the typed router accepts it. `ticketErrorMessage(error, t, fallbackKey)` has the same three-argument shape everywhere.
