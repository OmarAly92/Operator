# Handoff: Claude account switching — "/status shows the wrong account"

Written 2026-09-18 00:05 for a cleared session. Everything below is evidence
gathered on this machine (file:line or command output), not inference, except
where marked **not known**. Read `CLAUDE.md`, `AGENTS.md`, and — before touching
anything under `packages/terminal` or `backend/internal/adapters/runtime/ptyhost`
— `TERMINAL.md` end to end (§4.15 is the entry added by this work).

## 1. The user's report

> "I switched the orchestrator to the **Default** account, ran `/status` inside
> the Claude Code TUI, and the email shown is the **Personal** account's email.
> Same on a session created fresh after restarting the daemon and app."

The email in both cases is `omarkarim5555@gmail.com`.

## 2. What is already proven to work (do not re-investigate)

All of this is uncommitted on `development` (see §6 for the file list).

1. **The daemon routes the right `CLAUDE_CONFIG_DIR`.** Verified on an
   isolated daemon built from the working tree (`OPERATOR_PORT=3005`,
   throwaway `OPERATOR_DATA_DIR`): spawn a claude-code worker with
   `claudeAccountId: personal` → the `claude` processes have
   `CLAUDE_CONFIG_DIR=/Users/omaraly/.claude-personal`; `POST
   /sessions/{id}/relaunch-agent {"claudeAccountId":"default"}` → the new
   `claude` processes have **no** `CLAUDE_CONFIG_DIR`; relaunch back to
   personal → personal again. Checked with
   `ps eww -o command= -p <pid> | tr ' ' '\n' | grep ^CLAUDE_CONFIG_DIR=`.
2. **Two bugs found and fixed on the way** (tests pin both):
   - `UpdateSession` never wrote `claude_account_id`, so the switched account
     was not persisted. New `SetSessionClaudeAccount` query/store method
     (`backend/internal/storage/sqlite/queries/sessions.sql`,
     `store/session_store.go`), used by `Manager.RelaunchAgentFresh`
     (`backend/internal/session_manager/manager.go`). Real-SQLite test
     `TestSessionPersistsClaudeAccountChange`.
   - The pty-host inherits the session env at birth and builds child envs from
     its own `os.Environ()`, so a key *removed* on respawn (the default
     account removes `CLAUDE_CONFIG_DIR`) leaked from the pty-host's own
     environment. Fixed in `backend/internal/adapters/runtime/ptyhost/spawn.go`:
     the daemon stamps `OPERATOR_PTYHOST_SESSION_ENV=<overlay keys>` on the
     pty-host, `respawnEnvironment` drops stamped keys the new overlay omits.
     Tests `TestHostProcessEnvironmentRecordsTheSessionKeys`,
     `TestRespawnEnvironmentDropsSessionKeysTheNewOverlayOmits`.
3. **Sessions started before the daemon rebuild keep the old pty-host.**
   pty-hosts outlive daemon restarts by design. The user's orchestrator
   `scratch-29` (pty-host pid 82442, started Sep 16 20:37) ran old code for
   every test until they spawned a new session. Any test must be on a session
   spawned after the daemon binary was rebuilt and restarted.

## 3. The actual finding: both "accounts" are the same Claude login right now

Claude Code keys its macOS Keychain credential by config dir:
service `Claude Code-credentials` for `~/.claude`, and
`Claude Code-credentials-<sha256(configDir)[:8]>` otherwise
(`printf '%s' /Users/omaraly/.claude-personal | shasum -a 256 | cut -c1-8`
= `30c38298`, and `security dump-keychain | grep 'Claude Code-credentials'`
lists exactly `Claude Code-credentials-30c38298`). So the two folders have
**separate** credential stores — Operator is not sharing them.

But the contents are the same account:

| | `~/.claude` (Default) | `~/.claude-personal` (Personal) |
|---|---|---|
| config file | `~/.claude.json` (NOTE: home, not `~/.claude/.claude.json`) | `~/.claude-personal/.claude.json` |
| `oauthAccount.emailAddress` | omarkarim5555@gmail.com | omarkarim5555@gmail.com |
| `oauthAccount.accountUuid` | `dead0af6…` | `dead0af6…` (identical) |
| `oauthAccount.organizationUuid` | `6f1231d8…` | `6f1231d8…` (identical) |
| Keychain `claudeAiOauth.subscriptionType` | max | max |
| Keychain `rateLimitTier` | default_claude_max_5x | default_claude_max_5x |
| Keychain token `expiresAt` | 1789697402823 | 1789707279812 (personal login is the more recent one) |

