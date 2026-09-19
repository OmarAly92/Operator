# Claude Accounts — Design

**Date:** 2026-09-14
**Status:** Approved design, not yet implemented
**Goal:** Let one Operator run Claude Code sessions on more than one Claude
account. Settings lists the accounts, the default `~/.claude` first; spawning a
Claude session picks an account; a running session can switch account; and every
account shares the user's Claude setup.

Measurements cited as **P1–P6** come from
[`docs/superpowers/evidence/claude-accounts-probes.md`](../evidence/claude-accounts-probes.md),
recorded on 2026-09-14 against Claude Code 2.1.267.

## 1. Problem

Operator launches every Claude session with the user's one Claude login.
Claude Code supports separate accounts through `CLAUDE_CONFIG_DIR`: each folder
has its own login (P1, P2). Operator cannot use that today:

- Launch environments come from project settings only
  (`runtimeEnv`, `backend/internal/session_manager/manager.go:3084`), so there is
  no per-session account.
- Several places assume the default folder:
  - workspace trust writes `~/.claude.json`
    (`claudeConfigPath`, `backend/internal/adapters/agent/claudecode/claudecode.go:521`);
  - the auth check reads the same file (`claudecode.go:361`);
  - the transcript resolver passes a nil env
    (`backend/internal/observe/transcript/resolve.go:49`);
  - the session-id claim check passes a nil env
    (`backend/internal/adapters/agent/claudecode/claim.go:27`);
  - usage collection and the transcript watcher hard-code
    `~/.claude/projects` (`backend/internal/service/usage/collector.go:80`,
    `backend/internal/daemon/daemon.go:300`, `:441`).

The user runs Claude on more than one account and uses this daily, so the
requirements are **stable, reliable, practical**.

## 2. Facts the design rests on

From the probes:

1. **Logins are separate per folder.** Each `CLAUDE_CONFIG_DIR` folder gets its
   own Keychain entry, and adding one does not touch the default login (P2).
2. **The login is bound to the exact absolute path.** The Keychain entry is
   `Claude Code-credentials-<sha256(path)[:8]>`. A moved folder, a trailing
   slash or a `~` form looks up a different entry and appears logged out (P3).
3. **The default account must not set `CLAUDE_CONFIG_DIR`.** Setting it to
   `~/.claude` explicitly would look up a suffixed entry that does not exist (P3).
4. **Claude's global config lives inside the folder** when the variable is set
   (`$CLAUDE_CONFIG_DIR/.claude.json`), and at `~/.claude.json` otherwise (P1).
5. **The reported email does not identify an account.** Two logins on different
   plans reported the same email, org and account id; `subscriptionType`
   differed (P4).
6. **Claude writes real files on first launch** in an empty folder (P5).
7. **A linked `plugins/` resolves from any folder** because the plugin registry
   stores absolute paths (P6).

## 3. Data model

### 3.1 `claude_accounts` (migration `0109_claude_accounts.sql`)

| Column | Type | Meaning |
|---|---|---|
| `id` | TEXT PK | `default`, or a generated short id |
| `label` | TEXT NOT NULL UNIQUE | `Default`, `Personal` |
| `config_dir` | TEXT UNIQUE | `NULL` for the default; absolute clean path otherwise |
| `is_default` | INTEGER NOT NULL | exactly one row is `1` |
| `created_at` | TIMESTAMP NOT NULL | |

- `CHECK ((is_default = 1 AND config_dir IS NULL) OR (is_default = 0 AND config_dir IS NOT NULL))`.
- The migration inserts `('default', 'Default', NULL, 1, now)`.
- `NULL` means "Claude's own default". The database therefore enforces fact 3:
  there is no path to put in `CLAUDE_CONFIG_DIR` for the default account.
- `config_dir` is written once, at creation, and never updated (fact 2). It is
  stored as `filepath.Clean` of an absolute path with no trailing slash, and is
  passed to Claude byte-identical. It is never re-derived from the label, and
  symlinks are never resolved.
- The label can be renamed; the folder cannot.

### 3.2 Session ownership

