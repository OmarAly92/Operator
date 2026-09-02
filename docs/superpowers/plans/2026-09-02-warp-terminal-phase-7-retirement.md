# Warp Terminal Phase 7 — Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a session exactly one terminal plus chat, give that terminal the mouse and IME support xterm used to provide, and then delete xterm from the tree.

**Architecture:** Four movements, ordered so every irreversible step comes after the thing that replaces it is proven. First the in-session shell tab strip goes, frontend then backend, which is what "one session has exactly one terminal surface" actually means. Then the input path closes its three real gaps — mouse click and drag reporting, focus reporting, and IME composition — none of which xterm was supplying in the shipped default, and all of which are gated on modes the program sets rather than on the alternate screen. Only then do `XtermTerminal.tsx` and the seven `@xterm/*` dependencies go.

**Tech Stack:** Rust (`vt-core`), TypeScript (`ts/core`, `ts/react`, `ts/editor`), React 19, Go (`shellterm` service), SQLite, vitest, `go test`.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §11 (alt screen and wheel reporting), §13.3 (the renderer's job), §13.4 (retirement, and its ordering), §14 Phase 7, §15 items 12 and 18.

**Warp reference:** `/Users/omaraly/development/AI/warp`, read-only. §0.2 binds you: every citation below was verified on 2026-09-02 and is checkable. If one does not say what this plan says it says, report it rather than planning around it.

---

## Global Constraints

- **No comments in code.** The user's global rule. This applies to every file you touch, including tests. Explanatory prose belongs in this plan and in the spec, not in the source.
- **No source file in `packages/terminal` over 600 lines.** `packages/terminal/scripts/check-boundaries.mjs:42` sets `LINE_LIMIT = 600` and fails CI. `TerminalSurface.tsx` is 335 lines today and this plan adds to it; Task 5 extracts rather than grows past the cap.
- **The package must not import from `frontend/`, `backend/`, or `packages/shared/`.** `frontend/` imports the package by name only (`@operator/terminal-react`), never by relative path. §4.2.
- **Cubit-style layering does not apply here** — that is the mobile package. This plan touches `frontend/src/renderer` and `backend/internal` only.
- **Every task ends green on:**
  ```bash
  npm --prefix packages/terminal test
  npm --prefix packages/terminal run check:boundaries
  npm --prefix frontend test
  ```
  Backend tasks additionally: `cd backend && go test ./...`
- **`npm --prefix packages/terminal run bench:gate` is RED before you start** and is expected to stay red. `input-latency` fails at p95 24.80ms against a 9.00ms xterm baseline; spec §9.5 carries this as an open decision that is explicitly not this phase's to resolve. **Do not "fix" it and do not loosen the factor.** If a number moves, record it in your task report.
- **This project is pre-release with no users.** Breaking API changes, schema changes and data resets are all acceptable and need no migration path. Optimize every judgment call for the cleanest end state and the most stable behaviour, not for continuity.
- **`packages/terminal/bench/adapters/xterm.ts` is NEVER deleted**, in this phase or any other. The §9.4 gate is defined against recorded xterm baselines. Task 8 deletes `@xterm/*` from `frontend/package.json` only — the copies in `packages/terminal/package.json` devDependencies stay, because the bench adapter needs them.

---

## Scope decisions settled with the user before this plan was written

Recorded so no executor reopens them.

**1. The deletion target is the in-session shell tab strip, not the standalone `/terminals` screen.** §13.4 opens with *"one session has exactly one terminal surface"*, which is about shells appearing beside the agent pane inside a session (`SessionView.tsx:126-131`). The standalone screen is a different surface with its own UX justification, stated in `ShellTerminalsView.tsx:16-22`: *"the session view cannot be the only home for shells — it is unreachable in a project with no sessions, which is exactly when a user most wants a plain terminal."* Deleting it would be a UX regression. It stays.

**2. There is no history migration, because session-scoped shells are the only thing that would need one.** §13.4.1 requires that retiring the tabs must not delete or session-key the durable-block bridge. Removing session scoping satisfies that by construction: `shellterm`, `terminalcapture`, `terminal_blocks`, migration `0092` and `GET /api/v1/shell-terminals/{handleId}/blocks` are all untouched and keep serving standalone shells. **Verified before planning:** `backend/internal/daemon/shellterm_wiring.go:57` is the only `Adopt` call site, so agent session panes have never had durable capture at all and there is nothing to move.

**3. `ShellTerminalTab.tsx` and `useShellTerminals.ts` are NOT deleted.** §17.5 lists them as phase 7 artefacts, written before they were shared. `ShellTerminalsView.tsx:13` imports `ShellTerminalTab`, and `ShellTerminalsView.tsx:6` imports `useShellTerminals`. Both serve the surviving standalone screen. Deleting them breaks it.

**5. Five corrections came from a second Warp read on 2026-09-02, after the first draft of this plan.** They are folded into the tasks below; this list is so a reviewer can check them against Warp directly. §0.2 applies — every citation was verified.

| # | What the first draft got wrong | Warp's answer |
| --- | --- | --- |
| a | Mouse reporting gated on `altActive` only | `should_intercept_mouse` gates on `is_alt_screen_active() **\|\|** MOUSE_REPORT_CLICK \|\| MOUSE_DRAG \|\| MOUSE_MOTION` (`app/src/terminal/alt_screen/mod.rs:18-21`), with the comment *"Require some level of mouse tracking to be enabled when the block list is active."* Reporting is not alt-screen-only. **This is the serious one** — post-tmux an agent pane is in the normal buffer (§0.7), so an alt-only gate reports nothing in the pane the user watches all day. Task 5. |
| b | No shift override | `should_intercept_mouse(model, shift, ctx)` returns early — local handling, not the program — when shift is held (`:14-16`). Shift is the universal terminal escape hatch for selecting text out of a program that grabbed the mouse. Task 5. |
| c | No modifier bits in the SGR report | Warp has none either: `MouseState` carries `modifiers` (`model/mouse.rs:25,54`) and `to_escape_sequence` never reads them (`model/escape_sequences.rs:327-364`). **We deviate and do it properly** — shift 4, alt 8, ctrl 16 — because without it `ctrl+click` in a TUI is indistinguishable from a plain click. Task 5. |
| d | Focus reporting absent entirely | `?1004` is `TermMode::FOCUS_IN_OUT` (`model/mode.rs:21`, set at `grid/ansi_handler.rs:1015`), reported as `ESC [ I` / `ESC [ O` (`escape_sequences.rs:190-191`) behind `should_report_focus` (`app/src/terminal/view.rs:8374-8380`). `vt-core` does not parse 1004 at all. New Task 6. |
| e | IME only wired into the passthrough path | Warp shows marked text inline while composing (`set_marked_text(text, selected_range)`, `app/src/editor/view/mod.rs:8234`) and commits an incomplete composition when focus is lost (`maybe_commit_incomplete_ime_text`, `:8214-8232`). Task 7 covers the owned line editor too and records inline preedit as an explicit deferral. |

Warp also exposes all three as user settings — `terminal.mouse_reporting_enabled`, `terminal.scroll_reporting_enabled`, `terminal.focus_reporting_enabled`, all defaulting true (`app/src/terminal/alt_screen_reporting.rs:5-33`). **We do not add settings in this phase.** A settings surface is deferred phase 6 work; hard-coding "always report when the program asks" is the correct default and is what every terminal without a preferences pane does. Do not invent a toggle.

**4. Click/drag mouse reporting and IME are live product gaps, not deletion prerequisites.** `XtermTerminal.tsx:309` `HeadlessTerminalAttachment` returns `null` with `onUserInput: () => disposable` — a dead disposable — and `useTerminalSession.ts:601` subscribes to it. In the shipped default path xterm renders nothing and receives no input. So the pane cannot be clicked in **today**, and deleting xterm does not cause that. Fixing it is worth doing on its own merits; it is in this plan because it must land before Task 8, not because Task 8 creates it.

---

## File Structure

**Task 1–2, the session shell tabs.**

| File | Responsibility after this plan |
| --- | --- |
| `frontend/src/renderer/components/SessionView.tsx` | Modify. Drops all shell-terminal state, callbacks and props. Renders the agent terminal and chat only. |
| `frontend/src/renderer/components/TerminalPane.tsx` | Modify. Drops the shell-tab branch and the `shellTerminals` prop; keeps the agent-pane path and the standalone-screen path it also serves. |
| `frontend/src/renderer/routes/_shell.tsx` | Modify. `⌘T` inside a session now navigates to `/terminals` like everywhere else, instead of joining the session tab strip. |
| `backend/internal/service/shellterm/service.go` | Modify. `OpenShellTerminalInput.SessionID`, the session gate, `BeginSessionTeardown` and the `SessionWorkspace` locator go. |
| `backend/internal/service/shellterm/types.go` | Modify. `SessionID` leaves `ShellTerminal` and `OpenShellTerminalInput`. |

**Task 3–5, mouse reporting.**

| File | Responsibility |
| --- | --- |
| `packages/terminal/crates/vt-core/src/parser.rs` | Modify. `mouse_tracking` stays a `u8` bitfield internally; a new accessor exposes the level rather than collapsing it to a bool. |
| `packages/terminal/crates/vt-core/src/lib.rs` | Modify. Re-export the level accessor. |
| `packages/terminal/crates/vt-wasm/src/lib.rs` | Modify. Publish the level on the snapshot. |
| `packages/terminal/ts/core/src/types.ts` | Modify. `mouseTrackingLevel` joins the snapshot type. |
| `packages/terminal/ts/core/src/terminal-core.ts` | Modify. Read it through. |
| `packages/terminal/ts/react/src/mouse-report.ts` | **Create.** Pure SGR encoder. No DOM, no React — takes a described event and returns bytes or `null`. |
| `packages/terminal/ts/react/src/mouse-report.test.ts` | **Create.** |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | Modify. Wires pointer events through the encoder. Stays under 600 lines because the encoder is its own file. |

**Task 6, IME.**

| File | Responsibility |
| --- | --- |
| `packages/terminal/ts/react/src/composition-target.ts` | **Create.** A focusable, visually-hidden `<textarea>` that owns composition and is the focus target for both the owned and passthrough paths. |
| `packages/terminal/ts/react/src/composition-target.test.ts` | **Create.** |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | Modify. Mounts the target, routes `compositionend` to `onSendRaw`, suppresses the keydown path while composing. |

**Task 7–8, the deletion.**

| File | Responsibility |
| --- | --- |
| `frontend/src/renderer/components/XtermTerminal.tsx` + test | **Delete** (1,117 lines). |
| `frontend/src/renderer/theme/bridge/xterm-theme.ts` + test | **Delete.** `skinToTerminalTheme` maps directly instead. |
| `frontend/src/renderer/components/TerminalPane.tsx` | Modify. `usesXtermSurface`, the `headless` prop and the xterm mount go. |
| `frontend/src/renderer/components/BlockTerminal.tsx` | Modify. `handsAltScreenToXterm` and `handOffAltScreen` go. |
| `frontend/src/renderer/main.tsx` | Modify. Drop the xterm CSS import. |
| `frontend/package.json` | Modify. Drop seven `@xterm/*` entries. |

---

## Task 1: Remove the in-session shell tab strip (frontend)

**Files:**
- Modify: `frontend/src/renderer/components/SessionView.tsx:126-262, 505-520`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx`
- Modify: `frontend/src/renderer/routes/_shell.tsx:607-620`
- Test: `frontend/src/renderer/components/SessionView.test.tsx`
- Test: `frontend/src/renderer/test/shell-new-session-shortcut.test.tsx`

**Interfaces:**
- Consumes: nothing from earlier tasks; this is the first.
- Produces: `SessionView` renders with no shell-terminal props. `TerminalPane` no longer accepts `shellTerminals`, `onCloseShellTerminal`, `onRenameShellTerminal`. Task 2 relies on nothing in the frontend still sending `sessionId` to `POST /api/v1/shell-terminals`.

- [ ] **Step 1: Write the failing test**

Add to `frontend/src/renderer/components/SessionView.test.tsx`. The existing file already mocks `../hooks/useShellTerminals` at line 271 — change that mock to return a shell that *is* scoped to the session under test, and assert it does not render.

```tsx
vi.mock("../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [
			{
				handleId: "shell-in-session",
				sessionId: "session-1",
				workingDir: "/tmp",
				title: "shell",
				createdAt: new Date().toISOString(),
				durableBlocks: true,
			},
		],
		isSuccess: true,
	}),
	useOpenShellTerminal: () => ({ mutate: vi.fn() }),
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
	shellTerminalsQueryKey: ["shell-terminals"],
}));

