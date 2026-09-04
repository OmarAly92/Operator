# Single Session Kind, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the per-session chat/tui choice from every client and the daemon so every new session is the agent's TUI in a pty, delete the interface-transition surfaces and the desktop's dead blocks path, persist mobile's per-session view toggle, and clear the daemon's database.

**Architecture:** The ACP/chat subsystem stays in the tree and compiles (its deletion is Phase 4); only the request, resolution, settings, route and UI surfaces that let anyone *choose* it go. Desktop tasks come first so the renderer stops sending `mode` before the daemon starts rejecting it and before the generated API types lose the fields. Mobile follows for the same reason. Backend tasks land last and regenerate the OpenAPI spec and TypeScript types on each contract change, so every commit is green on its own.

**Tech Stack:** Go 1.x (chi, goose, sqlc, modernc sqlite), React + TypeScript (vitest, openapi-fetch, react-i18next), Flutter 3.44.5 (flutter_bloc, mocktail, shared_preferences).

**Spec:** `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`, section "Phase 1 — collapse the choice".

## Global Constraints

- Work on a fresh branch from `master` in its own worktree (superpowers:using-git-worktrees). The main checkout has unrelated uncommitted changes in `backend/internal/service/session`, `backend/internal/session_manager` and `frontend/src-tauri`; do not touch or commit them.
- Do not add code comments. Delete the comments attached to code you remove.
- Keep every change surgical. No drive-by cleanup outside the files this plan names, except deleting an import that your change made unused.
- Backend: never edit `backend/internal/storage/sqlite/gen/*` or an already-merged migration. After changing `queries/*.sql` run `npm run sqlc` from the repo root. After changing `controllers/dto.go` or `apispec/specgen/build.go` run `npm run api` from the repo root and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` with the Go change.
- Backend gate per task: `cd backend && go build ./... && go test ./<touched packages>/...`, then `go test ./...` before the final commit of the backend section.
- Frontend gate per task: `cd frontend && npx vitest run <touched test files>` then `npm run typecheck && npm run lint`.
- Mobile gate per task: `cd packages/mobile && flutter analyze` must print `No issues found!`, then `flutter test <touched files>`, then `flutter test` before the final mobile commit.
- Error envelopes keep `{error, code, message, requestId}`. New code for the removed field is `SESSION_MODE_REMOVED`.
- Mobile copy is inline English. Mobile navigation uses `RoutesStrings`. Parameterized paths live on `EndPoints`.
- Conventional commit messages. Every commit ends with the two trailers below.

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01A97XGLaWNszW59i6mcr4gb
```

## File map

**Desktop (delete):** `frontend/src/renderer/components/SessionInterfaceSwitch.tsx` + `.test.tsx`, `frontend/src/renderer/hooks/useSessionInterfaceTransition.ts` + `.test.tsx`, `frontend/src/renderer/hooks/useSettings.ts`, `frontend/src/renderer/hooks/useSessionBlocks.ts` + `.test.tsx`, `frontend/src/renderer/lib/block-assembly.ts` + `block-assembly.test.ts` + `block-assembly.fixtures.test.ts`, `frontend/src/renderer/components/CenterPane.blocks.test.tsx`, `frontend/e2e/blocks-find.spec.ts`, `frontend/e2e/blocks-viewport.spec.ts`, `frontend/e2e/support/fake-blocks-mux.ts`.

**Desktop (modify):** `SessionView.tsx` + `.test.tsx`, `CenterPane.tsx` + `CenterPane.test.tsx`, `settings/GeneralSettingsSection.tsx`, `TaskComposer.tsx` + `.test.tsx`, `SessionsBoard.tsx`, `BoardEmptyStates.tsx`, `OrchestratorReplacementDialog.tsx`, `routes/_shell.tsx`, `lib/spawn-orchestrator.ts` + `.test.ts`, `lib/restart-orchestrator.ts` + `.test.ts`, `lib/api-client.ts`, `lib/session-block.ts`, `types/workspace.ts`, `i18n/renderer-coverage.test.ts`, the eight `i18n/*.json` catalogs, `__tests__/integration/board-empty-states.test.tsx`.

**Mobile (delete):** `lib/feature/terminal/logic/interface_transition.dart`, `lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart` + `interface_switch_state.dart`, `lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart` + `interface_switch_sheet.dart`, `lib/feature/terminal/data/model/interface_transition_model.dart`, `interface_transition_status_model.dart`, `params/start_interface_transition_params.dart`, `lib/feature/spawn/data/model/operator_settings_model.dart`, `lib/core/error_handling/chat_preflight.dart`, `test/feature/terminal/logic/interface_transition_test.dart`, `test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`.

**Mobile (modify):** spawn body/cubit/state/params/data source/repository and their tests, `terminal_remote_data_source.dart`, `terminal_repository.dart`, `end_points.dart`, `service_locator.dart`, `app_router.dart`, `terminal_screen.dart`, `raw_terminal_pane.dart`, `chat_body.dart`, `conversation_menu_sheet.dart`, `session_route_screen.dart`, `session_model.dart`, `orchestrator_model.dart`, `sessions_cubit.dart`, `session_view_cubit.dart`, `cache_keys.dart`, and the tests named in each task.

**Backend (create):** `backend/internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql`, `backend/internal/storage/sqlite/migrate_clear_data_test.go`.

**Backend (delete):** `backend/internal/httpd/controllers/sessions_interface_transition.go`, `backend/e2e/chat_mode_test.go`.

**Backend (modify):** `ports/session.go`, `session_manager/manager.go`, `session_manager/chat_spawn.go` + `chat_spawn_test.go`, `daemon/lifecycle_wiring.go`, `daemon/daemon.go`, `daemon/wiring_test.go`, `daemon/settings_wiring.go`, `service/session/service.go` + `service_test.go`, `service/session/delegation.go` + `delegation_test.go`, `service/settings/service.go` + `service_test.go`, `httpd/controllers/dto.go`, `sessions.go` + `sessions_test.go`, `settings.go` + `settings_test.go`, `httpd/apispec/specgen/build.go`, `storage/sqlite/queries/app_settings.sql`, `storage/sqlite/store/app_settings_store.go` + `_test.go`, `cli/spawn.go`, `e2e/harness_test.go`, `docs/STATUS.md`, `docs/architecture.md`.

---

## Part A — Desktop

### Task 1: Delete the desktop interface switch

**Files:**
- Delete: `frontend/src/renderer/components/SessionInterfaceSwitch.tsx`, `frontend/src/renderer/components/SessionInterfaceSwitch.test.tsx`, `frontend/src/renderer/hooks/useSessionInterfaceTransition.ts`, `frontend/src/renderer/hooks/useSessionInterfaceTransition.test.tsx`
- Modify: `frontend/src/renderer/components/SessionView.tsx:7-22, 93-98, 140-205, 366-390, 436-444`
- Modify: `frontend/src/renderer/components/SessionView.test.tsx:11-20, 36-51, 121-127, 359, 373-376, 397-469`
- Modify: `frontend/src/renderer/i18n/renderer-coverage.test.ts:43`
- Modify: `frontend/src/renderer/lib/api-client.ts:83`

**Interfaces:**
- Produces: `SessionView` renders `CenterPane` with `topbarActions={<ShellTopbar embedded />}` and no `agentInputDisabled` prop value derived from a transition. Task 4 finishes the `CenterPane`-only render.

- [ ] **Step 1: Delete the four files**

```bash
cd frontend
git rm src/renderer/components/SessionInterfaceSwitch.tsx src/renderer/components/SessionInterfaceSwitch.test.tsx src/renderer/hooks/useSessionInterfaceTransition.ts src/renderer/hooks/useSessionInterfaceTransition.test.tsx
```

- [ ] **Step 2: Strip the switch from `SessionView.tsx`**

Remove these imports (lines 10-15 and 19-22):

```tsx
import {
	SessionInterfaceActionGroup,
	SessionInterfaceSwitchButton,
	SessionInterfaceSwitchDialog,
	SessionInterfaceTransitionNotice,
} from "./SessionInterfaceSwitch";
import {
	interfaceTransitionIsActive,
	useSessionInterfaceTransition,
} from "../hooks/useSessionInterfaceTransition";
```

Remove the two state hooks at lines 93-94 and the transition hook at line 98:

```tsx
	const [interfaceSwitchDialogOpen, setInterfaceSwitchDialogOpen] = useState(false);
	const [dismissedTransitionID, setDismissedTransitionID] = useState("");
	const interfaceSwitch = useSessionInterfaceTransition(session?.id);
```

Delete lines 140-199 (`activeInterfaceTransition` through the `interfaceSwitchAction` JSX) and replace lines 200-205 with:

```tsx
	const sessionHeaderActions = <ShellTopbar embedded />;
```

In the JSX block at lines 371-383, remove the `agentInputDisabled` prop entirely. Delete lines 385-390 (the `SessionInterfaceTransitionNotice` ternary). Delete lines 436-444 (`SessionInterfaceSwitchDialog`). Leave the `showChatSurface` ternary in place; Task 4 removes it.

- [ ] **Step 3: Strip the switch from `SessionView.test.tsx`**

Delete the hoisted `interfaceTransitionMock` and `interfaceTransitionState` blocks (lines 11-20). Delete the `vi.mock("../hooks/useSessionInterfaceTransition", …)` block (lines 36-51). In `beforeEach`, delete the four lines that reset `interfaceTransitionMock.*` and `interfaceTransitionState.status` (lines 373-376). Delete the four test blocks at lines 397-469: the `it.each` "switches an idle %s directly with drain", "keeps the policy dialog closed when an idle direct switch fails", the `it.each` "opens the switch policy dialog for %s", and "checks only the selected session when deciding whether to show the policy dialog". Leave `delete session.mode;` at line 359 for now; Task 4 removes it with the field.

- [ ] **Step 4: Remove the dead config entries**

In `frontend/src/renderer/i18n/renderer-coverage.test.ts` delete line 43, `"components/SessionInterfaceSwitch.tsx",`. In `frontend/src/renderer/lib/api-client.ts` delete line 83, `"/api/v1/sessions/{sessionId}/interface-transition",`.

- [ ] **Step 5: Run the touched tests, typecheck, lint**

```bash
cd frontend
npx vitest run src/renderer/components/SessionView.test.tsx src/renderer/i18n/renderer-coverage.test.ts
npm run typecheck
npm run lint
```

Expected: all pass. If typecheck reports an unused import (`useCallback`, `useState`) in `SessionView.tsx`, remove only that import.

- [ ] **Step 6: Commit**

```bash
git add -A frontend/src/renderer
git commit -m "feat(desktop): remove the session interface switch"
```

### Task 2: Delete the default-interface settings row and its hook

**Files:**
- Delete: `frontend/src/renderer/hooks/useSettings.ts`
- Modify: `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx:9-11, 13-67, 152`
- Modify: `frontend/src/renderer/i18n/en.json:575-579` and the same five keys in `de.json`, `es.json`, `fr.json`, `ja.json`, `ko.json`, `pt-BR.json`, `zh-CN.json`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: no renderer module imports `useSettings` or `useUpdateSessionInterface`. Step 2 removes the last other importer (`TaskComposer.tsx`) before Step 3 deletes the hook file.

- [ ] **Step 1: Remove the row from `GeneralSettingsSection.tsx`**

Delete the whole `SessionInterfaceRow` function (lines 13-67) and its mount `<SessionInterfaceRow />` at line 152. Delete the now-unused imports at lines 9-11:

```tsx
import { cn } from "../../lib/utils";
import { useSettings, useUpdateSessionInterface } from "../../hooks/useSettings";
import type { SessionMode } from "../../types/workspace";
```

(Match the exact import specifiers present in the file; the three lines import `cn`, the two hooks, and `SessionMode`.)

