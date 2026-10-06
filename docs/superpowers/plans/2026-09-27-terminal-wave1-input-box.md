# Input Box: Shared History and Quick Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In a shell pane's input box, ↑ reaches commands run in every shell terminal, including terminals that are closed and runs from before a daemon or app restart, newest first, never the same command twice in a row, with commands that look like they hold a secret left out; and when a shell command fails in a way a rule recognises (a `git push` with no upstream, a mistyped git subcommand, a one-dash git option, a busy port), the input box shows the fix with a **Use** button and as ghost text — the fix goes into the box and nothing runs until the user presses Enter.

**Architecture:** The daemon already keeps every finished shell command durably: the capture supervisor records each block into SQLite `terminal_blocks` (`command`, `cwd`, `finished_at`, `exit_code`; `backend/internal/storage/sqlite/migrations/0092_terminal_blocks.sql:14-34`), and nothing deletes a closed terminal's rows (`DeleteTerminalBlocks` has no caller outside tests). A new query reads the newest 5,000 rows across all terminals, the `terminalblock` service keeps the newest distinct commands and drops any that `redact.Text` would mask, start with a space, carry control characters or exceed 4 KiB, and a new route `GET /api/v1/terminal-history` returns them oldest first. In `packages/terminal`, the editor gets a product-independent seam — `CommandHistorySource { entries(); subscribe(); refresh?() }` — that `HistoryModel` merges with the pane's own block commands (pane's own commands newest, then the shared timeline, like macOS Terminal's per-session history), keeping the recalled entry on screen when a refresh lands mid-walk. Quick fixes are a second seam: a host passes `QuickFixRule[]` (command-line regex, exit condition, a bottom/top output window, `fix(match) → string`); the editor evaluates rules once per newly finished block, validates the fix, and renders it above the prompt row and as ghost text, following Warp's command-correction behaviour (suggestion only into an empty input, accepted with →, ignored by typing). The package ships four starter rules ported from VS Code (MIT); Operator opts in by passing them and a history source from a renderer-wide store that fetches the route on first use, on window focus, 500 ms after any shell command finishes, and at the start of each ↑ walk.

**Tech Stack:** Go 1.25 (`backend`, sqlc 1.31.1, goose migrations, chi), TypeScript 5.9 + vitest 4.1.8 (`packages/terminal/ts/{core,editor,react,renderer-dom}`), React 19 + vitest (`frontend`), openapi-typescript (generated `frontend/src/api/schema.ts`), Playwright 1.60 (bench and the headless real check). No Rust, no vt-core, no wasm change, no shell script change.

**Spec:** docs/terminal/2026-09-27-terminal-wishlist.md (items 4, 5) and survey §6.8, §6.6

**Tree this plan was written and proven against:** `development` @ `611254eb3` ("docs(terminal): survey status marks, checked against the tree after the real-app run"). Every code block below was applied and run in a scratch worktree of that commit on 2026-09-27 (macOS arm64, Go 1.25.12, Node 25.9.0, zsh 5.9, bash 3.2, fish 4): TS suites `core` 180, `renderer-dom` 995, `react` 159 (was 156), `editor` 218 (was 186), `completions` 109; `check:boundaries` pass; `bench:feel` "PASS feel gate: zero pixel diff"; frontend `npm run typecheck` clean and `npm run test` 173 files / 1742 tests pass; backend `go test ./...` ok (after the two fake stores in Task 1 Step 5), `golangci-lint` 0 issues on the touched packages; `TestShellBlocksReachTheSharedCommandHistoryWithoutSecrets` pass for zsh, bash and fish; the headless check in Task 9 R1–R8 all PASS against an isolated daemon.

## Global Constraints