it("renders no shell tab for a session-scoped shell", async () => {
	renderSessionView({ sessionId: "session-1" });
	expect(await screen.findByTestId("terminal-pane")).toBeInTheDocument();
	expect(screen.queryByRole("tab", { name: /shell/i })).not.toBeInTheDocument();
});
```

Use whatever `renderSessionView` helper the file already defines; do not add a second one.

- [ ] **Step 2: Run it to verify it fails**

```bash
npm --prefix frontend test -- SessionView.test.tsx
```
Expected: FAIL — the shell tab renders.

- [ ] **Step 3: Strip the shell-terminal wiring from `SessionView.tsx`**

Delete, in `SessionView.tsx`:
- the `useShellTerminals` / `useOpenShellTerminal` / `useCloseShellTerminal` / `useRenameShellTerminal` imports (lines 23-24 and their sibling import members)
- `allShellTerminals`, `shellTerminals`, `openShellTerminal`, `closeShellTerminal`, `renameShellTerminal` (lines 127-134)
- `renameShellTerminalByHandle` (139-141), the open effect (148-163), the select callback (167-178), `closeShellTerminalByHandle` (181-212), the active-shell effect (233-250) and the stale-handle effect (258-262)
- `activeShellTerminalHandleId` / `setActiveShellTerminal` reads if nothing else uses them after the above; keep them if the reviewer-terminal path still does
- the `shellTerminals`, `onCloseShellTerminal`, `onRenameShellTerminal` props passed at 510-518

- [ ] **Step 4: Strip the matching props from `TerminalPane.tsx`**

Remove the `shellTerminals`, `onCloseShellTerminal` and `onRenameShellTerminal` props from `TerminalPane`'s prop type and body, and delete the tab-strip JSX they feed. **Keep** `useShellTerminals()` at line 322 and `shellTerminalsQueryKey` — `TerminalPane` also renders for the standalone `/terminals` screen, which still needs them.

Run `npx tsc --noEmit -p frontend/tsconfig.json` and let the type errors drive you to every call site.

- [ ] **Step 5: Make `⌘T` always go to `/terminals`**

In `frontend/src/renderer/routes/_shell.tsx`, the open effect at 607-620 currently passes `sessionId: routeParams.sessionId` and only navigates when there is no session. Both halves go:

```tsx
		openShellTerminal.mutate(
			{ projectId: scopedProjectId },
			{
				onSuccess: (shell) => {
					setActiveShellTerminal(shell.handleId);
					void navigate({ to: "/terminals" });
				},
			},
		);
	}, [newShellTerminalNonce, openShellTerminal, scopedProjectId, navigate, setActiveShellTerminal]);
```

Update the comment block above it — it currently describes the in-session behaviour you just removed. Per the global rule the replacement is no comment at all; delete lines 591-597 rather than rewriting them.

- [ ] **Step 6: Run the tests**

```bash
npm --prefix frontend test
```
Expected: PASS. `shell-new-session-shortcut.test.tsx` asserts the shortcut's behaviour — if it asserted the in-session path, update it to assert navigation to `/terminals`.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/components/SessionView.tsx \
        frontend/src/renderer/components/SessionView.test.tsx \
        frontend/src/renderer/components/TerminalPane.tsx \
        frontend/src/renderer/routes/_shell.tsx \
        frontend/src/renderer/test/shell-new-session-shortcut.test.tsx
git commit -m "feat(session)!: one session is one terminal plus chat

The shell tab strip beside the agent pane goes, along with the session
scoping that fed it. Cmd+T opens a shell on the standalone terminals
screen from everywhere, including inside a session."
```

---

## Task 2: Remove session scoping from the shell-terminal service (backend)

**Files:**
- Modify: `backend/internal/service/shellterm/types.go:26-45`
- Modify: `backend/internal/service/shellterm/service.go:40-49, 83-92, 131-232, 251-270, 343-360, 530-545`
- Modify: `backend/internal/daemon/shellterm_wiring.go:26-45, 110-135`
- Modify: `backend/internal/httpd/controllers/shell_terminals.go`
- Modify: `backend/internal/storage/sqlite/queries/shell_terminals.sql`
- Test: `backend/internal/service/shellterm/service_test.go`

**Interfaces:**
- Consumes: Task 1's guarantee that no frontend caller sends `sessionId`.
- Produces: `OpenShellTerminalInput{ProjectID}` — one field. `ShellTerminal` with no `SessionID`. `shellterm.Service` with no `BeginSessionTeardown` and no `SessionWorkspaceLocator` dependency, so `NewService` loses one parameter.

**Why this is a separate task from Task 1:** it is the irreversible half. Task 1 alone makes the UX correct and is a pure frontend revert if anything is wrong. Do not fold them together.

- [ ] **Step 1: Write the failing test**

In `backend/internal/service/shellterm/service_test.go`:

```go
func TestOpenShellTerminalHasNoSessionScope(t *testing.T) {
	svc, _ := newTestService(t)
	got, err := svc.Open(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	if got.HandleID == "" {
		t.Fatal("Open() returned an empty handle id")
	}
	if reflect.TypeOf(OpenShellTerminalInput{}).NumField() != 1 {
		t.Fatalf("OpenShellTerminalInput has %d fields, want 1 (ProjectID)",
			reflect.TypeOf(OpenShellTerminalInput{}).NumField())
	}
}
```

