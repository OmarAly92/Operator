# Terminal Plan 6 — Typing Ahead, Shell Panes Only — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are unavailable in your session, run the same process by hand: one fresh implementer subagent per task, then a spec-compliance review subagent and a code-quality review subagent on that task's diff before the next task starts, then one whole-branch review subagent at the end.**

**Goal:** In a zsh shell pane, text the user types while a command is still running shows up in Operator's input box when the prompt returns — editable, never run by itself, and not doubled in the shell — while keys still reach the running program exactly as today and Claude Code panes do not change at all.

**Architecture:** Keys are never held back (`LineEditor.passthrough` is untouched). zsh's `line-init` hook, once per finished command and only at a primary prompt, reads the input waiting on the tty, pushes it straight back into zle with `zle -U` (so the shell keeps it exactly as before) and, when it is short and has no control character, reports it as `OSC 7000;v=1;typeahead=<percent-encoded UTF-8>` right after `input-ready`. vt-core keeps that report while the shell owns the line (`LineEditorTracker::on_typeahead`), `TerminalCore.takeTypeahead()` hands it over once, and `LineEditor` adopts it only when the user actually sent keys, IME text or a paste to the running command since the last adoption (`TypeaheadGate`), appends it to the input box and sends `^U` (0x15) so the shell's copy is cleared. A report nobody adopts (the daemon's own `SendMessage`, the phone, a program faking the mark) leaves the text with the shell, which then behaves exactly as it does today.

**Tech Stack:** zsh 5.x shell integration, Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`), wasm-bindgen 0.2.127, TypeScript 5.9 + vitest 4 (jsdom), node:test + tmux for real-shell tests, Go 1.25.7 (mark decoder, block assembler, pty-host, integration), Playwright 1.60 benches.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` — "Plan 6 — Typing ahead, shell panes only (§7.2)" (line 310) and "Rules every plan obeys" (line 39). Survey: `docs/terminal/2026-09-19-terminal-reference-survey.md` §7.2 (line 4113; table row line 133) — **Warp is AGPL-3.0: clean-room only.** This plan uses only the survey's behaviour description ("the shell reports its input buffer", Warp's `ShellReported`); no Warp file was read and none may be read. `TERMINAL.md` must be read end to end before Task 1.