Operator's own Settings → Claude accounts screen already showed this: both
rows read "Max" and `omarkarim5555@gmail.com` (the daemon probes each folder
with `claude auth status` under that folder's env —
`backend/internal/service/claudeaccounts/status.go`).

So `/status` inside a Default session showing `omarkarim5555@gmail.com` is
**correct for the current state of the folders**: that *is* the account
`~/.claude` is logged into. The switch is working; the two folders simply
hold the same login.

The memory note `claude-accounts-on-this-machine.md` (in
`~/.claude/projects/-Users-omaraly-development-AI-Operator/memory/`) says
Personal was a **Pro** account at `~/.claude-personal`. It is Max now, same
uuid as Default. **Not known:** when/how `~/.claude-personal` got re-logged
into the Max account. Things ruled out by reading the code:

- `claudesetup.Ensure` only symlinks `CLAUDE.md, settings.json, skills,
  commands, agents, plugins` (`backend/internal/adapters/agent/claudecode/claudesetup/setup.go:SharedItems`).
- `claudesetup.SyncMCP` copies only the `mcpServers` key from `~/.claude.json`
  into the account's `.claude.json` (`claudesetup/mcp.go`). It does not touch
  `oauthAccount`.
- Nothing in Operator writes the Keychain.

Remaining candidates (verify, don't assume): the user ran Operator's
"Log in" for Personal (`Service.Login`, `service.go:~240`, launches `claude`
with `CLAUDE_CONFIG_DIR=~/.claude-personal`) and signed in with the Max
account; or ran `claude /login` in that folder by hand; or Claude Code's own
`/login` flow reused the browser session that was already signed in as the
Max account (the OAuth page defaults to the browser's current claude.ai
login — very plausible if both logins happened in the same browser).

## 4. What to do

1. **Confirm with the user which email/plan Personal is supposed to be.** If
   it should be a different login, the fix is a re-login of that folder, not
   code: in Operator, Settings → Claude accounts → Personal → ⋯ → Log in, and
   in the browser page that opens, sign out of claude.ai first (or use a
   private window) so the OAuth grant goes to the intended account. Then
   `security find-generic-password -s "Claude Code-credentials-30c38298" -w |
   python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["subscriptionType"])'`
   and `~/.claude-personal/.claude.json → oauthAccount.emailAddress` must
   differ from Default's. Never print the tokens.
2. **Make the product tell the user this.** Today the accounts screen shows
   the same email twice with no warning, and the session chip says
   "Default"/"Personal" as if they were different logins. Add a visible
   warning in `ClaudeAccountsSection.tsx` (and the mobile equivalent if it
   shows accounts) when two accounts report the same email / `accountUuid`
   — the daemon already has both via `claude auth status`
   (`ClaudeAccountStatus.reportedEmail` in the API; add `accountUuid` if the
   probe output carries it — check `parseAuthStatus` in `status.go`).
   This is the change that would have made the current confusion impossible.
3. Optionally, in the Login flow, open the OAuth URL in a private window or
   show a one-line hint "sign out of claude.ai first if you want a different
   account". **Not known** whether Claude Code exposes the login URL in a way
   Operator can intercept; check `claude auth login --help` / the
   `LoginLaunch` PTY output before designing this.
4. Do **not** change `resolveSpawnClaudeAccount`: the user explicitly decided
   that workers inherit their orchestrator's account and the "New tasks"
   account applies only to sessions the user spawns directly (a change to the
   reverse was made and then reverted on 2026-09-17).

## 5. How to verify anything here for real

Desktop automation cannot click the Tauri window; drive the daemon.

```bash
# isolated daemon from the working tree (scrub CLAUDE* env first — see memory
# note scrub-claude-env-before-running-operator-dev)
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
SB=/tmp/opr-sb && mkdir -p $SB/data && cp frontend/daemon/opr $SB/opr
(cd $SB && env $(env | grep -o '^CLAUDE[A-Z_]*' | sed 's/^/-u /') OPERATOR_PORT=3005 OPERATOR_DATA_DIR=$SB/data OPERATOR_RUN_FILE=$SB/running.json nohup ./opr daemon > daemon.log 2>&1 &)
P=http://127.0.0.1:3005/api/v1
curl -s -X POST $P/claude-accounts -H 'content-type: application/json' -d '{"label":"Personal"}'   # adopts ~/.claude-personal
curl -s -X POST $P/sessions -H 'content-type: application/json' -d '{"projectId":"scratch","harness":"claude-code","kind":"worker","prompt":"Do nothing. Wait.","displayName":"probe","cols":100,"rows":30,"claudeAccountId":"personal"}'
curl -s -X POST $P/sessions/<id>/relaunch-agent -H 'content-type: application/json' -d '{"claudeAccountId":"default"}'
# evidence = process env, not the TUI:
for pid in $(pgrep -f '^/opt/homebrew/bin/claude'); do ps eww -o command= -p $pid | tr ' ' '\n' | grep -E '^CLAUDE_CONFIG_DIR=' || echo "$pid: default"; done
curl -s -X POST $P/sessions/<id>/kill; kill <daemon pid>
```

To read the TUI itself, attach to `ws://127.0.0.1:3005/mux` with
`{"ch":"terminal","id":"<session>","type":"open","cols":100,"rows":30}`,
send `/status\r` as a base64 `type:"data"` frame, decode the `data` frames
(a ~40-line Python `websockets` client; one is in the previous session's
scratchpad as `cap.py`). The dev app's daemon is on `:3002`, the installed
app's on `:3001`; do not spawn test sessions on those without the user.

## 6. Uncommitted work on `development` (all gates green as of 23:54)

Suggested commits, in order:

1. **feat: show each Claude session's account on the board card and session topbar**
   - `frontend/src/renderer/components/SessionClaudeAccountChip.tsx` (new),
     `ShellTopbar.tsx`, `SessionsBoard.tsx`, `hooks/useClaudeAccounts.ts`
     (`claudeAccountLabelForSession`) + tests, `i18n/*.json` (`shell.claudeAccount`).
2. **feat: switch a session's Claude account from the tab menu (relaunch)**
   - Backend: `RelaunchAgentRequest.claudeAccountId`, `RelaunchAgentConfig`
     in `session_manager/manager.go`, service + controller threading,
     `SetSessionClaudeAccount` store method, `openapi.yaml`, `schema.ts`.
   - Renderer: `SessionAgentTabMenu.tsx` ("Claude account ▸" submenu),
     `ui/context-menu.tsx` (`ContextMenuSub*`), `hooks/useRelaunchAgent.ts`,
     `CenterPane.test.tsx`, `i18n/*.json` (`terminal.claudeAccount`,
     `terminal.switchAccount{Title,Body}`).
3. **fix(ptyhost): drop stale session env on respawn** — `spawn.go`,
   `spawn_unix.go`, `spawn_windows.go`, `host_pty_unix.go`,
   `host_conpty_windows.go`, `spawn_env_test.go`.
4. **feat(terminal): process boundary mark ends the block on relaunch** —
   `packages/terminal/crates/vt-core/{parser.rs,block_grid.rs,grid.rs,event_bridge.rs,screen/edit.rs}`,
   `tests/process_boundary.rs` (new), `CHANGELOG.md`, `ptyhost/respawn.go`
   (+test), the rebuilt `ptyhost/vtwasm/assets/vt_host.wasm`, `TERMINAL.md` §4.15.
   Verified with a real captured relaunch stream replayed through vt-core:
   old session = finished block with full transcript, new one = clean block.

Gates that were run and passed: `cargo fmt/clippy -D warnings/test` (33
suites), host wasm + `go test ./internal/adapters/runtime/ptyhost/...`,
renderer wasm + core/renderer-dom/react vitest, `npm run bench:selection`,
frontend `tsc` + 1438 vitest, `go test ./...` in backend, `GOOS=windows go vet`
for ptyhost. Commit messages end with
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## 7. Rules that bit during this work

- `flutter`/`AGENTS.md`/`CLAUDE.md`: no comments in new code; cite Warp for
  terminal rendering decisions; product-independent `packages/terminal`.
- A green in-memory fake is not proof (the `UpdateSession` bug hid behind one
  for the whole account feature). Use the real SQLite store and real
  processes for anything touching persistence or env.
- Old pty-hosts survive daemon restarts; always test on a session spawned
  after the rebuild.