- Branch `terminal/wave1-input-box` from `origin/development` (use a separate worktree, e.g. `/Users/omaraly/development/AI/Operator-wave1-input-box`; memory "Never stash in the shared checkout"). Never commit to `development` or `master`, never merge, never force-push.
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a` or `git stash`.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- No comments in new code — Go, TS, TSX, CSS, SQL (user's global rule, `TERMINAL.md` §3.3). Existing comments stay.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, route, path or concept under `ts/`. The history source and the rule list come from the host; the package never fetches, never reads a shell history file (`scripts/check-boundaries.mjs:46,219-224` fails the build if `ts/editor/src` mentions `node:fs` or `*_history`), and ships only generic rules that a host must pass in.
- No file under `packages/terminal` may exceed 600 lines (`scripts/check-boundaries.mjs:42`, `npm run check:boundaries`). Planned sizes: `ts/editor/src/line-editor.ts` 575 → 555 (Task 3) → 581 (Task 5); `line-editor-dom.ts` 51 → 83; `history.ts` 56 → 106; `history.test.ts` 42 → 107; `editor-history.ts` new 77; `quick-fix.ts` new 85; `quick-fix-rules.ts` new 66; `quick-fix-offer.ts` new 82; `quick-fix.test.ts` new 92; `line-editor-history.test.ts` new 157; `line-editor-quick-fix.test.ts` new 113; `styles.css`/`styles.ts` 159 → 194; `ts/react/src/TerminalSurface.tsx` 515 → 541; `TerminalSurface.history.test.tsx` new 79; `ts/core/src/types.ts` 280 → 279. Do not add to `ts/renderer-dom/src/dom-block-renderer.ts` (598) or `ts/renderer-dom/src/styles.ts` (596) or `ts/core/src/terminal-core.ts` (599): this plan touches none of them.
- No vt-core change, so neither wasm artifact is rebuilt and `vt_host.wasm` must stay unchanged (`git status` shows nothing under `backend/internal/adapters/runtime/ptyhost/vtwasm/assets`). No shell script change, so the `shell/*.test.mjs` suites are not required (run them anyway in Task 8 if tmux is present; they must be unchanged).
- Backend follows `AGENTS.md`: the query lives in `backend/internal/storage/sqlite/queries/`, generated code is regenerated with `npm run sqlc` (never hand-edited), the migration is new (never edit a shipped one) and appended to the ledger `shippedMigrations`; the service depends on its own `Store` port (`internal/service/terminalblock/types.go`); the controller reuses the existing `ShellTerminalBlockHistory` dependency; DTOs live in `controllers/dto.go`; the spec entry lives in `apispec/specgen/build.go`; `npm run api` regenerates `openapi.yaml` and `frontend/src/api/schema.ts`, committed with the Go change. Error envelopes keep `requestId`.
- The migration number is **0120**. If another branch lands a `0120_*` first, renumber to the next free number in the file name, the ledger entry and every mention in this plan's commits (`TestMigrationVersionLedger` enforces the ledger).
- UI: the only new visible element is inside the terminal's input box, drawn by the package in the terminal palette (`DESIGN.md:36`, "the terminal keeps its own palette"); no Operator component or shadcn primitive is added. Visual reference is Warp (AGPL-3.0): behaviour only, no Warp code is copied. VS Code (MIT) regular expressions are ported with an attribution file.
- `bench:feel` must stay at zero pixel diff: no bench fixture contains `input-ready` (Plan 10 Global Constraints, `docs/superpowers/plans/2026-09-26-terminal-plan-10-shell-resize.md:28`), so the input box renders nothing in the benches. Never commit re-recorded baselines.
- New `TERMINAL.md` section: the next free `### 4.N` at the time of Task 9. The sibling wave-1 plans claim §4.51 (selection) and §4.52 (agent signals); this plan writes **§4.53** and Task 9 Step 1 says how to renumber.
- Docs and the report cite `file:line` or write "not known". A command that cannot run is reported as `not run: <reason>`, never as a pass.
- Before running the daemon or integration tests from a Claude session, strip `CLAUDE*` variables (memory "Scrub CLAUDE* env before running Operator dev"). Never stop the user's `tauri:dev` (memory "Stopping tauri:dev kills live sessions").
- **Amendment (2026-09-27):** the quick-fix on/off switch (Task 7.5) must not add a new prop or
  flag to `packages/terminal` — `findQuickFix(rules, input)` (Task 4, `quick-fix.ts`) already
  accepts an empty `rules` array and returns `null` for every block with no special case (it is a
  plain loop), so Operator gates the setting entirely on its own side by passing
  `DEFAULT_QUICK_FIX_RULES` or `[]` through the existing `quickFixRules` prop (Task 6). This keeps
  the package product-independent per `TERMINAL.md` §3.1 above: it never learns that an on/off
  setting exists.
- **Amendment (2026-09-27):** retention (Task 7.6) never deletes or clears a block whose
  `terminal_id` still has a row in `shell_terminals` — enforced in the `NOT IN (SELECT handle_id
  FROM shell_terminals)` clause of both new queries, not in Go, so no future caller can bypass it
  by skipping a check.
- **Amendment (2026-09-27):** migration `0121` (Task 7.6) is additive (`ALTER TABLE … ADD COLUMN`)
  per the existing "never edit a shipped migration" rule above; it must keep `TestMigrationVersionLedger`
  green the same way `0120` does.

## Review Focus

1. **A command holding a secret reaching another pane or the phone.** The route is served on the LAN listener too (`backend/internal/httpd/api.go:172` registers `shellTerms` with the app API). Expected: a command that `redact.Text` would mask (built-in shapes `backend/internal/redact/redact.go:36-43` plus the user's `redact-patterns.txt`), a command starting with a space (the shells' "leave this out of history" convention), a command with a control character, invalid UTF-8 or over 4 KiB never leaves the daemon; a pane's own commands stay in its own ↑ as today. Pinned by `TestRecentCommandsLeavesOutSecretsHiddenAndBrokenCommands` (Task 1) and the real-pty `TestShellBlocksReachTheSharedCommandHistoryWithoutSecrets` (zsh, bash, fish; Task 1), and Task 9 R4.
2. **↑ while a history fetch is in flight, or a refresh landing mid-walk.** The editor asks for a refresh at the start of every walk, so an answer usually lands while the user is still pressing ↑. Expected: the entry on screen stays on screen, ↑ continues to older entries, ↓ reaches the newly landed newer ones and finally the typed prefix; a new walk starts from the newest entry; one fetch at a time and one follow-up. Pinned by `HistoryModel` "keeps the entry on screen when shared history lands during a walk" and "starts a new walk from the newest entry" (Task 3), `LineEditor shared history` "keeps the recalled command when a refresh lands during the walk" and "asks the source to refresh once per walk" (Task 3), `createCommandHistoryStore` "runs one fetch at a time and one more after a refresh asked for during it" (Task 7).
3. **A multi-line command.** Commands are stored with their newlines (`cmd=` is percent-decoded by the mark scanner, `packages/terminal/go/marks/scanner.go:351,399`, and stored as it arrives by the assembler, `backend/internal/terminal/block_assembler.go:200-202`). Expected: it is kept by the daemon (newline and tab are allowed), sent as one JSON string, recalled whole into the box and submitted unchanged. Pinned by `TestRecentCommandsLeavesOutSecretsHiddenAndBrokenCommands` (keeps the `for … done` entry), `TestTerminalHistoryAPI_ReturnsCommandsOldestFirst`, `HistoryModel` "recalls a multi-line command whole", `LineEditor shared history` "recalls a multi-line shared command whole".
4. **A quick fix for a command the user already edited, or a fix that would overwrite typing.** Expected: the chip and the ghost show only while the box is empty and the line is owned; typing hides both and → then accepts nothing from the fix; **Use** is ignored if the box is not empty; once used (click or →) the fix is dismissed and never comes back for that block, even after the user edits it; a new command withdraws it; nothing is ever sent without Enter. Pinned by `LineEditor quick fixes` "hides the fix while the user types and never replaces what they typed", "does not bring an applied fix back after the user edits it", "withdraws the fix once the next command starts", "shows the fix … fills the box on click without sending", and Task 9 R6–R7.
5. **History from a different project, cwd or closed terminal; forged marks steering a fix.** Shared history is global by decision (a normal Mac terminal's history is per user, not per directory). Expected: commands from any terminal, any cwd and any closed terminal are returned, survive a store reopen (daemon restart), and a failed block that was already on screen when the pane mounted (a replay) offers no fix. Anything on the pty can print `OSC 7000;cmd=…` and output (survey §6.1, no nonce yet), so a captured branch name, subcommand or option must pass a narrow character class and a fix with a control character or newline is dropped. Pinned by `TestRecentCommandsSpansTerminalsOldestFirstWithoutRepeats` (three terminals, three cwds), `TestRecentCommandsSurvivesAClosedTerminal`, the integration test (close + reopen), `LineEditor quick fixes` "offers nothing for a failed block that was already there when the editor mounted", `findQuickFix` "drops a branch name a program could use to smuggle a second command" and "drops a fix with a control character or a newline, or one equal to the command".
6. **(Amendment 2026-09-27) The switch's on/off behavior and persistence.** Expected: the setting
   persists across a reload (`readStoredTerminalQuickFixesEnabled`, `localStorage` key
   `opr.terminal.quickFixesEnabled`, on by default); turning it off removes both the suggestion row
   and the ghost text (empty `quickFixRules`); turning it back on shows fixes again on the next
   finished block without a reload. Pinned by the three new `BlockTerminal.test.tsx` cases and the
   `GeneralSettingsSection.test.tsx` reload case (Task 7.5).
7. **(Amendment 2026-09-27) Retention cleanup's correctness, against a real SQLite store.**
   Expected: reclaimed bytes (raw output zeroed — measured directly against the row, since
   `ClearOldOrphanedRawOutput` itself returns only a row count) and reclaimed rows
   (`DeleteFullyClearedOrphanedBlocks`) are both exercised; `ListRecentTerminalCommands`
   (Task 1) still returns a cleaned terminal's commands until its row is actually deleted; a
   terminal that still has a `shell_terminals` row is never touched, even far past both grace
   periods. Pinned by `TestTickReclaimsRawOutputThenTheRowOnceTheDeleteGraceAlsoPasses`,
   `TestTickKeepsCommandHistoryOfARecentlyClearedTerminal`, `TestTickNeverTouchesARestorableTerminal`
   (Task 7.6).

---

## Design decisions (each one decided; evidence in brackets)

### What exists today

- ↑ in the input box walks `HistoryModel` (`packages/terminal/ts/editor/src/history.ts:1-56`, limit 1,000 at `:8`), which `LineEditor` rebuilds from **this core's blocks only** on every core change (`line-editor.ts:99-101` → `ingestHistory`, `:564-574`) and resets at every mount (`line-editor.ts:67`). The `HISTORY_LIMIT = 100` the brief mentions is not the editor's: it is the number of durable blocks a reopened shell pane replays (`frontend/src/renderer/hooks/useShellTerminalBlocks.ts:29,43`).
- A latent bug the redesign removes: `HistoryModel.ingest` calls `resetRecall()` on every call (`history.ts:21`) and `LineEditor` calls it on every core change, so any output while the user walks history (a background job, a branch mark) restarts the walk from the newest entry.
- The package design reserved this seam: "History is the package's, sourced from marks … persisted through an optional `HistoryStore` the host provides. The package MUST NOT read the user's `.zsh_history`" (`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md:1118-1123`). `HistoryStore` is declared (`ts/core/src/types.ts:277-280`, exported `index-browser.ts:20`) and used nowhere; this plan replaces it with `CommandHistorySource` in the editor package and deletes it.

### Decision 1 — the history source is the daemon's durable blocks, not the shell's history file

| Source | For | Against |
|---|---|---|
| **Daemon `terminal_blocks`** (chosen) | Already written for every standalone shell pane by the capture supervisor (`internal/service/terminalcapture/supervisor.go:80-97`, `blockRecorder` → `terminalblock.Service.Record`, `internal/service/terminalblock/service.go:26-32`; `Start` takes a `shellterm.ShellTerminalRecord`, `:100`); has `command`, `cwd`, `finished_at` (`migrations/0092_terminal_blocks.sql:14-34`); survives daemon and app restarts (SQLite under `~/.operator`); rows of closed terminals stay (`DeleteTerminalBlocks`, `store/terminal_block_store.go:77`, has no caller outside tests); the same for zsh, bash and fish; the daemon can apply its own redaction before anything leaves it; the phone can read the same route | Only commands run inside Operator; capped at 100 per terminal (`service.go:12`, `retainPerTerminal`); agent (`worker`) panes are not captured |
| `~/.zsh_history` / `~/.bash_history` / fish history | Includes Terminal.app and iTerm commands | Three formats (zsh extended/metafied, bash plain, fish YAML-like — VS Code needs a parser per shell, `vscode/src/vs/workbench/contrib/terminalContrib/history/common/history.ts:200-318`); written only at shell exit unless the user set `INC_APPEND_HISTORY`/`SHARE_HISTORY`; **Operator's own zsh panes likely do not write there**: the recipe exports `ZDOTDIR={{script}}.d` before `exec zsh` (`packages/terminal/go/bootstrap/recipes.json:4`) and restores the user's `ZDOTDIR` only inside the generated `.zshrc` (`go/bootstrap/bootstrap.go:164-166`), while macOS `/etc/zshrc:16` sets `HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history` before that runs — so, unless the user's `.zshrc` sets `HISTFILE`, zsh history goes to the generated directory (inferred from the startup order; not verified by running); the file is the user's and holds every secret they ever typed, with no redaction; the package spec forbids the package from reading it (above) |
| Browser `localStorage` per renderer | Trivial | Lost on reset, not on the phone, no redaction, `AGENTS.md` requires all state under `~/.operator` |

Reading the shell history file stays possible later as a host feature behind a setting (open decision 2); nothing in this plan precludes it.

### Decision 2 — ordering: this pane's own commands first, then the shared timeline

- Shared entries are ordered by `finished_at`; the pane's own commands (from its blocks, in block order) come after them, so ↑ gives the pane's newest command first, then everything else newest first. A new pane has no commands of its own, so its ↑ is the global timeline newest first — the wishlist's case ("↑ reaches commands run in other panes and before a restart").
- This is macOS Terminal's documented default: "save and restore the shell command history independently for each restored terminal session. It also merges commands into the global history for new sessions" (`/etc/zshrc_Apple_Terminal:74-77`), and Warp's model: a session sees the history from before it started plus its own session's commands (`warp/app/src/terminal/history.rs:828-887`, `collect_visible_commands_for_session`).
- Why not a strict global timeline by timestamp: the pane's own blocks carry no shell-reported time (`start_ms`/`end_ms` are not emitted by `packages/terminal/shell/{zsh.sh,bash.sh,fish.fish}` — grep finds none), so the core stamps them at feed time (`TERMINAL.md` §2 "BlockGrid clock"), and a reopened pane's replayed durable blocks all get the replay time. A timestamp merge would put a reopened pane's 100 replayed commands above every command other panes ran since. The daemon's `finished_at` is correct, but the pane-local entry is needed so ↑ immediately after a command recalls it before the daemon's record and the 500 ms refresh land. Open decision 1 offers the zsh `SHARE_HISTORY` alternative.
- Duplicates: global dedupe keeping the newest position (Warp dedupes the same way, `warp/app/src/terminal/history.rs:639` `dedupe_from_last`), which also guarantees "no duplicates in a row". The daemon dedupes too, so the route never returns a command twice.
- Prefix-filtered recall is unchanged (↑ with `git` typed walks only commands starting with `git`); ↓ past the newest now returns the typed prefix, as every shell does, instead of sticking on the newest entry.

### Decision 3 — secrets stay in the daemon

- Filter at the daemon with the daemon's own `redact.Text` (`backend/internal/redact/redact.go:51`), which applies the built-in shapes **and** the user's `redact-patterns.txt` (`redact/userpatterns.go:32`, `LoadUserPatterns`). The client-side pattern list is deliberately only the built-ins (`redact/jspatterns.go:28-31`), so filtering on the client would miss user patterns.
- A command that would be masked is **dropped**, not masked: a recalled `export TOKEN=[redacted]` would run and silently set the variable to the literal mask.
- Also dropped: a leading space (zsh `HIST_IGNORE_SPACE`, bash `HISTCONTROL=ignorespace` — users already use it to keep a command out of history), C0/C1 controls except newline and tab, invalid UTF-8, over 4,096 bytes.
- Known limit, written into §4.53: redaction catches shapes, not intent (`mysql -phunter2` is kept). A pane's own ↑ still has its own commands, secrets included, exactly as today and as the shell's own history.

### Decision 4 — caps

- Query: newest 5,000 rows across terminals (`recentCommandScan`), served by a new index `terminal_blocks_finished (finished_at DESC, terminal_id DESC, source_id DESC)` that matches the `ORDER BY` (checked with `EXPLAIN QUERY PLAN`: `SCAN terminal_blocks USING INDEX terminal_blocks_finished`, no temp B-tree; with only a `finished_at` index SQLite adds `USE TEMP B-TREE FOR ORDER BY`).
- Service: 500 distinct commands by default, 1,000 max (route `limit` 1..1000). Renderer asks for 1,000 (`TERMINAL_HISTORY_LIMIT`); the editor keeps 1,000 merged entries (`HistoryModel` default) and the pane's own commands up to 2,000 block ids.
- Retention is unchanged: 100 blocks per terminal. The history therefore holds the last 100 commands of each terminal ever opened; open decision 6 covers the unbounded growth of closed terminals' rows (pre-existing).

### Decision 5 — refresh, not push

The store refreshes on first subscriber, on window `focus`, 500 ms after any shell surface reports a finished block (`onBlockFinished`, debounced), and when the editor starts a walk (`CommandHistorySource.refresh`). No new mux channel: the existing terminal-block push is per handle (`backend/internal/terminal/manager.go:675-701`) and the renderer only subscribes to it for unloaded shells (`frontend/src/renderer/components/TerminalPane.tsx:388`). The walk-start refresh covers commands from another device (the phone).

### Decision 6 — quick fixes: the matcher and rules in the package, the rule list from the host

- `QuickFixRule { id, commandLine: RegExp, exit: "error" | "success" | "any", output?: { line, anchor, offset, length }, fix(match) → string | null }` follows VS Code's `ITerminalQuickFixInternalOptions` (`vscode/src/vs/workbench/contrib/terminalContrib/quickFix/browser/terminalQuickFixBuiltinActions.ts:27-62`) and its output window (`vscode/src/vs/platform/terminal/common/capabilities/commandDetection/terminalCommand.ts:157-200`, `getOutputMatch`: logical lines from the bottom, first match nearest the end). Deviation from the survey's proposal (§6.6: `onQuickFix` event, host owns actions): every fix here is a command for the input box, so the rule itself returns the command and the package needs no event; a host that wants other actions can pass its own rules later.
- Starter rules (`DEFAULT_QUICK_FIX_RULES`), regexes verbatim from VS Code (`terminalQuickFixBuiltinActions.ts:10-16`): `git-push-set-upstream` (`:147`), `git-similar` (`:27`), `git-two-dashes` (`:88`), `free-port` (`:115`, fix `kill $(lsof -t -iTCP:<port> -sTCP:LISTEN)`). Not ported: `gitFastForwardPull` (fires on success), `gitCreatePr` (opens a URL), PowerShell rules. Attribution: `ts/editor/src/VSCODE-QUICK-FIX-ATTRIBUTION.md` + `LICENSE-VSCODE-MIT`, the same pattern as `ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`.
- When: once per block that becomes the newest settled block while the editor is mounted; a block already settled at mount is marked seen (a replay offers nothing — the Plan 3/7 rule "never from loaded or replayed output", `TERMINAL.md` §4.34); cleared when a newer command starts; never on the alternate screen. Output is read once per candidate block with `core.readBlockOutput(id, { maxLines: 201 })` (`ts/core/src/terminal-core.ts:521-526`, head and tail 100 lines kept by `capLines`, `ts/core/src/compact-output.ts:62-71`), and only if a rule's command line and exit already match.
- Where and how it looks: in the input box, above the prompt row — "Suggested fix `<command>` [Use]" — plus the command as ghost text in the empty box, accepted with → or Ctrl+E like a history suggestion. This is Warp's command correction: generated on block completion (`warp/app/src/terminal/view.rs:15756-15800`), shown as the input's autosuggestion **only if the input is still empty** and announced as "Press right arrow to insert or keep editing to ignore" (`view.rs:15175-15215`), inserted by replacing the buffer (`view.rs:10189-10194`). The button is the wishlist's addition; its chip look reuses the prompt row's cwd/branch chip (`ts/editor/src/styles.css:99-107`: 1px `--terminal-block-border`, 4px radius) with `--terminal-ansi-3` (yellow) for the label. Not in the block header/footer: the block chrome lives in `ts/renderer-dom` whose renderer file is at 598 lines, and the fix belongs next to where it goes.
- Trust (survey §6.1): there is no nonce yet, so a program can forge `cmd=` and output. Mitigations: nothing runs without Enter, the whole command is shown, captures pass narrow classes (`BRANCH_NAME`, `GIT_SUBCOMMAND`, `OPTION_NAME`), `safeFix` drops controls/newlines, empty fixes, fixes over 1,024 characters and fixes equal to the failed command.

### Decision 7 — the phone

Unaffected: it has no line editor (`TERMINAL.md` §4.32 "a client without a line editor (the phone)"), its arrow keys go to the shell. It benefits later: `GET /api/v1/terminal-history` is served to a paired phone behind the bearer password (same group as `/shell-terminals`, whose raw, unredacted block output the phone can already read, `packages/mobile/lib/core/api/api_request_helpers/end_points.dart:31`), so a phone "recent commands" sheet needs no daemon work (open decision 7). No `packages/mobile` change here.

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `backend/internal/storage/sqlite/migrations/0120_terminal_blocks_finished_index.sql` (new) | 1 | index for the cross-terminal query |
| `backend/internal/storage/sqlite/migrate_burned_versions_test.go` | 1 | ledger entry 120 |
| `backend/internal/storage/sqlite/queries/terminal_blocks.sql`, `gen/terminal_blocks.sql.go` (generated) | 1 | `ListRecentTerminalCommands` |
| `backend/internal/domain/terminalblock.go` | 1 | `CommandRun` |
| `backend/internal/service/terminalblock/{types.go,history.go (new),history_test.go (new)}` | 1 | port method, `RecentCommands`, filter |
| `backend/internal/storage/sqlite/store/terminal_block_store.go` | 1 | adapter method |
| `backend/internal/service/terminalcapture/supervisor_test.go`, `backend/internal/adapters/runtime/parity/decision_sites_test.go` | 1 | fakes implement the port |
| `backend/internal/integration/shell_history_test.go` (new) | 1 | real pty, zsh/bash/fish, close + reopen |
| `backend/internal/httpd/controllers/{shell_terminals.go,dto.go,shell_terminals_test.go,terminal_history_test.go (new)}` | 2 | route, DTOs, tests |
| `backend/internal/httpd/apispec/specgen/build.go`, `apispec/openapi.yaml`, `frontend/src/api/schema.ts` (generated) | 2 | spec |
| `packages/terminal/ts/editor/src/{history.ts,history.test.ts,editor-history.ts (new),line-editor-dom.ts,line-editor.ts,line-editor-history.test.ts (new),index.ts}` | 3 | shared history seam |
| `packages/terminal/ts/core/src/{types.ts,index-browser.ts}` | 3, 5 | drop `HistoryStore`; two strings |
| `packages/terminal/ts/editor/src/{quick-fix.ts,quick-fix-rules.ts,quick-fix.test.ts,VSCODE-QUICK-FIX-ATTRIBUTION.md,LICENSE-VSCODE-MIT}` (new), `index.ts` | 4 | matcher, starter rules |
| `packages/terminal/ts/editor/src/{quick-fix-offer.ts (new),line-editor.ts,styles.css,styles.ts,line-editor-quick-fix.test.ts (new)}`, `ts/renderer-dom/src/{palette.test.ts,jump-to-bottom.test.ts}` | 5 | offer, chip, ghost, → |
| `packages/terminal/ts/react/src/{TerminalSurface.tsx,index.ts,TerminalSurface.history.test.tsx (new)}` | 6 | `commandHistory`, `quickFixRules` props |
| `frontend/src/renderer/lib/{command-history.ts,command-history.test.ts}` (new), `components/BlockTerminal.tsx`, `components/BlockTerminal.test.tsx`, `test/setup.ts` | 7 | Operator store and wiring |
| `frontend/src/renderer/lib/terminal-quick-fixes.ts` (new) | 7.5 | on/off setting storage, mirrors `terminal-predictive-echo.ts` |
| `frontend/src/renderer/stores/ui-store.ts`, `components/settings/GeneralSettingsSection.tsx`, `components/settings/GeneralSettingsSection.test.tsx`, `i18n/en.json`, `components/BlockTerminal.tsx`, `components/BlockTerminal.test.tsx` | 7.5 | switch UI, gate on `quickFixRules` |
| `backend/internal/storage/sqlite/migrations/0121_terminal_blocks_retention.sql` (new) | 7.6 | `raw_output_cleared_at` column |
| `backend/internal/storage/sqlite/migrate_burned_versions_test.go` | 7.6 | ledger entry 121 |
| `backend/internal/storage/sqlite/queries/terminal_blocks.sql`, `gen/terminal_blocks.sql.go` (generated) | 7.6 | `ClearOldOrphanedRawOutput`, `DeleteFullyClearedOrphanedBlocks` |
| `backend/internal/service/terminalblock/types.go`, `backend/internal/storage/sqlite/store/terminal_block_store.go` | 7.6 | widened port, adapter methods |
| `backend/internal/service/terminalcapture/supervisor_test.go`, `backend/internal/adapters/runtime/parity/decision_sites_test.go` | 7.6 | fakes implement the widened port (again) |
| `backend/internal/observe/blockretention/{retention.go,retention_test.go}` (new) | 7.6 | the janitor, shaped like `observe/reaper` |
| `backend/internal/daemon/lifecycle_wiring.go` | 7.6 | start the janitor with the reaper; `ReconcileBlockRetention` at boot |
| `TERMINAL.md`, `packages/terminal/CHANGELOG.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md` | 9 | §4.53, changelog, status lines, plus the switch and retention design |

---

### Task 0: Branch and baselines

**Files:** none changed.

**Interfaces:** Consumes nothing. Produces the baseline counts every later task compares against.

- [ ] **Step 1: Worktree on a new branch**

```bash
cd /Users/omaraly/development/AI/Operator && git fetch origin
git worktree add -b terminal/wave1-input-box /Users/omaraly/development/AI/Operator-wave1-input-box origin/development
cd /Users/omaraly/development/AI/Operator-wave1-input-box && git log --oneline -1
```
Expected: the new worktree at `origin/development`. If `git log` is not `611254eb3` or a descendant, stop and report.

- [ ] **Step 2: Install and build the TS packages in the worktree**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && npm ci && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend && npm ci
```
Expected: `build-wasm: … ready`, `tsc -b` silent.

- [ ] **Step 3: Record baselines**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal
for p in core renderer-dom react editor completions; do (cd ts/$p && echo "$p $(npx vitest run 2>&1 | grep -E 'Tests  ')"); done
npm run check:boundaries 2>&1 | tail -2
wc -l ts/editor/src/line-editor.ts ts/react/src/TerminalSurface.tsx ts/editor/src/line-editor-dom.ts ts/editor/src/history.ts
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/service/terminalblock/ ./internal/httpd/... ./internal/storage/sqlite/... -count=1 2>&1 | grep -v "no test files" | tail -8
```
Expected (planning run): `core 180`, `renderer-dom 995`, `react 156`, `editor 186`, `completions 109` passed; `boundary check passed`; `575`, `515`, `51`, `56` lines; every Go package `ok`. Write the numbers into the report; later tasks state their deltas against them.

- [ ] **Step 4: Confirm the fixtures never own the line**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && echo "count=$(grep -rl 'input-ready' bench/agent-session/fixtures | wc -l | tr -d ' ')"
```
Expected: `count=0`. If not 0, the input box renders in a bench fixture and `bench:feel` baselines may change; stop and report.

---

### Task 1: Backend — recent distinct commands across terminals, secrets left out

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0120_terminal_blocks_finished_index.sql`
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go:126` (append after the `119:` entry)
- Modify: `backend/internal/storage/sqlite/queries/terminal_blocks.sql:50` (append)
- Regenerate: `backend/internal/storage/sqlite/gen/terminal_blocks.sql.go`
- Modify: `backend/internal/domain/terminalblock.go:24` (append)
- Modify: `backend/internal/service/terminalblock/types.go:13`
- Modify: `backend/internal/storage/sqlite/store/terminal_block_store.go:84` (insert after `DeleteTerminalBlocks`)
- Modify: `backend/internal/service/terminalcapture/supervisor_test.go:206`, `backend/internal/adapters/runtime/parity/decision_sites_test.go:268-270`
- Create: `backend/internal/service/terminalblock/history.go`
- Test: `backend/internal/service/terminalblock/history_test.go` (new), `backend/internal/integration/shell_history_test.go` (new)

**Interfaces:**
- Consumes: `terminalblock.Service.Record` (`service.go:26`), `redact.Text(string) redact.Result` (`redact/redact.go:51`), test helpers `newService`, `sampleBlock` (`service/terminalblock/service_test.go:17-43`), integration harness `newShellBlocksHarnessIn`, `send`, `waitHistory`, fields `shells`, `blocks`, `store`, `dataDir`, `terminal` (`internal/integration/shell_blocks_tmux_test.go:82-196`), `sqlite.Open(dataDir)` (`storage/sqlite/db.go:58`).
- Produces: `domain.CommandRun{Command string; FinishedAt time.Time}`; `terminalblock.Store.ListRecentTerminalCommands(ctx, limit int) ([]domain.CommandRun, error)`; `(*store.Store).ListRecentTerminalCommands`; `gen.ListRecentTerminalCommandsRow{Command string; FinishedAt time.Time}` and `(*gen.Queries).ListRecentTerminalCommands(ctx, limit int64)`; `(*terminalblock.Service).RecentCommands(ctx, limit int) ([]domain.CommandRun, error)` — oldest first, distinct, newest occurrence's time; exported constants `terminalblock.DefaultRecentCommands = 500`, `terminalblock.MaxRecentCommands = 1000`. Task 2 consumes `RecentCommands` and `domain.CommandRun`.

- [ ] **Step 1: Write the failing service tests**

Create `backend/internal/service/terminalblock/history_test.go`:

```go
package terminalblock_test

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
)

func recordCommand(ctx context.Context, t *testing.T, svc *terminalblock.Service, terminalID, sourceID, command, cwd string, finishedAt time.Time) {
	t.Helper()
	b := sampleBlock(terminalID, sourceID, finishedAt)
	b.Command = command
	b.Cwd = cwd
	if err := svc.Record(ctx, b); err != nil {
		t.Fatalf("record %s/%s: %v", terminalID, sourceID, err)
	}
}

func commandsOf(runs []domain.CommandRun) []string {
	out := make([]string, 0, len(runs))
	for _, run := range runs {
		out = append(out, run.Command)
	}
	return out
}

func TestRecentCommandsSpansTerminalsOldestFirstWithoutRepeats(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(1000, 0).UTC()
	recordCommand(ctx, t, svc, "term-a", "1", "make build", "/repo/a", base)
	recordCommand(ctx, t, svc, "term-b", "1", "npm test", "/repo/b", base.Add(time.Second))
	recordCommand(ctx, t, svc, "term-a", "2", "make build", "/repo/a", base.Add(2*time.Second))
	recordCommand(ctx, t, svc, "term-c", "1", "git status", "/elsewhere", base.Add(3*time.Second))

	got, err := svc.RecentCommands(ctx, 10)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	want := []string{"npm test", "make build", "git status"}
	if fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
	if !got[1].FinishedAt.Equal(base.Add(2 * time.Second)) {
		t.Fatalf("make build finished at %v, want its newest run", got[1].FinishedAt)
	}
}

func TestRecentCommandsLeavesOutSecretsHiddenAndBrokenCommands(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(2000, 0).UTC()
	commands := []string{
		"export GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123",
		"curl -H 'Authorization: Bearer abcdefghijklmnop1234' https://x",
		"mysql --password=hunter2hunter2",
		" echo hidden by a leading space",
		"   ",
		"printf '\x1b]52;c;aGk=\x07'",
		strings.Repeat("x", 4097),
		"ls -la",
		"for f in a b; do\n  echo $f\ndone",
	}
	for i, command := range commands {
		recordCommand(ctx, t, svc, "term-a", fmt.Sprint(i), command, "/repo", base.Add(time.Duration(i)*time.Second))
	}

	got, err := svc.RecentCommands(ctx, 50)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	want := []string{"ls -la", "for f in a b; do\n  echo $f\ndone"}
	if fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}

func TestRecentCommandsKeepsTheNewestWithinTheLimit(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	base := time.Unix(3000, 0).UTC()
	for i := 0; i < 5; i++ {
		recordCommand(ctx, t, svc, "term-a", fmt.Sprint(i), fmt.Sprintf("cmd-%d", i), "/repo", base.Add(time.Duration(i)*time.Second))
	}

	got, err := svc.RecentCommands(ctx, 2)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	if want := []string{"cmd-3", "cmd-4"}; fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}

func TestRecentCommandsSurvivesAClosedTerminal(t *testing.T) {
	ctx := context.Background()
	svc, _ := newService(t)
	recordCommand(ctx, t, svc, "closed-term", "1", "cargo test", "/repo", time.Unix(4000, 0).UTC())

	got, err := svc.RecentCommands(ctx, 0)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	if want := []string{"cargo test"}; fmt.Sprint(commandsOf(got)) != fmt.Sprint(want) {
		t.Fatalf("commands = %q, want %q", commandsOf(got), want)
	}
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/service/terminalblock/ -run RecentCommands -count=1 2>&1 | head -5`
Expected: build failure, `svc.RecentCommands undefined (type *terminalblock.Service has no field or method RecentCommands)`.

- [ ] **Step 3: Migration, ledger, query, generated code**

Create `backend/internal/storage/sqlite/migrations/0120_terminal_blocks_finished_index.sql`:

```sql
-- +goose Up
-- +goose StatementBegin
CREATE INDEX terminal_blocks_finished
    ON terminal_blocks (finished_at DESC, terminal_id DESC, source_id DESC);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS terminal_blocks_finished;
-- +goose StatementEnd
```

In `backend/internal/storage/sqlite/migrate_burned_versions_test.go`, after line 126 (`119: "0119_session_launch_permission_mode.sql",`) add:

```go
	120: "0120_terminal_blocks_finished_index.sql",
```

Append to `backend/internal/storage/sqlite/queries/terminal_blocks.sql`:

```sql

-- name: ListRecentTerminalCommands :many
SELECT command, finished_at
FROM terminal_blocks
WHERE command <> ''
ORDER BY finished_at DESC, terminal_id DESC, source_id DESC
LIMIT ?;
```

(The `-- name:` line is sqlc's query annotation, not a comment; every query in the file has one.)

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box && npm run sqlc && git status --short backend/internal/storage/sqlite/gen`
Expected: only ` M backend/internal/storage/sqlite/gen/terminal_blocks.sql.go`, which now contains `type ListRecentTerminalCommandsRow struct { Command string; FinishedAt time.Time }` and `func (q *Queries) ListRecentTerminalCommands(ctx context.Context, limit int64) ([]ListRecentTerminalCommandsRow, error)`.

- [ ] **Step 4: Domain type, port, adapter, service**

Append to `backend/internal/domain/terminalblock.go` (after the `Block` struct, line 24):

```go

type CommandRun struct {
	Command    string
	FinishedAt time.Time
}
```

In `backend/internal/service/terminalblock/types.go`, after line 13 (`DeleteTerminalBlocks(context.Context, string) error`) add:

```go
	ListRecentTerminalCommands(context.Context, int) ([]domain.CommandRun, error)
```

In `backend/internal/storage/sqlite/store/terminal_block_store.go`, insert after `DeleteTerminalBlocks` (after line 84):

```go
func (s *Store) ListRecentTerminalCommands(ctx context.Context, limit int) ([]domain.CommandRun, error) {
	rows, err := s.qr.ListRecentTerminalCommands(ctx, int64(limit))
	if err != nil {
		return nil, fmt.Errorf("list recent terminal commands: %w", err)
	}
	out := make([]domain.CommandRun, 0, len(rows))
	for _, row := range rows {
		out = append(out, domain.CommandRun{Command: row.Command, FinishedAt: row.FinishedAt})
	}
	return out, nil
}

```

Create `backend/internal/service/terminalblock/history.go`:

```go
package terminalblock

import (
	"context"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

const (
	DefaultRecentCommands  = 500
	MaxRecentCommands      = 1000
	recentCommandScan      = 5000
	maxHistoryCommandBytes = 4096
)

func (s *Service) RecentCommands(ctx context.Context, limit int) ([]domain.CommandRun, error) {
	if limit <= 0 {
		limit = DefaultRecentCommands
	}
	limit = min(limit, MaxRecentCommands)
	runs, err := s.store.ListRecentTerminalCommands(ctx, recentCommandScan)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]struct{}, limit)
	out := make([]domain.CommandRun, 0, limit)
	for _, run := range runs {
		if len(out) == limit {
			break
		}
		if _, dup := seen[run.Command]; dup || !historyWorthy(run.Command) {
			continue
		}
		seen[run.Command] = struct{}{}
		out = append(out, run)
	}
	slices.Reverse(out)
	return out, nil
}

func historyWorthy(command string) bool {
	if len(command) > maxHistoryCommandBytes || !utf8.ValidString(command) {
		return false
	}
	if strings.TrimSpace(command) == "" || strings.HasPrefix(command, " ") {
		return false
	}
	for _, r := range command {
		if r == '\n' || r == '\t' {
			continue
		}
		if r < 0x20 || r == 0x7f || (r >= 0x80 && r < 0xa0) {
			return false
		}
	}
	return len(redact.Text(command).Spans) == 0
}
```

- [ ] **Step 5: The two test fakes implement the widened port**

`go test ./...` fails to build `internal/service/terminalcapture` without this (`supervisor_test.go:218,487` pass `*fakeBlockStore` as `terminalblock.Store`). In `backend/internal/service/terminalcapture/supervisor_test.go`, after line 206 (`func (f *fakeBlockStore) DeleteTerminalBlocks(…`) add:

```go
func (f *fakeBlockStore) ListRecentTerminalCommands(_ context.Context, _ int) ([]domain.CommandRun, error) {
	return nil, nil
}
```

In `backend/internal/adapters/runtime/parity/decision_sites_test.go`, after the `DeleteTerminalBlocks` method (lines 268-270) add:

```go
func (noopBlockStore) ListRecentTerminalCommands(ctx context.Context, limit int) ([]domain.CommandRun, error) {
	return nil, nil
}
```

(This package builds only with `-tags parity` and is already broken there at `decision_sites_test.go:98`, `realHostSpawner` vs `ptyhost.hostSpawner`, on `611254eb3` — not this plan's to fix; the method keeps the fake complete.)

- [ ] **Step 6: Run the service tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/service/terminalblock/ ./internal/service/terminalcapture/ ./internal/storage/sqlite/... -count=1 2>&1 | grep -v "no test files"`
Expected: every line `ok` (the ledger test `TestMigrationVersionLedger` included).

Evidence for Decision 4 (read-only, scratch DB):

```bash
cd "$(mktemp -d)" && sqlite3 eqp.db "$(sed -n '/CREATE TABLE terminal_blocks/,/^);/p' /Users/omaraly/development/AI/Operator-wave1-input-box/backend/internal/storage/sqlite/migrations/0092_terminal_blocks.sql) CREATE INDEX terminal_blocks_finished ON terminal_blocks (finished_at DESC, terminal_id DESC, source_id DESC); EXPLAIN QUERY PLAN SELECT command, finished_at FROM terminal_blocks WHERE command <> '' ORDER BY finished_at DESC, terminal_id DESC, source_id DESC LIMIT 5000;"
```
Expected: `SCAN terminal_blocks USING INDEX terminal_blocks_finished` and no `TEMP B-TREE` line.

- [ ] **Step 7: Real-pty integration test (zsh, bash, fish; close; reopen)**

Create `backend/internal/integration/shell_history_test.go`:

```go
//go:build !windows

package integration

import (
	"context"
	"fmt"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/service/terminalblock"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
)

func TestShellBlocksReachTheSharedCommandHistoryWithoutSecrets(t *testing.T) {
	for _, shell := range []string{"zsh", "bash", "fish"} {
		t.Run(shell, func(t *testing.T) {
			h := newShellBlocksHarnessIn(t, "run-history-"+shell, shell)
			h.send(t, "echo one")
			h.send(t, "export API_TOKEN=abcdefghijklmnop")
			h.send(t, "echo two")
			h.waitHistory(t, 3)

			ctx := context.Background()
			if err := h.shells.CloseShellTerminal(ctx, h.terminal.HandleID); err != nil {
				t.Fatalf("close shell terminal: %v", err)
			}
			h.terminal.HandleID = ""
			if err := h.store.Close(); err != nil {
				t.Fatalf("close store: %v", err)
			}
			reopened, err := sqlite.Open(h.dataDir)
			if err != nil {
				t.Fatalf("reopen store: %v", err)
			}
			h.store = reopened

			runs, err := terminalblock.NewService(reopened).RecentCommands(ctx, 10)
			if err != nil {
				t.Fatalf("recent commands: %v", err)
			}
			got := make([]string, 0, len(runs))
			for _, run := range runs {
				got = append(got, run.Command)
			}
			if want := []string{"echo one", "echo two"}; fmt.Sprint(got) != fmt.Sprint(want) {
				t.Fatalf("shared history = %q, want %q", got, want)
			}
		})
	}
}
```

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') go test ./internal/integration/ -run 'TestShellBlocksReachTheSharedCommandHistory' -count=1 -v 2>&1 | grep -E "^\s*--- |^ok|^FAIL"`
Expected: `--- PASS` for the parent and `zsh`, `bash`, `fish` (a missing shell prints `SKIP` via the harness's `t.Skip`; report it as `not run: <shell> unavailable`), then `ok`.

- [ ] **Step 8: Lint and commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && gofmt -l internal/ && go vet ./internal/service/... ./internal/storage/... ./internal/integration/ && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./internal/service/terminalblock/... ./internal/storage/sqlite/... ./internal/integration/... ./internal/domain/...
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add backend/internal/storage/sqlite/migrations/0120_terminal_blocks_finished_index.sql backend/internal/storage/sqlite/migrate_burned_versions_test.go backend/internal/storage/sqlite/queries/terminal_blocks.sql backend/internal/storage/sqlite/gen/terminal_blocks.sql.go backend/internal/domain/terminalblock.go backend/internal/service/terminalblock/types.go backend/internal/storage/sqlite/store/terminal_block_store.go backend/internal/service/terminalblock/history.go backend/internal/service/terminalblock/history_test.go backend/internal/service/terminalcapture/supervisor_test.go backend/internal/adapters/runtime/parity/decision_sites_test.go backend/internal/integration/shell_history_test.go
git commit -m "feat(backend): recent distinct shell commands across terminals, secrets left out

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `gofmt` prints nothing, `0 issues.`, one commit.

---

### Task 2: Backend — `GET /api/v1/terminal-history`

**Files:**
- Modify: `backend/internal/httpd/controllers/shell_terminals.go:21-24` (constants), `:35-37` (interface), `:47-53` (`Register`), insert a handler after `blocks` (after line 164)
- Modify: `backend/internal/httpd/controllers/dto.go:1287` (insert after `TerminalBlockView`)
- Modify: `backend/internal/httpd/apispec/specgen/build.go:300` (`schemaNames`), `:626-628` (query type), `:790` (operation)
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`
- Modify: `backend/internal/httpd/controllers/shell_terminals_test.go:70-81` (fake)
- Test: `backend/internal/httpd/controllers/terminal_history_test.go` (new)

**Interfaces:**
- Consumes: `(*terminalblock.Service).RecentCommands`, `domain.CommandRun` (Task 1); test helpers `newShellTerminalBlocksTestServer`, `newShellTerminalTestServer`, `fakeShellTerminalService`, `doRequest`, `assertJSON`, `mustJSON` (`controllers/shell_terminals_test.go:54-68`, `projects_test.go:527`).
- Produces: `controllers.ShellTerminalBlockHistory.RecentCommands(ctx, limit int) ([]domain.CommandRun, error)`; `controllers.TerminalHistoryEntry{Command string "command"; FinishedAt time.Time "finishedAt"}`; `controllers.TerminalHistoryResponse{Commands []TerminalHistoryEntry "commands"}`; route `GET /api/v1/terminal-history?limit=1..1000` (default 500) → `200 {"commands":[…]}` oldest first, `400 INVALID_QUERY`, `500` envelope, `501` without the service; operation id `listTerminalHistory`; generated TS `components["schemas"]["TerminalHistoryResponse"]`. Task 7 consumes the route through `apiClient.GET("/api/v1/terminal-history", …)`.

- [ ] **Step 1: Fake and failing tests**

In `backend/internal/httpd/controllers/shell_terminals_test.go`, replace the `fakeShellTerminalBlockHistory` struct (lines 70-75) and add a method after it:

```go
type fakeShellTerminalBlockHistory struct {
	gotTerminalID string
	gotLimit      int
	blocks        []domain.Block
	err           error
	recent        []domain.CommandRun
	gotRecent     int
}

func (f *fakeShellTerminalBlockHistory) RecentCommands(_ context.Context, limit int) ([]domain.CommandRun, error) {
	f.gotRecent = limit
	return f.recent, f.err
}
```

Create `backend/internal/httpd/controllers/terminal_history_test.go`:

```go
package controllers_test

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestTerminalHistoryAPI_ReturnsCommandsOldestFirst(t *testing.T) {
	finished := time.Date(2026, 9, 27, 10, 0, 0, 0, time.UTC)
	hist := &fakeShellTerminalBlockHistory{recent: []domain.CommandRun{
		{Command: "make build", FinishedAt: finished},
		{Command: "for f in a b; do\n  echo $f\ndone", FinishedAt: finished.Add(time.Minute)},
	}}
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, hist)

	body, status, hdr := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", status, body)
	}
	assertJSON(t, hdr)
	var got struct {
		Commands []struct {
			Command    string    `json:"command"`
			FinishedAt time.Time `json:"finishedAt"`
		} `json:"commands"`
	}
	mustJSON(t, body, &got)
	if len(got.Commands) != 2 || got.Commands[0].Command != "make build" || got.Commands[1].Command != "for f in a b; do\n  echo $f\ndone" {
		t.Fatalf("commands = %+v", got.Commands)
	}
	if !got.Commands[0].FinishedAt.Equal(finished) {
		t.Fatalf("finishedAt = %v, want %v", got.Commands[0].FinishedAt, finished)
	}
	if hist.gotRecent != 500 {
		t.Fatalf("default limit = %d, want 500", hist.gotRecent)
	}
}

func TestTerminalHistoryAPI_EmptyIsAnEmptyList(t *testing.T) {
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{})
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history?limit=10", "")
	if status != http.StatusOK || string(body) != "{\"commands\":[]}\n" {
		t.Fatalf("status = %d body = %q", status, body)
	}
}

func TestTerminalHistoryAPI_RejectsInvalidLimit(t *testing.T) {
	for _, raw := range []string{"abc", "0", "-3", "1001"} {
		srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{})
		body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history?limit="+raw, "")
		if status != http.StatusBadRequest {
			t.Fatalf("limit=%s status = %d, want 400; body=%s", raw, status, body)
		}
		var env struct {
			Code      string `json:"code"`
			RequestID string `json:"requestId"`
		}
		mustJSON(t, body, &env)
		if env.Code != "INVALID_QUERY" || env.RequestID == "" {
			t.Fatalf("limit=%s envelope = %+v", raw, env)
		}
	}
}

func TestTerminalHistoryAPI_StoreErrorKeepsTheEnvelope(t *testing.T) {
	srv := newShellTerminalBlocksTestServer(t, &fakeShellTerminalService{}, &fakeShellTerminalBlockHistory{err: errors.New("disk gone")})
	body, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", status, body)
	}
	var env struct {
		RequestID string `json:"requestId"`
	}
	mustJSON(t, body, &env)
	if env.RequestID == "" {
		t.Fatalf("envelope lost its requestId: %s", body)
	}
}

func TestTerminalHistoryAPI_NotImplementedWithoutHistoryService(t *testing.T) {
	srv := newShellTerminalTestServer(t, &fakeShellTerminalService{})
	_, status, _ := doRequest(t, srv, "GET", "/api/v1/terminal-history", "")
	if status != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501", status)
	}
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/httpd/controllers/ -run TerminalHistory -count=1 2>&1 | grep -E "^(---|ok|FAIL)|want" | head -8`
Expected: all five `--- FAIL`, each with `status = 404` and body code `ROUTE_NOT_FOUND` (`GET /api/v1/terminal-history has no handler`).

- [ ] **Step 3: DTOs, route, spec**

`backend/internal/httpd/controllers/dto.go`, after the `TerminalBlockView` struct (after line 1287):

```go

type TerminalHistoryEntry struct {
	Command    string    `json:"command"`
	FinishedAt time.Time `json:"finishedAt"`
}

type TerminalHistoryResponse struct {
	Commands []TerminalHistoryEntry `json:"commands"`
}
```

`backend/internal/httpd/controllers/shell_terminals.go` — apply this diff:

```diff
diff --git a/backend/internal/httpd/controllers/shell_terminals.go b/backend/internal/httpd/controllers/shell_terminals.go
--- a/backend/internal/httpd/controllers/shell_terminals.go
+++ b/backend/internal/httpd/controllers/shell_terminals.go
@@ -21,6 +21,8 @@ import (
 const (
 	defaultShellTerminalBlockLimit = 100
 	maxShellTerminalBlockLimit     = 500
+	defaultTerminalHistoryLimit    = 500
+	maxTerminalHistoryLimit        = 1000
 )
 
 // ShellTerminalService is the controller-facing standalone shell terminal
@@ -34,6 +36,7 @@ type ShellTerminalService interface {
 
 type ShellTerminalBlockHistory interface {
 	History(ctx context.Context, terminalID string, limit int) ([]domain.Block, error)
+	RecentCommands(ctx context.Context, limit int) ([]domain.CommandRun, error)
 }
 
 // ShellTerminalsController owns the /shell-terminals routes: standalone shells
@@ -50,6 +53,7 @@ func (c *ShellTerminalsController) Register(r chi.Router) {
 	r.Patch("/shell-terminals/{handleId}", c.rename)
 	r.Delete("/shell-terminals/{handleId}", c.close)
 	r.Get("/shell-terminals/{handleId}/blocks", c.blocks)
+	r.Get("/terminal-history", c.history)
 }
 
 func (c *ShellTerminalsController) list(w http.ResponseWriter, r *http.Request) {
@@ -163,6 +167,32 @@ func (c *ShellTerminalsController) blocks(w http.ResponseWriter, r *http.Request
 	envelope.WriteJSON(w, http.StatusOK, terminalBlockViews(blocks))
 }
 
+func (c *ShellTerminalsController) history(w http.ResponseWriter, r *http.Request) {
+	if c.Blocks == nil {
+		apispec.NotImplemented(w, r, "GET", "/api/v1/terminal-history")
+		return
+	}
+	limit := defaultTerminalHistoryLimit
+	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
+		n, err := strconv.Atoi(raw)
+		if err != nil || n < 1 || n > maxTerminalHistoryLimit {
+			envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", "limit must be an integer between 1 and 1000", nil)
+			return
+		}
+		limit = n
+	}
+	runs, err := c.Blocks.RecentCommands(r.Context(), limit)
+	if err != nil {
+		envelope.WriteError(w, r, err)
+		return
+	}
+	commands := make([]TerminalHistoryEntry, 0, len(runs))
+	for _, run := range runs {
+		commands = append(commands, TerminalHistoryEntry{Command: run.Command, FinishedAt: run.FinishedAt})
+	}
+	envelope.WriteJSON(w, http.StatusOK, TerminalHistoryResponse{Commands: commands})
+}
+
 func parseShellTerminalBlockLimit(w http.ResponseWriter, r *http.Request) (int, bool) {
 	raw := strings.TrimSpace(r.URL.Query().Get("limit"))
 	if raw == "" {
```

`backend/internal/httpd/apispec/specgen/build.go` — apply this diff:

```diff
diff --git a/backend/internal/httpd/apispec/specgen/build.go b/backend/internal/httpd/apispec/specgen/build.go
--- a/backend/internal/httpd/apispec/specgen/build.go
+++ b/backend/internal/httpd/apispec/specgen/build.go
@@ -298,6 +298,8 @@ var schemaNames = map[string]string{ //nolint:gosec // G101: schema type names s
 	"ControllersListShellTerminalsResponse": "ListShellTerminalsResponse",
 	"ControllersShellTerminalEnvelope":      "ShellTerminalEnvelope",
 	"ControllersTerminalBlockView":          "TerminalBlockView",
+	"ControllersTerminalHistoryEntry":       "TerminalHistoryEntry",
+	"ControllersTerminalHistoryResponse":    "TerminalHistoryResponse",
 	"ControllersClaudeAccountView":          "ClaudeAccountView",
 	"ControllersClaudeAccountStatus":        "ClaudeAccountStatus",
 	"ControllersListClaudeAccountsResponse": "ListClaudeAccountsResponse",
@@ -627,6 +629,10 @@ type shellTerminalBlocksQuery struct {
 	Limit *int64 `query:"limit,omitempty" minimum:"1" maximum:"500" description:"Maximum blocks to return, oldest first. Defaults to 100."`
 }
 
+type terminalHistoryQuery struct {
+	Limit *int64 `query:"limit,omitempty" minimum:"1" maximum:"1000" description:"Maximum distinct commands to return, oldest first. Defaults to 500."`
+}
+
 type claudeAccountsListQuery struct {
 	Refresh *int64 `query:"refresh,omitempty" minimum:"1" maximum:"1" description:"Set to 1 to bypass the 30-second login status cache."`
 }
@@ -788,6 +794,17 @@ func shellTerminalOperations() []operation {
 				{http.StatusNotImplemented, envelope.APIError{}},
 			},
 		},
+		{
+			method: http.MethodGet, path: "/api/v1/terminal-history", id: "listTerminalHistory", tag: "shellTerminals",
+			summary:    "Read recent distinct shell commands from every terminal, oldest first, leaving out commands that look like they hold a secret",
+			pathParams: []any{terminalHistoryQuery{}},
+			resps: []respUnit{
+				{http.StatusOK, controllers.TerminalHistoryResponse{}},
+				{http.StatusBadRequest, envelope.APIError{}},
+				{http.StatusInternalServerError, envelope.APIError{}},
+				{http.StatusNotImplemented, envelope.APIError{}},
+			},
+		},
 		{
 			method: http.MethodGet, path: "/api/v1/claude-accounts", id: "listClaudeAccounts", tag: "claudeAccounts",
 			summary:    "List Claude accounts, default first, with login status and shared setup state",
```

Regenerate:

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box && npm run api
git status --short backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
grep -n '"/api/v1/terminal-history"\|TerminalHistoryResponse: {' frontend/src/api/schema.ts
```
Expected: both files modified; `schema.ts` has the path and `TerminalHistoryResponse: { commands: components["schemas"]["TerminalHistoryEntry"][]; }` with `finishedAt: string` (`Format: date-time`).

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/httpd/... -count=1 2>&1 | grep -v "no test files"`
Expected: every package `ok`, including `apispec` (`TestRouteSpecParity`, spec drift).

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && gofmt -l internal/httpd && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./internal/httpd/...
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add backend/internal/httpd/controllers/shell_terminals.go backend/internal/httpd/controllers/dto.go backend/internal/httpd/controllers/shell_terminals_test.go backend/internal/httpd/controllers/terminal_history_test.go backend/internal/httpd/apispec/specgen/build.go backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(api): GET /api/v1/terminal-history serves the shared shell command history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Editor — shared history seam, pane-first merge, walks that survive a refresh

**Files:**
- Modify: `packages/terminal/ts/editor/src/history.ts:1-56` (rewrite)
- Modify: `packages/terminal/ts/editor/src/history.test.ts:1-42` (rewrite)
- Create: `packages/terminal/ts/editor/src/editor-history.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor-dom.ts:1` and append after `:51`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts:14-21` (imports), `:36-37` (fields), `:67-68` (mount), `:144`, `:153-155` (new setter), `:175-177` (dispose), `:305-347` (walk ends), `:365-370` (history), `:397`, `:402`, `:426`, `:455-487` (render), `:560`, `:568` — as one patch
- Modify: `packages/terminal/ts/editor/src/index.ts:17`
- Modify: `packages/terminal/ts/core/src/types.ts:277-280` (delete `HistoryStore`), `packages/terminal/ts/core/src/index-browser.ts:20`
- Test: `packages/terminal/ts/editor/src/line-editor-history.test.ts` (new)

**Interfaces:**
- Consumes: `BlockView` (`ts/core/src/types.ts:9-23`), `decodeBlocks`, `LineEditor` internals `visible`, `staleWhileHidden`, `render()` (`line-editor.ts:54-55,439`), `tokenize` (`highlight.ts`), `appendRange`, `createCaret` (`line-editor-dom.ts:4,31`).
- Produces (all exported from `@operator/terminal-editor` except `EditorHistory` and `renderBufferRows`):
  - `type CommandHistoryEntry = Readonly<{ command: string; at: number }>` (`at` = epoch ms);
  - `type CommandHistorySource = Readonly<{ entries(): readonly CommandHistoryEntry[]; subscribe(listener: () => void): () => void; refresh?(): void }>`;
  - `HistoryModel`: `setLocal(commands: readonly string[])`, `setShared(entries: readonly CommandHistoryEntry[])`, `suggest(prefix)`, `startRecall(prefix)`, `step(direction: -1 | 1): string | null` (returns the prefix after the newest), `endRecall()`, `entries()`; `ingest`/`recall` are removed;
  - `EditorHistory(changed: () => void)`: `setSource`, `ingest(blocks)`, `recall(text, direction)`, `endWalk()`, `suggest`, `entries`, `reset`, `dispose`;
  - `renderBufferRows(text, lines, cursor, ghost: string | null): HTMLElement[]`;
  - `LineEditor.setHistorySource(source: CommandHistorySource | null): void`.
  - Removed: `HistoryStore` from `@operator/terminal-core`.
  Task 5 extends `LineEditor`; Task 6 passes a source through `TerminalSurface`.

- [ ] **Step 1: Write the failing tests**

Replace `packages/terminal/ts/editor/src/history.test.ts` with:

```ts
import { describe, expect, it } from "vitest";
import { HistoryModel } from "./history";

describe("HistoryModel", () => {
	it("suggests the most recent entry that extends the prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["git status", "git commit -m wip", "ls"]);
		expect(history.suggest("git ")).toBe("git commit -m wip");
	});

	it("returns null when nothing matches", () => {
		const history = new HistoryModel();
		history.setLocal(["ls"]);
		expect(history.suggest("zzz")).toBeNull();
	});

	it("never suggests for an empty prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["rm -rf build"]);
		expect(history.suggest("")).toBeNull();
	});

	it("keeps the most recent occurrence when a command repeats", () => {
		const history = new HistoryModel();
		history.setLocal(["ls", "cd /", "ls"]);
		expect(history.entries()).toEqual(["cd /", "ls"]);
	});

	it("walks back and forward through matching entries and returns to the typed prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["git a", "git b", "git c"]);
		history.startRecall("git");
		expect(history.step(-1)).toBe("git c");
		expect(history.step(-1)).toBe("git b");
		expect(history.step(1)).toBe("git c");
		expect(history.step(1)).toBe("git");
	});

	it("stays on the oldest entry when stepping past it", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b"]);
		history.startRecall("");
		expect([history.step(-1), history.step(-1), history.step(-1)]).toEqual(["b", "a", "a"]);
	});

	it("drops the oldest entries past the limit", () => {
		const history = new HistoryModel(2);
		history.setLocal(["a", "b", "c"]);
		expect(history.entries()).toEqual(["b", "c"]);
	});

	it("orders shared entries by time and puts this pane's own commands after them, without repeats", () => {
		const history = new HistoryModel();
		history.setShared([
			{ command: "ls", at: 30 },
			{ command: "make", at: 10 },
			{ command: "npm test", at: 50 },
		]);
		history.setLocal(["ls", "git push"]);
		expect(history.entries()).toEqual(["make", "npm test", "ls", "git push"]);
	});

	it("keeps the entry on screen when shared history lands during a walk", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b", "c"]);
		history.startRecall("");
		expect(history.step(-1)).toBe("c");
		expect(history.step(-1)).toBe("b");
		history.setShared([
			{ command: "old", at: 1 },
			{ command: "newer", at: 100 },
		]);
		expect(history.step(-1)).toBe("a");
		expect(history.step(-1)).toBe("newer");
		expect(history.step(-1)).toBe("old");
		expect(history.step(1)).toBe("newer");
		expect(history.step(1)).toBe("a");
		expect(history.step(1)).toBe("b");
	});

	it("starts a new walk from the newest entry", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b", "c"]);
		history.startRecall("");
		history.step(-1);
		history.step(-1);
		history.endRecall();
		history.startRecall("");
		expect(history.step(-1)).toBe("c");
	});

	it("does not rebuild when the same entries arrive again", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b"]);
		history.startRecall("");
		expect(history.step(-1)).toBe("b");
		history.setLocal(["a", "b"]);
		expect(history.step(-1)).toBe("a");
	});

	it("recalls a multi-line command whole", () => {
		const history = new HistoryModel();
		history.setShared([{ command: "for f in *; do\n  echo $f\ndone", at: 5 }]);
		history.startRecall("");
		expect(history.step(-1)).toBe("for f in *; do\n  echo $f\ndone");
	});
});
```

Create `packages/terminal/ts/editor/src/line-editor-history.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import type { CommandHistoryEntry, CommandHistorySource } from "./history";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const block = (cmd: string) =>
	`\x1b]133;A\x07\x1b]7000;v=1;cmd=${encodeURIComponent(cmd)}\x07\x1b]133;C\x07ok\r\n\x1b]133;D;0\x07`;

beforeAll(async () => {
	const bytes = await readFile(join(process.cwd(), "../core/wasm/vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function fakeSource(initial: CommandHistoryEntry[]) {
	let entries = initial;
	const listeners = new Set<() => void>();
	let refreshes = 0;
	const source: CommandHistorySource = {
		entries: () => entries,
		subscribe: (listener) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
		refresh: () => {
			refreshes += 1;
		},
	};
	return {
		source,
		refreshes: () => refreshes,
		listeners: () => listeners.size,
		land(next: CommandHistoryEntry[]) {
			entries = next;
			for (const listener of [...listeners]) listener();
		},
	};
}

function mount() {
	const sent: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: () => {} };
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	return { editor, core, sent, container };
}

function recall(editor: LineEditor, presses: number): void {
	for (let index = 0; index < presses; index += 1) editor.handleKey(key({ key: "ArrowUp" }));
}

describe("LineEditor shared history", () => {
	it("reaches commands from other terminals and earlier runs, newest first", () => {
		const { editor, core, sent } = mount();
		const shared = fakeSource([
			{ command: "make build", at: 1 },
			{ command: "npm test", at: 2 },
		]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["make build"]);
	});

	it("puts this pane's newer commands ahead of older shared ones and never repeats one", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([
			{ command: "ls", at: 1 },
			{ command: "make", at: 2 },
		]).source);
		core.feed(encode(block("ls") + READY));
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["make"]);
	});

	it("asks the source to refresh once per walk", () => {
		const { editor, core } = mount();
		const shared = fakeSource([{ command: "a", at: 1 }]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 3);
		editor.handleKey(key({ key: "ArrowDown" }));
		expect(shared.refreshes()).toBe(1);
		editor.handleKey(key({ key: "x" }));
		recall(editor, 1);
		expect(shared.refreshes()).toBe(2);
	});

	it("walks this pane's own commands before commands another pane ran later", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([{ command: "cargo build", at: Date.now() + 60_000 }]).source);
		core.feed(encode(block("ls") + READY));
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls"]);
		recall(editor, 2);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls", "cargo build"]);
	});

	it("keeps the recalled command when a refresh lands during the walk", () => {
		const { editor, core, sent } = mount();
		const shared = fakeSource([
			{ command: "one", at: 1 },
			{ command: "two", at: 2 },
		]);
		editor.setHistorySource(shared.source);
		core.feed(encode(READY));
		recall(editor, 1);
		shared.land([
			{ command: "one", at: 1 },
			{ command: "two", at: 2 },
			{ command: "three", at: 3 },
		]);
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["one"]);
	});

	it("recalls a multi-line shared command whole", () => {
		const { editor, core, sent } = mount();
		editor.setHistorySource(fakeSource([{ command: "for f in a b; do\n  echo $f\ndone", at: 1 }]).source);
		core.feed(encode(READY));
		recall(editor, 1);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["for f in a b; do\n  echo $f\ndone"]);
	});

	it("suggests from shared history as ghost text", () => {
		const { editor, core, container } = mount();
		editor.setHistorySource(fakeSource([{ command: "docker compose up", at: 1 }]).source);
		core.feed(encode(READY));
		editor.setText("docker c");
		expect(container.querySelector(".terminal-editor-ghost")?.textContent).toBe("ompose up");
	});

	it("drops its subscription when the source changes or the editor is disposed", () => {
		const { editor } = mount();
		const first = fakeSource([]);
		const second = fakeSource([]);
		editor.setHistorySource(first.source);
		editor.setHistorySource(second.source);
		expect(first.listeners()).toBe(0);
		expect(second.listeners()).toBe(1);
		editor.dispose();
		expect(second.listeners()).toBe(0);
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal/ts/editor && npx vitest run src/history.test.ts src/line-editor-history.test.ts 2>&1 | grep -E "TypeError|Tests  " | sort | uniq -c | head`
Expected (planning run): `10 TypeError: history.setLocal is not a function`, `2 TypeError: history.setShared is not a function`, `8 TypeError: editor.setHistorySource is not a function`, `Tests  20 failed (20)`.

- [ ] **Step 3: The model**

Replace `packages/terminal/ts/editor/src/history.ts` with:

```ts
export type CommandHistoryEntry = Readonly<{ command: string; at: number }>;

export type CommandHistorySource = Readonly<{
	entries(): readonly CommandHistoryEntry[];
	subscribe(listener: () => void): () => void;
	refresh?(): void;
}>;

function sameEntries(a: readonly CommandHistoryEntry[], b: readonly CommandHistoryEntry[]): boolean {
	if (a.length !== b.length) return false;
	for (let index = 0; index < a.length; index += 1) {
		if (a[index]!.command !== b[index]!.command || a[index]!.at !== b[index]!.at) return false;
	}
	return true;
}

function sameCommands(a: readonly string[], b: readonly string[]): boolean {
	return a.length === b.length && a.every((command, index) => command === b[index]);
}

export class HistoryModel {
	private readonly limit: number;
	private local: readonly string[] = [];
	private shared: readonly CommandHistoryEntry[] = [];
	private values: string[] = [];
	private recallPrefix: string | null = null;
	private recallMatches: string[] = [];
	private recallIndex = 0;

	constructor(limit = 1000) {
		this.limit = Math.max(0, Math.floor(limit));
	}

	setLocal(commands: readonly string[]): void {
		if (sameCommands(this.local, commands)) return;
		this.local = [...commands];
		this.rebuild();
	}

	setShared(entries: readonly CommandHistoryEntry[]): void {
		if (sameEntries(this.shared, entries)) return;
		this.shared = [...entries];
		this.rebuild();
	}

	suggest(prefix: string): string | null {
		if (prefix.length === 0) return null;
		for (let index = this.values.length - 1; index >= 0; index -= 1) {
			const entry = this.values[index]!;
			if (entry.length > prefix.length && entry.startsWith(prefix)) return entry;
		}
		return null;
	}

	startRecall(prefix: string): void {
		this.recallPrefix = prefix;
		this.recallMatches = this.matching(prefix);
		this.recallIndex = this.recallMatches.length;
	}

	step(direction: -1 | 1): string | null {
		if (this.recallPrefix === null || this.recallMatches.length === 0) return null;
		const next = this.recallIndex + direction;
		if (next < 0) return this.recallMatches[this.recallIndex] ?? null;
		if (next >= this.recallMatches.length) {
			this.recallIndex = this.recallMatches.length;
			return this.recallPrefix;
		}
		this.recallIndex = next;
		return this.recallMatches[next] ?? null;
	}

	endRecall(): void {
		this.recallPrefix = null;
		this.recallMatches = [];
		this.recallIndex = 0;
	}

	entries(): readonly string[] {
		return [...this.values];
	}

	private matching(prefix: string): string[] {
		return this.values.filter((entry) => entry.startsWith(prefix));
	}

	private rebuild(): void {
		const shared = this.shared.map((entry, order) => ({ entry, order }));
		shared.sort((a, b) => a.entry.at - b.entry.at || a.order - b.order);
		const merged = [...shared.map(({ entry }) => entry.command), ...this.local];
		const seen = new Set<string>();
		const newestFirst: string[] = [];
		for (let index = merged.length - 1; index >= 0 && newestFirst.length < this.limit; index -= 1) {
			const command = merged[index]!;
			if (command.length === 0 || seen.has(command)) continue;
			seen.add(command);
			newestFirst.push(command);
		}
		this.values = newestFirst.reverse();
		if (this.recallPrefix === null) return;
		const current = this.recallMatches[this.recallIndex];
		this.recallMatches = this.matching(this.recallPrefix);
		const kept = current === undefined ? -1 : this.recallMatches.lastIndexOf(current);
		this.recallIndex = kept === -1 ? this.recallMatches.length : kept;
	}
}
```

Create `packages/terminal/ts/editor/src/editor-history.ts`:

```ts
import type { BlockView } from "@operator/terminal-core";
import { HistoryModel, type CommandHistorySource } from "./history.js";

const LOCAL_LIMIT = 2000;

export class EditorHistory {
	private readonly model = new HistoryModel();
	private readonly local = new Map<string, string>();
	private source: CommandHistorySource | null = null;
	private unsubscribe: (() => void) | null = null;
	private walking = false;

	constructor(private readonly changed: () => void) {}

	setSource(source: CommandHistorySource | null): void {
		if (source === this.source) return;
		this.unsubscribe?.();
		this.unsubscribe = null;
		this.source = source;
		this.model.setShared(source?.entries() ?? []);
		if (!source) return;
		this.unsubscribe = source.subscribe(() => {
			if (this.source !== source) return;
			this.model.setShared(source.entries());
			this.changed();
		});
	}

	ingest(blocks: readonly BlockView[]): void {
		let changed = false;
		for (const block of blocks) {
			if (block.command.length === 0 || this.local.get(block.id) === block.command) continue;
			this.local.set(block.id, block.command);
			changed = true;
		}
		if (!changed) return;
		for (const id of this.local.keys()) {
			if (this.local.size <= LOCAL_LIMIT) break;
			this.local.delete(id);
		}
		this.model.setLocal([...this.local.values()]);
	}

	recall(text: string, direction: -1 | 1): string | null {
		if (!this.walking) {
			this.walking = true;
			this.model.startRecall(text);
			this.source?.refresh?.();
		}
		return this.model.step(direction);
	}

	endWalk(): void {
		if (!this.walking) return;
		this.walking = false;
		this.model.endRecall();
	}

	suggest(prefix: string): string | null {
		return this.model.suggest(prefix);
	}

	entries(): readonly string[] {
		return this.model.entries();
	}

	reset(): void {
		this.endWalk();
		this.local.clear();
		this.model.setLocal([]);
	}

	dispose(): void {
		this.setSource(null);
		this.reset();
	}
}
```

- [ ] **Step 4: Move the buffer rows out of `LineEditor`, wire the seam**

`packages/terminal/ts/editor/src/line-editor-dom.ts` — apply (the body is `line-editor.ts:455-487` moved unchanged, with the ghost passed in):

```diff
diff --git a/packages/terminal/ts/editor/src/line-editor-dom.ts b/packages/terminal/ts/editor/src/line-editor-dom.ts
--- a/packages/terminal/ts/editor/src/line-editor-dom.ts
+++ b/packages/terminal/ts/editor/src/line-editor-dom.ts
@@ -1,4 +1,4 @@
-import type { TokenKind } from "./highlight.js";
+import { tokenize, type TokenKind } from "./highlight.js";
 import { editorStyles } from "./styles.js";
 
 export function appendRange(
@@ -49,3 +49,35 @@ export function ensurePackageStyleTag(): void {
 	tag.textContent = editorStyles;
 	document.head.append(tag);
 }
+
+export function renderBufferRows(text: string, lines: readonly string[], cursor: number, ghost: string | null): HTMLElement[] {
+	const tokens = tokenize(text);
+	let offset = 0;
+	const nodes = lines.map((line) => {
+		const row = document.createElement("div");
+		row.className = "terminal-editor-line";
+		const lineStart = offset;
+		const lineEnd = lineStart + line.length;
+		let position = lineStart;
+		for (const token of tokens) {
+			const start = Math.max(token.start, lineStart);
+			const end = Math.min(token.end, lineEnd);
+			if (start >= end) continue;
+			appendRange(row, text, position, start, null, cursor);
+			appendRange(row, text, start, end, token.kind, cursor);
+			position = end;
+		}
+		appendRange(row, text, position, lineEnd, null, cursor);
+		if (cursor === lineEnd) row.append(createCaret());
+		else if (!row.hasChildNodes()) row.append(document.createTextNode("\u00a0"));
+		offset = lineEnd + 1;
+		return row;
+	});
+	if (ghost !== null && cursor === text.length) {
+		const span = document.createElement("span");
+		span.className = "terminal-editor-ghost";
+		span.textContent = ghost;
+		nodes[nodes.length - 1]?.append(span);
+	}
+	return nodes;
+}
```

`packages/terminal/ts/editor/src/line-editor.ts` — save this patch as `/tmp/claude-501/wave1-input-box-le1.patch` (or any scratch path) and run `git apply --check` then `git apply` on it from the worktree root:

```diff
--- a/packages/terminal/ts/editor/src/line-editor.ts
+++ b/packages/terminal/ts/editor/src/line-editor.ts
@@ -11,14 +11,14 @@
 } from "@operator/terminal-core";
 import { EditorBuffer } from "./buffer.js";
 import { CompletionsDropdown } from "./completions-dropdown.js";
-import { tokenize } from "./highlight.js";
-import { HistoryModel } from "./history.js";
+import { EditorHistory } from "./editor-history.js";
+import type { CommandHistorySource } from "./history.js";
 import { encodeKey } from "./encode-key.js";
 import { clipboardHasImage, deliverPaste, planPaste, type PasteConfirm } from "./paste.js";
 import { mapKey, type EditorCommand } from "./keymap.js";
 import { renderPromptRow } from "./prompt-row.js";
 import { ReverseSearch } from "./reverse-search.js";
-import { appendRange, createCaret, ensurePackageStyleTag } from "./line-editor-dom.js";
+import { ensurePackageStyleTag, renderBufferRows } from "./line-editor-dom.js";
 import { CLEAR_SHELL_LINE, TypeaheadGate } from "./typeahead.js";
 
 const INTERRUPT = "\x03";
@@ -33,8 +33,7 @@
 
 export class LineEditor {
 	private readonly buffer = new EditorBuffer();
-	private history = new HistoryModel();
-	private historyPrefix: string | null = null;
+	private readonly history = new EditorHistory(() => this.historyChanged());
 	private readonly search = new ReverseSearch();
 	private searchOpen = false;
 	private readonly dropdown = new CompletionsDropdown();
@@ -64,8 +63,6 @@
 		ensurePackageStyleTag();
 		this.core = core;
 		this.host = host;
-		this.history = new HistoryModel();
-		this.historyPrefix = null;
 		this.promptCwd = "";
 		this.promptBranch = "";
 		this.promptExitCode = null;
@@ -141,7 +138,7 @@
 
 	setText(text: string): void {
 		this.buffer.setText(text);
-		this.historyPrefix = null;
+		this.history.endWalk();
 		this.render();
 	}
 
@@ -154,6 +151,11 @@
 		this.pasteConfirm = confirm;
 	}
 
+	setHistorySource(source: CommandHistorySource | null): void {
+		this.history.setSource(source);
+		this.render();
+	}
+
 	setVisible(visible: boolean): void {
 		this.visible = visible;
 		if (!visible || !this.staleWhileHidden) return;
@@ -174,6 +176,7 @@
 		this.unsubscribe = null;
 		this.unsubscribeCompletions?.();
 		this.unsubscribeCompletions = null;
+		this.history.dispose();
 		this.dropdown.dispose();
 		this.dropdownOpen = false;
 		this.composition?.dispose();
@@ -302,49 +305,49 @@
 		switch (command.kind) {
 			case "insert":
 				this.buffer.insert(command.text);
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "newline":
 				this.buffer.insert("\n");
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "submit":
 				if (wasDropdownOpen) {
 					this.applySelectedCompletion();
-					this.historyPrefix = null;
+					this.history.endWalk();
 					this.render();
 					return;
 				}
 				host.send(this.buffer.text);
 				this.buffer.clear();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "delete-backward":
 				this.buffer.deleteBackward();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "delete-forward":
 				this.buffer.deleteForward();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "delete-word-backward":
 				this.buffer.deleteWordBackward();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "delete-line-backward":
 				this.buffer.deleteToLineStart();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "delete-line-forward":
 				this.buffer.deleteToLineEnd();
-				this.historyPrefix = null;
+				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
 			case "move":
@@ -363,8 +366,7 @@
 				this.buffer.moveEnd();
 				break;
 			case "history": {
-				this.historyPrefix ??= this.buffer.text;
-				const recalled = this.history.recall(this.historyPrefix, command.direction);
+				const recalled = this.history.recall(this.buffer.text, command.direction);
 				if (recalled !== null) this.buffer.setText(recalled);
 				break;
 			}
@@ -394,12 +396,20 @@
 	private acceptSuggestion(): void {
 		const suggestion = this.history.suggest(this.buffer.text);
 		if (suggestion !== null) this.buffer.setText(suggestion);
-		this.historyPrefix = null;
+		this.history.endWalk();
+	}
+
+	private historyChanged(): void {
+		if (!this.visible) {
+			this.staleWhileHidden = true;
+			return;
+		}
+		this.render();
 	}
 
 	private discardLine(): void {
 		this.buffer.clear();
-		this.historyPrefix = null;
+		this.history.endWalk();
 		this.cancelDropdownIfOpen();
 		this.render();
 	}
@@ -423,7 +433,7 @@
 		const insertion = selected.value;
 		const cursor = before.length + insertion.length;
 		this.buffer.setText(before + insertion + after, cursor);
-		this.historyPrefix = null;
+		this.history.endWalk();
 		if (insertion.endsWith("/")) {
 			this.core?.requestCompletions(this.buffer.text, this.buffer.cursor);
 		}
@@ -452,39 +462,9 @@
 			content.replaceChildren();
 			return;
 		}
-		const cursor = this.buffer.cursor;
-		const lines = this.buffer.lines();
-		const tokens = tokenize(this.buffer.text);
-		let offset = 0;
-		const nodes: HTMLElement[] = lines.map((text) => {
-			const row = document.createElement("div");
-			row.className = "terminal-editor-line";
-			const lineStart = offset;
-			const lineEnd = lineStart + text.length;
-			let position = lineStart;
-			for (const token of tokens) {
-				const start = Math.max(token.start, lineStart);
-				const end = Math.min(token.end, lineEnd);
-				if (start >= end) continue;
-				appendRange(row, this.buffer.text, position, start, null, cursor);
-				appendRange(row, this.buffer.text, start, end, token.kind, cursor);
-				position = end;
-			}
-			appendRange(row, this.buffer.text, position, lineEnd, null, cursor);
-			if (cursor === lineEnd) row.append(createCaret());
-			else if (!row.hasChildNodes()) row.append(document.createTextNode("\u00a0"));
-			offset = lineEnd + 1;
-			return row;
-		});
-		if (cursor === this.buffer.text.length) {
-			const suggestion = this.history.suggest(this.buffer.text);
-			if (suggestion !== null) {
-				const ghost = document.createElement("span");
-				ghost.className = "terminal-editor-ghost";
-				ghost.textContent = suggestion.slice(this.buffer.text.length);
-				nodes[nodes.length - 1]?.append(ghost);
-			}
-		}
+		const text = this.buffer.text;
+		const ghost = this.history.suggest(text)?.slice(text.length) ?? null;
+		const nodes = renderBufferRows(text, this.buffer.lines(), this.buffer.cursor, ghost);
 		if (this.searchOpen) {
 			const state = this.search.state();
 			const search = document.createElement("div");
@@ -557,7 +537,7 @@
 		const tail = text.slice(head.length);
 		const cursor = this.buffer.cursor;
 		this.buffer.setText(head + typed + tail, cursor >= head.length ? cursor + typed.length : cursor);
-		this.historyPrefix = null;
+		this.history.endWalk();
 		this.host?.sendRaw(CLEAR_SHELL_LINE);
 	}
 
@@ -565,7 +545,7 @@
 		const core = this.core;
 		if (!core) return;
 		const blocks = decodeBlocks(core.snapshot());
-		this.history.ingest(blocks.map((block) => block.command).filter((command) => command.length > 0));
+		this.history.ingest(blocks);
 		const newest = blocks.at(-1);
 		this.promptCwd = newest?.cwd ?? "";
 		this.promptBranch = newest?.gitBranch ?? "";
```

`packages/terminal/ts/editor/src/index.ts` line 17 becomes:

```ts
export { HistoryModel, type CommandHistoryEntry, type CommandHistorySource } from "./history.js";
```

`packages/terminal/ts/core/src/types.ts`: delete lines 276-280 (the blank line and `export type HistoryStore = { load(): …; save(…): …; };`). `packages/terminal/ts/core/src/index-browser.ts`: delete line 20 (`	HistoryStore,`).

- [ ] **Step 5: Run to see them pass, build, boundaries**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && npm run build:ts 2>&1 | grep -i error; (cd ts/editor && npx vitest run 2>&1 | grep -E "Tests  ")
npm run check:boundaries 2>&1 | tail -2; wc -l ts/editor/src/line-editor.ts ts/editor/src/line-editor-dom.ts ts/editor/src/history.ts ts/editor/src/editor-history.ts
grep -rn "HistoryStore" ts/*/src | grep -v node_modules; echo "HistoryStore refs: $?"
```
Expected: no `error`; `Tests  200 passed (200)` (186 − 6 old `HistoryModel` tests + 12 + 8); `boundary check passed`; `555`, `83`, `106`, `77`; `HistoryStore refs: 1` (grep found nothing).

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add packages/terminal/ts/editor/src/history.ts packages/terminal/ts/editor/src/history.test.ts packages/terminal/ts/editor/src/editor-history.ts packages/terminal/ts/editor/src/line-editor-dom.ts packages/terminal/ts/editor/src/line-editor.ts packages/terminal/ts/editor/src/line-editor-history.test.ts packages/terminal/ts/editor/src/index.ts packages/terminal/ts/core/src/types.ts packages/terminal/ts/core/src/index-browser.ts
git commit -m "feat(editor): shared command history through a host history source

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Editor — quick-fix matcher and the starter rules

**Files:**
- Create: `packages/terminal/ts/editor/src/quick-fix.ts`, `packages/terminal/ts/editor/src/quick-fix-rules.ts`
- Create: `packages/terminal/ts/editor/src/VSCODE-QUICK-FIX-ATTRIBUTION.md`, `packages/terminal/ts/editor/src/LICENSE-VSCODE-MIT` (copy of `ts/core/src/LICENSE-VSCODE-MIT`)
- Modify: `packages/terminal/ts/editor/src/index.ts:17` (two lines after it)
- Test: `packages/terminal/ts/editor/src/quick-fix.test.ts` (new)

**Interfaces:**
- Consumes: nothing from the core (pure functions over strings).
- Produces (exported from `@operator/terminal-editor`): `type QuickFixOutputMatcher = { line: RegExp; anchor: "top" | "bottom"; offset: number; length: number }`; `type QuickFixMatch = { command; commandMatch: RegExpMatchArray; outputMatch: RegExpMatchArray | null; outputLines: readonly string[]; lineIndex: number }`; `type QuickFixRule = { id; commandLine: RegExp; exit: "error" | "success" | "any"; output?: QuickFixOutputMatcher; fix(match): string | null }`; `type QuickFix = { ruleId: string; command: string }`; `type QuickFixInput = { command; exitCode: number | null; output(): readonly string[] }`; `findQuickFix(rules, input): QuickFix | null`; `QUICK_FIX_WINDOW_LIMIT = 100` (not exported from the index); `safeFix(fix, original)` (module export for tests); rules `gitPushSetUpstream`, `gitSimilar`, `gitTwoDashes`, `freePort`, `DEFAULT_QUICK_FIX_RULES`. Task 5 consumes `findQuickFix`, `QUICK_FIX_WINDOW_LIMIT`, `QuickFix`, `QuickFixRule`.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/ts/editor/src/quick-fix.test.ts` (the push output is VS Code's macOS fixture from `terminalQuickFixBuiltinActions.ts:163-170`, the port message is Node's own):

