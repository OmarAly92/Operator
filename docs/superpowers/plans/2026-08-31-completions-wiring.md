# Completions Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Phase 4's completion engine to the running app and make the behaviour
identical to Warp's, so a shell pane completes as you type instead of doing nothing.

**Architecture:** Phase 4 built `ts/completions` and the core's provider seam, and nothing
calls either. Three connections are missing: a host that can list a directory, a
registration at the site where the core is created, and Warp's **as-you-type** trigger. The
package boundary does not move — `frontend/` gains a dependency on
`@operator/terminal-completions`, which §4.3 permits (only `ts/editor` and
`ts/renderer-dom` are forbidden from importing it).

**Tech Stack:** TypeScript, Rust (one Tauri command), vitest, `@testing-library/dom`.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §4.1 (host boundary), §4.3 (enforcement), §10.1 (the editor and the provider seam), §13.3 (the renderer's job), §14 Phase 4.

---

## Why this plan exists

Phase 4 landed complete, tested and invisible. `createCompletionProvider` has zero callers
outside its own test; `frontend/package.json` depends only on `@operator/terminal-react`;
nothing implements `HostCapabilities.listDirectory`. At runtime the dispatcher's provider is
`null`, so `requestCompletions` immediately emits `null` and the dropdown never opens.

That was a defect in the Phase 4 plan, not in its execution. Its accept criteria — no shell
execution, cancellable, three commands, gate passes — could all be met by an engine nobody
calls. **This plan's accept criterion is different and deliberately behavioural: a human
types `git ch` at a shell prompt in the running app and sees a dropdown.**

## Verified against Warp

Read in `/Users/omaraly/development/AI/warp` on 2026-08-31.

1. **Warp completes as you type, not only on Tab.** `CompletionsTrigger` has three variants
   — `Keybinding`, `AsYouType`, `SlashCommandAutoOpen` (`app/src/terminal/input.rs:2228-2233`)
   — and the input handler calls
   `self.open_completion_suggestions(CompletionsTrigger::AsYouType, ctx)` on edit
   (`input.rs:10770`, `input.rs:10876`). This is the single biggest difference between what
   we shipped and Warp: our editor **closes** the dropdown on every edit.
2. **As-you-type recalculates, it does not filter the open list.** Warp's own comment at
   `input.rs:10767-10769`: for as-you-type completions it recalculates "since typing could
   involve moving to a new parameter within a given command, rather than being a strict
   subset as is the case with manual tab completions." Our engine is already built this way
   — `requestCompletions` re-runs `locate` from scratch — so matching Warp here means
   calling it more often, not adding a filter path.
3. **Warp closes a stale menu rather than showing it.** Same call site: because completions
   are async, Warp closes the menu if it has not updated after a delay, "otherwise the user
   will see an old completions menu". Our dispatcher already drops stale generations; Task 3
   must not undo that.
4. **Explicit open keeps its own keybinding.** `OPEN_COMPLETIONS_KEYBINDING_NAME =
   "input:open_completion_suggestions"` (`input.rs:434`). Tab stays what it is.

## Global Constraints

- **No comments in code.** The user's global rule.
- **No file over 600 lines** (`check-boundaries.mjs`).
- **`ts/editor` and `ts/renderer-dom` must not import `ts/completions`.** `frontend/` may.
- `frontend/` imports the package **by name**, never by relative path (§4.2).
- User-facing copy goes through `TerminalStrings`; no locale files in the package.
- App state stays under `~/.operator`. `listDirectory` reads the user's *project* files,
  which is a different thing — do not route it through the app-data directory.
- Every task ends with `npm --prefix packages/terminal test`, `npm --prefix frontend test`
  and `npm --prefix packages/terminal run check:boundaries` green.

---

### Task 1: Never complete in an agent pane

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` — accept and honour `agentTui`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx` — pass it through
- Test: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`

**Interfaces:**
- Produces: `TerminalSurfaceProps.agentTui?: boolean`.

The editor host is hidden on `altActive` alone (`TerminalSurface.tsx:199`), and `altActive`
is not the same thing as "this is an agent pane". The host already knows the difference —
`agentTui={terminalTarget?.kind === "worker"}` (`TerminalPane.tsx:1090`) — and the core
already takes it (`setAgentTuiMode`). The two come apart in two real cases:

- an agent CLI that redraws **inline in the normal buffer**, which is the case the whole
  2026-08-30 normal-buffer grid plan exists for: Claude Code driven directly emits no
  `?1049`, and it is tmux that puts the pane in the alternate screen;
- the startup window before tmux's first `?1049h` arrives, when `altActive` is still false.

In both, an agent pane shows the editor today. That is harmless while completions only fire
on Tab; once Task 4 lands as-you-type, it would flash a dropdown over a TUI. This task must
land **before** Task 4 for that reason.

- [ ] **Step 1: Write the failing tests**

```ts
	it("hides the editor in an agent pane even outside the alternate screen", () => {
		const { editorHost } = mountSurface({ agentTui: true });
		expect(editorHost.hidden).toBe(true);
	});

	it("keeps the editor in a shell pane", () => {
		const { editorHost } = mountSurface({ agentTui: false });
		expect(editorHost.hidden).toBe(false);
	});

	it("asks for no completions in an agent pane", () => {
		const { editor, core } = mountSurface({ agentTui: true });
		let calls = 0;
		core.requestCompletions = () => {
			calls += 1;
		};
		editor.handleKey(new KeyboardEvent("keydown", { key: "Tab" }));
		expect(calls).toBe(0);
	});
```

- [ ] **Step 2: Run them and watch them fail**

```bash
npm --prefix packages/terminal/ts/react test
```

Expected: the first and third FAIL — `agentTui` is not a prop yet.

- [ ] **Step 3: Honour it**

Add `agentTui?: boolean` to `TerminalSurfaceProps`, and hide the editor host when
`altActive || agentTui`. Do not mount the `LineEditor` at all when `agentTui` is true: a
hidden editor that still holds a keydown listener and a completions subscription is a
liability, not a saving.

In `BlockTerminal.tsx`, pass the `agentTui` prop it already receives straight through to
`TerminalSurface`.

- [ ] **Step 4: Run the suites**

```bash
npm --prefix packages/terminal test
npm --prefix frontend test
```

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/react frontend/src/renderer
git commit -m "feat(terminal): never show the editor, or complete, in an agent pane"
```

---

### Task 2: A host that can list a directory

**Files:**
- Modify: `frontend/src-tauri/src/native.rs` — add `list_directory`
- Modify: `frontend/src-tauri/src/lib.rs` — register it in all three `generate_handler!` lists
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts` — expose it on the bridge
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:341` — add `listDirectory` to the `host` memo
- Test: `frontend/src/renderer/components/BlockTerminal.test.tsx`

**Interfaces:**
- Produces: Tauri command `list_directory(path: String) -> Result<Vec<DirEntryDto>, String>`
  where `DirEntryDto { name: String, is_directory: bool, is_hidden: bool }`;
  `operatorBridge.fs.listDirectory(path)`; and `host.listDirectory` satisfying
  `HostCapabilities` from `@operator/terminal-core`.

- [ ] **Step 1: Write the failing renderer test**

In `BlockTerminal.test.tsx`, assert that the `host` passed to `TerminalSurface` exposes
`listDirectory`, that it forwards the path to the bridge, and that it maps the bridge's
shape to `DirEntry`:

```tsx
it("gives the terminal a host that can list a directory", async () => {
	const asked: string[] = [];
	bridge.fs = {
		listDirectory: async (path: string) => {
			asked.push(path);
			return [{ name: ".git", isDirectory: true, isHidden: true }];
		},
	};
	render(<BlockTerminal {...props} />);
	const host = await capturedHost();
	expect(await host.listDirectory?.("/repo")).toEqual([
		{ name: ".git", isDirectory: true, isHidden: true },
	]);
	expect(asked).toEqual(["/repo"]);
});
```

Match the file's existing patterns for `capturedHost` and the bridge stub — read the
neighbouring tests rather than inventing a harness.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix frontend test -- BlockTerminal
```

Expected: FAIL — `host.listDirectory` is undefined.

- [ ] **Step 3: Add the Tauri command**

In `native.rs`, following the shape of `open_external` and `clipboard_write` above it:

```rust
#[derive(serde::Serialize)]
pub struct DirEntryDto {
    name: String,
    is_directory: bool,
    is_hidden: bool,
}

#[tauri::command]
pub async fn list_directory(path: String) -> Result<Vec<DirEntryDto>, String> {
    let mut entries = tokio::fs::read_dir(&path)
        .await
        .map_err(|error| error.to_string())?;
    let mut out = Vec::new();
    while let Some(entry) = entries.next_entry().await.map_err(|error| error.to_string())? {
        let name = entry.file_name().to_string_lossy().to_string();
        let is_directory = entry
            .file_type()
            .await
            .map(|kind| kind.is_dir())
            .unwrap_or(false);
        out.push(DirEntryDto {
            is_hidden: name.starts_with('.'),
            name,
            is_directory,
        });
    }
    Ok(out)
}
```

Register `list_directory` in **every** `tauri::generate_handler!` list in `lib.rs` — there
are three (around lines 970, 979, 999), and missing one produces a command that works in
some builds and not others.

**Scope note for the reviewer:** this lets the renderer enumerate any readable path. That is
not a new privilege in a terminal that already runs arbitrary commands, but it is new
*surface*, so it returns names only — no sizes, no contents, no symlink targets — and it
must not follow a path outside what the user could already reach from the shell.

- [ ] **Step 4: Expose it on the bridge and the host**

Add `fs: { listDirectory }` to `tauri-bridge.ts` next to `clipboard`, calling
`invoke("list_directory", { path })`. Then in `BlockTerminal.tsx`'s `host` memo, add:

```ts
			listDirectory: async (path: string) => operatorBridge.fs.listDirectory(path),
```

Keep the memo's dependency array correct.

- [ ] **Step 5: Run the tests**

```bash
npm --prefix frontend test -- BlockTerminal
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/src-tauri frontend/src/renderer
git commit -m "feat(terminal): let the host list a directory for path completion"
```

---

### Task 3: Register the engine where the core is created

**Files:**
- Modify: `frontend/package.json` — add the dependency
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:256` — register after `createTerminalCore`
- Test: `frontend/src/renderer/components/BlockTerminal.test.tsx`

**Interfaces:**
- Consumes: `createCompletionProvider` from `@operator/terminal-completions`;
  `core.registerCompletionProvider` (Phase 4, Task 5).
- Produces: nothing new — this is the connection itself.

- [ ] **Step 1: Write the failing test**

Assert the behaviour, not the call: feed the core into a mounted pane, ask it for
completions, and expect a real answer.

```tsx
it("answers a completion request once the core exists", async () => {
	render(<BlockTerminal {...props} />);
	const core = await capturedCore();
	const seen: unknown[] = [];
	core.onCompletions((result) => seen.push(result));
	core.requestCompletions("gi", 2);
	await waitFor(() => expect(seen).toHaveLength(1));
	expect((seen[0] as { items: { value: string }[] }).items.map((i) => i.value)).toContain(
		"git",
	);
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix frontend test -- BlockTerminal
```

Expected: FAIL — the listener receives `null`, because no provider is registered.

- [ ] **Step 3: Add the dependency**

In `frontend/package.json`, beside `"@operator/terminal-react"`:

```json
		"@operator/terminal-completions": "file:../packages/terminal/ts/completions",
```

Then `npm --prefix frontend install`.

- [ ] **Step 4: Register the provider**

In the `createTerminalCore` effect, immediately after `created.setAgentTuiMode(...)`:

```ts
				const releaseCompletions = created.registerCompletionProvider(
					createCompletionProvider(),
				);
```

Call `releaseCompletions()` in the effect's cleanup, before `created?.dispose()`. The
provider is created once per core, not per keystroke — `createCompletionProvider` builds a
`SignatureRegistry` and building one per request would be the one place this feature could
get expensive.

- [ ] **Step 5: Run the tests and the boundary check**

```bash
npm --prefix frontend test -- BlockTerminal
npm --prefix packages/terminal run check:boundaries
```

Expected: PASS and exit 0. `frontend` importing the package is allowed; if the boundary
script objects, read its message before changing it — it may be catching a relative import
rather than the dependency.

- [ ] **Step 6: Commit**

```bash
git add frontend/package.json frontend/package-lock.json frontend/src/renderer
git commit -m "feat(terminal): register the completion engine on every pane's core"
```

---

### Task 4: Complete as you type, the way Warp does

**Files:**
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` — request on edit instead of cancelling
- Test: `packages/terminal/ts/editor/src/line-editor.test.ts`

**Interfaces:**
- Consumes: `core.requestCompletions`, `core.cancelCompletions` (Phase 4, Task 5).
- Produces: no new API. `AS_YOU_TYPE_DELAY_MS = 60`.

Today every text-mutating command calls `cancelDropdownIfOpen()`, so typing **closes**
completions. Warp does the opposite: it recalculates (`input.rs:10770`). This task inverts
that, which is the change that makes the feature feel like Warp rather than like a Tab
shortcut.

The 60ms debounce is ours, not Warp's — Warp's editor is native and synchronous where ours
crosses an async provider. It exists so a fast typist issues one request per pause rather
than one per keystroke; the dispatcher already drops stale generations, so correctness does
not depend on it.

- [ ] **Step 1: Write the failing tests**

```ts
	it("asks for completions as the user types, without pressing Tab", async () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		const requested: string[] = [];
		const original = core.requestCompletions.bind(core);
		core.requestCompletions = (line, cursor) => {
			requested.push(line);
			original(line, cursor);
		};
		editor.handleKey(key({ key: "g" }));
		editor.handleKey(key({ key: "i" }));
		await vi.waitFor(() => expect(requested).toEqual(["gi"]));
	});

	it("coalesces a burst of keystrokes into one request", async () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		let calls = 0;
		core.requestCompletions = () => {
			calls += 1;
		};
		for (const character of "status") editor.handleKey(key({ key: character }));
		await vi.waitFor(() => expect(calls).toBe(1));
	});

	it("closes the dropdown and asks for nothing on an empty line", async () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		let calls = 0;
		core.requestCompletions = () => {
			calls += 1;
		};
		editor.setText("g");
		editor.handleKey(key({ key: "Backspace" }));
		await vi.waitFor(() => expect(calls).toBe(0));
	});

	it("stops asking once the editor is disposed", async () => {
		const { editor, core } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		let calls = 0;
		core.requestCompletions = () => {
			calls += 1;
		};
		editor.handleKey(key({ key: "g" }));
		editor.dispose();
		await new Promise((resolve) => setTimeout(resolve, 120));
		expect(calls).toBe(0);
	});