Use whatever constructor the existing tests use in place of `newTestService`; do not invent a second harness.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd backend && go test ./internal/service/shellterm/ -run TestOpenShellTerminalHasNoSessionScope -v
```
Expected: FAIL — `NumField()` is 2.

- [ ] **Step 3: Remove the field and everything it gates**

In `types.go`: drop `SessionID` from both `ShellTerminal` and `OpenShellTerminalInput`, and delete the sentence about session scoping from the `OpenShellTerminalInput` doc comment.

In `service.go`, delete:
- the `SessionWorkspaceLocator` interface member at :49 and the `sessions` field it backs
- `sessionGate`, `gates`, `onSessionGateWait`, `sessionGateFor`, `acquireSessionGate` (:83-92, :131, :178-191)
- the `if in.SessionID != ""` branch at :212-231, including the `SessionWorkspace` resolution and gate acquisition
- `SessionID: in.SessionID` at :270
- the `if rec.SessionID != ""` gate at :359-360
- `BeginSessionTeardown` (:530-545) and `SelectShellTerminalsBySessionID` from the store interface

**Leave `SessionID: domain.SessionID(handleID)` at :255 alone.** The comment at :251 says why: that is the runtime adapter's name for the PTY, not a session reference. Removing it renames every shell terminal's pty-host handle.

In `queries/shell_terminals.sql`: delete the `SelectShellTerminalsBySessionID` query and drop `session_id` from the remaining ones. Add a migration that drops the column:

```sql
-- Migration 0093: shell terminals are no longer session-scoped.
-- +goose Up
-- +goose StatementBegin
ALTER TABLE shell_terminals DROP COLUMN session_id;
-- +goose StatementEnd
```

Number it one above the highest existing migration — check `ls backend/internal/storage/sqlite/migrations/ | tail -1` first, do not assume 0093 is free.

Regenerate sqlc: `cd backend && sqlc generate` (or the repo's documented equivalent — check `AGENTS.md`).

In `shellterm_wiring.go`: delete `sessionWorkspaceLocator` entirely (:110-135) and the `sessions` parameter of `startShellTerminals`, then fix the call site in `daemon.go`.

- [ ] **Step 4: Find every remaining caller**

```bash
cd backend && go build ./... 2>&1 | head -40
```
Work the compiler errors to zero. Expect hits in `httpd/controllers/shell_terminals.go` (the DTO), `httpd/apispec/openapi.yaml` (the schema), and the session teardown path that called `BeginSessionTeardown`.

- [ ] **Step 5: Run the tests**

```bash
cd backend && go test ./... 2>&1 | tail -30
```
Expected: PASS. Delete tests that exercised only the session-scoped path rather than rewriting them to assert nothing.

- [ ] **Step 6: Commit**

```bash
git add backend/ 
git commit -m "refactor(shellterm)!: drop session scoping

Shell terminals are standalone again. The session gate, the workspace
locator, BeginSessionTeardown and the session_id column go with the
tab strip that was their only consumer. Standalone shells, durable
blocks and the capture supervisor are untouched."
```

---

## Task 3: `vt-core` exposes the mouse tracking level, not a bool

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:120-160`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:205-215`
- Test: `packages/terminal/crates/vt-core/src/parser.rs` (inline `#[cfg(test)]`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Parser::mouse_tracking_level() -> u8` and `TerminalCore::mouse_tracking_level() -> u8`, returning a bitfield where `0b001` = mode 1000 (click), `0b010` = mode 1002 (drag), `0b100` = mode 1003 (any motion). `mouse_tracking() -> bool` stays, defined as `level != 0`, because Task 5's wheel path still uses it.

**Why:** `parser.rs:128` collapses the level to a bool. That is enough for the wheel, which reports the same way at every level, but click and drag do not: mode 1000 reports press and release only, 1002 adds motion while a button is held, 1003 adds motion with no button. Reporting drags to a program that only asked for 1000 is a protocol violation. Warp keeps the three as separate mode bits — `crates/warp_terminal/src/model/mode.rs:13,16,22` defines `MOUSE_REPORT_CLICK`, `MOUSE_MOTION` and `MOUSE_DRAG` — and tests them separately at `app/src/terminal/alt_screen/mod.rs:19-21`.

- [ ] **Step 1: Write the failing test**

Append to the `#[cfg(test)] mod tests` block in `parser.rs`:

```rust
    #[test]
    fn mouse_tracking_level_distinguishes_the_three_modes() {
        let mut p = Parser::new();
        assert_eq!(p.mouse_tracking_level(), 0);
        p.feed(b"\x1b[?1000h");
        assert_eq!(p.mouse_tracking_level(), 0b001);
        p.feed(b"\x1b[?1002h");
        assert_eq!(p.mouse_tracking_level(), 0b011);
        p.feed(b"\x1b[?1003h");
        assert_eq!(p.mouse_tracking_level(), 0b111);
        p.feed(b"\x1b[?1002l");
        assert_eq!(p.mouse_tracking_level(), 0b101);
        assert!(p.mouse_tracking());
        p.feed(b"\x1b[?1000l");
        p.feed(b"\x1b[?1003l");
        assert_eq!(p.mouse_tracking_level(), 0);
        assert!(!p.mouse_tracking());
    }
```

If `Parser::feed` is named differently, match the name the other tests in the file use.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && cargo test -p vt-core mouse_tracking_level
```
Expected: FAIL — `no method named mouse_tracking_level`.

- [ ] **Step 3: Add the accessor**

In `parser.rs`, beside the existing `mouse_tracking`:

```rust
    pub fn mouse_tracking_level(&self) -> u8 {
        self.mouse_tracking
    }
```

In `lib.rs`, beside the existing delegate at :213:

```rust
    pub fn mouse_tracking_level(&self) -> u8 {
        self.parser.mouse_tracking_level()
    }
```

The bit assignments at `parser.rs:149-151` already match the test; do not change them.

- [ ] **Step 4: Run the tests**

```bash
cd packages/terminal && cargo test -p vt-core
```
Expected: PASS, whole crate.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core/src/parser.rs packages/terminal/crates/vt-core/src/lib.rs
git commit -m "feat(vt-core): expose the mouse tracking level, not just a bool"
```

---

## Task 4: Publish the tracking level on the snapshot

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/types.ts:41-` (the snapshot type, near `sgrMouse`/`mouseTracking`)
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:138`
- Test: `packages/terminal/ts/core/src/terminal-core.test.ts`

**Interfaces:**
- Consumes: `TerminalCore::mouse_tracking_level()` from Task 3.
- Produces: `TerminalSnapshot.mouseTrackingLevel: number`, alongside the existing `sgrMouse: boolean` and `mouseTracking: boolean`. Task 5 reads it.

- [ ] **Step 1: Write the failing test**

In `packages/terminal/ts/core/src/terminal-core.test.ts`:

```ts
it("publishes the mouse tracking level on the snapshot", async () => {
	const core = await createTestCore();
	expect(core.snapshot().mouseTrackingLevel).toBe(0);
	core.feed(new TextEncoder().encode("\x1b[?1002h"));
	expect(core.snapshot().mouseTrackingLevel).toBe(0b010);
	expect(core.snapshot().mouseTracking).toBe(true);
});
```

Use the file's existing core-construction helper rather than adding `createTestCore` if one is already there.

- [ ] **Step 2: Run it to verify it fails**

```bash
npm --prefix packages/terminal run build:wasm
npm --prefix packages/terminal test --workspace ts/core
```
Expected: FAIL — `mouseTrackingLevel` is `undefined`.

- [ ] **Step 3: Wire it through all three layers**

`crates/vt-wasm/src/lib.rs` — beside the existing `mouse_tracking` export:

```rust
    #[wasm_bindgen(js_name = mouse_tracking_level)]
    pub fn mouse_tracking_level(&self) -> u8 {
        self.core.mouse_tracking_level()
    }
```

`ts/core/src/types.ts` — add to the snapshot type beside `mouseTracking`:

```ts
	readonly mouseTrackingLevel: number;
```

`ts/core/src/terminal-core.ts:138` — beside the existing `bracketedPaste` line:

```ts
			mouseTrackingLevel: this.inner.mouse_tracking_level(),
```

- [ ] **Step 4: Run the tests**

```bash
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-wasm/src/lib.rs packages/terminal/ts/core/src/
git commit -m "feat(terminal-core): publish the mouse tracking level on the snapshot"
```

---

## Task 5: Click and drag reporting

**Files:**
- Create: `packages/terminal/ts/react/src/mouse-report.ts`
- Create: `packages/terminal/ts/react/src/mouse-report.test.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:186-270, 322-335`
- Modify: `packages/terminal/ts/react/src/index.ts`

**Interfaces:**
- Consumes: `TerminalSnapshot.mouseTrackingLevel` from Task 4.
- Produces:
  ```ts
  export type MouseReportKind = "press" | "release" | "drag" | "move" | "wheelUp" | "wheelDown";
  export interface MouseModifiers {
    shift: boolean;
    alt: boolean;
    ctrl: boolean;
  }
  export interface MouseReportInput {
    kind: MouseReportKind;
    button: 0 | 1 | 2;
    column: number;
    row: number;
    sgrMouse: boolean;
    trackingLevel: number;
    modifiers: MouseModifiers;
    altScreen: boolean;
  }
  export function encodeMouseReport(input: MouseReportInput): string | null;
  ```
  Task 6 does not use these. Tasks 6 and 9 do not either.

**Warp's encoding, verified 2026-09-02.** `crates/warp_terminal/src/model/escape_sequences.rs:327-364` is `impl ToEscapeSequence for MouseState`: the final byte is `'m'` for `MouseAction::Released` and `'M'` otherwise; the body is `CSI < button ; col+1 ; row+1 <final>`. The button constants are at `:183-188` — `MOUSE_LEFT = 0`, `MOUSE_RIGHT = 2`, `MOUSE_DRAG = 32`, `MOUSE_MOVE = 35`, `MOUSE_WHEEL_UP = 64`, `MOUSE_WHEEL_DOWN = 65`. Our existing wheel path in `TerminalSurface.tsx:239-241` already emits 64/65 with `M`, so it matches and does not change.