```ts
import { describe, expect, it } from "vitest";
import { findQuickFix, safeFix, type QuickFixRule } from "./quick-fix";
import { DEFAULT_QUICK_FIX_RULES, freePort, gitPushSetUpstream, gitSimilar, gitTwoDashes } from "./quick-fix-rules";

const input = (command: string, exitCode: number | null, output: string) => ({
	command,
	exitCode,
	output: () => output.split("\n"),
});

const PUSH_NO_UPSTREAM = [
	"fatal: The current branch feature/login has no upstream branch.",
	"To push the current branch and set the remote as upstream, use",
	"",
	"    git push --set-upstream origin feature/login",
	"",
	"To have this happen automatically for branches without a tracking",
	"upstream, see 'push.autoSetupRemote' in 'git help config'.",
	"",
].join("\n");

describe("findQuickFix", () => {
	it("offers the set-upstream push for a push with no upstream", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", 128, PUSH_NO_UPSTREAM))).toEqual({
			ruleId: "git-push-set-upstream",
			command: "git push --set-upstream origin feature/login",
		});
	});

	it("offers nothing when the command succeeded", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", 0, PUSH_NO_UPSTREAM))).toBeNull();
	});

	it("offers nothing when the exit status is unknown", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", null, PUSH_NO_UPSTREAM))).toBeNull();
	});

	it("offers nothing when the line is above the bottom window", () => {
		const padded = `${PUSH_NO_UPSTREAM}\n${Array.from({ length: 20 }, (_, index) => `line ${index}`).join("\n")}`;
		expect(findQuickFix([gitPushSetUpstream], input("git push", 1, padded))).toBeNull();
	});

	it("offers the similar git subcommand", () => {
		const output = "git: 'stauts' is not a git command. See 'git --help'.\n\nThe most similar command is\n\tstatus";
		expect(findQuickFix([gitSimilar], input("git stauts -s", 1, output))?.command).toBe("git status -s");
	});

	it("offers the two-dash option", () => {
		const output = "error: did you mean `--amend` (with two dashes)?";
		expect(findQuickFix([gitTwoDashes], input("git commit -amend", 129, output))?.command).toBe("git commit --amend");
	});

	it("offers to free a port that is in use", () => {
		const output = "Error: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle";
		expect(findQuickFix([freePort], input("npm run dev", 1, output))?.command).toBe(
			"kill $(lsof -t -iTCP:3000 -sTCP:LISTEN)",
		);
	});

	it("reads the output only for a rule whose command line and exit match", () => {
		let reads = 0;
		const result = findQuickFix(DEFAULT_QUICK_FIX_RULES, {
			command: "ls",
			exitCode: 0,
			output: () => {
				reads += 1;
				return [];
			},
		});
		expect(result).toBeNull();
		expect(reads).toBe(0);
	});

	it("drops a branch name a program could use to smuggle a second command", () => {
		const forged = "    git push --set-upstream origin x;curl${IFS}evil|sh";
		expect(findQuickFix([gitPushSetUpstream], input("git push", 1, forged))).toBeNull();
	});

	it("drops a fix with a control character or a newline, or one equal to the command", () => {
		const rule: QuickFixRule = { id: "echo", commandLine: /.+/, exit: "any", fix: ({ command }) => `${command}\nrm -rf ~` };
		expect(findQuickFix([rule], input("ls", 1, ""))).toBeNull();
		expect(safeFix("ls\x1b[2J", "x")).toBeNull();
		expect(safeFix(" ls ", "ls")).toBeNull();
		expect(safeFix("ls -la", "ls")).toBe("ls -la");
	});

	it("takes the first rule that produces a fix", () => {
		const first: QuickFixRule = { id: "first", commandLine: /make/, exit: "error", fix: () => null };
		const second: QuickFixRule = { id: "second", commandLine: /make/, exit: "error", fix: () => "make clean" };
		expect(findQuickFix([first, second], input("make", 2, ""))?.ruleId).toBe("second");
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal/ts/editor && npx vitest run src/quick-fix.test.ts 2>&1 | grep -E "Failed to resolve|Error" | head -2`
Expected: `Failed to resolve import "./quick-fix"`.