```

The last two matter more than they look. An empty line must not open a dropdown listing
every command, and a pending timer that fires after `dispose()` reaches a disposed core.

- [ ] **Step 2: Run them and watch them fail**

```bash
npm --prefix packages/terminal/ts/editor test -- line-editor
```

Expected: FAIL — the first two because nothing requests on edit, the fourth because there is
no timer to cancel yet.

- [ ] **Step 3: Replace cancellation with a debounced request**

Add a private `asYouTypeHandle: ReturnType<typeof setTimeout> | null = null`, and a method:

```ts
	private scheduleCompletions(): void {
		if (this.asYouTypeHandle !== null) clearTimeout(this.asYouTypeHandle);
		if (this.buffer.text.trim().length === 0) {
			this.cancelDropdownIfOpen();
			return;
		}
		this.asYouTypeHandle = setTimeout(() => {
			this.asYouTypeHandle = null;
			this.core?.requestCompletions(this.buffer.text, this.buffer.cursor);
		}, AS_YOU_TYPE_DELAY_MS);
	}
```

Call `scheduleCompletions()` from `insert`, `delete-backward`, `delete-forward` and
`delete-word-backward` in place of their current `cancelDropdownIfOpen()` calls. Leave
`submit` calling `cancelDropdownIfOpen()` — a sent command must not leave a menu behind.
Clear the timer in `dispose()`.

Do **not** filter the open list instead of re-requesting: Warp recalculates precisely
because typing can move the cursor into a different parameter (`input.rs:10767-10769`), and
our `locate` already re-derives that.

- [ ] **Step 4: Run the whole editor suite**

```bash
npm --prefix packages/terminal/ts/editor test
```

Expected: PASS. Existing tests that assert typing *cancels* completions describe the
pre-Warp behaviour and must be rewritten to assert the debounced request instead — do not
delete them.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/editor/src
git commit -m "feat(terminal): complete as you type, the way Warp does"
```

