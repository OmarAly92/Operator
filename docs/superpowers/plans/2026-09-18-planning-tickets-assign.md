# Planning Tickets: Assign and Edit Implementation Plan (plan 3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag a ticket plan onto the board or a sidebar project to start its implementing session after a confirm sheet that shows the daemon's dry-run warnings, edit ticket files in the app with CodeMirror (Edit / Preview / Split, Cmd+S, stale-file bar), and set per-project ticket role defaults in project settings.

**Architecture:** Frontend only. A `TicketDndProvider` (dnd-kit `DndContext` plus a small React context) wraps the shell content in `_shell.tsx` so plan rows on ticket cards can be dropped on the IDLE / WORKING column and on sidebar project headers; the provider owns the `AssignPlanSheet`, which runs `POST …/assign?dryRun=1` on open, renders the warnings with human copy, and submits with `force` (and a `kill` of the live session first for `plan_assigned`). The ticket page's right pane becomes a `TicketEditor` that owns a draft, saves with `ifUnmodifiedSince`, shows the Reload / Keep mine bar on `409 TICKET_FILE_STALE` and on an SSE reload while dirty, and hosts CodeMirror through a thin `CodeMirrorField`. Project settings gain a "Tickets" section bound to `ProjectConfig.tickets`, saved through the existing `PUT /api/v1/projects/{id}`.

**Tech Stack:** React 19, TanStack Router (hash history, `useBlocker`), TanStack Query, openapi-fetch, `@dnd-kit/core` 6.3.1 (installed, unused until now), CodeMirror 6 (`@codemirror/state` 6.7.5, `@codemirror/view` 6.43.12, `@codemirror/lang-markdown` 6.5.2, `@codemirror/commands` 6.11.1, verified with `npm view <pkg> version` on 2026-09-18), react-markdown + remark-gfm (existing `MarkdownBody`), `radix-ui` `RadioGroup` (existing `settings-segment` pattern), i18next flat catalogues in 8 locales, Vitest + Testing Library.

**Spec:** `docs/superpowers/specs/2026-09-18-planning-tickets-design.md` — §2.4 (assign, dry run, warnings, `force`), §3.2 (drag and drop), §3.3 editing half, §4 (Reassign, `ticket_not_on_default_branch`), §5 frontend Vitest bullets, §6 "Plan 3".

**Baseline commit:** `origin/development` at `7622f4e4c` (plan 2 merged as `c980f21fc`; the plan-3 authoring prompt is the only later commit). Run `git fetch origin` and branch from `origin/development`.

**Where the shipped code overrules the spec (verified 2026-09-18):**

- The daemon emits **five** assign warnings, not four: `plan_order`, `ticket_repo_dirty`, `ticket_not_on_default_branch`, `planning_active`, `plan_assigned` (`backend/internal/service/ticket/service.go:543-564`). The spec's §2.4 list omits `ticket_not_on_default_branch` and the prompt omitted `plan_order`; the UI must render all five.
- `force: true` does **not** terminate the live session for `plan_assigned`; `Assign` only spawns another attempt (`service.go:566-621`). "Terminate and start" therefore calls the existing `POST /api/v1/sessions/{sessionId}/kill` (the route `useTerminateSession.ts:60-62` uses) and then assigns with `force: true`, as spec §6 "Plan 3" says.
- Status codes: dry run → `200 {warnings}`; warnings and no `force` → `409 TICKET_ASSIGN_BLOCKED` with `details.warnings: string[]`; success → `201 {warnings, session}` (`service.go:576-581`, `controllers/tickets.go:242-254`). `PUT …/file` with an older `ifUnmodifiedSince` → `409 TICKET_FILE_STALE` with `details.modifiedAt` (`service.go:316-320`); the comparison truncates to whole seconds.
- The branch is `opr/<slug>-<NN>` with `-<attempt>` appended from the second assignment of the same plan (`service.go:535-541`, `589-594`). The sheet shows `opr/<slug>-<NN>` and says the daemon may add a suffix; the session card shows the real branch afterwards.
- The `{plan}` route segment is the **bare** file name (`dto.go:1510-1512`); `planParam()` in `useTicketMutations.ts:42-44` already strips `plans/`.
- The board has **no** dashed empty-lane highlight today (`grep -rn dashed frontend/src/renderer/components/SessionsBoard.tsx` → nothing; the only dashed borders are `CreateProjectFlow.tsx:581` and `SessionInspector.tsx:1721`). Task 7 designs one from the board's tokens.
- `Sidebar` is rendered by `_shell.tsx:694`, the board by the `<Outlet />` at `_shell.tsx:711`; they share no ancestor below `SidebarProvider` (`_shell.tsx:674-757`). The `DndContext` therefore wraps `SidebarProvider`.
- The spec's editor dependency list names `@codemirror/language`; it arrives transitively with `@codemirror/lang-markdown` and is not imported directly. `@codemirror/commands` is added instead for `defaultKeymap`, `history` and `Mod-s`.

**Blockers for the daemon:** none. Everything plan 3 needs exists.

## Global Constraints