`MOUSE_DRAG = 32` is left-drag specifically: 32 is the motion bit (`0b100000`) plus button 0. A right-button drag is `32 + 2 = 34`. Warp only ever constructs `LeftDrag`, so this is our extension, not a copy; encode it as motion-bit-plus-button so all three buttons behave.

**Three deliberate departures from Warp in this task.** Each is scope decision 5 in the header, restated where the code is.

1. **Modifier bits are encoded; Warp's are not.** `MouseState` carries a `ModifiersState` (`model/mouse.rs:25,54`) that `to_escape_sequence` never reads (`escape_sequences.rs:327-364`), so in Warp a `ctrl+click` and a plain click produce identical bytes. The xterm convention adds them to the button code — **shift 4, alt 8, ctrl 16** — and a TUI that offers ctrl+click cannot work without them. We encode them.
2. **Shift suppresses reporting entirely.** `should_intercept_mouse` returns early when shift is held (`alt_screen/mod.rs:14-16`), meaning Warp handles the event locally rather than forwarding it. That is the universal terminal escape hatch: hold shift to select text out of a program that has grabbed the mouse. `encodeMouseReport` returns `null` for a shift-held event, before anything else — so shift never reaches the child *and* never suppresses browser selection, because the caller exits without `preventDefault`. Note the interaction with (1): shift is the one modifier that is never encoded, because it is consumed here.
3. **The gate is tracking-mode OR alt-screen, not alt-screen alone.** `alt_screen/mod.rs:18-21` ORs `is_alt_screen_active()` with the three tracking modes, commented *"Require some level of mouse tracking to be enabled when the block list is active."* **This is the correction that matters most.** Since the tmux removal an Operator agent pane runs in the normal buffer (spec §0.7), so gating on the alternate screen would report nothing in the pane the user watches all day. `altScreen` is an input to the encoder, not a precondition on the listener.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/react/src/mouse-report.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { encodeMouseReport } from "./mouse-report.js";

const noMods = { shift: false, alt: false, ctrl: false } as const;
const base = {
	column: 5,
	row: 3,
	sgrMouse: true,
	trackingLevel: 0b001,
	modifiers: noMods,
	altScreen: false,
} as const;

describe("encodeMouseReport", () => {
	it("returns null when the program has not asked for SGR encoding", () => {
		expect(encodeMouseReport({ ...base, sgrMouse: false, kind: "press", button: 0 })).toBeNull();
	});

	it("returns null when no tracking level is set", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0, kind: "press", button: 0 })).toBeNull();
	});

	it("encodes a left press with Warp's button code and a trailing M", () => {
		expect(encodeMouseReport({ ...base, kind: "press", button: 0 })).toBe("\x1b[<0;5;3M");
	});

	it("encodes a right press as button 2", () => {
		expect(encodeMouseReport({ ...base, kind: "press", button: 2 })).toBe("\x1b[<2;5;3M");
	});

	it("encodes a release with a trailing m", () => {
		expect(encodeMouseReport({ ...base, kind: "release", button: 0 })).toBe("\x1b[<0;5;3m");
	});

	it("suppresses a drag when only click tracking is on", () => {
		expect(encodeMouseReport({ ...base, kind: "drag", button: 0 })).toBeNull();
	});

	it("encodes a left drag as the motion bit plus the button under 1002", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "drag", button: 0 })).toBe(
			"\x1b[<32;5;3M",
		);
	});

	it("encodes a right drag as 34", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "drag", button: 2 })).toBe(
			"\x1b[<34;5;3M",
		);
	});

	it("suppresses buttonless motion unless 1003 is on", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "move", button: 0 })).toBeNull();
		expect(encodeMouseReport({ ...base, trackingLevel: 0b100, kind: "move", button: 0 })).toBe(
			"\x1b[<35;5;3M",
		);
	});

	it("reports in the normal buffer when the program asked, with no alt screen", () => {
		expect(encodeMouseReport({ ...base, altScreen: false, kind: "press", button: 0 })).toBe(
			"\x1b[<0;5;3M",
		);
	});

	it("reports in the alt screen even with no tracking mode set", () => {
		expect(
			encodeMouseReport({ ...base, altScreen: true, trackingLevel: 0, kind: "press", button: 0 }),
		).toBe("\x1b[<0;5;3M");
	});

	it("returns null for a shift-held event so the user can always select", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 0,
				modifiers: { shift: true, alt: false, ctrl: false },
			}),
		).toBeNull();
	});

	it("encodes the wheel with Warp's 64 and 65 at any tracking level", () => {
		expect(encodeMouseReport({ ...base, kind: "wheelUp", button: 0 })).toBe("\x1b[<64;5;3M");
		expect(encodeMouseReport({ ...base, kind: "wheelDown", button: 0 })).toBe("\x1b[<65;5;3M");
	});

	it("returns null for the wheel when no tracking mode is set and no alt screen", () => {
		expect(
			encodeMouseReport({ ...base, trackingLevel: 0, altScreen: false, kind: "wheelUp", button: 0 }),
		).toBeNull();
	});

	it("returns null for a shift-held wheel so the block list scrolls", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "wheelUp",
				button: 0,
				modifiers: { shift: true, alt: false, ctrl: false },
			}),
		).toBeNull();
	});

	it("adds 8 for alt and 16 for ctrl, and both together", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 0,
				modifiers: { shift: false, alt: true, ctrl: false },
			}),
		).toBe("\x1b[<8;5;3M");
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 2,
				modifiers: { shift: false, alt: false, ctrl: true },
			}),
		).toBe("\x1b[<18;5;3M");
		expect(
			encodeMouseReport({
				...base,
				trackingLevel: 0b010,
				kind: "drag",
				button: 0,
				modifiers: { shift: false, alt: true, ctrl: true },
			}),
		).toBe("\x1b[<56;5;3M");
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
npm --prefix packages/terminal test --workspace ts/react
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the encoder**

Create `packages/terminal/ts/react/src/mouse-report.ts`:

```ts
export type MouseReportKind = "press" | "release" | "drag" | "move" | "wheelUp" | "wheelDown";

export interface MouseModifiers {
	shift: boolean;
	alt: boolean;
	ctrl: boolean;
}

export interface MouseReportInput {
	kind: MouseReportKind;
	button: 0 | 1 | 2;
	column: number;
	row: number;
	sgrMouse: boolean;
	trackingLevel: number;
	modifiers: MouseModifiers;
	altScreen: boolean;
}

const TRACK_CLICK = 0b001;
const TRACK_DRAG = 0b010;
const TRACK_MOTION = 0b100;
const MOTION_BIT = 32;
const MOVE_BUTTON = 35;
const WHEEL_UP = 64;
const WHEEL_DOWN = 65;
const MOD_ALT = 8;
const MOD_CTRL = 16;

export function encodeMouseReport(input: MouseReportInput): string | null {
	if (input.modifiers.shift) return null;
	if (!input.sgrMouse) return null;
	const { kind, button, trackingLevel, altScreen } = input;
	const tracking = altScreen
		? trackingLevel | TRACK_CLICK | TRACK_DRAG | TRACK_MOTION
		: trackingLevel;
	if (tracking === 0) return null;
	let code: number;
	switch (kind) {
		case "press":
		case "release":
			if ((tracking & (TRACK_CLICK | TRACK_DRAG | TRACK_MOTION)) === 0) return null;
			code = button;
			break;
		case "drag":
			if ((tracking & (TRACK_DRAG | TRACK_MOTION)) === 0) return null;
			code = MOTION_BIT + button;
			break;
		case "move":
			if ((tracking & TRACK_MOTION) === 0) return null;
			code = MOVE_BUTTON;
			break;
		case "wheelUp":
			code = WHEEL_UP;
			break;
		case "wheelDown":
			code = WHEEL_DOWN;
			break;
	}
	if (input.modifiers.alt) code += MOD_ALT;
	if (input.modifiers.ctrl) code += MOD_CTRL;
	const final = kind === "release" ? "m" : "M";
	return `\x1b[<${code};${input.column};${input.row}${final}`;
}
```

Export it from `ts/react/src/index.ts`.

- [ ] **Step 4: Run the tests**

```bash
npm --prefix packages/terminal test --workspace ts/react
```
Expected: PASS, all nine.

- [ ] **Step 5: Wire it into `TerminalSurface`, in its own effect**

First widen `pointerCell` (:322) to accept `MouseEvent | WheelEvent` — the two fields it reads, `clientX` and `clientY`, exist on both:

```tsx
function pointerCell(
	host: HTMLElement,
	event: MouseEvent | WheelEvent,
	renderer: DomBlockRenderer | null,
): { column: number; row: number } {
```

**The mouse listeners do NOT go in the `altActive` effect at :186.** That effect returns early when the alternate screen is inactive, and an Operator agent pane is in the normal buffer (spec §0.7). Add a *new* effect that does not depend on `altActive`:

```tsx
	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		if (!blockHost) return;
		let dragButton: 0 | 1 | 2 | null = null;
		const modifiersOf = (event: MouseEvent) => ({
			shift: event.shiftKey,
			alt: event.altKey,
			ctrl: event.ctrlKey,
		});
		const buttonOf = (event: MouseEvent): 0 | 1 | 2 | null =>
			event.button === 0 ? 0 : event.button === 1 ? 1 : event.button === 2 ? 2 : null;
		const reportFor = (kind: MouseReportKind, button: 0 | 1 | 2, event: MouseEvent) => {
			const snapshot = core.snapshot();
			const { column, row } = pointerCell(blockHost, event, rendererRef.current);
			return encodeMouseReport({
				kind,
				button,
				column,
				row,
				sgrMouse: snapshot.sgrMouse,
				trackingLevel: snapshot.mouseTrackingLevel,
				modifiers: modifiersOf(event),
				altScreen: snapshot.altScreen !== null,
			});
		};
		const onMouseDown = (event: MouseEvent) => {
			const button = buttonOf(event);
			if (button === null) return;
			const data = reportFor("press", button, event);
			if (data === null) return;
			event.preventDefault();
			dragButton = button;
			onSendRaw(data);
		};
		const onMouseMove = (event: MouseEvent) => {
			const data =
				dragButton === null ? reportFor("move", 0, event) : reportFor("drag", dragButton, event);
			if (data === null) return;
			onSendRaw(data);
		};
		const onMouseUp = (event: MouseEvent) => {
			const button = buttonOf(event);
			if (button === null) return;
			dragButton = null;
			const data = reportFor("release", button, event);
			if (data === null) return;
			event.preventDefault();
			onSendRaw(data);
		};
		blockHost.addEventListener("mousedown", onMouseDown);
		blockHost.addEventListener("mousemove", onMouseMove);
		blockHost.addEventListener("mouseup", onMouseUp);
		return () => {
			blockHost.removeEventListener("mousedown", onMouseDown);
			blockHost.removeEventListener("mousemove", onMouseMove);
			blockHost.removeEventListener("mouseup", onMouseUp);
		};
	}, [core, onSendRaw]);
```

Import `encodeMouseReport` and `type MouseReportKind` from `./mouse-report.js`.

Check what the snapshot field for alt-screen state is actually called before writing `snapshot.altScreen !== null` — `TerminalSurface.tsx:229` reads `snapshot.altScreen?.rows`, so a nullable object is the shape, but confirm against `ts/core/src/types.ts` rather than trusting this line.

**Four properties this shape guarantees, each of which is a bug if lost.**

- **Selection still works.** `encodeMouseReport` returns `null` whenever the program has not asked, and every handler returns before `preventDefault` in that case. The browser's native selection — which §9.3 says DOM buys us for free — is untouched.
- **Shift always selects.** The encoder rejects shift-held events first, so holding shift is a guaranteed escape hatch out of a program that grabbed the mouse. This is Warp's `should_intercept_mouse` early return (`alt_screen/mod.rs:14-16`).
- **`mousemove` never calls `preventDefault`.** It fires constantly; taking the default on every one of them would break selection and hover across the whole pane.
- **No timer decides anything.** §3.5 and `check-no-ownership-timer.mjs` both apply. The mode bits say whether to report; nothing waits.

**The wheel moves to the same predicate — see Step 6.** Warp routes scroll through it too: `should_intercept_scroll` is `should_intercept_mouse(...) || !scroll_reporting_enabled` (`alt_screen/mod.rs:29-34`). A normal-buffer program with tracking on must receive wheel reports rather than scrolling the block list underneath it.

- [ ] **Step 6: Move the wheel onto the same predicate**

`onWheel` currently lives in the `altActive` effect (`TerminalSurface.tsx:220-247`), so a normal-buffer program that set mouse tracking gets no wheel reports and the block list scrolls underneath it instead. Warp routes scroll through the same gate — `should_intercept_scroll` is `should_intercept_mouse(...) || !scroll_reporting_enabled` (`alt_screen/mod.rs:29-34`). Move it into the effect Step 5 created.

**Three outcomes, and the third is the one that must not regress.** Decide which before touching the accumulators:

| Program asked (`sgrMouse` + tracking, or alt screen) | Alt screen | Outcome |
| --- | --- | --- |
| yes | either | SGR wheel report, `preventDefault` |
| no | yes | synthesized `CSI A`/`B` (or `SS3` under `DECCKM`), `preventDefault` |
| no | no | **do nothing at all** — no `preventDefault`, no accumulator touch — so the block list scrolls natively |

That third row is the behaviour the user confirmed good on 2026-09-02, and `todo_without_tmux.md` §1 records that the `scroll-latency` benchmark **cannot detect** a regression in it: p50 = p95 = 17.000ms, the vsync floor, zero variance. There is no instrument that will catch you breaking this, so the test below is the only guard.

Move the handler, and gate before the velocity sampling so the accumulator never advances on an event the surface is not consuming:

```tsx
		const onWheel = (event: WheelEvent) => {
			const snapshot = core.snapshot();
			const altScreen = snapshot.altScreen !== null;
			const reports =
				!event.shiftKey &&
				snapshot.sgrMouse &&
				(altScreen || snapshot.mouseTrackingLevel !== 0);
			if (!reports && !altScreen) return;
			event.preventDefault();
			const measuredCellHeight = rendererRef.current?.measure().cellHeight ?? 0;
			const deltaLines =
				event.deltaMode === WheelEvent.DOM_DELTA_LINE
					? event.deltaY
					: event.deltaMode === WheelEvent.DOM_DELTA_PAGE
						? event.deltaY * (snapshot.altScreen?.rows ?? 1)
						: measuredCellHeight > 0
							? (event.deltaY * accelerationGain(sampleVelocity(event.deltaY))) / measuredCellHeight
							: 0;
			if (!Number.isFinite(deltaLines)) return;
			pendingWheelLines += deltaLines;
			const lines = Math.trunc(pendingWheelLines);
			pendingWheelLines -= lines;
			if (lines === 0) return;
			const count = Math.abs(lines);
			if (reports) {
				const { column, row } = pointerCell(blockHost, event, rendererRef.current);
				const data = encodeMouseReport({
					kind: lines > 0 ? "wheelDown" : "wheelUp",
					button: 0,
					column,
					row,
					sgrMouse: snapshot.sgrMouse,
					trackingLevel: snapshot.mouseTrackingLevel,
					modifiers: { shift: event.shiftKey, alt: event.altKey, ctrl: event.ctrlKey },
					altScreen,
				});
				if (data !== null) onSendRaw(data.repeat(count));
				return;
			}
			const prefix = core.snapshot().applicationCursorKeys ? "\x1bO" : "\x1b[";
			onSendRaw(`${prefix}${lines > 0 ? "B" : "A"}`.repeat(count));
		};
		blockHost.addEventListener("wheel", onWheel, { passive: false });
```

with the matching `removeEventListener` in the cleanup. Move `pendingWheelLines`, `velocityPxPerSec`, `lastWheelAt` and `sampleVelocity` into this effect and delete them, and the old `onWheel` and its listener, from the `altActive` effect. `appCursor()` is still needed there for `onKeyDown`; leave it.

The `reports` expression is computed inline rather than by calling `encodeMouseReport` first, because the answer decides whether to `preventDefault` *before* any delta work happens — and a report that returns `null` for some other reason must not silently fall through to arrow keys in a program that asked for SGR.

Note `snapshot.mouseTrackingLevel !== 0` here where the button paths use the level's individual bits: every tracking mode reports the wheel identically, which is why `encodeMouseReport`'s wheel arms carry no level check.

- [ ] **Step 7: Guard the block-list scroll with a test**

In `TerminalSurface.test.tsx`:

```tsx
it("leaves a normal-buffer wheel to the block list when no program asked", () => {
	const onSendRaw = vi.fn();
	const { host } = renderSurface({ altScreenActive: false, onSendRaw });
	const event = new WheelEvent("wheel", { deltaY: 120, cancelable: true, bubbles: true });
	host.dispatchEvent(event);
	expect(onSendRaw).not.toHaveBeenCalled();
	expect(event.defaultPrevented).toBe(false);
});

it("reports a normal-buffer wheel once the program asks for tracking", () => {
	const onSendRaw = vi.fn();
	const { host, core } = renderSurface({ altScreenActive: false, onSendRaw });
	core.feed(new TextEncoder().encode("\x1b[?1006h\x1b[?1000h"));
	const event = new WheelEvent("wheel", { deltaY: 120, cancelable: true, bubbles: true });
	host.dispatchEvent(event);
	expect(onSendRaw).toHaveBeenCalledWith(expect.stringContaining("\x1b[<65;"));
	expect(event.defaultPrevented).toBe(true);
});

it("gives the block list a shift-wheel even when the program asked", () => {
	const onSendRaw = vi.fn();
	const { host, core } = renderSurface({ altScreenActive: false, onSendRaw });
	core.feed(new TextEncoder().encode("\x1b[?1006h\x1b[?1000h"));
	const event = new WheelEvent("wheel", { deltaY: 120, shiftKey: true, cancelable: true, bubbles: true });
	host.dispatchEvent(event);
	expect(onSendRaw).not.toHaveBeenCalled();
	expect(event.defaultPrevented).toBe(false);
});
```

The first test is the regression guard for the confirmed-good scroll. If it ever fails, the fix is that test's expectations, never its deletion.

- [ ] **Step 8: Check the line count**

```bash
npm --prefix packages/terminal run check:boundaries
```
Expected: PASS. If `TerminalSurface.tsx` crossed 600, extract the whole alt-screen input effect into `ts/react/src/alt-input.ts` as a function taking `{ blockHost, core, rendererRef, onSendRaw }` and returning a disposer — do not raise `LINE_LIMIT`.

- [ ] **Step 9: Run the tests**

```bash
npm --prefix packages/terminal test
npm --prefix frontend test
```
Expected: PASS.

- [ ] **Step 10: Verify by running it, not only by unit test**

Phase 7's accept criteria require this. Start the app, open a session, run `htop`, and click a column header to sort. Then run `vim`, and drag to select. Both must respond to the mouse. Then scroll an ordinary shell session with no TUI running and confirm the block list still scrolls the way it does today — that is the Step 7 guard, verified by hand.

```bash
npm --prefix frontend run tauri:dev
```

If you have no display session, say so in your task report and leave this step unchecked rather than checking it on the unit tests alone.

- [ ] **Step 11: Commit**

```bash
git add packages/terminal/ts/react/src/
git commit -m "feat(terminal): report mouse events to the program that asked

vt-core already tracked 1000/1002/1003; the surface only ever reported
the wheel, and only in the alternate screen. Clicks, drags and the wheel
now follow the program's own mode bits in either buffer, which is where
an agent pane has lived since tmux left. Button codes follow Warp's own
constants; modifier bits and the shift override are ours. A wheel no
program asked for is left to the block list."
```

---

## Task 6: Focus reporting (`?1004`)

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/types.ts`, `terminal-core.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Test: `packages/terminal/crates/vt-core/src/parser.rs` (inline), `packages/terminal/ts/react/src/TerminalSurface.test.tsx`

**Interfaces:**
- Consumes: the snapshot-plumbing pattern established by Task 4. Follow it exactly.
- Produces: `Parser::focus_reporting() -> bool`, `TerminalSnapshot.focusReporting: boolean`, and a `focus`/`blur` listener that writes `\x1b[I` / `\x1b[O`.

**Why this is in phase 7 at all.** It is not in the spec's phase 7 deliverable list; it was found in the same Warp read that produced Task 5's corrections. It belongs here rather than in a later phase for one reason: `?1004` is a *mode the program sets and then waits on*. `vt-core` does not parse 1004 at all today, which means the sequence falls through the parser and a program that enables focus reporting gets silence forever. Warp implements it — `TermMode::FOCUS_IN_OUT` at `crates/warp_terminal/src/model/mode.rs:21`, set at `crates/warp_terminal/src/model/grid/ansi_handler.rs:1015` and cleared at `:1082`, reported as `EscCodes::FOCUS_IN` / `FOCUS_OUT` = `ESC [ I` / `ESC [ O` (`crates/warp_terminal/src/model/escape_sequences.rs:190-191`) behind `should_report_focus` (`app/src/terminal/view.rs:8374-8380`).

It is small, it shares every layer Task 4 just plumbed, and it is the third of the three "reporting" modes Warp groups together. Doing it now costs one task; doing it later costs the same plumbing twice.

- [ ] **Step 1: Write the failing parser test**

Append to `parser.rs`'s test module:

```rust
    #[test]
    fn focus_reporting_mode_is_tracked() {
        let mut p = Parser::new();
        assert!(!p.focus_reporting());
        p.feed(b"\x1b[?1004h");
        assert!(p.focus_reporting());
        p.feed(b"\x1b[?1004l");
        assert!(!p.focus_reporting());
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && cargo test -p vt-core focus_reporting
```
Expected: FAIL — `no method named focus_reporting`.

- [ ] **Step 3: Track the mode**

In `parser.rs`, add a `focus_reporting: bool` field beside `bracketed_paste` (:24), default `false` (:44), an accessor beside `bracketed_paste()` (:124), and a match arm beside `2004` (:145):

```rust
            1004 => {
                self.focus_reporting = set;
            }
```

Delegate from `lib.rs` and export from `vt-wasm/src/lib.rs` exactly as Task 4 did for `mouse_tracking_level`. Add `readonly focusReporting: boolean;` to the snapshot type and `focusReporting: this.inner.focus_reporting(),` to `terminal-core.ts`.

- [ ] **Step 4: Run the Rust and core tests**

```bash
cd packages/terminal && cargo test -p vt-core
npm --prefix packages/terminal run build:wasm && npm --prefix packages/terminal test --workspace ts/core
```
Expected: PASS.

- [ ] **Step 5: Write the failing surface test**

In `TerminalSurface.test.tsx`:

```tsx
it("reports focus and blur only when the program asked", () => {
	const onSendRaw = vi.fn();
	const { host, core } = renderSurface({ onSendRaw });
	host.dispatchEvent(new FocusEvent("focus"));
	expect(onSendRaw).not.toHaveBeenCalled();
	core.feed(new TextEncoder().encode("\x1b[?1004h"));
	host.dispatchEvent(new FocusEvent("focus"));
	expect(onSendRaw).toHaveBeenCalledWith("\x1b[I");
	host.dispatchEvent(new FocusEvent("blur"));
	expect(onSendRaw).toHaveBeenCalledWith("\x1b[O");
});
```

- [ ] **Step 6: Emit the reports**

Add to the same non-`altActive` effect Task 5 created:

```tsx
		const onFocus = () => {
			if (!core.snapshot().focusReporting) return;
			onSendRaw("\x1b[I");
		};
		const onBlur = () => {
			if (!core.snapshot().focusReporting) return;
			onSendRaw("\x1b[O");
		};
		blockHost.addEventListener("focus", onFocus);
		blockHost.addEventListener("blur", onBlur);
```

and the matching removals in the cleanup. Reading the mode at event time rather than capturing it is deliberate: a program can enable focus reporting at any point after mount, and a captured value would be stale.

- [ ] **Step 7: Run everything**

```bash
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/terminal/crates/vt-core/src/ packages/terminal/crates/vt-wasm/src/ packages/terminal/ts/
git commit -m "feat(terminal): report focus and blur when the program asks

?1004 was not parsed at all, so a program that enabled focus reporting
waited forever."
```

---

## Task 7: IME composition

**Files:**
- Create: `packages/terminal/ts/react/src/composition-target.ts`
- Create: `packages/terminal/ts/react/src/composition-target.test.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Modify: `packages/terminal/ts/react/src/index.ts`

**Interfaces:**
- Consumes: nothing from Tasks 3-5.
- Produces:
  ```ts
  export interface CompositionTarget {
    element: HTMLTextAreaElement;
    focus(): void;
    isComposing(): boolean;
    dispose(): void;
  }
  export function createCompositionTarget(opts: {
    parent: HTMLElement;
    onCommit(text: string): void;
  }): CompositionTarget;
  ```

**Why this is more than the spec implies.** §13.4.2 lists IME as something xterm supplies. It is, but the package has no composition path at all in *either* direction: `ts/editor/src/line-editor.ts` builds its root with `document.createElement("div")` (:59) and never creates a text input, and the alt-screen path focuses `blockHost` and listens for `keydown`. A `div` receives no `compositionstart`/`compositionend` and cannot host an IME candidate window. So this task adds the missing element, and it benefits the owned line editor as much as passthrough.

**What Warp does, and the one part of it we are not doing.** Warp's editor shows the composing text *inline* while the IME is still open — `set_marked_text(marked_text, selected_range, ctx)` (`app/src/editor/view/mod.rs:8234`) paints the preedit with the IME's own selection range inside it, tracked as `MarkedTextState::{Active { selected_range }, Inactive}` (`app/src/editor/view/model/selections.rs:350-358`). It also commits a half-finished composition rather than dropping it when the user clicks away or makes a new selection — `maybe_commit_incomplete_ime_text` (`:8214-8232`).

Split those two by path, because they are not equally reachable:

- **Passthrough (a program owns the line).** Commit-on-`compositionend` is not a compromise, it is the only correct behaviour: the child process cannot render a preedit and no terminal shows one. Steps 1-6 below.
- **The owned line editor.** Warp's inline preedit is genuinely better, and we are **deferring it** rather than pretending otherwise. Step 7 wires the same commit-on-end target into the line editor so CJK input *works* there; the composing text appears in the IME's floating candidate window rather than inline in the prompt row. Recorded as a known gap in Task 10, with `set_marked_text` as the reference for whoever closes it. Closing it needs the line editor to render a styled range it does not own, which is a `ts/editor` change of its own size — larger than the rest of this task combined.
- **The commit-on-focus-loss case is NOT deferred.** Dropping half-typed text when a user clicks away is data loss, and it is cheap to prevent. Step 5 covers it.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/react/src/composition-target.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createCompositionTarget } from "./composition-target.js";

describe("createCompositionTarget", () => {
	let parent: HTMLElement;

	beforeEach(() => {
		parent = document.createElement("div");
		document.body.append(parent);
	});

	it("mounts a focusable textarea that is visually hidden", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		expect(target.element.tagName).toBe("TEXTAREA");
		expect(parent.contains(target.element)).toBe(true);
		expect(target.element.getAttribute("aria-hidden")).toBe("true");
		target.dispose();
		expect(parent.contains(target.element)).toBe(false);
	});

	it("reports composing between compositionstart and compositionend", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		expect(target.isComposing()).toBe(false);
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		expect(target.isComposing()).toBe(true);
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		expect(target.isComposing()).toBe(false);
	});

	it("commits the composed text once, on compositionend", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		expect(onCommit).not.toHaveBeenCalled();
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日本");
	});

	it("clears the textarea after a commit so the next composition starts empty", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		target.element.value = "日本";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
		expect(target.element.value).toBe("");
	});

	it("does not commit an empty composition", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "" }));
		expect(onCommit).not.toHaveBeenCalled();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
npm --prefix packages/terminal test --workspace ts/react
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the composition target**

Create `packages/terminal/ts/react/src/composition-target.ts`:

```ts
export interface CompositionTarget {
	element: HTMLTextAreaElement;
	focus(): void;
	isComposing(): boolean;
	dispose(): void;
}

export function createCompositionTarget(opts: {
	parent: HTMLElement;
	onCommit(text: string): void;
}): CompositionTarget {
	const element = document.createElement("textarea");
	element.setAttribute("aria-hidden", "true");
	element.setAttribute("autocorrect", "off");
	element.setAttribute("autocapitalize", "off");
	element.setAttribute("spellcheck", "false");
	element.tabIndex = -1;
	element.style.position = "absolute";
	element.style.left = "0";
	element.style.top = "0";
	element.style.width = "1px";
	element.style.height = "1px";
	element.style.padding = "0";
	element.style.border = "0";
	element.style.outline = "none";
	element.style.resize = "none";
	element.style.opacity = "0";
	element.style.overflow = "hidden";
	element.style.zIndex = "-1";

	let composing = false;

	const onStart = () => {
		composing = true;
	};
	const onEnd = (event: CompositionEvent) => {
		composing = false;
		const text = event.data ?? "";
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};

	element.addEventListener("compositionstart", onStart);
	element.addEventListener("compositionend", onEnd);
	opts.parent.append(element);

	return {
		element,
		focus: () => element.focus({ preventScroll: true }),
		isComposing: () => composing,
		dispose: () => {
			element.removeEventListener("compositionstart", onStart);
			element.removeEventListener("compositionend", onEnd);
			element.remove();
		},
	};
}
```

`opacity: 0` with a real 1×1 box rather than `display: none` or `visibility: hidden` is deliberate: a hidden element cannot be focused and receives no composition events, and the IME candidate window positions itself against the element's box. Export it from `ts/react/src/index.ts`.

- [ ] **Step 4: Run the tests**

```bash
npm --prefix packages/terminal test --workspace ts/react
```
Expected: PASS, all five.

- [ ] **Step 5: Commit an incomplete composition when focus is lost**

Add to `composition-target.ts`, before the return:

```ts
	const onBlur = () => {
		if (!composing) return;
		composing = false;
		const text = element.value;
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};
	element.addEventListener("blur", onBlur);
```

and remove it in `dispose`. Warp does the same thing at `app/src/editor/view/mod.rs:8214-8232`, and its doc comment names the two cases it exists for: *"a new selection"* and *"clicking outside of the editor"*.

Cover it:

```ts
	it("commits an in-flight composition when focus is lost", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "にほ";
		target.element.dispatchEvent(new FocusEvent("blur"));
		expect(onCommit).toHaveBeenCalledExactlyOnceWith("にほ");
		expect(target.isComposing()).toBe(false);
	});

	it("does not commit on blur when nothing is composing", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new FocusEvent("blur"));
		expect(onCommit).not.toHaveBeenCalled();
	});