**Shared files with the parallel plans of this wave** (Plan 3 vt-core OSC title/notifications, Plan 5 renderer highlights + marks, Plan 7 vt-core eviction ring): `packages/terminal/crates/vt-core/src/lib.rs` (582 lines after this plan — watch the 600-line cap on merge), `packages/terminal/crates/vt-wasm/src/lib.rs` (566 after), `packages/terminal/ts/core/src/terminal-core.ts` (571 after), `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (binary: on a merge conflict, rebuild it from the merged tree, never pick a side), `packages/terminal/protocol/SPEC.md`, `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md` (status table and count sentence), `docs/terminal/2026-09-24-not-done-plain-language.md`. Files only this plan touches: `shell/zsh.sh`, `go/bootstrap/shell/zsh.sh`, the three `shell/*.test.mjs`, `shell/README.md`, `crates/vt-core/src/line_editor.rs`, `ts/editor/src/line-editor.ts`, `ts/editor/src/typeahead.ts`, the new test files, `protocol/vectors/typeahead.json`, `backend/internal/terminal/block_assembler_test.go`.

---

## Global Constraints

- No comments in new code — Rust, TypeScript, Go, and the shell scripts (`TERMINAL.md` §3 rule 3; the user's global instruction). Existing comments may be corrected only if they become false.
- Commit with explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a`, or `git stash`.
- Work on branch `terminal/plan-6-typing-ahead` cut from `origin/development`. Never commit to `development` or `master`, never merge, never bump a version.
- End every commit message with exactly this trailer line: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- `packages/terminal` stays product-independent (`TERMINAL.md` §3 rule 1): nothing under `crates/`, `ts/` or `shell/` names Operator concepts (the existing `__operator_terminal_*` / `OPERATOR_TERMINAL_*` prefixes in the shell scripts are the package's own namespace and stay). This plan changes no file under `frontend/`.
- No file under `packages/terminal` may exceed 600 lines (`packages/terminal/scripts/check-boundaries.mjs:42`, `LINE_LIMIT = 600`). `ts/editor/src/line-editor.ts` is 576 today and 595 after Task 4 — do not add anything else to it.
- `packages/terminal/scripts/check-no-ownership-timer.mjs` fails any file under `ts/editor/src` that mentions `lineEditorState` and also contains `setTimeout`, `setInterval`, `requestIdleCallback` or `sleep`. The new editor test uses `setTimeout`, so it must never mention `lineEditorState` (it reads `root.dataset.ownership` instead).
- Cite `file:line` or write "not known" in every doc you write. Every number you report comes from a command you ran in this session.
- Keys are never held back: `LineEditor.passthrough` (`ts/editor/src/line-editor.ts:253-261`) keeps sending every key to the pty while the line is not owned. Never execute typed-ahead text: the editor only puts it in the buffer.
- Claude Code panes (and any pane without the shell integration) behave exactly as today: vt-core stores a report only while the line editor state is `Owned`, which a pane without `input-ready` never reaches.
- A `vt-core` change rebuilds both wasm artifacts (`npm run build:wasm -- --force` for the renderer; `cargo build --release -p vt-host --target wasm32-unknown-unknown` copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` and committed) and runs the pty-host Go tests (`TERMINAL.md` §6).
- `bench:feel` is compared against pixels recorded **on the unmodified tree in the same environment** (Task 0 Step 8). Never commit re-recorded baselines. `bench:affordances` rewrites committed PNGs: restore them with `git checkout -- packages/terminal/bench/agent-session/baselines` before any commit.
- Toolchain pins: `rustc 1.96.0` (`packages/terminal/rust-toolchain.toml`), `wasm-bindgen 0.2.127` exactly (`packages/terminal/scripts/build-wasm.mjs`), Go `1.25.7` (`backend/go.mod:3`), Playwright `1.60.0` (`packages/terminal/package.json`).
- Run the shell tests with `LANG=C.UTF-8 LC_ALL=C.UTF-8` in the environment (one test types `é` and `€` through tmux).
- New `TERMINAL.md` section number for this plan: **§4.32** (4.30 and 4.31 belong to parallel plans; the gap is expected if they have not merged yet).

## Review Focus

1. **A program or the daemon writes a command's text and its Enter as two writes, and the text arrives while the previous command is finishing.** The daemon's `SendMessage` does exactly that (`backend/internal/adapters/runtime/ptyhost/client.go:38-70`: text frames, a pause, then Enter as a separate frame). The shell cannot tell that text from the user's typeahead. Expected: the command still runs. Pinned by the zsh test "keeps the reported text in the shell when nothing clears it, so a separate Enter still runs it" (Task 5), the editor test "leaves a report it did not type to the shell" (Task 4), and the existing integration test `TestShellBlocksAlternateScreenAtCaptureStartExcludesRepaint` (run in Task 5 Step 9) — it failed 3 of 3 runs under the first design, in which the shell cleared its own buffer.
2. **A multi-line submission from the input box** (`frontend/src/renderer/components/BlockTerminal.tsx:254-256` writes `${text}\n`, so a pasted two-command buffer reaches zsh as `a\nb\n`; the second command is waiting on the tty when the first one's prompt returns). Expected: every command runs, nothing lands in the box. Pinned by the zsh test "runs every command of a multi-line submission and reports nothing" (Task 5).
3. **A program prints a fake report** (`cat` of a file holding `ESC]7000;v=1;input-ready=1 BEL ESC]7000;v=1;typeahead=rm%20-rf%20~ BEL`). Expected: nothing the user did not type appears in the box and no `^U` is sent. Pinned by the editor tests "leaves a report it did not type to the shell…" and "drops a report carrying a control character or longer than the cap…" (Task 4).
4. **A password typed at a program with echo off** (`read -s`, `sudo`). Expected: the program consumes it, nothing is reported, the password appears nowhere in the pane. Pinned by the zsh test "never surfaces a password a program read with echo off" (Task 5).
5. **Non-ASCII typeahead** (`echo café €`). Expected: the box shows exactly what was typed. The zsh encoder encoded code points, not bytes (`é` → `%e9`, `€` → `%c`; measured on `origin/development` @ `5185f35be`). Pinned by the zsh tests "reports typed-ahead UTF-8 as percent-encoded bytes" and "percent-encodes non-ASCII bytes as UTF-8" (Task 5), the vector `typeahead.json` (Task 1) and `a_typeahead_after_input_ready_is_taken_once` (Task 2).

---

## Design decisions (all fixed; evidence gathered 2026-09-25 on `origin/development` @ `5185f35be`, macOS, zsh 5.9, bash 3.2.57, fish 4.8.1, tmux)

1. **zsh is covered; bash and fish keep today's behaviour.**
   - zsh: at `line-init`, `$BUFFER` is still empty — zle has not read the typeahead yet. A probe widget printed `probe-buffer=[]` and `probe-pending=[echo hi]` after `sleep 1` with `echo hi` typed during it: `read -t 0 -k 1` inside the widget drains the waiting input, and `zle -U` gives it back.
   - bash: `READLINE_LINE` exists only inside a `bind -x` binding, and the additive-only contract forbids adding one (`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` §8, "MUST NOT … add or remove any `bindkey` / `bind` binding", line 872). A `PROMPT_COMMAND` drain can read the text (probe with `read -r -s -n 1 -t 1` returned `probe-pending=[echo hi]`), but bash has no way to hand it back to readline, so the daemon's `SendMessage` case (Review Focus 1) would lose its command. macOS `/bin/bash` 3.2 also takes only whole-second timeouts: with `-t 0` the probe read nothing and the next command ran as `echo hiecho after` (today's doubling, reproduced).
   - fish: `commandline` is empty in a `fish_prompt` handler (probe printed `probe-event=[]`, then fish inserted `echo hi` into its line after drawing the prompt), and fish's `read` has no timeout option (`read --help` lists none), so fish cannot peek without a key binding.
2. **The shell keeps the text; the line editor clears it.** The first design (shell drains and clears) made `TestShellBlocksAlternateScreenAtCaptureStartExcludesRepaint` fail 3/3: the daemon's `SendMessage` text arrived while the previous command was finishing, the shell reported and dropped it, and the separate Enter ran an empty line. Only the line editor knows the user typed the text, so only it clears the shell's copy, with `^U`. `^U` clears the whole line in zsh's emacs keymap (`kill-whole-line`) and in `viins` (`vi-kill-line` back to where insert began; the cursor is at the end of the pushed text) — both pinned by zsh tests.
3. **When the shell reports:** only at the first prompt after a command actually ran (`__operator_terminal_TYPEAHEAD_ARMED`, set in `precmd` when `__operator_terminal_COMMAND_RUNNING` was set), only when `$CONTEXT == start` (never at a `PS2` continuation), only when the waiting text is non-empty, at most 256 characters and has no control character (`[[:cntrl:]]`: newline, tab, ESC, DEL…). A line typed ahead with Enter is not reported and runs as before. The text is always pushed back with `zle -U`, reported or not.
4. **Encoding and cap:** `OSC 7000 ; v=1 ; typeahead=<value> BEL`, its own mark directly after the `input-ready` mark; the value is the text's UTF-8 bytes percent-encoded with the existing safe alphabet (`zsh.sh:6`), lowercase hex. Cap 256 characters: the worst case, 256 four-byte characters, is 3,072 encoded bytes + 19 bytes of prefix, under the decoder's 4,096-byte OSC cap (`crates/marks/src/scanner.rs:8` `PENDING_CAP`). The editor enforces the same cap and rejects any C0, DEL or C1 character (`acceptTypeahead`), so a report the shell script would never send is dropped.
5. **Where the report is parsed:** in vt-core, not in TS. The Rust scanner already decodes the key into a generic `MarkEvent::Extension` (the Go decoder too — no decoder change, the vector proves it). The line-editor state that gates it (`Owned`, alternate screen) lives in vt-core (`crates/vt-core/src/lib.rs:265-273`), and TS has no OSC scanner at all; a TS scanner would be a third decoder. Cost: both wasm artifacts are rebuilt.
6. **What the editor does with a report:** takes it on every core change, visible or not (`LineEditor`'s existing `onChange`, before the visibility check); adopts it only if `TypeaheadGate` saw keys, IME text or a paste go to the pty since mount or the last report; appends it to the buffer (cursor at the end) — never submits; then `sendRaw("\x15")`. A report it does not adopt is dropped and nothing is sent.
7. **Fixed on the way:** `__operator_terminal_pct_encode` in `zsh.sh` now encodes bytes (`setopt no_multibyte`, `printf -v … "'$ch"`) and matches the safe set literally (`== *"$ch"*`; the old unquoted pattern treated `?`, `[` as globs). This also corrects non-ASCII `cmd=`/`cwd=`. `bash.sh`'s encoder has the same code-point bug (`printf '%%%02x' "'$ch"` printed `%ffffffffffffffe2` for `€` on bash 3.2) and is **not** changed by this plan; the completion report lists it as a follow-up.

## File map

| File | Change | Responsibility |
|---|---|---|
| `packages/terminal/protocol/SPEC.md` | insert §4.5 before `## 5. Tier 2 — events emitted` (line 148) | define the `typeahead` key |
| `packages/terminal/protocol/vectors/typeahead.json` | create | normative vector for both decoders |
| `backend/internal/terminal/block_assembler_test.go` | append | the daemon's block assembler ignores the key |
| `packages/terminal/crates/vt-core/src/line_editor.rs` | rewrite (40 → 53 lines) | keep the last report while owned; drop it on release / alt screen |
| `packages/terminal/crates/vt-core/src/lib.rs` | modify `:268-273`, after `:469-471` | route the `typeahead` extension field; `take_typeahead` |
| `packages/terminal/crates/vt-core/tests/typeahead.rs` | create | vt-core behaviour, incl. the Claude recording |
| `packages/terminal/crates/vt-wasm/src/lib.rs` | modify after `:343-345` | `takeTypeahead` export |
| `packages/terminal/ts/core/src/terminal-core.ts` | modify after `:474-476` | `TerminalCore.takeTypeahead()` |
| `packages/terminal/ts/core/src/typeahead.test.ts` | create | core binding tests |
| `packages/terminal/ts/editor/src/typeahead.ts` | create | `TYPEAHEAD_MAX_CHARS`, `CLEAR_SHELL_LINE`, `acceptTypeahead`, `TypeaheadGate` |
| `packages/terminal/ts/editor/src/line-editor.ts` | modify `:21`, `:54`, `:67-68`, `:91-92`, `:104`, `:182-185`, `:244`, `:258-260`, before `:516` | adopt reports, note passthrough sends |
| `packages/terminal/ts/editor/src/line-editor-typeahead.test.ts` | create | editor behaviour, incl. the Claude recording |
| `packages/terminal/shell/zsh.sh` | rewrite (110 → 118 lines) | report typeahead; byte-wise percent-encoding |
| `packages/terminal/go/bootstrap/shell/zsh.sh` | copy of `shell/zsh.sh` | the copy the daemon embeds (`go/bootstrap/bootstrap.go:47-48`) |
| `packages/terminal/shell/zsh.test.mjs` | append | real-zsh tests |
| `packages/terminal/shell/bash.test.mjs`, `fish.test.mjs` | append | bash and fish unchanged |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` | rebuild | host mirror wasm |
| `packages/terminal/shell/README.md`, `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, survey, plain-language doc | modify | docs |

How new shells get the script: the daemon never reads `packages/terminal/shell/`. `backend/internal/service/shellterm/service.go:436-450` calls `bootstrap.Recipe`, which writes the **embedded** `go/bootstrap/shell/zsh.sh` (`go/bootstrap/bootstrap.go:47-48`, `:110-157`) to `<data dir>/shell/operator-zsh-<sha256>.sh` — a new content hash, so the next shell spawned by a rebuilt daemon gets the new script; shells already running keep the old one. `go/bootstrap/bootstrap_test.go` `TestScriptCopyIsInSyncWithShellDir` fails when the two copies differ. `ts/core/scripts/prepare-spawn-assets.mjs:13-15` copies `shell/*.sh` into `ts/core/assets/shell/` at `npm run build:ts` (gitignored, nothing to commit).

---

### Task 0: Branch, toolchains, shells, baselines

**Files:** none changed (a temporary baseline recording is restored in Step 8).

**Interfaces:** Produces the branch and the baseline numbers every later task compares against.

- [ ] **Step 1: Create the branch**

```bash
git fetch origin && git checkout -b terminal/plan-6-typing-ahead origin/development && git log -1 --oneline
```
Expected: the tip of `origin/development` (`5185f35be test: stop two timing races under load` when this plan was written; a later commit is fine). If a line number quoted in this plan no longer matches, find the quoted text with `grep -n` and use that; list every drift in the completion report.

- [ ] **Step 2: Read the docs**

Read `TERMINAL.md` end to end, `packages/terminal/CHANGELOG.md` "Unreleased", `packages/terminal/shell/README.md`, `packages/terminal/protocol/SPEC.md` §4, and the spec section named in the header. Do not start Task 1 before this.

- [ ] **Step 3: Rust toolchain and wasm-bindgen**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rustup show active-toolchain && rustc --version && rustup target list --installed
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
```
Expected: `1.96.0-…` active, `rustc 1.96.0 (…)`, `wasm32-unknown-unknown` listed (if missing: `rustup target add wasm32-unknown-unknown --toolchain 1.96.0`), and `wasm-bindgen 0.2.127` exactly.

- [ ] **Step 4: Shells and tmux**

```bash
for tool in zsh bash fish tmux; do printf '%s: ' "$tool"; command -v "$tool" || echo missing; done
```
For each missing tool install it (use `sudo` only if you are not root):
```bash
sudo apt-get update && sudo apt-get install -y zsh tmux fish
zsh --version; bash --version | head -1; fish --version; tmux -V; locale -a | grep -i '^c.utf'
```
Expected: a version line for each and `C.utf8` (or `C.UTF-8`) listed. If `apt-get` is blocked, write "zsh/fish/tmux: not installed — <exact error>" in the report; every real-shell test then reports as skipped (the test files skip when a shell or tmux is absent), and those gates are "not run" with that reason.

- [ ] **Step 5: Node, Go, Playwright**

```bash
node --version && npm --version && (go version || echo "go missing")
```
Expected: Node `v20`+; Go `go1.25.x`. If Go is missing or older, run every Go command in this plan as `GOTOOLCHAIN=auto go …` (the go command fetches `go1.25.7` through the module proxy); if that also fails, write "Go: not run — <exact error>" and every Go step becomes not-run.

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm ci && npx playwright install --with-deps chromium
```
Expected: `added … packages`; Playwright installs chromium or says it is installed. If the download fails with HTTP 403 (CDN blocked), use a preinstalled Chromium **outside the repo**:
```bash
ls /opt/pw-browsers 2>/dev/null
node -e "for (const b of require('$(git rev-parse --show-toplevel)/packages/terminal/node_modules/playwright-core/browsers.json').browsers) if (b.name.startsWith('chromium')) console.log(b.name, b.revision)"
```
The second command prints the pinned revisions (`chromium 1223`, `chromium-headless-shell 1223` for Playwright 1.60.0). For each pinned directory that is missing under `/opt/pw-browsers`, symlink it to the preinstalled one of the same kind, e.g. `ln -s /opt/pw-browsers/chromium-<have> /opt/pw-browsers/chromium-1223` and `ln -s /opt/pw-browsers/chromium_headless_shell-<have> /opt/pw-browsers/chromium_headless_shell-1223`, then `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` in every bench command. If no Chromium exists at all, write "Playwright: not run — <exact error>"; every bench step becomes not-run.

- [ ] **Step 6: Baseline Rust and TS gates**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace 2>&1 | grep -E "^test result" | awk '{p+=$4; f+=$6} END {print "passed", p, "failed", f}'
```
Expected: `passed 488 failed 0` on the author's machine (record your number; later tasks add 9).

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor completions react; do (cd ts/$p && echo "== $p" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done && npm run check:boundaries
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`; on the author's machine core `8`/`80`, renderer-dom `56`/`915`, editor `13`/`162`, completions `10`/`109`, react `11`/`123`; `boundary check passed`; `no ownership timers found (5 files scanned)`. Record your counts; a failure here is pre-existing and must be named in the report.

- [ ] **Step 7: Baseline shell tests and host wasm hash**

```bash
cd "$(git rev-parse --show-toplevel)" && LANG=C.UTF-8 LC_ALL=C.UTF-8 node --test packages/terminal/shell/zsh.test.mjs packages/terminal/shell/bash.test.mjs packages/terminal/shell/fish.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail|skipped)"
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown && sha256sum target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: `ℹ fail 0` (the author's machine: zsh `ℹ tests 11`, bash `ℹ tests 8`, fish `ℹ tests 5`, 24 in all; skips allowed only for a tool Step 4 could not install); two hashes (they usually differ — the committed binary was built elsewhere). Record the first hash.

- [ ] **Step 8: Record feel baselines for this environment on the unmodified tree, then restore the committed ones**

The committed baselines under `bench/agent-session/baselines/` only match the machine they were recorded on (on the author's Mac the unmodified tree reported `FAIL 25 screenshot(s) differ from the baseline`; with pixels recorded this way the finished plan reported `PASS feel gate: zero pixel diff`).

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:feel -- --record && rm -rf /tmp/plan6-feel-base && cp -R bench/agent-session/baselines /tmp/plan6-feel-base && git checkout -- bench/agent-session/baselines && git clean -fdq -- bench/agent-session/baselines && git status --short bench/agent-session/baselines
```
Expected: one `recorded …` line per screenshot, then `recorded feel baselines`; the final `git status --short` prints nothing. If Playwright is unavailable: "bench:feel: not run — <reason>".

- [ ] **Step 9: No commit** — nothing to commit in Task 0.

---

### Task 1: Protocol — the `typeahead` key

**Files:**
- Modify: `packages/terminal/protocol/SPEC.md` (insert before line 148, `## 5. Tier 2 — events emitted`)
- Create: `packages/terminal/protocol/vectors/typeahead.json`
- Test: `backend/internal/terminal/block_assembler_test.go` (append after the last line, 407)

**Interfaces:**
- Consumes: nothing.
- Produces: the wire form every later task uses — `ESC ] 7000 ; v=1 ; typeahead=<percent-encoded UTF-8> BEL`, emitted in its own mark directly after `ESC ] 7000 ; v=1 ; input-ready=1 BEL`. Decoders surface it as an `extension` event with pairs `[["v","1"],["typeahead", <decoded text>]]`.

This key is additive: both decoders already decode unknown keys generically (`crates/marks/src/scanner.rs:166-211`, `go/marks/scanner.go` `extensionEvents`), so the vector and the Go test pass without a decoder change. That is the point of this task: prove the new key reaches every consumer unchanged, before anything depends on it.

- [ ] **Step 1: Add the spec section**

In `packages/terminal/protocol/SPEC.md`, find the paragraph that ends the §4.4 section:

```
They remain strictly additive. A decoder that ignores them still produces
correct blocks, and no block lifecycle transition depends on either key.
```

and insert directly after it (before `## 5. Tier 2 — events emitted`), with one blank line on each side:

```markdown
### 4.5 Typeahead key

| Key | Meaning | Value |
| --- | --- | --- |
| `typeahead` | text the user typed while the previous command ran, found waiting by the shell when its next prompt started | percent-encoded UTF-8, at most 256 characters, no control character |

A shell emits `typeahead` in a mark of its own, directly after the
`input-ready` mark of the prompt that found the text, and only when the text
holds no line break or other control character. The shell keeps the text in
its own line buffer. A line editor that adopts the text clears the shell's
copy by sending `^U` (0x15). Decoders surface the key as an ordinary
`extension` event (vector `typeahead.json`); a decoder that ignores it loses
nothing, because the text is still in the shell's buffer.
```

- [ ] **Step 2: Add the vector**

Create `packages/terminal/protocol/vectors/typeahead.json`:

```json
{
  "name": "typeahead",
  "description": "A shell reports the text typed ahead of its prompt as its own Tier-2 mark after input-ready. It decodes as an extension event whose typeahead value is percent-decoded UTF-8.",
  "input": "\u001b]7000;v=1;input-ready=1\u0007\u001b]7000;v=1;typeahead=echo%20caf%c3%a9\u0007",
  "events": [
    { "kind": "input_ready" },
    { "kind": "extension", "pairs": [["v", "1"], ["typeahead", "echo café"]] }
  ]
}
```

- [ ] **Step 3: Append the block-assembler guard test**

Append to `backend/internal/terminal/block_assembler_test.go` (after the closing `}` of the last test, `TestAssemblerKeepsTheShellsOwnStartTime`):

```go

func TestAssemblerIgnoresATypeaheadMark(t *testing.T) {
	first := "\x1b]133;A\x07\x1b]7000;v=1;id=t-1;cmd=sleep%201\x1b\\\x1b]133;C\x07done\r\n\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]133;D;0\x07"
	prompt := "\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07\x1b]7000;v=1;typeahead=echo%20hi\x07"
	second := "\x1b]7000;v=1;input-released=1\x07\x1b]7000;v=1;id=t-2;cmd=ls\x1b\\\x1b]133;C\x07a\r\n\x1b]7000;v=1;id=t-2;exit=0\x1b\\\x1b]133;D;0\x07"
	a, dec := newAssembler(false)
	blocks := assembleChunks(a, dec, first, prompt, second)
	if len(blocks) != 2 {
		t.Fatalf("got %d blocks, want 2", len(blocks))
	}
	if blocks[0].Command != "sleep 1" || blocks[1].Command != "ls" {
		t.Fatalf("commands = %q, %q; a typeahead mark must not become block metadata", blocks[0].Command, blocks[1].Command)
	}
}
```

- [ ] **Step 4: Run both decoders and the assembler**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p terminal-marks --test vectors 2>&1 | grep -E "test result|panicked"
cd "$(git rev-parse --show-toplevel)/packages/terminal/go/marks" && go test ./... 2>&1 | tail -1
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/terminal/ -run 'TestAssemblerIgnoresATypeaheadMark|TestAssemblerExtensionFullBlock' -count=1 -v 2>&1 | grep -E "^(--- |ok|FAIL)"
```
Expected: `test result: ok. 6 passed; 0 failed`; `ok  	github.com/OmarAly92/operator/packages/terminal/go/marks`; `--- PASS: TestAssemblerExtensionFullBlock`, `--- PASS: TestAssemblerIgnoresATypeaheadMark`, `ok`. All pass on the first run by design (see the note above). If the vector fails in either decoder, stop: the decoders are not generic as `scanner.rs:166-211` shows, and that needs a decision.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/protocol/SPEC.md packages/terminal/protocol/vectors/typeahead.json backend/internal/terminal/block_assembler_test.go && git commit -m "$(cat <<'EOF'
feat(protocol): define the OSC 7000 typeahead key

A shell reports text typed ahead of its prompt in its own mark after
input-ready. Both decoders already surface it as an extension event;
the vector pins that, and the daemon's block assembler ignores it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: vt-core keeps the report while the shell owns the line

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/line_editor.rs` (whole file, 40 lines)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:268-273` and after `:469-471`
- Test: `packages/terminal/crates/vt-core/tests/typeahead.rs` (create)

**Interfaces:**
- Consumes: the wire form from Task 1.
- Produces: `vt_core::TerminalCore::take_typeahead(&mut self) -> Option<String>` — the decoded text of the last `typeahead` report received while the line editor state was `Owned`, once; `None` otherwise. A report is dropped by `input-released`, by entering the alternate screen, and ignored while the state is `Unknown` or `Released`, while the alternate screen is active, or when empty.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/crates/vt-core/tests/typeahead.rs`:

```rust
use vt_core::{LineEditorState, TerminalCore};

const READY: &[u8] = b"\x1b]7000;v=1;input-ready=1\x07";
const RELEASED: &[u8] = b"\x1b]7000;v=1;input-released=1\x07";
const TYPED: &[u8] = b"\x1b]7000;v=1;typeahead=echo%20caf%c3%a9\x07";

fn core() -> TerminalCore {
    TerminalCore::new(80, 100).expect("valid terminal dimensions")
}

#[test]
fn a_typeahead_after_input_ready_is_taken_once() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead().as_deref(), Some("echo café"));
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_in_the_same_mark_chunk_as_input_ready_is_kept() {
    let mut c = core();
    c.feed(&[READY, TYPED].concat());
    assert_eq!(c.take_typeahead().as_deref(), Some("echo café"));
}

#[test]
fn a_typeahead_while_a_program_owns_the_tty_is_ignored() {
    let mut c = core();
    c.feed(READY);
    c.feed(RELEASED);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_before_any_shell_mark_is_ignored() {
    let mut c = core();
    c.feed(TYPED);
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn input_released_drops_a_typeahead_nobody_took() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    c.feed(RELEASED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn the_alternate_screen_drops_and_ignores_typeahead() {
    let mut c = core();
    c.feed(READY);
    c.feed(TYPED);
    c.feed(b"\x1b[?1049h");
    assert_eq!(c.take_typeahead(), None);
    c.feed(READY);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn an_empty_typeahead_is_nothing() {
    let mut c = core();
    c.feed(READY);
    c.feed(b"\x1b]7000;v=1;typeahead=\x07");
    assert_eq!(c.take_typeahead(), None);
}

#[test]
fn a_typeahead_mark_changes_no_block_and_no_row() {
    let block = b"\x1b]133;A\x07\x1b]7000;v=1;id=t-1;cmd=sleep%201\x1b\\\x1b]133;C\x07done\r\n\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]133;D;0\x07\x1b]133;A\x07";
    let mut plain = core();
    plain.feed(block);
    plain.feed(READY);
    let mut typed = core();
    typed.feed(block);
    typed.feed(READY);
    typed.feed(TYPED);
    let a = plain.snapshot().expect("snapshot");
    let b = typed.snapshot().expect("snapshot");
    assert_eq!(a.content, b.content);
    assert_eq!(a.rows, b.rows);
    assert_eq!(a.blocks.len(), b.blocks.len());
    assert_eq!(a.block_command(0), "sleep 1");
    assert_eq!(b.block_command(0), "sleep 1");
}

#[test]
fn the_claude_code_recording_never_yields_a_typeahead() {
    let recording = std::fs::read(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../bench/agent-session/fixtures/claude-spinner-10s/recording"),
    )
    .expect("recording");
    let mut c = TerminalCore::new(120, 1000).expect("valid terminal dimensions");
    c.feed(&recording);
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
    assert_eq!(c.take_typeahead(), None);
    c.feed(TYPED);
    assert_eq!(c.take_typeahead(), None);
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-core --test typeahead 2>&1 | grep -E "^error" | head -3
```
Expected: `error[E0599]: no method named `take_typeahead` found for struct `TerminalCore`…`.

- [ ] **Step 3: Keep the report in the tracker**

Replace the whole of `packages/terminal/crates/vt-core/src/line_editor.rs` with:

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum LineEditorState {
    #[default]
    Unknown,
    Owned,
    Released,
}

impl LineEditorState {
    pub fn wire(self) -> u32 {
        match self {
            LineEditorState::Unknown => 0,
            LineEditorState::Owned => 1,
            LineEditorState::Released => 2,
        }
    }
}

#[derive(Default)]
pub struct LineEditorTracker {
    state: LineEditorState,
    typeahead: Option<String>,
}

impl LineEditorTracker {
    pub fn state(&self) -> LineEditorState {
        self.state
    }

    pub fn on_input_ready(&mut self) {
        self.state = LineEditorState::Owned;
    }

    pub fn on_input_released(&mut self) {
        self.state = LineEditorState::Released;
        self.typeahead = None;
    }

    pub fn on_alt_screen_enter(&mut self) {
        self.state = LineEditorState::Released;
        self.typeahead = None;
    }

    pub fn on_typeahead(&mut self, text: &str) {
        if self.state == LineEditorState::Owned && !text.is_empty() {
            self.typeahead = Some(text.to_string());
        }
    }

    pub fn take_typeahead(&mut self) -> Option<String> {
        self.typeahead.take()
    }
}
```

- [ ] **Step 4: Route the field and expose the take**

In `packages/terminal/crates/vt-core/src/lib.rs`, replace (lines 268-273, the second `match event {` in `feed_raw`, right after the alternate-screen `continue`):

```rust
            match event {
                MarkEvent::InputReady => self.line_editor.on_input_ready(),
                MarkEvent::InputReleased => self.line_editor.on_input_released(),
                MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
                _ => {}
            }
```

with:

```rust
            match &event {
                MarkEvent::InputReady => self.line_editor.on_input_ready(),
                MarkEvent::InputReleased => self.line_editor.on_input_released(),
                MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
                MarkEvent::Extension(fields) => {
                    if let Some((_, text)) = fields.pairs.iter().find(|(key, _)| key == "typeahead")
                    {
                        self.line_editor.on_typeahead(text);
                    }
                }
                _ => {}
            }
```

Then find (lines 469-471):

```rust
    pub fn line_editor_state(&self) -> LineEditorState {
        self.line_editor.state()
    }
```

and add directly after it, with one blank line between:

```rust
    pub fn take_typeahead(&mut self) -> Option<String> {
        self.line_editor.take_typeahead()
    }
```

- [ ] **Step 5: Run the tests and the Rust gates**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --all && cargo test -p vt-core --test typeahead 2>&1 | grep -E "test result" && cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -1 && cargo test --workspace 2>&1 | grep -E "^test result" | awk '{p+=$4; f+=$6} END {print "passed", p, "failed", f}' && wc -l crates/vt-core/src/lib.rs crates/vt-core/src/line_editor.rs && git diff --stat
```
Expected: `test result: ok. 9 passed; 0 failed`; clippy's last line `Finished …` with no warning; `passed <Task 0 count + 9> failed 0` (497 on the author's machine); `582 crates/vt-core/src/lib.rs`, `53 crates/vt-core/src/line_editor.rs`; `cargo fmt` changed nothing outside these files (if `git diff --stat` lists another file, `git checkout --` it — it is a formatting drift you did not cause).

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/crates/vt-core/src/line_editor.rs packages/terminal/crates/vt-core/src/lib.rs packages/terminal/crates/vt-core/tests/typeahead.rs && git commit -m "$(cat <<'EOF'
feat(vt-core): keep a shell's typeahead report while it owns the line

TerminalCore::take_typeahead hands over, once, the last typeahead=
report received after input-ready. input-released and the alternate
screen drop it; a pane no shell has spoken in never gets one.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `takeTypeahead` through wasm to `@operator/terminal-core`

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs` after `:343-345`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts` after `:474-476`
- Test: `packages/terminal/ts/core/src/typeahead.test.ts` (create)

**Interfaces:**
- Consumes: `vt_core::TerminalCore::take_typeahead(&mut self) -> Option<String>` (Task 2).
- Produces: wasm `WasmTerminalCore.takeTypeahead(): string` (`""` for none) and `TerminalCore.takeTypeahead(): string` in `@operator/terminal-core` — the report text once, `""` when there is none or the core is disposed. A report arriving on its own still fires `onChange` (every `feed` bumps the generation: `crates/vt-core/src/parser.rs:149-151` `note_mutation`, called at the end of every feed).

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/core/src/typeahead.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "./index";

const encode = (text: string) => new TextEncoder().encode(text);
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const RELEASED = "\x1b]7000;v=1;input-released=1\x07";
const TYPED = "\x1b]7000;v=1;typeahead=echo%20caf%c3%a9\x07";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

describe("TerminalCore.takeTypeahead", () => {
	it("hands over the text the shell reported after input-ready exactly once", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + TYPED));
		expect(core.takeTypeahead()).toBe("echo café");
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("returns nothing for a report while a program owns the tty", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + RELEASED + TYPED));
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("returns nothing for a report in a pane no shell has spoken in", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(TYPED));
		expect(core.lineEditorState()).toBe("unknown");
		expect(core.takeTypeahead()).toBe("");
		core.dispose();
	});

	it("notifies change listeners when a report arrives on its own", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY));
		let changes = 0;
		const off = core.onChange(() => {
			changes += 1;
		});
		core.feed(encode(TYPED));
		expect(changes).toBe(1);
		off();
		core.dispose();
	});

	it("returns nothing once the core is disposed", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		core.feed(encode(READY + TYPED));
		core.dispose();
		expect(core.takeTypeahead()).toBe("");
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/core" && npx vitest run src/typeahead.test.ts 2>&1 | grep -E "TypeError|Tests  " | head -3
```
Expected: `TypeError: core.takeTypeahead is not a function` and `Tests  5 failed (5)`.

- [ ] **Step 3: Export it from wasm**

In `packages/terminal/crates/vt-wasm/src/lib.rs` find (lines 343-345):

```rust
    pub fn line_editor_state(&self) -> u32 {
        self.export.line_editor_state()
    }
```

and add directly after it, with one blank line between:

```rust
    #[wasm_bindgen(js_name = takeTypeahead)]
    pub fn take_typeahead(&mut self) -> String {
        self.core.take_typeahead().unwrap_or_default()
    }
```

- [ ] **Step 4: Wrap it in `TerminalCore`**

In `packages/terminal/ts/core/src/terminal-core.ts` find (lines 474-476):

```ts
	lineEditorState(): LineEditorState {
		return LINE_EDITOR_STATES[this.snapshot().lineEditorState] ?? "unknown";
	}
```

and add directly after it, with one blank line between:

```ts
	takeTypeahead(): string {
		if (this.disposed) {
			return "";
		}
		return this.inner.takeTypeahead();
	}
```

- [ ] **Step 5: Rebuild and run**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -1 && npm run build:wasm -- --force 2>&1 | tail -1 && grep -n "takeTypeahead(): string" ts/core/wasm/vt_core.d.ts && npm run build:ts 2>&1 | tail -1 && (cd ts/core && npx vitest run 2>&1 | grep -E "Test Files|Tests  ") && wc -l crates/vt-wasm/src/lib.rs ts/core/src/terminal-core.ts
```
Expected: clippy `Finished …`; `build-wasm: … ready`; one line `…    takeTypeahead(): string;`; `tsc` prints nothing; `Test Files  9 passed (9)` and `Tests  85 passed (85)` (Task 0's core count + 1 file / + 5 tests); `566 crates/vt-wasm/src/lib.rs`, `571 ts/core/src/terminal-core.ts`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/crates/vt-wasm/src/lib.rs packages/terminal/ts/core/src/terminal-core.ts packages/terminal/ts/core/src/typeahead.test.ts && git commit -m "$(cat <<'EOF'
feat(terminal-core): takeTypeahead hands a shell's report to the host once

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: The line editor adopts what the user typed ahead

**Files:**
- Create: `packages/terminal/ts/editor/src/typeahead.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` at `:21`, `:54`, `:67-68`, `:91-92`, `:104`, `:182-185`, `:244`, `:258-260`, before `:516`
- Test: `packages/terminal/ts/editor/src/line-editor-typeahead.test.ts` (create)

**Interfaces:**
- Consumes: `TerminalCore.takeTypeahead(): string` (Task 3).
- Produces (module `ts/editor/src/typeahead.ts`, not re-exported from the package index): `TYPEAHEAD_MAX_CHARS = 256`; `CLEAR_SHELL_LINE = "\x15"`; `acceptTypeahead(text: string): string | null` (null for empty text, more than 256 code points, or any character in U+0000–U+001F, U+007F–U+009F); `class TypeaheadGate { reset(): void; noteSent(data: string): void; take(core: TerminalCore): string | null }` — `take` always drains the core, returns the accepted text only if `noteSent` saw non-empty data since the last `take` that found a report (or `reset`), and closes the gate whenever a report was found. `LineEditor` behaviour: on mount and on every core change (visible or hidden) it takes a report; an adopted report is appended to the buffer (cursor at the end), never submitted, and followed by `host.sendRaw("\x15")`.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/editor/src/line-editor-typeahead.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import { acceptTypeahead, CLEAR_SHELL_LINE, TYPEAHEAD_MAX_CHARS } from "./typeahead";

const here = dirname(fileURLToPath(import.meta.url));
const encode = (text: string) => new TextEncoder().encode(text);
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;
const READY = "\x1b]7000;v=1;input-ready=1\x07";
const RELEASED = "\x1b]7000;v=1;input-released=1\x07";
const report = (text: string) => `\x1b]7000;v=1;typeahead=${encodeURIComponent(text)}\x07`;

beforeAll(async () => {
	const bytes = await readFile(join(here, "..", "..", "core", "wasm", "vt_core_bg.wasm"));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

function mount() {
	const sent: string[] = [];
	const raw: string[] = [];
	const drafts: string[] = [];
	const host: EditorHost = {
		send: (text) => sent.push(text),
		sendRaw: (data) => raw.push(data),
		onDraftChange: (draft) => drafts.push(draft),
	};
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	const root = container.querySelector<HTMLElement>(".terminal-editor")!;
	const lines = () => [...container.querySelectorAll(".terminal-editor-line")].map((line) => line.textContent?.replace(/ /g, "") ?? "");
	return { editor, core, root, sent, raw, drafts, lines };
}

function typeWhileRunning(editor: LineEditor, text: string) {
	for (const character of text) editor.handleKey(key({ key: character }));
}

function paste(root: HTMLElement, text: string) {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: { types: ["text/plain"], getData: () => text, files: [] },
	});
	root.dispatchEvent(event);
}

describe("typing ahead into the line editor", () => {
	it("puts the text the shell reports into the input box without running it", () => {
		const { editor, core, sent, raw, drafts, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "echo hi");
		expect(raw.join("")).toBe("echo hi");
		core.feed(encode(READY + report("echo hi")));
		expect(lines()).toEqual(["echo hi"]);
		expect(drafts.at(-1)).toBe("echo hi");
		expect(sent).toEqual([]);
		expect(raw.join("")).toBe("echo hi\x15");
	});

	it("submits the adopted text once, so the shell never sees it twice", () => {
		const { editor, core, sent, raw } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "ls");
		core.feed(encode(READY + report("ls")));
		editor.handleKey(key({ key: " " }));
		editor.handleKey(key({ key: "-" }));
		editor.handleKey(key({ key: "a" }));
		editor.handleKey(key({ key: "Enter" }));
		expect(sent).toEqual(["ls -a"]);
		expect(raw).toEqual(["l", "s", CLEAR_SHELL_LINE]);
	});

	it("appends the report to a draft the host put back while the command ran", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		editor.setText("git ");
		typeWhileRunning(editor, "status");
		core.feed(encode(READY + report("status")));
		expect(lines()).toEqual(["git status"]);
	});

	it("counts a paste sent to the running command as typing ahead", async () => {
		const { core, root, lines } = mount();
		core.feed(encode(READY + RELEASED));
		paste(root, "make test");
		await settle();
		core.feed(encode(READY + report("make test")));
		expect(lines()).toEqual(["make test"]);
	});

	it("leaves a report it did not type to the shell: nothing shown, the shell's line not cleared", () => {
		const { core, lines, drafts, raw } = mount();
		core.feed(encode(READY + RELEASED));
		core.feed(encode(READY + report("rm -rf ~")));
		expect(lines()).toEqual([""]);
		expect(drafts).toEqual([]);
		expect(raw).toEqual([]);
	});

	it("adopts one report per burst of typing", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "a");
		core.feed(encode(READY + report("a")));
		editor.handleKey(key({ key: "Enter" }));
		core.feed(encode(RELEASED + READY + report("b")));
		expect(lines()).toEqual([""]);
	});

	it("drops a report carrying a control character or longer than the cap, and leaves the shell's line alone", () => {
		const { editor, core, lines, raw } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "x");
		core.feed(encode(READY + report("ls\nrm -rf ~")));
		expect(lines()).toEqual([""]);
		core.feed(encode(RELEASED));
		typeWhileRunning(editor, "x");
		core.feed(encode(READY + report("y".repeat(TYPEAHEAD_MAX_CHARS + 1))));
		expect(lines()).toEqual([""]);
		expect(raw).toEqual(["x", "x"]);
	});

	it("takes a report while the pane is hidden and shows it when the pane is shown", () => {
		const { editor, core, lines } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "pwd");
		editor.setVisible(false);
		core.feed(encode(READY + report("pwd")));
		expect(core.takeTypeahead()).toBe("");
		editor.setVisible(true);
		expect(lines()).toEqual(["pwd"]);
	});

	it("stops taking reports once disposed", () => {
		const { editor, core } = mount();
		core.feed(encode(READY + RELEASED));
		typeWhileRunning(editor, "ls");
		editor.dispose();
		core.feed(encode(READY + report("ls")));
		expect(core.takeTypeahead()).toBe("ls");
	});

	it("leaves a Claude Code pane exactly as before: every key goes to Claude, nothing reaches the box", async () => {
		const recording = await readFile(join(here, "..", "..", "..", "bench", "agent-session", "fixtures", "claude-spinner-10s", "recording"));
		const { editor, core, root, raw, sent, lines, drafts } = mount();
		core.feed(new Uint8Array(recording));
		expect(root.dataset.ownership).toBe("unknown");
		typeWhileRunning(editor, "yes");
		editor.handleKey(key({ key: "Enter" }));
		expect(raw).toEqual(["y", "e", "s", "\r"]);
		core.feed(encode(report("yes")));
		expect(lines()).toEqual([]);
		expect(drafts).toEqual([]);
		expect(sent).toEqual([]);
	});
});

describe("acceptTypeahead", () => {
	it("keeps printable text up to the cap, counted in characters", () => {
		expect(acceptTypeahead("echo café €")).toBe("echo café €");
		expect(acceptTypeahead("é".repeat(TYPEAHEAD_MAX_CHARS))).toBe("é".repeat(TYPEAHEAD_MAX_CHARS));
		expect(acceptTypeahead("é".repeat(TYPEAHEAD_MAX_CHARS + 1))).toBeNull();
	});

	it("refuses empty text and any C0, DEL or C1 control", () => {
		expect(acceptTypeahead("")).toBeNull();
		for (const control of ["\t", "\n", "\r", "\x1b[A", "\x7f", "\x9b"]) {
			expect(acceptTypeahead(`ls${control}`)).toBeNull();
		}
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run src/line-editor-typeahead.test.ts 2>&1 | grep -E "Failed to (resolve|load)|Test Files" | head -3
```
Expected: the file fails to load because `./typeahead` does not exist (`Failed to resolve import "./typeahead"` or `Failed to load url ./typeahead`) and `Test Files  1 failed (1)`.

- [ ] **Step 3: Create the gate**

Create `packages/terminal/ts/editor/src/typeahead.ts`:

```ts
import type { TerminalCore } from "@operator/terminal-core";

export const TYPEAHEAD_MAX_CHARS = 256;

export const CLEAR_SHELL_LINE = "\x15";

const CONTROL = /[\u0000-\u001f\u007f-\u009f]/u;

export function acceptTypeahead(text: string): string | null {
	if (text === "") return null;
	if ([...text].length > TYPEAHEAD_MAX_CHARS) return null;
	if (CONTROL.test(text)) return null;
	return text;
}

export class TypeaheadGate {
	private typed = false;

	reset(): void {
		this.typed = false;
	}

	noteSent(data: string): void {
		if (data !== "") this.typed = true;
	}

	take(core: TerminalCore): string | null {
		const reported = core.takeTypeahead();
		if (reported === "") return null;
		const accepted = this.typed ? acceptTypeahead(reported) : null;
		this.typed = false;
		return accepted;
	}
}
```

- [ ] **Step 4: Wire it into `LineEditor`** (`packages/terminal/ts/editor/src/line-editor.ts`, nine edits; each quoted `find` text occurs exactly once)

4a. Line 21 — find `import { editorStyles } from "./styles.js";` and add directly after it:
```ts
import { CLEAR_SHELL_LINE, TypeaheadGate } from "./typeahead.js";
```

4b. Line 54 — find `	private pasteConfirm: PasteConfirm | null = null;` and add directly after it:
```ts
	private readonly typeahead = new TypeaheadGate();
```

4c. Lines 67-68 (in `mount`) — find
```ts
		this.reportedDraft = "";
		this.search.cancel();
```
and replace with
```ts
		this.reportedDraft = "";
		this.typeahead.reset();
		this.search.cancel();
```

4d. Lines 91-92 — find
```ts
		this.unsubscribe = core.onChange(() => {
			this.ingestHistory();
```
and replace with
```ts
		this.unsubscribe = core.onChange(() => {
			this.ingestHistory();
			this.adoptTypeahead();
```

4e. Lines 104-106 — find
```ts
		this.ingestHistory();
		this.render();
	}

	setTheme(
```
and replace with
```ts
		this.ingestHistory();
		this.adoptTypeahead();
		this.render();
	}

	setTheme(
```

4f. Lines 182-185 (in `commitComposedText`) — find
```ts
		if (this.core?.lineEditorState() !== "owned") {
			this.host?.sendRaw(text);
			return;
		}
```
and replace with
```ts
		if (this.core?.lineEditorState() !== "owned") {
			this.host?.sendRaw(text);
			this.typeahead.noteSent(text);
			return;
		}
```

4g. Line 244 (in `onPaste`) — find
```ts
				if (this.root === root) host.sendRaw(data);
```
and replace with
```ts
				if (this.root !== root) return;
				host.sendRaw(data);
				this.typeahead.noteSent(data);
```

4h. Lines 259-260 (in `passthrough`) — find
```ts
		this.host?.sendRaw(data);
		return data;
```
and replace with
```ts
		this.host?.sendRaw(data);
		this.typeahead.noteSent(data);
		return data;
```

4i. Line 516 — find `	private ingestHistory(): void {` and insert directly before it:
```ts
	private adoptTypeahead(): void {
		const core = this.core;
		if (!core) return;
		const typed = this.typeahead.take(core);
		if (typed === null) return;
		this.buffer.setText(this.buffer.text + typed);
		this.historyPrefix = null;
		this.host?.sendRaw(CLEAR_SHELL_LINE);
	}

```

- [ ] **Step 5: Run the tests and the package gates**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts 2>&1 | tail -1 && (cd ts/editor && npx vitest run src/line-editor-typeahead.test.ts 2>&1 | grep -E "Tests  ") && for p in core renderer-dom editor completions react; do (cd ts/$p && echo "== $p" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done && npm run check:boundaries 2>&1 | tail -2 && wc -l ts/editor/src/line-editor.ts ts/editor/src/typeahead.ts
```
Expected: `tsc` prints nothing; `Tests  12 passed (12)`; editor `14`/`174` (Task 0 + 1 file / + 12 tests), core `9`/`85`, the other three equal to Task 0; `boundary check passed` and `no ownership timers found (5 files scanned)`; `595 ts/editor/src/line-editor.ts`, `33 ts/editor/src/typeahead.ts`.

On the author's machine, running this test file against the unmodified `line-editor.ts` (with `typeahead.ts` present) failed exactly the five adoption tests ("puts the text…", "submits…", "appends…", "counts a paste…", "takes a report while the pane is hidden…") and passed the guards — that is the expected red/green split if a reviewer re-checks.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/ts/editor/src/typeahead.ts packages/terminal/ts/editor/src/line-editor.ts packages/terminal/ts/editor/src/line-editor-typeahead.test.ts && git commit -m "$(cat <<'EOF'
feat(editor): put text typed during a command into the input box

When the shell reports typeahead and the user sent keys, IME text or a
paste to the running command, the line editor appends the report to its
buffer, never submits it, and sends ^U so the shell's copy is cleared.
A report the user did not type is left to the shell.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: zsh reports its typeahead

**Files:**
- Modify: `packages/terminal/shell/zsh.sh` (whole file)
- Modify: `packages/terminal/go/bootstrap/shell/zsh.sh` (byte copy of the above)
- Test: `packages/terminal/shell/zsh.test.mjs` (append), `packages/terminal/shell/bash.test.mjs` (append), `packages/terminal/shell/fish.test.mjs` (append)

**Interfaces:**
- Consumes: the wire form from Task 1; the `^U` the editor sends (Task 4).
- Produces: at the first primary prompt after a command ran, zsh prints `ESC]7000;v=1;typeahead=<pct> BEL` right after `ESC]7000;v=1;input-ready=1 BEL` when text of 1–256 characters without control characters was waiting on the tty; the text always stays in zle's buffer (`zle -U`). `__operator_terminal_pct_encode` encodes UTF-8 bytes.

- [ ] **Step 1: Write the failing zsh tests**

Append to `packages/terminal/shell/zsh.test.mjs` (after the last test, which ends the file at line 202):

```js

const TYPEAHEAD_PREFIX = "7000;v=1;typeahead=";

function typeaheadReports(records) {
	return records
		.filter((record) => record.payload.startsWith(TYPEAHEAD_PREFIX))
		.map((record) => record.payload.slice(TYPEAHEAD_PREFIX.length));
}

function commandsRun(records) {
	return records.map((record) => field(record.payload, "cmd")).filter((command) => command !== undefined);
}

function typeaheadSession(steps) {
	const raw = runInPty("zsh -f -i", [`source ${bootstrap}`, ...steps], {
		settleMs: 300,
		env: { OPERATOR_TERMINAL_ID: "terminal-1", LANG: "C.UTF-8", LC_ALL: "C.UTF-8" },
	});
	return { raw, records: parseOscRecords(raw) };
}

test("reports text typed during a command once the prompt returns, and a Ctrl-U clears the shell's copy", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo hi", enter: false, waitMs: 1800 },
		{ keys: "C-u", enter: false, waitMs: 200 },
		{ keys: "echo second", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20hi"]);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20second"]);
	const report = records.findIndex((record) => record.payload.startsWith(TYPEAHEAD_PREFIX));
	const finished = records.findIndex((record) => record.payload === "133;D;0");
	assert.ok(finished >= 0 && finished < report, "the report comes after the command finished");
	assert.equal(records[report - 1].payload, "7000;v=1;input-ready=1", "the report directly follows input-ready");
});

test("keeps the reported text in the shell when nothing clears it, so a separate Enter still runs it", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo sent", enter: false, waitMs: 1800 },
		{ keys: "", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20sent"]);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20sent"]);
});

test("reports typed-ahead UTF-8 as percent-encoded bytes", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo café €", enter: false, waitMs: 1800 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20caf%c3%a9%20%e2%82%ac"]);
});

test("runs a line typed ahead with Enter exactly as before and reports nothing", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo queued", waitMs: 1800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20queued"]);
});

test("runs every command of a multi-line submission and reports nothing", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([{ keys: "sleep 1\necho two\necho three", waitMs: 2000 }]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", "echo%20two", "echo%20three"]);
});

test("does not report text longer than the cap and leaves it to the shell", { skip: ptySkip }, () => {
	const long = `echo ${"x".repeat(300)}`;
	const { records } = typeaheadSession([
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: long, enter: false, waitMs: 1800 },
		{ keys: "", waitMs: 600 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.deepEqual(commandsRun(records), ["sleep%201", `echo%20${"x".repeat(300)}`]);
});

test("never surfaces a password a program read with echo off", { skip: ptySkip }, () => {
	const { raw, records } = typeaheadSession([
		{ keys: "read -s -k 7 pw; echo got-${#pw}", waitMs: 300 },
		{ keys: "hunter2", enter: false, waitMs: 800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.equal(raw.includes("hunter2"), false, "the password must appear nowhere in the pane");
	assert.match(raw, /got-7/);
});

test("a program's own prompt still receives the keys typed at it", { skip: ptySkip }, () => {
	const { raw, records } = typeaheadSession([
		{ keys: "read 'name?name: '; echo got-$name", waitMs: 300 },
		{ keys: "bob", waitMs: 800 },
	]);
	assert.deepEqual(typeaheadReports(records), []);
	assert.match(raw, /got-bob/);
});

test("clears the reported text with Ctrl-U in vi insert mode too", { skip: ptySkip }, () => {
	const { records } = typeaheadSession([
		"bindkey -v",
		{ keys: "sleep 1", waitMs: 200 },
		{ keys: "echo hi", enter: false, waitMs: 1800 },
		{ keys: "C-u", enter: false, waitMs: 200 },
		{ keys: "echo second", waitMs: 500 },
	]);
	assert.deepEqual(typeaheadReports(records), ["echo%20hi"]);
	assert.deepEqual(commandsRun(records), ["bindkey%20-v", "sleep%201", "echo%20second"]);
});

test("percent-encodes non-ASCII bytes as UTF-8", { skip }, () => {
	const out = execFileSync("zsh", ["-f", "-c", `source ${bootstrap}; __operator_terminal_pct_encode 'café € ?[x]'`], {
		encoding: "utf8",
		env: { ...process.env, LANG: "C.UTF-8", LC_ALL: "C.UTF-8" },
	});
	assert.equal(out, "caf%c3%a9%20%e2%82%ac%20%3f%5bx%5d");
});
```

(`field`, `runInPty`, `parseOscRecords`, `execFileSync`, `bootstrap`, `skip` and `ptySkip` are already defined or imported at the top of the file.)

- [ ] **Step 2: Append the bash and fish "unchanged" tests**

Append to `packages/terminal/shell/bash.test.mjs` (after its last test; `fieldOf`, `runInPty`, `parseOscRecords`, `bootstrap`, `ptySkip` are already in scope):

```js

test("reports no typeahead: text typed during a command stays with readline, as before", { skip: ptySkip }, () => {
	const raw = runInPty(
		"bash --noprofile --norc -i",
		[
			`source ${JSON.stringify(bootstrap)}`,
			{ keys: "sleep 1", waitMs: 200 },
			{ keys: "echo later", enter: false, waitMs: 1800 },
			{ keys: "", waitMs: 500 },
		],
		{ settleMs: 300 },
	);
	const records = parseOscRecords(raw);
	assert.equal(records.some((record) => record.payload.includes("typeahead=")), false);
	const commands = records.map((record) => fieldOf(record.payload, "cmd")).filter((command) => command !== undefined);
	assert.deepEqual(commands, ["sleep%201", "echo%20later"]);
});
```

Append to `packages/terminal/shell/fish.test.mjs` (after its last test; `field`, `runInPty`, `parseOscRecords`, `bootstrap`, `fishSkip` are already in scope):

```js

test("reports no typeahead: text typed during a command stays with fish's reader, as before", { skip: fishSkip }, () => {
	const raw = runInPty(
		"fish --no-config --interactive",
		[
			`source ${JSON.stringify(bootstrap)}`,
			{ keys: "sleep 1", waitMs: 200 },
			{ keys: "echo later", enter: false, waitMs: 1800 },
			{ keys: "", waitMs: 500 },
		],
		{ settleMs: 300 },
	);
	const records = parseOscRecords(raw);
	assert.equal(records.some((record) => record.payload.includes("typeahead=")), false);
	const commands = records.map((record) => field(record.payload, "cmd")).filter((command) => command !== undefined);
	assert.deepEqual(commands, ["sleep%201", "echo%20later"]);
});
```

- [ ] **Step 3: Run the new tests to see the zsh ones fail**

```bash
cd "$(git rev-parse --show-toplevel)" && LANG=C.UTF-8 LC_ALL=C.UTF-8 node --test packages/terminal/shell/zsh.test.mjs packages/terminal/shell/bash.test.mjs packages/terminal/shell/fish.test.mjs 2>&1 | grep -E "^✖|^ℹ (pass|fail|skipped)" | sort -u
```
Expected (author's machine): exactly five zsh failures — "reports text typed during a command…", "keeps the reported text in the shell…", "reports typed-ahead UTF-8…", "clears the reported text with Ctrl-U in vi insert mode too", "percent-encodes non-ASCII bytes as UTF-8" — plus the `✖ failing tests:` header; everything else passes, including the two new bash/fish tests (they pin today's behaviour).

- [ ] **Step 4: Replace `shell/zsh.sh`**

Replace the whole of `packages/terminal/shell/zsh.sh` with (tabs for indentation, as in the original):

```zsh
__operator_terminal_guard() {
	emulate -L zsh
	[[ -n ${__OPERATOR_TERMINAL_LOADED:-} ]] && return 0
	__OPERATOR_TERMINAL_LOADED=1

	typeset -gr __operator_terminal_SAFE='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~/:@!$&()*+,-'

	typeset -gi __operator_terminal_COUNTER=0

	autoload -Uz add-zsh-hook 2>/dev/null

	typeset -gri __operator_terminal_TYPEAHEAD_MAX=256

	__operator_terminal_input_ready() {
		emulate -L zsh
		print -nr -- $'\e]133;B\a'
		print -nr -- $'\e]7000;v=1;input-ready=1\a'
		__operator_terminal_report_typeahead
	}

	__operator_terminal_report_typeahead() {
		emulate -L zsh
		[[ ${__operator_terminal_TYPEAHEAD_ARMED:-0} == 1 ]] || return 0
		unset __operator_terminal_TYPEAHEAD_ARMED
		[[ $CONTEXT == start ]] || return 0
		local typed='' key
		while (( ${#typed} <= __operator_terminal_TYPEAHEAD_MAX )) && read -t 0 -k 1 key; do
			typed+=$key
		done
		[[ -n $typed ]] || return 0
		zle -U -- "$typed"
		(( ${#typed} <= __operator_terminal_TYPEAHEAD_MAX )) || return 0
		[[ $typed != *[[:cntrl:]]* ]] || return 0
		print -nr -- $'\e]7000;v=1;typeahead='"$(__operator_terminal_pct_encode "$typed")"$'\a'
	}

	__operator_terminal_input_released() {
		emulate -L zsh
		print -nr -- $'\e]7000;v=1;input-released=1\a'
	}

	if autoload -Uz add-zle-hook-widget 2>/dev/null; then
		zle -N __operator_terminal_input_ready
		add-zle-hook-widget line-init __operator_terminal_input_ready
	fi

	add-zsh-hook preexec __operator_terminal_input_released

	__operator_terminal_pct_encode() {
		emulate -L zsh
		setopt no_multibyte
		local s=$1 out='' ch encoded
		local -i i
		for ((i = 1; i <= ${#s}; i++)); do
			ch=${s[i]}
			if [[ $__operator_terminal_SAFE == *"$ch"* ]]; then
				out+=$ch
			else
				printf -v encoded '%%%02x' "'$ch"
				out+=$encoded
			fi
		done
		print -nr -- $out
	}

	__operator_terminal_next_id() {
		emulate -L zsh
		local handle=${OPERATOR_TERMINAL_ID:-terminal}
		handle=${handle//[^A-Za-z0-9_-]/_}
		[[ -n $handle ]] || handle=terminal
		__operator_terminal_COUNTER=$(( __operator_terminal_COUNTER + 1 ))
		__operator_terminal_CURRENT_ID="${handle}-${__operator_terminal_COUNTER}"
	}

	__operator_terminal_branch() {
		emulate -L zsh
		command -v git >/dev/null 2>&1 || return 0
		git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
		local b
		b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
		print -nr -- $b
	}

	__operator_terminal_preexec() {
		emulate -L zsh
		local cmd=$(__operator_terminal_pct_encode "$1")
		print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';cmd='${cmd}$'\e\\'
		print -nr -- $'\e]7000;v=1;input-released=1\a'
		print -nr -- $'\e]133;C\a'
		__operator_terminal_COMMAND_RUNNING=1
	}

	__operator_terminal_precmd() {
		local __operator_terminal_status=$?
		emulate -L zsh
		if [[ ${OPERATOR_TERMINAL_SUPPRESS_PROMPT:-0} == 1 ]]; then
			PROMPT=''
			RPROMPT=''
		fi
		if [[ ${__operator_terminal_COMMAND_RUNNING:-0} == 1 ]]; then
			print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';exit='${__operator_terminal_status}$'\e\\'
			print -nr -- $'\e]133;D;'${__operator_terminal_status}$'\a'
			unset __operator_terminal_COMMAND_RUNNING
			__operator_terminal_TYPEAHEAD_ARMED=1
		fi
		__operator_terminal_next_id
		local cwd branch
		cwd=$(__operator_terminal_pct_encode "$PWD")
		branch=$(__operator_terminal_pct_encode "$(__operator_terminal_branch)")
		print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';cwd='${cwd}$';branch='${branch}$'\e\\'
		print -nr -- $'\e]133;A\a'
	}

	add-zsh-hook precmd __operator_terminal_precmd
	add-zsh-hook preexec __operator_terminal_preexec
}

__operator_terminal_guard
```

What changed against `origin/development`: the `TYPEAHEAD_MAX` constant (new line 12), `input_ready` calls `__operator_terminal_report_typeahead` (new function, lines 21-36), `pct_encode` rewritten byte-wise (was lines 30-57), and `precmd` arms the report after a finished command (new line 104).

- [ ] **Step 5: Copy it to the embedded bootstrap**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cp shell/zsh.sh go/bootstrap/shell/zsh.sh && cmp shell/zsh.sh go/bootstrap/shell/zsh.sh && echo same && wc -l shell/zsh.sh
```
Expected: `same`, `118 shell/zsh.sh`.

- [ ] **Step 6: Run the shell tests**

```bash
cd "$(git rev-parse --show-toplevel)" && LANG=C.UTF-8 LC_ALL=C.UTF-8 node --test packages/terminal/shell/zsh.test.mjs packages/terminal/shell/bash.test.mjs packages/terminal/shell/fish.test.mjs 2>&1 | grep -E "^✖|^ℹ (tests|pass|fail|skipped)"
```
Expected: no `✖`, `ℹ fail 0` (author's machine: `ℹ tests 36`, `ℹ pass 36` — zsh 21, bash 9, fish 6, i.e. Task 0's counts + 10 / + 1 / + 1). If a zsh typeahead test fails **only** in this environment, do not change the design: rerun that file once (the tests use fixed 200–1800 ms waits); if it fails again, capture `runInPty`'s raw output for that test (add a temporary `console.log(JSON.stringify(raw))`, do not commit it), stop, and report it.

- [ ] **Step 7: Run the package's other shell consumers**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/go/bootstrap" && go test ./... 2>&1 | tail -1
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts 2>&1 | tail -1 && (cd ts/core && npx vitest run src/spawn-recipe.test.ts 2>&1 | grep -E "Tests  ") && node --test ./scripts/spawn-recipe-package.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
```
Expected: `ok  	github.com/OmarAly92/operator/packages/terminal/go/bootstrap` (`TestScriptCopyIsInSyncWithShellDir` passes because of Step 5); `Tests  8 passed (8)`; `ℹ pass 1`, `ℹ fail 0`.

- [ ] **Step 8: Run the daemon's shell-terminal tests**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/service/shellterm/... ./internal/terminal/... -count=1 2>&1 | tail -2
```
Expected: two `ok` lines.

- [ ] **Step 9: Run the real-pty integration tests (the regression that shaped the design)**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/integration/ -run 'TestShellBlocks' -count=1 2>&1 | tail -2
```
Expected: `ok  	github.com/OmarAly92/operator/backend/internal/integration` (≈13 s on the author's machine). These spawn real zsh through the daemon's recipe and send commands with `SendMessage` (text, pause, Enter). If `TestShellBlocksAlternateScreenAtCaptureStartExcludesRepaint` fails with `timed out waiting for pane output "ALT-REPAINT-SENTINEL"`, the script is clearing text it reported — check that `zle -U` runs before both `return 0` lines in `__operator_terminal_report_typeahead`. If zsh is absent the tests skip (`zsh unavailable`): report "integration: skipped — zsh unavailable".

- [ ] **Step 10: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/shell/zsh.sh packages/terminal/go/bootstrap/shell/zsh.sh packages/terminal/shell/zsh.test.mjs packages/terminal/shell/bash.test.mjs packages/terminal/shell/fish.test.mjs && git commit -m "$(cat <<'EOF'
feat(shell): zsh reports text typed ahead of its prompt

At the first prompt after a command, line-init reads the input waiting
on the tty, gives it straight back to zle, and reports it as OSC 7000
typeahead= when it is at most 256 characters with no control character.
The shell keeps the text, so a sender that writes Enter separately is
unaffected; the line editor clears it with ^U when it adopts it.
pct_encode now encodes UTF-8 bytes. bash and fish are unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Rebuild the host mirror wasm and the daemon

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt binary)

**Interfaces:**
- Consumes: the vt-core change of Task 2 (the mirror stores a report it never hands out; it is dropped on the next `input-released`).
- Produces: a committed `vt_host.wasm` built from this branch.

- [ ] **Step 1: Build and copy**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1 && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && sha256sum ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && ls -l ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: a hash different from Task 0 Step 7's first hash (the author's build grew 319,536 → 319,952 bytes). If it is identical, write "vt_host.wasm unchanged by this plan (hash <h>)" in the report, run `git checkout -- backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, and skip Step 3's commit.

- [ ] **Step 2: pty-host Go tests and the daemon build**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
cd "$(git rev-parse --show-toplevel)/frontend" && npm ci && cd "$(git rev-parse --show-toplevel)" && npm --prefix frontend run build:daemon 2>&1 | tail -2 && ls -l frontend/daemon/opr
```
Expected: `ok` for `ptyhost`, `ptyhost/ptyregistry`, `ptyhost/vtwasm` (if only `TestProcessEnvironmentLetsOverridesWin` fails, it is the pre-existing failure named in `TERMINAL.md` §5 — record it); the daemon binary exists (`frontend/daemon/opr` is gitignored, `.gitignore:70`; nothing to commit). If `npm ci` in `frontend` fails, record "frontend: not run — <error>" and skip the daemon build.

- [ ] **Step 3: Commit the binary**

```bash
cd "$(git rev-parse --show-toplevel)" && git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "$(cat <<'EOF'
build(terminal): rebuild vt_host.wasm for the typeahead report

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Gates

**Files:** none changed (benches write only under `bench/results/`, which is gitignored, and `bench:affordances` rewrites committed PNGs that Step 5 restores).

**Interfaces:** Produces the numbers for the completion report.

- [ ] **Step 1: Full Rust and TS suites**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -1 && cargo test --workspace 2>&1 | grep -E "^test result" | awk '{p+=$4; f+=$6} END {print "passed", p, "failed", f}' && npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1 && for p in core renderer-dom editor completions react; do (cd ts/$p && echo "== $p" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done && npm run check:boundaries 2>&1 | tail -2
```
Expected: `passed <Task 0 + 9> failed 0`; core 9/85, editor 14/174, the rest equal to Task 0; `boundary check passed`, `no ownership timers found (5 files scanned)`.

- [ ] **Step 2: bench:feel against the Task 0 recording**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rm -rf bench/agent-session/baselines && cp -R /tmp/plan6-feel-base bench/agent-session/baselines && npm run bench:feel 2>&1 | tail -1; rc=$?; git checkout -- bench/agent-session/baselines && git clean -fdq -- bench/agent-session/baselines; git status --short bench/agent-session/baselines; echo "bench:feel exit $rc"
```
Expected: `PASS feel gate: zero pixel diff` (what the author got), `bench:feel exit 0`, and `git status --short` prints nothing. Any `DIFF` is a real pixel change — stop and investigate (this plan draws nothing new: the input box shows adopted text through the existing editor rendering, and no feel fixture contains a typeahead mark). If Task 0 Step 8 was not run: "bench:feel: not run — <reason>".

- [ ] **Step 3: bench:selection, bench:agent:gate, bench:agent:scroll**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:selection 2>&1 | tail -1 && npm run bench:agent:gate 2>&1 | tail -4 && npm run bench:agent:scroll 2>&1 | tail -3
```
Expected (author's machine): `PASS selection survived 23 repaints`; `spinner: 10.19 row nodes and 75.98 DOM nodes per paint` … `PASS agent-session gate`; three JSON lines, the first with `"total":60134,"covered":60134`, the trim line with equal `before`/`after` rows, the width line with equal `before`/`after`. The Claude Code fixtures carry no OSC 7000 mark, so these must match Task 0's numbers within noise.

- [ ] **Step 4: Claude fixtures carry no typeahead mark**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && for f in bench/agent-session/fixtures/*/recording; do printf '%s: ' "$f"; grep -c $'\x1b]7000' "$f" || true; done
```
Expected: `0` for every recording (the same fact `TERMINAL.md` §5 records for `claude-spinner-10s` and `claude-long-50k`), so the Claude panes the benches replay never reach `Owned` and never produce a report.

- [ ] **Step 5: bench:affordances (never diffed), then restore**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && for action in hover hint redact; do npm run bench:affordances -- --action $action 2>&1 | tail -1; done; git checkout -- bench/agent-session/baselines && git clean -fdq -- bench/agent-session/baselines && git status --short bench/agent-session/baselines
```
Expected: one JSON report line per action; the final `git status --short` prints nothing.