- Branch `feat/planning-tickets-assign` from `origin/development`; never commit to `master`. Worktrees live outside the checkout (`../Operator-planning-tickets-assign`), never under `.worktrees/` or `.claude/worktrees/`.
- No comments in new code (user rule). Match the surrounding code's tab indentation, double quotes, and import order.
- Read `DESIGN.md` first; build UI from the shipped patterns (`settingsDialog*Class`, `settings-field-label`, `settings-segment`, `settings-row-*`, `TopbarButton`, `ConfirmDialog`, `components/ui/*`). Never use `text-accent` or `bg-accent/*` (they resolve to `rgba(255,255,255,0.06)` in this theme); use `text-foreground`, `text-muted-foreground`, `text-passive`, `text-status-*`, `bg-status-*/15`, bordered chips.
- Lesson 1: the `{plan}` path param is the bare file name. Every new mutation that hits `/plans/{plan}/…` uses `planParam(input.plan)` and has a unit test asserting `params.path.plan === "01-daemon.md"` for input `plans/01-daemon.md`.
- Lesson 2: React synthetic events bubble through portals. Nothing new renders a dialog inside `TicketCard` (the assign sheet lives in `TicketDndProvider`); drag handles and row actions inside the card call `stopPropagation` on click and pointerdown; card tests assert `navigateMock` was not called after using a row action.
- Lesson 3: no accent tokens (above).
- Lesson 4: every user-visible string goes through `t()` with keys added to all eight catalogues (`frontend/src/renderer/i18n/{en,de,es,fr,ja,ko,pt-BR,zh-CN}.json`) in Task 1, before any component work, so the renderer is never relaunched after an i18n edit. `renderer-coverage.test.ts` and `instance.test.ts` must pass after every task.
- Lesson 5: green unit tests are not proof. Task 12 verifies in the real renderer against an isolated daemon (never the user's daemons on ports 3001 and 3002) using the recipe from `docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md` §"Planner review › Live verification".
- No changes under `backend/`. If something is missing, stop and write it down in the report.
- Gates after every task, from `frontend/`: `npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`. Lint must show 0 errors (150 pre-existing warnings are known). If typecheck dirties `packages/terminal/package-lock.json`, run `git checkout -- packages/terminal/package-lock.json` from the repo root before committing.
- Scrub `CLAUDE*` environment variables before starting any `opr` daemon or Vite dev server (`env -i HOME=$HOME PATH=$PATH …`).
- Every task ends in a commit with a conventional message and the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## File map

New files:

| Path | Responsibility |
|---|---|
| `frontend/src/renderer/lib/ticket-assign.ts` | Pure helpers: warning codes → message keys, `canAssignPlan`, `assignActionKey`, `planBranchName`, drag/drop ids, `needsForce` |
| `frontend/src/renderer/lib/ticket-assign.test.ts` | Tests for the above |
| `frontend/src/renderer/lib/markdown-scroll-sync.ts` | `headingIndexBeforeLine(content, line)` for Split preview follow |
| `frontend/src/renderer/lib/markdown-scroll-sync.test.ts` | Tests |
| `frontend/src/renderer/components/tickets/AssignPlanSheet.tsx` | Confirm sheet: dry run on open, warnings, role fields, Start / Terminate and start |
| `frontend/src/renderer/components/tickets/AssignPlanSheet.test.tsx` | Tests |
| `frontend/src/renderer/components/tickets/TicketDndProvider.tsx` | `DndContext`, sensors, overlay chip, `useTicketDrag`, `usePlanDraggable`, `useTicketDropTarget`, owns the sheet |
| `frontend/src/renderer/components/tickets/TicketDndProvider.test.tsx` | Tests |
| `frontend/src/renderer/components/tickets/CodeMirrorField.tsx` | Thin CodeMirror 6 mount: theme, markdown, wrapping, `Mod-s`, top-line reporting |
| `frontend/src/renderer/components/tickets/CodeMirrorField.test.tsx` | jsdom smoke test with `Range` stubs |
| `frontend/src/renderer/components/tickets/TicketEditor.tsx` | Toolbar, Edit / Preview / Split, draft, save, stale bar, SSE reload rule |
| `frontend/src/renderer/components/tickets/TicketEditor.test.tsx` | Tests |
| `frontend/src/renderer/components/settings/TicketDefaultsSection.tsx` | Planner / implementer / reviewer rows, reviewer mode, auto-review switch |
| `frontend/src/renderer/components/settings/TicketDefaultsSection.test.tsx` | Tests |
| `docs/superpowers/plans/2026-09-18-planning-tickets-assign-report.md` | Execution report (Task 12) |

Modified files:

| Path | Change |
|---|---|
| `frontend/src/renderer/i18n/*.json` (8) | New `tickets.*`, `settings.project.tickets.*` keys |
| `frontend/src/renderer/hooks/useTicketMutations.ts` | `assignPlan`, `saveTicketFile`, `apiErrorDetails`, `assignBlockedWarnings`, `staleModifiedAt`, new error keys |
| `frontend/src/renderer/hooks/useTicketMutations.test.tsx` | Tests for the above |
| `frontend/src/renderer/components/tickets/PlanRow.tsx` | Drag handle, `onAssign`, Assign / Reassign action |
| `frontend/src/renderer/components/tickets/TicketCard.tsx` | Pass `onAssign` via `useTicketDrag().requestAssign` |
| `frontend/src/renderer/components/tickets/TicketCard.test.tsx` | Assign path, navigate-not-called |
| `frontend/src/renderer/components/tickets/TicketPage.tsx` | Back crumb, `TicketEditor`, assign action, dirty-navigation blocker |
| `frontend/src/renderer/components/tickets/TicketPage.test.tsx` | Tests |
| `frontend/src/renderer/components/SessionsBoard.tsx` | `WorkLaneColumn` drop target, dimming, intake chip token fix |
| `frontend/src/renderer/components/SessionsBoard.test.tsx` | Drop target present |
| `frontend/src/renderer/components/Sidebar.tsx` | `ProjectItem` drop target |
| `frontend/src/renderer/components/Sidebar.test.tsx` | Drop target present |
| `frontend/src/renderer/routes/_shell.tsx` | Wrap `SidebarProvider` in `TicketDndProvider` |
| `frontend/src/renderer/components/ProjectSettingsForm.tsx` | `"tickets"` section, form state, save |
| `frontend/src/renderer/components/ProjectSettingsForm.test.tsx` | Tests |
| `frontend/src/renderer/components/SettingsDialog.tsx` | "Tickets" tab |
| `frontend/package.json`, `frontend/package-lock.json` | CodeMirror packages |

Exported names introduced by this plan, used across tasks:

- `lib/ticket-assign.ts`: `ASSIGN_WARNINGS`, `AssignWarning`, `assignWarningLabel`, `canAssignPlan`, `assignActionKey`, `planBranchName`, `needsForce`, `PlanDragData`, `planDragId`, `LANE_DROP_ID`, `projectDropId`, `dropAccepts`
- `hooks/useTicketMutations.ts`: `AssignPlanInput`, `SaveTicketFileInput`, `apiErrorDetails`, `assignBlockedWarnings`, `staleModifiedAt`, `useTicketMutations().assignPlan`, `useTicketMutations().saveTicketFile`
- `components/tickets/TicketDndProvider.tsx`: `TicketDndProvider`, `useTicketDrag`, `usePlanDraggable`, `useTicketDropTarget`, `AssignRequest`
- `components/tickets/AssignPlanSheet.tsx`: `AssignPlanSheet`
- `components/tickets/CodeMirrorField.tsx`: `CodeMirrorField`
- `components/tickets/TicketEditor.tsx`: `TicketEditor`, `EditorMode`
- `lib/markdown-scroll-sync.ts`: `headingIndexBeforeLine`
- `components/settings/TicketDefaultsSection.tsx`: `TicketDefaultsSection`, `cleanTicketDefaults`
- `components/ProjectSettingsForm.tsx`: `ProjectSettingsSection` gains `"tickets"`

---

### Task 1: Message catalogue for assign, editor and ticket defaults

**Files:**
- Modify: `frontend/src/renderer/i18n/en.json`, `de.json`, `es.json`, `fr.json`, `ja.json`, `ko.json`, `pt-BR.json`, `zh-CN.json`
- Test: `frontend/src/renderer/i18n/instance.test.ts` (existing parity test at lines 149-160), `frontend/src/renderer/i18n/renderer-coverage.test.ts` (existing)

**Interfaces:**
- Produces: the `MessageKey` union (`i18n/messages.ts:21`, `keyof typeof enMessages`) gains every key below; later tasks reference them by name.

- [ ] **Step 1: Write the merge script to the scratchpad**

Save as `/tmp/claude-501/add-ticket-keys.mjs` (outside the repo). It appends keys to each catalogue without reordering existing ones.

```js
import { readFileSync, writeFileSync } from "node:fs";

const dir = new URL("./", import.meta.url);
const root = process.argv[2];
if (!root) throw new Error("usage: node add-ticket-keys.mjs <frontend/src/renderer/i18n>");

const keys = {
	en: {
		"tickets.assign": "Assign",
		"tickets.reassign": "Reassign",
		"tickets.assignTitle": "Assign {{plan}}",
		"tickets.assignDescription": "Starts an implementing session in a fresh worktree on the branch below. Its prompt says to implement only this plan.",
		"tickets.assignTicket": "Ticket",
		"tickets.assignPlan": "Plan",
		"tickets.assignBranch": "Branch",
		"tickets.assignBranchHint": "A repeat assignment of the same plan gets a numbered suffix; the session card shows the final branch.",
		"tickets.assignChecking": "Checking…",
		"tickets.assignWarnings": "Before you start",
		"tickets.assignFailed": "Could not assign the plan",
		"tickets.terminateAndStart": "Terminate and start",
		"tickets.warning.plan_order": "An earlier plan in this ticket is not merged or done yet.",
		"tickets.warning.ticket_repo_dirty": "The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.",
		"tickets.warning.ticket_not_on_default_branch": "The project checkout is not on its default branch. The worktree is cut from the default branch, which may not contain these files.",
		"tickets.warning.planning_active": "The planning session is still running.",
		"tickets.warning.plan_assigned": "This plan already has a live session. Starting again terminates it first.",
		"tickets.dragHandleAria": "Drag {{plan}} to assign it",
		"tickets.dropToAssign": "Drop to assign",
		"tickets.dropOnProjectAria": "Assign a plan to {{name}}",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "The assignment needs confirmation.",
		"tickets.error.TICKET_FILE_STALE": "The file changed on disk since it was loaded.",
		"tickets.error.TICKET_PATH_OUTSIDE": "That path is outside the ticket folder.",
		"tickets.editor.mode": "View",
		"tickets.editor.edit": "Edit",
		"tickets.editor.preview": "Preview",
		"tickets.editor.split": "Split",
		"tickets.editor.save": "Save",
		"tickets.editor.saving": "Saving…",
		"tickets.editor.saved": "Saved",
		"tickets.editor.unsaved": "Unsaved changes",
		"tickets.editor.aria": "Edit {{file}}",
		"tickets.editor.previewAria": "Preview of {{file}}",
		"tickets.editor.staleTitle": "This file changed on disk",
		"tickets.editor.staleBody": "Reload to take the version on disk and drop your edits, or keep yours and overwrite it.",
		"tickets.editor.reload": "Reload",
		"tickets.editor.keepMine": "Keep mine",
		"tickets.editor.saveFailed": "Could not save the file",
		"tickets.editor.discardTitle": "Discard unsaved changes?",
		"tickets.editor.discardBody": "{{file}} has edits that were not saved.",
		"tickets.editor.discard": "Discard",
		"tickets.backToBoard": "Back to {{name}}",
		"settings.project.tickets": "Tickets",
		"settings.project.tickets.description": "Defaults for the agents that plan, implement and review tickets. Empty fields use the project's worker agent.",
		"settings.project.tickets.planner": "Planner",
		"settings.project.tickets.implementer": "Implementer",
		"settings.project.tickets.reviewer": "Reviewer",
		"settings.project.tickets.agent": "{{role}} agent",
		"settings.project.tickets.model": "{{role}} model",
		"settings.project.tickets.account": "{{role}} Claude account",
		"settings.project.tickets.inherit": "Project default",
		"settings.project.tickets.reviewerMode": "Reviews run in",
		"settings.project.tickets.reviewerMode.planner": "Planning session",
		"settings.project.tickets.reviewerMode.new": "New session",
		"settings.project.tickets.disableAutoReview": "Skip automatic review",
		"settings.project.tickets.scratch": "Tickets are not available for scratch projects.",
	},
	de: {
		"tickets.assign": "Zuweisen",
		"tickets.reassign": "Neu zuweisen",
		"tickets.assignTitle": "{{plan}} zuweisen",
		"tickets.assignDescription": "Startet eine Implementierungssitzung in einem neuen Worktree auf dem Branch unten. Der Prompt sagt, nur diesen Plan umzusetzen.",
		"tickets.assignTicket": "Ticket",
		"tickets.assignPlan": "Plan",
		"tickets.assignBranch": "Branch",
		"tickets.assignBranchHint": "Eine erneute Zuweisung desselben Plans erhält ein nummeriertes Suffix; die Sitzungskarte zeigt den endgültigen Branch.",
		"tickets.assignChecking": "Prüfe…",
		"tickets.assignWarnings": "Vor dem Start",
		"tickets.assignFailed": "Der Plan konnte nicht zugewiesen werden",
		"tickets.terminateAndStart": "Beenden und starten",
		"tickets.warning.plan_order": "Ein früherer Plan dieses Tickets ist noch nicht gemergt oder erledigt.",
		"tickets.warning.ticket_repo_dirty": "Der Ticket-Ordner hat nicht committete Änderungen. Der Worktree wird vom committeten Branch abgezweigt und sieht sie nicht.",
		"tickets.warning.ticket_not_on_default_branch": "Das Projekt ist nicht auf seinem Standard-Branch. Der Worktree wird vom Standard-Branch abgezweigt, der diese Dateien möglicherweise nicht enthält.",
		"tickets.warning.planning_active": "Die Planungssitzung läuft noch.",
		"tickets.warning.plan_assigned": "Dieser Plan hat bereits eine laufende Sitzung. Ein Neustart beendet sie zuerst.",
		"tickets.dragHandleAria": "{{plan}} ziehen, um ihn zuzuweisen",
		"tickets.dropToAssign": "Zum Zuweisen ablegen",
		"tickets.dropOnProjectAria": "Einen Plan {{name}} zuweisen",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "Die Zuweisung braucht eine Bestätigung.",
		"tickets.error.TICKET_FILE_STALE": "Die Datei hat sich seit dem Laden auf der Festplatte geändert.",
		"tickets.error.TICKET_PATH_OUTSIDE": "Dieser Pfad liegt außerhalb des Ticket-Ordners.",
		"tickets.editor.mode": "Ansicht",
		"tickets.editor.edit": "Bearbeiten",
		"tickets.editor.preview": "Vorschau",
		"tickets.editor.split": "Geteilt",
		"tickets.editor.save": "Speichern",
		"tickets.editor.saving": "Speichere…",
		"tickets.editor.saved": "Gespeichert",
		"tickets.editor.unsaved": "Ungespeicherte Änderungen",
		"tickets.editor.aria": "{{file}} bearbeiten",
		"tickets.editor.previewAria": "Vorschau von {{file}}",
		"tickets.editor.staleTitle": "Diese Datei hat sich auf der Festplatte geändert",
		"tickets.editor.staleBody": "Neu laden übernimmt die Version auf der Festplatte und verwirft deine Änderungen; Meine behalten überschreibt sie.",
		"tickets.editor.reload": "Neu laden",
		"tickets.editor.keepMine": "Meine behalten",
		"tickets.editor.saveFailed": "Die Datei konnte nicht gespeichert werden",
		"tickets.editor.discardTitle": "Ungespeicherte Änderungen verwerfen?",
		"tickets.editor.discardBody": "{{file}} hat Änderungen, die nicht gespeichert wurden.",
		"tickets.editor.discard": "Verwerfen",
		"tickets.backToBoard": "Zurück zu {{name}}",
		"settings.project.tickets": "Tickets",
		"settings.project.tickets.description": "Standards für die Agenten, die Tickets planen, umsetzen und prüfen. Leere Felder verwenden den Worker-Agenten des Projekts.",
		"settings.project.tickets.planner": "Planer",
		"settings.project.tickets.implementer": "Umsetzer",
		"settings.project.tickets.reviewer": "Prüfer",
		"settings.project.tickets.agent": "{{role}}-Agent",
		"settings.project.tickets.model": "{{role}}-Modell",
		"settings.project.tickets.account": "{{role}}-Claude-Konto",
		"settings.project.tickets.inherit": "Projektstandard",
		"settings.project.tickets.reviewerMode": "Reviews laufen in",
		"settings.project.tickets.reviewerMode.planner": "Planungssitzung",
		"settings.project.tickets.reviewerMode.new": "Neuer Sitzung",
		"settings.project.tickets.disableAutoReview": "Automatisches Review überspringen",
		"settings.project.tickets.scratch": "Tickets sind für Scratch-Projekte nicht verfügbar.",
	},
	es: {
		"tickets.assign": "Asignar",
		"tickets.reassign": "Reasignar",
		"tickets.assignTitle": "Asignar {{plan}}",
		"tickets.assignDescription": "Inicia una sesión de implementación en un worktree nuevo sobre la rama indicada. Su prompt dice implementar solo este plan.",
		"tickets.assignTicket": "Ticket",
		"tickets.assignPlan": "Plan",
		"tickets.assignBranch": "Rama",
		"tickets.assignBranchHint": "Una nueva asignación del mismo plan recibe un sufijo numérico; la tarjeta de la sesión muestra la rama final.",
		"tickets.assignChecking": "Comprobando…",
		"tickets.assignWarnings": "Antes de empezar",
		"tickets.assignFailed": "No se pudo asignar el plan",
		"tickets.terminateAndStart": "Terminar e iniciar",
		"tickets.warning.plan_order": "Un plan anterior de este ticket aún no está fusionado ni completado.",
		"tickets.warning.ticket_repo_dirty": "La carpeta del ticket tiene cambios sin confirmar. El worktree se corta desde la rama confirmada y no los verá.",
		"tickets.warning.ticket_not_on_default_branch": "El proyecto no está en su rama predeterminada. El worktree se corta desde la rama predeterminada, que quizá no contenga estos archivos.",
		"tickets.warning.planning_active": "La sesión de planificación sigue en ejecución.",
		"tickets.warning.plan_assigned": "Este plan ya tiene una sesión activa. Volver a iniciarlo la termina primero.",
		"tickets.dragHandleAria": "Arrastra {{plan}} para asignarlo",
		"tickets.dropToAssign": "Suelta para asignar",
		"tickets.dropOnProjectAria": "Asignar un plan a {{name}}",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "La asignación necesita confirmación.",
		"tickets.error.TICKET_FILE_STALE": "El archivo cambió en disco desde que se cargó.",
		"tickets.error.TICKET_PATH_OUTSIDE": "Esa ruta está fuera de la carpeta del ticket.",
		"tickets.editor.mode": "Vista",
		"tickets.editor.edit": "Editar",
		"tickets.editor.preview": "Vista previa",
		"tickets.editor.split": "Dividido",
		"tickets.editor.save": "Guardar",
		"tickets.editor.saving": "Guardando…",
		"tickets.editor.saved": "Guardado",
		"tickets.editor.unsaved": "Cambios sin guardar",
		"tickets.editor.aria": "Editar {{file}}",
		"tickets.editor.previewAria": "Vista previa de {{file}}",
		"tickets.editor.staleTitle": "Este archivo cambió en disco",
		"tickets.editor.staleBody": "Recargar toma la versión en disco y descarta tus cambios; Conservar los míos la sobrescribe.",
		"tickets.editor.reload": "Recargar",
		"tickets.editor.keepMine": "Conservar los míos",
		"tickets.editor.saveFailed": "No se pudo guardar el archivo",
		"tickets.editor.discardTitle": "¿Descartar los cambios sin guardar?",
		"tickets.editor.discardBody": "{{file}} tiene cambios que no se guardaron.",
		"tickets.editor.discard": "Descartar",
		"tickets.backToBoard": "Volver a {{name}}",
		"settings.project.tickets": "Tickets",
		"settings.project.tickets.description": "Valores predeterminados para los agentes que planifican, implementan y revisan tickets. Los campos vacíos usan el agente worker del proyecto.",
		"settings.project.tickets.planner": "Planificador",
		"settings.project.tickets.implementer": "Implementador",
		"settings.project.tickets.reviewer": "Revisor",
		"settings.project.tickets.agent": "Agente de {{role}}",
		"settings.project.tickets.model": "Modelo de {{role}}",
		"settings.project.tickets.account": "Cuenta de Claude de {{role}}",
		"settings.project.tickets.inherit": "Predeterminado del proyecto",
		"settings.project.tickets.reviewerMode": "Las revisiones se ejecutan en",
		"settings.project.tickets.reviewerMode.planner": "Sesión de planificación",
		"settings.project.tickets.reviewerMode.new": "Sesión nueva",
		"settings.project.tickets.disableAutoReview": "Omitir la revisión automática",
		"settings.project.tickets.scratch": "Los tickets no están disponibles en proyectos scratch.",
	},
	fr: {
		"tickets.assign": "Assigner",
		"tickets.reassign": "Réassigner",
		"tickets.assignTitle": "Assigner {{plan}}",
		"tickets.assignDescription": "Démarre une session d'implémentation dans un nouveau worktree sur la branche ci-dessous. Son prompt demande d'implémenter uniquement ce plan.",
		"tickets.assignTicket": "Ticket",
		"tickets.assignPlan": "Plan",
		"tickets.assignBranch": "Branche",
		"tickets.assignBranchHint": "Une nouvelle assignation du même plan reçoit un suffixe numérique ; la carte de session affiche la branche finale.",
		"tickets.assignChecking": "Vérification…",
		"tickets.assignWarnings": "Avant de démarrer",
		"tickets.assignFailed": "Impossible d'assigner le plan",
		"tickets.terminateAndStart": "Terminer et démarrer",
		"tickets.warning.plan_order": "Un plan précédent de ce ticket n'est pas encore fusionné ni terminé.",
		"tickets.warning.ticket_repo_dirty": "Le dossier du ticket contient des modifications non validées. Le worktree part de la branche validée et ne les verra pas.",
		"tickets.warning.ticket_not_on_default_branch": "Le projet n'est pas sur sa branche par défaut. Le worktree part de la branche par défaut, qui ne contient peut-être pas ces fichiers.",
		"tickets.warning.planning_active": "La session de planification est encore en cours.",
		"tickets.warning.plan_assigned": "Ce plan a déjà une session active. Redémarrer la termine d'abord.",
		"tickets.dragHandleAria": "Glisser {{plan}} pour l'assigner",
		"tickets.dropToAssign": "Déposer pour assigner",
		"tickets.dropOnProjectAria": "Assigner un plan à {{name}}",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "L'assignation demande une confirmation.",
		"tickets.error.TICKET_FILE_STALE": "Le fichier a changé sur le disque depuis son chargement.",
		"tickets.error.TICKET_PATH_OUTSIDE": "Ce chemin est en dehors du dossier du ticket.",
		"tickets.editor.mode": "Vue",
		"tickets.editor.edit": "Éditer",
		"tickets.editor.preview": "Aperçu",
		"tickets.editor.split": "Divisé",
		"tickets.editor.save": "Enregistrer",
		"tickets.editor.saving": "Enregistrement…",
		"tickets.editor.saved": "Enregistré",
		"tickets.editor.unsaved": "Modifications non enregistrées",
		"tickets.editor.aria": "Éditer {{file}}",
		"tickets.editor.previewAria": "Aperçu de {{file}}",
		"tickets.editor.staleTitle": "Ce fichier a changé sur le disque",
		"tickets.editor.staleBody": "Recharger prend la version du disque et abandonne vos modifications ; Garder les miennes l'écrase.",
		"tickets.editor.reload": "Recharger",
		"tickets.editor.keepMine": "Garder les miennes",
		"tickets.editor.saveFailed": "Impossible d'enregistrer le fichier",
		"tickets.editor.discardTitle": "Abandonner les modifications non enregistrées ?",
		"tickets.editor.discardBody": "{{file}} a des modifications qui n'ont pas été enregistrées.",
		"tickets.editor.discard": "Abandonner",
		"tickets.backToBoard": "Retour à {{name}}",
		"settings.project.tickets": "Tickets",
		"settings.project.tickets.description": "Valeurs par défaut des agents qui planifient, implémentent et relisent les tickets. Les champs vides utilisent l'agent worker du projet.",
		"settings.project.tickets.planner": "Planificateur",
		"settings.project.tickets.implementer": "Implémenteur",
		"settings.project.tickets.reviewer": "Relecteur",
		"settings.project.tickets.agent": "Agent {{role}}",
		"settings.project.tickets.model": "Modèle {{role}}",
		"settings.project.tickets.account": "Compte Claude {{role}}",
		"settings.project.tickets.inherit": "Défaut du projet",
		"settings.project.tickets.reviewerMode": "Les relectures s'exécutent dans",
		"settings.project.tickets.reviewerMode.planner": "La session de planification",
		"settings.project.tickets.reviewerMode.new": "Une nouvelle session",
		"settings.project.tickets.disableAutoReview": "Ignorer la relecture automatique",
		"settings.project.tickets.scratch": "Les tickets ne sont pas disponibles pour les projets scratch.",
	},
	ja: {
		"tickets.assign": "割り当て",
		"tickets.reassign": "再割り当て",
		"tickets.assignTitle": "{{plan}} を割り当て",
		"tickets.assignDescription": "下のブランチで新しいワークツリーに実装セッションを開始します。プロンプトはこのプランだけを実装するよう指示します。",
		"tickets.assignTicket": "チケット",
		"tickets.assignPlan": "プラン",
		"tickets.assignBranch": "ブランチ",
		"tickets.assignBranchHint": "同じプランを再度割り当てると番号付きの接尾辞が付きます。最終的なブランチはセッションカードに表示されます。",
		"tickets.assignChecking": "確認中…",
		"tickets.assignWarnings": "開始する前に",
		"tickets.assignFailed": "プランを割り当てられませんでした",
		"tickets.terminateAndStart": "終了して開始",
		"tickets.warning.plan_order": "このチケットの前のプランがまだマージも完了もしていません。",
		"tickets.warning.ticket_repo_dirty": "チケットフォルダーに未コミットの変更があります。ワークツリーはコミット済みブランチから作られるため、その変更は見えません。",
		"tickets.warning.ticket_not_on_default_branch": "プロジェクトがデフォルトブランチにありません。ワークツリーはデフォルトブランチから作られ、これらのファイルを含まない可能性があります。",
		"tickets.warning.planning_active": "計画セッションがまだ実行中です。",
		"tickets.warning.plan_assigned": "このプランにはすでに稼働中のセッションがあります。再開すると先にそれを終了します。",
		"tickets.dragHandleAria": "{{plan}} をドラッグして割り当て",
		"tickets.dropToAssign": "ドロップして割り当て",
		"tickets.dropOnProjectAria": "{{name}} にプランを割り当て",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "割り当てには確認が必要です。",
		"tickets.error.TICKET_FILE_STALE": "読み込み後にファイルがディスク上で変更されました。",
		"tickets.error.TICKET_PATH_OUTSIDE": "そのパスはチケットフォルダーの外です。",
		"tickets.editor.mode": "表示",
		"tickets.editor.edit": "編集",
		"tickets.editor.preview": "プレビュー",
		"tickets.editor.split": "分割",
		"tickets.editor.save": "保存",
		"tickets.editor.saving": "保存中…",
		"tickets.editor.saved": "保存済み",
		"tickets.editor.unsaved": "未保存の変更",
		"tickets.editor.aria": "{{file}} を編集",
		"tickets.editor.previewAria": "{{file}} のプレビュー",
		"tickets.editor.staleTitle": "このファイルはディスク上で変更されました",
		"tickets.editor.staleBody": "再読み込みはディスク上の版を採用して編集を捨てます。自分の版を保持は上書きします。",
		"tickets.editor.reload": "再読み込み",
		"tickets.editor.keepMine": "自分の版を保持",
		"tickets.editor.saveFailed": "ファイルを保存できませんでした",
		"tickets.editor.discardTitle": "未保存の変更を破棄しますか？",
		"tickets.editor.discardBody": "{{file}} に保存されていない編集があります。",
		"tickets.editor.discard": "破棄",
		"tickets.backToBoard": "{{name}} に戻る",
		"settings.project.tickets": "チケット",
		"settings.project.tickets.description": "チケットを計画・実装・レビューするエージェントの既定値。空欄はプロジェクトのワーカーエージェントを使います。",
		"settings.project.tickets.planner": "プランナー",
		"settings.project.tickets.implementer": "実装者",
		"settings.project.tickets.reviewer": "レビュアー",
		"settings.project.tickets.agent": "{{role}}のエージェント",
		"settings.project.tickets.model": "{{role}}のモデル",
		"settings.project.tickets.account": "{{role}}の Claude アカウント",
		"settings.project.tickets.inherit": "プロジェクトの既定",
		"settings.project.tickets.reviewerMode": "レビューの実行先",
		"settings.project.tickets.reviewerMode.planner": "計画セッション",
		"settings.project.tickets.reviewerMode.new": "新しいセッション",
		"settings.project.tickets.disableAutoReview": "自動レビューをスキップ",
		"settings.project.tickets.scratch": "スクラッチプロジェクトではチケットを使えません。",
	},
	ko: {
		"tickets.assign": "할당",
		"tickets.reassign": "재할당",
		"tickets.assignTitle": "{{plan}} 할당",
		"tickets.assignDescription": "아래 브랜치의 새 워크트리에서 구현 세션을 시작합니다. 프롬프트는 이 플랜만 구현하라고 지시합니다.",
		"tickets.assignTicket": "티켓",
		"tickets.assignPlan": "플랜",
		"tickets.assignBranch": "브랜치",
		"tickets.assignBranchHint": "같은 플랜을 다시 할당하면 번호 접미사가 붙습니다. 최종 브랜치는 세션 카드에 표시됩니다.",
		"tickets.assignChecking": "확인 중…",
		"tickets.assignWarnings": "시작하기 전에",
		"tickets.assignFailed": "플랜을 할당할 수 없습니다",
		"tickets.terminateAndStart": "종료 후 시작",
		"tickets.warning.plan_order": "이 티켓의 이전 플랜이 아직 병합되거나 완료되지 않았습니다.",
		"tickets.warning.ticket_repo_dirty": "티켓 폴더에 커밋되지 않은 변경이 있습니다. 워크트리는 커밋된 브랜치에서 만들어져 그 변경을 보지 못합니다.",
		"tickets.warning.ticket_not_on_default_branch": "프로젝트가 기본 브랜치에 있지 않습니다. 워크트리는 기본 브랜치에서 만들어지며 이 파일들이 없을 수 있습니다.",
		"tickets.warning.planning_active": "계획 세션이 아직 실행 중입니다.",
		"tickets.warning.plan_assigned": "이 플랜에는 이미 실행 중인 세션이 있습니다. 다시 시작하면 먼저 그 세션을 종료합니다.",
		"tickets.dragHandleAria": "{{plan}}을(를) 끌어서 할당",
		"tickets.dropToAssign": "놓아서 할당",
		"tickets.dropOnProjectAria": "{{name}}에 플랜 할당",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "할당에 확인이 필요합니다.",
		"tickets.error.TICKET_FILE_STALE": "불러온 뒤 디스크에서 파일이 변경되었습니다.",
		"tickets.error.TICKET_PATH_OUTSIDE": "해당 경로는 티켓 폴더 밖입니다.",
		"tickets.editor.mode": "보기",
		"tickets.editor.edit": "편집",
		"tickets.editor.preview": "미리보기",
		"tickets.editor.split": "분할",
		"tickets.editor.save": "저장",
		"tickets.editor.saving": "저장 중…",
		"tickets.editor.saved": "저장됨",
		"tickets.editor.unsaved": "저장되지 않은 변경",
		"tickets.editor.aria": "{{file}} 편집",
		"tickets.editor.previewAria": "{{file}} 미리보기",
		"tickets.editor.staleTitle": "이 파일이 디스크에서 변경되었습니다",
		"tickets.editor.staleBody": "다시 불러오기는 디스크의 버전을 가져오고 편집을 버립니다. 내 것 유지는 덮어씁니다.",
		"tickets.editor.reload": "다시 불러오기",
		"tickets.editor.keepMine": "내 것 유지",
		"tickets.editor.saveFailed": "파일을 저장할 수 없습니다",
		"tickets.editor.discardTitle": "저장되지 않은 변경을 버릴까요?",
		"tickets.editor.discardBody": "{{file}}에 저장되지 않은 편집이 있습니다.",
		"tickets.editor.discard": "버리기",
		"tickets.backToBoard": "{{name}}로 돌아가기",
		"settings.project.tickets": "티켓",
		"settings.project.tickets.description": "티켓을 계획, 구현, 검토하는 에이전트의 기본값입니다. 빈 필드는 프로젝트의 워커 에이전트를 사용합니다.",
		"settings.project.tickets.planner": "플래너",
		"settings.project.tickets.implementer": "구현자",
		"settings.project.tickets.reviewer": "리뷰어",
		"settings.project.tickets.agent": "{{role}} 에이전트",
		"settings.project.tickets.model": "{{role}} 모델",
		"settings.project.tickets.account": "{{role}} Claude 계정",
		"settings.project.tickets.inherit": "프로젝트 기본값",
		"settings.project.tickets.reviewerMode": "리뷰 실행 위치",
		"settings.project.tickets.reviewerMode.planner": "계획 세션",
		"settings.project.tickets.reviewerMode.new": "새 세션",
		"settings.project.tickets.disableAutoReview": "자동 리뷰 건너뛰기",
		"settings.project.tickets.scratch": "스크래치 프로젝트에서는 티켓을 사용할 수 없습니다.",
	},
	"pt-BR": {
		"tickets.assign": "Atribuir",
		"tickets.reassign": "Reatribuir",
		"tickets.assignTitle": "Atribuir {{plan}}",
		"tickets.assignDescription": "Inicia uma sessão de implementação em um worktree novo no branch abaixo. O prompt diz para implementar apenas este plano.",
		"tickets.assignTicket": "Ticket",
		"tickets.assignPlan": "Plano",
		"tickets.assignBranch": "Branch",
		"tickets.assignBranchHint": "Uma nova atribuição do mesmo plano recebe um sufixo numérico; o cartão da sessão mostra o branch final.",
		"tickets.assignChecking": "Verificando…",
		"tickets.assignWarnings": "Antes de começar",
		"tickets.assignFailed": "Não foi possível atribuir o plano",
		"tickets.terminateAndStart": "Encerrar e iniciar",
		"tickets.warning.plan_order": "Um plano anterior deste ticket ainda não foi mesclado nem concluído.",
		"tickets.warning.ticket_repo_dirty": "A pasta do ticket tem alterações não confirmadas. O worktree parte do branch confirmado e não as verá.",
		"tickets.warning.ticket_not_on_default_branch": "O projeto não está no branch padrão. O worktree parte do branch padrão, que pode não conter estes arquivos.",
		"tickets.warning.planning_active": "A sessão de planejamento ainda está em execução.",
		"tickets.warning.plan_assigned": "Este plano já tem uma sessão ativa. Iniciar de novo a encerra primeiro.",
		"tickets.dragHandleAria": "Arraste {{plan}} para atribuí-lo",
		"tickets.dropToAssign": "Solte para atribuir",
		"tickets.dropOnProjectAria": "Atribuir um plano a {{name}}",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "A atribuição precisa de confirmação.",
		"tickets.error.TICKET_FILE_STALE": "O arquivo mudou no disco desde que foi carregado.",
		"tickets.error.TICKET_PATH_OUTSIDE": "Esse caminho está fora da pasta do ticket.",
		"tickets.editor.mode": "Visualização",
		"tickets.editor.edit": "Editar",
		"tickets.editor.preview": "Pré-visualização",
		"tickets.editor.split": "Dividido",
		"tickets.editor.save": "Salvar",
		"tickets.editor.saving": "Salvando…",
		"tickets.editor.saved": "Salvo",
		"tickets.editor.unsaved": "Alterações não salvas",
		"tickets.editor.aria": "Editar {{file}}",
		"tickets.editor.previewAria": "Pré-visualização de {{file}}",
		"tickets.editor.staleTitle": "Este arquivo mudou no disco",
		"tickets.editor.staleBody": "Recarregar adota a versão do disco e descarta suas edições; Manter as minhas a sobrescreve.",
		"tickets.editor.reload": "Recarregar",
		"tickets.editor.keepMine": "Manter as minhas",
		"tickets.editor.saveFailed": "Não foi possível salvar o arquivo",
		"tickets.editor.discardTitle": "Descartar alterações não salvas?",
		"tickets.editor.discardBody": "{{file}} tem edições que não foram salvas.",
		"tickets.editor.discard": "Descartar",
		"tickets.backToBoard": "Voltar para {{name}}",
		"settings.project.tickets": "Tickets",
		"settings.project.tickets.description": "Padrões para os agentes que planejam, implementam e revisam tickets. Campos vazios usam o agente worker do projeto.",
		"settings.project.tickets.planner": "Planejador",
		"settings.project.tickets.implementer": "Implementador",
		"settings.project.tickets.reviewer": "Revisor",
		"settings.project.tickets.agent": "Agente de {{role}}",
		"settings.project.tickets.model": "Modelo de {{role}}",
		"settings.project.tickets.account": "Conta Claude de {{role}}",
		"settings.project.tickets.inherit": "Padrão do projeto",
		"settings.project.tickets.reviewerMode": "As revisões rodam em",
		"settings.project.tickets.reviewerMode.planner": "Sessão de planejamento",
		"settings.project.tickets.reviewerMode.new": "Nova sessão",
		"settings.project.tickets.disableAutoReview": "Pular a revisão automática",
		"settings.project.tickets.scratch": "Tickets não estão disponíveis em projetos scratch.",
	},
	"zh-CN": {
		"tickets.assign": "分配",
		"tickets.reassign": "重新分配",
		"tickets.assignTitle": "分配 {{plan}}",
		"tickets.assignDescription": "在下方分支的新工作树中启动实施会话。提示词要求只实施这个计划。",
		"tickets.assignTicket": "工单",
		"tickets.assignPlan": "计划",
		"tickets.assignBranch": "分支",
		"tickets.assignBranchHint": "再次分配同一计划会加上数字后缀；会话卡片显示最终分支。",
		"tickets.assignChecking": "检查中…",
		"tickets.assignWarnings": "开始之前",
		"tickets.assignFailed": "无法分配该计划",
		"tickets.terminateAndStart": "终止并开始",
		"tickets.warning.plan_order": "此工单中较早的计划尚未合并或完成。",
		"tickets.warning.ticket_repo_dirty": "工单文件夹有未提交的更改。工作树从已提交的分支创建，看不到这些更改。",
		"tickets.warning.ticket_not_on_default_branch": "项目不在默认分支上。工作树从默认分支创建，可能不包含这些文件。",
		"tickets.warning.planning_active": "规划会话仍在运行。",
		"tickets.warning.plan_assigned": "此计划已有正在运行的会话。再次开始会先终止它。",
		"tickets.dragHandleAria": "拖动 {{plan}} 以分配",
		"tickets.dropToAssign": "放下以分配",
		"tickets.dropOnProjectAria": "把计划分配给 {{name}}",
		"tickets.error.TICKET_ASSIGN_BLOCKED": "分配需要确认。",
		"tickets.error.TICKET_FILE_STALE": "文件在加载后已在磁盘上被修改。",
		"tickets.error.TICKET_PATH_OUTSIDE": "该路径在工单文件夹之外。",
		"tickets.editor.mode": "视图",
		"tickets.editor.edit": "编辑",
		"tickets.editor.preview": "预览",
		"tickets.editor.split": "分栏",
		"tickets.editor.save": "保存",
		"tickets.editor.saving": "保存中…",
		"tickets.editor.saved": "已保存",
		"tickets.editor.unsaved": "未保存的更改",
		"tickets.editor.aria": "编辑 {{file}}",
		"tickets.editor.previewAria": "{{file}} 的预览",
		"tickets.editor.staleTitle": "此文件已在磁盘上更改",
		"tickets.editor.staleBody": "重新加载会采用磁盘上的版本并丢弃你的编辑；保留我的会覆盖它。",
		"tickets.editor.reload": "重新加载",
		"tickets.editor.keepMine": "保留我的",
		"tickets.editor.saveFailed": "无法保存文件",
		"tickets.editor.discardTitle": "放弃未保存的更改？",
		"tickets.editor.discardBody": "{{file}} 有尚未保存的编辑。",
		"tickets.editor.discard": "放弃",
		"tickets.backToBoard": "返回 {{name}}",
		"settings.project.tickets": "工单",
		"settings.project.tickets.description": "规划、实施和评审工单的代理默认值。留空则使用项目的 worker 代理。",
		"settings.project.tickets.planner": "规划者",
		"settings.project.tickets.implementer": "实施者",
		"settings.project.tickets.reviewer": "评审者",
		"settings.project.tickets.agent": "{{role}}代理",
		"settings.project.tickets.model": "{{role}}模型",
		"settings.project.tickets.account": "{{role}} Claude 账户",
		"settings.project.tickets.inherit": "项目默认",
		"settings.project.tickets.reviewerMode": "评审运行于",
		"settings.project.tickets.reviewerMode.planner": "规划会话",
		"settings.project.tickets.reviewerMode.new": "新会话",
		"settings.project.tickets.disableAutoReview": "跳过自动评审",
		"settings.project.tickets.scratch": "临时项目不支持工单。",
	},
};

for (const [locale, additions] of Object.entries(keys)) {
	const file = `${root}/${locale}.json`;
	const catalogue = JSON.parse(readFileSync(file, "utf8"));
	for (const [key, value] of Object.entries(additions)) {
		if (key in catalogue) throw new Error(`${locale} already has ${key}`);
		catalogue[key] = value;
	}
	writeFileSync(file, `${JSON.stringify(catalogue, null, "\t")}\n`);
}
console.log("added", Object.keys(keys.en).length, "keys to", Object.keys(keys).length, "locales");
```

- [ ] **Step 2: Check the catalogue formatting before running the script**

Run: `head -c 200 frontend/src/renderer/i18n/en.json | od -c | head -3`
Expected: keys are tab-indented and the file ends with `}\n` (so `JSON.stringify(..., "\t")` reproduces the existing layout and the diff is additions only). If the file uses spaces instead, change the `"\t"` argument to match before running.

- [ ] **Step 3: Run the script**

Run: `node /tmp/claude-501/add-ticket-keys.mjs frontend/src/renderer/i18n`
Expected: `added 56 keys to 8 locales`. Then `git diff --stat frontend/src/renderer/i18n` shows 8 files, each `+56` lines and `-1`/`+1` at most for the trailing line.

- [ ] **Step 4: Run the i18n tests**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/i18n`
Expected: PASS (parity test `keeps locale catalogs covering every English key with non-empty values`, interpolation alignment, coverage).

- [ ] **Step 5: Typecheck (MessageKey union picks up the new keys)**

Run: `cd frontend && npm run typecheck`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/i18n
git commit -m "feat(i18n): copy for ticket assign, editor and ticket defaults" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Assign helpers (`lib/ticket-assign.ts`)

**Files:**
- Create: `frontend/src/renderer/lib/ticket-assign.ts`
- Test: `frontend/src/renderer/lib/ticket-assign.test.ts`

**Interfaces:**
- Consumes: `PlanView`, `TicketWithProject`, `planNumber` from `lib/ticket-presentation.ts:6,10,127-130`; `MessageKey` from `../i18n`.
- Produces (used by Tasks 4-7, 10):
  - `type AssignWarning = "plan_order" | "ticket_repo_dirty" | "ticket_not_on_default_branch" | "planning_active" | "plan_assigned"`
  - `ASSIGN_WARNINGS: readonly AssignWarning[]` (daemon order, `service.go:543-564`)
  - `assignWarningLabel(code: string, t: TFunction): string` — unknown codes render verbatim
  - `canAssignPlan(plan: Pick<PlanView, "status">): boolean` — `todo` or `terminated`
  - `assignActionKey(plan: Pick<PlanView, "status">): "tickets.assign" | "tickets.reassign"`
  - `planBranchName(slug: string, file: string): string` — `opr/<slug>-<NN>`; falls back to the file stem, mirroring `planStem` at `service.go:527-533`
  - `needsForce(warnings: readonly string[]): boolean`
  - `type PlanDragData = { ticket: TicketWithProject; plan: PlanView }`
  - `planDragId(data: PlanDragData): string`
  - `LANE_DROP_ID = "drop:lane:working"`, `projectDropId(projectId: string): string`
  - `dropAccepts(dropId: string, data: PlanDragData): boolean` — the lane accepts everything; a project header accepts only its own project's plans

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/lib/ticket-assign.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { appI18n } from "../i18n";
import type { PlanView, TicketWithProject } from "./ticket-presentation";
import {
	ASSIGN_WARNINGS,
	assignActionKey,
	assignWarningLabel,
	canAssignPlan,
	dropAccepts,
	LANE_DROP_ID,
	needsForce,
	planBranchName,
	planDragId,
	projectDropId,
} from "./ticket-assign";

const ticket: TicketWithProject = {
	projectId: "p1",
	projectName: "app",
	slug: "search-page",
	title: "Search page",
	status: "ready",
	plans: [],
	files: [],
};

function plan(status: PlanView["status"], file = "plans/01-index.md"): PlanView {
	return { file, order: 1, title: "Index", status };
}

describe("assign warnings", () => {
	it("lists the five daemon warnings in daemon order", () => {
		expect(ASSIGN_WARNINGS).toEqual([
			"plan_order",
			"ticket_repo_dirty",
			"ticket_not_on_default_branch",
			"planning_active",
			"plan_assigned",
		]);
	});

	it("maps every known warning to copy and echoes unknown codes", () => {
		for (const code of ASSIGN_WARNINGS) {
			expect(assignWarningLabel(code, appI18n.t)).not.toBe(code);
		}
		expect(assignWarningLabel("plan_assigned", appI18n.t)).toBe(
			"This plan already has a live session. Starting again terminates it first.",
		);
		expect(assignWarningLabel("something_new", appI18n.t)).toBe("something_new");
	});

	it("needs force whenever the dry run returned anything", () => {
		expect(needsForce([])).toBe(false);
		expect(needsForce(["ticket_repo_dirty"])).toBe(true);
	});
});

describe("assignable plans", () => {
	it("allows todo and terminated plans only", () => {
		expect(canAssignPlan(plan("todo"))).toBe(true);
		expect(canAssignPlan(plan("terminated"))).toBe(true);
		for (const status of ["idle", "working", "needs_you", "in_review", "reviewing", "awaiting_merge", "merging", "merged", "done"] as const) {
			expect(canAssignPlan(plan(status))).toBe(false);
		}
	});

	it("labels the action Assign for todo and Reassign for terminated", () => {
		expect(assignActionKey(plan("todo"))).toBe("tickets.assign");
		expect(assignActionKey(plan("terminated"))).toBe("tickets.reassign");
	});
});

describe("planBranchName", () => {
	it("uses the NN prefix like the daemon", () => {
		expect(planBranchName("search-page", "plans/01-index.md")).toBe("opr/search-page-01");
		expect(planBranchName("search-page", "plans/12-ui.md")).toBe("opr/search-page-12");
	});

	it("falls back to the file stem for unnumbered plans", () => {
		expect(planBranchName("search-page", "plans/cleanup.md")).toBe("opr/search-page-cleanup");
	});
});

describe("drag and drop ids", () => {
	const data = { ticket, plan: plan("todo") };

	it("builds a stable draggable id from project, slug and file", () => {
		expect(planDragId(data)).toBe("plan:p1:search-page:plans/01-index.md");
	});

	it("lets the lane accept any plan and a project header only its own", () => {
		expect(dropAccepts(LANE_DROP_ID, data)).toBe(true);
		expect(dropAccepts(projectDropId("p1"), data)).toBe(true);
		expect(dropAccepts(projectDropId("p2"), data)).toBe(false);
		expect(dropAccepts("something-else", data)).toBe(false);
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-assign.test.ts`
Expected: FAIL — `Cannot find module './ticket-assign'`.

- [ ] **Step 3: Write the helpers**

`frontend/src/renderer/lib/ticket-assign.ts`:

```ts
import type { TFunction } from "i18next";
import type { MessageKey } from "../i18n";
import { planNumber, type PlanView, type TicketWithProject } from "./ticket-presentation";

export type AssignWarning =
	| "plan_order"
	| "ticket_repo_dirty"
	| "ticket_not_on_default_branch"
	| "planning_active"
	| "plan_assigned";

export const ASSIGN_WARNINGS: readonly AssignWarning[] = [
	"plan_order",
	"ticket_repo_dirty",
	"ticket_not_on_default_branch",
	"planning_active",
	"plan_assigned",
];

const warningKeys: Record<AssignWarning, MessageKey> = {
	plan_order: "tickets.warning.plan_order",
	ticket_repo_dirty: "tickets.warning.ticket_repo_dirty",
	ticket_not_on_default_branch: "tickets.warning.ticket_not_on_default_branch",
	planning_active: "tickets.warning.planning_active",
	plan_assigned: "tickets.warning.plan_assigned",
};

function isAssignWarning(code: string): code is AssignWarning {
	return code in warningKeys;
}

export function assignWarningLabel(code: string, t: TFunction): string {
	return isAssignWarning(code) ? t(warningKeys[code]) : code;
}

export function needsForce(warnings: readonly string[]): boolean {
	return warnings.length > 0;
}

const assignableStatuses = new Set<PlanView["status"]>(["todo", "terminated"]);

export function canAssignPlan(plan: Pick<PlanView, "status">): boolean {
	return assignableStatuses.has(plan.status);
}

export function assignActionKey(plan: Pick<PlanView, "status">): "tickets.assign" | "tickets.reassign" {
	return plan.status === "terminated" ? "tickets.reassign" : "tickets.assign";
}

export function planBranchName(slug: string, file: string): string {
	const number = planNumber(file);
	const stem = file.split("/").pop()?.replace(/\.md$/, "") ?? file;
	return `opr/${slug}-${number || stem}`;
}

export type PlanDragData = { ticket: TicketWithProject; plan: PlanView };

export function planDragId(data: PlanDragData): string {
	return `plan:${data.ticket.projectId}:${data.ticket.slug}:${data.plan.file}`;
}

export const LANE_DROP_ID = "drop:lane:working";

const projectDropPrefix = "drop:project:";

export function projectDropId(projectId: string): string {
	return `${projectDropPrefix}${projectId}`;
}

export function dropAccepts(dropId: string, data: PlanDragData): boolean {
	if (dropId === LANE_DROP_ID) return true;
	if (dropId.startsWith(projectDropPrefix)) return dropId.slice(projectDropPrefix.length) === data.ticket.projectId;
	return false;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/ticket-assign.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/lib/ticket-assign.ts frontend/src/renderer/lib/ticket-assign.test.ts
git commit -m "feat(tickets): assign warning copy, assignable statuses and drag ids" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `assignPlan` and `saveTicketFile` mutations

**Files:**
- Modify: `frontend/src/renderer/hooks/useTicketMutations.ts` (error keys at lines 22-32, `roleBody` at 46-53, hook body at 66-135)
- Test: `frontend/src/renderer/hooks/useTicketMutations.test.tsx` (mock at lines 7-12 stubs `POST` and `GET`; add `PUT`)

**Interfaces:**
- Consumes: `planParam` (`useTicketMutations.ts:42-44`), `roleBody` (46-53), `unwrap` (55-59), `ticketFileQueryKey` and `TicketFile` (`useTicketsQuery.ts:8,14-15`), `apiClient` (`lib/api-client.ts:259`).
- Produces:
  - `type AssignPlanInput = PlanRef & TicketRoleInput & { dryRun?: boolean; force?: boolean; terminateSessionId?: string }`
  - `type SaveTicketFileInput = TicketRef & { path: string; content: string; ifUnmodifiedSince?: string }`
  - `apiErrorDetails(error: unknown): Record<string, unknown> | undefined`
  - `assignBlockedWarnings(error: unknown): string[]` — `details.warnings` of a `TICKET_ASSIGN_BLOCKED` envelope, else `[]`
  - `staleModifiedAt(error: unknown): string | undefined` — `details.modifiedAt` of a `TICKET_FILE_STALE` envelope
  - `useTicketMutations().assignPlan: UseMutationResult<AssignPlanResponse, unknown, AssignPlanInput>`
  - `useTicketMutations().saveTicketFile: UseMutationResult<TicketFile, unknown, SaveTicketFileInput>` — on success writes the response into the file query cache
  - `ticketErrorKeys` gains `TICKET_ASSIGN_BLOCKED`, `TICKET_FILE_STALE`, `TICKET_PATH_OUTSIDE`

- [ ] **Step 1: Extend the API mock and add failing tests**

In `useTicketMutations.test.tsx`, change the hoisted mock to include `PUT`:

```tsx
const { postMock, putMock } = vi.hoisted(() => ({ postMock: vi.fn(), putMock: vi.fn() }));

vi.mock("../lib/api-client", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../lib/api-client")>();
	return {
		...actual,
		apiClient: { POST: (...args: unknown[]) => postMock(...args), PUT: (...args: unknown[]) => putMock(...args), GET: vi.fn() },
	};
});