- [ ] **Step 3: Implement**

Create `packages/terminal/ts/editor/src/quick-fix.ts`:

```ts
export type QuickFixOutputMatcher = Readonly<{
	line: RegExp;
	anchor: "top" | "bottom";
	offset: number;
	length: number;
}>;

export type QuickFixMatch = Readonly<{
	command: string;
	commandMatch: RegExpMatchArray;
	outputMatch: RegExpMatchArray | null;
	outputLines: readonly string[];
	lineIndex: number;
}>;

export type QuickFixRule = Readonly<{
	id: string;
	commandLine: RegExp;
	exit: "error" | "success" | "any";
	output?: QuickFixOutputMatcher;
	fix(match: QuickFixMatch): string | null;
}>;

export type QuickFix = Readonly<{ ruleId: string; command: string }>;

export type QuickFixInput = Readonly<{
	command: string;
	exitCode: number | null;
	output(): readonly string[];
}>;

export const QUICK_FIX_WINDOW_LIMIT = 100;
const MAX_FIX_LENGTH = 1024;

function exitMatches(rule: QuickFixRule, exitCode: number | null): boolean {
	if (rule.exit === "any") return true;
	if (exitCode === null) return false;
	return rule.exit === "error" ? exitCode !== 0 : exitCode === 0;
}

function outputWindow(lines: readonly string[], matcher: QuickFixOutputMatcher): string[] {
	const offset = Math.max(0, Math.min(matcher.offset, QUICK_FIX_WINDOW_LIMIT));
	const length = Math.max(0, Math.min(matcher.length, QUICK_FIX_WINDOW_LIMIT - offset));
	if (matcher.anchor === "top") return lines.slice(offset, offset + length);
	const end = Math.max(0, lines.length - offset);
	return lines.slice(Math.max(0, end - length), end);
}

export function safeFix(fix: string | null, original: string): string | null {
	if (fix === null) return null;
	const trimmed = fix.trim();
	if (trimmed.length === 0 || trimmed.length > MAX_FIX_LENGTH || trimmed === original.trim()) return null;
	for (const character of trimmed) {
		const code = character.codePointAt(0)!;
		if (code < 0x20 || code === 0x7f || (code >= 0x80 && code < 0xa0)) return null;
	}
	return trimmed;
}

export function findQuickFix(rules: readonly QuickFixRule[], input: QuickFixInput): QuickFix | null {
	let lines: readonly string[] | null = null;
	for (const rule of rules) {
		const commandMatch = input.command.match(rule.commandLine);
		if (!commandMatch || !exitMatches(rule, input.exitCode)) continue;
		let outputMatch: RegExpMatchArray | null = null;
		let outputLines: readonly string[] = [];
		let lineIndex = -1;
		if (rule.output) {
			lines ??= input.output();
			outputLines = outputWindow(lines, rule.output);
			for (let index = outputLines.length - 1; index >= 0; index -= 1) {
				const match = outputLines[index]!.match(rule.output.line);
				if (match) {
					outputMatch = match;
					lineIndex = index;
					break;
				}
			}
			if (!outputMatch) continue;
		}
		const command = safeFix(rule.fix({ command: input.command, commandMatch, outputMatch, outputLines, lineIndex }), input.command);
		if (command !== null) return { ruleId: rule.id, command };
	}
	return null;
}
```

Create `packages/terminal/ts/editor/src/quick-fix-rules.ts`:

```ts
import type { QuickFixRule } from "./quick-fix.js";

const GIT_COMMAND_LINE = /git/;
const GIT_PUSH_COMMAND_LINE = /git\s+push/;
const GIT_SIMILAR_OUTPUT = /(?:(most similar commands? (is|are)))/;
const GIT_TWO_DASHES_OUTPUT = /error: did you mean `--(.+)` \(with two dashes\)\?/;
const GIT_PUSH_OUTPUT = /git push --set-upstream origin (?<branchName>[^\s]+)/;
const FREE_PORT_OUTPUT = /(?:address already in use (?:0\.0\.0\.0|127\.0\.0\.1|localhost|::):|Unable to bind [^ ]*:|can't listen on port |listen EADDRINUSE [^ ]*:)(?<portNumber>\d{4,5})/;

const BRANCH_NAME = /^[A-Za-z0-9._/@+-]+$/;
const GIT_SUBCOMMAND = /^[a-z][a-z0-9-]*$/;
const OPTION_NAME = /^[a-z][a-z0-9-]*$/;

export const gitPushSetUpstream: QuickFixRule = {
	id: "git-push-set-upstream",
	commandLine: GIT_PUSH_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_PUSH_OUTPUT, anchor: "bottom", offset: 0, length: 8 },
	fix: ({ outputMatch }) => {
		const branch = outputMatch?.groups?.branchName;
		return branch && BRANCH_NAME.test(branch) ? `git push --set-upstream origin ${branch}` : null;
	},
};

export const gitSimilar: QuickFixRule = {
	id: "git-similar",
	commandLine: GIT_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_SIMILAR_OUTPUT, anchor: "bottom", offset: 0, length: 10 },
	fix: ({ command, outputLines, lineIndex }) => {
		const suggestion = outputLines.slice(lineIndex + 1).map((line) => line.trim()).find((line) => line.length > 0);
		if (!suggestion || !GIT_SUBCOMMAND.test(suggestion)) return null;
		return command.replace(/git\s+[^\s]+/, () => `git ${suggestion}`);
	},
};

export const gitTwoDashes: QuickFixRule = {
	id: "git-two-dashes",
	commandLine: GIT_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_TWO_DASHES_OUTPUT, anchor: "bottom", offset: 0, length: 2 },
	fix: ({ command, outputMatch }) => {
		const option = outputMatch?.[1];
		if (!option || !OPTION_NAME.test(option)) return null;
		const fixed = command.replace(` -${option}`, () => ` --${option}`);
		return fixed === command ? null : fixed;
	},
};

export const freePort: QuickFixRule = {
	id: "free-port",
	commandLine: /.+/,
	exit: "error",
	output: { line: FREE_PORT_OUTPUT, anchor: "bottom", offset: 0, length: 30 },
	fix: ({ outputMatch }) => {
		const port = outputMatch?.groups?.portNumber;
		return port ? `kill $(lsof -t -iTCP:${port} -sTCP:LISTEN)` : null;
	},
};

export const DEFAULT_QUICK_FIX_RULES: readonly QuickFixRule[] = Object.freeze([
	gitPushSetUpstream,
	gitSimilar,
	gitTwoDashes,
	freePort,
]);
```

Create `packages/terminal/ts/editor/src/VSCODE-QUICK-FIX-ATTRIBUTION.md`:

```markdown
# Quick-fix rules

`quick-fix-rules.ts` ports the output and command-line regular expressions of
four built-in terminal quick fixes from
`src/vs/workbench/contrib/terminalContrib/quickFix/browser/terminalQuickFixBuiltinActions.ts`
in Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file):
`gitSimilar`, `gitTwoDashes`, `freePort` and `gitPushSetUpstream`, with their
output windows (anchor, offset, length) and exit condition.

Changes made in the port, and nothing else:

- The expressions `GitCommandLineRegex`, `GitPushCommandLineRegex`,
  `GitSimilarOutputRegex`, `GitTwoDashesRegex`, `FreePortOutputRegex` and
  `GitPushOutputRegex` are kept verbatim.
- Every fix is a command placed in the line editor; none runs. VS Code runs
  the git fixes (`shouldExecute: true`) and frees a port through its own
  process API; here the port fix is the command
  `kill $(lsof -t -iTCP:<port> -sTCP:LISTEN)`.
- The captured branch name, subcommand and option are checked against a
  narrow character class before they are placed in a command, and a fix
  with a control character or a line break is dropped (`safeFix`).
- `gitFastForwardPull`, `gitCreatePr` and the PowerShell rules are not
  ported: they fire on success, open a URL, or target a shell this package
  does not integrate.
- The matcher (`quick-fix.ts`) is written for this package; it follows the
  behaviour of VS Code's `getOutputMatch` window (last lines of the output,
  `anchor: 'bottom'`) but copies no code from it.
```

Copy the licence: `cp packages/terminal/ts/core/src/LICENSE-VSCODE-MIT packages/terminal/ts/editor/src/LICENSE-VSCODE-MIT`.

In `packages/terminal/ts/editor/src/index.ts`, after the history export (line 17) add:

```ts
export { findQuickFix, type QuickFix, type QuickFixInput, type QuickFixMatch, type QuickFixOutputMatcher, type QuickFixRule } from "./quick-fix.js";
export { DEFAULT_QUICK_FIX_RULES, freePort, gitPushSetUpstream, gitSimilar, gitTwoDashes } from "./quick-fix-rules.js";
```

- [ ] **Step 4: Run to see it pass**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal/ts/editor && npx vitest run 2>&1 | grep -E "Tests  "`
Expected: `Tests  211 passed (211)`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add packages/terminal/ts/editor/src/quick-fix.ts packages/terminal/ts/editor/src/quick-fix-rules.ts packages/terminal/ts/editor/src/quick-fix.test.ts packages/terminal/ts/editor/src/VSCODE-QUICK-FIX-ATTRIBUTION.md packages/terminal/ts/editor/src/LICENSE-VSCODE-MIT packages/terminal/ts/editor/src/index.ts
git commit -m "feat(editor): quick-fix matcher and four starter rules ported from VS Code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Editor — the fix in the input box (chip, ghost, →, Use)

**Files:**
- Create: `packages/terminal/ts/editor/src/quick-fix-offer.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` (Task 3's result, 555 lines) — one patch, hunks at Task-3 lines `:19-24` (imports), `:34-39` (field), `:63-68` (mount), `:156-161` (setter), `:177-182` (dispose), `:322-327` (submit), `:394-402` (`acceptSuggestion` + new `useQuickFix`), `:463-469` and `:486-491` (render: ghost and chip), `:546-551` (`ingestHistory` → `observe`)
- Modify: `packages/terminal/ts/editor/src/styles.css:159`, `packages/terminal/ts/editor/src/styles.ts:159` (append the same rules)
- Modify: `packages/terminal/ts/core/src/types.ts:214` and `:240` (two strings each)
- Modify: `packages/terminal/ts/renderer-dom/src/palette.test.ts:28`, `packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts:28` (full `TerminalStrings` literals)
- Test: `packages/terminal/ts/editor/src/line-editor-quick-fix.test.ts` (new)

**Interfaces:**
- Consumes: `findQuickFix`, `QUICK_FIX_WINDOW_LIMIT`, `QuickFix`, `QuickFixRule` (Task 4); `TerminalCore.readBlockOutput(id, { maxLines })` (`ts/core/src/terminal-core.ts:521`), `snapshot().altScreen`, `decodeBlocks`, `lineEditorState()`; `LineEditor.focus()`, `cancelDropdownIfOpen()`, `history.endWalk()` (Task 3).
- Produces: `QuickFixOffer` (`setRules`, `reset(core)`, `observe(core)`, `fix()`, `dismiss()`), `renderQuickFixRow(fix, label, useLabel, use): HTMLElement` (DOM: `.terminal-editor-quick-fix[data-quick-fix=<ruleId>]` > `.terminal-editor-quick-fix-label`, `.terminal-editor-quick-fix-command`, `button.terminal-editor-quick-fix-use`); `LineEditor.setQuickFixRules(rules: readonly QuickFixRule[]): void`; `TerminalStrings.quickFixLabel` (default "Suggested fix") and `TerminalStrings.quickFixUse` (default "Use"). Task 6 passes rules through `TerminalSurface`; Task 7 translates the two strings.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/ts/editor/src/line-editor-quick-fix.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import { DEFAULT_QUICK_FIX_RULES } from "./quick-fix-rules";

const encode = (text: string) => new TextEncoder().encode(text);
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const PUSH_OUTPUT = [
	"fatal: The current branch feat has no upstream branch.",
	"To push the current branch and set the remote as upstream, use",
	"",
	"    git push --set-upstream origin feat",
	"",
].join("\r\n");
const run = (cmd: string, output: string, exit: number) =>
	`\x1b]133;A\x07\x1b]7000;v=1;cmd=${encodeURIComponent(cmd)}\x07\x1b]133;C\x07${output}\r\n\x1b]133;D;${exit}\x07`;
const FIX = "git push --set-upstream origin feat";

beforeAll(async () => {
	const bytes = await readFile(join(process.cwd(), "../core/wasm/vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function mount(rules = DEFAULT_QUICK_FIX_RULES) {
	const sent: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: () => {} };
	const core = createTerminalCore({ columns: 80, scrollback: 200 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	document.body.append(container);
	editor.mount(container, core, host);
	editor.setQuickFixRules(rules);
	return { editor, core, sent, container };
}

const row = (container: HTMLElement) => container.querySelector<HTMLElement>(".terminal-editor-quick-fix");
const useButton = (container: HTMLElement) => container.querySelector<HTMLButtonElement>(".terminal-editor-quick-fix-use");

describe("LineEditor quick fixes", () => {
	it("shows the fix for a failed push above the prompt and fills the box on click without sending", () => {
		const { core, container, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 128) + READY));
		expect(row(container)?.dataset.quickFix).toBe("git-push-set-upstream");
		expect(row(container)?.textContent).toContain(FIX);
		expect(container.querySelector(".terminal-editor-ghost")?.textContent).toBe(FIX);
		useButton(container)!.click();
		expect(sent).toEqual([]);
		expect(row(container)).toBeNull();
		expect(container.querySelector(".terminal-editor-content")?.textContent).toContain(FIX);
	});

	it("accepts the fix with ArrowRight in an empty box and runs it only on Enter", () => {
		const { editor, core, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		editor.handleKey(key({ key: "ArrowRight" }));
		expect(sent).toEqual([]);
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual([FIX]);
	});

	it("hides the fix while the user types and never replaces what they typed", () => {
		const { editor, core, container, sent } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		editor.handleKey(key({ key: "l" }));
		expect(row(container)).toBeNull();
		editor.handleKey(key({ key: "ArrowRight" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["l"]);
	});

	it("does not bring an applied fix back after the user edits it", () => {
		const { editor, core, container } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		useButton(container)!.click();
		editor.handleKey(key({ key: "Backspace", metaKey: true }));
		expect(row(container)).toBeNull();
		expect(container.querySelector(".terminal-editor-ghost")).toBeNull();
	});

	it("offers nothing for a successful command or with no rules", () => {
		const ok = mount();
		ok.core.feed(encode(run("git push", PUSH_OUTPUT, 0) + READY));
		expect(row(ok.container)).toBeNull();
		const none = mount([]);
		none.core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		expect(row(none.container)).toBeNull();
	});

	it("offers nothing for a failed block that was already there when the editor mounted", () => {
		const sent: string[] = [];
		const core = createTerminalCore({ columns: 80, scrollback: 200 });
		core.feed(encode(run("git push", PUSH_OUTPUT, 1)));
		const editor = new LineEditor();
		const container = document.createElement("div");
		editor.mount(container, core, { send: (text) => sent.push(text), sendRaw: () => {} });
		editor.setQuickFixRules(DEFAULT_QUICK_FIX_RULES);
		core.feed(encode(READY));
		expect(row(container)).toBeNull();
	});

	it("withdraws the fix once the next command starts", () => {
		const { core, container } = mount();
		core.feed(encode(run("git push", PUSH_OUTPUT, 1) + READY));
		expect(row(container)).not.toBeNull();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07"));
		core.feed(encode("a\r\n\x1b]133;D;0\x07" + READY));
		expect(row(container)).toBeNull();
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal/ts/editor && npx vitest run src/line-editor-quick-fix.test.ts 2>&1 | grep -E "TypeError|Tests  " | sort -u | head -3`
Expected: `7 TypeError: editor.setQuickFixRules is not a function` and `Tests  7 failed (7)`.

- [ ] **Step 3: The offer**

Create `packages/terminal/ts/editor/src/quick-fix-offer.ts`:

```ts
import { decodeBlocks, type BlockView, type TerminalCore } from "@operator/terminal-core";
import { findQuickFix, QUICK_FIX_WINDOW_LIMIT, type QuickFix, type QuickFixRule } from "./quick-fix.js";

const OUTPUT_LINES = QUICK_FIX_WINDOW_LIMIT * 2 + 1;

function lastSettled(blocks: readonly BlockView[]): number {
	for (let index = blocks.length - 1; index >= 0; index -= 1) {
		if (blocks[index]!.state !== "running") return index;
	}
	return -1;
}

export class QuickFixOffer {
	private rules: readonly QuickFixRule[] = [];
	private seen: string | null = null;
	private current: QuickFix | null = null;

	setRules(rules: readonly QuickFixRule[]): void {
		this.rules = rules;
	}

	reset(core: TerminalCore): void {
		const blocks = decodeBlocks(core.snapshot());
		this.seen = blocks[lastSettled(blocks)]?.id ?? null;
		this.current = null;
	}

	observe(core: TerminalCore): void {
		const snapshot = core.snapshot();
		if (snapshot.altScreen !== null) return;
		const blocks = decodeBlocks(snapshot);
		const index = lastSettled(blocks);
		if (blocks.slice(index + 1).some((block) => block.command.length > 0)) {
			this.current = null;
			return;
		}
		const block = blocks[index];
		if (!block || block.id === this.seen) return;
		this.seen = block.id;
		this.current = null;
		if (this.rules.length === 0 || block.state !== "finished" || block.source === "synthetic") return;
		this.current = findQuickFix(this.rules, {
			command: block.command,
			exitCode: block.exitCode,
			output: () => (core.readBlockOutput(block.id, { maxLines: OUTPUT_LINES }) ?? "").split("\n"),
		});
	}

	fix(): QuickFix | null {
		return this.current;
	}

	dismiss(): void {
		this.current = null;
	}
}

export function renderQuickFixRow(fix: QuickFix, label: string, useLabel: string, use: () => void): HTMLElement {
	const row = document.createElement("div");
	row.className = "terminal-editor-quick-fix";
	row.dataset.quickFix = fix.ruleId;
	const title = document.createElement("span");
	title.className = "terminal-editor-quick-fix-label";
	title.textContent = label;
	const command = document.createElement("span");
	command.className = "terminal-editor-quick-fix-command";
	command.textContent = fix.command;
	command.title = fix.command;
	const button = document.createElement("button");
	button.type = "button";
	button.className = "terminal-editor-quick-fix-use";
	button.textContent = useLabel;
	button.setAttribute("aria-label", `${useLabel}: ${fix.command}`);
	button.addEventListener("mousedown", (event) => event.preventDefault());
	button.addEventListener("click", (event) => {
		event.preventDefault();
		event.stopPropagation();
		use();
	});
	row.append(title, command, button);
	return row;
}
```

- [ ] **Step 4: Wire it into `LineEditor`**

Save as a scratch patch and `git apply` from the worktree root:

```diff
--- a/packages/terminal/ts/editor/src/line-editor.ts
+++ b/packages/terminal/ts/editor/src/line-editor.ts
@@ -19,6 +19,8 @@
 import { renderPromptRow } from "./prompt-row.js";
 import { ReverseSearch } from "./reverse-search.js";
 import { ensurePackageStyleTag, renderBufferRows } from "./line-editor-dom.js";
+import { QuickFixOffer, renderQuickFixRow } from "./quick-fix-offer.js";
+import type { QuickFixRule } from "./quick-fix.js";
 import { CLEAR_SHELL_LINE, TypeaheadGate } from "./typeahead.js";
 
 const INTERRUPT = "\x03";
@@ -34,6 +36,7 @@
 export class LineEditor {
 	private readonly buffer = new EditorBuffer();
 	private readonly history = new EditorHistory(() => this.historyChanged());
+	private readonly quickFix = new QuickFixOffer();
 	private readonly search = new ReverseSearch();
 	private searchOpen = false;
 	private readonly dropdown = new CompletionsDropdown();
@@ -63,6 +66,7 @@
 		ensurePackageStyleTag();
 		this.core = core;
 		this.host = host;
+		this.quickFix.reset(core);
 		this.promptCwd = "";
 		this.promptBranch = "";
 		this.promptExitCode = null;
@@ -156,6 +160,10 @@
 		this.render();
 	}
 
+	setQuickFixRules(rules: readonly QuickFixRule[]): void {
+		this.quickFix.setRules(rules);
+	}
+
 	setVisible(visible: boolean): void {
 		this.visible = visible;
 		if (!visible || !this.staleWhileHidden) return;
@@ -177,6 +185,7 @@
 		this.unsubscribeCompletions?.();
 		this.unsubscribeCompletions = null;
 		this.history.dispose();
+		this.quickFix.dismiss();
 		this.dropdown.dispose();
 		this.dropdownOpen = false;
 		this.composition?.dispose();
@@ -322,6 +331,7 @@
 				}
 				host.send(this.buffer.text);
 				this.buffer.clear();
+				this.quickFix.dismiss();
 				this.history.endWalk();
 				this.cancelDropdownIfOpen();
 				break;
@@ -394,9 +404,22 @@
 	}
 
 	private acceptSuggestion(): void {
-		const suggestion = this.history.suggest(this.buffer.text);
+		const fix = this.buffer.text.length === 0 ? this.quickFix.fix() : null;
+		const suggestion = fix?.command ?? this.history.suggest(this.buffer.text);
 		if (suggestion !== null) this.buffer.setText(suggestion);
+		if (fix) this.quickFix.dismiss();
+		this.history.endWalk();
+	}
+
+	private useQuickFix(): void {
+		const fix = this.quickFix.fix();
+		if (!fix || this.buffer.text.length > 0 || this.core?.lineEditorState() !== "owned") return;
+		this.buffer.setText(fix.command);
+		this.quickFix.dismiss();
 		this.history.endWalk();
+		this.cancelDropdownIfOpen();
+		this.render();
+		this.focus();
 	}
 
 	private historyChanged(): void {
@@ -463,7 +486,8 @@
 			return;
 		}
 		const text = this.buffer.text;
-		const ghost = this.history.suggest(text)?.slice(text.length) ?? null;
+		const fix = text.length === 0 ? this.quickFix.fix() : null;
+		const ghost = fix ? fix.command : (this.history.suggest(text)?.slice(text.length) ?? null);
 		const nodes = renderBufferRows(text, this.buffer.lines(), this.buffer.cursor, ghost);
 		if (this.searchOpen) {
 			const state = this.search.state();
@@ -486,6 +510,7 @@
 				this.strings,
 			),
 		);
+		if (fix) nodes.unshift(renderQuickFixRow(fix, this.strings.quickFixLabel, this.strings.quickFixUse, () => this.useQuickFix()));
 		content.replaceChildren(...nodes);
 	}
 
@@ -546,6 +571,7 @@
 		if (!core) return;
 		const blocks = decodeBlocks(core.snapshot());
 		this.history.ingest(blocks);
+		this.quickFix.observe(core);
 		const newest = blocks.at(-1);
 		this.promptCwd = newest?.cwd ?? "";
 		this.promptBranch = newest?.gitBranch ?? "";
```

- [ ] **Step 5: Strings and styles**

`packages/terminal/ts/core/src/types.ts`: after line 214 (`	loadOlderOutput: string;`) add

```ts
	quickFixLabel: string;
	quickFixUse: string;
```

and after line 240 (`	loadOlderOutput: "Load older output",`, now 242 after the first insertion) add

```ts
	quickFixLabel: "Suggested fix",
	quickFixUse: "Use",
```

In both `packages/terminal/ts/renderer-dom/src/palette.test.ts` and `packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts`, after line 28 (`	loadOlderOutput: "Load older output",`) add the same two lines as the defaults (their `STRINGS: TerminalStrings` literals are complete objects and stop compiling otherwise).

Append to **both** `packages/terminal/ts/editor/src/styles.css` (after line 159) and the template literal in `packages/terminal/ts/editor/src/styles.ts` (before the closing `` `; `` on line 159), with one blank line before the first rule — `styles-parity.test.ts` requires the two to be byte-identical:

```css
.terminal-editor-quick-fix {
	display: flex;
	gap: 8px;
	align-items: center;
	min-width: 0;
	padding-bottom: 8px;
	white-space: nowrap;
}

.terminal-editor-quick-fix-label {
	color: var(--terminal-ansi-3);
}

.terminal-editor-quick-fix-command {
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
}

.terminal-editor-quick-fix-use {
	padding: 2px 8px;
	color: var(--terminal-foreground);
	background: transparent;
	border: 1px solid var(--terminal-block-border);
	border-radius: 4px;
	font: inherit;
	cursor: pointer;
}

.terminal-editor-quick-fix-use:hover,
.terminal-editor-quick-fix-use:focus-visible {
	border-color: var(--terminal-ansi-3);
	outline: none;
}
```

- [ ] **Step 6: Run to see it pass; build; boundaries; sizes**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && npm run build:ts 2>&1 | grep -i error
for p in core renderer-dom editor; do (cd ts/$p && echo "$p $(npx vitest run 2>&1 | grep -E 'Tests  ')"); done
npm run check:boundaries 2>&1 | tail -2; wc -l ts/editor/src/line-editor.ts ts/editor/src/styles.css ts/editor/src/styles.ts ts/core/src/types.ts
```
Expected: no `error`; `core 180`, `renderer-dom 995`, `editor 218` passed; `boundary check passed`; `581`, `194`, `194`, `279`.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add packages/terminal/ts/editor/src/quick-fix-offer.ts packages/terminal/ts/editor/src/line-editor.ts packages/terminal/ts/editor/src/line-editor-quick-fix.test.ts packages/terminal/ts/editor/src/styles.css packages/terminal/ts/editor/src/styles.ts packages/terminal/ts/core/src/types.ts packages/terminal/ts/renderer-dom/src/palette.test.ts packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts
git commit -m "feat(editor): offer a failed command's fix in the input box, into the box only

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: React — `commandHistory` and `quickFixRules` on `TerminalSurface`

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:2` (import), `:74-75` (props), `:107-108` (destructure), `:146` (refs), `:195` (mount), `:297` (effects)
- Modify: `packages/terminal/ts/react/src/index.ts:11`
- Test: `packages/terminal/ts/react/src/TerminalSurface.history.test.tsx` (new)

**Interfaces:**
- Consumes: `LineEditor.setHistorySource`, `LineEditor.setQuickFixRules`, `CommandHistorySource`, `CommandHistoryEntry`, `QuickFixRule`, `DEFAULT_QUICK_FIX_RULES` (Tasks 3–5); `surface-harness.tsx` `feed`, `font`, `ignoreRaw`, `loadWasm`, `theme`.
- Produces: `TerminalSurfaceProps.commandHistory?: CommandHistorySource`, `TerminalSurfaceProps.quickFixRules?: readonly QuickFixRule[]`; `@operator/terminal-react` re-exports `DEFAULT_QUICK_FIX_RULES`, `type CommandHistoryEntry`, `type CommandHistorySource`, `type QuickFixRule`. Both props are read through refs at mount and re-applied by their own layout effects, like `confirmPaste` (`TerminalSurface.tsx:144-146,195,295-297`), so a new object does not remount the renderer. Task 7 consumes them.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/react/src/TerminalSurface.history.test.tsx`:

```tsx
import { cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import type { CommandHistoryEntry, CommandHistorySource, QuickFixRule } from "@operator/terminal-editor";
import { TerminalSurface } from "./index";
import { feed, font, ignoreRaw, loadWasm, theme } from "./surface-harness";

const READY = "\x1b]7000;v=1;input-ready=1\x07";

beforeAll(loadWasm);
afterEach(cleanup);

function source(entries: CommandHistoryEntry[]): CommandHistorySource & { listeners: Set<() => void> } {
	const listeners = new Set<() => void>();
	return {
		listeners,
		entries: () => entries,
		subscribe: (listener) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
	};
}

describe("TerminalSurface command history and quick fixes", () => {
	it("recalls a command from the host's shared history with ArrowUp", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		feed(core, READY);
		const onSend = vi.fn();
		const { container } = render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				onSend={onSend}
				onSendRaw={ignoreRaw}
				commandHistory={source([{ command: "make release", at: 1 }])}
			/>,
		);
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		fireEvent.keyDown(editor, { key: "ArrowUp" });
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(onSend).toHaveBeenCalledWith("make release");
	});

	it("moves its subscription to a new history source and drops it on unmount", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const first = source([]);
		const second = source([]);
		const surface = (history: CommandHistorySource) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={vi.fn()} onSendRaw={ignoreRaw} commandHistory={history} />
		);
		const { rerender, unmount } = render(surface(first));
		expect(first.listeners.size).toBe(1);
		rerender(surface(second));
		expect(first.listeners.size).toBe(0);
		expect(second.listeners.size).toBe(1);
		unmount();
		expect(second.listeners.size).toBe(0);
	});

	it("shows a host rule's fix above the input box after a failed command", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const rule: QuickFixRule = { id: "make-clean", commandLine: /^make$/, exit: "error", fix: () => "make clean" };
		const onSend = vi.fn();
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} quickFixRules={[rule]} />,
		);
		feed(core, `\x1b]133;A\x07\x1b]7000;v=1;cmd=make\x07\x1b]133;C\x07boom\r\n\x1b]133;D;2\x07${READY}`);
		const row = container.querySelector<HTMLElement>(".terminal-editor-quick-fix");
		expect(row?.dataset.quickFix).toBe("make-clean");
		fireEvent.click(row!.querySelector("button")!);
		expect(onSend).not.toHaveBeenCalled();
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(onSend).toHaveBeenCalledWith("make clean");
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal/ts/react && npx vitest run src/TerminalSurface.history.test.tsx 2>&1 | grep -E "×|Tests  "`
Expected: three `×` and `Tests  3 failed (3)` (`onSend` never called, listener sizes `0`, no `.terminal-editor-quick-fix`).

- [ ] **Step 3: Implement**

`packages/terminal/ts/react/src/TerminalSurface.tsx`:

```diff
diff --git a/packages/terminal/ts/react/src/TerminalSurface.tsx b/packages/terminal/ts/react/src/TerminalSurface.tsx
--- a/packages/terminal/ts/react/src/TerminalSurface.tsx
+++ b/packages/terminal/ts/react/src/TerminalSurface.tsx
@@ -1,5 +1,13 @@
 import { useCallback, useLayoutEffect, useRef, useState, type MouseEvent as ReactMouseEvent, type ReactElement, type ReactNode } from "react";
-import { clipboardHasImage, deliverPaste, encodeKey, LineEditor, planPaste } from "@operator/terminal-editor";
+import {
+	clipboardHasImage,
+	deliverPaste,
+	encodeKey,
+	LineEditor,
+	planPaste,
+	type CommandHistorySource,
+	type QuickFixRule,
+} from "@operator/terminal-editor";
 import {
 	createFindBar,
 	createPathProvider,
@@ -72,6 +80,8 @@ export interface TerminalSurfaceProps {
 	onBlockFinished?: (event: BlockFinishedEvent) => void;
 	onHint?: (hint: HintEvent) => void;
 	onDraftChange?: (draft: string) => void;
+	commandHistory?: CommandHistorySource;
+	quickFixRules?: readonly QuickFixRule[];
 }
 
 let lastFocusedSurface: HTMLElement | null = null;
@@ -105,6 +115,8 @@ export function TerminalSurface({
 	visible,
 	features,
 	marks,
+	commandHistory,
+	quickFixRules,
 }: TerminalSurfaceProps): ReactElement {
 	const hostRef = useRef<HTMLDivElement | null>(null);
 	const surfaceRef = useRef<HTMLDivElement | null>(null);
@@ -144,6 +156,10 @@ export function TerminalSurface({
 	const confirmPaste = host?.confirmPaste;
 	const confirmPasteRef = useRef(confirmPaste);
 	confirmPasteRef.current = confirmPaste;
+	const commandHistoryRef = useRef(commandHistory);
+	commandHistoryRef.current = commandHistory;
+	const quickFixRulesRef = useRef(quickFixRules);
+	quickFixRulesRef.current = quickFixRules;
 
 	const applyLinkProviders = useCallback(() => {
 		const renderer = rendererRef.current;
@@ -193,6 +209,8 @@ export function TerminalSurface({
 		editor.setFont(font);
 		editor.setStrings(strings);
 		editor.setPasteConfirm(confirmPasteRef.current ?? null);
+		editor.setHistorySource(commandHistoryRef.current ?? null);
+		editor.setQuickFixRules(quickFixRulesRef.current ?? []);
 		const findBar = createFindBar({
 			core,
 			renderer,
@@ -296,6 +314,14 @@ export function TerminalSurface({
 		editorRef.current?.setPasteConfirm(confirmPaste ?? null);
 	}, [confirmPaste]);
 
+	useLayoutEffect(() => {
+		editorRef.current?.setHistorySource(commandHistory ?? null);
+	}, [commandHistory]);
+
+	useLayoutEffect(() => {
+		editorRef.current?.setQuickFixRules(quickFixRules ?? []);
+	}, [quickFixRules]);
+
 	useLayoutEffect(() => {
 		const blockHost = hostRef.current;
 		if (!blockHost || !rendererRef.current) {
```