- [ ] **Step 6: Frontend sanity (nothing in `frontend/` changed)**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx tsc --noEmit -p . && npx vitest run src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Test Files|Tests  "
```
Expected: `tsc` prints nothing; `Test Files  1 passed (1)`, `Tests  41 passed (41)` on the author's machine. If `npm ci` failed in Task 6: "frontend: not run — <reason>".

- [ ] **Step 7: No commit.**

---

### Task 8: Docs

**Files:**
- Modify: `packages/terminal/CHANGELOG.md` (top of "Unreleased", line 5)
- Modify: `TERMINAL.md` (new §4.32 before `## 5. Known gaps (not bugs, decisions pending)`; one bullet in §5)
- Modify: `packages/terminal/shell/README.md`
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md` (table row line 133, status line 4115, "Ours today" lines 4128-4135, count sentence line 52)
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md` (lines 149-150)

**Interfaces:** none.

- [ ] **Step 1: CHANGELOG**

In `packages/terminal/CHANGELOG.md`, insert as the first bullet under `## Unreleased` (before the `- core/editor/react: paste safety …` bullet):

```markdown
- shell/vt-core/vt-wasm/core/editor: typing ahead in zsh (roadmap Plan 6, survey §7.2). Keys typed while a command runs still go to the running program (`LineEditor.passthrough` is unchanged). At the first primary prompt after a command, `zsh.sh`'s `line-init` hook reads the input waiting on the tty (`read -t 0 -k 1`), gives it straight back to zle (`zle -U`) and, when it is 1–256 characters with no control character, reports it after `input-ready` as `OSC 7000;v=1;typeahead=<percent-encoded UTF-8>` (`protocol/SPEC.md` §4.5, vector `typeahead.json`). vt-core keeps the report only while the line is owned (`LineEditorTracker::on_typeahead`; dropped on `input-released` and the alternate screen); `TerminalCore.takeTypeahead()` hands it over once. `LineEditor` adopts it only if the user sent keys, IME text or a paste to the running command since the last report (`TypeaheadGate`, `ts/editor/src/typeahead.ts`), appends it to the input box without submitting it, and sends `^U` so zsh's copy is cleared — a report nobody adopts (the daemon's `SendMessage`, the phone, a program faking the mark) leaves the text with the shell, which behaves as before. bash and fish are unchanged (`TERMINAL.md` §4.32 has the evidence). Fixed on the way: `zsh.sh`'s percent-encoder encoded code points (`é` → `%e9`, `€` → `%c`); it now encodes UTF-8 bytes, which also corrects non-ASCII `cmd=`/`cwd=`. Clean-room from the survey's description of Warp's shell-reported typeahead; no Warp code read. Both wasm artifacts and the daemon must be rebuilt; shells started before the daemon is rebuilt keep the old script.
```

