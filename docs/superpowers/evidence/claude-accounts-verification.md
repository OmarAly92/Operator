# Claude accounts — real-app verification (Task 13 Step 2)

**Date:** 2026-09-15
**Branch:** `feat/claude-accounts` at `130845df6` (review fixes applied)
**App:** `npm run tauri:dev` from `frontend/`, isolated dev mode — daemon on
`127.0.0.1:3002`, data `~/.operator/dev/data` (DB migrated 0108 → 0109 on boot),
Claude Code 2.1.267. The installed app's daemon on `:3001` was left untouched.

Two facts about how this run differed from the plan's script, both recorded
before the results:

- **The shell had to be launched with the `CLAUDE*` environment scrubbed.** The
  first launch inherited this Claude Code session's `CLAUDE_CODE_CHILD_SESSION`
  marker; every spawned Claude then showed "Transcript saving is off — inherited
  CLAUDE_CODE_CHILD_SESSION marker" and wrote no transcript. Relaunching with
  `env -u CLAUDE…` (24 variables) fixed it; the daemon process then carried zero
  `CLAUDE*` variables. This only affects launching the app from inside a Claude
  Code session.
- **State changes were driven through the daemon's own routes** (the exact ones
  the renderer calls) and the terminal mux WebSocket, because the desktop
  automation available to this session cannot click inside the Tauri webview.
  The window itself was captured with `screencapture` (Board view). The Settings
  section, composer chip and switch dialog were therefore verified by their
  unit tests plus the API they render, not by a click-through.

## Results