- [ ] **Step 2: Remove the `useSettings` import and `requiresTuiFallback` from `TaskComposer.tsx`**

Delete line 22 `import { useSettings } from "../hooks/useSettings";`, line 146 `const { settings } = useSettings();`, and lines 179-182:

```tsx
	const requiresTuiFallback =
		selectedAgent !== "" &&
		settings?.defaultSessionMode === "chat" &&
		!settings.chatHarnesses.includes(selectedAgent);
```

Change line 246 from `void submitTask(requiresTuiFallback ? "tui" : undefined);` to `void submitTask();`. Task 3 removes the `interfaceMode` parameter itself.

- [ ] **Step 3: Delete the hook file**

```bash
cd frontend && git rm src/renderer/hooks/useSettings.ts
```

- [ ] **Step 4: Delete the five locale keys from all eight catalogs**

Remove these keys from `en.json`, `de.json`, `es.json`, `fr.json`, `ja.json`, `ko.json`, `pt-BR.json`, `zh-CN.json` under `frontend/src/renderer/i18n/`:

```
settings.sessionInterface.available
settings.sessionInterface.chat
settings.sessionInterface.label
settings.sessionInterface.terminal
settings.sessionInterface.unavailable
```

Verify none remain:

```bash
grep -rn "sessionInterface" frontend/src/renderer/i18n/*.json
```

Expected: no output.

- [ ] **Step 5: Run the touched tests, typecheck, lint**

```bash
cd frontend
npx vitest run src/renderer/components/GlobalSettingsForm.test.tsx src/renderer/i18n/instance.test.ts src/renderer/components/TaskComposer.test.tsx
npm run typecheck
npm run lint
```

Expected: pass. `TaskComposer.test.tsx` still has the "offers an explicit Terminal UI retry" test, which passes until Task 3 removes the fallback because the mocked preflight error still triggers `canCreateAsTUI`.

- [ ] **Step 6: Commit**

```bash
git add -A frontend/src/renderer
git commit -m "feat(desktop): drop the default session interface setting"
```

### Task 3: Delete the chat-preflight TUI fallbacks