- [ ] **Step 2: TERMINAL.md §4.32**

In `TERMINAL.md`, insert directly before the line `## 5. Known gaps (not bugs, decisions pending)` (after the last `### 4.x` entry and its blank line):

```markdown
### 4.32 Text typed during a command reached the shell, not the input box — roadmap Plan 6
- Symptom: in a zsh pane, keys typed while a command ran went to the pty
  (deliberate since `4b31952aa`, so a `y/n` prompt, a password or Claude Code
  gets them: `ts/editor/src/line-editor.ts` `passthrough`). When the prompt
  returned, zsh held the text in its own line buffer, invisible in the input
  box, and the next thing submitted from the box was appended to it: `echo hi`
  typed during `sleep`, then `ls` in the box, ran `echo hils`.
- Cause: a shell reads typeahead only after its prompt starts, and nothing
  told the line editor what it read. At `line-init`, zsh's `$BUFFER` is still
  empty; the text is waiting on the tty.
- Now: behaviour taken from the survey's description of Warp's shell-reported
  typeahead (§7.2; Warp is AGPL-3.0 — clean-room, no Warp file read).
  `shell/zsh.sh`'s `line-init` hook, once per finished command
  (`__operator_terminal_TYPEAHEAD_ARMED`, set in `precmd`) and only at a
  primary prompt (`$CONTEXT == start`), reads what is waiting
  (`read -t 0 -k 1`, at most 257 characters), pushes it straight back into zle
  (`zle -U`), and — when it is at most 256 characters with no control
  character — reports it right after `input-ready` as
  `OSC 7000;v=1;typeahead=<percent-encoded UTF-8>` (`protocol/SPEC.md` §4.5).
  vt-core keeps the report only while the line is owned
  (`LineEditorTracker::on_typeahead`; `input-released` and the alternate
  screen drop it) and `TerminalCore.takeTypeahead()` hands it over once.
  `LineEditor` takes it on every change, visible or not, and adopts it only if
  the user sent keys, IME text or a paste to the pty since the last report
  (`TypeaheadGate`, `ts/editor/src/typeahead.ts`): it appends the text to the
  buffer, never submits it, and sends `^U` (0x15) to clear zsh's copy. Keys are
  still never held back.
- Why the shell does not clear its own buffer (the first design did): the
  daemon's `SendMessage` writes text, pauses, then sends Enter as a separate
  frame (`backend/internal/adapters/runtime/ptyhost/client.go:38-70`). Text
  arriving while a command is finishing looks exactly like typeahead to the
  shell; a shell that cleared it lost the command and ran an empty line —
  `TestShellBlocksAlternateScreenAtCaptureStartExcludesRepaint` failed 3 of 3
  runs that way. Only the line editor knows the user typed the text, so only
  it clears the shell's copy. `^U` is `kill-whole-line` in zsh's emacs keymap
  and `vi-kill-line` in `viins`; both clear the pushed text.
- bash and fish are not covered, by decision. bash: `READLINE_LINE` is
  reachable only inside a `bind -x` binding, which the additive-only contract
  forbids (`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
  §8, line 872); a `PROMPT_COMMAND` drain (`read -r -s -n 1 -t …`) can read the
  text but cannot hand it back to readline, so it would lose the `SendMessage`
  case; macOS `/bin/bash` 3.2 also takes whole-second timeouts only (`-t 0`
  read nothing). fish: `commandline` is empty in a `fish_prompt` handler (fish
  reads the typeahead after drawing the prompt) and its `read` has no timeout.
  Both keep the old doubling.