---

### Task 5: Prove it in the running app, then record it

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` — §13.3 and §14 Phase 4
- Modify: `docs/superpowers/plans/2026-08-30-warp-terminal-phase-4-completions.md` — status banner

- [ ] **Step 1: Run the app and look**

```bash
npm run tauri:dev
```

Open a **shell** pane, not an agent pane — the editor host is `hidden={altActive}`
(`TerminalSurface.tsx:199`), so a tmux/agent pane has no editor and therefore no dropdown,
by design and matching Warp. Then check all four, and report exactly what you saw:

1. typing `git ch` opens a dropdown with `checkout` selected, no Tab pressed;
2. `↓`/`↑` move the selection, `Esc` closes it, `Enter` inserts;
3. `cd ` lists directories, and accepting one ending in `/` immediately lists its contents;
4. `docker build --file=` offers files and replaces only the text right of the `=`.

If the dropdown does not appear, the fault is one of three things and they are
distinguishable: no provider registered (Task 2), the pane is in the alternate screen
(expected — open a shell pane), or the line editor never reached `Owned` because the shell
bootstrap is not active (§10.2, not this plan's to fix — report it).

- [ ] **Step 2: Confirm nothing regressed**

```bash
npm --prefix packages/terminal test
npm --prefix frontend test
npm --prefix packages/terminal run check:boundaries
```

Do not run `bench:gate` expecting green — `input-latency` is red from the paint throttle in
`ac9236563` and spec §9.5 carries that as an open decision. Note whether the number moved;
as-you-type adds work to the keystroke path, so a change here would be new information.

- [ ] **Step 3: Record it**

- **§13.3** — state that `BlockTerminal` registers `createCompletionProvider()` on each
  core it creates and supplies `listDirectory`, and that this is what makes Phase 4 visible.
- **§14 Phase 4** — amend the landed note: the engine shipped 2026-08-30 with no consumer,
  and the wiring landed separately; add **"a human sees a dropdown in a shell pane"** to the
  accept criteria, since the original four could all pass while the feature did nothing.
- Update the Phase 4 plan's banner to point here.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers
git commit -m "spec: record the completions wiring, and what phase 4's criteria missed"
```