```

- [ ] **Step 6: Route composition into the surface**

In `TerminalSurface.tsx`, inside the `altActive` effect, create the target and make it the focus owner:

```tsx
		const composition = createCompositionTarget({
			parent: blockHost,
			onCommit: (text) => onSendRaw(text),
		});
```

Replace `blockHost.focus();` with `composition.focus();`, and add `composition.dispose();` to the cleanup.

Guard the key path so a composing keystroke is not sent twice — the IME's own keys must not also reach the child:

```tsx
		const onKeyDown = (event: KeyboardEvent) => {
			if (composition.isComposing() || event.isComposing || event.keyCode === 229) {
				return;
			}
			const data = encodeKey(event, appCursor());
			if (data === null) {
				return;
			}
			event.preventDefault();
			onSendRaw(data);
		};
```

`keyCode === 229` is the historical "the IME is handling this" signal and is still what browsers send for a composing key in some engines; `event.isComposing` alone misses those. Both are cheap and neither is a timer, so §3.5 is not in play.

- [ ] **Step 7: Wire the same target into the owned line editor, then add a regression test**

Mount a second `createCompositionTarget` against the line editor's root (`ts/editor/src/line-editor.ts:59` builds it) and make it the focus owner there, with `onCommit` feeding the editor's insert path — the same one a printable keystroke takes. Do not add inline preedit rendering; that is the deferral recorded above.

Then, in `packages/terminal/ts/react/src/TerminalSurface.test.tsx`, following the file's existing render helper:

```tsx
it("sends composed text once and swallows the composing keydown", async () => {
	const onSendRaw = vi.fn();
	const { host } = renderSurface({ altScreenActive: true, onSendRaw });
	const textarea = host.querySelector("textarea");
	expect(textarea).not.toBeNull();
	host.dispatchEvent(new KeyboardEvent("keydown", { key: "Process", keyCode: 229, bubbles: true }));
	expect(onSendRaw).not.toHaveBeenCalled();
	textarea!.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
	expect(onSendRaw).toHaveBeenCalledExactlyOnceWith("日本");
});
```

- [ ] **Step 8: Run everything**

```bash
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
npm --prefix frontend test
```
Expected: PASS.

- [ ] **Step 9: Verify by hand**

Switch the OS input source to a CJK IME, focus the terminal, type a word, and confirm the candidate window appears near the caret and the committed text reaches the shell exactly once. If you have no display session or no IME installed, leave this unchecked and say so in your report.

- [ ] **Step 10: Commit**

```bash
git add packages/terminal/ts/react/src/
git commit -m "feat(terminal): give the surface a real composition target