`packages/terminal/ts/react/src/index.ts`:

```diff
diff --git a/packages/terminal/ts/react/src/index.ts b/packages/terminal/ts/react/src/index.ts
--- a/packages/terminal/ts/react/src/index.ts
+++ b/packages/terminal/ts/react/src/index.ts
@@ -9,6 +9,12 @@ export {
 	type MouseReportKind,
 } from "./mouse-report.js";
 export { warpDarkTheme, type MarkRule } from "@operator/terminal-renderer-dom";
+export {
+	DEFAULT_QUICK_FIX_RULES,
+	type CommandHistoryEntry,
+	type CommandHistorySource,
+	type QuickFixRule,
+} from "@operator/terminal-editor";
 export { createTerminalCore, markRegexValid, type TerminalCoreOptions } from "@operator/terminal-core";
 export { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
 export type {
```

- [ ] **Step 4: Run to see it pass**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && npm run build:ts 2>&1 | grep -i error; (cd ts/react && npx vitest run 2>&1 | grep -E "Tests  "); wc -l ts/react/src/TerminalSurface.tsx
```
Expected: no `error`; `Tests  159 passed (159)`; `541`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/index.ts packages/terminal/ts/react/src/TerminalSurface.history.test.tsx
git commit -m "feat(react): TerminalSurface takes a command history source and quick-fix rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Operator — the shared history store and the wiring in `BlockTerminal`

**Files:**
- Create: `frontend/src/renderer/lib/command-history.ts`
- Test: `frontend/src/renderer/lib/command-history.test.ts` (new)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:4-5` (import), `:16` (import), `:568` (strings), `:640-641` (props), `:663` (`onBlockFinished`)
- Modify: `frontend/src/renderer/test/setup.ts:44` (global mock export)
- Modify: `frontend/src/renderer/components/BlockTerminal.test.tsx:56`, `:182-183`, `:215`, `:262` (new mock before it), `:422`, and a new `describe` at the end

**Interfaces:**
- Consumes: `apiClient.GET("/api/v1/terminal-history", { params: { query: { limit } } })` and `components["schemas"]["TerminalHistoryResponse"]` (Task 2); `apiErrorMessage` (`lib/api-client.ts`); `terminalDebug(scope, message, detail)` (`lib/terminal-debug.ts:16`); `DEFAULT_QUICK_FIX_RULES`, `CommandHistorySource`, `CommandHistoryEntry` from `@operator/terminal-react` (Task 6); `BlockTerminalProps.agentTui` (`BlockTerminal.tsx:58`); `TerminalSurface`'s `onBlockFinished` (`BlockTerminal.tsx:663`).
- Produces: `fetchTerminalHistory(): Promise<CommandHistoryEntry[]>`; `createCommandHistoryStore(deps: { fetch; focusTarget: Pick<Window, "addEventListener" | "removeEventListener"> | null; schedule(run, delayMs): () => void }): CommandHistoryStore`; `type CommandHistoryStore = CommandHistorySource & { refresh(): void; noteCommandFinished(): void }`; the renderer singleton `commandHistory`; constants `TERMINAL_HISTORY_LIMIT = 1000`, `COMMAND_FINISHED_REFRESH_MS = 500`. A shell `BlockTerminal` passes `commandHistory` and `DEFAULT_QUICK_FIX_RULES`; an agent (`agentTui`) one passes neither and never refreshes the store.

- [ ] **Step 1: Write the failing tests**

Create `frontend/src/renderer/lib/command-history.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiGetMock } = vi.hoisted(() => ({ apiGetMock: vi.fn() }));

vi.mock("./api-client", () => ({
	apiClient: { GET: apiGetMock },
	apiErrorMessage: () => "Request failed",
}));

import { createCommandHistoryStore, fetchTerminalHistory, TERMINAL_HISTORY_LIMIT } from "./command-history";

type Entry = { command: string; at: number };

function deferred() {
	let resolve!: (entries: Entry[]) => void;
	let reject!: (error: Error) => void;
	const promise = new Promise<Entry[]>((res, rej) => {
		resolve = res;
		reject = rej;
	});
	return { promise, resolve, reject };
}

function harness() {
	const calls: Array<ReturnType<typeof deferred>> = [];
	const focus = new EventTarget();
	let scheduled: (() => void) | null = null;
	const store = createCommandHistoryStore({
		fetch: () => {
			const call = deferred();
			calls.push(call);
			return call.promise;
		},
		focusTarget: focus as unknown as Window,
		schedule: (run) => {
			scheduled = run;
			return () => {
				scheduled = null;
			};
		},
	});
	return { store, calls, focus, fireScheduled: () => scheduled?.(), hasScheduled: () => scheduled !== null };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("fetchTerminalHistory", () => {
	beforeEach(() => apiGetMock.mockReset());

	it("asks the daemon for the capped history and maps finishedAt to epoch milliseconds", async () => {
		apiGetMock.mockResolvedValue({
			data: {
				commands: [
					{ command: "make", finishedAt: "2026-09-27T10:00:00Z" },
					{ command: "", finishedAt: "2026-09-27T10:00:01Z" },
					{ command: "ls", finishedAt: "not a date" },
				],
			},
		});
		await expect(fetchTerminalHistory()).resolves.toEqual([{ command: "make", at: Date.parse("2026-09-27T10:00:00Z") }]);
		expect(apiGetMock).toHaveBeenCalledWith("/api/v1/terminal-history", {
			params: { query: { limit: TERMINAL_HISTORY_LIMIT } },
		});
	});

	it("throws on an error envelope", async () => {
		apiGetMock.mockResolvedValue({ error: { message: "boom" } });
		await expect(fetchTerminalHistory()).rejects.toThrow("Request failed");
	});
});

describe("createCommandHistoryStore", () => {
	it("fetches on the first subscriber and notifies when the answer lands", async () => {
		const { store, calls } = harness();
		const listener = vi.fn();
		store.subscribe(listener);
		store.subscribe(vi.fn());
		expect(calls).toHaveLength(1);
		calls[0]!.resolve([{ command: "npm test", at: 5 }]);
		await flush();
		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.entries()).toEqual([{ command: "npm test", at: 5 }]);
	});

	it("runs one fetch at a time and one more after a refresh asked for during it", async () => {
		const { store, calls } = harness();
		store.subscribe(vi.fn());
		store.refresh();
		store.refresh();
		expect(calls).toHaveLength(1);
		calls[0]!.resolve([]);
		await flush();
		expect(calls).toHaveLength(2);
		calls[1]!.resolve([{ command: "b", at: 2 }]);
		await flush();
		expect(calls).toHaveLength(2);
		expect(store.entries()).toEqual([{ command: "b", at: 2 }]);
	});

	it("keeps the last good entries when a fetch fails", async () => {
		const { store, calls } = harness();
		store.subscribe(vi.fn());
		calls[0]!.resolve([{ command: "a", at: 1 }]);
		await flush();
		store.refresh();
		calls[1]!.reject(new Error("daemon down"));
		await flush();
		expect(store.entries()).toEqual([{ command: "a", at: 1 }]);
	});

	it("refreshes on window focus only while someone listens", async () => {
		const { store, calls, focus } = harness();
		const off = store.subscribe(vi.fn());
		calls[0]!.resolve([]);
		await flush();
		focus.dispatchEvent(new Event("focus"));
		expect(calls).toHaveLength(2);
		calls[1]!.resolve([]);
		await flush();
		off();
		focus.dispatchEvent(new Event("focus"));
		expect(calls).toHaveLength(2);
	});

	it("refreshes once after a burst of finished commands", () => {
		const { store, calls, fireScheduled, hasScheduled } = harness();
		store.noteCommandFinished();
		store.noteCommandFinished();
		expect(calls).toHaveLength(0);
		expect(hasScheduled()).toBe(true);
		fireScheduled();
		expect(calls).toHaveLength(1);
	});
});
```

In `frontend/src/renderer/components/BlockTerminal.test.tsx` apply the mock changes and the new `describe` block:

```diff
diff --git a/frontend/src/renderer/components/BlockTerminal.test.tsx b/frontend/src/renderer/components/BlockTerminal.test.tsx
--- a/frontend/src/renderer/components/BlockTerminal.test.tsx
+++ b/frontend/src/renderer/components/BlockTerminal.test.tsx
@@ -54,6 +54,8 @@ const mockState = vi.hoisted(() => {
 		focusToken: undefined as number | undefined,
 		visible: undefined as boolean | undefined,
 		marks: undefined as readonly { pattern: string; regex: boolean; colour: string }[] | undefined,
+		commandHistory: undefined as unknown,
+		quickFixRules: undefined as unknown,
 		// The real surface only reports geometry once its host has a non-zero
 		// client box. Off means "mounted but never laid out", which is what a
 		// pane behind another tab looks like.
@@ -180,7 +182,11 @@ vi.mock("@operator/terminal-react", () => {
 			focusToken?: number;
 			visible?: boolean;
 			marks?: readonly { pattern: string; regex: boolean; colour: string }[];
+			commandHistory?: unknown;
+			quickFixRules?: unknown;
 		}) => {
+			mockState.commandHistory = props.commandHistory;
+			mockState.quickFixRules = props.quickFixRules;
 			mockState.focusToken = props.focusToken;
 			mockState.visible = props.visible;
 			mockState.marks = props.marks;
@@ -213,6 +219,7 @@ vi.mock("@operator/terminal-react", () => {
 			mockState.wasmInits += 1;
 		},
 		markRegexValid: (_pattern: string): boolean | null => null,
+		DEFAULT_QUICK_FIX_RULES: Object.freeze([{ id: "mock-quick-fix" }]),
 		createTerminalCore: () => {
 			let generation = 0;
 			const core: MockCore = {
@@ -259,6 +266,15 @@ vi.mock("@operator/terminal-react", () => {
 	};
 });
 
+const mockCommandHistory = vi.hoisted(() => ({
+	entries: () => [],
+	subscribe: () => () => undefined,
+	refresh: vi.fn(),
+	noteCommandFinished: vi.fn(),
+}));
+
+vi.mock("../lib/command-history", () => ({ commandHistory: mockCommandHistory }));
+
 vi.mock("../lib/external-link-policy", () => ({
 	isWebLink: (url: string) => url.startsWith("http://") || url.startsWith("https://"),
 	openLinkInSystemBrowser: vi.fn(),
@@ -420,6 +436,9 @@ beforeEach(() => {
 	mockState.focusToken = undefined;
 	mockState.visible = undefined;
 	mockState.marks = undefined;
+	mockState.commandHistory = undefined;
+	mockState.quickFixRules = undefined;
+	mockCommandHistory.noteCommandFinished.mockClear();
 	subscribers.clear();
 });
 
@@ -1024,3 +1043,35 @@ describe("BlockTerminal load older output", () => {
 		expect(mockState.host?.loadOlderOutput).toBeUndefined();
 	});
 });
+
+describe("BlockTerminal shared history and quick fixes", () => {
+	it("gives a shell surface the shared command history, the default quick-fix rules and their strings", async () => {
+		renderTerminal();
+		await waitFor(() => expect(mockState.commandHistory).toBe(mockCommandHistory));
+		expect(mockState.quickFixRules).toEqual([{ id: "mock-quick-fix" }]);
+		expect(mockState.strings?.quickFixLabel).toBe("Suggested fix");
+		expect(mockState.strings?.quickFixUse).toBe("Use");
+	});
+
+	it("gives an agent surface neither", async () => {
+		renderTerminal({ agentTui: true });
+		await waitFor(() => expect(mockState.onBlockFinished).toBeTypeOf("function"));
+		expect(mockState.commandHistory).toBeUndefined();
+		expect(mockState.quickFixRules).toBeUndefined();
+	});
+
+	it("asks the shared history to refresh when a shell command finishes, visible or not", async () => {
+		renderTerminal();
+		await waitFor(() => expect(mockState.onBlockFinished).toBeTypeOf("function"));
+		mockState.onBlockFinished!({ id: "0:1", exitCode: 0, durationMs: 10, visible: true });
+		mockState.onBlockFinished!({ id: "0:2", exitCode: 1, durationMs: 20_000, visible: false });
+		expect(mockCommandHistory.noteCommandFinished).toHaveBeenCalledTimes(2);
+	});
+
+	it("does not refresh it for an agent pane's blocks", async () => {
+		renderTerminal({ agentTui: true });
+		await waitFor(() => expect(mockState.onBlockFinished).toBeTypeOf("function"));
+		mockState.onBlockFinished!({ id: "0:1", exitCode: 0, durationMs: 10, visible: true });
+		expect(mockCommandHistory.noteCommandFinished).not.toHaveBeenCalled();
+	});
+});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/command-history.test.ts src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Failed to resolve|×|Tests  " | head -8`
Expected (planning run): `Error: Failed to resolve import "./command-history" from "src/renderer/lib/command-history.test.ts"`; in `BlockTerminal.test.tsx` `× gives a shell surface the shared command history…` (`expected undefined to be { entries: … }`) and `× asks the shared history to refresh…` (`called 2 times, but got 0 times`); `Test Files  2 failed (2)`, `Tests  2 failed | 53 passed (55)`. The two agent-pane tests pass before the change by construction.

- [ ] **Step 3: The store**

Create `frontend/src/renderer/lib/command-history.ts`:

```ts
import type { CommandHistoryEntry, CommandHistorySource } from "@operator/terminal-react";
import { apiClient, apiErrorMessage } from "./api-client";
import { terminalDebug } from "./terminal-debug";

export const TERMINAL_HISTORY_LIMIT = 1000;
export const COMMAND_FINISHED_REFRESH_MS = 500;

export async function fetchTerminalHistory(): Promise<CommandHistoryEntry[]> {
	const { data, error } = await apiClient.GET("/api/v1/terminal-history", {
		params: { query: { limit: TERMINAL_HISTORY_LIMIT } },
	});
	if (error) throw new Error(apiErrorMessage(error, "Unable to load command history"));
	const entries: CommandHistoryEntry[] = [];
	for (const entry of data?.commands ?? []) {
		const at = Date.parse(entry.finishedAt);
		if (entry.command.length > 0 && Number.isFinite(at)) entries.push({ command: entry.command, at });
	}
	return entries;
}

export type CommandHistoryStore = CommandHistorySource & {
	refresh(): void;
	noteCommandFinished(): void;
};

type FocusTarget = Pick<Window, "addEventListener" | "removeEventListener">;

export type CommandHistoryStoreDeps = {
	fetch: () => Promise<CommandHistoryEntry[]>;
	focusTarget: FocusTarget | null;
	schedule: (run: () => void, delayMs: number) => () => void;
};

export function createCommandHistoryStore(deps: CommandHistoryStoreDeps): CommandHistoryStore {
	let entries: readonly CommandHistoryEntry[] = [];
	const listeners = new Set<() => void>();
	let inFlight = false;
	let again = false;
	let cancelScheduled: (() => void) | null = null;

	const refresh = (): void => {
		if (inFlight) {
			again = true;
			return;
		}
		inFlight = true;
		void deps
			.fetch()
			.then(
				(next) => {
					entries = next;
					for (const listener of [...listeners]) listener();
				},
				(error: unknown) => {
					terminalDebug("command-history", "refresh failed", { error: String(error) });
				},
			)
			.finally(() => {
				inFlight = false;
				if (!again) return;
				again = false;
				refresh();
			});
	};
	const onFocus = () => refresh();

	return {
		entries: () => entries,
		subscribe(listener) {
			listeners.add(listener);
			if (listeners.size === 1) {
				deps.focusTarget?.addEventListener("focus", onFocus);
				refresh();
			}
			return () => {
				if (!listeners.delete(listener) || listeners.size > 0) return;
				deps.focusTarget?.removeEventListener("focus", onFocus);
			};
		},
		refresh,
		noteCommandFinished() {
			cancelScheduled?.();
			cancelScheduled = deps.schedule(() => {
				cancelScheduled = null;
				refresh();
			}, COMMAND_FINISHED_REFRESH_MS);
		},
	};
}

export const commandHistory = createCommandHistoryStore({
	fetch: fetchTerminalHistory,
	focusTarget: typeof window === "undefined" ? null : window,
	schedule: (run, delayMs) => {
		const id = setTimeout(run, delayMs);
		return () => clearTimeout(id);
	},
});
```

- [ ] **Step 4: Wire `BlockTerminal` and the global test mock**

```diff
diff --git a/frontend/src/renderer/components/BlockTerminal.tsx b/frontend/src/renderer/components/BlockTerminal.tsx
--- a/frontend/src/renderer/components/BlockTerminal.tsx
+++ b/frontend/src/renderer/components/BlockTerminal.tsx
@@ -2,6 +2,7 @@ import { useQuery } from "@tanstack/react-query";
 import { useCallback, useEffect, useMemo, useRef, useState } from "react";
 import { useTranslation } from "react-i18next";
 import {
+	DEFAULT_QUICK_FIX_RULES,
 	TerminalSurface,
 	createTerminalCore,
 	initTerminalCoreFromUrl,
@@ -14,6 +15,7 @@ import {
 	type TerminalTheme,
 } from "@operator/terminal-react";
 import { operatorBridge } from "../lib/bridge";
+import { commandHistory } from "../lib/command-history";
 import { rememberPaneGrid } from "../lib/pane-grid";
 import { BLOCK_NOTIFY_AFTER_MS } from "../lib/retained-terminal";
 import { terminalBackgroundColor, type TerminalBackground } from "../lib/terminal-background";
@@ -566,6 +568,8 @@ export function BlockTerminal({
 			}),
 			jumpToBottom: t("blocks.jumpToBottom", { defaultValue: "Jump to bottom" }),
 			loadOlderOutput: t("blocks.loadOlderOutput", { defaultValue: "Load older output" }),
+			quickFixLabel: t("blocks.quickFixLabel", { defaultValue: "Suggested fix" }),
+			quickFixUse: t("blocks.quickFixUse", { defaultValue: "Use" }),
 			shellBlocksUnavailable: t("blocks.shellBlocksUnavailable", {
 				defaultValue: "Shell blocks are unavailable in this terminal.",
 			}),
@@ -639,6 +643,7 @@ export function BlockTerminal({
 		visible,
 		marks,
 		onDraftChange,
+		...(agentTui ? {} : { commandHistory, quickFixRules: DEFAULT_QUICK_FIX_RULES }),
 		onHint: (hint) => {
 			// A hint's path is the text as it was printed, so it is relative as
 			// often as not; open_path only answers for an absolute file. Resolving
@@ -661,6 +666,7 @@ export function BlockTerminal({
 			void reportTerminalActionFailure(host.writeClipboard(hint.text));
 		},
 		onBlockFinished: ({ id, exitCode, durationMs, visible }) => {
+			if (!agentTui) commandHistory.noteCommandFinished();
 			if (visible || durationMs === null || durationMs < BLOCK_NOTIFY_AFTER_MS) return;
 			void reportTerminalActionFailure(
 				operatorBridge.notifications.show({
```

```diff
diff --git a/frontend/src/renderer/test/setup.ts b/frontend/src/renderer/test/setup.ts
--- a/frontend/src/renderer/test/setup.ts
+++ b/frontend/src/renderer/test/setup.ts
@@ -42,6 +42,7 @@ vi.mock("@operator/terminal-react", () => {
 			};
 		},
 		markRegexValid: vi.fn((_pattern: string): boolean | null => null),
+		DEFAULT_QUICK_FIX_RULES: Object.freeze([]),
 		initTerminalCoreFromUrl: vi.fn(async () => undefined),
 		warpDarkTheme: {
 			ansi: new Array(16).fill("#000000"),
```

The two strings use `defaultValue` only, like `blocks.loadOlderOutput` (`BlockTerminal.tsx:568`, absent from `i18n/en.json`); no i18n JSON edit (memory "Tauri dev goes blank after a full reload").

- [ ] **Step 5: Run to see them pass; typecheck; lint**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend
npx vitest run --config vite.renderer.config.ts src/renderer/lib/command-history.test.ts src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Test Files|Tests  "
npm run typecheck 2>&1 | tail -2
npx eslint src/renderer/lib/command-history.ts src/renderer/lib/command-history.test.ts src/renderer/components/BlockTerminal.tsx src/renderer/components/BlockTerminal.test.tsx src/renderer/test/setup.ts 2>&1 | grep problems
```
Expected: `Test Files  2 passed (2)`, `Tests  62 passed (62)`; typecheck silent; `✖ 10 problems (0 errors, 10 warnings)` — the same 10 `react-hooks/refs` warnings `BlockTerminal.tsx` has on `611254eb3` (check with the same command on the base; the count must not grow).

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add frontend/src/renderer/lib/command-history.ts frontend/src/renderer/lib/command-history.test.ts frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx frontend/src/renderer/test/setup.ts
git commit -m "feat(renderer): shell panes share command history and offer quick fixes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Amendment (2026-09-27): the quick-fix on/off switch and terminal-block retention

Two of the plan's open decisions (above, "Open decisions for the user" 3 and 6) were decided by the
user on 2026-09-27: quick fixes get a Settings toggle, on by default; retention for closed
terminals' blocks is designed and built in this plan, not left as an open question. Tasks 7.5 and
7.6 below implement them, inserted after Task 7 (they depend on Task 7's `BlockTerminal` wiring and
Task 1's schema) and before Task 8 (Gates), which must now also cover them — see the Task 8 and
Task 10 notes at the end of this amendment. Every other task, file and line citation elsewhere in
this plan is unchanged.

### Task 7.5: Settings — quick-fix on/off switch

**Files:**
- Create: `frontend/src/renderer/lib/terminal-quick-fixes.ts` — same shape as
  `frontend/src/renderer/lib/terminal-predictive-echo.ts:1-16` (`terminalPredictiveEchoStorageKey`,
  `defaultTerminalPredictiveEcho`, `getLocalStorage`, `readStoredTerminalPredictiveEcho`): exports
  `terminalQuickFixesEnabledStorageKey = "opr.terminal.quickFixesEnabled"`,
  `defaultTerminalQuickFixesEnabled = true` (on by default, per the user's decision — the one
  difference from the predictive-echo default), `readStoredTerminalQuickFixesEnabled()`.
- Modify: `frontend/src/renderer/stores/ui-store.ts` — add `terminalQuickFixesEnabled: boolean` to
  the state type next to `terminalPredictiveEcho: boolean` (`:72`), seed it from
  `readStoredTerminalQuickFixesEnabled()` next to `initialTerminalPredictiveEcho` (`:176`), and add
  `setTerminalQuickFixesEnabled` following `setTerminalPredictiveEcho` verbatim (`:218-221`): early
  return if unchanged, `getLocalStorage()?.setItem(terminalQuickFixesEnabledStorageKey, … ? "1" :
  "0")`, then `set({ terminalQuickFixesEnabled })`.
- Modify: `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx` — add a
  `SettingsRow`+`Switch` pair for the new setting immediately after the
  `settings.terminalPredictiveEcho` row (`:124-130`), reading `terminalQuickFixesEnabled` /
  `setTerminalQuickFixesEnabled` off `useUiStore` the same way (`:53-54` pattern).
- Modify: `frontend/src/renderer/i18n/en.json` — add `"settings.terminalQuickFixes": "Suggest fixes
  for failed commands"` next to `"settings.terminalPredictiveEcho"` (`:608`).
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx` — at the `quickFixRules={…}`
  pass-through Task 7 adds for a shell `BlockTerminal` (Task 7 Interfaces, this plan's line 2646:
  "A shell `BlockTerminal` passes `commandHistory` and `DEFAULT_QUICK_FIX_RULES`"), read
  `terminalQuickFixesEnabled` off `useUiStore` and gate the value:
  `quickFixRules={terminalQuickFixesEnabled ? DEFAULT_QUICK_FIX_RULES : EMPTY_QUICK_FIX_RULES}`
  (a module-level `const EMPTY_QUICK_FIX_RULES: readonly QuickFixRule[] = []` so the prop is
  reference-stable when off, matching how `commandHistory` is already kept stable). No new prop is
  added to `packages/terminal` — `TerminalSurfaceProps.quickFixRules` (Task 6) already accepts any
  `readonly QuickFixRule[]`, and `findQuickFix` (Task 4, `quick-fix.ts`) is a plain loop over its
  `rules` argument, so an empty array already yields `null` for every block with no special case
  (verified by reading `quick-fix.ts`'s design in Task 4: `findQuickFix(rules, input)` iterates
  `rules` and returns on the first match, so `rules.length === 0` skips the loop body).
- Test: `frontend/src/renderer/components/settings/GeneralSettingsSection.test.tsx` (new case),
  `frontend/src/renderer/components/BlockTerminal.test.tsx` (three new cases).

**Interfaces:**
- Consumes: `useUiStore` (`frontend/src/renderer/stores/ui-store.ts`), `Switch`
  (`frontend/src/renderer/components/ui/switch`), `DEFAULT_QUICK_FIX_RULES` and `QuickFixRule`
  (Task 4/6), the shell `BlockTerminal`'s `quickFixRules` pass-through (Task 7).
- Produces: `terminalQuickFixesEnabled: boolean` and `setTerminalQuickFixesEnabled(next: boolean):
  void` on the ui-store; `readStoredTerminalQuickFixesEnabled(): boolean`,
  `terminalQuickFixesEnabledStorageKey`, `defaultTerminalQuickFixesEnabled` in
  `lib/terminal-quick-fixes.ts`. Nothing outside `frontend/` consumes this — `packages/terminal`
  gains no new prop, per the Global Constraints addition below.

- [ ] **Step 1: Write the failing tests**

Add to `frontend/src/renderer/components/settings/GeneralSettingsSection.test.tsx` (same render
harness the existing `terminalPredictiveEcho` toggle test uses):

```tsx
it("persists the quick-fix switch across a reload", () => {
	const { getByLabelText, unmount } = render(<GeneralSettingsSection onConnectMobile={vi.fn()} />);
	const toggle = getByLabelText("Suggest fixes for failed commands");
	expect(toggle).toBeChecked();
	fireEvent.click(toggle);
	expect(toggle).not.toBeChecked();
	unmount();
	const remounted = render(<GeneralSettingsSection onConnectMobile={vi.fn()} />);
	expect(remounted.getByLabelText("Suggest fixes for failed commands")).not.toBeChecked();
});
```

Add to `frontend/src/renderer/components/BlockTerminal.test.tsx`, in the `describe` Task 7 adds
for shared history and quick fixes:

```tsx
it("passes no quick-fix rules when the setting is off", () => {
	useUiStore.getState().setTerminalQuickFixesEnabled(false);
	render(<BlockTerminal {...shellProps} />);
	expect(surfaceProps().quickFixRules).toEqual([]);
});