**Files:**
- Modify: `frontend/src/renderer/components/TaskComposer.tsx:35-59, 91, 101-130, 206-247, 345-368`
- Modify: `frontend/src/renderer/components/TaskComposer.test.tsx:296-317`
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:54, 111, 128, 219-253, 275-279, 367`
- Modify: `frontend/src/renderer/components/BoardEmptyStates.tsx:39, 47, 83-87`
- Modify: `frontend/src/renderer/components/OrchestratorReplacementDialog.tsx:5, 21, 30, 76-80`
- Modify: `frontend/src/renderer/routes/_shell.tsx:402-417, 798`
- Modify: `frontend/src/renderer/lib/spawn-orchestrator.ts:4, 13-18, 33-39, 44-53`, `frontend/src/renderer/lib/spawn-orchestrator.test.ts:2, 62-72, 124`
- Modify: `frontend/src/renderer/lib/restart-orchestrator.ts:3, 19, 38, 43`, `frontend/src/renderer/lib/restart-orchestrator.test.ts:89-115`
- Modify: `frontend/src/renderer/__tests__/integration/board-empty-states.test.tsx:18-22, 250-265`
- Modify: the key `newTask.createAsTui` in all eight `frontend/src/renderer/i18n/*.json`

**Interfaces:**
- Produces: `spawnOrchestrator(projectId, source, clean = false)` with no fourth parameter; `restartProjectOrchestrator` options without `mode`; `OrchestratorReplacementDialog` without `onRetryAsTui`; `ProjectBoardEmpty` without `onOpenOrchestratorAsTui`. The delegate POST body never contains `mode`.

- [ ] **Step 1: `TaskComposer.tsx`**

In `CreateTaskInput` (lines 35-42) delete `mode?: "tui";`. Delete `CHAT_PREFLIGHT_CODES` (lines 44-49) and the `TaskCreateError` class (lines 51-59). Delete line 91 `const [canCreateAsTUI, setCanCreateAsTUI] = useState(false);`. In `createTask` (lines 105-119) delete the spread `...(input.mode ? { mode: input.mode } : {}),` and change the throw to a plain error:

```tsx
				if (error) {
					throw new Error(apiErrorMessage(error, t("newTask.unableToStart")));
				}
```

Remove `apiErrorCode` from the `../lib/api-client` import if nothing else in the file uses it. Change `submitTask` to take no parameter: `const submitTask = async () => {`, delete `setCanCreateAsTUI(false);` (line 218), delete `mode: interfaceMode,` (line 228), and replace the catch body (lines 233-238) with:

```tsx
		} catch (err) {
			setError(err instanceof Error ? err.message : t("newTask.unableToStart"));
		} finally {
```

Delete the fallback button block inside the error banner (lines 350-363, from the comment through the closing `) : null}`), leaving:

```tsx
					{error && (
						<div className="flex items-center justify-between gap-3 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive">
							<span>{error}</span>
						</div>
					)}
```

Remove the `Button` import only if it is now unused in the file.

- [ ] **Step 2: `TaskComposer.test.tsx`**

Delete the test `it("offers an explicit Terminal UI retry after Chat preflight fails", …)` at lines 296-317.

- [ ] **Step 3: `spawn-orchestrator.ts` and its test**

Delete line 4 `import type { SessionMode } from "../types/conversation";`, the `CHAT_PREFLIGHT_CODES` set (lines 13-18), and both helpers `isChatPreflightCode` and `isChatPreflightError` (lines 33-39). Change the signature and body:

```ts
export async function spawnOrchestrator(
	projectId: string,
	source: OrchestratorSpawnSource,
	clean = false,
): Promise<string> {
	void captureRendererEvent("opr.renderer.orchestrator_spawn_requested", { project_id: projectId, source });
	try {
		const { data, error, response } = await apiClient.POST("/api/v1/orchestrators", {
			body: { projectId, clean },
		});
```

In `spawn-orchestrator.test.ts` remove `isChatPreflightError` from the import on line 2, delete the test "sends mode only when the user explicitly chooses it" (lines 62-72), and delete the line `expect(isChatPreflightError(error)).toBe(true);` (line 124) from "surfaces daemon spawn error messages and codes". Keep that test's `OrchestratorSpawnError` assertions.

- [ ] **Step 4: `restart-orchestrator.ts` and its test**

Delete line 3 `import type { SessionMode } from "../types/conversation";`, the `mode?: SessionMode;` option (line 19), `mode,` in the destructure (line 38), and call `spawnOrchestrator(projectId, "restart", true)` at line 43. In the test, rewrite "preserves typed preflight details and retries with an explicit TUI mode" (lines 89-115) to drop the mode:

```ts
	it("preserves typed spawn failure details", async () => {
		const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		vi.spyOn(queryClient, "invalidateQueries").mockResolvedValue();
		const setOrchestratorReplacementError = vi.fn();
		spawnMock.mockRejectedValue(
			new OrchestratorSpawnError("Claude Code is unavailable", "AGENT_UNAVAILABLE", "request-42", 400),
		);

		await restartProjectOrchestrator({
			projectId: "proj-1",
			queryClient,
			navigate: vi.fn(),
			setProjectRestarting: vi.fn(),
			setOrchestratorReplacementError,
		});

		expect(spawnMock).toHaveBeenCalledWith("proj-1", "restart", true);
		expect(setOrchestratorReplacementError).toHaveBeenLastCalledWith("proj-1", {
			message: "Claude Code is unavailable",
			code: "AGENT_UNAVAILABLE",
			requestId: "request-42",
		});
	});
```

Keep whatever trailing assertions the original test had after the `requestId` line, adjusted to the same shape.

- [ ] **Step 5: `_shell.tsx`**

Change the callback at lines 402-417 to drop the mode:

```tsx
	const restartOrchestrator = useCallback(
		async (projectId: string) => {
			await restartProjectOrchestrator({
				projectId,
				queryClient,
				navigate,
				setProjectRestarting,
				setOrchestratorReplacementError,
				onError: (error) => {
					captureOrchestratorReplacementFailure(error, projectId);
				},
			});
		},
		[navigate, queryClient, setOrchestratorReplacementError, setProjectRestarting],
	);
```

Delete line 798 `onRetryAsTui={(projectId) => void restartOrchestrator(projectId, "tui")}`.

- [ ] **Step 6: `OrchestratorReplacementDialog.tsx`**

Delete line 5 `import { isChatPreflightCode } from "../lib/spawn-orchestrator";`, the prop `onRetryAsTui: (projectId: string) => void;` (line 21), the destructured `onRetryAsTui,` (line 30), and the footer block at lines 76-80:

```tsx
						{error && isChatPreflightCode(error.code) ? (
							<Button type="button" variant="footer" onClick={() => projectId && onRetryAsTui(projectId)}>
								{t("newTask.createAsTui")}
							</Button>
						) : null}
```

- [ ] **Step 7: `SessionsBoard.tsx` and `BoardEmptyStates.tsx`**

In `SessionsBoard.tsx`: change line 54 to `import { spawnOrchestrator } from "../lib/spawn-orchestrator";`; delete line 111 (`canCreateAsTui` state), line 128 and line 235 (`setCanCreateAsTui(false);`), line 251 (`setCanCreateAsTui(isChatPreflightError(err));`); change `const openOrchestrator = async (mode?: "tui") => {` to `const openOrchestrator = async () => {` and the call to `spawnOrchestrator(projectId, "board", false)`; delete the topbar fallback button at lines 275-279; delete line 367 `onOpenOrchestratorAsTui={…}`.

In `BoardEmptyStates.tsx`: delete the prop `onOpenOrchestratorAsTui?: () => void;` (line 47), its destructure (line 39), and the block at lines 83-87:

```tsx
						{onOpenOrchestratorAsTui ? (
							<TopbarButton disabled={isSpawning || isProjectRestarting} onClick={onOpenOrchestratorAsTui}>
								{t("newTask.createAsTui")}
							</TopbarButton>
						) : null}
```

- [ ] **Step 8: `board-empty-states.test.tsx`**

Remove `isChatPreflightError` from the `vi.mock("../../lib/spawn-orchestrator", …)` factory (lines 18-22) so it only provides `spawnOrchestrator: spawnOrchestratorMock`. Delete the test "offers an explicit Terminal UI fallback when Chat preflight fails" (lines 250-265). Any remaining `toHaveBeenCalledWith(…, "board", false, undefined)` assertions in the file become `toHaveBeenCalledWith("proj-1", "board", false)`.

- [ ] **Step 9: Delete the locale key**

Remove `newTask.createAsTui` from all eight catalogs under `frontend/src/renderer/i18n/`. Verify:

```bash
grep -rn "createAsTui" frontend/src/renderer
```

Expected: no output.

- [ ] **Step 10: Run tests, typecheck, lint**

```bash
cd frontend
npx vitest run src/renderer/components/TaskComposer.test.tsx src/renderer/lib/spawn-orchestrator.test.ts src/renderer/lib/restart-orchestrator.test.ts src/renderer/__tests__/integration/board-empty-states.test.tsx src/renderer/components/SessionsBoard.test.tsx src/renderer/i18n/instance.test.ts
npm run typecheck
npm run lint
```

Expected: pass.

- [ ] **Step 11: Commit**

```bash
git add -A frontend/src/renderer
git commit -m "feat(desktop): remove the chat preflight terminal fallbacks"
```

### Task 4: SessionView always renders the terminal; delete the dead blocks path

**Files:**
- Delete: `frontend/src/renderer/hooks/useSessionBlocks.ts`, `frontend/src/renderer/hooks/useSessionBlocks.test.tsx`, `frontend/src/renderer/lib/block-assembly.ts`, `frontend/src/renderer/lib/block-assembly.test.ts`, `frontend/src/renderer/lib/block-assembly.fixtures.test.ts`, `frontend/src/renderer/components/CenterPane.blocks.test.tsx`, `frontend/e2e/blocks-find.spec.ts`, `frontend/e2e/blocks-viewport.spec.ts`, `frontend/e2e/support/fake-blocks-mux.ts`
- Modify: `frontend/src/renderer/components/SessionView.tsx:7, 232, 364-384`
- Modify: `frontend/src/renderer/components/SessionView.test.tsx:121-127, 359`
- Modify: `frontend/src/renderer/components/CenterPane.tsx:36, 51, 443-518, 808-820`
- Modify: `frontend/src/renderer/components/CenterPane.test.tsx:62-72`
- Modify: `frontend/src/renderer/lib/session-block.ts` (only if `blocksCoverHarness` has no importer left)
- Modify: `frontend/src/renderer/types/workspace.ts:124-125, 138-144`

**Interfaces:**
- Consumes: `sessionHeaderActions` from Task 1.
- Produces: `SessionBlocksPane({ sessionId, headerActions })` renders only the chat pane and is exported but unused (ACP is dormant until Phase 4). `WorkspaceSession` has no `mode` field. No renderer module imports `useSessionBlocks`.

- [ ] **Step 1: Delete the files**

```bash
cd frontend
git rm src/renderer/hooks/useSessionBlocks.ts src/renderer/hooks/useSessionBlocks.test.tsx src/renderer/lib/block-assembly.ts src/renderer/lib/block-assembly.test.ts src/renderer/lib/block-assembly.fixtures.test.ts src/renderer/components/CenterPane.blocks.test.tsx e2e/blocks-find.spec.ts e2e/blocks-viewport.spec.ts e2e/support/fake-blocks-mux.ts
```

- [ ] **Step 2: `SessionView.tsx` always renders `CenterPane`**

Change line 7 to `import { CenterPane } from "./CenterPane";`. Delete line 232 (`const showChatSurface = …`). Replace the ternary at lines 366-384 with the `CenterPane` element alone:

```tsx
					<div className="relative h-full min-h-0">
						<CenterPane
							daemonReady={daemonStatus.state === "ready"}
							onSelectSessionTerminal={selectSessionTerminal}
							onSelectReviewerTerminal={selectReviewerTerminal}
							reviewerTerminal={reviewerTerminal}
							session={session}
							terminalTarget={routedTerminalTarget}
							theme={theme}
							topbarActions={sessionHeaderActions}
						/>
					</div>
```

- [ ] **Step 3: `CenterPane.tsx`**

Delete line 36 `import { useSessionBlocks } from "../hooks/useSessionBlocks";`. Replace `SessionBlocksPane` and delete `TuiSessionBlocksPane` (lines 443-518) with:

```tsx
export function SessionBlocksPane({ sessionId, headerActions }: { sessionId: string; headerActions?: ReactNode }) {
	return (
		<div className="flex h-full min-h-0 flex-col">
			{headerActions}
			<ChatSessionBlocksPane sessionId={sessionId} />
		</div>
	);
}
```

Delete `useTuiSend` (lines 808-820). Delete `blocksCoverHarness` from the import on line 51 if its only use was line 512. If `agentInputDisabled` is now never passed by any caller, delete the prop from `CenterPane`'s props type and its uses (lines 76 and 100); confirm with `grep -rn agentInputDisabled src/renderer`.

- [ ] **Step 4: `CenterPane.test.tsx`**

Delete the `vi.mock("../hooks/useSessionBlocks", …)` block at lines 62-72.

- [ ] **Step 5: `SessionView.test.tsx`**

In the `vi.mock("./CenterPane", …)` factory (lines 121-127) delete the `SessionBlocksPane` entry, keeping `CenterPane`. Delete `delete session.mode;` at line 359.

- [ ] **Step 6: `types/workspace.ts`**

Delete `export type SessionMode = "chat" | "tui";` (lines 124-125 with its comment) and the `mode?: SessionMode;` field with its comment (lines 138-144). Then:

```bash
cd frontend && grep -rn "SessionMode\b" src/renderer --include='*.ts' --include='*.tsx' | grep -v "types/conversation.ts"
```

Expected: no remaining importer of the `workspace.ts` type. `types/conversation.ts` keeps its own `SessionMode` for the dormant chat snapshot.

- [ ] **Step 7: Prune `blocksCoverHarness` if orphaned**

```bash
cd frontend && grep -rn "blocksCoverHarness" src/renderer --include='*.ts' --include='*.tsx'
```

If the only hits are its definition in `lib/session-block.ts` and a test, delete the function and the test case. Do the same check for `BlockEventView` in `lib/terminal-mux.ts`; if only its definition remains, leave it (removing an exported type is not required).

- [ ] **Step 8: Run tests, typecheck, lint, e2e typecheck**

```bash
cd frontend
npx vitest run src/renderer/components/SessionView.test.tsx src/renderer/components/CenterPane.test.tsx src/renderer/lib
npm run typecheck
npm run typecheck:e2e
npm run lint
npm run check:desktop-parity
```

Expected: all pass. If `check:desktop-parity` names a deleted file, update `frontend/perf/parity-ledger.json` to drop that row and note it in the commit body.

- [ ] **Step 9: Commit**

```bash
git add -A frontend
git commit -m "feat(desktop): render the terminal for every session and drop the dead blocks pane"
```

---

## Part B — Mobile

All paths in this part are relative to `packages/mobile`.

### Task 5: Remove the interface picker from spawn

**Files:**
- Delete: `lib/feature/spawn/data/model/operator_settings_model.dart`, `lib/core/error_handling/chat_preflight.dart`
- Modify: `lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart:6, 9, 23-26, 141, 154, 157-160, 190-233, 252-261, 283-321`
- Modify: `lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart` (rewrite below)
- Modify: `lib/feature/spawn/presentation/spawn_screen/logic/spawn_state.dart:49-57`
- Modify: `lib/feature/spawn/data/model/params/spawn_session_params.dart` (rewrite below)
- Modify: `lib/feature/spawn/data/data_source/spawn_remote_data_source.dart:5, 12, 40-48`
- Modify: `lib/feature/spawn/data/repository/spawn_repository.dart:7, 14, 46-55`
- Test: `test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart` (rewrite below), `test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart:41, 98-118, 120-145, 180-220`, `test/feature/spawn/data/data_source/spawn_remote_data_source_test.dart:56-70, 77-81, 88-103, 111, 115`, `test/feature/spawn/data/repository/spawn_repository_test.dart:24, 112-140, 145`

**Interfaces:**
- Produces: `SpawnSessionParams({required projectId, prompt, issueId, harness})` whose `toJson()` never emits `mode`; `SpawnCubit` without `mode`, `setMode`, `chatHarnesses`; `SpawnFailureState(Failure failure)`; `SpawnRepository`/`SpawnRemoteDataSource` without `getSettings`.

- [ ] **Step 1: Rewrite the cubit test first**

Replace `test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart` with:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

AgentInfo _agent(String id) => AgentInfo(id: id, label: id, authStatus: 'authorized');

AgentCatalog get _catalog => AgentCatalog(
  supported: [_agent('claude-code'), _agent('codex')],
  installed: [_agent('claude-code'), _agent('codex')],
  authorized: [_agent('claude-code'), _agent('codex')],
);

void main() {
  late _MockSpawnRepository repository;

  SpawnCubit buildCubit() {
    when(() => repository.getAgents())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
    return SpawnCubit(repository);
  }

  setUpAll(() => registerFallbackValue(const SpawnSessionParams(projectId: 'p')));

  setUp(() {
    repository = _MockSpawnRepository();
    when(() => repository.spawn(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionModel(id: 's1'))),
    );
  });

  blocTest<SpawnCubit, SpawnState>(
    'offers the whole catalog and picks its default agent',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.agents.map((a) => a.id), ['claude-code', 'codex']);
      expect(cubit.harness, 'claude-code');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'emits when the project changes',
    build: () => SpawnCubit(repository),
    act: (cubit) => cubit.setProject('p'),
    expect: () => [isA<CatalogReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.projectId, 'p'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'emits when the harness changes',
    build: () => SpawnCubit(repository),
    act: (cubit) => cubit.setHarness('codex'),
    expect: () => [isA<CatalogReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.harness, 'codex'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'reports a catalog fetch failure instead of showing an empty picker',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      return SpawnCubit(repository);
    },
    act: (cubit) => cubit.loadCatalog(),
    expect: () => [isA<CatalogLoadingState>(), isA<CatalogFailureState>()],
  );

  blocTest<SpawnCubit, SpawnState>(
    'refuses to submit without a name and a task',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = '  ';
      cubit.prompt = 'do the thing';
      await cubit.submit();
    },
    verify: (cubit) => verifyNever(() => repository.spawn(any())),
    expect: () => [
      isA<CatalogLoadingState>(),
      isA<CatalogReadyState>(),
      isA<CatalogReadyState>(),
      isA<SpawnValidationFailureState>(),
    ],
  );

  blocTest<SpawnCubit, SpawnState>(
    'spawns with the chosen project and agent and never names a session mode',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
    },
    verify: (cubit) {
      final params = verify(() => repository.spawn(captureAny())).captured.single
          as SpawnSessionParams;
      expect(params.projectId, 'p');
      expect(params.issueId, 'flaky login');
      expect(params.prompt, 'fix it');
      expect(params.harness, 'claude-code');
      expect(params.toJson().containsKey('mode'), isFalse);
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'surfaces a spawn failure with the daemon message',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
      when(() => repository.spawn(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'branch is busy')),
      );
      return SpawnCubit(repository);
    },
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'n';
      cubit.prompt = 'p';
      await cubit.submit();
    },
    verify: (cubit) => expect((cubit.state as SpawnFailureState).failure.message, 'branch is busy'),
  );
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd packages/mobile && flutter test test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart
```

Expected: compile errors (`mode` is a required parameter of `SpawnSessionParams`; `SpawnFailureState` needs `chatUnavailable`).

- [ ] **Step 3: Rewrite `SpawnSessionParams`**

```dart
import 'package:equatable/equatable.dart';

class SpawnSessionParams extends Equatable {
  const SpawnSessionParams({
    required this.projectId,
    this.prompt,
    this.issueId,
    this.harness,
  });

  final String projectId;
  final String? prompt;
  final String? issueId;
  final String? harness;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    if (prompt != null && prompt!.isNotEmpty) 'prompt': prompt,
    if (issueId != null && issueId!.isNotEmpty) 'issueId': issueId,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    'kind': 'worker',
  };

  @override
  List<Object?> get props => [projectId, prompt, issueId, harness];
}
```

- [ ] **Step 4: Rewrite `SpawnCubit`**

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

part 'spawn_state.dart';

class SpawnCubit extends Cubit<SpawnState> {
  SpawnCubit(this._repository) : super(const SpawnInitialState());

  final SpawnRepository _repository;

  AgentCatalog? _catalog;
  int _revision = 0;

  String? projectId;
  String harness = '';
  String name = '';
  String prompt = '';

  List<RankedAgent> get agents => rankAgents(_catalog);

  void setProject(String? next) {
    projectId = next;
    _bump();
  }

  void setHarness(String next) {
    harness = next;
    _bump();
  }

  String _pickHarness(String current) =>
      agents.any((agent) => agent.id == current) ? current : (defaultAgent(agents) ?? '');

  Future<void> loadCatalog() async {
    emit(const CatalogLoadingState());
    final result = await _repository.getAgents();
    result.when(
      onSuccess: (response) {
        _catalog = response.data;
        harness = _pickHarness(harness);
        _bump();
      },
      onFailure: (failure) => emit(CatalogFailureState(failure)),
    );
  }

  Future<void> refreshCatalog() async {
    emit(const CatalogLoadingState());
    final result = await _repository.refreshAgents();
    result.when(
      onSuccess: (response) {
        _catalog = response.data;
        harness = _pickHarness(harness);
        _bump();
      },
      onFailure: (failure) => emit(CatalogFailureState(failure)),
    );
  }

  Future<void> submit() async {
    if (name.trim().isEmpty || prompt.trim().isEmpty) {
      emit(const SpawnValidationFailureState('Name and task are required.'));
      return;
    }
    final project = projectId;
    if (project == null || project.isEmpty) {
      emit(const SpawnValidationFailureState('Choose a project.'));
      return;
    }
    emit(const SpawnLoadingState());
    final result = await _repository.spawn(SpawnSessionParams(
      projectId: project,
      prompt: prompt.trim(),
      issueId: name.trim(),
      harness: harness,
    ));
    TelemetryRuntime.featureUsed('spawn', succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) => emit(SpawnSuccessState(response.data ?? const SessionModel())),
      onFailure: (failure) => emit(SpawnFailureState(failure)),
    );
  }

  void _bump() => emit(CatalogReadyState(++_revision));
}
```

If `spawn_state.dart` references a type whose import you just removed (`GlobalResponse`, `Result`), add that import back; otherwise the list above is complete.

- [ ] **Step 5: Simplify `SpawnFailureState`**

In `spawn_state.dart` replace lines 49-57 with:

```dart
final class SpawnFailureState extends SpawnState {
  const SpawnFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
```

- [ ] **Step 6: Drop the settings fetch from the data layer**

In `spawn_remote_data_source.dart` delete the `operator_settings_model.dart` import (line 5), the abstract `getSettings()` (line 12) and its implementation (lines 40-48). In `spawn_repository.dart` delete the same import (line 7), the abstract method (line 14) and the implementation (lines 46-55). Then:

```bash
cd packages/mobile
git rm lib/feature/spawn/data/model/operator_settings_model.dart lib/core/error_handling/chat_preflight.dart
grep -rn "OperatorSettingsModel\|chat_preflight\|isChatPreflightFailure\|chatErrorCopy" lib
```

Expected: no output.

- [ ] **Step 7: Remove the picker from `spawn_body.dart`**

Delete the three hint constants (lines 23-26). Delete the `chat_preflight.dart` import (line 6) and the `app_ink_well.dart` import (line 9). Delete `final catalogLoaded = …` (line 141) and `final showNoChatAgentWarning = …` (line 154). Replace the failure branch (lines 157-160) with:

```dart
        if (state is SpawnFailureState) errorText = state.failure.message;
```

Delete lines 190-233, from the `const VerticalSpace(20),` that precedes `AppText('INTERFACE', …)` through the closing `],` of the `showNoChatAgentWarning` block, so the column runs from the agent row straight into the `const VerticalSpace(20)` before the NAME field. Delete the `state.chatUnavailable` TextButton block (lines 252-261). Delete the `_ModeOption` class (lines 283-321).

- [ ] **Step 8: Update the remaining spawn tests**

`spawn_body_test.dart`: line 41 becomes `registerFallbackValue(const SpawnSessionParams(projectId: 'p1'))`; remove the `getSettings` stubs and `OperatorSettingsModel` import so `stubChatOnlyCatalog`/`stubEmptyChatCatalog` become plain catalog stubs (rename them `stubCatalog` and `stubSingleAgentCatalog` if you keep both); delete the tests at lines 120-131, 133-145, 180-208 and 210-220. Keep "submitting with an empty name…" and "a filled form calls repository.spawn once", and add to the latter, after the body is pumped:

```dart
    expect(find.text('INTERFACE'), findsNothing);
    expect(find.text('Chat'), findsNothing);
```

`spawn_remote_data_source_test.dart`: delete the two settings tests (lines 56-70); at line 77-81 the expected body becomes `{'projectId': 'p', 'kind': 'worker'}`; in "sends every field it was given" drop `mode: 'tui'` from the params and `'mode': 'tui'` from the expected body; drop `mode: 'chat'` at lines 111 and 115.

`spawn_repository_test.dart`: line 24 and 145 drop `mode: 'chat'`; delete the whole `getSettings` group (the tests around lines 112-140 that stub `dataSource.getSettings`); remove the `operator_settings_model.dart` import.

- [ ] **Step 9: Analyze and test**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/spawn
```

Expected: `No issues found!` and all spawn tests pass. If `flutter analyze` reports an unused import in `spawn_body.dart` (for example `haptics.dart`), remove that import.

- [ ] **Step 10: Commit**

```bash
git add -A packages/mobile
git commit -m "feat(mobile): remove the interface picker from spawn"
```

### Task 6: Delete the mobile interface-transition coordinator

**Files:**
- Delete: `lib/feature/terminal/logic/interface_transition.dart`, `lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart`, `lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_state.dart`, `lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart`, `lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart`, `lib/feature/terminal/data/model/interface_transition_model.dart`, `lib/feature/terminal/data/model/interface_transition_status_model.dart`, `lib/feature/terminal/data/model/params/start_interface_transition_params.dart`, `test/feature/terminal/logic/interface_transition_test.dart`, `test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`
- Modify: `lib/feature/terminal/data/data_source/terminal_remote_data_source.dart:4-5, 8, 16-21, 62-94`
- Modify: `lib/feature/terminal/data/repository/terminal_repository.dart:6-7, 10, 17-24, 64-77`
- Modify: `lib/core/api/api_request_helpers/end_points.dart:51-52`
- Modify: `lib/core/utils/service_locator.dart:54, 228-233`
- Modify: `lib/core/app_routes/app_router.dart:25, 88-90, 115-117`
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart:8, 10, 17-38, 77-85`
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart:3, 5, 41-46`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart:32, 34-35, 126, 154-155, 212-234, 423-436`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart:17, 36, 52, 65, 74, 202-211`
- Test: `test/feature/terminal/terminal_harness.dart:26, 37-38, 66, 110-119, 156`, `test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart:88-131`, `test/feature/terminal/data/model/terminal_models_test.dart:2-3, 6, 46-90, 99-102`, `test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart:9, 78-122`, `test/core/utils/service_locator_test.dart:22, 131-139`, `test/core/app_routes/app_router_test.dart:13, 24-25, 62`, `test/core/api/end_points_test.dart:45-48`, `test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart:54-55, 129, 151, 172, 235, 548, 589, 623, 678-690`, `test/feature/sessions/presentation/session_route/session_route_screen_test.dart:40-41, 71, 82, 101-110, 166, 203`

**Interfaces:**
- Produces: `TerminalRepository` and `TerminalRemoteDataSource` expose only shell and send methods; no `InterfaceSwitchCubit` anywhere; `ConversationMenuAction` has no `terminalUi` value and `showConversationMenu` has no `interfaceSupported` parameter.

- [ ] **Step 1: Delete the files**

```bash
cd packages/mobile
git rm lib/feature/terminal/logic/interface_transition.dart \
  lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart \
  lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_state.dart \
  lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart \
  lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart \
  lib/feature/terminal/data/model/interface_transition_model.dart \
  lib/feature/terminal/data/model/interface_transition_status_model.dart \
  lib/feature/terminal/data/model/params/start_interface_transition_params.dart \
  test/feature/terminal/logic/interface_transition_test.dart \
  test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart
```

- [ ] **Step 2: Data layer and endpoint**

`terminal_remote_data_source.dart`: delete imports at lines 4, 5, 8; delete the three abstract declarations (lines 16-21); delete the three implementations (lines 62-94).

`terminal_repository.dart`: delete imports at lines 6, 7, 10; delete the abstract declarations (lines 17-24); delete the implementations (lines 64-77).

`end_points.dart`: delete lines 51-52 (`sessionInterfaceTransition`).

- [ ] **Step 3: Wiring**

`service_locator.dart`: delete the import at line 54 and the `registerFactoryParam<InterfaceSwitchCubit, …>` block at lines 228-233. If `unawaited` is now unused, `flutter analyze` will say so; then delete the `dart:async` import.

`app_router.dart`: delete the import at line 25 and both `BlocProvider<InterfaceSwitchCubit>` entries (lines 88-90 and 115-117).

- [ ] **Step 4: Terminal UI**

`terminal_screen.dart`: delete imports at lines 8 and 10, the `_requestSwitch` method (lines 17-38), and the "Open Chat interface" action (lines 77-85, the `if (!args.shellOnly) Semantics(... label: 'Open Chat interface' ...)` block). If `extensions.dart` (`showSnackBar`) is now unused, delete that import too.

`raw_terminal_pane.dart`: delete imports at lines 3 and 5 and the `BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>` child (lines 41-46).

- [ ] **Step 5: Chat body stays compilable without the switch**

`conversation_menu_sheet.dart`: delete `terminalUi,` from `ConversationMenuAction` (line 17); delete `required bool interfaceSupported,` from the function parameters (line 36), the pass-through `interfaceSupported: interfaceSupported,` (line 52), the constructor parameter (line 65) and the field (line 74); delete the `_MenuRow(icon: Icons.swap_horiz, label: 'Open Terminal UI', …)` entry (lines 202-211).

`chat_body.dart`: delete imports at lines 32, 34, 35 (`interface_switch_cubit.dart`, `interface_switch_overlay.dart`, `interface_switch_sheet.dart`); delete `interfaceSupported: context.read<InterfaceSwitchCubit>().supported,` (line 126); delete the two lines `case ConversationMenuAction.terminalUi:` / `await _switchToTerminal();` (lines 154-155); delete `_switchToTerminal()` (lines 212-234); delete the overlay `BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>(…)` child in the `Stack` (lines 423-436).

- [ ] **Step 6: Tests**

`terminal_harness.dart`: delete the import (line 26), `MockInterfaceSwitchCubit` (lines 37-38), the `switchCubit` field (line 66), the ten `when(() => switchCubit.…)` stubs (lines 110-119), and the `BlocProvider<InterfaceSwitchCubit>.value` provider (line 156).

`terminal_screen_test.dart`: delete the four tests at lines 88-131 ("explains why Chat is unavailable…", "asks how to hand off…", "covers the terminal while a transition is in flight", "a worktree shell has no Chat handoff at all").

`terminal_models_test.dart`: delete imports at lines 2, 3, 6; delete the `InterfaceTransitionStatusModel` group (lines 46-90); delete the `StartInterfaceTransitionParams` expectation (lines 99-102) inside the `params` test.

`terminal_remote_data_source_test.dart`: delete the import at line 9 and the three tests at lines 78-122.

`service_locator_test.dart`: delete the import at line 22 and the test at lines 131-139.

`app_router_test.dart`: delete the import at line 13, `_MockInterfaceSwitchCubit` (lines 24-25), and the registration line 62.

`end_points_test.dart`: delete the `sessionInterfaceTransition` expectation (lines 45-48).

`chat_body_test.dart`: delete `_MockInterfaceSwitchCubit` (lines 54-55), the field (line 129), its construction (line 151), the state stub (line 172), the four `BlocProvider<InterfaceSwitchCubit>.value` providers (lines 235, 548, 589, 623), and the test "asks how to hand off before switching to the Terminal UI" (lines 678-690). Remove the now-unused import of `interface_switch_cubit.dart`.

`session_route_screen_test.dart`: delete `_MockInterfaceSwitchCubit` (lines 40-41), the `switchCubit` field (line 71), its construction (line 82), the stubs (lines 101-110), and both `BlocProvider<InterfaceSwitchCubit>.value` providers (lines 166 and 203). Remove the import.

- [ ] **Step 7: Verify nothing references the coordinator**

```bash
cd packages/mobile
grep -rn "InterfaceSwitch\|interface_transition\|interfaceTransition\|InterfaceTransition\|interface-transition" lib test
```

Expected: no output.

- [ ] **Step 8: Analyze and test**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/terminal test/core test/feature/chat test/feature/sessions
```

Expected: `No issues found!`, all pass.

- [ ] **Step 9: Commit**

```bash
git add -A packages/mobile
git commit -m "feat(mobile): delete the interface transition coordinator"
```

### Task 7: Route every session to the terminal

**Files:**
- Modify: `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` (rewrite of `_lookup` and `build` below)
- Modify: `lib/core/app_routes/app_router.dart:87` (the `BlocProvider<ChatCubit>` under `RoutesStrings.session`)
- Modify: `lib/feature/sessions/data/model/session_model.dart:13, 30, 47, 62`
- Modify: `lib/feature/sessions/data/model/orchestrator_model.dart:12, 24, 39, 48`
- Modify: `lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart:114`
- Test: `test/feature/sessions/presentation/session_route/session_route_screen_test.dart:215-223, 244-256`, plus any test under `test/feature/sessions` that constructs `SessionModel(... mode: ...)` or asserts `.mode`

**Interfaces:**
- Produces: `SessionModel` and `OrchestratorModel` have no `mode`; `SessionRouteScreen` renders `TerminalScreen` for any session it can find and the not-found scaffold otherwise.

- [ ] **Step 1: Update the route test**

In `session_route_screen_test.dart` rename the first test and drop the `mode` from both fixtures:

```dart
  testWidgets('renders the terminal for any session it can find', (tester) async {
    await pumpRoute(
      tester,
      sessions: const [SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code')],
    );

    expect(find.byType(TerminalScreen), findsOneWidget);
  });
```

and in "uses a cached session without another board refresh" the fixture becomes `SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code')`. Run it:

```bash
cd packages/mobile && flutter test test/feature/sessions/presentation/session_route/session_route_screen_test.dart
```

Expected: the first test fails, because a session with no `mode` currently falls through to the not-found scaffold.

- [ ] **Step 2: Rewrite the route**

In `session_route_screen.dart` delete the three chat imports (`chat_cubit.dart`, `chat_screen.dart`, `conversation_blocks_cubit.dart`). Change `_lookup` to return `({String id, String title, String? projectId, String? previewUrl, String? harness})?` and drop `mode:` from both record literals. Replace everything in `build` from `if (session?.mode == 'chat') {` through the end of the `if (session?.mode == 'tui') {` block with:

```dart
        if (session != null) {
          final args = TerminalArgs(
            id: session.id,
            sessionId: session.id,
            title: session.title,
            projectId: session.projectId,
            previewUrl: session.previewUrl,
            harness: session.harness,
          );
          return MultiBlocProvider(
            providers: [
              BlocProvider<TerminalCubit>(
                create: (_) => sl<TerminalCubit>(param1: args),
              ),
              BlocProvider<SessionViewCubit>(
                create: (_) => sl<SessionViewCubit>(param1: args),
              ),
              BlocProvider<BlocksCubit>(
                create: (_) => sl<BlocksCubit>(param1: args.sessionId, param2: args.harness),
              ),
              BlocProvider<PreviewCubit>(
                create: (_) => sl<PreviewCubit>(param1: session.id, param2: session.previewUrl),
              ),
            ],
            child: const TerminalScreen(),
          );
        }
```

The not-found `Scaffold` below stays as it is.

- [ ] **Step 3: Stop creating a chat cubit for every session route**

In `app_router.dart`, under `case RoutesStrings.session:`, delete `BlocProvider<ChatCubit>(create: (_) => sl<ChatCubit>(param1: sessionId)),` (line 87). Remove the `chat_cubit.dart` import if nothing else in the file uses it.

- [ ] **Step 4: Drop `mode` from the session models**

`session_model.dart`: delete `this.mode,` (line 13), `final String? mode;` (line 30), `mode: json['mode'] as String?,` (line 47), and `mode,` from `props` (line 62).

`orchestrator_model.dart`: delete `this.mode,` (line 12), `final String? mode;` (line 24), `mode: json['mode'] == 'chat' ? 'chat' : 'tui',` (line 39), and `mode,` from `props` (line 48).

`sessions_cubit.dart`: delete `mode: s.mode,` (line 114).

Then:

```bash
cd packages/mobile && grep -rn "mode:" test/feature/sessions | grep -v "SessionViewMode\|VoiceMode"
```

Remove every `mode: '...'` argument and every assertion on `.mode` those hits show. `lib/feature/blocks/logic/block_actions.dart` keeps its own string `mode` field; it is not the session model and stays.

- [ ] **Step 5: Analyze and test**

```bash
cd packages/mobile
flutter analyze
flutter test test/feature/sessions test/core/app_routes
```

Expected: `No issues found!`, all pass.

- [ ] **Step 6: Commit**

```bash
git add -A packages/mobile
git commit -m "feat(mobile): route every session to the terminal"
```

### Task 8: Persist the per-session view toggle

**Files:**
- Modify: `lib/core/helpers/cache/cache_keys.dart`
- Modify: `lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`
- Modify: `lib/core/utils/service_locator.dart:256-258`
- Test: `test/feature/blocks/presentation/session_view_test.dart:1-48`

**Interfaces:**
- Produces: `SessionViewMode? persistedViewMode(String key)`, `String sessionViewKey(TerminalArgs args)`, `SessionViewCubit(SessionViewMode initial, {String? persistKey})`. `toggle()` writes `mode.name` under `CacheKeys.sessionView(persistKey)` when a key is given. Callers that construct the cubit directly without a key (the terminal test harness, the session route test) keep working unchanged.

- [ ] **Step 1: Write the failing tests**

In `test/feature/blocks/presentation/session_view_test.dart` add the imports

```dart
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

and replace the `SessionViewCubit` group with:

```dart
  group('SessionViewCubit', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CacheHelper.init();
    });

    test('toggles between the two modes', () {
      final cubit = SessionViewCubit(SessionViewMode.blocks);

      expect(cubit.mode, SessionViewMode.blocks);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.raw);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.blocks);
      cubit.close();
    });

    test('remembers the toggled mode under its key', () async {
      final cubit = SessionViewCubit(SessionViewMode.blocks, persistKey: 's-1');
      cubit.toggle();
      await Future<void>.delayed(Duration.zero);

      expect(persistedViewMode('s-1'), SessionViewMode.raw);
      expect(persistedViewMode('s-2'), isNull);
      cubit.close();
    });

    test('a shell keys its preference by handle so it never collides with its session', () {
      expect(
        sessionViewKey(const TerminalArgs(id: 'h-1', sessionId: 's-1', title: 'Shell', shellOnly: true)),
        'h-1',
      );
      expect(sessionViewKey(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S')), 's-1');
    });

    test('ignores an unknown saved value', () async {
      SharedPreferences.setMockInitialValues({'opr.session.view.s-9': 'sideways'});
      await CacheHelper.init();

      expect(persistedViewMode('s-9'), isNull);
    });
  });
```

- [ ] **Step 2: Run to see it fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/session_view_test.dart
```

Expected: compile error, `persistKey`, `persistedViewMode`, `sessionViewKey` undefined.

- [ ] **Step 3: Add the cache key**

In `lib/core/helpers/cache/cache_keys.dart` add after `chatDraft`:

```dart
  static String sessionView(String key) => 'opr.session.view.$key';
```

- [ ] **Step 4: Implement the cubit**

Replace `session_view_cubit.dart` with:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

part 'session_view_state.dart';

enum SessionViewMode { blocks, raw }

SessionViewMode defaultViewMode(TerminalArgs args) {
  if (args.shellOnly) return SessionViewMode.raw;
  return BlockHarnesses.covers(args.harness) ? SessionViewMode.blocks : SessionViewMode.raw;
}

String sessionViewKey(TerminalArgs args) => args.shellOnly ? args.id : args.sessionId;

SessionViewMode? persistedViewMode(String key) {
  final saved = CacheHelper.get(CacheKeys.sessionView(key)) as String?;
  for (final mode in SessionViewMode.values) {
    if (mode.name == saved) return mode;
  }
  return null;
}

class SessionViewCubit extends Cubit<SessionViewState> {
  SessionViewCubit(SessionViewMode initial, {this.persistKey}) : super(SessionViewReadyState(initial));

  final String? persistKey;

  SessionViewMode get mode => (state as SessionViewReadyState).mode;

  void toggle() {
    final next = mode == SessionViewMode.blocks ? SessionViewMode.raw : SessionViewMode.blocks;
    final key = persistKey;
    if (key != null && key.isNotEmpty) CacheHelper.save(CacheKeys.sessionView(key), next.name);
    emit(SessionViewReadyState(next));
  }
}
```

- [ ] **Step 5: Wire the factory**

In `service_locator.dart` replace lines 256-258 with:

```dart
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(
        persistedViewMode(sessionViewKey(args)) ?? defaultViewMode(args),
        persistKey: sessionViewKey(args),
      ),
    );
```

- [ ] **Step 6: Analyze and run the full mobile suite**

```bash
cd packages/mobile
flutter analyze
flutter test
```

Expected: `No issues found!`, full suite green. If `flutter analyze` flags the un-awaited `CacheHelper.save` in `toggle()`, wrap it as `unawaited(CacheHelper.save(...))` with `import 'dart:async';`, matching whatever `SkinCubit.setSkin` does in this checkout.

- [ ] **Step 7: Commit**

```bash
git add -A packages/mobile
git commit -m "feat(mobile): remember the blocks/raw view per session on the device"
```

---

## Part C — Backend

All paths in this part are relative to `backend/` unless they start with `docs/` or `frontend/`.

### Task 9: Migration 0094 clears the store

**Files:**
- Create: `internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql`
- Test: `internal/storage/sqlite/migrate_clear_data_test.go`

**Interfaces:**
- Consumes: `openTestDB`, `upTo`, `mustExec` from the package's existing migration tests.
- Produces: an applied database whose every table except `app_settings` and `goose_db_version` is empty. `sqlite_sequence` is left alone on purpose so `change_log` ids keep increasing and no client cursor moves backwards.

- [ ] **Step 1: Write the failing test**

Create `internal/storage/sqlite/migrate_clear_data_test.go`:

```go
package sqlite

import (
	"testing"
	"time"
)

var clearedTables = []string{
	"change_log",
	"block_events",
	"terminal_blocks",
	"shell_terminals",
	"conversation_provider_events",
	"conversation_activities",
	"conversation_messages",
	"conversation_turns",
	"conversation_branches",
	"conversations",
	"session_interface_transition_messages",
	"session_interface_transitions",
	"agent_switches",
	"agent_native_sessions",
	"agent_model_catalog",
	"pr_review_threads",
	"pr_reviews",
	"pr_comment",
	"pr_checks",
	"pr",
	"review_run",
	"review",
	"session_cleanup_facts",
	"session_worktrees",
	"notifications",
	"telemetry_event",
	"model_usage_events",
	"usage_bindings",
	"usage_sources",
	"sessions",
	"workspace_repos",
	"projects",
}

func TestMigration0094ClearsEveryTableExceptAppSettings(t *testing.T) {
	db := openTestDB(t)
	upTo(t, db, 93)

	now := time.Now().UTC()
	mustExec(t, db, `INSERT INTO projects (id, path, display_name, registered_at) VALUES ('p1', '/tmp/p1', 'proj', ?)`, now)
	mustExec(t, db, `INSERT INTO sessions (id, project_id, num, kind, activity_state, activity_last_at, is_terminated, created_at, updated_at)
		VALUES ('opr-1', 'p1', 1, 'worker', 'idle', ?, 0, ?, ?)`, now, now, now)
	mustExec(t, db, `UPDATE app_settings SET ui_locale = 'de' WHERE id = 1`)

	var seeded int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sessions`).Scan(&seeded); err != nil || seeded != 1 {
		t.Fatalf("seed sessions = %d, %v", seeded, err)
	}

	upTo(t, db, 94)

	for _, table := range clearedTables {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM ` + table).Scan(&n); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if n != 0 {
			t.Errorf("%s still holds %d rows", table, n)
		}
	}

	var settingsRows int
	var locale string
	if err := db.QueryRow(`SELECT COUNT(*), MAX(ui_locale) FROM app_settings`).Scan(&settingsRows, &locale); err != nil {
		t.Fatalf("read app_settings: %v", err)
	}
	if settingsRows != 1 || locale != "de" {
		t.Errorf("app_settings = %d rows, locale %q; want the single seeded row with locale de", settingsRows, locale)
	}
}
```

If either seed `INSERT` fails on a `NOT NULL` column added between migration 0042 and 0093, add that column to the insert with a literal value; the seed only has to put one row in `projects` and one in `sessions`.

- [ ] **Step 2: Run it to see it fail**

```bash
cd backend && go test ./internal/storage/sqlite/ -run TestMigration0094 -v
```

Expected: FAIL, `migrate to 94: no migration files found` or a version error, because 0094 does not exist.

- [ ] **Step 3: Write the migration**

Create `internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql`:

```sql
-- +goose Up
-- +goose StatementBegin
DELETE FROM change_log;
DELETE FROM block_events;
DELETE FROM terminal_blocks;
DELETE FROM shell_terminals;
DELETE FROM conversation_provider_events;
DELETE FROM conversation_activities;
DELETE FROM conversation_messages;
DELETE FROM conversation_turns;
DELETE FROM conversation_branches;
DELETE FROM conversations;
DELETE FROM session_interface_transition_messages;
DELETE FROM session_interface_transitions;
DELETE FROM agent_switches;
DELETE FROM agent_native_sessions;
DELETE FROM agent_model_catalog;
DELETE FROM pr_review_threads;
DELETE FROM pr_reviews;
DELETE FROM pr_comment;
DELETE FROM pr_checks;
DELETE FROM pr;
DELETE FROM review_run;
DELETE FROM review;
DELETE FROM session_cleanup_facts;
DELETE FROM session_worktrees;
DELETE FROM notifications;
DELETE FROM telemetry_event;
DELETE FROM model_usage_events;
DELETE FROM usage_bindings;
DELETE FROM usage_sources;
DELETE FROM sessions;
DELETE FROM workspace_repos;
DELETE FROM projects;
-- +goose StatementEnd

-- +goose Down
```

- [ ] **Step 4: Run the migration tests**

```bash
cd backend && go test ./internal/storage/sqlite/...
```

Expected: PASS, including `TestMigrationVersionsAreUnique` and the missing-migration guards.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0094_clear_pre_release_data.sql backend/internal/storage/sqlite/migrate_clear_data_test.go
git commit -m "feat(storage): clear every pre-release table except app settings"
```

### Task 10: The session manager spawns a TUI session unconditionally

**Files:**
- Modify: `internal/session_manager/manager.go:276-279, 484, 521, 613-635, 2786`
- Modify: `internal/session_manager/chat_spawn.go:234-256`
- Modify: `internal/daemon/lifecycle_wiring.go:158, 194`
- Modify: `internal/daemon/daemon.go:268`
- Modify: `internal/daemon/wiring_test.go:194, 253`
- Test: `internal/session_manager/chat_spawn_test.go`, `internal/session_manager/manager_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces: `sessionmanager.Deps` has no `Defaults` field; `sessionmanager.SessionModeDefaults` no longer exists; `startSession(ctx, cfg, runtime, store, lcm, messenger, telemetry, agents, previewLifecycle, browserLifecycle, browserCapabilities, chat, log)`; `Manager.Spawn` records `Mode: domain.SessionModeTUI` for every session and ignores `cfg.RequestedMode` (the field itself goes in Task 11).

- [ ] **Step 1: Write the failing test**

Add to `internal/session_manager/manager_test.go`, next to `TestSpawn_ResolvesProjectConfig` (line 1058), reusing its fixtures:

```go
func TestSpawnAlwaysRecordsTUIMode(t *testing.T) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: domain.ProjectConfig{
		Worker: domain.RoleOverride{Harness: domain.HarnessCodex},
	}}
	agent := &recordingAgent{}
	rt := &fakeRuntime{}
	ws := &fakeWorkspace{}
	lookPath := func(string) (string, error) { return "/bin/true", nil }
	m := New(Deps{Runtime: rt, Agents: singleAgent{agent: agent}, Workspace: ws, Store: st, Messenger: &fakeMessenger{}, Lifecycle: &fakeLCM{store: st}, LookPath: lookPath})

	rec, _, _, err := m.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", Kind: domain.KindWorker, RequestedMode: domain.SessionModeChat})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Mode != domain.SessionModeTUI {
		t.Fatalf("spawned mode = %q, want every session recorded as tui", rec.Mode)
	}
	if rt.lastCfg.Env[EnvSessionID] == "" {
		t.Fatal("a tui session must launch the terminal runtime")
	}
}
```

Task 11 deletes `RequestedMode` from `ports.SpawnConfig`; when it does, drop that argument from this test and keep the assertions.

```bash
cd backend && go test ./internal/session_manager/ -run TestSpawnAlwaysRecordsTUIMode -v
```

Expected: FAIL with `chat mode is not available in this build`, because the fixture has no chat launcher and the manager still honours the requested mode.

- [ ] **Step 2: Remove the resolution and the defaults dependency**

In `internal/session_manager/chat_spawn.go` delete lines 234-256: the `SessionModeDefaults` interface with its comment and the `resolveSessionMode` method with its comment.

In `internal/session_manager/manager.go`:
- delete the `defaults SessionModeDefaults` field and its comment (lines 276-279);
- delete `Defaults SessionModeDefaults` from `Deps` (line 484) and `defaults: d.Defaults,` (line 521);
- replace lines 613-635 (from the comment `// Resolve the controller mode here` through the closing brace of `if mode == domain.SessionModeTUI { … }`) with:

```go
	mode := domain.SessionModeTUI
	if err := m.validateRuntimePrerequisites(); err != nil {
		return domain.SessionRecord{}, 0, 0, fmt.Errorf("spawn: %w", err)
	}
```

  Keep the `mode` local only if `spawn` still reads it further down (`grep -n "mode ==" internal/session_manager/manager.go` inside the function); if nothing reads it, drop the first line. The dormant `if mode == domain.SessionModeChat` branches later in `spawn` stay as they are: unreachable but compiled, and deleted with ACP in Phase 4.
- change line 2786 in `seedRecord` to `Mode: domain.SessionModeTUI,` and delete the two comment lines above it.

- [ ] **Step 3: Rewire the daemon**

In `internal/daemon/lifecycle_wiring.go` delete the parameter `defaults sessionmanager.SessionModeDefaults,` from `startSession` (line 158) and the line `Defaults: defaults,` (line 194). In `internal/daemon/daemon.go:268` delete the `settingsSvc,` argument so the call ends `…, chatLauncher{svc: chatSvc}, log)`. In `internal/daemon/wiring_test.go` lines 194 and 253 delete one `nil` from each `startSession(...)` call so the arity matches.

- [ ] **Step 4: Delete the chat-spawn tests**

In `internal/session_manager/chat_spawn_test.go` delete every test function that passes `RequestedMode: domain.SessionModeChat` (`grep -n RequestedMode internal/session_manager/chat_spawn_test.go` lists eight sites): `TestResumeBranchlessScratchChatSession`, `TestChatSpawnRejectedBeforeDurableStateWhenUnsupported`, `TestChatSpawnWithoutLauncherIsRefusedNotDowngraded`, `TestChatSpawnStartsControllerAndNoRuntime`, `TestChatSpawnRollsBackWhenControllerFailsToStart`, `TestKillClosesTheChatControllerAndTouchesNoRuntime`, `TestRestoreResumesChatRatherThanRelaunchingATerminal`, `TestSendRoutesIntoTheChatConversation`, `TestSendRefusedForTerminatedChatSession`. If `newChatManager` or `recordingLauncher` end up unreferenced, delete them too; if the file becomes empty apart from the package clause, `git rm` it.

- [ ] **Step 5: Build, test, lint**

```bash
cd backend
go build ./...
go test ./internal/session_manager/... ./internal/daemon/...
cd .. && npm run lint
```

Expected: PASS. If golangci-lint's `unused` check names an unexported method in `chat_spawn.go` that only the deleted code called, delete that method and rerun.

- [ ] **Step 6: Commit**

```bash
git add -A backend
git commit -m "feat(session): spawn every session as the agent's terminal UI"
```

### Task 11: The session service and ports forget the requested mode

**Files:**
- Modify: `internal/ports/session.go:28-33`
- Modify: `internal/service/session/service.go:373-400, 415-419`
- Modify: `internal/service/session/delegation.go:31, 54-56, 69`
- Modify: `internal/httpd/controllers/sessions.go` (the `SessionService` interface's `SpawnOrchestrator`, the spawn handler's `ports.SpawnConfig{…}` literal at line 287, `RequestedMode: in.Mode,` at line 1338, the call at line 1501)
- Test: `internal/service/session/service_test.go:1377-1425`, `internal/service/session/delegation_test.go:14-60`, `internal/httpd/controllers/sessions_test.go:47, 154-169, 943-955, 2052`

**Interfaces:**
- Produces: `ports.SpawnConfig` without `RequestedMode`; `(*sessionsvc.Service).SpawnOrchestrator(ctx, projectID, clean)`; `sessionsvc.DelegateTaskInput` without `RequestedMode`.

- [ ] **Step 1: Update the tests first**

`internal/service/session/service_test.go`: delete `TestSpawnOrchestratorCleanPreservesPersistedMode`, `TestSpawnOrchestratorCleanHonorsExplicitReplacementMode`, `TestSpawnOrchestratorUsesExplicitModeForNewProjectOrchestrator` (lines 1377-1425). Every remaining call `svc.SpawnOrchestrator(ctx, id, clean, "")` in the file loses its fourth argument.

`internal/service/session/delegation_test.go`: in the table struct delete `mode domain.SessionMode`, in the second case delete `mode: domain.SessionModeChat,`, in the `DelegateTaskInput` literal delete `RequestedMode: tt.mode,`, and delete the assertion block:

```go
			if cmd.spawnedCfg.RequestedMode != tt.mode {
				t.Fatalf("spawn mode = %q, want %q", cmd.spawnedCfg.RequestedMode, tt.mode)
			}
```

`internal/httpd/controllers/sessions_test.go`: delete the `orchestratorMode domain.SessionMode` field (line 47); change the fake to

```go
func (f *fakeSessionService) SpawnOrchestrator(ctx context.Context, projectID domain.ProjectID, clean bool) (domain.Session, error) {
	if clean {
		active := true
		existing, err := f.List(ctx, sessionsvc.ListFilter{ProjectID: projectID, Active: &active, OrchestratorOnly: true})
		if err != nil {
			return domain.Session{}, err
		}
		for _, o := range existing {
			if _, err := f.Kill(ctx, o.ID); err != nil {
				return domain.Session{}, err
			}
		}
	}
	s, _, _, err := f.Spawn(ctx, ports.SpawnConfig{ProjectID: projectID, Kind: domain.KindOrchestrator})
	return s, err
}
```

delete `TestSessionsAPI_OrchestratorAcceptsExplicitChatMode` (lines 943-955); and in `TestSessionsAPI_DelegateTask` drop `|| svc.delegationInput.RequestedMode != domain.SessionModeChat` from the assertion at line 2052 (the request body may keep `"mode":"chat"` until Task 12).

Run:

```bash
cd backend && go test ./internal/service/session/... ./internal/httpd/controllers/ -run 'Orchestrator|Delegate' 2>&1 | head -20
```

Expected: compile errors, the signatures still carry the mode.

- [ ] **Step 2: Service**

In `internal/service/session/service.go` change `SpawnOrchestrator` to:

```go
func (s *Service) SpawnOrchestrator(
	ctx context.Context,
	projectID domain.ProjectID,
	clean bool,
) (domain.Session, error) {
	unlock := s.lockOrchestratorProject(projectID)
	defer unlock()

	project, err := s.requireProject(ctx, projectID)
	if err != nil {
		return domain.Session{}, err
	}
	if clean {
		existing, err := s.activeOrchestrators(ctx, projectID)
		if err != nil {
			return domain.Session{}, err
		}
		for _, orch := range existing {
			_ = s.sendRetireNotice(ctx, orch.ID)
			if err := s.manager.RetireForReplacement(ctx, orch.ID); err != nil {
				return domain.Session{}, toAPIError(err)
			}
		}
	} else {
```

(the `mode := requestedMode` line and the `if len(existing) > 0 && mode == ""` block with its comment are gone) and change the spawn literal at lines 415-419 to:

```go
	sess, _, _, err := s.spawn(ctx, ports.SpawnConfig{
		ProjectID: projectID,
		Kind:      domain.KindOrchestrator,
	})
```

In `internal/service/session/delegation.go` delete `RequestedMode  domain.SessionMode` from `DelegateTaskInput` (line 31), the validation

```go
	if in.RequestedMode != "" && !in.RequestedMode.Valid() {
		return DelegateTaskOutcome{}, apierr.Invalid("INVALID_SESSION_MODE", "mode must be chat or tui", nil)
	}
```

(lines 54-56), and `RequestedMode: in.RequestedMode,` (line 69).

- [ ] **Step 3: Port and controller call sites**

In `internal/ports/session.go` delete the `RequestedMode domain.SessionMode` field and its comment (lines 28-33).

In `internal/httpd/controllers/sessions.go`: change the `SpawnOrchestrator` method in the controller's `SessionService` interface to `SpawnOrchestrator(ctx context.Context, projectID domain.ProjectID, clean bool) (domain.Session, error)`; delete `RequestedMode: in.Mode,` from the `ports.SpawnConfig{…}` literal in `spawn` (line 287) and from the `sessionsvc.DelegateTaskInput{…}` literal in `delegateTask` (line 1338); change line 1501 to `sess, err := c.Svc.SpawnOrchestrator(r.Context(), in.ProjectID, in.Clean)`. Leave the `in.Mode` validation blocks in place; Task 12 removes them with the DTO fields.

```bash
cd backend && grep -rn "RequestedMode" internal | grep -v _test.go
```

Expected: no output.

- [ ] **Step 4: Build and test**

```bash
cd backend
go build ./...
go test ./internal/ports/... ./internal/service/session/... ./internal/session_manager/... ./internal/httpd/controllers/...
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A backend
git commit -m "feat(session): drop the requested session mode from spawn and delegation"
```

### Task 12: The HTTP API refuses a session mode

**Files:**
- Modify: `internal/httpd/controllers/dto.go:167-190, 621-634, 917-924`
- Modify: `internal/httpd/controllers/sessions.go:250-265, 1301-1326, 1486-1500` plus two new helpers
- Test: `internal/httpd/controllers/sessions_test.go:931-940, 957-964, 2039, 2063-2082`
- Regenerate: `internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Produces: `SpawnSessionRequest`, `DelegateTaskRequest`, `SpawnOrchestratorRequest` without `Mode`; a body carrying a `mode` key on any of the three routes is answered `400` with code `SESSION_MODE_REMOVED`; `sessionModeRequested(body []byte) bool` and `writeSessionModeRemoved(w, r)` in `sessions.go`.

- [ ] **Step 1: Rewrite the tests**

Replace `TestSessionsAPI_SpawnRejectsUnknownExplicitMode` (lines 931-940) with:

```go
func TestSessionsAPI_SpawnRejectsRemovedMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	for _, mode := range []string{`"chat"`, `"tui"`, `null`} {
		body, status, _ := doRequest(t, srv, "POST", "/api/v1/sessions",
			`{"projectId":"opr","kind":"worker","harness":"codex","prompt":"fix","mode":`+mode+`}`)
		assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_MODE_REMOVED")
	}
	if len(svc.sessions) != 1 {
		t.Fatalf("a removed-mode request created a session: %#v", svc.sessions)
	}
}
```

Replace `TestSessionsAPI_OrchestratorRejectsUnknownExplicitMode` (lines 957-964) with:

```go
func TestSessionsAPI_OrchestratorRejectsRemovedMode(t *testing.T) {
	svc := newFakeSessionService()
	srv := newSessionTestServer(t, svc)

	body, status, _ := doRequest(t, srv, "POST", "/api/v1/orchestrators",
		`{"projectId":"opr","mode":"tui"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_MODE_REMOVED")
}
```

In `TestSessionsAPI_DelegateTask` (line 2039) remove `"mode":"chat",` from the request body. In `TestSessionsAPI_DelegateTaskValidationAndServiceError` change the last case (lines 2080-2082) to:

```go
	svc.delegationErr = nil
	body, status, _ = doRequest(t, srv, "POST", "/api/v1/orchestrators/delegate", `{"projectId":"opr","brief":"Fix it","mode":"tui"}`)
	assertErrorCode(t, body, status, http.StatusBadRequest, "SESSION_MODE_REMOVED")
```

Run:

```bash
cd backend && go test ./internal/httpd/controllers/ -run 'RemovedMode|DelegateTask' -v 2>&1 | tail -20
```

Expected: FAIL with `SESSION_MODE_INVALID` or a 201/202 where `SESSION_MODE_REMOVED` is wanted.

- [ ] **Step 2: Remove the DTO fields**

In `internal/httpd/controllers/dto.go` delete the `Mode` field and its comment block from `SpawnSessionRequest` (the comment starting `// Mode picks the conversation controller` through `Mode domain.SessionMode …`), from `DelegateTaskRequest` (the comment `// Mode is omitted for the daemon-owned default…` through `Mode domain.SessionMode …`), and from `SpawnOrchestratorRequest` (the comment `// Mode applies only when…` through `Mode domain.SessionMode …`).

- [ ] **Step 3: Reject the key in the three handlers**

Add to `internal/httpd/controllers/sessions.go` (imports need `encoding/json` and `io` if not already present):

```go
func sessionModeRequested(body []byte) bool {
	var probe struct {
		Mode json.RawMessage `json:"mode"`
	}
	return json.Unmarshal(body, &probe) == nil && len(probe.Mode) > 0
}

func writeSessionModeRemoved(w http.ResponseWriter, r *http.Request) {
	envelope.WriteAPIError(w, r, http.StatusBadRequest, "validation", "SESSION_MODE_REMOVED",
		"mode is no longer accepted: every session runs the agent's terminal interface", nil)
}
```

In `spawn`, replace the decode (lines 250-254) and delete the `ParseSessionMode` block (lines 258-265):

```go
	r.Body = http.MaxBytesReader(w, r.Body, maxSpawnBodyBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	var in SpawnSessionRequest
	if err := json.Unmarshal(body, &in); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	if sessionModeRequested(body) {
		writeSessionModeRemoved(w, r)
		return
	}
```

If a later line in `spawn` declares `err` with `:=` and the compiler now reports a redeclaration, change that one to `=`.

In `delegateTask`, apply the same read-then-unmarshal replacement to the `decodeJSON(r, &in)` block (lines 1301-1305, `DelegateTaskRequest`) and delete the `if in.Mode != "" { … }` block (lines 1319-1326).

In `spawnOrchestrator`, apply the same replacement to the `decodeJSON(r, &in)` block (lines 1486-1490, `SpawnOrchestratorRequest`; this route has no `MaxBytesReader`, keep it that way) and delete the `if in.Mode != "" { … }` block (lines 1495-1500).

- [ ] **Step 4: Regenerate the contract and verify**

```bash
npm run api
cd backend && go build ./... && go test ./internal/httpd/...
cd ../frontend && npm run typecheck
git -C .. diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: tests pass, typecheck passes (Task 3 already stopped the renderer from sending `mode`), and the diff removes the `mode` property from the three request schemas and nothing else.

- [ ] **Step 5: Commit**

```bash
git add -A backend frontend/src/api/schema.ts
git commit -m "feat(api): reject a session mode on spawn, delegate and orchestrator requests"
```

### Task 13: The CLI drops `--mode`

**Files:**
- Modify: `internal/cli/spawn.go:27, 43, 86-90, 133, 180`
- Test: `internal/cli/spawn_test.go`, `internal/cli/dto_drift_e2e_test.go`

**Interfaces:**
- Produces: `opr spawn` has no `--mode` flag; `spawnRequest` mirrors `SpawnSessionRequest` without `Mode`.

- [ ] **Step 1: Write the failing test**

Add to `internal/cli/spawn_test.go`, in the style of `TestSpawnCommand_RequiresName` (line 172):

```go
func TestSpawnCommand_HasNoModeFlag(t *testing.T) {
	var out, errb bytes.Buffer
	root := NewRootCommand(Deps{Out: &out, Err: &errb})
	root.SetArgs([]string{"spawn", "--name", "w", "--mode", "tui"})
	err := root.Execute()
	if err == nil || !strings.Contains(err.Error(), "unknown flag: --mode") {
		t.Fatalf("err = %v, want unknown flag: --mode", err)
	}
}
```

```bash
cd backend && go test ./internal/cli/ -run TestSpawnCommand_HasNoModeFlag -v
```

Expected: FAIL, the flag still parses.

- [ ] **Step 2: Remove the flag**

In `internal/cli/spawn.go` delete `mode string` from `spawnOptions` (line 27), `Mode string \`json:"mode,omitempty"\`` from `spawnRequest` (line 43), the validation block with its comment (lines 86-90):

```go
			// Rejected here rather than forwarded, so a typo exits 2 as a usage
			// error instead of reaching the daemon as an unsupported mode.
			if opts.mode != "" && opts.mode != "chat" && opts.mode != "tui" {
				return usageError{fmt.Errorf(`--mode must be "chat" or "tui"`)}
			}
```

`Mode: opts.mode,` from the request literal (line 133), and the `f.StringVar(&opts.mode, "mode", …)` registration (line 180).

- [ ] **Step 3: Test the CLI package**

```bash
cd backend && go test ./internal/cli/...
```

Expected: PASS, including `dto_drift_e2e_test.go`, which compares `spawnRequest` against `controllers.SpawnSessionRequest`.

- [ ] **Step 4: Commit**

```bash
git add -A backend/internal/cli
git commit -m "feat(cli): remove the spawn --mode flag"
```

### Task 14: Settings lose the default session interface

**Files:**
- Modify: `internal/httpd/controllers/dto.go:1811-1837`
- Modify: `internal/httpd/controllers/settings.go:20, 26, 40, 60-84, 209-226`
- Modify: `internal/httpd/apispec/specgen/build.go:550-560` (and any `schemaNames` entry naming `UpdateSessionInterfaceRequest`)
- Modify: `internal/service/settings/service.go:23, 46, 57, 66-84, 97-115, 173-184, 202`
- Modify: `internal/daemon/settings_wiring.go:27, 40-45` and the `settingssvc.New(...)` call in `internal/daemon/daemon.go`
- Modify: `internal/storage/sqlite/store/app_settings_store.go:22-26, 63, 83-97`
- Modify: `internal/storage/sqlite/queries/app_settings.sql:9-10`
- Delete: `e2e/chat_mode_test.go`
- Modify: `e2e/harness_test.go:180-183`
- Test: `internal/httpd/controllers/settings_test.go`, `internal/service/settings/service_test.go`, `internal/storage/sqlite/store/app_settings_store_test.go`
- Regenerate: `internal/storage/sqlite/gen/*` via `npm run sqlc`; `openapi.yaml` and `schema.ts` via `npm run api`

**Interfaces:**
- Produces: `SettingsResponse` without `defaultSessionMode` and `chatHarnesses`; no `PATCH /api/v1/settings/session-interface`; `settingssvc.New(store Store, now func() time.Time)`; `settingssvc.Snapshot`, `Record`, `Store` without the default mode; the store has no `SetDefaultSessionMode`. The `default_session_mode` column stays in the schema until Phase 4 and is simply unread.

- [ ] **Step 1: Update the controller tests first**

In `internal/httpd/controllers/settings_test.go`: delete `gotMode domain.SessionMode` and the `harnesses` field from `fakeSettingsService`, the `SetDefaultSessionMode` and `ChatHarnesses` methods (lines 37-44), the `harnesses: …` argument from every `&fakeSettingsService{…}` literal, the `DefaultSessionMode`/`ChatHarnesses` fields from the response struct in `TestSettingsAPIGetReturnsFullPreferenceSet` (lines 111-113) and its assertion at line 137 (keep the rest of that assertion), and the whole `TestSettingsAPISessionInterfaceUnchanged` (lines 288-306). Rewrite `TestSettingsAPIGetStillServesWhenOnlySessionFieldsSet` (line 309) so its snapshot is `settingssvc.Snapshot{}` and rename it `TestSettingsAPIGetStillServesAnEmptySnapshot`. If the NOT_IMPLEMENTED loop near line 270 lists `PATCH /api/v1/settings/session-interface`, drop that entry.

```bash
cd backend && go test ./internal/httpd/controllers/ -run Settings 2>&1 | head
```

Expected: compile errors, the fake no longer satisfies `SettingsService`.

- [ ] **Step 2: Controller and DTO**

`dto.go`: delete the `DefaultSessionMode` and `ChatHarnesses` fields with their comments from `SettingsResponse` (lines 1813-1818) and the whole `UpdateSessionInterfaceRequest` type with its comment (lines 1834-1837).

`settings.go`: delete `SetDefaultSessionMode(...)` (line 20) and `ChatHarnesses(...)` (line 26) from `SettingsService`; delete the route `r.Patch("/settings/session-interface", c.setSessionInterface)` (line 40); delete the `setSessionInterface` handler (lines 60-84); rewrite `response`:

```go
func (c *SettingsController) response(snapshot settingssvc.Snapshot) SettingsResponse {
	return SettingsResponse{
		UI:                      UiSettings{Locale: snapshot.UILocale},
		Updates:                 snapshot.Updates,
		Keybindings:             snapshot.Keybindings,
		Migration:               wireMigrationState(snapshot.Migration),
		LegacyDesktopImportedAt: snapshot.LegacyDesktopImportedAt,
	}
}
```

`build.go`: delete the `updateSessionInterface` operation (lines 550-560). Then `grep -n "SessionInterface" internal/httpd/apispec/specgen/build.go` and delete any remaining `schemaNames` line for `UpdateSessionInterfaceRequest`.

- [ ] **Step 3: Service**

In `internal/service/settings/service.go`: delete `DefaultSessionMode domain.SessionMode` from `Record` (line 23) and from `Snapshot` (line 57); delete `SetDefaultSessionMode(...)` from `Store` (line 46); delete the `ChatCapability` interface with its comment (lines 66-71); change the struct and constructor to

```go
type Service struct {
	store Store
	now   func() time.Time
}

func New(store Store, now func() time.Time) *Service {
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	return &Service{store: store, now: now}
}
```

delete `DefaultSessionMode` and `SetDefaultSessionMode` (lines 97-115) and `ChatHarnesses` (lines 173-184); delete `DefaultSessionMode: domain.NormalizeSessionMode(record.DefaultSessionMode),` from `snapshotFromRecord` (line 202). If `domain` or `ports` is no longer imported by anything in the file, remove the import.

Update the tests in `internal/service/settings/service_test.go`: delete `fakeStore.SetDefaultSessionMode` (lines 29-38), `DefaultSessionMode: domain.SessionModeTUI,` in `TestGetNormalizesPersistedDesktopPreferences` (line 165), the whole `TestSetDefaultSessionModePersistsAndReturnsSnapshot` and `TestDefaultSessionModeFallsBackWhenStoreFails` (lines 201-224), and the two assertion lines on `snapshot.DefaultSessionMode` in `TestFacetUpdatesPreserveUnrelatedFields` (lines 549-551). The helper at `service_test.go:158` calls `New(store, nil, func() time.Time {…})`; delete the `nil` so it reads `New(store, func() time.Time {…})`, and do the same for any other `New(` call in the file.

- [ ] **Step 4: Wiring and store**

`internal/daemon/settings_wiring.go`: delete `DefaultSessionMode: row.DefaultSessionMode,` (line 27) and the `SetDefaultSessionMode` adapter method (lines 40-45). In `internal/daemon/daemon.go` the multi-line `settingssvc.New(` call at line 202 passes the store, a chat capability and a clock; delete the chat-capability argument so it matches `New(store, now)`.

`internal/storage/sqlite/queries/app_settings.sql`: delete lines 9-10:

```sql
-- name: SetDefaultSessionMode :exec
UPDATE app_settings SET default_session_mode = ?, updated_at = ? WHERE id = 1;
```

Regenerate: `npm run sqlc` from the repo root.

`internal/storage/sqlite/store/app_settings_store.go`: delete `DefaultSessionMode domain.SessionMode` from `Record` with its comment (lines 22-26), the `DefaultSessionMode: domain.NormalizeSessionMode(row.DefaultSessionMode),` mapping (line 63), and the `SetDefaultSessionMode` method (lines 83-97).

`internal/storage/sqlite/store/app_settings_store_test.go`: delete the `row.DefaultSessionMode` assertions (lines 26-27, 81-82), the `s.SetDefaultSessionMode(...)` write (line 60), and the `SetDefaultSessionMode` entry in the mutation list (line 187).

- [ ] **Step 5: e2e**

```bash
cd backend && git rm e2e/chat_mode_test.go
```

In `e2e/harness_test.go` replace the settings struct in `waitReady` (lines 180-183) with `var settings map[string]any`.

- [ ] **Step 6: Regenerate the contract, build, test**

```bash
npm run api
cd backend
go build ./...
go test ./internal/httpd/... ./internal/service/settings/... ./internal/storage/sqlite/... ./internal/daemon/...
go vet ./e2e/...
cd ../frontend && npm run typecheck
```

Expected: PASS. The `openapi.yaml` diff removes `defaultSessionMode`, `chatHarnesses`, `UpdateSessionInterfaceRequest` and the `/api/v1/settings/session-interface` path.

- [ ] **Step 7: Commit**

```bash
git add -A backend frontend/src/api/schema.ts
git commit -m "feat(settings): remove the default session interface preference"
```

### Task 15: Remove the interface-transition routes

**Files:**
- Delete: `internal/httpd/controllers/sessions_interface_transition.go`
- Modify: `internal/httpd/controllers/sessions.go:195-197`
- Modify: `internal/httpd/controllers/dto.go:524-569`
- Modify: `internal/httpd/apispec/specgen/build.go:243-247, 1683-1719`
- Regenerate: `openapi.yaml`, `schema.ts`

**Interfaces:**
- Produces: no `/api/v1/sessions/{sessionId}/interface-transition` route in the router or the spec. `session_manager/interface_transition.go` and `service/session`'s transition methods stay (dormant, Phase 4).

- [ ] **Step 1: Delete the handler file and routes**

```bash
cd backend && git rm internal/httpd/controllers/sessions_interface_transition.go
```

In `internal/httpd/controllers/sessions.go` delete lines 195-197:

```go
	r.Get("/sessions/{sessionId}/interface-transition", c.interfaceTransitionStatus)
	r.Post("/sessions/{sessionId}/interface-transition", c.startInterfaceTransition)
	r.Delete("/sessions/{sessionId}/interface-transition", c.cancelInterfaceTransition)
```

- [ ] **Step 2: Delete the DTOs and spec entries**

In `dto.go` delete `StartSessionInterfaceTransitionRequest`, `SessionInterfaceTransitionView`, `SessionInterfaceTransitionStatusResponse`, `StartSessionInterfaceTransitionResponse`, `CancelSessionInterfaceTransitionResponse` with their comments (lines 524-569).

In `build.go` delete the five `schemaNames` lines 243-247 and the three operation entries at lines 1683-1719 (`getSessionInterfaceTransition`, `startSessionInterfaceTransition`, `cancelSessionInterfaceTransition`).

- [ ] **Step 3: Regenerate, build, test**

```bash
npm run api
cd backend
go build ./...
go test ./internal/httpd/...
grep -rn "interface-transition" internal/httpd
cd ../frontend && npm run typecheck
```

Expected: PASS; the grep prints nothing; the `openapi.yaml` diff removes the path and the five schemas.

- [ ] **Step 4: Run the whole backend suite**

```bash
cd backend && go test ./... && cd .. && npm run lint
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A backend frontend/src/api/schema.ts
git commit -m "feat(api): remove the session interface-transition routes"
```

### Task 16: Docs

**Files:**
- Modify: `docs/STATUS.md:43-48, 177-186, 227`
- Modify: `docs/architecture.md:316-377`
- Modify: `docs/superpowers/specs/2026-09-04-single-session-interface-design.md` (the `CreateSessionRequest.Mode` citation in Phase 1)

- [ ] **Step 1: STATUS.md**

Replace the bullet at lines 43-48 ("One daemon-committed interface per session…") with:

```markdown
- One session kind. Every session runs the agent's own terminal UI in the
  pty-host runtime; there is no chat controller to choose and no interface
  handoff. The ACP/chat subsystem is still in the tree but unreachable, and is
  deleted in Phase 4 of `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`.
```

Replace the three mobile bullets at lines 177-186 ("New mobile workers…", "Session routing uses…", "Mobile exposes the same capability-gated…") with:

```markdown
- Mobile spawns a terminal session with no interface choice and routes every
  session to the terminal screen, which opens in the blocks view for a covered
  harness and can be toggled to the raw terminal per session, remembered on the
  device.
```

Check line 227 ("Cross-interface visual history import") and delete the bullet if it describes the TUI↔Chat handoff.

- [ ] **Step 2: architecture.md**

Replace the "Session Interface Handoff" section (heading at line 316 through the end of its mermaid diagram and prose, up to the `### Observation Flow` heading at line 378) with:

```markdown
### Session Interface Handoff

Removed on 2026-09-04. Every session runs the agent's terminal UI and there is
no second controller to hand off to. The coordinator in
`session_manager/interface_transition.go` and its tables are unreachable and are
deleted in Phase 4 of
`docs/superpowers/specs/2026-09-04-single-session-interface-design.md`.
```

Update the table of contents entry if it lists the section's subsections.

- [ ] **Step 3: Fix the spec citation**

In the spec's Phase 1 backend list, change `CreateSessionRequest.Mode` to `SpawnSessionRequest.Mode`, and change "A request carrying `mode` is rejected" to name all three routes: `POST /sessions`, `POST /orchestrators`, `POST /orchestrators/delegate`.

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs: record the collapse to one session kind"
```

---

## Final verification

Run from the repo root after Task 16:

```bash
cd backend && go build ./... && go test ./... && go vet ./... && cd ..
npm run lint
cd frontend && npm run typecheck && npm run typecheck:e2e && npm run lint && npx vitest run && npm run check:desktop-parity && cd ..
cd packages/mobile && flutter analyze && flutter test && cd ../..
git diff --stat master... -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

All green, and the generated files differ from `master` only by the removed `mode` properties, the removed settings fields and path, and the removed interface-transition path and schemas.