import { assignBlockedWarnings, planParam, staleModifiedAt, ticketErrorMessage, useTicketMutations } from "./useTicketMutations";
```

Add to `beforeEach`: `putMock.mockReset();`. Append these tests inside `describe("useTicketMutations", …)`:

```tsx
	it("sends a dry run to the bare plan route and returns the warnings", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValue({ data: { warnings: ["ticket_repo_dirty"] } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const response = await act(() =>
			result.current.assignPlan.mutateAsync({ projectId: "p1", slug: "t", plan: "plans/01-daemon.md", dryRun: true }),
		);

		expect(response.warnings).toEqual(["ticket_repo_dirty"]);
		expect(postMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
			params: { path: { id: "p1", slug: "t", plan: "01-daemon.md" }, query: { dryRun: true } },
			body: { harness: undefined, model: undefined, claudeAccountId: undefined, extra: undefined, force: undefined },
		});
	});

	it("kills the live session before a forced assign when asked to", async () => {
		const queryClient = new QueryClient();
		postMock.mockResolvedValueOnce({ data: {} }).mockResolvedValueOnce({ data: { warnings: ["plan_assigned"], session: { id: "s-2", projectId: "p1" } } });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		const response = await act(() =>
			result.current.assignPlan.mutateAsync({
				projectId: "p1",
				slug: "t",
				plan: "plans/01-daemon.md",
				force: true,
				terminateSessionId: "s-1",
				harness: "claude-code",
				model: "claude-haiku-4-5-20251001",
			}),
		);

		expect(response.session?.id).toBe("s-2");
		expect(postMock).toHaveBeenNthCalledWith(1, "/api/v1/sessions/{sessionId}/kill", { params: { path: { sessionId: "s-1" } } });
		expect(postMock).toHaveBeenNthCalledWith(2, "/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
			params: { path: { id: "p1", slug: "t", plan: "01-daemon.md" }, query: {} },
			body: { harness: "claude-code", model: "claude-haiku-4-5-20251001", claudeAccountId: undefined, extra: undefined, force: true },
		});
	});

	it("saves a file with ifUnmodifiedSince and primes the file query", async () => {
		const queryClient = new QueryClient();
		const saved = { path: "spec.md", content: "# Spec", modifiedAt: "2026-09-18T11:00:00Z" };
		putMock.mockResolvedValue({ data: saved });
		const { result } = renderHook(() => useTicketMutations(), { wrapper: wrapper(queryClient) });

		await act(() =>
			result.current.saveTicketFile.mutateAsync({
				projectId: "p1",
				slug: "t",
				path: "spec.md",
				content: "# Spec",
				ifUnmodifiedSince: "2026-09-18T10:00:00Z",
			}),
		);

		expect(putMock).toHaveBeenCalledWith("/api/v1/projects/{id}/tickets/{slug}/file", {
			params: { path: { id: "p1", slug: "t" }, query: { path: "spec.md" } },
			body: { content: "# Spec", ifUnmodifiedSince: "2026-09-18T10:00:00Z" },
		});
		expect(queryClient.getQueryData(["tickets", "p1", "t", "file", "spec.md"])).toEqual(saved);
	});