- Limits: a line typed ahead with Enter runs as before and is not moved; the
  typed text also stays in the finished command's output, where the tty echoed
  it while the command ran (as in every terminal); keys that reach zsh after
  its report and before the `^U` (one pty round trip) are cleared with it; a
  client without a line editor (the phone) leaves the text in the shell, as
  before; a user who rebinds `^U` gets the old doubling.
- Also fixed: `__operator_terminal_pct_encode` in `zsh.sh` encoded a code
  point, not bytes (`é` → `%e9`, `€` → `%c`); it now encodes UTF-8 bytes under
  `no_multibyte`. `bash.sh`'s encoder has the same bug and is not fixed here.
- Guards: `shell/zsh.test.mjs` (reports and is cleared by Ctrl-U, kept when
  nothing clears it, UTF-8, Enter typed ahead runs, multi-line submission,
  over the cap, `read -s` password never surfaced, a program's own prompt
  still gets its keys, vi insert mode, byte encoding); `bash.test.mjs` and
  `fish.test.mjs` "reports no typeahead"; `crates/vt-core/tests/typeahead.rs`
  (incl. the Claude Code recording); `ts/core/src/typeahead.test.ts`;
  `ts/editor/src/line-editor-typeahead.test.ts` (incl. the Claude Code
  recording and a faked report); `protocol/vectors/typeahead.json`;
  `backend/internal/terminal/block_assembler_test.go`
  `TestAssemblerIgnoresATypeaheadMark`; `backend/internal/integration`
  `TestShellBlocks*`.