- `sessions.claude_account_id TEXT NOT NULL DEFAULT 'default' REFERENCES claude_accounts(id) ON DELETE RESTRICT`.
- Existing rows take `default`; no data wipe is needed.
- It is a real column, not metadata, because restore, switching and deletion
  must trust it.
- `SessionRecord.ClaudeAccountID` carries it. The session read model adds
  `claudeAccountId` and `claudeAccountLabel`.

### 3.3 Switch records

`agent_switches` adds `from_claude_account_id` and `target_claude_account_id`
(both nullable: non-Claude sides are `NULL`). Switch history and crash recovery
need to know which folder each side used.

## 4. API

Error envelope as today (`{error, code, message, requestId}`).

### 4.1 Accounts

- **`GET /claude-accounts`** returns every account, default first:
  `{id, label, configDir, isDefault, status, sharedSetup}`.
  - `status`: `{loggedIn, subscriptionType, reportedEmail, checkedAt}` from
    running `claude auth status` with the account's env, 3-second timeout, all
    accounts in parallel. Cached per account for 30 seconds, and invalidated by
    login and by `?refresh=1`. A timeout or parse failure gives
    `loggedIn: null` ("Unknown"), never an error.
  - `reportedEmail` is display-only and labelled "reported by Claude" (fact 5).
  - `sharedSetup`: per shared item, `linked | missing | replaced` (§7).
  - `configDir` for the default is resolved at read time to the absolute
    `~/.claude` for display only.
- **`POST /claude-accounts {label}`** — trims the label, derives the slug
  (lowercase, `[a-z0-9-]`, collapsed dashes), and sets the path to
  `$HOME/.claude-<slug>`:
  - A folder that doesn't exist is created with mode `0700`.
  - A folder that exists and isn't registered is **adopted**: its login is kept,
    and existing real files at shared paths are reported as `replaced` rather
    than overwritten.
  - Shared links are created **before** the response returns, so they exist
    before any Claude launch (fact 6).
  - Errors: `CLAUDE_ACCOUNT_EXISTS` (label or folder already registered),
    `CLAUDE_ACCOUNT_LABEL_INVALID` (empty, over 32 characters, or an empty slug),
    `CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE` (cannot create, or the path exists as a
    non-directory).
- **`PATCH /claude-accounts/{id} {label}`** renames the label only.
- **`POST /claude-accounts/{id}/login`** repairs shared links (§7), then opens a
  shell terminal whose environment carries `CLAUDE_CONFIG_DIR` (unset for the
  default) and which runs `claude auth login`, so the sign-in flow starts at once
  even when the folder already holds a login. It returns the shell terminal.
- **`POST /claude-accounts/{id}/relink`** backs up each `replaced` item as
  `<name>.bak-<unix>` and then links it.