| # | Plan step | Result |
|---|---|---|
| 1 | Settings lists **Default** first, plan **Max**, no Remove | **Pass (API).** `GET /claude-accounts` → `default` first, `isDefault: true`, `status.subscriptionType: "max"`, `reportedEmail: omarkarim5555@gmail.com`. The Remove button is hidden for `isDefault` (`ClaudeAccountsSection.test.tsx`). |
| 2 | Add **Personal** | **Pass, adopted.** `POST /claude-accounts {"label":"Personal"}` → `id: personal`, `configDir: /Users/omaraly/.claude-personal`. The folder already existed from the 2026-09-14 probes, so it was adopted (mode stayed `drwxr-xr-x`, not `0700` — the plan's `drwx------` applies only to a folder Operator creates). Links created: `CLAUDE.md`, `commands`, `skills` → `~/.claude/…`; `agents` skipped (no source); `settings.json` and `plugins` were real files and are reported `replaced`. `POST /claude-accounts/personal/login` returned shell terminal `shellterm-adcb24b720c65d9e` titled "Claude login · Personal"; its `claude` process (pid 70344) ran with `CLAUDE_CONFIG_DIR=/Users/omaraly/.claude-personal`. |
| 3 | `/login`, then Personal shows **Pro** | **Pass, without a new login.** The folder already held a login. `GET /claude-accounts?refresh=1` → Personal `loggedIn: true`, `subscriptionType: "pro"`, `reportedEmail: omaralybusiness8888@gmail.com`; Default still `max`. `security dump-keychain` lists `Claude Code-credentials`, `Claude Code-credentials-30c38298`, `Claude Code-credentials-6ed7293c`. `claude auth status` with no env still reports the default login. |
| 4 | New task on Personal; `/status` shows it; only `~/.claude-personal/projects` gains the folder | **Pass.** `POST /sessions {projectId: scratch, harness: claude-code, claudeAccountId: personal}` → `scratch-26`, `claudeAccountId: personal`. Its pty-host, supervisor and `claude` processes all carry `CLAUDE_CONFIG_DIR=/Users/omaraly/.claude-personal`; no other process does. The session header (read over the mux) shows **"Sonnet 5 · Claude Pro"**. `~/.claude-personal/projects` gained `-Users-omaraly--operator-dev-data-worktrees-scratch-workers-scratch-26`; `~/.claude/projects` (121 entries) was unchanged. |
| 5 | The Personal session obeys the global `CLAUDE.md` | **Pass.** Prompt: "What are your standing instructions about comments? Quote them in one line and stop." Transcript `…/scratch-26/38ccd826-b19d-592b-b4f7-5a66d7dba3de.jsonl` assistant text: `- don't make comments`. |
| 6 | Switch to Default → fresh; back to Personal → resumed | **Pass.** `POST /sessions/scratch-26/switch-agent {targetHarness: claude-code, targetClaudeAccountId: default}` → `state: completed`, `targetStartMode: fresh`, `agentHandoffStatus: received`, `sourceTranscriptStatus: available`; session `claudeAccountId: default`, new processes have `CLAUDE_CONFIG_DIR` unset. Switch back with `targetClaudeAccountId: personal` → `state: completed`, **`targetStartMode: resumed`**; session `personal`, `CLAUDE_CONFIG_DIR` set again; the resumed screen shows the original conversation and the handoff write. `GET /sessions/scratch-26/agent-switches` lists both records with the account columns populated. (An earlier switch on `scratch-25`, before the env fix, also completed `fresh` with `sourceTranscriptStatus: unavailable`.) |
| 7 | Restart → session restores on its last account | **Pass.** Killed the dev shell's process group and relaunched. `GET /sessions/scratch-26` → `claudeAccountId: personal`, not terminated, restored process env `CLAUDE_CONFIG_DIR=/Users/omaraly/.claude-personal`; `scratch-25` restored on `default` with the variable unset. Verified on two restarts. |
| 8 | Remove Personal while a session uses it | **Pass.** `DELETE /claude-accounts/personal` → `409 {"code":"CLAUDE_ACCOUNT_IN_USE","message":"Sessions still use this account; remove or switch them first"}`. The section renders that message inline (`ClaudeAccountsSection.test.tsx`). |
| 9 | Mobile: Account row only for Claude Code; spawn on Personal | **Not run in the real app.** Needs a paired daemon with the LAN listener and a booted simulator; neither was available in this run. Covered by `spawn_body_test.dart` (row hidden for non-Claude harnesses), `spawn_cubit_test.dart` (account reset in `setHarness`, `claudeAccountId` sent only for claude-code) and the params/model tests. |

## Observations worth knowing

- **First-run dialogs in a new account folder are Claude's, and the session
  waits on them.** `scratch-26` sat on "Claude in Chrome extension detected —
  No, keep browser tools off / Yes, use my browser" until Enter was sent over
  the mux; the Personal `.claude.json` had never answered it (its `theme` is
  also unset). A user sees this in the session terminal and answers once per
  folder. Not a feature defect, but the Settings copy could mention it.
- **The Default account was at its weekly usage limit** during the run ("You've
  hit your weekly limit · resets 5pm"). Switches to Default still completed and
  the handoff was still received, so this did not block any step.
- Both verification sessions are visible on the Board of the dev window
  (`accounts-verify-2` idle on Personal, `accounts-verify` on Default).

## Commands used

```bash
cd frontend && env -u CLAUDE… -u OPERATOR_DATA_DIR -u OPERATOR_RUN_FILE -u OPERATOR_PORT npm run tauri:dev
curl -s http://127.0.0.1:3002/api/v1/claude-accounts?refresh=1
curl -s -X POST http://127.0.0.1:3002/api/v1/claude-accounts -d '{"label":"Personal"}'
curl -s -X POST http://127.0.0.1:3002/api/v1/claude-accounts/personal/login -d '{}'
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions -d '{"projectId":"scratch","harness":"claude-code","claudeAccountId":"personal","prompt":"…"}'
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions/scratch-26/switch-agent -d '{"targetHarness":"claude-code","targetClaudeAccountId":"default","idempotencyKey":"verify-2"}'
curl -s http://127.0.0.1:3002/api/v1/sessions/scratch-26/agent-switches
curl -s -i -X DELETE http://127.0.0.1:3002/api/v1/claude-accounts/personal
ps eww -o command= -p <pid> | tr ' ' '\n' | grep ^CLAUDE_CONFIG_DIR=
```

Terminal screens were read by opening the pane on `ws://127.0.0.1:3002/mux`
(`{"ch":"terminal","id":"<session>","type":"open","cols":120,"rows":40}`) and
decoding the base64 `data` frames.