```

Then, in §5, append this bullet after the last bullet of the section (the one that begins `- **What a parked pane still costs.**`, before the `---` that ends §5):

```markdown
- **Typing ahead covers zsh only.** bash and fish panes keep the old
  behaviour: text typed during a command lands in the shell's own line and
  is doubled by the next submission from the input box. The reasons and the
  evidence are in §4.32; `bash.sh`'s percent-encoder still encodes code
  points, not UTF-8 bytes, so a non-ASCII `cmd=`/`cwd=` from bash is wrong.
```

- [ ] **Step 3: Shell README**

In `packages/terminal/shell/README.md`, find the paragraph that ends

```
The branch read is the only command run for the package's own bookkeeping;
it is gated on `git rev-parse --is-inside-work-tree` and tolerates git
being absent.
```

and insert after it, with a blank line before:

```markdown
`zsh.sh` also registers a `line-init` zle hook widget. It emits `OSC 133 B`
and `OSC 7000 ; v=1 ; input-ready=1`, and at the first prompt after a
command it reads the input already waiting on the tty, gives it straight
back to zle with `zle -U`, and reports it as `OSC 7000 ; v=1 ;
typeahead=<percent-encoded UTF-8>` when it is 1–256 characters with no
control character (`protocol/SPEC.md` §4.5). The shell keeps the text; a
line editor that adopts it clears it with `^U`. `bash.sh` and `fish.fish`
do not report typeahead.
```

Then replace the whole `## Tests` section body (from the line after `## Tests` to the end of the file) with:

```markdown
`zsh.test.mjs`, `bash.test.mjs` and `fish.test.mjs` run under `node --test`
against the real shells; the pty cases drive them through `tmux`
(`pty.mjs`) and skip when the shell or tmux is missing. Run them with a
UTF-8 locale (`LANG=C.UTF-8 LC_ALL=C.UTF-8`): one case types `é` and `€`.
`go/bootstrap/shell/` holds the byte copies the daemon embeds;
`go/bootstrap/bootstrap_test.go` `TestScriptCopyIsInSyncWithShellDir` fails
when they drift.
```

- [ ] **Step 4: Survey**

In `docs/terminal/2026-09-19-terminal-reference-survey.md`:

4a. Replace the table row (line 133) that begins `| §7.2 | Partial |` with:

```markdown
| §7.2 | Partial | Background output after the last block is kept as a running synthetic block (`e7684bed8`). Typeahead done for zsh (roadmap Plan 6): the shell reports text typed during a command at its next prompt, the line editor adopts it only if the user typed it and clears the shell's copy with `^U` (`TERMINAL.md` §4.32). bash and fish keep the old behaviour. |
```

4b. Replace the status line (line 4115) that begins `> **Status: Partial.** Background output` with:

```markdown
> **Status: Partial.** Background output after the last block is kept as a running synthetic block (`e7684bed8`). Typeahead done for zsh (roadmap Plan 6, `TERMINAL.md` §4.32); bash and fish keep the old behaviour.
```