```

And a new top-level describe:

```tsx
describe("error details", () => {
	it("reads the blocked warnings and the stale timestamp from the envelope", () => {
		expect(
			assignBlockedWarnings({ error: "conflict", code: "TICKET_ASSIGN_BLOCKED", message: "x", details: { warnings: ["plan_assigned"] } }),
		).toEqual(["plan_assigned"]);
		expect(assignBlockedWarnings({ error: "conflict", code: "TICKET_NOT_FOUND", message: "x" })).toEqual([]);
		expect(
			staleModifiedAt({ error: "conflict", code: "TICKET_FILE_STALE", message: "x", details: { modifiedAt: "2026-09-18T11:00:00Z" } }),
		).toBe("2026-09-18T11:00:00Z");
		expect(staleModifiedAt({ error: "conflict", code: "TICKET_FILE_NOT_FOUND", message: "x" })).toBeUndefined();
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useTicketMutations.test.tsx`
Expected: FAIL — `assignPlan`/`saveTicketFile` undefined, `assignBlockedWarnings` not exported.

- [ ] **Step 3: Implement**

In `useTicketMutations.ts`:

Add after the existing type imports (line 12):

```ts
type AssignPlanResponse = components["schemas"]["AssignPlanResponse"];
```

Change the `useTicketsQuery` import (line 6) to:

```ts
import { ticketFileQueryKey, ticketsQueryRoot, type TicketFile } from "./useTicketsQuery";
```

Add after `SetArchivedInput` (line 20):

```ts
export type AssignPlanInput = PlanRef &
	TicketRoleInput & { dryRun?: boolean; force?: boolean; terminateSessionId?: string };
export type SaveTicketFileInput = TicketRef & { path: string; content: string; ifUnmodifiedSince?: string };
```

Add three keys to `ticketErrorKeys` (keep alphabetical order):

```ts
	TICKET_ASSIGN_BLOCKED: "tickets.error.TICKET_ASSIGN_BLOCKED",
	TICKET_FILE_STALE: "tickets.error.TICKET_FILE_STALE",
	TICKET_PATH_OUTSIDE: "tickets.error.TICKET_PATH_OUTSIDE",
```

Add after `ticketErrorMessage`:

```ts
export function apiErrorDetails(error: unknown): Record<string, unknown> | undefined {
	if (typeof error !== "object" || error === null) return undefined;
	const details = (error as { details?: unknown }).details;
	return typeof details === "object" && details !== null ? (details as Record<string, unknown>) : undefined;
}

export function assignBlockedWarnings(error: unknown): string[] {
	if (apiErrorCode(error) !== "TICKET_ASSIGN_BLOCKED") return [];
	const warnings = apiErrorDetails(error)?.warnings;
	return Array.isArray(warnings) ? warnings.filter((item): item is string => typeof item === "string") : [];
}

export function staleModifiedAt(error: unknown): string | undefined {
	if (apiErrorCode(error) !== "TICKET_FILE_STALE") return undefined;
	const modifiedAt = apiErrorDetails(error)?.modifiedAt;
	return typeof modifiedAt === "string" ? modifiedAt : undefined;
}
```

Add inside `useTicketMutations()` before the `return`:

```ts
	const assignPlan = useMutation({
		mutationFn: async (input: AssignPlanInput): Promise<AssignPlanResponse> => {
			if (input.terminateSessionId) {
				const killed = await apiClient.POST("/api/v1/sessions/{sessionId}/kill", {
					params: { path: { sessionId: input.terminateSessionId } },
				});
				if (killed.error) throw killed.error;
			}
			return unwrap(
				await apiClient.POST("/api/v1/projects/{id}/tickets/{slug}/plans/{plan}/assign", {
					params: {
						path: { id: input.projectId, slug: input.slug, plan: planParam(input.plan) },
						query: input.dryRun ? { dryRun: true } : {},
					},
					body: { ...roleBody(input), force: input.force || undefined },
				}),
			);
		},
		onSettled: (_data, _error, input) => {
			if (!input.dryRun) invalidateTickets(queryClient);
		},
	});

	const saveTicketFile = useMutation({
		mutationFn: async (input: SaveTicketFileInput): Promise<TicketFile> =>
			unwrap(
				await apiClient.PUT("/api/v1/projects/{id}/tickets/{slug}/file", {
					params: { path: { id: input.projectId, slug: input.slug }, query: { path: input.path } },
					body: { content: input.content, ifUnmodifiedSince: input.ifUnmodifiedSince },
				}),
			),
		onSuccess: (file, input) => {
			queryClient.setQueryData(ticketFileQueryKey(input.projectId, input.slug, input.path), file);
			invalidateTickets(queryClient);
		},
	});
```

and extend the return: `return { createTicket, planTicket, reviewPlan, approveMerge, markPlanDone, setArchived, assignPlan, saveTicketFile };`.

The kill call inspects only `error`, like `useTerminateSession.ts:60-66`, because the daemon's kill response body is not part of this contract.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useTicketMutations.test.tsx`
Expected: PASS. If the kill test fails on `body: undefined` vs missing key, make the assertion match what the implementation sends (`{ params }` only) — the important assertions are the call order and the bare `plan` param.

- [ ] **Step 5: Gates**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts src/renderer/hooks src/renderer/components/tickets`
Expected: clean, 0 lint errors, all passing (the existing `TicketCard`/`TicketPage` tests mock `useTicketMutations` and are unaffected).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/hooks/useTicketMutations.ts frontend/src/renderer/hooks/useTicketMutations.test.tsx
git commit -m "feat(tickets): assign and save-file mutations with dry run, force and stale details" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `AssignPlanSheet`

**Files:**
- Create: `frontend/src/renderer/components/tickets/AssignPlanSheet.tsx`
- Test: `frontend/src/renderer/components/tickets/AssignPlanSheet.test.tsx`

**Interfaces:**
- Consumes: `useTicketMutations().assignPlan`, `assignBlockedWarnings`, `ticketErrorMessage` (Task 3); `assignWarningLabel`, `needsForce`, `planBranchName` (Task 2); `planNumber` (`ticket-presentation.ts:127`); `TicketRoleFields`, `emptyTicketRoleValues`, `TicketRoleValues` (`TicketRoleFields.tsx:11-25`); the dialog frame used by `ReviewPlanSheet.tsx:79-134` (`Dialog`, `DialogContent showCloseButton={false}`, `settingsDialog*Class`, `Button variant="footer" | "footer-primary"`).
- Produces: `AssignPlanSheet({ open, onOpenChange, ticket, plan })` where `ticket: Pick<TicketWithProject, "projectId" | "slug" | "title" | "projectName">` and `plan: Pick<PlanView, "file" | "title" | "status" | "sessionId">`. Task 5 renders it from the provider; nothing renders it inside `TicketCard`.

Behaviour (spec §3.2 confirm sheet, daemon truth above):
- On open: reset fields, run `assignPlan.mutateAsync({ …ref, dryRun: true })`; while pending show `Checking…`; then list each warning on its own line via `assignWarningLabel`.
- Read-only rows: ticket title, plan `NN title`, project name, branch `planBranchName(slug, file)` with the suffix hint.
- Submit (form `onSubmit`, so Enter submits): `force: needsForce(warnings) || undefined`, `terminateSessionId: warnings.includes("plan_assigned") ? plan.sessionId : undefined`, plus the role values. On success close and navigate to `result.session`. On `409 TICKET_ASSIGN_BLOCKED` (a warning appeared between dry run and submit) adopt `details.warnings` and show the error, so the next Start forces.
- Button label: `Starting…` while busy, else `Terminate and start` when `plan_assigned` is present, else `Start`. Disabled while the dry run is pending or a submit is in flight.
- Escape / Cancel: the Radix dialog calls `onOpenChange(false)`; nothing is spawned. Closing is blocked while busy (same as `ReviewPlanSheet.tsx:79`).

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/components/tickets/AssignPlanSheet.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { navigateMock, assignMutateAsync } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	assignMutateAsync: vi.fn(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return {
		...actual,
		useTicketMutations: () => ({ assignPlan: { mutateAsync: assignMutateAsync, isPending: false } }),
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

import { AssignPlanSheet } from "./AssignPlanSheet";

const ticket = { projectId: "p1", slug: "search-page", title: "Search page", projectName: "app" };
const todoPlan = { file: "plans/01-index.md", title: "Index", status: "todo" as const };
const livePlan = { file: "plans/01-index.md", title: "Index", status: "working" as const, sessionId: "s-old" };

function dryRunThen(warnings: string[], result: unknown = { warnings, session: { id: "s-new", projectId: "p1" } }) {
	assignMutateAsync.mockImplementation(async (input: { dryRun?: boolean }) => {
		if (input.dryRun) return { warnings };
		if (result instanceof Error || (typeof result === "object" && result !== null && "code" in result)) throw result;
		return result;
	});
}

function renderSheet(plan: typeof todoPlan | typeof livePlan, onOpenChange = vi.fn()) {
	render(
		<QueryClientProvider client={new QueryClient()}>
			<AssignPlanSheet open onOpenChange={onOpenChange} ticket={ticket} plan={plan} />
		</QueryClientProvider>,
	);
	return onOpenChange;
}

beforeEach(() => {
	navigateMock.mockReset();
	assignMutateAsync.mockReset();
});

describe("AssignPlanSheet", () => {
	it("dry-runs on open, shows the read-only rows and each warning, then forces and navigates", async () => {
		dryRunThen(["ticket_repo_dirty", "plan_order"]);
		renderSheet(todoPlan);

		expect(screen.getByText("Checking…")).toBeInTheDocument();
		expect(await screen.findByText("The ticket folder has uncommitted changes. The worktree is cut from the committed branch and will not see them.")).toBeInTheDocument();
		expect(screen.getByText("An earlier plan in this ticket is not merged or done yet.")).toBeInTheDocument();
		expect(screen.getByText("opr/search-page-01")).toBeInTheDocument();
		expect(screen.getByText("01 Index")).toBeInTheDocument();
		expect(screen.getByText("app")).toBeInTheDocument();
		expect(assignMutateAsync).toHaveBeenCalledWith({ projectId: "p1", slug: "search-page", plan: "plans/01-index.md", dryRun: true });

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		await waitFor(() => expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "p1", sessionId: "s-new" },
		}));
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ plan: "plans/01-index.md", force: true, terminateSessionId: undefined }),
		);
	});

	it("does not force when the dry run is clean", async () => {
		dryRunThen([]);
		renderSheet(todoPlan);
		const start = await screen.findByRole("button", { name: "Start" });
		await waitFor(() => expect(start).toBeEnabled());

		await userEvent.click(start);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(assignMutateAsync).toHaveBeenLastCalledWith(expect.objectContaining({ force: undefined }));
	});

	it("turns Start into Terminate and start for a live plan and kills that session first", async () => {
		dryRunThen(["plan_assigned"]);
		renderSheet(livePlan);

		const button = await screen.findByRole("button", { name: "Terminate and start" });
		await userEvent.click(button);

		await waitFor(() => expect(navigateMock).toHaveBeenCalled());
		expect(assignMutateAsync).toHaveBeenLastCalledWith(
			expect.objectContaining({ force: true, terminateSessionId: "s-old" }),
		);
	});

	it("submits on Enter and cancels on Escape without spawning", async () => {
		dryRunThen([]);
		const onOpenChange = renderSheet(todoPlan);
		await waitFor(() => expect(screen.getByRole("button", { name: "Start" })).toBeEnabled());

		await userEvent.keyboard("{Escape}");
		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(assignMutateAsync).toHaveBeenCalledTimes(1);

		await userEvent.click(screen.getByLabelText("Model"));
		await userEvent.keyboard("{Enter}");
		await waitFor(() => expect(assignMutateAsync).toHaveBeenCalledTimes(2));
		expect(assignMutateAsync.mock.calls[1]?.[0]).not.toHaveProperty("dryRun");
	});

	it("adopts the daemon's warnings when a submit comes back blocked", async () => {
		dryRunThen([], { error: "conflict", code: "TICKET_ASSIGN_BLOCKED", message: "Assignment needs confirmation", details: { warnings: ["planning_active"] } });
		renderSheet(todoPlan);
		await waitFor(() => expect(screen.getByRole("button", { name: "Start" })).toBeEnabled());

		await userEvent.click(screen.getByRole("button", { name: "Start" }));

		expect(await screen.findByText("The planning session is still running.")).toBeInTheDocument();
		expect(screen.getByRole("alert")).toHaveTextContent("The assignment needs confirmation.");
		expect(navigateMock).not.toHaveBeenCalled();
	});
});
```

The Enter test focuses the mocked model `<input>` (the `extra` field is a `<textarea>`, where Enter inserts a newline), so Enter submits the enclosing form.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/AssignPlanSheet.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

`frontend/src/renderer/components/tickets/AssignPlanSheet.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { assignBlockedWarnings, ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { assignWarningLabel, needsForce, planBranchName } from "../../lib/ticket-assign";
import { planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
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

export function AssignPlanSheet({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketWithProject, "projectId" | "slug" | "title" | "projectName">;
	plan: Pick<PlanView, "file" | "title" | "status" | "sessionId">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { assignPlan } = useTicketMutations();
	const assign = assignPlan.mutateAsync;
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [warnings, setWarnings] = useState<string[] | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [busy, setBusy] = useState(false);
	const checking = warnings === null;
	const terminating = warnings?.includes("plan_assigned") ?? false;

	useEffect(() => {
		if (!open) {
			setValues(emptyTicketRoleValues);
			setWarnings(null);
			setError(null);
			setBusy(false);
			return;
		}
		let cancelled = false;
		setWarnings(null);
		setError(null);
		assign({ projectId: ticket.projectId, slug: ticket.slug, plan: plan.file, dryRun: true })
			.then((result) => {
				if (!cancelled) setWarnings(result.warnings);
			})
			.catch((err: unknown) => {
				if (cancelled) return;
				setWarnings([]);
				setError(ticketErrorMessage(err, t, "tickets.assignFailed"));
			});
		return () => {
			cancelled = true;
		};
	}, [assign, open, plan.file, t, ticket.projectId, ticket.slug]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy || warnings === null) return;
		setBusy(true);
		setError(null);
		try {
			const result = await assign({
				projectId: ticket.projectId,
				slug: ticket.slug,
				plan: plan.file,
				...values,
				force: needsForce(warnings) || undefined,
				terminateSessionId: terminating ? plan.sessionId : undefined,
			});
			onOpenChange(false);
			if (result.session) {
				void navigate({
					to: "/projects/$projectId/sessions/$sessionId",
					params: { projectId: result.session.projectId || ticket.projectId, sessionId: result.session.id },
				});
			}
		} catch (err) {
			const blocked = assignBlockedWarnings(err);
			if (blocked.length > 0) setWarnings(blocked);
			setError(ticketErrorMessage(err, t, "tickets.assignFailed"));
		} finally {
			setBusy(false);
		}
	};

	const number = planNumber(plan.file);
	const rows: Array<[string, string]> = [
		[t("tickets.assignTicket"), ticket.title],
		[t("tickets.assignPlan"), number ? `${number} ${plan.title}` : plan.title],
		[t("tickets.project"), ticket.projectName],
		[t("tickets.assignBranch"), planBranchName(ticket.slug, plan.file)],
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
						<DialogTitle className="settings-dialog-title">{t("tickets.assignTitle", { plan: plan.title })}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.assignDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 rounded-md border border-border bg-surface px-3 py-2 text-2xs">
							{rows.map(([label, value]) => (
								<div key={label} className="contents">
									<dt className="settings-field-label">{label}</dt>
									<dd className="min-w-0 truncate font-mono text-foreground" title={value}>
										{value}
									</dd>
								</div>
							))}
						</dl>
						<p className="text-caption leading-4 text-settings-muted">{t("tickets.assignBranchHint")}</p>
						<TicketRoleFields projectId={ticket.projectId} value={values} onChange={setValues} disabled={busy} />
						<div className="flex flex-col gap-1.5" role="status">
							<span className="settings-field-label">{t("tickets.assignWarnings")}</span>
							{checking ? (
								<p className="text-caption leading-4 text-settings-muted">{t("tickets.assignChecking")}</p>
							) : warnings.length === 0 ? null : (
								<ul className="flex flex-col gap-1">
									{warnings.map((code) => (
										<li key={code} className="text-caption leading-4 text-warning" data-warning={code}>
											{assignWarningLabel(code, t)}
										</li>
									))}
								</ul>
							)}
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
						<Button type="submit" variant="footer-primary" disabled={busy || checking}>
							{busy ? t("tickets.starting") : terminating ? t("tickets.terminateAndStart") : t("tickets.start")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

If the `"Before you start"` label with an empty list looks odd when there are no warnings, hide the whole block when `warnings` is an empty array; the tests only look for the warning text and the `Checking…` state.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/AssignPlanSheet.test.tsx`
Expected: PASS (5 tests).

- [ ] **Step 5: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts src/renderer/i18n src/renderer/components/tickets`
Expected: clean; the coverage test passes because every string is `t()`.

```bash
git add frontend/src/renderer/components/tickets/AssignPlanSheet.tsx frontend/src/renderer/components/tickets/AssignPlanSheet.test.tsx
git commit -m "feat(tickets): assign confirm sheet with dry-run warnings and terminate-and-start" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `TicketDndProvider` (drag context, drop targets, sheet owner) mounted in the shell

**Files:**
- Create: `frontend/src/renderer/components/tickets/TicketDndProvider.tsx`
- Test: `frontend/src/renderer/components/tickets/TicketDndProvider.test.tsx`
- Modify: `frontend/src/renderer/routes/_shell.tsx` (imports at lines 1-40; `<SidebarProvider …>` opens at line 674 and closes at line 757)

**Interfaces:**
- Consumes: `@dnd-kit/core` 6.3.1 (`DndContext`, `DragOverlay`, `PointerSensor`, `KeyboardSensor`, `useSensor`, `useSensors`, `useDraggable`, `useDroppable`, `pointerWithin`, `closestCenter`); `PlanDragData`, `planDragId`, `dropAccepts` (Task 2); `AssignPlanSheet` (Task 4).
- Produces:
  - `TicketDndProvider({ children })`
  - `useTicketDrag(): { active: PlanDragData | null; requestAssign: (ticket: TicketWithProject, plan: PlanView) => void }` — safe default outside the provider (`active: null`, `requestAssign` no-op), so existing tests that render `TicketCard`, `SessionsBoard` and `Sidebar` without the provider keep working. dnd-kit's own hooks also tolerate a missing `DndContext` (`@dnd-kit/core/dist/core.esm.js:2545-2559` create the contexts with a default value whose `dispatch` is a no-op).
  - `usePlanDraggable(data: PlanDragData, enabled: boolean): { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging }`
  - `useTicketDropTarget(id: string): { setNodeRef, isOver: boolean; accepts: boolean; dragging: boolean }` — `accepts` is true while a drag is in progress and `dropAccepts(id, active)`; `isOver` is only true when `accepts` is.
  - `type AssignRequest = PlanDragData`

Design:
- Sensors: `PointerSensor` with `activationConstraint: { distance: 4 }` (a plain click on the handle never starts a drag), `KeyboardSensor` with default codes (Space / Enter start and drop, arrows move, Escape cancels).
- Collision detection: `pointerWithin` first, `closestCenter` as fallback. Pointer drags only light a target under the pointer; keyboard drags (no pointer) reach the nearest target, so the flow is keyboard-accessible.
- `DragOverlay` renders a compact chip (`NN Title · slug`) so the row itself does not move inside the scrolling column.
- Drop with `dropAccepts(over.id, data)` → `pending = data` → the provider renders `AssignPlanSheet` (outside any card, so lesson 2 holds by construction). `requestAssign` sets the same `pending` for the non-drag Assign / Reassign actions.

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/components/tickets/TicketDndProvider.test.tsx`:

```tsx
import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { LANE_DROP_ID, projectDropId } from "../../lib/ticket-assign";
import type { PlanView, TicketWithProject } from "../../lib/ticket-presentation";

vi.mock("./AssignPlanSheet", () => ({
	AssignPlanSheet: ({ plan, ticket }: { plan: { file: string }; ticket: { slug: string } }) => (
		<div data-testid="assign-sheet">
			{ticket.slug}:{plan.file}
		</div>
	),
}));

import { TicketDndProvider, usePlanDraggable, useTicketDrag, useTicketDropTarget } from "./TicketDndProvider";

const ticket: TicketWithProject = {
	projectId: "p1",
	projectName: "app",
	slug: "search-page",
	title: "Search page",
	status: "ready",
	plans: [],
	files: [],
};
const plan: PlanView = { file: "plans/01-index.md", order: 1, title: "Index", status: "todo" };

function Handle({ enabled = true }: { enabled?: boolean }) {
	const { attributes, listeners, setNodeRef, setActivatorNodeRef } = usePlanDraggable({ ticket, plan }, enabled);
	return (
		<div ref={setNodeRef}>
			<button ref={setActivatorNodeRef} type="button" {...attributes} {...listeners}>
				handle
			</button>
		</div>
	);
}

function Target({ id }: { id: string }) {
	const { setNodeRef, accepts, isOver, dragging } = useTicketDropTarget(id);
	return <div ref={setNodeRef} data-testid={id} data-accepts={accepts} data-over={isOver} data-dragging={dragging} />;
}

function AssignButton() {
	const { requestAssign } = useTicketDrag();
	return (
		<button type="button" onClick={() => requestAssign(ticket, plan)}>
			assign
		</button>
	);
}

beforeAll(() => {
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

beforeEach(() => {
	vi.useRealTimers();
});

describe("TicketDndProvider", () => {
	it("opens the assign sheet from requestAssign without any drag", async () => {
		render(
			<TicketDndProvider>
				<AssignButton />
			</TicketDndProvider>,
		);
		await userEvent.click(screen.getByRole("button", { name: "assign" }));
		expect(screen.getByTestId("assign-sheet")).toHaveTextContent("search-page:plans/01-index.md");
	});

	it("is inert outside the provider", async () => {
		render(
			<>
				<AssignButton />
				<Target id={LANE_DROP_ID} />
			</>,
		);
		await userEvent.click(screen.getByRole("button", { name: "assign" }));
		expect(screen.queryByTestId("assign-sheet")).not.toBeInTheDocument();
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});

	it("marks accepting targets during a keyboard drag and opens the sheet on drop", async () => {
		render(
			<TicketDndProvider>
				<Handle />
				<Target id={LANE_DROP_ID} />
				<Target id={projectDropId("p2")} />
			</TicketDndProvider>,
		);
		const handle = screen.getByRole("button", { name: "handle" });
		handle.focus();

		fireEvent.keyDown(handle, { code: "Space", key: " " });
		await act(async () => {
			await new Promise((resolve) => setTimeout(resolve, 0));
		});

		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "true");
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-accepts", "true");
		expect(screen.getByTestId(projectDropId("p2"))).toHaveAttribute("data-accepts", "false");

		fireEvent.keyDown(handle, { code: "ArrowRight", key: "ArrowRight" });
		fireEvent.keyDown(handle, { code: "Space", key: " " });

		expect(await screen.findByTestId("assign-sheet")).toHaveTextContent("plans/01-index.md");
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});

	it("does not start a drag from a disabled handle", async () => {
		render(
			<TicketDndProvider>
				<Handle enabled={false} />
				<Target id={LANE_DROP_ID} />
			</TicketDndProvider>,
		);
		const handle = screen.getByRole("button", { name: "handle" });
		fireEvent.keyDown(handle, { code: "Space", key: " " });
		await act(async () => {
			await new Promise((resolve) => setTimeout(resolve, 0));
		});
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});
});
```

dnd-kit's `KeyboardSensor` binds its move/end listener in a `setTimeout` after activation (`core.esm.js:1158`), hence the zero-delay `await` after the first Space. jsdom returns zero rects, so `closestCenter` puts every target at distance 0 and the first registered one wins; with `LANE_DROP_ID` rendered first the drop lands there. If the keyboard drop still does not fire in jsdom, keep the first two tests, delete the drag tests, and note in the report that the gesture is covered by Task 12's real-renderer run instead; do not stub dnd-kit internals to force it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketDndProvider.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the provider**

`frontend/src/renderer/components/tickets/TicketDndProvider.tsx`:

```tsx
import {
	closestCenter,
	DndContext,
	DragOverlay,
	KeyboardSensor,
	PointerSensor,
	pointerWithin,
	useDraggable,
	useDroppable,
	useSensor,
	useSensors,
	type CollisionDetection,
	type DragEndEvent,
	type DragStartEvent,
} from "@dnd-kit/core";
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { dropAccepts, planDragId, type PlanDragData } from "../../lib/ticket-assign";
import { planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { AssignPlanSheet } from "./AssignPlanSheet";

export type AssignRequest = PlanDragData;

type TicketDragContextValue = {
	active: PlanDragData | null;
	requestAssign: (ticket: TicketWithProject, plan: PlanView) => void;
};

const TicketDragContext = createContext<TicketDragContextValue>({ active: null, requestAssign: () => undefined });

export function useTicketDrag(): TicketDragContextValue {
	return useContext(TicketDragContext);
}

const collisionDetection: CollisionDetection = (args) => {
	const within = pointerWithin(args);
	return within.length > 0 ? within : closestCenter(args);
};

function dragData(event: { active: { data: { current?: unknown } } }): PlanDragData | null {
	const data = event.active.data.current as PlanDragData | undefined;
	return data && data.ticket && data.plan ? data : null;
}

export function TicketDndProvider({ children }: { children: ReactNode }) {
	const [active, setActive] = useState<PlanDragData | null>(null);
	const [pending, setPending] = useState<AssignRequest | null>(null);
	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
		useSensor(KeyboardSensor),
	);
	const requestAssign = useCallback((ticket: TicketWithProject, plan: PlanView) => setPending({ ticket, plan }), []);
	const onDragStart = (event: DragStartEvent) => setActive(dragData(event));
	const onDragEnd = (event: DragEndEvent) => {
		const data = dragData(event);
		setActive(null);
		if (!data || !event.over) return;
		if (dropAccepts(String(event.over.id), data)) setPending(data);
	};
	const value = useMemo(() => ({ active, requestAssign }), [active, requestAssign]);

	return (
		<TicketDragContext.Provider value={value}>
			<DndContext
				sensors={sensors}
				collisionDetection={collisionDetection}
				onDragStart={onDragStart}
				onDragEnd={onDragEnd}
				onDragCancel={() => setActive(null)}
			>
				{children}
				<DragOverlay dropAnimation={null}>{active ? <PlanDragChip data={active} /> : null}</DragOverlay>
			</DndContext>
			{pending ? (
				<AssignPlanSheet
					open
					onOpenChange={(open) => !open && setPending(null)}
					ticket={pending.ticket}
					plan={pending.plan}
				/>
			) : null}
		</TicketDragContext.Provider>
	);
}

function PlanDragChip({ data }: { data: PlanDragData }) {
	const number = planNumber(data.plan.file);
	return (
		<div className="pointer-events-none inline-flex max-w-72 items-center gap-2 rounded-md border border-border-strong bg-surface px-2.5 py-1.5 text-2xs shadow-md">
			<span className="shrink-0 font-mono text-micro text-passive">{number || "·"}</span>
			<span className="min-w-0 truncate font-medium text-foreground">{data.plan.title}</span>
			<span className="shrink-0 font-mono text-micro text-passive">{data.ticket.slug}</span>
		</div>
	);
}

export function usePlanDraggable(data: PlanDragData, enabled: boolean) {
	const { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
		id: planDragId(data),
		data,
		disabled: !enabled,
	});
	return { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging };
}

export function useTicketDropTarget(id: string) {
	const { active } = useTicketDrag();
	const { setNodeRef, isOver } = useDroppable({ id });
	const accepts = active !== null && dropAccepts(id, active);
	return { setNodeRef, isOver: isOver && accepts, accepts, dragging: active !== null };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketDndProvider.test.tsx`
Expected: PASS (4 tests, or 2 with the documented fallback).

- [ ] **Step 5: Mount the provider in the shell**

In `frontend/src/renderer/routes/_shell.tsx` add the import next to the other component imports (after line 17, `import { Sidebar } …`):

```tsx
import { TicketDndProvider } from "../components/tickets/TicketDndProvider";
```

Wrap the `SidebarProvider` block: insert `<TicketDndProvider>` on the line before `<SidebarProvider` (line 674) and `</TicketDndProvider>` on the line after `</SidebarProvider>` (line 757). Keep the existing indentation style of that file (it is already irregular; do not reformat neighbouring lines).

- [ ] **Step 6: Gates**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: clean, 0 lint errors, all tests pass (no test renders `_shell.tsx`; `SessionsBoard`, `Sidebar`, `TicketCard` tests still render without the provider and pass because of the safe defaults).

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/components/tickets/TicketDndProvider.tsx frontend/src/renderer/components/tickets/TicketDndProvider.test.tsx frontend/src/renderer/routes/_shell.tsx
git commit -m "feat(tickets): drag context around the shell that opens the assign sheet on drop" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Plan rows become draggable and get Assign / Reassign; card and page wiring

**Files:**
- Modify: `frontend/src/renderer/components/tickets/PlanRow.tsx` (props at lines 9-18, row root at 57-64, action row at 100-153)
- Modify: `frontend/src/renderer/components/tickets/TicketCard.tsx` (imports 1-13, `PlanRow` usage at 103-108)
- Modify: `frontend/src/renderer/components/tickets/TicketPage.tsx` (imports 1-26, `sessionsById` build at 42-47, `PlanRow` usage at 136-150)
- Test: `frontend/src/renderer/components/tickets/TicketCard.test.tsx` (mocks at 9-31), `frontend/src/renderer/components/tickets/TicketPage.test.tsx` (mocks at 7-29)

**Interfaces:**
- Consumes: `usePlanDraggable`, `useTicketDrag` (Task 5); `canAssignPlan`, `assignActionKey` (Task 2); `GripVertical` from `lucide-react`.
- Produces: `PlanRowProps` gains `ticket: TicketWithProject` (required), `draggable?: boolean`, `onAssign?: (plan: PlanView) => void`. `PlanRow` is used only by `TicketCard.tsx` and `TicketPage.tsx` (verified with `grep -rln PlanRow frontend/src/renderer`).

Behaviour:
- A `GripVertical` handle appears at the start of rows where `draggable && canAssignPlan(plan)`; it carries dnd-kit's `attributes` and `listeners`, `aria-label` `Drag {{plan}} to assign it`, and stops `click`, `pointerdown` and `keydown` propagation before delegating to dnd-kit, so neither a click nor a drag start opens the ticket card (lesson 2). The row root gets `setNodeRef` and `opacity-40` while dragging.
- An `Assign` (todo) / `Reassign` (terminated, spec §4) action renders in the action row when `onAssign` is given and `canAssignPlan(plan)`; it stops propagation like the other row actions.
- `TicketCard` passes `ticket`, `draggable`, and `onAssign={(plan) => requestAssign(ticket, plan)}`. `TicketPage` builds a `TicketWithProject` from the workspace name and passes the same, so the sheet is reachable without dragging (keyboard, mobile-later).

- [ ] **Step 1: Add the provider mock and failing tests to `TicketCard.test.tsx`**

Add to the hoisted block: `requestAssignMock: vi.fn(),` and after the existing mocks:

```tsx
vi.mock("./TicketDndProvider", () => ({
	useTicketDrag: () => ({ active: null, requestAssign: requestAssignMock }),
	usePlanDraggable: () => ({
		attributes: {},
		listeners: {},
		setNodeRef: () => undefined,
		setActivatorNodeRef: () => undefined,
		isDragging: false,
	}),
}));
```

Reset it in `beforeEach`: `requestAssignMock.mockReset();`. Add tests:

```tsx
	it("offers Assign on a todo plan and a drag handle, without opening the ticket", async () => {
		const data = ticket({
			status: "ready",
			plans: [
				{ file: "plans/01-index.md", order: 1, title: "Index", status: "todo" },
				{ file: "plans/02-ui.md", order: 2, title: "UI", status: "working", sessionId: "s-2" },
			],
		});
		renderCard(data, [session({ id: "s-2" })]);

		expect(screen.getByRole("button", { name: "Drag Index to assign it" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Drag UI to assign it" })).not.toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Drag Index to assign it" }));
		await userEvent.click(screen.getByRole("button", { name: "Assign" }));

		expect(requestAssignMock).toHaveBeenCalledWith(data, expect.objectContaining({ file: "plans/01-index.md" }));
		expect(navigateMock).not.toHaveBeenCalled();
	});

	it("offers Reassign on a terminated plan", async () => {
		renderCard(
			ticket({
				status: "in_progress",
				plans: [{ file: "plans/01-index.md", order: 1, title: "Index", status: "terminated", sessionId: "s-gone" }],
			}),
		);
		await userEvent.click(screen.getByRole("button", { name: "Reassign" }));
		expect(requestAssignMock).toHaveBeenCalledWith(expect.objectContaining({ slug: "search-page" }), expect.objectContaining({ status: "terminated" }));
		expect(navigateMock).not.toHaveBeenCalled();
	});
```

- [ ] **Step 2: Add the provider mock and a failing test to `TicketPage.test.tsx`**

Add `requestAssignMock: vi.fn()` to the hoisted block, the same `vi.mock("./TicketDndProvider", …)` as above, reset in `beforeEach`, and:

```tsx
	it("offers Assign on a todo plan from the file list", async () => {
		ticketQueryMock.mockReturnValue({
			data: { ...ticket, plans: [...ticket.plans, { file: "plans/03-docs.md", order: 3, title: "Docs", status: "todo" as const }] },
			isError: false,
			isSuccess: true,
		});
		renderPage();
		await userEvent.click(screen.getByRole("button", { name: "Assign" }));
		expect(requestAssignMock).toHaveBeenCalledWith(
			expect.objectContaining({ slug: "search-page", projectName: "app" }),
			expect.objectContaining({ file: "plans/03-docs.md" }),
		);
	});
```

Check the existing `workspaceQueryMock` return in that file's `beforeEach` (line ~70 onwards): the workspace must have `id: "p1"` and `name: "app"` for `projectName: "app"`; if its name differs, use that name in the assertion.

- [ ] **Step 3: Run both test files to verify the new tests fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketCard.test.tsx src/renderer/components/tickets/TicketPage.test.tsx`
Expected: the three new tests FAIL (no Assign button / handle); the existing ones pass.

- [ ] **Step 4: Change `PlanRow.tsx`**

Replace the imports and props (lines 1-18) with:

```tsx
import { AlertTriangle, GripVertical } from "lucide-react";
import type { KeyboardEvent, MouseEvent, PointerEvent } from "react";
import { useTranslation } from "react-i18next";
import { getAgentActivityView } from "../../lib/session-presentation";
import { assignActionKey, canAssignPlan } from "../../lib/ticket-assign";
import { getPlanStatusView, planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { usePlanDraggable } from "./TicketDndProvider";

export type PlanRowProps = {
	ticket: TicketWithProject;
	plan: PlanView;
	session?: WorkspaceSession;
	draggable?: boolean;
	onOpenSession: (sessionId: string) => void;
	onAssign?: (plan: PlanView) => void;
	onReview?: (plan: PlanView) => void;
	onMerge?: (plan: PlanView) => void;
	onMarkDone?: (plan: PlanView) => void;
	onOpenFile?: (file: string) => void;
	selectedFile?: string;
};
```

In the component signature add `ticket`, `draggable = false`, `onAssign`. After `const selected = …` (line 54) add:

```tsx
	const assignable = canAssignPlan(plan);
	const drag = usePlanDraggable({ ticket, plan }, draggable && assignable);
	const showAssign = onAssign && assignable;
	const showHandle = draggable && assignable;
	const dragListeners = drag.listeners ?? {};
	const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		dragListeners.onPointerDown?.(event);
	};
	const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		dragListeners.onKeyDown?.(event);
	};
```

Change the row root (lines 57-64) to:

```tsx
		<div
			ref={drag.setNodeRef}
			className={cn(
				"flex flex-col gap-1 rounded-md px-1.5 py-1 text-2xs",
				selected && "bg-interactive-hover",
				drag.isDragging && "opacity-40",
			)}
			data-plan-file={plan.file}
			data-testid="ticket-plan-row"
		>
```

Insert the handle as the first child of the title line (before the `<span className="w-5 …">{number || "·"}</span>` at line 66):

```tsx
				{showHandle ? (
					<button
						ref={drag.setActivatorNodeRef}
						type="button"
						aria-label={t("tickets.dragHandleAria", { plan: plan.title })}
						className="inline-flex size-control-md shrink-0 cursor-grab items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 active:cursor-grabbing"
						{...drag.attributes}
						onClick={stop}
						onKeyDown={handleKeyDown}
						onPointerDown={handlePointerDown}
					>
						<GripVertical aria-hidden="true" className="size-icon-2xs" />
					</button>
				) : null}
```

Change the action-row condition (line 100) to `{sessionId || showAssign || showReview || showMerge || showDone ? (` and add the Assign button right after `<span className="flex-1" />` (line 114):

```tsx
						{showAssign ? (
							<button
								type="button"
								className={cn(rowActionClass, "text-foreground")}
								data-testid="plan-assign-button"
								onClick={(event) => {
									stop(event);
									onAssign(plan);
								}}
							>
								{t(assignActionKey(plan))}
							</button>
						) : null}
```

`drag.attributes` includes `role="button"` and `tabIndex`; spreading them onto a real `<button>` is harmless. The explicit `onKeyDown`/`onPointerDown` props come after the spread so they win, and they call dnd-kit's handlers themselves.

- [ ] **Step 5: Wire `TicketCard.tsx`**

Add the import `import { useTicketDrag } from "./TicketDndProvider";` and inside the component `const { requestAssign } = useTicketDrag();`. Change the `PlanRow` usage to:

```tsx
									<PlanRow
										ticket={ticket}
										plan={plan}
										draggable
										session={plan.sessionId ? sessionsById.get(plan.sessionId) : undefined}
										onOpenSession={openSession}
										onAssign={(target) => requestAssign(ticket, target)}
										onReview={(target) => setReviewPlan(target)}
									/>
```

- [ ] **Step 6: Wire `TicketPage.tsx`**

Add `import { useTicketDrag } from "./TicketDndProvider";` and `import type { TicketWithProject } from "../../lib/ticket-presentation"` (merge into the existing `ticket-presentation` import). Inside the component, after the `sessionsById` loop (line 47), add:

```tsx
	const projectName = workspaces.find((workspace) => workspace.id === projectId)?.name ?? "";
	const { requestAssign } = useTicketDrag();
```

After `if (!ticket) return null;` (line 71) add `const ticketWithProject: TicketWithProject = { ...ticket, projectName };` and change the `PlanRow` usage to pass `ticket={ticketWithProject}`, `draggable`, and `onAssign={(target) => requestAssign(ticketWithProject, target)}`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets`
Expected: PASS, including the existing `TicketCard` merge test's `navigateMock` assertion.

- [ ] **Step 8: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: clean.

```bash
git add frontend/src/renderer/components/tickets/PlanRow.tsx frontend/src/renderer/components/tickets/TicketCard.tsx frontend/src/renderer/components/tickets/TicketCard.test.tsx frontend/src/renderer/components/tickets/TicketPage.tsx frontend/src/renderer/components/tickets/TicketPage.test.tsx
git commit -m "feat(tickets): draggable plan rows with Assign and Reassign actions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Drop targets — IDLE / WORKING column and sidebar project headers, dimming and highlight

**Files:**
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx` (imports 1-76; board grid at 388-392; `WorkLaneColumn` 643-672; `SplitLaneColumn` 709-794; intake chip 1079-1086)
- Modify: `frontend/src/renderer/styles.css` (append after the `.board-scrollbar` rules, around line 1340)
- Modify: `frontend/src/renderer/components/Sidebar.tsx` (imports at the top; `ProjectItem` visual row wrapper at 578-588)
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx` (mocks at 30-60), `frontend/src/renderer/components/Sidebar.test.tsx` (mocks around 47)

**Interfaces:**
- Consumes: `useTicketDrag`, `useTicketDropTarget` (Task 5); `LANE_DROP_ID`, `projectDropId` (Task 2).
- Produces: DOM contract for tests and Task 12: the board grid carries `data-board-grid` and `data-dragging="true|false"`; the working column `<section data-column="working">` carries `data-drop-accepts` and `data-drop-over`; each sidebar project row wrapper (`[data-project-press]`) carries `data-drop-accepts` and `data-drop-over`.

Design (spec §3.2: "other columns dim; the target shows the dashed highlight already used for empty lanes"): there is no dashed empty-lane style in the board today (not known in the shipped code; see the header), so the highlight is designed from the board's tokens: the target column's scroll body gets `outline-dashed outline-1 outline-border-strong -outline-offset-4 rounded-lg` while a drag that it accepts is in progress, `bg-interactive-hover/40` while the pointer is over it, and a `Drop to assign` caption at the bottom. Every other column dims to `opacity-40` through one CSS rule keyed on the grid's `data-dragging`.

- [ ] **Step 1: Add mocks and failing tests to `SessionsBoard.test.tsx`**

Hoist two mocks:

```tsx
const { ticketDragMock, dropTargetMock } = vi.hoisted(() => ({
	ticketDragMock: vi.fn(() => ({ active: null as unknown, requestAssign: vi.fn() })),
	dropTargetMock: vi.fn((id: string) => ({ setNodeRef: () => undefined, isOver: false, accepts: false, dragging: false, id })),
}));

vi.mock("./tickets/TicketDndProvider", () => ({
	useTicketDrag: () => ticketDragMock(),
	useTicketDropTarget: (id: string) => dropTargetMock(id),
	usePlanDraggable: () => ({
		attributes: {},
		listeners: {},
		setNodeRef: () => undefined,
		setActivatorNodeRef: () => undefined,
		isDragging: false,
	}),
}));
```

Reset both in `beforeEach` (`ticketDragMock.mockReset().mockReturnValue({ active: null, requestAssign: vi.fn() }); dropTargetMock.mockReset().mockImplementation((id) => ({ setNodeRef: () => undefined, isOver: false, accepts: false, dragging: false, id }));`). Add tests next to the planned-column test (line 1308):

```tsx
	it("registers the working column as the lane drop target and stays undimmed at rest", () => {
		workspaceQueryMock.mockReturnValue({
			data: [{ ...workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working" })]), kind: "single_repo" }],
			isError: false,
			isSuccess: true,
		});
		renderBoard("p1");

		expect(dropTargetMock).toHaveBeenCalledWith("drop:lane:working");
		expect(screen.getByTestId("board-grid")).toHaveAttribute("data-dragging", "false");
		const working = screen.getAllByTestId("board-column").find((column) => column.getAttribute("data-column") === "working");
		expect(working).toHaveAttribute("data-drop-accepts", "false");
		expect(screen.queryByText("Drop to assign")).not.toBeInTheDocument();
	});

	it("dims the board and highlights the working column while a plan is dragged", () => {
		workspaceQueryMock.mockReturnValue({
			data: [{ ...workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working" })]), kind: "single_repo" }],
			isError: false,
			isSuccess: true,
		});
		ticketDragMock.mockReturnValue({ active: { ticket: { projectId: "p1" }, plan: { file: "plans/01-a.md" } }, requestAssign: vi.fn() });
		dropTargetMock.mockImplementation((id) => ({ setNodeRef: () => undefined, isOver: id === "drop:lane:working", accepts: id === "drop:lane:working", dragging: true, id }));
		renderBoard("p1");

		expect(screen.getByTestId("board-grid")).toHaveAttribute("data-dragging", "true");
		const working = screen.getAllByTestId("board-column").find((column) => column.getAttribute("data-column") === "working");
		expect(working).toHaveAttribute("data-drop-accepts", "true");
		expect(working).toHaveAttribute("data-drop-over", "true");
		expect(within(working!).getByText("Drop to assign")).toBeInTheDocument();
	});

	it("renders the intake chip with a visible bordered look", () => {
		workspaceQueryMock.mockReturnValue({
			data: [workspaceWithSessions([boardSession({ id: "s-1", title: "worker", status: "working", issueId: "github:42" })])],
			isError: false,
			isSuccess: true,
		});
		renderBoard("p1");
		const chip = screen.getByTitle("Intake issue: github:42");
		expect(chip.className).not.toMatch(/text-accent|bg-accent/);
		expect(chip.className).toMatch(/border-border/);
	});
```

`boardSession` (`SessionsBoard.test.tsx:1541-1553`) accepts any `Partial<WorkspaceSession>`, so `issueId` passes straight through; the chip renders only for provider-prefixed ids (`canonicalTrackerIssueId`, `types/workspace.ts:201-204`, prefix `github:`) and its title is `shell.intakeIssue` = `Intake issue: {{id}}` (`en.json:718`).

- [ ] **Step 2: Add a mock and a failing test to `Sidebar.test.tsx`**

Add:

```tsx
const { sidebarDropMock } = vi.hoisted(() => ({
	sidebarDropMock: vi.fn((id: string) => ({ setNodeRef: () => undefined, isOver: false, accepts: false, dragging: false, id })),
}));

vi.mock("./tickets/TicketDndProvider", () => ({
	useTicketDropTarget: (id: string) => sidebarDropMock(id),
	useTicketDrag: () => ({ active: null, requestAssign: () => undefined }),
}));
```

and a test that renders the sidebar (use the file's `renderSidebar` helper and its `workspace` fixture; read `workspace.id` there):

```tsx
	it("registers each project row as a drop target and highlights it while accepting", () => {
		sidebarDropMock.mockImplementation((id) => ({ setNodeRef: () => undefined, isOver: true, accepts: true, dragging: true, id }));
		renderSidebar({});
		expect(sidebarDropMock).toHaveBeenCalledWith(`drop:project:${workspace.id}`);
		const row = document.querySelector("[data-project-press]");
		expect(row).toHaveAttribute("data-drop-accepts", "true");
		expect(row).toHaveAttribute("data-drop-over", "true");
		expect(row).toHaveAttribute("aria-label", `Assign a plan to ${workspace.name}`);
	});
```

- [ ] **Step 3: Run both test files to verify the new tests fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test.tsx src/renderer/components/Sidebar.test.tsx`
Expected: the four new tests FAIL; the rest pass.

- [ ] **Step 4: Change `SessionsBoard.tsx`**

Imports: add

```tsx
import { LANE_DROP_ID } from "../lib/ticket-assign";
import { useTicketDrag, useTicketDropTarget } from "./tickets/TicketDndProvider";
```

In `SessionsBoard` after `const supportsTickets = …` (line 118) add `const { active: draggingPlan } = useTicketDrag();`. Change the grid div (line 388) to:

```tsx
						<div
							className="relative grid h-full min-w-[80rem] grid-cols-5 divide-x divide-border-strong xl:min-w-0"
							data-board-grid=""
							data-dragging={draggingPlan !== null}
							data-testid="board-grid"
						>
```

`WorkLaneColumn` (643-672): add `const dropTarget = useTicketDropTarget(LANE_DROP_ID);` and pass `dropTarget={dropTarget}` to `SplitLaneColumn`. Add to `SplitLaneColumn`'s props type:

```tsx
	dropTarget?: { setNodeRef: (node: HTMLElement | null) => void; isOver: boolean; accepts: boolean; dragging: boolean };
```

and change its `<section>` (lines 729-734) to:

```tsx
		<section
			ref={dropTarget?.setNodeRef}
			aria-label={ariaLabel}
			className="flex min-w-0 flex-col overflow-hidden"
			data-column={zone}
			data-drop-accepts={dropTarget?.accepts ?? false}
			data-drop-over={dropTarget?.isOver ?? false}
			data-testid="board-column"
		>
```

and the scroll body (line 757-758) to:

```tsx
			<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-3">
				<div
					className={cn(
						"flex min-h-full flex-col transition-[background-color,outline-color] duration-150",
						dropTarget?.accepts && "rounded-lg outline-dashed outline-1 -outline-offset-4 outline-border-strong",
						dropTarget?.isOver && "bg-interactive-hover/40",
					)}
				>
```

and, as the last child inside that inner div (after the `showSecondary` block), the caption:

```tsx
					{dropTarget?.accepts ? (
						<p className="mt-auto pt-3 text-center text-2xs font-medium text-muted-foreground" role="status">
							{t("tickets.dropToAssign")}
						</p>
					) : null}
```

Intake chip (line 1081): replace `bg-accent/12 px-1.5 py-0.5 font-mono text-micro text-accent` with `border border-border bg-surface px-1.5 py-0.5 font-mono text-micro text-muted-foreground`.

- [ ] **Step 5: Add the dimming rule to `styles.css`**

After the `.board-scrollbar` rules (around line 1340) add:

```css
[data-board-grid][data-dragging="true"] > [data-column]:not([data-drop-accepts="true"]) {
	opacity: 0.4;
	transition: opacity 150ms ease-out;
}
```

- [ ] **Step 6: Change `Sidebar.tsx`**

Imports: `import { projectDropId } from "../lib/ticket-assign";` and `import { useTicketDropTarget } from "./tickets/TicketDndProvider";`. In `ProjectItem`, after `const { mutate: openShellTerminal, … }` (line 470) add `const drop = useTicketDropTarget(projectDropId(workspace.id));`. Change the visual row wrapper (lines 578-588) to:

```tsx
		<div
			ref={drop.setNodeRef}
			aria-label={drop.accepts ? t("tickets.dropOnProjectAria", { name: workspace.name }) : undefined}
			className={cn(
				"relative rounded-md transition-[transform,background-color] duration-[100ms] ease-out",
				projectPressed && "scale-[0.98]",
				drop.accepts && "outline-dashed outline-1 -outline-offset-2 outline-border-strong",
				drop.isOver && "bg-interactive-hover",
			)}
			data-drop-accepts={drop.accepts}
			data-drop-over={drop.isOver}
			data-project-press=""
			onPointerCancel={() => setProjectPressed(false)}
			onPointerDown={() => setProjectPressed(true)}
			onPointerLeave={() => setProjectPressed(false)}
			onPointerUp={() => setProjectPressed(false)}
		>
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test.tsx src/renderer/components/Sidebar.test.tsx`
Expected: PASS.

- [ ] **Step 8: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: clean.

```bash
git add frontend/src/renderer/components/SessionsBoard.tsx frontend/src/renderer/components/SessionsBoard.test.tsx frontend/src/renderer/components/Sidebar.tsx frontend/src/renderer/components/Sidebar.test.tsx frontend/src/renderer/styles.css
git commit -m "feat(tickets): drop plans on the working column or a sidebar project" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: `CodeMirrorField` (CodeMirror 6 mount) and the heading-follow helper

**Files:**
- Modify: `frontend/package.json`, `frontend/package-lock.json` (new dependencies)
- Create: `frontend/src/renderer/components/tickets/CodeMirrorField.tsx`
- Test: `frontend/src/renderer/components/tickets/CodeMirrorField.test.tsx`
- Create: `frontend/src/renderer/lib/markdown-scroll-sync.ts`
- Test: `frontend/src/renderer/lib/markdown-scroll-sync.test.ts`

**Interfaces:**
- Consumes: `--font-family-mono` (`frontend/src/styles/tokens.css:44-47`, the terminal's mono stack, aliased as `--font-mono` at `styles.css:29`); skin colour tokens `--color-bg-terminal-opaque`, `--color-text-primary`, `--color-text-passive` (`frontend/src/renderer/theme/token-map.generated.ts:85` and neighbours; the renderer's `--color-terminal-opaque` at `styles.css:121` is an alias of the first) and `--color-interactive-hover` (`styles.css:279`).
- Produces:
  - `CodeMirrorField({ value, onChange, onSave, onTopLineChange?, ariaLabel, autoFocus? })` — an uncontrolled-in-DOM, controlled-by-prop editor: external `value` changes replace the document; user edits call `onChange(nextDoc)`; `Mod-s` (Cmd on macOS, Ctrl elsewhere, decided by CodeMirror) calls `onSave()` and swallows the browser default; scrolling calls `onTopLineChange(lineNumber)` with the 1-based line at the top of the viewport.
  - `headingIndexBeforeLine(content: string, line: number): number` — index (0-based, in document order) of the last ATX heading (`#`…`######` followed by a space) on or before 1-based `line`, skipping fenced code blocks and a leading YAML frontmatter block; `-1` when none.

- [ ] **Step 1: Install the CodeMirror packages**

Run from `frontend/`:

```bash
npm install @codemirror/state@6.7.5 @codemirror/view@6.43.12 @codemirror/lang-markdown@6.5.2 @codemirror/commands@6.11.1
```

Expected: `package.json` `dependencies` gains the four exact entries (`^6.7.5` etc. is fine; the lock pins them), `package-lock.json` updates, and `@codemirror/language` appears in the lock as a transitive dependency of `lang-markdown`. If `npm view @codemirror/view version` prints a newer patch, use that and record the version in the report.

- [ ] **Step 2: Write the failing helper test**

`frontend/src/renderer/lib/markdown-scroll-sync.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { headingIndexBeforeLine } from "./markdown-scroll-sync";

const doc = [
	"---",
	"title: \"Search page\"",
	"---",
	"",
	"# Spec",
	"",
	"Intro.",
	"",
	"## Goals",
	"",
	"```md",
	"# not a heading",
	"```",
	"",
	"### Details",
	"text",
].join("\n");

describe("headingIndexBeforeLine", () => {
	it("returns -1 before the first heading and inside the frontmatter", () => {
		expect(headingIndexBeforeLine(doc, 1)).toBe(-1);
		expect(headingIndexBeforeLine(doc, 4)).toBe(-1);
	});

	it("returns the index of the last heading at or before the line", () => {
		expect(headingIndexBeforeLine(doc, 5)).toBe(0);
		expect(headingIndexBeforeLine(doc, 7)).toBe(0);
		expect(headingIndexBeforeLine(doc, 9)).toBe(1);
		expect(headingIndexBeforeLine(doc, 15)).toBe(2);
		expect(headingIndexBeforeLine(doc, 99)).toBe(2);
	});

	it("ignores headings inside fenced code", () => {
		expect(headingIndexBeforeLine(doc, 12)).toBe(1);
	});
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/markdown-scroll-sync.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Write the helper**

`frontend/src/renderer/lib/markdown-scroll-sync.ts`:

```ts
const fence = /^(```|~~~)/;
const heading = /^#{1,6}\s/;

export function headingIndexBeforeLine(content: string, line: number): number {
	const lines = content.split("\n");
	let start = 0;
	if (lines[0] === "---") {
		const end = lines.indexOf("---", 1);
		if (end !== -1) start = end + 1;
	}
	let index = -1;
	let inFence = false;
	for (let i = start; i < lines.length && i < line; i++) {
		const text = lines[i] ?? "";
		if (fence.test(text)) {
			inFence = !inFence;
			continue;
		}
		if (!inFence && heading.test(text)) index++;
	}
	return index;
}
```

- [ ] **Step 5: Run the helper test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/markdown-scroll-sync.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Write the failing CodeMirror smoke test**

`frontend/src/renderer/components/tickets/CodeMirrorField.test.tsx`:

```tsx
import { EditorView } from "@codemirror/view";
import { act, fireEvent, render, screen } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { CodeMirrorField } from "./CodeMirrorField";

beforeAll(() => {
	const emptyRect = { x: 0, y: 0, width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0, toJSON: () => ({}) } as DOMRect;
	Range.prototype.getBoundingClientRect = () => emptyRect;
	Range.prototype.getClientRects = () =>
		({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

function viewOf(testId = "codemirror-field"): EditorView {
	const view = EditorView.findFromDOM(screen.getByTestId(testId) as HTMLElement);
	if (!view) throw new Error("no editor view mounted");
	return view;
}

describe("CodeMirrorField", () => {
	it("mounts a labelled markdown editor with the initial value", () => {
		render(<CodeMirrorField value="# Hello" onChange={vi.fn()} onSave={vi.fn()} ariaLabel="Edit spec.md" />);
		expect(screen.getByLabelText("Edit spec.md")).toHaveClass("cm-content");
		expect(viewOf().state.doc.toString()).toBe("# Hello");
	});

	it("reports edits and adopts external value changes", () => {
		const onChange = vi.fn();
		const { rerender } = render(<CodeMirrorField value="one" onChange={onChange} onSave={vi.fn()} ariaLabel="Edit" />);
		act(() => {
			viewOf().dispatch({ changes: { from: 3, insert: " two" } });
		});
		expect(onChange).toHaveBeenCalledWith("one two");

		rerender(<CodeMirrorField value="three" onChange={onChange} onSave={vi.fn()} ariaLabel="Edit" />);
		expect(viewOf().state.doc.toString()).toBe("three");
	});

	it("runs onSave for Mod-s and swallows the browser default", () => {
		const onSave = vi.fn();
		render(<CodeMirrorField value="x" onChange={vi.fn()} onSave={onSave} ariaLabel="Edit" />);
		const content = screen.getByLabelText("Edit");
		const prevented = !fireEvent.keyDown(content, { key: "s", code: "KeyS", ctrlKey: true });
		expect(onSave).toHaveBeenCalledTimes(1);
		expect(prevented).toBe(true);
	});
});
```

jsdom's user agent is not macOS, so CodeMirror resolves `Mod` to Ctrl there; the real app resolves it to Cmd on macOS. If CodeMirror still throws in jsdom after the two `Range` stubs, add exactly the missing stub it names to this test file's `beforeAll` (not to the shared `test/setup.ts`) and record it in the report.

- [ ] **Step 7: Run it to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/CodeMirrorField.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 8: Write the component**

`frontend/src/renderer/components/tickets/CodeMirrorField.tsx`:

```tsx
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from "@codemirror/view";
import { useEffect, useRef } from "react";

const editorTheme = EditorView.theme(
	{
		"&": {
			height: "100%",
			backgroundColor: "var(--color-bg-terminal-opaque)",
			color: "var(--color-text-primary)",
			fontSize: "12.5px",
		},
		".cm-scroller": { fontFamily: "var(--font-family-mono)", lineHeight: "1.6", overflow: "auto" },
		".cm-content": { padding: "12px 0", caretColor: "var(--color-text-primary)" },
		".cm-line": { padding: "0 16px" },
		".cm-gutters": {
			backgroundColor: "transparent",
			color: "var(--color-text-passive)",
			border: "none",
			paddingLeft: "8px",
		},
		".cm-activeLine, .cm-activeLineGutter": { backgroundColor: "var(--color-interactive-hover)" },
		"&.cm-focused": { outline: "none" },
		".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
			backgroundColor: "var(--color-interactive-hover)",
		},
		".cm-cursor": { borderLeftColor: "var(--color-text-primary)" },
	},
	{ dark: true },
);

type Callbacks = {
	onChange: (next: string) => void;
	onSave: () => void;
	onTopLineChange?: (line: number) => void;
};

function topLine(view: EditorView): number {
	const rect = view.scrollDOM.getBoundingClientRect();
	const pos = view.posAtCoords({ x: rect.left + 1, y: rect.top + 1 }, false);
	return view.state.doc.lineAt(pos).number;
}

export function CodeMirrorField({
	value,
	onChange,
	onSave,
	onTopLineChange,
	ariaLabel,
	autoFocus = false,
}: Callbacks & { value: string; ariaLabel: string; autoFocus?: boolean }) {
	const host = useRef<HTMLDivElement>(null);
	const viewRef = useRef<EditorView | null>(null);
	const callbacks = useRef<Callbacks>({ onChange, onSave, onTopLineChange });
	callbacks.current = { onChange, onSave, onTopLineChange };
	const initialValue = useRef(value);

	useEffect(() => {
		const parent = host.current;
		if (!parent) return;
		const state = EditorState.create({
			doc: initialValue.current,
			extensions: [
				lineNumbers(),
				highlightActiveLine(),
				highlightActiveLineGutter(),
				history(),
				markdown(),
				EditorView.lineWrapping,
				keymap.of([
					{
						key: "Mod-s",
						preventDefault: true,
						run: () => {
							callbacks.current.onSave();
							return true;
						},
					},
					...defaultKeymap,
					...historyKeymap,
				]),
				EditorView.updateListener.of((update) => {
					if (update.docChanged) callbacks.current.onChange(update.state.doc.toString());
				}),
				EditorView.domEventHandlers({
					scroll: (_event, view) => {
						callbacks.current.onTopLineChange?.(topLine(view));
						return false;
					},
				}),
				EditorView.contentAttributes.of({ "aria-label": ariaLabel }),
				editorTheme,
			],
		});
		const view = new EditorView({ state, parent });
		viewRef.current = view;
		return () => {
			view.destroy();
			viewRef.current = null;
		};
	}, [ariaLabel]);

	useEffect(() => {
		if (autoFocus) viewRef.current?.focus();
	}, [autoFocus]);

	useEffect(() => {
		const view = viewRef.current;
		if (!view) return;
		const current = view.state.doc.toString();
		if (current === value) return;
		view.dispatch({ changes: { from: 0, to: current.length, insert: value } });
	}, [value]);

	return <div ref={host} className="min-h-0 flex-1 overflow-hidden [&_.cm-editor]:h-full" data-testid="codemirror-field" />;
}
```

`keymap` bindings accept `preventDefault: true` (`@codemirror/view` `KeyBinding.preventDefault`); with it, the `Mod-s` keydown is cancelled even though `run` returns `true` anyway. `findFromDOM` is a static on `EditorView` in `@codemirror/view` 6.x; if typecheck says it does not exist at the pinned version, expose the view for tests through `(parent as HTMLElement & { cmView?: EditorView }).cmView = view` on the host element instead and read that in the test.

- [ ] **Step 9: Run the smoke test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/CodeMirrorField.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 10: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts src/renderer/lib src/renderer/components/tickets`
Expected: clean.

```bash
git add frontend/package.json frontend/package-lock.json frontend/src/renderer/components/tickets/CodeMirrorField.tsx frontend/src/renderer/components/tickets/CodeMirrorField.test.tsx frontend/src/renderer/lib/markdown-scroll-sync.ts frontend/src/renderer/lib/markdown-scroll-sync.test.ts
git commit -m "feat(tickets): CodeMirror markdown field with skin theme, Mod-s and heading follow helper" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: `TicketEditor` — toolbar, Edit / Preview / Split, save, stale bar, SSE rule

**Files:**
- Create: `frontend/src/renderer/components/tickets/TicketEditor.tsx`
- Test: `frontend/src/renderer/components/tickets/TicketEditor.test.tsx`

**Interfaces:**
- Consumes: `CodeMirrorField` (Task 8), `headingIndexBeforeLine` (Task 8), `useTicketMutations().saveTicketFile`, `staleModifiedAt`, `ticketErrorMessage` (Task 3), `TicketFile` (`useTicketsQuery.ts:8`), `splitFrontmatter` (`ticket-presentation.ts:138`), `MarkdownBody` (`MarkdownBody.tsx:5`), `formatTimeCompact` (`lib/format-time`), `TopbarButton`, `RadioGroup` from `radix-ui` with the `settings-segment` classes (`ReviewPlanSheet.tsx:102-113`).
- Produces:
  - `type EditorMode = "edit" | "preview" | "split"`
  - `TicketEditor({ projectId, slug, path, file, isError, error, warning, leading, reload, onDirtyChange })` where `file: TicketFile | undefined`, `reload: () => Promise<unknown>`, `leading?: ReactNode` (Task 10 passes the back crumb), `onDirtyChange?: (dirty: boolean) => void`.
  - DOM contract: toolbar `data-testid="ticket-editor-toolbar"`; dirty dot `role="status"` with `aria-label` `Unsaved changes`; stale bar `role="alert"` `data-testid="ticket-file-stale"` with buttons `Reload` and `Keep mine`; preview root `data-testid="ticket-file-preview"` (keeps plan 2's test id); the `View` segmented control is a `radiogroup` labelled `View` with radios `Edit`, `Preview`, `Split`.

Behaviour (spec §3.3 editing half; daemon truth for the 409):
- Mode defaults to `preview`. The mode is local state; switching files remounts the editor (Task 10 keys it by path), so each file opens in preview.
- `draft` is `null` while clean; `dirty = draft !== null && draft !== file.content`.
- Save (toolbar button, `Cmd/Ctrl+S` from CodeMirror's `Mod-s` or from the wrapper `onKeyDown` in preview mode, skipped when `defaultPrevented`): `PUT` with `ifUnmodifiedSince = loadedAt` (the `modifiedAt` of the version the draft started from). Success → clean, `loadedAt = saved.modifiedAt`, `Saved` flashes for 1.8 s. `409 TICKET_FILE_STALE` → stale bar with the daemon's `details.modifiedAt`. Other errors → inline `role="alert"` message.
- File changes from the query (SSE invalidation refetch, or another client's save): clean → adopt silently; dirty → stale bar, draft kept. A `savingRef` guards the window where the mutation's `onSuccess` has already written the new file into the cache but the component has not yet updated `loadedAt`.
- Stale bar: `Reload` → drop the draft, adopt the file, call `reload()`. `Keep mine` → save again without `ifUnmodifiedSince`.
- Split: editor left, preview right; on the editor's top-line change, `headingIndexBeforeLine(content, line)` picks the heading and the preview's `n`-th `h1..h6` is `scrollIntoView({ block: "start" })` inside a `requestAnimationFrame`; `-1` scrolls the preview to the top. This is the deterministic "nearest heading" mechanism the prompt allowed; exact line-to-pixel sync is out of scope.

- [ ] **Step 1: Write the failing tests**

`frontend/src/renderer/components/tickets/TicketEditor.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ComponentProps } from "react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { TicketFile } from "../../hooks/useTicketsQuery";

const { saveMock } = vi.hoisted(() => ({ saveMock: vi.fn() }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return { ...actual, useTicketMutations: () => ({ saveTicketFile: { mutateAsync: saveMock, isPending: false } }) };
});

vi.mock("./CodeMirrorField", () => ({
	CodeMirrorField: ({
		value,
		onChange,
		onSave,
		onTopLineChange,
		ariaLabel,
	}: {
		value: string;
		onChange: (next: string) => void;
		onSave: () => void;
		onTopLineChange?: (line: number) => void;
		ariaLabel: string;
	}) => (
		<div>
			<textarea
				aria-label={ariaLabel}
				value={value}
				onChange={(event) => onChange(event.target.value)}
				onKeyDown={(event) => {
					if (event.key === "s" && (event.metaKey || event.ctrlKey)) {
						event.preventDefault();
						onSave();
					}
				}}
			/>
			<button type="button" onClick={() => onTopLineChange?.(9)}>
				scroll to line 9
			</button>
		</div>
	),
}));

import { TicketEditor } from "./TicketEditor";

const body = ["# Spec", "", "Intro.", "", "## Goals", "", "Goal text.", "", "### Details", "more"].join("\n");
const file: TicketFile = { path: "spec.md", content: body, modifiedAt: "2026-09-18T10:00:00Z" };

function renderEditor(current: TicketFile | undefined = file, props: Partial<ComponentProps<typeof TicketEditor>> = {}) {
	const reload = vi.fn().mockResolvedValue(undefined);
	const onDirtyChange = vi.fn();
	const view = render(
		<QueryClientProvider client={new QueryClient()}>
			<TicketEditor projectId="p1" slug="search-page" path="spec.md" file={current} isError={false} reload={reload} onDirtyChange={onDirtyChange} {...props} />
		</QueryClientProvider>,
	);
	const rerenderWith = (next: TicketFile) =>
		view.rerender(
			<QueryClientProvider client={new QueryClient()}>
				<TicketEditor projectId="p1" slug="search-page" path="spec.md" file={next} isError={false} reload={reload} onDirtyChange={onDirtyChange} {...props} />
			</QueryClientProvider>,
		);
	return { reload, onDirtyChange, rerenderWith };
}

async function switchTo(mode: "Edit" | "Preview" | "Split") {
	await userEvent.click(within(screen.getByRole("radiogroup", { name: "View" })).getByRole("radio", { name: mode }));
}

beforeAll(() => {
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

beforeEach(() => {
	saveMock.mockReset();
});

describe("TicketEditor", () => {
	it("previews by default and tracks dirty state in edit mode", async () => {
		const { onDirtyChange } = renderEditor();
		expect(screen.getByTestId("ticket-file-preview")).toHaveTextContent("Intro.");
		expect(screen.queryByRole("status", { name: "Unsaved changes" })).not.toBeInTheDocument();

		await switchTo("Edit");
		const editor = screen.getByLabelText("Edit spec.md");
		expect(editor).toHaveValue(body);
		await userEvent.type(editor, "!");

		expect(screen.getByRole("status", { name: "Unsaved changes" })).toBeInTheDocument();
		expect(onDirtyChange).toHaveBeenLastCalledWith(true);
	});

	it("saves with ifUnmodifiedSince on Cmd+S and clears the dirty state", async () => {
		saveMock.mockResolvedValue({ ...file, content: `${body}!`, modifiedAt: "2026-09-18T10:05:00Z" });
		const { onDirtyChange } = renderEditor();
		await switchTo("Edit");
		const editor = screen.getByLabelText("Edit spec.md");
		await userEvent.type(editor, "!");
		await userEvent.keyboard("{Meta>}s{/Meta}");

		await waitFor(() =>
			expect(saveMock).toHaveBeenCalledWith({
				projectId: "p1",
				slug: "search-page",
				path: "spec.md",
				content: `${body}!`,
				ifUnmodifiedSince: "2026-09-18T10:00:00Z",
			}),
		);
		expect(await screen.findByText("Saved")).toBeInTheDocument();
		expect(screen.queryByRole("status", { name: "Unsaved changes" })).not.toBeInTheDocument();
		expect(onDirtyChange).toHaveBeenLastCalledWith(false);
	});

	it("shows the stale bar on 409 and Keep mine saves without ifUnmodifiedSince", async () => {
		saveMock
			.mockRejectedValueOnce({ error: "conflict", code: "TICKET_FILE_STALE", message: "stale", details: { modifiedAt: "2026-09-18T10:03:00Z" } })
			.mockResolvedValueOnce({ ...file, content: `${body}!`, modifiedAt: "2026-09-18T10:06:00Z" });
		renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		await userEvent.click(screen.getByRole("button", { name: "Save" }));

		const bar = await screen.findByTestId("ticket-file-stale");
		expect(bar).toHaveTextContent("This file changed on disk");
		await userEvent.click(within(bar).getByRole("button", { name: "Keep mine" }));

		await waitFor(() => expect(saveMock).toHaveBeenCalledTimes(2));
		expect(saveMock.mock.calls[1][0]).toMatchObject({ content: `${body}!`, ifUnmodifiedSince: undefined });
		await waitFor(() => expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument());
	});

	it("Reload drops the draft and refetches", async () => {
		saveMock.mockRejectedValue({ error: "conflict", code: "TICKET_FILE_STALE", message: "stale", details: { modifiedAt: "2026-09-18T10:03:00Z" } });
		const { reload } = renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		await userEvent.click(screen.getByRole("button", { name: "Save" }));
		const bar = await screen.findByTestId("ticket-file-stale");

		await userEvent.click(within(bar).getByRole("button", { name: "Reload" }));

		expect(reload).toHaveBeenCalled();
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(body);
		expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument();
	});

	it("adopts a changed file silently when clean and shows the bar when dirty", async () => {
		const { rerenderWith } = renderEditor();
		await switchTo("Edit");
		rerenderWith({ ...file, content: `${body}\n\nFrom disk.`, modifiedAt: "2026-09-18T10:01:00Z" });
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(`${body}\n\nFrom disk.`);
		expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument();

		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		rerenderWith({ ...file, content: `${body}\n\nSecond write.`, modifiedAt: "2026-09-18T10:02:00Z" });

		expect(await screen.findByTestId("ticket-file-stale")).toBeInTheDocument();
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(`${body}\n\nFrom disk.!`);
	});

	it("scrolls the split preview to the heading nearest the editor's top line", async () => {
		renderEditor();
		await switchTo("Split");
		const preview = screen.getByTestId("ticket-file-preview");
		const details = within(preview).getByRole("heading", { name: "Details" });
		const spy = vi.spyOn(details, "scrollIntoView");

		await userEvent.click(screen.getByRole("button", { name: "scroll to line 9" }));
		await act(async () => {
			await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
		});

		expect(spy).toHaveBeenCalledWith({ block: "start" });
	});
});
```

Line 9 of `body` is `### Details`, so `headingIndexBeforeLine(body, 9)` is 2 and the third heading is the one scrolled into view.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketEditor.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

`frontend/src/renderer/components/tickets/TicketEditor.tsx`:

```tsx
import { AlertTriangle } from "lucide-react";
import { RadioGroup } from "radix-ui";
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { staleModifiedAt, ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketFile } from "../../hooks/useTicketsQuery";
import { formatTimeCompact } from "../../lib/format-time";
import { headingIndexBeforeLine } from "../../lib/markdown-scroll-sync";
import { splitFrontmatter } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import { MarkdownBody } from "../MarkdownBody";
import { TopbarButton } from "../TopbarButton";
import { CodeMirrorField } from "./CodeMirrorField";

export type EditorMode = "edit" | "preview" | "split";

const SAVED_FLASH_MS = 1800;

export function TicketEditor({
	projectId,
	slug,
	path,
	file,
	isError,
	error,
	warning,
	leading,
	reload,
	onDirtyChange,
}: {
	projectId: string;
	slug: string;
	path: string;
	file: TicketFile | undefined;
	isError: boolean;
	error?: unknown;
	warning?: string;
	leading?: ReactNode;
	reload: () => Promise<unknown>;
	onDirtyChange?: (dirty: boolean) => void;
}) {
	const { t } = useTranslation();
	const { saveTicketFile } = useTicketMutations();
	const [mode, setMode] = useState<EditorMode>("preview");
	const [draft, setDraft] = useState<string | null>(null);
	const [loadedAt, setLoadedAt] = useState<string | undefined>(file?.modifiedAt);
	const [stale, setStale] = useState<string | null>(null);
	const [saveError, setSaveError] = useState<string | null>(null);
	const [savedAt, setSavedAt] = useState<number | null>(null);
	const [busy, setBusy] = useState(false);
	const savingRef = useRef(false);
	const previewRef = useRef<HTMLDivElement>(null);
	const followFrame = useRef<number | null>(null);
	const content = draft ?? file?.content ?? "";
	const dirty = draft !== null && draft !== (file?.content ?? "");

	useEffect(() => {
		onDirtyChange?.(dirty);
	}, [dirty, onDirtyChange]);

	useEffect(() => {
		if (!file || savingRef.current) return;
		if (loadedAt === undefined) {
			setLoadedAt(file.modifiedAt);
			return;
		}
		if (file.modifiedAt === loadedAt) return;
		if (dirty) {
			setStale(file.modifiedAt);
			return;
		}
		setLoadedAt(file.modifiedAt);
		setDraft(null);
		setStale(null);
	}, [dirty, file, loadedAt]);

	useEffect(() => {
		if (savedAt === null) return;
		const timeout = window.setTimeout(() => setSavedAt(null), SAVED_FLASH_MS);
		return () => window.clearTimeout(timeout);
	}, [savedAt]);

	const save = async (keepMine = false) => {
		if (!file || busy) return;
		savingRef.current = true;
		setBusy(true);
		setSaveError(null);
		try {
			const saved = await saveTicketFile.mutateAsync({
				projectId,
				slug,
				path,
				content,
				ifUnmodifiedSince: keepMine ? undefined : loadedAt,
			});
			setDraft(null);
			setLoadedAt(saved.modifiedAt);
			setStale(null);
			setSavedAt(Date.now());
		} catch (err) {
			const modifiedAt = staleModifiedAt(err);
			if (modifiedAt) setStale(modifiedAt);
			else setSaveError(ticketErrorMessage(err, t, "tickets.editor.saveFailed"));
		} finally {
			savingRef.current = false;
			setBusy(false);
		}
	};

	const reloadFromDisk = () => {
		setDraft(null);
		setStale(null);
		setSaveError(null);
		if (file) setLoadedAt(file.modifiedAt);
		void reload();
	};

	const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (event.defaultPrevented) return;
		if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
			event.preventDefault();
			void save();
		}
	};

	const followTopLine = (line: number) => {
		if (followFrame.current !== null) cancelAnimationFrame(followFrame.current);
		followFrame.current = requestAnimationFrame(() => {
			followFrame.current = null;
			const root = previewRef.current;
			if (!root) return;
			const index = headingIndexBeforeLine(content, line);
			if (index < 0) {
				root.scrollTop = 0;
				return;
			}
			root.querySelectorAll("h1, h2, h3, h4, h5, h6")[index]?.scrollIntoView({ block: "start" });
		});
	};

	useEffect(
		() => () => {
			if (followFrame.current !== null) cancelAnimationFrame(followFrame.current);
		},
		[],
	);

	const parsed = splitFrontmatter(content);
	const modes: Array<{ value: EditorMode; label: string }> = [
		{ value: "edit", label: t("tickets.editor.edit") },
		{ value: "preview", label: t("tickets.editor.preview") },
		{ value: "split", label: t("tickets.editor.split") },
	];
	const showEditor = mode !== "preview";
	const showPreview = mode !== "edit";

	const preview = (
		<div ref={previewRef} className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-6 py-5" data-testid="ticket-file-preview">
			{warning ? (
				<p className="mb-4 flex items-start gap-1.5 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-2xs text-warning" role="status">
					<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
					<span>{warning}</span>
				</p>
			) : null}
			{isError ? (
				<p className="text-2xs text-error" role="alert">
					{ticketErrorMessage(error, t, "tickets.fileLoadFailed")}
				</p>
			) : null}
			{parsed.fields.length > 0 ? (
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
			{file ? <MarkdownBody body={parsed.body} className="max-w-3xl text-sm text-foreground" /> : null}
		</div>
	);

	return (
		<section className="flex min-w-0 flex-1 flex-col" onKeyDown={onKeyDown}>
			<div className="flex h-toolbar shrink-0 items-center gap-2 border-b border-border-strong px-4" data-testid="ticket-editor-toolbar">
				{leading}
				<span className="min-w-0 truncate font-mono text-2xs text-foreground">{path}</span>
				{dirty ? (
					<span aria-label={t("tickets.editor.unsaved")} className="size-dot-sm shrink-0 rounded-full bg-status-working" role="status" />
				) : null}
				<span className="min-w-0 flex-1" />
				<RadioGroup.Root
					aria-label={t("tickets.editor.mode")}
					className="settings-segment"
					value={mode}
					onValueChange={(next) => setMode(next as EditorMode)}
				>
					{modes.map((option) => (
						<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
							{option.label}
						</RadioGroup.Item>
					))}
				</RadioGroup.Root>
				<span className="font-mono text-micro text-passive">
					{savedAt !== null
						? t("tickets.editor.saved")
						: file
							? t("tickets.fileModified", { time: formatTimeCompact(file.modifiedAt) })
							: ""}
				</span>
				<TopbarButton variant="primary" disabled={!file || busy || !dirty} onClick={() => void save()}>
					{busy ? t("tickets.editor.saving") : t("tickets.editor.save")}
				</TopbarButton>
			</div>
			{stale ? (
				<div
					className="flex flex-wrap items-center gap-2 border-b border-warning/40 bg-warning/10 px-4 py-2 text-2xs text-warning"
					data-testid="ticket-file-stale"
					role="alert"
				>
					<AlertTriangle aria-hidden="true" className="size-icon-2xs shrink-0" />
					<span className="font-medium">{t("tickets.editor.staleTitle")}</span>
					<span className="text-warning/80">{t("tickets.editor.staleBody")}</span>
					<span className="flex-1" />
					<TopbarButton onClick={reloadFromDisk}>{t("tickets.editor.reload")}</TopbarButton>
					<TopbarButton variant="primary" disabled={busy} onClick={() => void save(true)}>
						{t("tickets.editor.keepMine")}
					</TopbarButton>
				</div>
			) : null}
			{saveError ? (
				<p className="border-b border-border-strong px-4 py-1.5 text-2xs text-error" role="alert">
					{saveError}
				</p>
			) : null}
			<div className={cn("flex min-h-0 flex-1", mode === "split" && "divide-x divide-border-strong")}>
				{showEditor && file ? (
					<div className={cn("flex min-h-0 min-w-0 flex-col", mode === "split" ? "flex-1 basis-1/2" : "flex-1")}>
						<CodeMirrorField
							value={content}
							onChange={setDraft}
							onSave={() => void save()}
							onTopLineChange={mode === "split" ? followTopLine : undefined}
							ariaLabel={t("tickets.editor.aria", { file: path })}
							autoFocus={mode === "edit"}
						/>
					</div>
				) : null}
				{showPreview ? (
					<div className={cn("flex min-h-0 min-w-0 flex-col", mode === "split" ? "flex-1 basis-1/2" : "flex-1")}>{preview}</div>
				) : null}
			</div>
		</section>
	);
}
```

The `Save` button is disabled while clean; the tests click it only after typing. If `TopbarButton`'s `variant` union has no `"primary"`, use the variant `TicketPage.tsx:189` already passes (it is `variant="primary"` there, so this is consistent).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketEditor.test.tsx`
Expected: PASS (6 tests). If the `Meta+s` keyboard shortcut does not reach the mocked textarea in the second test, click into the textarea first (`userEvent.type` already focuses it) or fall back to `{Control>}s{/Control}`; both paths call `onSave` in the mock.

- [ ] **Step 5: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts src/renderer/i18n src/renderer/components/tickets`
Expected: clean.

```bash
git add frontend/src/renderer/components/tickets/TicketEditor.tsx frontend/src/renderer/components/tickets/TicketEditor.test.tsx
git commit -m "feat(tickets): ticket file editor with edit, preview, split, save and stale-file bar" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Ticket page — editor pane, back crumb, dirty-navigation guard

**Files:**
- Modify: `frontend/src/renderer/components/tickets/TicketPage.tsx` (imports 1-26; hooks 35-52; right pane `<section>` at 217-254)
- Test: `frontend/src/renderer/components/tickets/TicketPage.test.tsx` (router mock at line 15; `ticketFileQueryMock` return in `beforeEach`)

**Interfaces:**
- Consumes: `TicketEditor` (Task 9); `useBlocker` from `@tanstack/react-router` 1.170.15 (`node_modules/@tanstack/react-router/dist/esm/useBlocker.d.ts`: `useBlocker({ shouldBlockFn, withResolver: true, disabled?, enableBeforeUnload? })` returns `{ status: "blocked", proceed, reset } | { status: "idle" }`); `ConfirmDialog` (`ConfirmDialog.tsx:17-43`: `open, title, description, confirmLabel, destructive?, onConfirm, onOpenChange`); `ChevronLeft` from `lucide-react`; the ticket route keeps `?file=` (`routes/_shell.projects.$projectId_.tickets.$slug.tsx:6-17`, unchanged).
- Produces: the page's right pane is `<TicketEditor key={selectedFile} …/>`; a crumb button labelled `Back to {{name}}` navigates to `/projects/$projectId`; a `ConfirmDialog` titled `Discard unsaved changes?` appears when the router blocks a navigation while the editor is dirty.

Both in-page file switches (`navigate({ …, replace: true })`) and leaving the route go through TanStack's history, so one `useBlocker` covers both; Task 12 confirms the in-page case in the real renderer.

- [ ] **Step 1: Update the router mock and add failing tests**

In `TicketPage.test.tsx`, add `blockerMock: vi.fn()` to the hoisted block and change the router mock to:

```tsx
vi.mock("@tanstack/react-router", () => ({
	useNavigate: () => navigateMock,
	useBlocker: (options: unknown) => blockerMock(options),
}));
```

Reset in `beforeEach`: `blockerMock.mockReset().mockReturnValue({ status: "idle" });`. Add tests:

```tsx
	it("renders a back crumb to the project board", async () => {
		renderPage("spec.md");
		await userEvent.click(screen.getByRole("button", { name: "Back to app" }));
		expect(navigateMock).toHaveBeenCalledWith({ to: "/projects/$projectId", params: { projectId: "p1" } });
	});

	it("asks before leaving with unsaved edits and proceeds on Discard", async () => {
		const proceed = vi.fn();
		const reset = vi.fn();
		blockerMock.mockReturnValue({ status: "blocked", proceed, reset });
		renderPage("spec.md");

		expect(screen.getByRole("dialog")).toHaveTextContent("Discard unsaved changes?");
		expect(screen.getByRole("dialog")).toHaveTextContent("spec.md has edits that were not saved.");
		await userEvent.click(screen.getByRole("button", { name: "Discard" }));
		expect(proceed).toHaveBeenCalled();
	});

	it("registers the blocker disabled while the editor is clean", () => {
		renderPage("spec.md");
		expect(blockerMock).toHaveBeenCalledWith(expect.objectContaining({ withResolver: true, disabled: true }));
	});
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketPage.test.tsx`
Expected: the three new tests FAIL; the existing preview test still passes (the old inline preview is still there).

- [ ] **Step 3: Rewrite the page's right pane**

In `TicketPage.tsx`:

Imports: change line 1 to `import { useBlocker, useNavigate } from "@tanstack/react-router";`, line 2 to `import { AlertTriangle, Archive, ArchiveRestore, ChevronLeft, FileText } from "lucide-react";`, line 3 to `import { useRef, useState } from "react";`. Remove `formatTimeCompact` (line 8), `splitFrontmatter` from the presentation import (line 13), and `MarkdownBody` (line 20). Add:

```tsx
import { ConfirmDialog } from "../ConfirmDialog";
import { TicketEditor } from "./TicketEditor";
```

Hooks (after `const [actionError, setActionError] = useState<string | null>(null);` at line 52):

```tsx
	const [dirty, setDirty] = useState(false);
	const dirtyRef = useRef(false);
	dirtyRef.current = dirty;
	const blocker = useBlocker({
		shouldBlockFn: () => dirtyRef.current,
		withResolver: true,
		disabled: !dirty,
		enableBeforeUnload: false,
	});
	const openBoard = () => void navigate({ to: "/projects/$projectId", params: { projectId } });
```

Delete the now-unused `fileContent`, `parsed`, `selectedPlan` and `fileWarning` lines (95-98) except keep:

```tsx
	const selectedPlan = ticket.plans.find((plan) => plan.file === selectedFile);
	const fileWarning = selectedFile === "ticket.md" ? ticket.warning : selectedPlan?.warning;
```

Replace the whole `<section className="flex min-w-0 flex-1 flex-col">…</section>` (lines 217-254) with:

```tsx
				{selectedFile ? (
					<TicketEditor
						key={selectedFile}
						projectId={projectId}
						slug={slug}
						path={selectedFile}
						file={fileQuery.data}
						isError={fileQuery.isError}
						error={fileQuery.error}
						warning={fileWarning}
						reload={() => fileQuery.refetch()}
						onDirtyChange={setDirty}
						leading={
							<button
								type="button"
								aria-label={t("tickets.backToBoard", { name: projectName || t("shell.board") })}
								className="inline-flex h-control-md shrink-0 items-center gap-1 rounded-sm pr-2 pl-1 text-2xs text-muted-foreground transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
								onClick={openBoard}
							>
								<ChevronLeft aria-hidden="true" className="size-icon-sm" />
								<span className="max-w-40 truncate">{projectName || t("shell.board")}</span>
							</button>
						}
					/>
				) : (
					<section className="flex min-w-0 flex-1 flex-col" />
				)}
```

and add, next to the other dialogs at the bottom (after `MergeConfirmDialog`):

```tsx
			<ConfirmDialog
				open={blocker.status === "blocked"}
				title={t("tickets.editor.discardTitle")}
				description={t("tickets.editor.discardBody", { file: selectedFile ?? "" })}
				confirmLabel={t("tickets.editor.discard")}
				destructive
				onConfirm={() => blocker.proceed?.()}
				onOpenChange={(open) => {
					if (!open) blocker.reset?.();
				}}
			/>
```

`projectName` is the value Task 6 introduced from the workspace query. `useBlocker` is called before the early returns because it is a hook; the `TicketEditor` and `ConfirmDialog` render after them.

- [ ] **Step 4: Run the page tests**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/tickets/TicketPage.test.tsx`
Expected: PASS, including `previews the selected file with its frontmatter above the body` (now rendered by `TicketEditor` in preview mode) and `shows a warning banner above an unreadable ticket`. If the warning test looked for the banner outside the preview root, it still finds it: the banner is inside `ticket-file-preview`.

- [ ] **Step 5: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: clean; lint 0 errors (an unused-import error here means a leftover from step 3).

```bash
git add frontend/src/renderer/components/tickets/TicketPage.tsx frontend/src/renderer/components/tickets/TicketPage.test.tsx
git commit -m "feat(tickets): editable ticket page with back crumb and unsaved-changes guard" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Project settings — "Tickets" section for `ProjectConfig.tickets`

**Files:**
- Create: `frontend/src/renderer/components/settings/AgentModelField.tsx` (moved out of `ProjectSettingsForm.tsx:489-668`, gains `label` and `fieldId` props)
- Create: `frontend/src/renderer/components/settings/TicketDefaultsSection.tsx`
- Test: `frontend/src/renderer/components/settings/TicketDefaultsSection.test.tsx`
- Modify: `frontend/src/renderer/components/ProjectSettingsForm.tsx` (`ProjectSettingsSection` at line 38; form state 112-127; `mutation` body 166-214; sections 298-486)
- Modify: `frontend/src/renderer/components/SettingsDialog.tsx` (icons import line 1; `projectSections` at 59-64)
- Test: `frontend/src/renderer/components/ProjectSettingsForm.test.tsx` (helpers `mockProject` 146-173, `renderSettings`, `chooseOption`, `submitSettings`)

**Interfaces:**
- Consumes: `ProjectConfig.tickets?: TicketDefaults` (`schema.ts:2548`, `3054-3060`, `3071-3075`: `{ planner?, implementer?, reviewer?: { agent?, model?, claudeAccountId? }, reviewerMode?: "planner" | "new", disableAutoReview?: boolean }`), saved through the existing `apiClient.PUT("/api/v1/projects/{id}", { body: { displayName, config } })` at `ProjectSettingsForm.tsx:215-218`; `SettingsSection`, `SettingsRow` (`settings/SettingsRow.tsx:16-33`), `SettingsOptionMenu` (`settings/SettingsOptionMenu.tsx:15-45`, the menu the form already uses for permission mode at `ProjectSettingsForm.tsx:698-724`), `Switch` (`ui/switch`, used at `IntakeFields.tsx:109-113`), `RadioGroup` `settings-segment` (`ReviewPlanSheet.tsx:102-113`), `useClaudeAccounts`/`ClaudeAccount` (`hooks/useClaudeAccounts.ts:10,79`), `AgentInfo` (`schema.ts`).
- Why not `RequiredAgentField`/`ClaudeAccountSelect` for these rows: neither offers a blank "inherit" option (`RequiredAgentField` is required by design, `ClaudeAccountSelect` lists only accounts), and empty must mean "use the project's worker defaults" (`service.go:428-439`). `SettingsOptionMenu` with a leading `Project default` option gives that in the form's own idiom.
- Produces:
  - `AgentModelField` exported from `components/settings/AgentModelField.tsx` with the same props plus `label?: string` (overrides the `settings.models.<role>Model` copy) and `fieldId?: string` (overrides the `<role>-model-options` input id); `ProjectSettingsForm.tsx` imports it.
  - `cleanTicketDefaults(value: TicketDefaults): TicketDefaults | undefined` — strips empty strings and empty role objects; `undefined` when nothing is set.
  - `TicketDefaultsSection({ value, onChange, projectId, fallbackAgent, agents })`.
  - `ProjectSettingsSection` gains `"tickets"`; the dialog lists it after Intake.

- [ ] **Step 1: Move `AgentModelField` and `ModelRefreshButton` into `components/settings/AgentModelField.tsx`**

Create the file with the two functions copied verbatim from `ProjectSettingsForm.tsx:489-668`, exporting `AgentModelField`, with these edits:

```tsx
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { RefreshCw } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	agentModelsQueryKey,
	agentModelsQueryOptions,
	refreshAgentModels,
	revalidateAgentModels,
	type AgentModelCatalog,
} from "../../hooks/useAgentModelsQuery";
import { cn } from "../../lib/utils";
import { Input } from "../ui/input";
import { AgentModelCombobox } from "./AgentModelCombobox";
import { SettingsOptionMenu } from "./SettingsOptionMenu";
import { SettingsRow } from "./SettingsRow";

export function AgentModelField({
	role,
	agentId,
	projectId,
	model,
	mode,
	onModelChange,
	onModeChange,
	label: labelOverride,
	fieldId,
}: {
	role: "worker" | "orchestrator";
	agentId: string;
	projectId: string;
	model: string;
	mode: string;
	onModelChange: (value: string) => void;
	onModeChange: (value: string) => void;
	label?: string;
	fieldId?: string;
}) {
```

and inside: `const label = labelOverride ?? t(`settings.models.${role}${isMode ? "Mode" : "Model"}`);` and `const datalistID = fieldId ?? `${role}-model-options`;`. Delete the two functions from `ProjectSettingsForm.tsx`, add `import { AgentModelField } from "./settings/AgentModelField";`, and remove the imports that become unused there (`RefreshCw` stays: the refresh-agents button at line 405 uses it; `AgentModelCombobox`, `revalidateAgentModels`, `refreshAgentModels`, `agentModelsQueryKey`, `agentModelsQueryOptions`, `AgentModelCatalog`, `Input` may become unused — let lint tell you).

Run: `cd frontend && npm run typecheck && npx vitest run --config vite.renderer.config.ts src/renderer/components/ProjectSettingsForm.test.tsx`
Expected: clean and all existing settings tests pass (pure move).

- [ ] **Step 2: Write the failing section tests**

`frontend/src/renderer/components/settings/TicketDefaultsSection.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { accountsMock } = vi.hoisted(() => ({ accountsMock: vi.fn() }));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => accountsMock() };
});

vi.mock("./AgentModelField", () => ({
	AgentModelField: ({ label, model, onModelChange, fieldId }: { label?: string; model: string; onModelChange: (v: string) => void; fieldId?: string }) => (
		<input id={fieldId} aria-label={label} value={model} onChange={(event) => onModelChange(event.target.value)} />
	),
}));

import { cleanTicketDefaults, TicketDefaultsSection } from "./TicketDefaultsSection";

const agents = [
	{ id: "claude-code", label: "Claude Code" },
	{ id: "codex", label: "Codex" },
];

function renderSection(value: Parameters<typeof TicketDefaultsSection>[0]["value"] = {}) {
	const onChange = vi.fn();
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TicketDefaultsSection value={value} onChange={onChange} projectId="p1" fallbackAgent="claude-code" agents={agents} />
		</QueryClientProvider>,
	);
	return onChange;
}

async function chooseOption(trigger: HTMLElement, name: string) {
	await userEvent.click(trigger);
	await userEvent.click(await screen.findByRole("menuitem", { name }));
}

beforeEach(() => {
	accountsMock.mockReset().mockReturnValue({ data: [], isError: false, isLoading: false });
});

describe("TicketDefaultsSection", () => {
	it("renders a row set per role with Project default selected when empty", () => {
		renderSection();
		expect(screen.getByRole("button", { name: "Planner agent" })).toHaveTextContent("Project default");
		expect(screen.getByRole("button", { name: "Implementer agent" })).toHaveTextContent("Project default");
		expect(screen.getByRole("button", { name: "Reviewer agent" })).toHaveTextContent("Project default");
		expect(screen.getByLabelText("Planner model")).toHaveValue("");
		expect(screen.getByRole("radio", { name: "Planning session" })).toHaveAttribute("aria-checked", "true");
		expect(screen.getByRole("switch", { name: "Skip automatic review" })).toHaveAttribute("aria-checked", "false");
	});

	it("emits the changed role, reviewer mode and auto-review switch", async () => {
		const onChange = renderSection({ planner: { agent: "claude-code", model: "claude-opus-5" } });
		expect(screen.getByLabelText("Planner model")).toHaveValue("claude-opus-5");

		await chooseOption(screen.getByRole("button", { name: "Implementer agent" }), "Codex");
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ implementer: { agent: "codex", model: "", claudeAccountId: "" } }));

		await userEvent.click(screen.getByRole("radio", { name: "New session" }));
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ reviewerMode: "new" }));

		await userEvent.click(screen.getByRole("switch", { name: "Skip automatic review" }));
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ disableAutoReview: true }));
	});

	it("shows the account row only for Claude Code with more than one account", () => {
		accountsMock.mockReturnValue({
			data: [
				{ id: "default", label: "Default", isPreferred: true },
				{ id: "personal", label: "Personal" },
			],
			isError: false,
			isLoading: false,
		});
		renderSection({ implementer: { agent: "codex" } });
		expect(screen.getByRole("button", { name: "Planner Claude account" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Implementer Claude account" })).not.toBeInTheDocument();
	});
});

describe("cleanTicketDefaults", () => {
	it("drops empty strings, empty roles and returns undefined when nothing is set", () => {
		expect(cleanTicketDefaults({})).toBeUndefined();
		expect(cleanTicketDefaults({ planner: { agent: "", model: "", claudeAccountId: "" }, reviewerMode: undefined })).toBeUndefined();
		expect(
			cleanTicketDefaults({
				planner: { agent: "claude-code", model: " claude-opus-5 ", claudeAccountId: "" },
				implementer: { agent: "", model: "", claudeAccountId: "" },
				reviewerMode: "new",
				disableAutoReview: false,
			}),
		).toEqual({ planner: { agent: "claude-code", model: "claude-opus-5" }, reviewerMode: "new" });
	});
});
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/settings/TicketDefaultsSection.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 4: Write the section**

`frontend/src/renderer/components/settings/TicketDefaultsSection.tsx`:

```tsx
import { RadioGroup } from "radix-ui";
import { useTranslation } from "react-i18next";
import type { components } from "../../../api/schema";
import { useClaudeAccounts } from "../../hooks/useClaudeAccounts";
import { Switch } from "../ui/switch";
import { AgentModelField } from "./AgentModelField";
import { SettingsOptionMenu } from "./SettingsOptionMenu";
import { SettingsRow } from "./SettingsRow";

type TicketDefaults = components["schemas"]["TicketDefaults"];
type TicketRoleDefaults = components["schemas"]["TicketRoleDefaults"];
type AgentInfo = components["schemas"]["AgentInfo"];
type Role = "planner" | "implementer" | "reviewer";
type ReviewerMode = NonNullable<TicketDefaults["reviewerMode"]>;

const roles: readonly Role[] = ["planner", "implementer", "reviewer"];
const INHERIT = "";

function cleanRole(role: TicketRoleDefaults | undefined): TicketRoleDefaults | undefined {
	const agent = role?.agent || undefined;
	const model = role?.model?.trim() || undefined;
	const claudeAccountId = role?.claudeAccountId || undefined;
	if (!agent && !model && !claudeAccountId) return undefined;
	return {
		...(agent ? { agent } : {}),
		...(model ? { model } : {}),
		...(claudeAccountId ? { claudeAccountId } : {}),
	};
}

export function cleanTicketDefaults(value: TicketDefaults): TicketDefaults | undefined {
	const next: TicketDefaults = {};
	for (const role of roles) {
		const cleaned = cleanRole(value[role]);
		if (cleaned) next[role] = cleaned;
	}
	if (value.reviewerMode) next.reviewerMode = value.reviewerMode;
	if (value.disableAutoReview) next.disableAutoReview = true;
	return Object.keys(next).length > 0 ? next : undefined;
}

export function TicketDefaultsSection({
	value,
	onChange,
	projectId,
	fallbackAgent,
	agents,
}: {
	value: TicketDefaults;
	onChange: (next: TicketDefaults) => void;
	projectId: string;
	fallbackAgent: string;
	agents?: AgentInfo[];
}) {
	const { t } = useTranslation();
	const accounts = useClaudeAccounts().data ?? [];
	const agentOptions = [
		{ value: INHERIT, label: t("settings.project.tickets.inherit") },
		...(agents ?? []).map((agent) => ({ value: agent.id, label: agent.label || agent.id })),
	];
	const accountOptions = [
		{ value: INHERIT, label: t("settings.project.tickets.inherit") },
		...accounts.map((account) => ({ value: account.id, label: account.label })),
	];
	const roleLabels: Record<Role, string> = {
		planner: t("settings.project.tickets.planner"),
		implementer: t("settings.project.tickets.implementer"),
		reviewer: t("settings.project.tickets.reviewer"),
	};
	const setRole = (role: Role, patch: Partial<TicketRoleDefaults>) => {
		const current = value[role] ?? {};
		onChange({
			...value,
			[role]: { agent: current.agent ?? "", model: current.model ?? "", claudeAccountId: current.claudeAccountId ?? "", ...patch },
		});
	};
	const reviewerModes: Array<{ value: ReviewerMode; label: string }> = [
		{ value: "planner", label: t("settings.project.tickets.reviewerMode.planner") },
		{ value: "new", label: t("settings.project.tickets.reviewerMode.new") },
	];

	return (
		<>
			{roles.map((role) => {
				const current = value[role] ?? {};
				const effectiveAgent = current.agent || fallbackAgent;
				const showAccount = effectiveAgent === "claude-code" && accounts.length > 1;
				return (
					<div key={role} className="contents">
						<SettingsRow label={t("settings.project.tickets.agent", { role: roleLabels[role] })}>
							<SettingsOptionMenu
								aria-label={t("settings.project.tickets.agent", { role: roleLabels[role] })}
								value={current.agent ?? INHERIT}
								options={agentOptions}
								onChange={(agent) => setRole(role, { agent, model: "", claudeAccountId: "" })}
							/>
						</SettingsRow>
						<AgentModelField
							role="worker"
							agentId={effectiveAgent}
							projectId={projectId}
							model={current.model ?? ""}
							mode=""
							label={t("settings.project.tickets.model", { role: roleLabels[role] })}
							fieldId={`ticket-${role}-model`}
							onModelChange={(model) => setRole(role, { model })}
							onModeChange={(model) => setRole(role, { model })}
						/>
						{showAccount ? (
							<SettingsRow label={t("settings.project.tickets.account", { role: roleLabels[role] })}>
								<SettingsOptionMenu
									aria-label={t("settings.project.tickets.account", { role: roleLabels[role] })}
									value={current.claudeAccountId ?? INHERIT}
									options={accountOptions}
									onChange={(claudeAccountId) => setRole(role, { claudeAccountId })}
								/>
							</SettingsRow>
						) : null}
					</div>
				);
			})}
			<SettingsRow label={t("settings.project.tickets.reviewerMode")}>
				<RadioGroup.Root
					aria-label={t("settings.project.tickets.reviewerMode")}
					className="settings-segment"
					value={value.reviewerMode ?? "planner"}
					onValueChange={(next) => onChange({ ...value, reviewerMode: next as ReviewerMode })}
				>
					{reviewerModes.map((option) => (
						<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
							{option.label}
						</RadioGroup.Item>
					))}
				</RadioGroup.Root>
			</SettingsRow>
			<SettingsRow label={t("settings.project.tickets.disableAutoReview")}>
				<Switch
					aria-label={t("settings.project.tickets.disableAutoReview")}
					checked={value.disableAutoReview ?? false}
					onCheckedChange={(disableAutoReview) => onChange({ ...value, disableAutoReview })}
				/>
			</SettingsRow>
		</>
	);
}
```

`SettingsOptionMenu<T extends string>` accepts `""` as a value. If its trigger renders the placeholder rather than the option label for an empty-string value, pass `renderTrigger={(selected) => <span>{selected?.label}</span>}` so the trigger reads `Project default`.

- [ ] **Step 5: Run the section tests**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/settings/TicketDefaultsSection.test.tsx`
Expected: PASS (4 tests).

- [ ] **Step 6: Add a failing form test**

In `ProjectSettingsForm.test.tsx`, inside `describe("ProjectSettingsForm", …)`:

```tsx
	it("loads and saves the ticket role defaults without touching other config", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "git@github.com:acme/project-one.git",
			defaultBranch: "main",
			config: {
				defaultBranch: "develop",
				worker: { agent: "claude-code" },
				orchestrator: { agent: "claude-code" },
				tickets: { planner: { agent: "claude-code", model: "claude-opus-5" } },
			},
		});

		renderSettings("proj-1", undefined, "tickets");

		expect(await screen.findByLabelText("Planner model")).toHaveValue("claude-opus-5");
		await chooseOption(screen.getByRole("button", { name: "Implementer agent" }), "Codex");
		await userEvent.type(screen.getByLabelText("Implementer model"), "gpt-5.4");
		await userEvent.click(screen.getByRole("radio", { name: "New session" }));
		await userEvent.click(screen.getByRole("switch", { name: "Skip automatic review" }));

		submitSettings();

		await waitFor(() => expect(putMock).toHaveBeenCalledTimes(1));
		expect(putMock).toHaveBeenCalledWith("/api/v1/projects/{id}", {
			params: { path: { id: "proj-1" } },
			body: {
				displayName: "Project One",
				config: expect.objectContaining({
					defaultBranch: "develop",
					tickets: {
						planner: { agent: "claude-code", model: "claude-opus-5" },
						implementer: { agent: "codex", model: "gpt-5.4" },
						reviewerMode: "new",
						disableAutoReview: true,
					},
				}),
			},
		});
	}, 20_000);

	it("tells scratch projects that tickets are unavailable", async () => {
		mockProject({
			id: "proj-2",
			name: "Scratch",
			kind: "scratch",
			path: "/tmp/scratch",
			config: { worker: { agent: "claude-code" }, orchestrator: { agent: "claude-code" } },
		});
		renderSettings("proj-2", undefined, "tickets");
		expect(await screen.findByText("Tickets are not available for scratch projects.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Planner agent" })).not.toBeInTheDocument();
	});
```

- [ ] **Step 7: Run to verify the form tests fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/ProjectSettingsForm.test.tsx`
Expected: the two new tests FAIL (section unknown, nothing rendered).

- [ ] **Step 8: Wire the form and the dialog**

`ProjectSettingsForm.tsx`:
- Line 38: `export type ProjectSettingsSection = "general" | "agents" | "workflow" | "intake" | "tickets";`
- Add `type TicketDefaults = components["schemas"]["TicketDefaults"];` next to the other schema aliases (line 30-32) and `import { cleanTicketDefaults, TicketDefaultsSection } from "./settings/TicketDefaultsSection";`.
- Form state (inside `useState({ … })`, after `intakeAssignee`): `tickets: (config.tickets ?? {}) as TicketDefaults,`.
- In the non-scratch `next` object (after `trackerIntake: buildIntake(intakeForm),`): `tickets: cleanTicketDefaults(form.tickets),`. The scratch branch keeps `scratchSupportedConfig(config)` unchanged.
- After the Intake block (line 486) add:

```tsx
			{section === "tickets" && (
				<>
					{!isScratchProject ? (
						<SettingsSection title={t("settings.project.tickets")} grouped>
							<p className="px-1 text-xs text-settings-muted">{t("settings.project.tickets.description")}</p>
							<TicketDefaultsSection
								value={form.tickets}
								onChange={(tickets) => setForm((f) => ({ ...f, tickets }))}
								projectId={projectId}
								fallbackAgent={form.workerAgent}
								agents={agentCatalog?.supported}
							/>
						</SettingsSection>
					) : (
						<p className="px-1 text-xs text-settings-muted">{t("settings.project.tickets.scratch")}</p>
					)}
				</>
			)}
```

`SettingsDialog.tsx`: add `ClipboardList` to the `lucide-react` import (line 1) and append `{ id: "tickets", label: t("settings.project.tickets"), icon: ClipboardList },` to `projectSections` (line 64).

- [ ] **Step 9: Run the form tests**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/components/ProjectSettingsForm.test.tsx src/renderer/components/settings`
Expected: PASS. If the `chooseOption` menu item for `Codex` is ambiguous because the agents section is not rendered, it is not: only the tickets section renders for `section="tickets"`.

- [ ] **Step 10: Gates and commit**

Run: `cd frontend && npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: clean; `renderer-coverage.test.ts` passes (the settings copy is all `t()`).

```bash
git add frontend/src/renderer/components/settings/AgentModelField.tsx frontend/src/renderer/components/settings/TicketDefaultsSection.tsx frontend/src/renderer/components/settings/TicketDefaultsSection.test.tsx frontend/src/renderer/components/ProjectSettingsForm.tsx frontend/src/renderer/components/ProjectSettingsForm.test.tsx frontend/src/renderer/components/SettingsDialog.tsx
git commit -m "feat(settings): ticket role defaults section in project settings" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Gates, real-renderer verification against an isolated daemon, report

**Files:**
- Create: `docs/superpowers/plans/2026-09-18-planning-tickets-assign-report.md`
- Temporary, restored afterwards: `.claude/launch.json` (repo root) gains a `tickets-assign-review` entry for the Vite server; remove it before the final commit.

**Interfaces:**
- Consumes: the recipe from `docs/superpowers/plans/2026-09-18-planning-tickets-board-report.md` §"Planner review › Live verification" and the curl shapes from `docs/superpowers/plans/2026-09-18-planning-tickets-daemon-report.md` §"Curl verification against a real daemon" (loopback curl needs no bearer; `POST /api/v1/projects {"path"}` answers `{"project":{"id":"<folder name>",…}}`).
- Never touch the user's daemons on ports 3001 and 3002. Spare port for this run: `39312`.

- [ ] **Step 1: Full gates on the branch**

Run from `frontend/`: `npm run typecheck && npm run frontend:lint && npx vitest run --config vite.renderer.config.ts`
Expected: typecheck clean; lint 0 errors (warnings may remain at the pre-existing 150 or fewer); every test file passes. From the repo root, `git status --porcelain` shows nothing; if `packages/terminal/package-lock.json` is dirty, `git checkout -- packages/terminal/package-lock.json`.

- [ ] **Step 2: Start an isolated daemon and a throwaway repo**

All commands from the worktree root with `CLAUDE*` scrubbed. `S=/tmp/claude-501/plan3-verify`.

```bash
S=/tmp/claude-501/plan3-verify; rm -rf "$S"; mkdir -p "$S/data" "$S/repo"
git -C "$S/repo" init -q -b main && git -C "$S/repo" -c user.email=v@x -c user.name=v commit -q --allow-empty -m init
(cd backend && go build -o "$S/opr" ./cmd/opr)
env -i HOME="$HOME" PATH="$PATH" OPERATOR_DATA_DIR="$S/data" OPERATOR_RUN_FILE="$S/data/run.json" OPERATOR_PORT=39312 "$S/opr" daemon > "$S/daemon.log" 2>&1 &
sleep 2; curl -s localhost:39312/readyz
curl -s -X POST localhost:39312/api/v1/projects -H 'content-type: application/json' -d "{\"path\":\"$S/repo\"}" | jq .project.id
```

Expected: `readyz` answers OK; the project id is `repo`.

- [ ] **Step 3: Seed a ticket with two plans, committed**

```bash
B=localhost:39312/api/v1/projects/repo/tickets
curl -s -X POST $B -H 'content-type: application/json' -d '{"title":"Search page","brief":"Full text search"}' | jq '.ticket.slug, .warnings'
curl -s -X PUT "$B/search-page/file?path=plans/01-index.md" -H 'content-type: application/json' -d '{"content":"# Index\n\n- [ ] build the index\n"}' | jq .modifiedAt
curl -s -X PUT "$B/search-page/file?path=plans/02-ui.md" -H 'content-type: application/json' -d '{"content":"# UI\n\n## Goals\n\ntext\n\n### Details\n\nmore\n"}' | jq .modifiedAt
git -C "$S/repo" add -A && git -C "$S/repo" -c user.email=v@x -c user.name=v commit -qm tickets
curl -s "$B/search-page" | jq '.ticket.status, [.ticket.plans[] | {file, status}]'
curl -s -X POST "$B/search-page/plans/01-index.md/assign?dryRun=1" | jq .warnings
```

Expected: slug `search-page`; status `ready`; both plans `todo`; the dry run answers `[]` (folder committed, on `main`, no planning session).

- [ ] **Step 4: Serve the renderer against that daemon**

Add to `.claude/launch.json` at the repo root (create the file if absent, keep any existing entries):

```json
{
  "name": "tickets-assign-review",
  "runtimeExecutable": "sh",
  "runtimeArgs": ["-c", "cd <absolute worktree path>/frontend && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT OPERATOR_DEV_API_TARGET=http://127.0.0.1:39312 npx vite --config vite.renderer.config.ts --host --port 5180 --strictPort"],
  "port": 5180
}
```

Start it (`preview_start {name: "tickets-assign-review"}` in a Claude Code session, or run the command in a terminal), then open **`http://127.0.0.1:5180/#/projects/repo`** — `127.0.0.1`, not `localhost`, because the daemon's CORS allow-origin is `tauri://localhost` and only the same-origin page proxies through Vite. Terminals render a demo terminal in this mode; everything else is real.

Expected: five columns, PLANNED first with the `Search page` card, rows `01 Index · To do` and `02 UI · To do`, each with a drag handle (`Drag Index to assign it`) and an `Assign` action.

- [ ] **Step 5: Drag-drop assign with `ticket_repo_dirty`, forced**

Make the folder dirty first: `printf '\nlocal edit\n' >> "$S/repo/.operator/tickets/search-page/spec.md"`, then in the browser:

1. Drag the `01 Index` handle onto the IDLE / WORKING column. While dragging: the other four columns dim (`data-dragging="true"` on the grid), the working column shows the dashed outline and `Drop to assign`; the overlay chip reads `01 Index search-page`.
2. Drop. The sheet `Assign Index` opens with rows `Search page`, `01 Index`, `repo`, `opr/search-page-01`, briefly `Checking…`, then the warning `The ticket folder has uncommitted changes…`. The button reads `Start`.
3. Pick agent `Claude Code`, model `claude-haiku-4-5-20251001`, press Enter.
4. Expected: `POST …/plans/01-index.md/assign` → `201` (check the Vite terminal / network: body carried `force: true`), the app navigates to the new session, its card shows the badge `search-page · 01`, the ticket card row reads `01 Index · Working` (or `Idle`). Confirm with curl: `curl -s localhost:39312/api/v1/sessions | jq '.sessions[] | {id, branch, ticket, model}'` shows `branch: "opr/search-page-01"` and `ticket: {slug: "search-page", planFile: "plans/01-index.md", role: "implementing"}`.

Also confirm the card did not navigate to the ticket page at any point during the drag (lesson 2).

- [ ] **Step 6: `plan_assigned` → Terminate and start**

The UI hides Assign on a live row by design, so the reachable path is the one where the plan becomes live between the dry run and Start (the sheet then adopts the daemon's 409 warnings):

1. On the board card click `Assign` on `02 UI`. The sheet opens; the dry run lists only the dirty warning; the button reads `Start`. Pick `Claude Code` / `claude-haiku-4-5-20251001` but do not press Start yet.
2. From the shell, assign the same plan behind the sheet's back:
   `curl -s -X POST "$B/search-page/plans/02-ui.md/assign" -H 'content-type: application/json' -d '{"harness":"claude-code","model":"claude-haiku-4-5-20251001","force":true}' | jq -r .session.id` → session A.
3. Press Start. Expected: `POST …/assign` → `409 TICKET_ASSIGN_BLOCKED`; the sheet now lists `This plan already has a live session. Starting again terminates it first.` plus the dirty line, shows the alert `The assignment needs confirmation.`, and the button reads `Terminate and start`.
4. Click `Terminate and start`. Expected: `POST /api/v1/sessions/A/kill` then `POST …/assign` with `force: true` → `201`; the app navigates to session B. Confirm with `curl -s localhost:39312/api/v1/sessions | jq '.sessions[] | {id, status, branch, ticket}'`: A is terminated, B carries `branch: "opr/search-page-02-2"` (the daemon's attempt suffix, which is why the sheet only promised `opr/search-page-02` and showed the hint) and `ticket.planFile: "plans/02-ui.md"`.
5. Kill B: `curl -s -X POST localhost:39312/api/v1/sessions/<B>/kill`. Back on the board the row reads `Terminated` and offers `Reassign`; click it, confirm the sheet opens with `Start` (the dry run has no `plan_assigned` for a dead session), press Escape, and confirm the session count is unchanged.

- [ ] **Step 7: Edit-save round trip and the stale bar**

1. Open `#/projects/repo/tickets/search-page?file=plans%2F02-ui.md`. The toolbar shows the back crumb `repo`, the file name, `Edit / Preview / Split`, `Save` (disabled while clean).
2. Switch to `Edit`. CodeMirror renders in the mono font on the terminal background with line numbers. Type a line; the dirty dot appears; the sidebar link to `spec.md` → the `Discard unsaved changes?` dialog appears; Cancel keeps you on the file.
3. Press Cmd+S (Ctrl+S on Linux/Windows). `Saved` flashes; `cat "$S/repo/.operator/tickets/search-page/plans/02-ui.md"` shows the new line.
4. Stale path: type another line (dirty), then from the shell `printf '\nfrom disk\n' >> "$S/repo/.operator/tickets/search-page/plans/02-ui.md"`. Within a couple of seconds the SSE-driven refetch shows the bar `This file changed on disk` (the draft is kept). Click `Keep mine` → the file on disk now holds your draft, the bar clears. Repeat the shell append, then press Cmd+S before the refetch lands → `409 TICKET_FILE_STALE` → the same bar; click `Reload` → the editor shows the disk version, bar gone.
5. `Split`: scroll the editor so `### Details` is the top line; the preview scrolls to the `Details` heading.

- [ ] **Step 8: Ticket defaults used by the planner spawn**

1. Open the project settings dialog → `Tickets`. Set `Planner agent` = `Claude Code`, `Planner model` = `claude-haiku-4-5-20251001`, `Reviews run in` = `New session`, save.
2. `curl -s localhost:39312/api/v1/projects/repo | jq .project.config.tickets` → `{"planner":{"agent":"claude-code","model":"claude-haiku-4-5-20251001"},"reviewerMode":"new"}`.
3. On the ticket page click `Plan with agent`, leave the model empty, Start. `curl -s localhost:39312/api/v1/sessions | jq '.sessions[] | select(.ticket.role=="planning") | {model, harness}'` shows `model: "claude-haiku-4-5-20251001"`.
4. Kill that session: `curl -s -X POST localhost:39312/api/v1/sessions/<id>/kill`.

- [ ] **Step 9: Tear down**

Kill every session the run spawned (`curl -s localhost:39312/api/v1/sessions | jq -r '.sessions[].id' | xargs -I{} curl -s -X POST localhost:39312/api/v1/sessions/{}/kill`), stop the Vite server, stop the daemon (`kill %1` or the pid from `$S/data/run.json`), remove the `tickets-assign-review` entry from `.claude/launch.json` (or delete the file if you created it), and confirm the user's daemons are untouched: `curl -s localhost:3001/readyz; curl -s localhost:3002/readyz` answer as before, and `curl -s localhost:3002/api/v1/projects | jq '[.projects[].id]'` does not list `repo`.

- [ ] **Step 10: Write the report**

`docs/superpowers/plans/2026-09-18-planning-tickets-assign-report.md` with: commit list (`git log --oneline origin/development..HEAD`), gate output summary (counts), the exact CodeMirror versions installed, every deviation from this plan and why (including any jsdom fallback taken in Tasks 5 or 8), the verification transcript from steps 5-8 (curl outputs and what the browser showed, plus the request/status lines seen for assign, save 200 and 409), anything left undone, and the "do not merge" reminder: the branch stays unmerged and unpushed for the planner's review.

- [ ] **Step 11: Commit**

```bash
git add docs/superpowers/plans/2026-09-18-planning-tickets-assign-report.md
git commit -m "docs: planning tickets assign plan execution report" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Do not push and do not merge; report the branch name, the worktree path and the HEAD sha.

---

## Self-review (run by the plan author on 2026-09-18)

**Spec coverage**

| Spec item | Task |
|---|---|
| §2.4 dry run (`?dryRun=1`), warnings, `force` | 3 (mutation), 4 (sheet) |
| §2.4 `plan_assigned` → UI asks to terminate first | 3 (`terminateSessionId` kill), 4 (`Terminate and start`) |
| §3.2 dnd-kit, plan rows draggable | 5, 6 |
| §3.2 droppable IDLE/WORKING column and sidebar project headers of the same project | 7 (`dropAccepts` in 2) |
| §3.2 other columns dim, target dashed highlight | 7 (designed; none existed) |
| §3.2 sheet: read-only ticket/plan/project/branch; editable harness, account, extra; warnings one per line; Start; Enter; Escape | 4 |
| §3.3 toolbar: file name, dirty dot, Edit/Preview/Split, Cmd+S | 9 |
| §3.3 CodeMirror 6 + lang-markdown, wrapping, mono font, skin colours | 8 |
| §3.3 Split with preview following the editor's top line | 8 (helper), 9 (nearest heading, stated) |
| §3.3 reload on SSE when clean; Reload / Keep mine bar when dirty; 409 shows the same bar | 9 |
| §4 Reassign on a terminated plan | 2 (`assignActionKey`), 6 |
| §4 `ticket_not_on_default_branch` as a warning | 1 (copy), 2, 4 |
| §5 drag → sheet → assign call with dry-run warnings | 4, 5, 6 tests |
| §5 editor dirty, Cmd+S, 409 bar, SSE reload only when clean | 9 tests |
| §5 i18n coverage | 1 |
| §6 Plan 3: `AssignPlanSheet.tsx`, `TicketDndProvider`, editor component, Reassign | 4, 5, 9, 6 |
| Prompt: project ticket defaults UI, scratch copy | 11 |
| Prompt: back crumb; no `text-accent`; intake chip fixed since the file is touched | 10, 7 |
| Prompt lesson 5: real renderer against isolated daemon, five scenarios | 12 |

Not in scope and deliberately absent: mobile, backend changes, review/merge flow changes, auto-assign on merge.

**Placeholder scan:** no TBD/TODO; every code step carries the code; the two "if X does not hold, do Y" fallbacks (dnd-kit keyboard drop in jsdom, `findFromDOM`) name the exact alternative.

**Type consistency:** `PlanDragData = { ticket: TicketWithProject; plan: PlanView }` is the shape used by `planDragId`, `dropAccepts`, `usePlanDraggable`, `TicketDndProvider` and the sheet's `AssignRequest`; `AssignPlanInput` fields (`dryRun`, `force`, `terminateSessionId`) match between Task 3's mutation, its tests, and Task 4's calls; `useTicketDropTarget` returns `{ setNodeRef, isOver, accepts, dragging }` in Task 5 and is consumed with those names in Task 7 and its mocks; `TicketEditor` props (`file`, `isError`, `error`, `warning`, `leading`, `reload`, `onDirtyChange`) match between Task 9 and Task 10; `ProjectSettingsSection` `"tickets"` matches the dialog entry.