---

## Self-Review

**Spec coverage.** §4.1's `listDirectory` gets its first implementation (Task 1). §13.3's
"the renderer's job" gains the registration it was missing (Task 2). §10.1's dropdown
becomes reachable. §4.3 is respected: `frontend` imports the package by name, and the two
forbidden edges are untouched — Task 2 changes no file under `ts/editor` or
`ts/renderer-dom`.

**Warp fidelity.** Task 3 is the whole of it, and it rests on four citations read on
2026-08-31: the `CompletionsTrigger` enum, the two `AsYouType` call sites, Warp's own
comment on why as-you-type recalculates instead of filtering, and the separate keybinding
for explicit opening. The 60ms debounce is marked as ours, not Warp's, with its reason.

**What this plan does not do.** It does not make completions appear in an agent pane — the
editor is hidden on the alternate screen, which is what Warp does too. If the panes you use
are all agent panes, this feature stays invisible to you no matter what lands here, and that
is worth deciding before Task 1 rather than discovering at Task 4. It also does not touch
the `input-latency` gate, which is red for an unrelated reason (§9.5).

**Ordering risk.** Task 1 must precede Task 4: as-you-type is what would make an agent
pane flash a dropdown, and Task 1 is the guarantee that it cannot. Task 3 depends on Task 2 only for path completion; commands, subcommands
and flags all work with no host filesystem, so a reviewer can accept Task 2 on its own.
Task 3 is independent of both and could land first, but would then be untestable by hand.

**Type consistency.** `DirEntry` (name/isDirectory/isHidden) is `@operator/terminal-core`'s
existing type; the Rust `DirEntryDto` serialises to it via serde's default camelCase-free
naming — **verify the JSON keys match `DirEntry` exactly**, adding
`#[serde(rename_all = "camelCase")]` if they do not. That is the one place this plan is
most likely to fail silently, since a mismatched key yields `undefined` rather than an error.