4c. Replace the "Ours today" bullet (lines 4129-4135, from `- Rows before the first` to `approximate (`packages/terminal/shell/zsh.sh:15-20`).`) with:

```markdown
- Rows before the first `A` and after the last `D` are synthetic blocks
  (`TERMINAL.md` §4.15 / CHANGELOG "markless rows"), so background output
  is kept and rendered. Typeahead: keys typed while a command runs go to
  the pty (`ts/editor/src/line-editor.ts` `passthrough`, since
  `4b31952aa`). Since roadmap Plan 6, zsh reports what was waiting on the
  tty at its next prompt as `OSC 7000;v=1;typeahead=` (Warp's
  `ShellReported`, clean-room) and the line editor adopts it
  (`TERMINAL.md` §4.32); bash and fish do not report it.
```

(The earlier text claimed keys typed during a command stay in the editor; that stopped being true at `4b31952aa`.)

4d. Recount and check the count sentence:

```bash
cd "$(git rev-parse --show-toplevel)" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c && grep -n "Every entry below carries a \*\*Status\*\* line" docs/terminal/2026-09-19-terminal-reference-survey.md
```
Expected: counts per status (on `5185f35be`: `39 Done`, `1 N/A`, `21 Notdone`, `1 Notneeded`, `7 Notpursued`, `19 Partial`) — this plan keeps §7.2 `Partial`, so they do not change unless a parallel plan already merged. Make the sentence on the printed line (line 52: "…: 39 done, 19 partial, 21 not done, 7 not pursued, 1 not needed, 1 n/a.") match the counts exactly, and change its date `(updated 2026-09-24)` in the heading two lines above to `(updated 2026-09-25)`.

- [ ] **Step 5: Plain-language doc**

In `docs/terminal/2026-09-24-not-done-plain-language.md`, replace the bullet (lines 149-150)

```
- **Typing ahead:** while a command runs, what you type goes straight to the
  running program instead of waiting in the input box (§7.2).
```

with

```markdown
- **Typing ahead (done for zsh, roadmap Plan 6, 2026-09-25):** in a zsh
  shell, what you type while a command runs still reaches the running
  program, and whatever it did not read shows up in the input box when the
  command finishes, ready to edit; it runs only when you press Enter. A line
  you finish with Enter while the command runs still runs right after it,
  as before. Still missing: bash and fish shells behave the old way (§7.2).
```

- [ ] **Step 6: Check citations and commit**

```bash
cd "$(git rev-parse --show-toplevel)" && sed -n 38,70p backend/internal/adapters/runtime/ptyhost/client.go | grep -n "Enter" | head -3 && sed -n 872p docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md && git diff --stat
```
Expected: `client.go` shows the separate-Enter comment inside lines 38-70; line 872 of the spec is the `add or remove any bindkey / bind binding` rule. If either moved, fix the citation in every doc you wrote. `git diff --stat` lists only the five doc files.

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/CHANGELOG.md TERMINAL.md packages/terminal/shell/README.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md && git commit -m "$(cat <<'EOF'
docs(terminal): record typing ahead for zsh (roadmap Plan 6)

Changelog, TERMINAL.md 4.32 and a known gap, shell README, survey 7.2
status, plain-language status.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Push and report

**Files:** none.

- [ ] **Step 1: Final check and push (never merge)**

```bash
cd "$(git rev-parse --show-toplevel)" && git status --short && git log --oneline origin/development..HEAD && git push -u origin terminal/plan-6-typing-ahead
```
Expected: `git status --short` prints nothing (if it lists `bench/…/baselines` files, `git checkout -- packages/terminal/bench/agent-session/baselines` and `git clean -fdq -- packages/terminal/bench/agent-session/baselines` first); seven commits (Tasks 1–6 and 8); the push creates the remote branch. Do not open a merge, do not merge into `development`.

- [ ] **Step 2: Completion report**

Write the report as your final message. It must contain:

1. The branch, the base commit, and the seven commit hashes with subjects.
2. Every gate with its result — **passed** with the command's last output line(s) copied verbatim, or **not run** with the exact reason:
   `cargo fmt --check`, `cargo clippy`, `cargo test` (count before/after), `terminal-marks` vectors, Go `go/marks`, `npm run build:wasm -- --force`, `npm run build:ts`, the five vitest suites (counts before/after), `npm run check:boundaries`, the three shell test files (pass/fail/skipped counts, shell versions), `go/bootstrap` tests, backend `internal/terminal` + `internal/service/shellterm` + `internal/integration -run TestShellBlocks`, pty-host `go test`, `vt_host.wasm` hash before/after, `build:daemon`, `bench:feel` (against the Task 0 recording), `bench:selection`, `bench:agent:gate`, `bench:agent:scroll`, `bench:affordances` ×3 (and that the PNGs were restored), frontend `tsc` + `BlockTerminal.test.tsx`, the fixture grep (Task 7 Step 4).
3. Every line-number drift found against this plan.
4. Follow-up found, not done: `packages/terminal/shell/bash.sh:9-19` `__operator_terminal_pct_encode` encodes code points, not UTF-8 bytes (same bug this plan fixed in zsh).
5. The real-app checklist, each item marked **not run: needs the desktop app on a Mac** (a cloud session cannot run it):
   - In a zsh shell pane: run `sleep 3`, type `echo hi` while it runs. Expected: `echo hi` also appears in the sleep block's output (the tty echo), and when the prompt returns it is in the input box, not run. Press Enter once: `hi` is printed once, and the block's command reads `echo hi` (not `echo hiecho hi`).
   - Same, but type `echo hi` then Enter during `sleep 3`: it runs right after `sleep` finishes, as before; the input box stays empty.
   - In a zsh pane: `read -s pw` then type a password and Enter: nothing appears in the input box or the pane.
   - In a Claude Code pane: type while Claude is working and at its prompt. Expected: exactly as before — every key reaches Claude, the input box never shows text.
   - In a bash pane: type during `sleep 3`. Expected: unchanged from before this plan (the text stays with bash).
   - After rebuilding: restart the daemon and the app, and open a **new** shell pane (running shells keep the old script).