it("passes the starter rules when the setting is on", () => {
	useUiStore.getState().setTerminalQuickFixesEnabled(true);
	render(<BlockTerminal {...shellProps} />);
	expect(surfaceProps().quickFixRules).toBe(DEFAULT_QUICK_FIX_RULES);
});

it("shows fixes again immediately after the setting is switched back on, without a reload", () => {
	useUiStore.getState().setTerminalQuickFixesEnabled(false);
	const { rerender } = render(<BlockTerminal {...shellProps} />);
	expect(surfaceProps().quickFixRules).toEqual([]);
	act(() => useUiStore.getState().setTerminalQuickFixesEnabled(true));
	rerender(<BlockTerminal {...shellProps} />);
	expect(surfaceProps().quickFixRules).toBe(DEFAULT_QUICK_FIX_RULES);
});
```

`surfaceProps()` is this test file's existing helper that reads the last props the mocked
`TerminalSurface` was rendered with (the same helper Task 7's own history tests must use to assert
on `commandHistory`).

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend
npx vitest run --config vite.renderer.config.ts src/renderer/components/settings/GeneralSettingsSection.test.tsx src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Test Files|Tests  |FAIL"
```
Expected: the three new `BlockTerminal` cases fail (`terminalQuickFixesEnabled`/
`setTerminalQuickFixesEnabled` do not exist on the store yet); the settings case fails on the
missing label.

- [ ] **Step 3: Implement**

Write `frontend/src/renderer/lib/terminal-quick-fixes.ts`, the `ui-store.ts` additions, the
`GeneralSettingsSection.tsx` row, the `en.json` key and the `BlockTerminal.tsx` gate exactly as
described in **Files** above, mirroring `terminalPredictiveEcho`'s existing shape at each cited
line.

- [ ] **Step 4: Run to see them pass; typecheck; lint**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend
npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-quick-fixes.test.ts src/renderer/components/settings/GeneralSettingsSection.test.tsx src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Test Files|Tests  "
npm run typecheck 2>&1 | tail -2
```
Expected: every file passes; typecheck silent.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add frontend/src/renderer/lib/terminal-quick-fixes.ts frontend/src/renderer/stores/ui-store.ts frontend/src/renderer/components/settings/GeneralSettingsSection.tsx frontend/src/renderer/components/settings/GeneralSettingsSection.test.tsx frontend/src/renderer/i18n/en.json frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx
git commit -m "feat(settings): on/off switch for terminal quick fixes, on by default

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7.6: Backend — retention cleanup for closed terminal blocks

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0121_terminal_blocks_retention.sql` — the
  next free migration number after this plan's own `0120` (Task 1); `0120` is the highest number
  on `development` as of this amendment (`ls backend/internal/storage/sqlite/migrations | sort -V |
  tail -1` → `0119_session_launch_permission_mode.sql` before Task 1 lands `0120`), so `0121` is
  free unless another branch claims it first, in which case renumber per Global Constraints.
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go:126` (append `121:
  "0121_terminal_blocks_retention.sql",` after Task 1's `120:` entry) — this is the ledger
  `TestMigrationVersionLedger` checks (`migrate_burned_versions_test.go:152`,
  "every migration file has exactly one entry in shippedMigrations").
- Create: `backend/internal/storage/sqlite/queries/terminal_blocks_retention.sql` (or appended to
  `terminal_blocks.sql`) — `DeleteOrphanedTerminalBlocksOlderThan` and
  `CountOrphanedTerminalBlocks`, see design below.
- Regenerate: `backend/internal/storage/sqlite/gen/terminal_blocks.sql.go` (or a new
  `terminal_blocks_retention.sql.go`) via `npm run sqlc`.
- Create: `backend/internal/observe/blockretention/{retention.go,retention_test.go}` — the janitor,
  following `backend/internal/observe/reaper/reaper.go`'s shape exactly (package doc, `Config{Tick,
  Clock, Logger}`, `New(store, cfg) *Retention`, `Start(ctx) <-chan struct{}` launching
  `time.NewTicker(r.tick)` in a goroutine, an exported `Tick(ctx) error` the daemon and tests can
  also drive synchronously — `reaper.go:18-20,37-48,64-124`).
- Modify: `backend/internal/daemon/lifecycle_wiring.go` — wire the janitor next to the reaper in
  `startLifecycle` (`:57-72`): `New(store, blockretention.Config{Logger: logger})` then
  `.Start(ctx)`, its done channel added to `lifecycleStack` next to `reaperDone` (`:46-51`).
- Modify: `backend/internal/service/terminalblock/types.go:13` (widen `Store` again, after Task 1's
  `ListRecentTerminalCommands` line) and `backend/internal/storage/sqlite/store/terminal_block_store.go`
  (new adapter methods after `ListRecentTerminalCommands`, Task 1's insertion point).
- Modify: the same two test fakes Task 1 touches —
  `backend/internal/service/terminalcapture/supervisor_test.go:206+` and
  `backend/internal/adapters/runtime/parity/decision_sites_test.go:268+` — with one more method each
  for the widened port.
- Test: `backend/internal/observe/blockretention/retention_test.go` (new, real SQLite store per
  Global Constraints "no network calls… prefer fakes" — a store is not a network call and Task 1's
  own tests already open a real `sqlite.Open` in-process, `service/terminalblock/service_test.go`'s
  `newService` helper).

**Design (evidence-based, following the schema Task 1 already reads):**
- What "closed and not restorable" means for a `terminal_blocks.terminal_id`: shell terminals are
  the only source of `terminal_blocks` rows (Decision 1: "agent (worker) panes are not captured";
  `backend/internal/service/terminalcapture/supervisor.go:80-97` records only shell terminal
  blocks). A shell terminal has exactly one durable row while it can still be re-attached to —
  `shell_terminals.handle_id` (`backend/internal/storage/sqlite/migrations/0027_shell_terminals.sql:20-27`,
  primary key `handle_id`) — and that row is deleted only in
  `backend/internal/service/shellterm/service.go`'s `destroyConfirmed` (`:356-368`, called from
  `CloseShellTerminal` `:217-242`, `ListShellTerminalsForCurrentAppRun`'s dead-row prune `:274-302`,
  and `ReapShellTerminalsFromPreviousAppRuns` `:315-339`) — never paused, never soft-deleted. There
  is no restore/relaunch path for a shell terminal once its `shell_terminals` row is gone (that
  concept — §4.38's `Restore`/relaunch — is `session_manager`'s, for agent sessions, which do not
  write `terminal_blocks` at all). So a terminal is "closed and not restorable" for this feature
  exactly when its `terminal_id` has **no** matching row left in `shell_terminals`; a
  `terminal_blocks.terminal_id` that still has a `shell_terminals` row is either still open or was
  merely disconnected and can still be re-attached (`ListShellTerminalsForCurrentAppRun` repopulates
  tabs after a daemon restart, `service.go:244-264`), so its blocks are never touched.
- Cleanup, in the plan's own words for Decision 4 ("Retention is unchanged: 100 blocks per
  terminal… open decision 6 covers the unbounded growth of closed terminals' rows"): rather than a
  new small table, keep the existing `terminal_blocks` schema (Global Constraint: do not modify a
  shipped migration) and add one column and one query pair, since the shared-history feature this
  plan builds needs exactly `command`, `cwd`, `finished_at` per row (`0092_terminal_blocks.sql:14-34`)
  and nothing from `raw_output` once a terminal is gone — `raw_output BLOB NOT NULL` is the only
  column that can hold megabytes (Decision 1's table: "100 blocks × 8 MiB raw output each per
  terminal"). Migration `0121` adds `raw_output_cleared_at TIMESTAMP` (nullable) to `terminal_blocks`
  (an `ALTER TABLE … ADD COLUMN`, additive and safe on a live SQLite file, the same shape as
  `0118_session_agent_report.sql`/`0119_session_launch_permission_mode.sql` use for their own
  additive columns — not read here in full, but every migration after `0092` in this directory adds
  columns/indexes rather than rewriting tables, per `ls` above).
- `DeleteOrphanedTerminalBlocksOlderThan(ctx, cutoff)`:
  `UPDATE terminal_blocks SET raw_output = x'', raw_output_cleared_at = ? WHERE raw_output_cleared_at
  IS NULL AND finished_at < ? AND terminal_id NOT IN (SELECT handle_id FROM shell_terminals)` clears
  the heavy bytes but keeps the row (`command`, `cwd`, `finished_at`, `exit_code` survive, so
  `ListRecentTerminalCommands` — Task 1 — and the durable-block list a reopened pane would have shown
  keep working); a second statement,
  `DELETE FROM terminal_blocks WHERE raw_output_cleared_at IS NOT NULL AND raw_output_cleared_at <
  ? AND terminal_id NOT IN (SELECT handle_id FROM shell_terminals)`, drops the whole row once it has
  been cleared for a second, longer grace period (rows already contributing nothing but their small
  metadata are removed once history has no further use for them). Never touches a `terminal_id`
  that still has a `shell_terminals` row — the `NOT IN` guard is the "never delete a restorable
  terminal's blocks" rule from the task brief, enforced in the SQL itself rather than in Go, so it
  cannot be bypassed by a future caller.
- Defaults (documented in the janitor's `Config`, following `reaper.DefaultTickInterval`
  `reaper.go:18-20`): clear raw output 7 days after `finished_at` for an orphaned terminal, delete
  the row 30 days after clearing; the janitor ticks once at daemon start (via the same
  `ReconcileRuntime`-style synchronous `Tick` call `lifecycle_wiring.go:74-79` pattern) and every 6
  hours after.

**Interfaces:**
- Consumes: `terminalblock.Store` (widened again), `shell_terminals` via a plain `NOT IN` subquery
  (no new Go port needed for the join — it is one SQL statement against two tables already in the
  same SQLite file, matching how `TrimTerminalBlocks` (`terminal_block_store.go:63-75`) is already a
  single multi-row statement).
- Produces: `blockretention.Retention`, `blockretention.Config{Tick, Clock, Logger, RawOutputGrace,
  RowGrace}`, `blockretention.New(store, cfg) *Retention`, `(*Retention).Start(ctx) <-chan
  struct{}`, `(*Retention).Tick(ctx) (cleared, deleted int64, err error)` — `cleared` is the number
  of rows whose `raw_output` was just zeroed (a count, not a byte total: sqlc's `:execrows` only
  reports rows affected) and `deleted` the number of rows removed outright, both asserted on by the
  tests below; `terminalblock.Store.ClearOldOrphanedRawOutput(ctx, cutoff time.Time) (rows int64,
  err error)`, `terminalblock.Store.DeleteFullyClearedOrphanedBlocks(ctx, cutoff time.Time) (rows
  int64, err error)`. "Reclaimed bytes" (Review Focus 7) is verified in the test by measuring
  `LENGTH(raw_output)` (via a small test-only query, or by reading the row back through the store)
  before and after `Tick`, not by a byte count the store returns.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/observe/blockretention/retention_test.go` (real SQLite, following
`service/terminalblock/service_test.go`'s `newService`/`sampleBlock` shape and Task 1's
`recordCommand` helper for inserting blocks; `insertShellTerminal` is this test file's own small
helper around `store.InsertShellTerminal`):

```go
package blockretention_test

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/observe/blockretention"
)

func TestTickReclaimsRawOutputThenTheRowOnceTheDeleteGraceAlsoPasses(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertBlock(t, store, "closed-term", "1", "make build", []byte("a lot of output"), now.Add(-40*24*time.Hour))

	clock := now
	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return clock }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick 1: %v", err)
	}
	if cleared != 1 || deleted != 0 {
		t.Fatalf("tick 1 cleared=%d deleted=%d, want 1,0 (raw_output_cleared_at is set to now, so the delete grace has not started yet)", cleared, deleted)
	}
	if runs, err := listCommandRuns(t, store); err != nil || len(runs) != 1 || runs[0] != "make build" {
		t.Fatalf("history right after clearing = %v, err %v, want [make build] (the row survives, only raw_output is gone)", runs, err)
	}

	clock = now.Add(31 * 24 * time.Hour)
	cleared, deleted, err = r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick 2: %v", err)
	}
	if cleared != 0 || deleted != 1 {
		t.Fatalf("tick 2 cleared=%d deleted=%d, want 0,1 (31 days past the clear, past the row-delete grace)", cleared, deleted)
	}
	runs, err := listCommandRuns(t, store)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(runs) != 0 {
		t.Fatalf("history after full retention = %v, want empty (row deleted)", runs)
	}
}

func TestTickKeepsCommandHistoryOfARecentlyClearedTerminal(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertBlock(t, store, "closed-term", "1", "make build", []byte("output"), now.Add(-8*24*time.Hour))

	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return now }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick: %v", err)
	}
	if cleared != 1 || deleted != 0 {
		t.Fatalf("cleared=%d deleted=%d, want 1,0", cleared, deleted)
	}
	runs, err := listCommandRuns(t, store)
	if err != nil || len(runs) != 1 || runs[0] != "make build" {
		t.Fatalf("history = %v, err %v, want [make build]", runs, err)
	}
}

func TestTickNeverTouchesARestorableTerminal(t *testing.T) {
	ctx := context.Background()
	store := newTestStore(t)
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	insertShellTerminal(t, store, "open-term", now.Add(-90*24*time.Hour))
	insertBlock(t, store, "open-term", "1", "make build", []byte("output"), now.Add(-90*24*time.Hour))

	r := blockretention.New(store, blockretention.Config{Clock: func() time.Time { return now }})
	cleared, deleted, err := r.Tick(ctx)
	if err != nil {
		t.Fatalf("tick: %v", err)
	}
	if cleared != 0 || deleted != 0 {
		t.Fatalf("cleared=%d deleted=%d, want 0,0 (the terminal still has a shell_terminals row)", cleared, deleted)
	}
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go test ./internal/observe/blockretention/... -count=1 2>&1 | head -10
```
Expected: build failure — the `blockretention` package does not exist yet.

- [ ] **Step 3: Migration, ledger, queries, generated code**

Create `backend/internal/storage/sqlite/migrations/0121_terminal_blocks_retention.sql`:

```sql
-- +goose Up
-- +goose StatementBegin
ALTER TABLE terminal_blocks ADD COLUMN raw_output_cleared_at TIMESTAMP;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE terminal_blocks DROP COLUMN raw_output_cleared_at;
-- +goose StatementEnd
```

In `backend/internal/storage/sqlite/migrate_burned_versions_test.go`, after Task 1's `120:` entry
(`:126` before Task 1 lands, one line lower after it) add:

```go
	121: "0121_terminal_blocks_retention.sql",
```

Append to `backend/internal/storage/sqlite/queries/terminal_blocks.sql`:

```sql

-- name: ClearOldOrphanedRawOutput :execrows
UPDATE terminal_blocks
SET raw_output = x'', raw_output_cleared_at = ?
WHERE raw_output_cleared_at IS NULL
  AND finished_at < ?
  AND terminal_id NOT IN (SELECT handle_id FROM shell_terminals);

-- name: DeleteFullyClearedOrphanedBlocks :execrows
DELETE FROM terminal_blocks
WHERE raw_output_cleared_at IS NOT NULL
  AND raw_output_cleared_at < ?
  AND terminal_id NOT IN (SELECT handle_id FROM shell_terminals);
```

Run `npm run sqlc` and confirm only the generated file changes, as Task 1 Step 3 does.

- [ ] **Step 4: Store methods, port, janitor**

Add `ClearOldOrphanedRawOutput`/`DeleteFullyClearedOrphanedBlocks` to
`backend/internal/storage/sqlite/store/terminal_block_store.go` (after Task 1's
`ListRecentTerminalCommands`), each wrapping the generated `:execrows` call and returning the
affected-row count as `int64`; widen `terminalblock.Store` (`types.go:13`) with both methods; add
the two no-op implementations to the two test fakes Task 1 already touches.

Create `backend/internal/observe/blockretention/retention.go` matching
`backend/internal/observe/reaper/reaper.go`'s shape: `Config{Tick, Clock, Logger, RawOutputGrace,
RowGrace}` with defaults `DefaultRawOutputGrace = 7 * 24 * time.Hour`, `DefaultRowGrace = 30 * 24 *
time.Hour`, `DefaultTickInterval = 6 * time.Hour`; `New(store, cfg) *Retention`; `Start(ctx) <-chan
struct{}` launching the same ticker-loop shape as `reaper.go:104-124`; `Tick(ctx) (cleared, deleted
int64, err error)` calling the two store methods with `now.Add(-RawOutputGrace)` and
`now.Add(-RowGrace)` and logging counts at `Info` when non-zero, matching the reaper's log-but-
never-propagate-per-item posture (`reaper.go:181-186`).

- [ ] **Step 5: Run to see them pass**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend
go test ./internal/observe/blockretention/... ./internal/service/terminalblock/... ./internal/storage/sqlite/... -count=1 2>&1 | grep -v "no test files"
```
Expected: every line `ok`, `TestMigrationVersionLedger` included.

- [ ] **Step 6: Wire into the daemon**