- **`DELETE /claude-accounts/{id}`** unregisters the account; the folder stays on
  disk. Errors: `CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE`, `CLAUDE_ACCOUNT_IN_USE` (any
  session row references it — the FK — including sessions that aren't running),
  `CLAUDE_ACCOUNT_NOT_FOUND`.

### 4.2 Spawn and switch

- `SpawnSessionRequest` and `SpawnOrchestratorRequest` add `claudeAccountId`.
  - Omitted with harness `claude-code`: the default account.
  - Omitted on a worker whose `requestedBy` orchestrator has an account: that
    orchestrator's account.
  - Sent with any other harness, or unknown: `INVALID_CLAUDE_ACCOUNT`.
- `SwitchAgentRequest` adds `targetClaudeAccountId`, allowed only when
  `targetHarness` is `claude-code`; omitted means the session's current account.
- The shell-terminal service gains an internal `Env` on
  `OpenShellTerminalInput` (`backend/internal/service/shellterm/types.go:48`),
  used only by the login route. The public `POST /shell-terminals` body does
  not expose it.

Regenerate with `npm run api`. New named types get `schemaNames` entries in
`backend/internal/httpd/apispec/specgen/build.go`.

## 5. Launching on an account

### 5.1 One environment builder

`runtimeEnv` and `launchRuntimeEnv` take the `SessionRecord` (plus an optional
account override for switching) instead of loose ids. They resolve the account
and:

- **default:** delete `CLAUDE_CONFIG_DIR` from the env, even if project env set
  it, so the account is always the session's account;
- **other:** set `CLAUDE_CONFIG_DIR=<config_dir>`.

Every launch goes through it:

- spawn (`manager.go:623`)
- restore (`manager.go:1487`, `:3331`)
- relaunch
- agent-switch source and target (`agent_switching.go:214`, `:742`, `:2533`)

A table test over these call sites guards that no path skips it.

A project env that sets `CLAUDE_CONFIG_DIR` is overridden by the session account.
This is deliberate and documented in project settings help text.

### 5.2 Launch preflight

Before any Claude launch on a non-default account:

1. `config_dir` must exist and be a directory; otherwise the launch fails with
   `CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE`. It never falls back to the default.
2. Shared links are repaired (§7).
3. User-scope MCP servers are synced (§7).

A logged-out account is not blocked; Claude shows its own login prompt in the
session terminal, which is an accurate failure (the probe is advisory, as
`AuthStatus` already treats it at `claudecode.go:329`).

### 5.3 Adapter changes (`adapters/agent/claudecode`)

- `claudeConfigPath()` is deleted. A new
  `claudeGlobalConfigPath(env map[string]string) (string, error)` returns
  `$CLAUDE_CONFIG_DIR/.claude.json` when set, else `~/.claude.json` (fact 4).
- `PreLaunch` uses `claudeGlobalConfigPath(cfg.Env)`. `ports.LaunchConfig`
  (`backend/internal/ports/agent.go:373`) has no `Env` today and gains
  `Env map[string]string`. The manager fills it from the env it already builds
  at each launch site. `WorkspaceHookConfig` (`agent.go:401`) already carries
  one, so this follows an existing shape.
- `claudeTrustMu` becomes a per-path lock, so two accounts don't serialize on
  each other.
- `AuthStatus` stays default-account only (agent catalog badge). Per-account
  status comes from §4.1.
- `IsSessionIDClaimed` takes the list of every registered account's session
  folder (default `~/.claude` plus each `config_dir`) and reports claimed if any
  folder holds the transcript. Over-reporting costs one allocator number
  (`claim.go:20`).
- `ports.AgentNativeSessionConfigProvider.NativeSessionConfigDir` keeps its
  signature; no caller passes `nil` any more.

### 5.4 Reading transcripts and usage

- `transcript.Resolver.Path` (`resolve.go:37`) resolves the session's account
  env and passes it to `NativeSessionConfigDir`.
- `usagesvc.SourceRoots.ClaudeProjects` becomes `[]string`, one `projects`
  folder per account.
  - `allowedRoots` and `discoverPath` (`collector.go:1648`, `:1698`) use only
    the binding session's account root, so a transcript in another account's
    folder is rejected.
- The usage pipeline and transcript watcher get `AddRoot(path)`.
  - `POST /claude-accounts` calls it after creation.
  - Roots are never removed at runtime: deletion requires no referencing
    session, so a stale root watches an idle folder until restart.

## 6. Switching account on a running session

Reuses the agent-switch saga. The target is `(harness, claudeAccountID)`.

- `SwitchAgentConfig` adds `TargetClaudeAccountID`.
- The same-harness rejection (`agent_switching.go:186`) rejects only when the
  harness **and** the account both match.
- `prepareTargetActivation` (`agent_switching.go:722`) builds the target env
  from the target account.
- `findTargetResumeCandidate` already filters by `ConfigDir`
  (`agent_switching.go:1010`), so:

| Switch | Result |
|---|---|
| Claude@A → Claude@B, first time | fresh start with hidden handoff context; worktree, branch and PR unchanged |
| Claude@B → Claude@A | resumes A's original conversation |
| Codex → Claude@B | as today, on account B |

- `sessions.claude_account_id` is updated in the same store transaction that
  records the target as the session's active generation. A daemon restart after
  that point restores on the new account.
- A failed switch leaves the column unchanged.
- **Not done:** copying a transcript into another account's folder to `--resume`
  there. It writes provider-owned storage, which the continuation protocol
  forbids, and it is unverified that Claude accepts it.

## 7. Shared setup

Every non-default account shares the user's Claude setup with the default
`~/.claude`.

| Item | Handling |
|---|---|
| `CLAUDE.md`, `settings.json`, `skills/`, `commands/`, `agents/`, `plugins/` | symlink → `~/.claude/<item>` |
| `.claude.json`, `projects/`, `sessions/`, `history.jsonl`, `todos/`, caches, backups, Keychain login | per account, untouched |
| `mcpServers` in `~/.claude.json` | copied into `<config_dir>/.claude.json` |

A new `claudesetup` package (inside `adapters/agent/claudecode` or alongside it)
owns this, with one function used by account creation, login and launch
preflight:

```go
Ensure(defaultDir, accountDir string) (Report, error)
```

For each shared item, keyed by name:

| State | Action | Report |
|---|---|---|
| source absent in `~/.claude` | nothing | `skipped` |
| target absent | create symlink | `linked` |
| target is a symlink to the source | nothing | `linked` |
| target is a symlink elsewhere | replace it (Operator owns links) | `linked` |
| target is a real file or directory | **leave it** | `replaced` |

- A `replaced` item never blocks a launch.
- Settings shows "Setup no longer shared: `settings.json`" with **Re-link**
  (§4.1). This covers Claude writing a real file over a link and adopted folders
  (P5).
- MCP sync reads `mcpServers` from `~/.claude.json`. If it differs from the
  account's `.claude.json`, it replaces only that key, using the same
  read–modify–temp-file–rename write and per-path lock as trust (§5.3). Every
  other key, including login state, is preserved.
- Sync is one-way, default to account. MCP servers added from an account's own
  CLI are overwritten on the next launch; the Settings section says so.

## 8. Screens

### 8.1 Desktop Settings — "Claude accounts"

A new section in `GlobalSettingsForm`
(`frontend/src/renderer/components/GlobalSettingsForm.tsx:36`) after General,
built from `SettingsSection` / `SettingsRow` and shadcn primitives.

- **Row layout:** label; plan badge (`Max`, `Pro`, `Not logged in`, `Unknown`);
  folder path in mono; reported email in muted text.
- **Default row:** a `Default` tag; **Log in** only.
- **Other rows:** **Log in** (or **Log in again**), **Rename**, **Remove**
  (confirm dialog; shows the `CLAUDE_ACCOUNT_IN_USE` message inline), and, when
  any item is `replaced`, the setup warning with **Re-link**.
- **Add account:** a dialog with a label field.
  - Shows the resulting folder path live, e.g. `~/.claude-personal`.
  - On success the dialog closes and the login terminal opens.
- **Login terminal:** opened the same way `useOpenShellTerminal` is used in
  `Sidebar.tsx:479`.
- **Refresh:** the list refetches with `refresh=1` on window focus and when the
  login terminal closes.

### 8.2 Desktop new task

In `TaskComposer` (`frontend/src/renderer/components/TaskComposer.tsx:333`):

- An **Account** chip after the Agent chip, styled like the model picker,
  rendered only when the agent is `claude-code`.
- It defaults to `default`, and changing the agent resets it, as model does
  (`:347`).
- Options show label and plan badge; logged-out accounts stay selectable and are
  marked.
- The submit includes `claudeAccountId`.

### 8.3 Desktop switch dialog

In `SwitchAgentDialog` (`frontend/src/renderer/components/SwitchAgentDialog.tsx:77`):

- An **Account** select appears when the target is Claude Code.
- It preselects the session's account when the source is another agent, and the
  first other account when the source is Claude.
- The default target (`:87`) becomes Claude on another account when the session
  is on Claude and another account exists, else Codex.
- `canSwitchAgentHarness` and the same-agent guard (`:205`) allow Claude→Claude
  when the account differs.

### 8.4 Desktop session labels

Where the agent name renders (`SessionAgentTabMenu.tsx:29`, the switch dialog
description), a non-default account appends its label: **Claude Code · Personal**.

### 8.5 Mobile spawn

Under `packages/mobile/lib/feature/spawn/`:

- **Data:** `data/data_source/claude_accounts_remote_data_source.dart`
  (`GET /claude-accounts`), `data/model/claude_account_model.dart` (hand-written,
  nullable fields), and `EndPoints.claudeAccounts`.
- **Params:** `SpawnSessionParams` adds `claudeAccountId`, included in `toJson`
  only when set.
- **Cubit:** `SpawnCubit` loads accounts with the catalog, holds
  `claudeAccountId`, and resets it to `default` in `setHarness`.
- **Screen:** `SpawnBody` renders an **Account** row under Agent only when the
  harness is `claude-code`. It opens a picker sheet modelled on
  `core/widgets/pickers/agent_picker_sheet.dart`, with label, plan and a check.

Mobile does not manage accounts or switch a session's account.

## 9. Errors

| Code | When |
|---|---|
| `CLAUDE_ACCOUNT_EXISTS` | label or folder already registered |
| `CLAUDE_ACCOUNT_LABEL_INVALID` | empty, too long, or empty slug |
| `CLAUDE_ACCOUNT_NOT_FOUND` | unknown id |
| `CLAUDE_ACCOUNT_DEFAULT_IMMUTABLE` | removing the default |
| `CLAUDE_ACCOUNT_IN_USE` | removing an account a session references |
| `CLAUDE_ACCOUNT_FOLDER_UNAVAILABLE` | folder cannot be created, or is missing at launch |
| `INVALID_CLAUDE_ACCOUNT` | unknown id on spawn/switch, or sent with a non-Claude harness |

## 10. Testing

**Backend** (`go test ./...`, `npm run lint`):

- **Migration:** the CHECK constraint rejects a default row with a path and a
  non-default row without one; exactly one default; the FK blocks deleting an
  in-use account.
- **Accounts service:**
  - slug derivation;
  - create makes the `0700` folder;
  - adopt keeps an existing folder;
  - duplicate label and folder errors;
  - label rename leaves `config_dir` byte-identical;
  - status parse of `claude auth status` JSON, including a timeout giving
    `loggedIn: null`.
- **`claudesetup.Ensure`:** every row of the §7 state table in a temp home; MCP
  sync replaces only `mcpServers` and preserves `oauthAccount`; re-link writes
  `.bak-<unix>`.
- **Launch env:** a table over every §5.1 call site asserts `CLAUDE_CONFIG_DIR` is
  absent for the default (even when project env sets it) and exact for others.
- **Adapter:**
  - `claudeGlobalConfigPath` with and without the variable;
  - `PreLaunch` writes trust into the account's `.claude.json`;
  - `IsSessionIDClaimed` finds a transcript in a non-default folder.
- **Transcripts and usage:** a session's transcript resolves from its own folder;
  a transcript placed in another account's folder is rejected; `AddRoot`
  registers a new folder.
- **Switching:**
  - A→B starts fresh;
  - B→A resumes;
  - same harness and account is rejected;
  - the column changes only on success;
  - a restart after success restores on B.
- **HTTP:** the new routes and error codes; `claudeAccountId` on spawn,
  orchestrator and switch; worker inherits its orchestrator's account;
  `go test ./internal/httpd/...` spec parity after `npm run api`.

**Desktop** (`npm run frontend:typecheck`, `npm run frontend:lint`, unit tests):

- the accounts section rows, add dialog path preview, and replaced-setup warning;
- the Account chip renders only for Claude and resets on agent change;
- the switch dialog allows Claude→Claude only across accounts.

**Mobile** (`flutter analyze`, `flutter test`):

- model parse;
- `SpawnSessionParams.toJson` with and without the account;
- `SpawnCubit` resets the account in `setHarness`;
- the Account row is hidden for non-Claude harnesses.

**Real app** (`npm run tauri:dev`, manual, recorded in the PR):

1. Add `Personal` → login terminal runs `claude auth login` → the row shows the plan.
2. Spawn on Personal → confirm with `/status` in the session.
3. Switch the session to Default and back → it resumes.
4. Restart the daemon → the session restores on its account.
5. Confirm `CLAUDE.md` rules and a skill are visible to the Personal session.

## 11. Out of scope

- Moving or renaming an account folder (fact 2).
- Copying conversations between accounts (§6).
- Account management and account switching on mobile.
- Automatic "continue on another account" when a usage limit is hit.
- Accounts for agents other than Claude Code.
- Two-way MCP sync.

## 13. Amendments from planning (2026-09-14)

These supersede the sections they name.

1. **Default account env (§5.1).** The default account removes
   `CLAUDE_CONFIG_DIR` from the launch env and never sets it to `""`. An empty
   value makes Claude's projects directory the relative path `projects` (P7).
   The daemon unsets an inherited `CLAUDE_CONFIG_DIR` at boot and logs a
   warning.
2. **No foreign key (§3.2, §4.1 DELETE).** SQLite's `ALTER TABLE ADD COLUMN`
   rules mean a column with a `REFERENCES` clause can't be added with a non-NULL
   default. So `sessions.claude_account_id` is `TEXT NOT NULL DEFAULT 'default'`
   without a foreign key. `DeleteClaudeAccount` counts referencing sessions
   inside the same write transaction and refuses with
   `CLAUDE_ACCOUNT_IN_USE`.
3. **Switch columns (§3.3).** `from_claude_account_id` and
   `target_claude_account_id` are `TEXT NOT NULL DEFAULT ''`, appended at the
   end of the table; `''` means "not recorded". A switch to a non-Claude target
   records the session's current account as the target account, so the column
   is stable across the switch.
4. **Session label (§3.2, §8.4).** The session read model carries
   `claudeAccountId` only (via `SessionRecord`). Clients resolve the label from
   `GET /claude-accounts`.
5. **Account id.** `claude_accounts.id` is the slug fixed at creation.
   Renaming the label changes neither the id nor the folder.
6. **Login terminal (§4.1).** The login route opens a shell-terminal record
   whose argv is the resolved `claude` binary itself, not an interactive shell.
   The pane ends when Claude exits.
7. **Mobile data (§8.5).** Accounts are read through the existing
   `SpawnRemoteDataSource` / `SpawnRepository`, not a new data source, so DI and
   the network guard stay unchanged.
8. **Read-only listing (§4.1, §7).** `GET /claude-accounts` never creates links.
   `sharedSetup` comes from a read-only `claudesetup.Inspect`. Links are created
   or repaired on create, login, relink and launch.
9. **Usage path check (§5.4).** `validateSourcePath` only has the harness in
   scope (`collector.go:1555`), so the containment check accepts a transcript
   under **any registered account's** `projects` folder, not only the session's.
   Discovery by native id still searches only the session's own account folder
   (`ClaudeProjectsFor`). Both roots are provider-owned, so the containment
   guarantee is unchanged. Only cross-account attribution depends on discovery
   rather than on the path check.

## 12. File map

**Backend**

- `backend/internal/storage/sqlite/migrations/0109_claude_accounts.sql`
- `backend/internal/storage/sqlite/queries/*` + `npm run sqlc`
- `backend/internal/domain/` — `ClaudeAccount`, `SessionRecord.ClaudeAccountID`
- `backend/internal/service/claudeaccounts/` — registry, status probe, create/adopt
- `backend/internal/adapters/agent/claudecode/` — `claudeGlobalConfigPath`, trust lock, claim check, `claudesetup`
- `backend/internal/session_manager/manager.go`, `agent_switching.go`
- `backend/internal/observe/transcript/resolve.go`
- `backend/internal/service/usage/collector.go`, `backend/internal/daemon/daemon.go`
- `backend/internal/service/shellterm/types.go`, `service.go`
- `backend/internal/httpd/controllers/` — `claude_accounts.go`, `dto.go`, `sessions.go`
- `backend/internal/httpd/apispec/` + `npm run api`

**Desktop**

- `frontend/src/renderer/components/settings/ClaudeAccountsSection.tsx` (+ add dialog)
- `frontend/src/renderer/components/GlobalSettingsForm.tsx`
- `frontend/src/renderer/components/TaskComposer.tsx`
- `frontend/src/renderer/components/SwitchAgentDialog.tsx`, `SessionAgentTabMenu.tsx`
- `frontend/src/renderer/hooks/useClaudeAccounts.ts`
- `frontend/src/api/schema.ts` (generated)

**Mobile**

- `packages/mobile/lib/feature/spawn/data/data_source/claude_accounts_remote_data_source.dart`
- `packages/mobile/lib/feature/spawn/data/model/claude_account_model.dart`
- `packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart`
- `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`
- `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