Neither the line editor nor the alt surface could host an IME: a div
receives no composition events. A visually-hidden textarea owns focus
and commits on compositionend."
```

---

## Task 8: Map the skin straight to a terminal theme

**Files:**
- Modify: `frontend/src/renderer/theme/bridge/` — whichever module exposes `skinToTerminalTheme`
- Delete: `frontend/src/renderer/theme/bridge/xterm-theme.ts` and `xterm-theme.test.ts`
- Test: the surviving bridge test

**Interfaces:**
- Consumes: nothing.
- Produces: a `skinToTerminalTheme` that builds a `TerminalTheme` with no xterm type in its path. Task 8 depends on this being done first, because it is what makes the xterm import removable.

**Why separate from Task 8:** this is a pure refactor with a test, reversible on its own. Folding it into the deletion means a failure there is two changes to unpick.

- [ ] **Step 1: Find the current path**

```bash
grep -rn "xterm-theme\|skinToTerminalTheme" frontend/src/renderer | grep -v node_modules
```

- [ ] **Step 2: Write the failing test**

In the bridge's test file, assert the output shape directly rather than via an xterm type:

```ts
it("maps a skin to a terminal theme with no xterm type in the path", () => {
	const theme = skinToTerminalTheme(darkSkin);
	expect(theme.ansi).toHaveLength(16);
	expect(theme.background).toMatch(/^#|^rgb/);
	expect(theme.foreground).toMatch(/^#|^rgb/);
	expect(theme.blockBorder).toBeDefined();
});
```

- [ ] **Step 3: Run it**

```bash
npm --prefix frontend test -- theme/bridge
```

- [ ] **Step 4: Inline the mapping and delete the xterm hop**

Rewrite `skinToTerminalTheme` to build the `TerminalTheme` fields directly from the skin, then delete `xterm-theme.ts` and its test.

- [ ] **Step 5: Run the tests**

```bash
npm --prefix frontend test
npx tsc --noEmit -p frontend/tsconfig.json
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/theme/
git commit -m "refactor(theme): map the skin straight to a terminal theme"
```

---

## Task 9: Delete xterm

**Files:**
- Delete: `frontend/src/renderer/components/XtermTerminal.tsx`, `XtermTerminal.test.tsx`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx:55, 1107`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:54-56, 379`
- Modify: `frontend/src/renderer/hooks/useTerminalSession.ts:30, 49, 601`
- Modify: `frontend/src/renderer/main.tsx:7`
- Modify: `frontend/src/renderer/styles.css`
- Modify: `frontend/package.json:102-108`

**Interfaces:**
- Consumes: Tasks 5, 6, 7 and 8. Do not start this until all four are green.
- Produces: no `@xterm` reference anywhere under `frontend/`.

**This is the only irreversible step in the plan.** Everything before it can be reverted commit by commit with the terminal still working.

- [ ] **Step 1: Write the failing test**

Create `frontend/src/renderer/test/no-xterm.test.ts`:

```ts
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { describe, expect, it } from "vitest";

describe("xterm is gone from the renderer", () => {
	it("has no @xterm dependency", () => {
		const pkg = JSON.parse(readFileSync("package.json", "utf8"));
		const deps = { ...pkg.dependencies, ...pkg.devDependencies };
		expect(Object.keys(deps).filter((name) => name.startsWith("@xterm"))).toEqual([]);
	});

	it("has no @xterm import in renderer source", () => {
		const out = execFileSync("git", ["grep", "-l", "@xterm", "--", "src/renderer"], {
			encoding: "utf8",
			cwd: process.cwd(),
		}).trim();
		expect(out).toBe("");
	});
});
```

`git grep` exits non-zero with no matches, which throws — wrap in a try and treat the throw as the empty case, or use `execFileSync(... , { stdio: "pipe" })` inside a helper that catches. Write whichever the repo's other shell-touching tests already do.

- [ ] **Step 2: Run it to verify it fails**

```bash
npm --prefix frontend test -- no-xterm
```
Expected: FAIL on both assertions.

- [ ] **Step 3: Remove the flag and the mount**

`BlockTerminal.tsx`: delete `handsAltScreenToXterm` (:56), the comment above it (:54-55), and `handOffAltScreen` (:379). Every use of `handOffAltScreen` collapses to `false` — simplify the expressions rather than leaving `false &&`.

`TerminalPane.tsx`: delete `usesXtermSurface` (:55), the `<XtermTerminal … headless={…} />` mount (:1107) and its import.

`useTerminalSession.ts`: the `AttachableTerminal` contract at :30 and :49 existed for xterm. Keep the interface if the package surface implements it; delete the `onUserInput` subscription at :601 only if nothing produces those events any more. Let `tsc` decide — do not guess.

- [ ] **Step 4: Delete the files and the dependencies**

```bash
git rm frontend/src/renderer/components/XtermTerminal.tsx \
       frontend/src/renderer/components/XtermTerminal.test.tsx
```

Remove the `import "@xterm/xterm/css/xterm.css";` line from `main.tsx:7`, the `.xterm*` rules from `styles.css`, and the seven `@xterm/*` entries from `frontend/package.json:102-108`. Then:

```bash
npm --prefix frontend install
```

**Do not touch `packages/terminal/package.json`.** Its `@xterm/*` devDependencies feed `bench/adapters/xterm.ts`, which the §9.4 gate measures against.

- [ ] **Step 5: Run everything**

```bash
npm --prefix frontend test
npx tsc --noEmit -p frontend/tsconfig.json
npm --prefix frontend run lint
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
```
Expected: PASS.

- [ ] **Step 6: Prove the gate still measures against xterm**

```bash
npm --prefix packages/terminal run bench:gate
```
Expected: the same single `input-latency` failure that existed before this plan started, and **no** error about a missing xterm adapter. If the adapter cannot load, you deleted the wrong dependency — revert Step 4's `package.json` edit and re-check which file needs it.

- [ ] **Step 7: Verify by running it**

Phase 7's accept criteria require this explicitly, *"verified by running them, not by unit tests alone"*. With no xterm in the tree, confirm in the real app: typing, pasting, mouse clicks and IME composition in `vim`, `htop`, `less` and an agent CLI.

```bash
npm --prefix frontend run tauri:dev
```

Leave unchecked and report if you have no display session.

- [ ] **Step 8: Run the e2e suite**

```bash
npm --prefix frontend run test:e2e
```
Expected: PASS. `frontend/e2e/shell-terminal-tabs.spec.ts` covers the standalone screen, which survives; if it asserts in-session tabs, trim those cases.

- [ ] **Step 9: Commit**

```bash
git add -A frontend/
git commit -m "feat(terminal)!: delete xterm from the renderer

The package's own surface has carried every pane since phase 3 and
now supplies the mouse and IME paths xterm used to. The bench adapter
stays: the perf gate is defined against it."
```

---

## Task 10: Record the phase in the spec

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` — §11, §13.4, §14 Phase 7, §17.5

**Interfaces:**
- Consumes: the outcome of Tasks 1-8.
- Produces: a spec that matches the tree, the way phases 3, 4 and 5 each recorded theirs.

- [ ] **Step 1: Mark the phase landed**

Change the phase 7 heading to `### Phase 7 — Retirement — **landed <date>**` and add a "Landed" paragraph naming the commit range and the task list, in the style of the Phase 5 entry.

- [ ] **Step 2: Record every deviation**

For each place this plan departed from the spec as written, add a numbered entry under the phase. At minimum these four are already known and must appear:

1. **The deletion target was the in-session shell tabs, not the standalone `/terminals` screen.** §13.4's *"one session has exactly one terminal surface"* is about the session pane; §17.5's artefact list named the standalone screen, which has its own UX justification and stays.
2. **There was no history migration.** `daemon/shellterm_wiring.go:57` is the only `Adopt` call site, so session panes never had durable capture. Removing session scoping satisfied §13.4.1 by construction.
3. **`ShellTerminalTab.tsx` and `useShellTerminals.ts` were not deleted** despite §17.5 listing them. Both serve the surviving standalone screen.
4. **IME was not an xterm-supplied capability being replaced.** Neither the line editor nor the alt surface had a composition path; `line-editor.ts:59` builds a `div`. The composition target is new capability, not a port.
5. **Mouse and wheel reporting are gated on the program's tracking modes, not on the alternate screen** — matching `should_intercept_mouse` (`app/src/terminal/alt_screen/mod.rs:18-21`) and `should_intercept_scroll` (`:29-34`), and required because agent panes are in the normal buffer since the tmux removal (§0.7). **§11's wheel paragraph needs rewriting, not annotating:** it describes the wheel rules entirely in terms of the alternate screen, and the rule is now three-way — report when the program asked, synthesize arrows in the alt screen when it did not, and leave the event alone in the normal buffer so the block list scrolls. That third branch is what preserves the scroll the user confirmed good on 2026-09-02, and it has a named regression test because no benchmark can catch it (`todo_without_tmux.md` §1).
6. **Modifier bits are encoded where Warp encodes none**, and **shift suppresses reporting entirely** so the user can always select. Both belong in §3 as named departures — the first is the "Warp carries `modifiers` and never reads them" case at `model/escape_sequences.rs:327-364`; the second is copied from `alt_screen/mod.rs:14-16`.
7. **Focus reporting (`?1004`) was added**, unlisted in the phase. `vt-core` did not parse it, so a program that enabled it waited forever. Add it to §11 beside the mouse modes.
8. **Inline IME preedit is deferred, explicitly.** Warp paints the composing text in the editor via `set_marked_text` with the IME's selection range (`app/src/editor/view/mod.rs:8234`, state at `view/model/selections.rs:350-358`). We commit on `compositionend` and on focus loss; the composing text shows only in the OS candidate window. Record it as a gap with that citation so the next reader has the reference rather than the discovery.
9. **No reporting settings were added.** Warp exposes `terminal.mouse_reporting_enabled`, `scroll_reporting_enabled` and `focus_reporting_enabled`, all defaulting true (`app/src/terminal/alt_screen_reporting.rs:5-33`). A settings surface is deferred phase 6 work; "always report when the program asks" is the right default and the only behaviour a terminal without a preferences pane can have.

- [ ] **Step 3: Fix §11 and §15 item 12**

§11 and §15 item 12 both say `XtermTerminal.tsx` must survive until phase 7. Amend both to past tense with the commit that removed it, so the next reader does not go looking for a fallback that is gone.

- [ ] **Step 4: Update §17.5**

Correct the two rows that this plan proved stale: the `XtermTerminal.tsx` row, and the §13.4 artefact row that lists `ShellTerminalsView.tsx` and friends as phase 7 deletions.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md
git commit -m "docs(spec): record phase 7"
```

---

## Self-review

**Spec coverage.** Phase 7's five accept criteria map as follows. *"The files listed in §13.4.1 and §13.4.2 are gone and no route references `/terminals`"* — partially deliberately **not** met: the `/terminals` route stays by the scope decision recorded above, and Task 10 amends the criterion rather than the tree. *"`grep -rn "@xterm" frontend/src frontend/package.json` returns nothing while the bench adapter is untouched"* — Task 9 Steps 1 and 6. *"Typing, pasting, mouse clicks and IME composition all work … verified by running them"* — Task 5 Step 8, Task 7 Step 9, Task 9 Step 7. *"Bracketed paste and mouse reporting are covered by `vt-core` tests and by at least one recorded vector each"* — bracketed paste is already covered (`parser.rs:145`); mouse reporting gets Task 3's parser test and Task 5's encoder tests. **Gap:** neither adds a recorded *vector* under `protocol/alt-vectors`. An executor who wants the criterion met literally should add a `mouse-report` vector during Task 5; it is cheap and the harness already replays that directory. *"The full e2e suite passes"* — Task 9 Step 8.

**The inherited phase 6 deliverable.** Scrollback persistence moved into phase 7 in the spec on 2026-09-02, on the assumption it meant migrating the bridge. Investigation showed there is no bridge to migrate, so it is discharged by Task 2 rather than built. Task 10 Step 2 records that; if a future reader wants durable blocks for *agent session* panes, that is new work and a new plan, not this one.

**Type consistency.** `mouse_tracking_level` (Rust, Tasks 3-4) → `mouseTrackingLevel` (TS snapshot, Task 4) → `trackingLevel` (encoder input field, Task 5) are three deliberate names at three boundaries, matching each layer's existing convention. `encodeMouseReport` returns `string | null` in every use. `createCompositionTarget` returns the same `CompositionTarget` shape in Task 6's test, implementation and wiring.

**Ordering.** Tasks 1, 2 and 9 are the destructive ones. 1 is frontend-only and revertible; 2 lands after 1 proves nothing calls it; 9 lands last, after 5, 6, 7 and 8 have supplied everything it removes.