In `backend/internal/daemon/lifecycle_wiring.go`, add the janitor to `startLifecycle` next to the
reaper (`:64-71`) and its done channel to `lifecycleStack` (`:46-51`); add a
`ReconcileBlockRetention(ctx) error` next to `ReconcileRuntime` (`:74-79`) calling the janitor's
`Tick` once at boot, following the same rationale comment ("folds work missed while Operator was
stopped… before the API starts serving").

- [ ] **Step 7: Lint and commit**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && gofmt -l internal/ && go vet ./internal/observe/... ./internal/storage/... ./internal/daemon/... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./internal/observe/blockretention/... ./internal/storage/sqlite/... ./internal/daemon/...
cd /Users/omaraly/development/AI/Operator-wave1-input-box
git add backend/internal/storage/sqlite/migrations/0121_terminal_blocks_retention.sql backend/internal/storage/sqlite/migrate_burned_versions_test.go backend/internal/storage/sqlite/queries/terminal_blocks.sql backend/internal/storage/sqlite/gen/terminal_blocks.sql.go backend/internal/service/terminalblock/types.go backend/internal/storage/sqlite/store/terminal_block_store.go backend/internal/observe/blockretention/retention.go backend/internal/observe/blockretention/retention_test.go backend/internal/service/terminalcapture/supervisor_test.go backend/internal/adapters/runtime/parity/decision_sites_test.go backend/internal/daemon/lifecycle_wiring.go
git commit -m "feat(backend): retention cleanup for closed terminals' blocks, never touching a restorable one

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `gofmt` prints nothing, `0 issues.`, one commit.

---

### Task 8: Gates

**Files:** none changed (a gate that fails sends you back to the owning task).

**Interfaces:** Consumes every earlier task. Produces the numbers for the report.

- [ ] **Step 1: TS packages, boundaries, node tests, feel**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && npm run build:ts 2>&1 | grep -i error
for p in core renderer-dom react editor completions; do (cd ts/$p && echo "$p $(npx vitest run 2>&1 | grep -E 'Tests  ')"); done
npm run check:boundaries 2>&1 | tail -2
node --test ./scripts/browser-types.test.mjs ./scripts/spawn-recipe-package.test.mjs ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
npm run bench:feel 2>&1 | tail -1
git -C /Users/omaraly/development/AI/Operator-wave1-input-box status --short packages/terminal/bench backend/internal/adapters/runtime/ptyhost/vtwasm/assets
```
Expected: no `error`; `core 180`, `renderer-dom 995`, `react 159`, `editor 218`, `completions 109` passed; `boundary check passed`; `ℹ pass 7`, `ℹ fail 0`; `PASS feel gate: zero pixel diff`; the status line prints nothing (no baseline or wasm change).

- [ ] **Step 2: Frontend**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/frontend && npm run typecheck 2>&1 | tail -1 && npm run test 2>&1 | grep -E "Test Files|Tests  "
```
Expected: typecheck silent; every file passes (planning run: `Test Files  173 passed (173)`, `Tests  1742 passed (1742)` — 11 more tests than the base: 7 store + 4 `BlockTerminal`; **amendment 2026-09-27, Tasks 7.5/7.6:** add 1 more test file (`GeneralSettingsSection.test.tsx` already exists, gains 1 case) and 4 more `BlockTerminal.test.tsx` cases — the exact new totals were not run and are `not known`; report the actual numbers from this run).

- [ ] **Step 3: Backend**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend
env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') go test ./... -count=1 2>&1 | grep -Ev "^ok|no test files" | head
go vet ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs 2>&1 | tail -2
cd /Users/omaraly/development/AI/Operator-wave1-input-box && npm run api >/dev/null 2>&1 && git status --short backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```
Expected: the first command prints nothing (every package `ok`); `0 issues.`; the last prints nothing (regenerating the spec changes nothing that is not already committed). If `TestProcessEnvironmentLetsOverridesWin` fails in `ptyhost`, it is the known pre-existing failure (`TERMINAL.md` §8) — rerun it alone and report. **Amendment 2026-09-27:** `go test ./...` already walks `./internal/observe/blockretention/...` and the widened `TestMigrationVersionLedger`, so no new backend gate command is needed for Task 7.6; the same is true of Step 2 above for Task 7.5's frontend tests (`npm run test` is repo-wide).

- [ ] **Step 4: Shell integration suites (unchanged scripts; only if tmux is installed)**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal && command -v tmux >/dev/null && node --test ./shell/zsh.test.mjs ./shell/bash.test.mjs ./shell/fish.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
```
Expected: `ℹ fail 0`, or `not run: tmux unavailable` in the report. No shell script changed in this plan.

---

### Task 9: Real checks, docs, changelog

**Files:**
- Modify: `TERMINAL.md` — insert `### 4.53 …` after §4.50 (which ends before `## 5. Known gaps`, line 1987 on `611254eb3`; after the sibling plans land it is the line before `## 5.`); the amendment (2026-09-27) adds the switch and retention design to the same §4.53 body (see the "Now, the switch and retention" bullet below), so no second section number is needed
- Modify: `packages/terminal/CHANGELOG.md:3-4` (two entries at the top of "Unreleased")
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:3827` (§6.6 status), `:3886` (§6.8 status)

**Interfaces:** Consumes the whole branch. Produces the docs and the real-check evidence.

- [ ] **Step 1: Real check A — isolated daemon, real zsh, the route (API evidence)**

Scratch only; nothing here is committed. `SCRATCH` is your session scratchpad directory.

```bash
export SCRATCH=<your scratchpad dir>
cd /Users/omaraly/development/AI/Operator-wave1-input-box/backend && go build -o "$SCRATCH/opr-input-box" ./cmd/opr
mkdir -p "$SCRATCH/daemon-data"
env -i HOME="$HOME" PATH="$PATH" SHELL=/bin/zsh TERM=xterm-256color OPERATOR_DATA_DIR="$SCRATCH/daemon-data" OPERATOR_RUN_FILE="$SCRATCH/daemon-data/run.json" OPERATOR_PORT=39311 "$SCRATCH/opr-input-box" daemon > "$SCRATCH/daemon.log" 2>&1 &
for i in $(seq 1 20); do curl -sf http://127.0.0.1:39311/api/v1/terminal-history && break; sleep 1; done
```
Expected: `{"commands":[]}`. Never use the user's ports 3001/3002.

Save as `$SCRATCH/prime-history.mjs` (opens a real shell terminal through the API and types into it through the `/mux` socket, the same frames the renderer sends, `frontend/src/renderer/lib/terminal-mux.ts:76-90`):

```js
const base = process.argv[2] ?? "http://127.0.0.1:39311";
const commands = process.argv.slice(3);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const opened = await fetch(`${base}/api/v1/shell-terminals`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
if (!opened.ok) throw new Error(`open shell: ${opened.status} ${await opened.text()}`);
const { shellTerminal } = await opened.json();
const id = shellTerminal.handleId;
const socket = new WebSocket(`${base.replace(/^http/, "ws")}/mux`);
await new Promise((resolve, reject) => {
	socket.addEventListener("open", resolve, { once: true });
	socket.addEventListener("error", reject, { once: true });
});
socket.send(JSON.stringify({ ch: "terminal", type: "open", id, cols: 100, rows: 30 }));
await sleep(1500);
for (const command of commands) {
	socket.send(JSON.stringify({ ch: "terminal", type: "data", id, data: Buffer.from(`${command}\r`).toString("base64") }));
	await sleep(700);
}
await sleep(1500);
socket.close();
console.log(JSON.stringify({ handleId: id }));
```

```bash
node "$SCRATCH/prime-history.mjs" http://127.0.0.1:39311 "echo one" "export API_TOKEN=abcdefghijklmnop" "echo two"
curl -s http://127.0.0.1:39311/api/v1/terminal-history; echo
```
Expected: `{"handleId":"shellterm-…"}`, then exactly `echo one` and `echo two` (with `finishedAt`), no `API_TOKEN` (planning run: `{"commands":[{"command":"echo one",…},{"command":"echo two",…}]}`).

- [ ] **Step 2: Real check B — headless Chromium against a Vite page with the real package and the daemon above**

The Operator renderer in a browser shows a demo terminal (`docs/terminal/2026-09-26-real-app-test-runbook.md` §0 rule 4), so this check mounts the real `TerminalSurface`, the real wasm core and the real `DEFAULT_QUICK_FIX_RULES` in a Vite page whose `/api` is proxied to the isolated daemon. The page lives in a `mkdtemp` directory inside `packages/terminal` (the precedent is `scripts/browser-types.test.mjs:12`, `.browser-types-*`) and is deleted at the end. Save as `$SCRATCH/input-box-check.mjs`:

```js
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

const packageRoot = resolve(process.argv[2]);
const daemon = process.argv[3] ?? "http://127.0.0.1:39311";
const shots = resolve(process.argv[4] ?? ".");
const { createServer } = await import(join(packageRoot, "node_modules/vite/dist/node/index.js"));
const { default: react } = await import(join(packageRoot, "node_modules/@vitejs/plugin-react/dist/index.js"));
const { chromium } = await import(join(packageRoot, "node_modules/playwright/index.mjs"));

const PUSH = [
	"fatal: The current branch feat has no upstream branch.",
	"To push the current branch and set the remote as upstream, use",
	"",
	"    git push --set-upstream origin feat",
	"",
].join("\\r\\n");

const main = `
import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { DEFAULT_QUICK_FIX_RULES, TerminalSurface, createTerminalCore, initTerminalCoreFromUrl, warpDarkTheme } from "@operator/terminal-react";
const FONT = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };
const listeners = new Set();
let entries = [];
async function load() {
	const response = await fetch("/api/v1/terminal-history?limit=1000");
	const body = await response.json();
	entries = body.commands.map((entry) => ({ command: entry.command, at: Date.parse(entry.finishedAt) }));
	document.body.dataset.historyCount = String(entries.length);
	for (const listener of [...listeners]) listener();
}
const history = {
	entries: () => entries,
	subscribe: (listener) => { listeners.add(listener); return () => listeners.delete(listener); },
	refresh: () => { void load(); },
};
window.__sent = [];
function App() {
	const [core, setCore] = useState(null);
	useEffect(() => {
		void (async () => {
			await initTerminalCoreFromUrl();
			await load();
			setCore(createTerminalCore({ columns: 100, scrollback: 500 }));
		})();
	}, []);
	useEffect(() => {
		if (!core) return;
		core.feed(new TextEncoder().encode("\\x1b]7000;v=1;input-ready=1\\x07"));
		document.body.dataset.ready = "1";
	}, [core]);
	window.__fail = () => core.feed(new TextEncoder().encode("\\x1b]7000;v=1;input-released=1\\x07\\x1b]133;A\\x07\\x1b]7000;v=1;cmd=git%20push\\x07\\x1b]133;C\\x07${PUSH}\\r\\n\\x1b]133;D;128\\x07\\x1b]7000;v=1;input-ready=1\\x07"));
	return core ? <div style={{ height: 400 }}><TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={(text) => window.__sent.push(text)} onSendRaw={() => {}} commandHistory={history} quickFixRules={DEFAULT_QUICK_FIX_RULES} /></div> : null;
}
const container = document.getElementById("root");
if (container.dataset.mounted !== "1") {
	container.dataset.mounted = "1";
	createRoot(container).render(<App />);
}
`;

const dir = await mkdtemp(join(packageRoot, ".input-box-check-"));
const results = [];
const check = (name, pass, detail) => results.push({ name, pass, detail });
let server;
let browser;
try {
	await writeFile(join(dir, "index.html"), `<!doctype html><html><body style="margin:0;background:#000"><div id="root"></div><script type="module" src="./main.tsx"></script></body></html>`);
	await writeFile(join(dir, "main.tsx"), main);
	server = await createServer({
		configFile: false,
		root: dir,
		plugins: [react()],
		logLevel: "error",
		server: { host: "127.0.0.1", port: 0, proxy: { "/api": daemon } },
	});
	await server.listen();
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1000, height: 500 } });
	const errors = [];
	page.on("pageerror", (error) => errors.push(String(error)));
	await page.goto(`http://127.0.0.1:${port}/`);
	await page.waitForSelector("body[data-ready='1']", { timeout: 20000 });
	const count = Number(await page.getAttribute("body", "data-history-count"));
	check("R1 daemon history reached the page", count >= 2, { count });
	const editor = page.locator(".terminal-editor");
	await editor.focus();
	await page.keyboard.press("ArrowUp");
	const first = await page.locator(".terminal-editor-content").innerText();
	check("R2 ArrowUp recalls the newest daemon command", first.includes("echo two"), { first });
	await page.keyboard.press("ArrowUp");
	const second = await page.locator(".terminal-editor-content").innerText();
	check("R3 a second ArrowUp walks back", second.includes("echo one"), { second });
	check("R4 the secret command is not recallable", !second.includes("API_TOKEN") && !first.includes("API_TOKEN"), {});
	await page.keyboard.press("ArrowDown");
	await page.keyboard.press("ArrowDown");
	await page.screenshot({ path: join(shots, "input-box-history.png") });
	await page.evaluate(() => window.__fail());
	const chip = page.locator(".terminal-editor-quick-fix");
	await chip.waitFor({ timeout: 5000 });
	const chipText = await chip.innerText();
	check("R5 the failed push shows the set-upstream fix", chipText.includes("git push --set-upstream origin feat"), { chipText });
	await page.screenshot({ path: join(shots, "input-box-quick-fix.png") });
	await chip.locator("button").click();
	const sentAfterClick = await page.evaluate(() => [...window.__sent]);
	const boxText = await page.locator(".terminal-editor-content").innerText();
	check("R6 Use fills the box and sends nothing", sentAfterClick.length === 0 && boxText.includes("git push --set-upstream origin feat"), { sentAfterClick, boxText });
	await page.keyboard.press("Enter");
	const sent = await page.evaluate(() => [...window.__sent]);
	check("R7 Enter runs the fix", sent.at(-1) === "git push --set-upstream origin feat", { sent });
	check("R8 no page errors", errors.length === 0, { errors });
} finally {
	await browser?.close();
	await server?.close();
	await rm(dir, { recursive: true, force: true });
}
for (const result of results) console.log(`${result.pass ? "PASS" : "FAIL"} ${result.name} ${JSON.stringify(result.detail)}`);
process.exit(results.every((result) => result.pass) ? 0 : 1);
```

```bash
cd "$SCRATCH" && node input-box-check.mjs /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal http://127.0.0.1:39311 "$SCRATCH"
ls /Users/omaraly/development/AI/Operator-wave1-input-box/packages/terminal | grep input-box-check; echo "leftover=$?"
```
Expected (planning run, all eight): `PASS R1 daemon history reached the page {"count":2}`, `PASS R2 ArrowUp recalls the newest daemon command`, `PASS R3 a second ArrowUp walks back`, `PASS R4 the secret command is not recallable`, `PASS R5 the failed push shows the set-upstream fix`, `PASS R6 Use fills the box and sends nothing`, `PASS R7 Enter runs the fix`, `PASS R8 no page errors`; `leftover=1`. Look at `$SCRATCH/input-box-quick-fix.png`: the chip row "Suggested fix git push --set-upstream origin feat [Use]" sits above the prompt row, yellow label, bordered button, the fix as grey ghost text after the caret.

Stop everything you started (only your own processes):

```bash
pkill -f "$SCRATCH/opr-input-box"; sleep 1; pgrep -fl "$SCRATCH/opr-input-box" || echo stopped
```

- [ ] **Step 3: Real checks C — the desktop app (deferred to the wave's real-app run)**

These need the Tauri window, which a session cannot drive (`docs/terminal/2026-09-26-real-app-test-runbook.md` §0 rule 3), and the memory rule "Defer real-app checks to the roadmap end" applies. Do not restart `tauri:dev`. Write them into §4.53 as "Real-app checks still open" (Step 4 text below) and report them as `not run: needs the Tauri window`:

1. Two shell panes: run `echo from-a` in pane A; in pane B press ↑ → `echo from-a` (within 1 s of A's block finishing).
2. Restart the daemon and the app; open a new shell pane; ↑ → the last command from before the restart.
3. Close a shell pane that ran `make build`; in another pane ↑ reaches `make build`.
4. `export API_TOKEN=abcdefghijklmnop` in pane A; ↑ in pane B never shows it; ↑ in pane A still does.
5. In a git repo on a branch with no upstream, `git push` → chip "Suggested fix git push --set-upstream origin <branch> [Use]" above the prompt; click Use → the box holds the command, nothing ran; Enter → it runs.
6. `git stauts` → `git status`; `git commit -amend` → `git commit --amend`; `npx http-server -p 3000` twice → `kill $(lsof -t -iTCP:3000 -sTCP:LISTEN)`.
7. A Claude Code (worker) pane shows no chip and its ↑ is unchanged.
8. The phone: `GET /api/v1/terminal-history` over the LAN listener with the bearer password returns the same list; the phone app itself is unchanged.

- [ ] **Step 4: `TERMINAL.md` §4.53**

Numbering: run `grep -n '^### 4\.' TERMINAL.md | tail -1`. If the last entry is `4.52`, use `4.53` as written. Otherwise use the next number after the last one and replace `4.53` with it everywhere in this step and in Step 5.

Insert before `## 5. Known gaps (not bugs, decisions pending)`:

```markdown
### 4.53 The input box only knew this pane's commands and offered no fix for a failed one (wishlist wave 1, 2026-09-27)
- Symptom: ↑ in a shell pane's input box reached only the commands of that pane's own
  core (`LineEditor.ingestHistory` read `decodeBlocks` of this core, the model was reset at
  every mount), so a new pane, a reopened pane or another pane's work was out of reach;
  any output during a walk restarted it from the newest entry (`HistoryModel.ingest` reset
  the walk on every core change). A failed `git push` with no upstream left the user to
  copy the suggested command by hand.
- Now, history: the daemon answers `GET /api/v1/terminal-history` from `terminal_blocks`
  (every standalone shell block is already recorded there, closed terminals included):
  the newest 5,000 rows across terminals (index `terminal_blocks_finished`, migration
  0120), newest occurrence of each command, oldest first, 500 by default and 1,000 at
  most. Commands `redact.Text` would mask (built-ins and `redact-patterns.txt`), commands
  starting with a space, with a control character (newline and tab allowed), invalid
  UTF-8 or over 4 KiB never leave the daemon. The editor takes a host
  `CommandHistorySource { entries, subscribe, refresh? }` (`ts/editor/src/history.ts`);
  `HistoryModel` puts the pane's own block commands after the shared timeline (macOS
  Terminal's per-session history, `/etc/zshrc_Apple_Terminal:74-77`; Warp
  `app/src/terminal/history.rs:828-887`), dedupes globally, keeps the entry on screen when
  a refresh lands mid-walk, and ↓ past the newest returns the typed prefix. Operator's
  store (`frontend/src/renderer/lib/command-history.ts`) refreshes on first use, window
  focus, 500 ms after a shell block finishes and at the start of each walk.
- Now, quick fixes: a host passes `QuickFixRule[]`; the editor evaluates them once per
  block that becomes the newest settled block while mounted (never a replayed block,
  never on the alternate screen), reading the output once with
  `readBlockOutput(id, { maxLines: 201 })`. The fix shows above the prompt row ("Suggested
  fix … [Use]") and as ghost text while the box is empty; → or Use puts it in the box;
  typing hides it; nothing runs without Enter (Warp's command correction,
  `app/src/terminal/view.rs:15175-15215`). Starter rules ported from VS Code (MIT,
  `ts/editor/src/VSCODE-QUICK-FIX-ATTRIBUTION.md`): set-upstream push, similar git
  subcommand, two-dash git option, free a busy port. Captures pass narrow character
  classes and `safeFix` drops controls, newlines and no-op fixes, because anything on the
  pty can forge `cmd=` and output (no nonce yet, survey §6.1).
- Now, the switch and retention (amendment, 2026-09-27): quick fixes have an on/off switch in
  Settings → General, on by default (`frontend/src/renderer/lib/terminal-quick-fixes.ts`,
  `localStorage` key `opr.terminal.quickFixesEnabled`), gating `quickFixRules` between
  `DEFAULT_QUICK_FIX_RULES` and an empty array — the package needed no new prop, since an empty
  rule list already disables every fix. A closed shell terminal's blocks (no row left in
  `shell_terminals`) have their raw output cleared 7 days after the last command finished and the
  whole row deleted 30 days after that (`backend/internal/observe/blockretention`, migration 0121);
  a terminal that can still be re-attached to is never touched, checked in the SQL itself. The
  janitor runs once at daemon start and every 6 hours, the same shape as `observe/reaper`.
- Limits: history holds only commands run in Operator's standalone shell panes, 100 per
  terminal (`retainPerTerminal`); agent panes are not captured. Redaction matches shapes,
  not intent (`mysql -phunter2` is kept). A pane's own commands stay in its own ↑, secrets
  included, as before. A reopened pane's replayed commands rank above newer commands of
  other panes (by design: they are the pane's own). The shell's history file is not read.
- Real-app checks still open (need the Tauri window): two panes share ↑; ↑ after a daemon
  and app restart; a closed pane's command; a secret not shared; the push fix chip, Use,
  Enter; `git stauts`, `-amend`, busy port; no chip in a Claude Code pane; the phone reads
  the route over the LAN listener.
- Guards: `service/terminalblock/history_test.go`, `integration/shell_history_test.go`
  (zsh, bash, fish; close and reopen), `controllers/terminal_history_test.go`,
  `ts/editor/src/{history,line-editor-history,quick-fix,line-editor-quick-fix}.test.ts`,
  `ts/react/src/TerminalSurface.history.test.tsx`,
  `frontend/src/renderer/lib/command-history.test.ts`, `BlockTerminal.test.tsx` "BlockTerminal
  shared history and quick fixes", `GeneralSettingsSection.test.tsx` (switch reload case),
  `observe/blockretention/retention_test.go` (Task 7.5/7.6).
```

- [ ] **Step 5: CHANGELOG and survey status**

In `packages/terminal/CHANGELOG.md`, directly under `## Unreleased` (line 3) and its blank line, add:

```markdown
- editor/react: shared command history. `LineEditor.setHistorySource(source)` and `TerminalSurface`'s `commandHistory` prop take a host `CommandHistorySource { entries, subscribe, refresh? }`; ↑ walks the pane's own commands, then the host's entries newest first, without repeats, and keeps the recalled entry when a refresh lands mid-walk; ↓ past the newest entry returns the typed prefix. `HistoryModel` now has `setLocal`/`setShared`/`startRecall`/`step`/`endRecall` instead of `ingest`/`recall`. Output during a walk no longer restarts it from the newest entry. `HistoryStore` is removed from `@operator/terminal-core` (it was never used) (`TERMINAL.md` §4.53).
- editor/react: quick fixes. `LineEditor.setQuickFixRules(rules)` and `TerminalSurface`'s `quickFixRules` prop; when a finished command matches a rule, the fix shows above the prompt row with a Use button and as ghost text in the empty box, accepted with → or Use, never run without Enter. `DEFAULT_QUICK_FIX_RULES` (git set-upstream push, similar git subcommand, two-dash git option, free a busy port) are ported from VS Code (MIT). New strings `quickFixLabel`, `quickFixUse` (`TERMINAL.md` §4.53).
```

In `docs/terminal/2026-09-19-terminal-reference-survey.md`, line 3827 becomes:

```markdown
> **Status: Done (wishlist wave 1, 2026-09-27).** `QuickFixRule` matcher in `ts/editor` with a host-supplied rule list and four VS Code starter rules; the fix goes into the input box (chip + ghost), never runs by itself (`TERMINAL.md` §4.53). No `onQuickFix` event: every fix is a command. Not done: "ask the agent to fix this", opener fixes (`gitCreatePr`), the §6.1 nonce.
```

and line 3886 becomes:

```markdown
> **Status: Partial (wishlist wave 1, 2026-09-27).** ↑ in the input box reaches every shell terminal's commands, closed ones and ones from before a restart, from the daemon's durable blocks with secrets left out (`GET /api/v1/terminal-history`, `TERMINAL.md` §4.53). Not done: a "run recent" palette, recent directories, the shell's own history file.
```

- [ ] **Step 6: Check and commit the docs**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box && grep -n "^### 4.53\|^## 5\. Known" TERMINAL.md && sed -n 3,6p packages/terminal/CHANGELOG.md | cut -c1-80 && sed -n 3827p docs/terminal/2026-09-19-terminal-reference-survey.md | cut -c1-60 && sed -n 3886p docs/terminal/2026-09-19-terminal-reference-survey.md | cut -c1-60
git add TERMINAL.md packages/terminal/CHANGELOG.md docs/terminal/2026-09-19-terminal-reference-survey.md
git commit -m "docs(terminal): §4.53 shared input-box history and quick fixes, changelog, survey status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: the §4.53 heading right before `## 5. Known gaps`; the two changelog entries; both status lines start with `> **Status: Done (wishlist` / `> **Status: Partial (wishlist`.

---

### Task 10: Push and report (do not merge)

**Files:** none.

**Interfaces:** Consumes the branch. Produces the pushed branch and the report.

- [ ] **Step 1: Whole-branch review input**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box && git log --oneline origin/development..HEAD && git diff --stat origin/development...HEAD | tail -1
grep -rn "HistoryStore\|historyPrefix" packages/terminal/ts/*/src frontend/src | grep -v node_modules; echo "stale refs: $?"
```
Expected: eight commits (Tasks 1–7 and 9); `stale refs: 1`. **Amendment 2026-09-27:** with Tasks
7.5 and 7.6 built, ten commits (Tasks 1–7, 7.5, 7.6, 9).

- [ ] **Step 2: Push**

```bash
cd /Users/omaraly/development/AI/Operator-wave1-input-box && git push -u origin terminal/wave1-input-box
```

- [ ] **Step 3: Report**

Report: the branch; each task's commit; the Task 0 baselines and Task 8 numbers; real checks A and B line by line with the screenshot paths; checks C as `not run: needs the Tauri window`; anything that was `not run` and why; every deviation from this plan with its reason. Do not merge; the merge, the whole-branch review and the real-app run happen in the planning session (memory "Plan, clean session, then review").

---

## Open decisions for the user

1. **Ordering.** Chosen: the pane's own commands first, then everything else newest first (macOS Terminal and Warp). Alternative: one global timeline for every pane (zsh `SHARE_HISTORY`), which needs the shells to report command times (`start_ms`/`end_ms` in `shell/*.sh`) so replayed blocks stop looking new.
2. **Also read `~/.zsh_history` / `~/.bash_history` / fish history?** Not built. It would add commands typed outside Operator; it is a privacy decision (the file holds everything ever typed, unredacted) and Operator's zsh panes may not write to it (Decision 1). A daemon-side reader behind a Settings toggle, redacted the same way, fits the same route.
3. **A setting to turn quick fixes off.** ~~Not built; on for every shell pane. Warp has one (`terminal.input.command_corrections`, `warp/app/src/settings/input.rs:88-96`).~~ **Decided 2026-09-27 by the user:** quick fixes get an on/off switch in Operator's Settings → Terminal, on by default. Built in Task 7.5.
4. **The busy-port fix kills the listener.** `kill $(lsof -t -iTCP:<port> -sTCP:LISTEN)` goes into the box and needs Enter; a gentler variant shows only `lsof -nP -iTCP:<port> -sTCP:LISTEN`. Still open — unrelated to decisions 3 and 6 below.
5. **Agent panes.** No "ask the agent to fix this" (survey §6.6 proposal) and no history for Claude Code panes.
6. **Retention.** ~~Closed terminals' blocks are never deleted (`DeleteTerminalBlocks` has no caller), up to 100 blocks × 8 MiB raw output each per terminal ever opened. The history depends on those rows; a global cap (for example keep blocks from the last N terminals or N days) would bound the database without losing much history.~~ **Decided 2026-09-27 by the user:** retention for old terminal blocks is fixed in this plan. Built in Task 7.6.

> **Deviation note (amendment, 2026-09-27):** the user's decision referred to these as "Open Questions entries 3 and 4." This section is titled "Open decisions for the user" and its own numbering has the quick-fix switch at item 3 (an exact match) and retention at item **6**, not item 4 — item 4 here is the unrelated busy-port-kill-variant question, left open. This amendment applies the user's two decisions to items 3 and 6 by content, not by the literal number 4, and leaves item 4 open as before.
7. **The phone.** The route works over the LAN listener; a "recent commands" sheet in `packages/mobile` would need no daemon work.

## Risks

- Migration 0120 can collide with another branch; `TestMigrationVersionLedger` catches it and the fix is a rename (Global Constraints).
- `line-editor.ts` ends at 581 of 600 lines; the next editor feature should split it (the history and quick-fix logic already live in their own files).
- The `line-editor.ts` patches in Tasks 3 and 5 were cut against `611254eb3`; if a sibling plan changes `line-editor.ts` first, `git apply --check` fails and the hunks must be applied by hand from the same text.
- Sibling wave-1 plans also touch `TerminalSurface.tsx` (selection plan, line 330) and `types.ts` (line 80); the hunks here are elsewhere but a three-way merge may be needed.
- Redaction is shape-based; a secret without a known shape is shared across panes and to a paired phone.
- A failed block's output is joined once per failure with a matching rule (`readBlockOutput`, 201 lines kept but the whole block walked); a failure after a very long output costs one join.

## Self-review

- Spec coverage: wishlist 4 — ↑ reaches other panes (Task 3 tests, check C1), past restarts (integration reopen, check C2), newest first and no repeats (`HistoryModel` tests, service test); wishlist 5 — suggested fix with a button (Task 5, check B R5–R7), into the box only (Review Focus 4). Brief extras: evidence-based source choice (Decision 1), secrets (Decision 3), caps (Decision 4), host seam (`CommandHistorySource`, `QuickFixRule`), phone (Decision 7), UI placement with Warp citations (Decision 6), starter rules (Decision 6), 600-line limits (Global Constraints).
- Placeholders: none; every code block is the exact code run in the planning worktree; the only variable is `SCRATCH` (your scratchpad path) and the §4.53 number rule.
- Type consistency: `CommandHistoryEntry.at` is epoch ms everywhere (`Date.parse(finishedAt)` in Task 7); `QuickFixRule.exit` values match `findQuickFix`; `TerminalStrings` gains exactly `quickFixLabel`/`quickFixUse` in `types.ts`, both renderer-dom literals and `BlockTerminal.tsx`; `ShellTerminalBlockHistory.RecentCommands` matches `terminalblock.Service.RecentCommands` and the fake.
- Review focus: each of the five items names the tests that pin it, and each of those tests is in a task's Step 1.
