# Mobile slash commands — design

**Date:** 2026-09-17
**Status:** approved in conversation, awaiting implementation
**Scope:** `backend/internal` (send path, one new service, one new route),
`packages/mobile` (composer menu). No desktop renderer changes.

## 1. Problem

Typing `/compact` into the phone composer and sending it reaches the agent
and runs, but the phone reports `Send failed: The agent did not accept the
message; the terminal is not responding to input`, keeps the text in the
field, and never shows the message in the conversation. Observed on
2026-09-17 against daemon 0.14.4 with Claude Code 2.1.267.

Cause. `POST /sessions/{id}/send` pastes the text and then runs
`confirmActive` (`backend/internal/session_manager/manager.go:2376-2380`),
which re-sends Enter until the session reports `active` or the attempt
budget is spent, then returns `ErrAgentNotResponding`
(`manager.go:2504-2513`). "Active" is learned from Claude Code's
`UserPromptSubmit` hook. A built-in slash command such as `/compact` is
handled by the TUI itself and never fires that hook, so the loop always
times out, and no `prompt_submit` block event exists for the phone to render
as a bubble. The Session-actions "Compact" button does not suffer from this
because it uses `POST /sessions/{id}/command`, whose `commandTyped` writes
`/compact\r` and returns without waiting (`command.go:63-76`).

The mobile composer has no notion of slash commands: it is a bare
`TextField` bound to `TerminalCubit.composer`
(`packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart:156-180`).

## 2. Goals

- Sending a built-in slash command from the phone succeeds, clears the
  field, and appears in the conversation as the user's bubble — on the phone
  and in every other client reading the block stream.
- Typing `/` in the composer opens a menu of the commands available to that
  session, filtered as the user keeps typing; tapping a row fills the
  composer with `/name ` so arguments can follow, or sends immediately when
  the command takes none.
- The menu lists Claude Code's built-in commands **and** the user's own
  commands and skills: `~/.claude/commands/**/*.md`,
  `~/.claude/skills/*/SKILL.md`, the project's `.claude/commands` and
  `.claude/skills`, and installed plugin skills. It respects the session's
  Claude account (its `CLAUDE_CONFIG_DIR`).
- The list is computed on the daemon, not the phone: the phone has no
  filesystem access to the Mac and the daemon already resolves the account's
  config directory for transcripts
  (`backend/internal/observe/transcript/resolve.go:42-62`).

## 3. Non-goals

- Commands for harnesses other than `claude-code`. Codex/grok/copilot
  sessions get an empty list and no menu. The send-path rules in §4.2 key on
  the message alone, so they apply to every harness: an interactive built-in
  name is refused everywhere (the same names open pickers in codex), and the
  confirmation skip is a no-op for harnesses that never confirmed.
- Argument completion (e.g. `/model <name>`), argument hints, or
  descriptions beyond one line.
- Executing interactive built-ins from the phone. Commands that open a TUI
  dialog (`/config`, `/permissions`, `/hooks`, `/mcp`, `/agents`, `/login`,
  `/logout`, `/vim`, `/ide`, `/terminal-setup`, `/resume`, `/rewind`,
  `/memory`, `/statusline`, `/add-dir`, `/exit`, `/bug`) park the desktop
  terminal in a menu the phone cannot drive — the same reason `commandModel`
  drives `/model` to completion in one call (`command.go:78-90`). They are
  served with `interactive: true` and hidden by the phone. `/model` stays
  reachable through the existing Session-actions picker.
- Watching the filesystem for changes. The list is fetched when the session
  screen opens; a pull-to-refresh is not needed for this milestone.
- Desktop renderer changes. The desktop types into the PTY directly and
  already has Claude Code's own menu.

## 4. Daemon

### 4.1 `slashcommands` package — the built-in catalogue

New package `backend/internal/slashcommands` owns one shared fact: which
messages are built-in Claude Code slash commands. Both the send path and the
listing route import it, so the two can never disagree.

```go
package slashcommands

type Command struct {
    Name        string `json:"name"`        // without the leading slash, e.g. "compact", "sc:analyze"
    Description string `json:"description"`
    Source      string `json:"source"`      // "builtin" | "user" | "project" | "plugin"
    Interactive bool   `json:"interactive"` // opens a TUI dialog; phone hides it
}

// Builtin is Claude Code's own command set (2.1.x). Descriptions are the
// TUI's one-liners. Interactive marks commands that open a dialog.
var Builtin = []Command{...}

// Lookup returns the built-in the message invokes: the first
// whitespace-delimited token, minus its leading '/', matches a Builtin name
// exactly (case-sensitive). "/compact" and "/compact focus on tests" resolve;
// "/sc:analyze" and "hello /compact" do not.
func Lookup(message string) (Command, bool)

// IsBuiltin is Lookup's boolean form.
func IsBuiltin(message string) bool
```

The built-in table, with `interactive` as decided in §3:

| name | description | interactive |
|---|---|---|
| clear | Clear conversation history and free up context | no |
| compact | Clear conversation history but keep a summary in context | no |
| context | Show current context usage as a colored grid | no |
| cost | Show the total cost and duration of the current session | no |
| doctor | Diagnose and verify your Claude Code installation and settings | no |
| export | Export the current conversation to a file or clipboard | yes |
| help | Show help and available commands | no |
| init | Initialize a new CLAUDE.md file with codebase documentation | no |
| pr-comments | Get comments from a GitHub pull request | no |
| release-notes | View release notes | no |
| review | Review a pull request | no |
| security-review | Complete a security review of the pending changes on the current branch | no |
| status | Show Claude Code status including version, model, account, API connectivity, and tool statuses | no |
| usage | Show plan usage limits | no |
| add-dir | Add a new working directory | yes |
| agents | Manage agent configurations | yes |
| bug | Submit feedback about Claude Code | yes |
| config | Open config panel | yes |
| exit | Exit the REPL | yes |
| hooks | Manage hook configurations for tool events | yes |
| ide | Manage IDE integrations and show status | yes |
| login | Sign in with your Anthropic account | yes |
| logout | Sign out from your Anthropic account | yes |
| mcp | Manage MCP servers | yes |
| memory | Edit Claude memory files | yes |
| model | Set the AI model for Claude Code | yes |
| permissions | Manage allow & deny tool permission rules | yes |
| resume | Resume a conversation | yes |
| rewind | Restore the code and/or conversation to a previous point | yes |
| statusline | Set up Claude Code's status line UI | yes |
| terminal-setup | Install Shift+Enter key binding for newlines | yes |
| vim | Toggle between Vim and Normal editing modes | yes |

The descriptions are transcribed from the Claude Code 2.1 `/help` output as
best known on 2026-09-17; exact wording is not load-bearing and the table is
plain data, so a wrong line is a one-line fix. Verified on 2026-09-17
against Claude Code 2.1.273: `/doctor` runs an ordinary agentic turn that
ends in an `AskUserQuestion` the phone already answers, so it stays
non-interactive; `/export` opens an export-method picker (clipboard or
file), so it is interactive.

### 4.2 Send path: a built-in slash command is delivered, not confirmed

In `Manager.send` (`manager.go:2326-2381`), three changes, all keyed on
`slashcommands.Lookup(message)`:

1. **Interactive built-ins are refused before anything is written.** A
   built-in with `Interactive: true` (`/model`, `/config`, `/resume`, …)
   would park the desktop TUI in a dialog the phone cannot drive, which is
   exactly what `commandModel` exists to avoid (`command.go:78-90`). The
   phone hides them, but a typed `/model` must not get through either, so
   `send` returns a new `ErrInteractiveSlashCommand` before
   `DeliverWithPostWrite`, and `service/session/service.go:875` maps it to
   `409 SLASH_COMMAND_INTERACTIVE` ("This command opens a dialog on the
   desktop; run it there"). `/model` stays reachable through
   `POST /sessions/{id}/command`.
2. **The latest-user-prompt fact is not recorded.** The `afterWrite`
   callback at `manager.go:2332-2341` persists the message as the session's
   `LatestUserPrompt`, which feeds the handoff artifact
   (`handoff_artifact.go`), agent switching and the CLI board. `/compact` is
   not task direction, so for a built-in `afterWrite` stays nil.
3. **Confirmation is skipped.** After the `switch outcome` block and before
   the `harnessNudgeSafe` gate:

```go
if slashcommands.IsBuiltin(message) {
    return nil
}
```

Rationale for 3: the confirmation loop's only signal is the prompt-submit
hook, which built-ins never fire, so waiting can only ever end in a false
`ErrAgentNotResponding` after sending stray Enters. The paste itself is
still gated by every existing guard (terminated, exited, awaiting a
decision, switch in progress) because those run inside
`DeliverWithPostWrite` before this point.

Custom commands and skills (`/sc:analyze`, `/paseo`) are expanded into a
prompt by Claude Code, and that expansion **does** fire `UserPromptSubmit`
(verified 2026-09-17: `/sc:help` returned 200 in 0.66 s and the hook itself
recorded the `prompt_submit` block). They keep today's confirmed path and
need no synthetic block.

### 4.3 The bubble: a synthetic `prompt_submit` block

The `send` handler (`backend/internal/httpd/controllers/sessions.go:1332-1366`)
already holds `c.BlockEvents` (the same recorder the hook route uses at
`sessions.go:1643`). After `c.Svc.Send` succeeds and `slashcommands.IsBuiltin(message)`
is true, it records:

```go
sig := ports.ActivitySignal{
    Event:            "user-prompt-submit",
    Harness:          string(sess.Harness),
    LatestUserPrompt: message,
}
c.BlockEvents.Record(r.Context(), sessionID(r), string(sess.Harness), sig)
```

where `sess` comes from `c.Svc.Get`. `blockdispatch.Map("claude-code",
"user-prompt-submit")` yields `prompt_submit`
(`backend/internal/adapters/agent/blockdispatch/dispatch.go:50`), the phone's
assembler turns that into a user bubble
(`packages/mobile/lib/feature/blocks/logic/block_assembly.dart`, case
`prompt_submit`), and the desktop's block timeline sees the same record. A
recording failure is logged and does not fail the send, matching the hook
route. The block is recorded only for `claude-code` sessions; other
harnesses are out of scope (§3).

This does not double-record: the hook never fires for built-ins (§1), which
is the whole reason the synthetic record exists.

### 4.4 `GET /api/v1/sessions/{sessionId}/slash-commands`

**Response** `200`:

```json
{
  "commands": [
    {"name": "compact", "description": "Clear conversation history but keep a summary in context", "source": "builtin", "interactive": false},
    {"name": "sc:analyze", "description": "Comprehensive code analysis across quality, security, performance, and architecture domains", "source": "user", "interactive": false},
    {"name": "bug-triage", "description": "Triage bugs reported in chat/issues, …", "source": "project", "interactive": false},
    {"name": "superpowers:brainstorming", "description": "You MUST use this before any creative work …", "source": "plugin", "interactive": false}
  ]
}
```

Errors use the locked envelope. `404 SESSION_NOT_FOUND` for an unknown
session. A session whose harness is not `claude-code` returns `{"commands":
[]}` with `200`. Filesystem errors while scanning a folder (missing,
unreadable) skip that folder silently — a user without `~/.claude/commands`
is the normal case, not an error.

**Discovery service.** New `backend/internal/service/slashcommands`
(service package; the catalogue package in §4.1 is a leaf it imports):

```go
type Service struct {
    sessions SessionGetter          // GetSession(ctx, id) (domain.SessionRecord, bool, error) — the store
    agents   ports.AgentResolver    // to reach ports.AgentNativeSessionConfigProvider
    accounts ClaudeAccountEnv       // EnvFor(ctx, ClaudeAccountID) — same interface as transcript.ClaudeAccountEnv
}

func New(sessions SessionGetter, agents ports.AgentResolver, accounts ClaudeAccountEnv) *Service
func (s *Service) List(ctx context.Context, id domain.SessionID) ([]slashcommands.Command, error)
```

`List` resolves the config dir exactly as `transcript.Resolver.Path` does
(`resolve.go:46-62`): `agents.Agent(rec.Harness)` →
`AgentNativeSessionConfigProvider.NativeSessionConfigDir(ctx, accounts.EnvFor(rec.ClaudeAccountID))`.
It then scans, in this order, appending in place:

1. `slashcommands.Builtin` verbatim (`source: builtin`).
2. `<configDir>/commands/**/*.md` → `source: user`. Name is the path
   relative to `commands/` without `.md`, with `/` replaced by `:` — so
   `~/.claude/commands/sc/analyze.md` is `sc:analyze`, which is how the
   Claude Code CLI lists it (this session's own skill listing shows
   `sc:analyze`). Files named `README.md` are skipped.
3. `<configDir>/skills/*/SKILL.md` → `source: user`, name is the folder.
4. `<workspace>/.claude/commands/**/*.md` and `<workspace>/.claude/skills/*/SKILL.md`
   → `source: project`, same naming; `workspace` is
   `rec.Metadata.WorkspacePath` (`backend/internal/domain/session.go:29`),
   skipped when empty.
5. Plugins: read `<configDir>/plugins/installed_plugins.json`, shape
   `{"version": 2, "plugins": {"<plugin>@<marketplace>": [{"scope": "user"|"local"|"project", "projectPath": "...", "installPath": "...", ...}]}}`
   (observed at `~/.claude/plugins/installed_plugins.json` on 2026-09-17;
   `projectPath` is present only for non-`user` scopes). An install is
   taken only when **both** hold:
   - its `scope` is `user`, or its `projectPath` equals the session's
     workspace path (`rec.Metadata.WorkspacePath`, compared after
     `filepath.Clean`);
   - `<configDir>/settings.json` has `"enabledPlugins": {"<key>": true}`
     for the full `<plugin>@<marketplace>` key (observed shape on
     2026-09-17: a map of key → bool). A missing or unreadable
     `settings.json`, or a missing key, means disabled.

   Evidence this filter is load-bearing: the machine holds
   `frontend-design@claude-plugins-official` with `scope: local` for an
   unrelated project and without an `enabledPlugins` entry, and this very
   session's skill listing does not show it. Whether project-level
   `.claude/settings.json` / `settings.local.json` can also enable a plugin
   is **not known**; only the config-dir settings file is consulted.

   For every taken install, scan `<installPath>/skills/*/SKILL.md` and
   `<installPath>/commands/**/*.md` → `source: plugin`, name
   `<plugin>:<skill>` where `<plugin>` is the key up to `@`.

Description for a Markdown file is the `description:` value of its YAML
front matter (`gopkg.in/yaml.v3` is already a dependency, `go.mod:25`), or
`""` when absent. Front matter is the block between a leading `---` line and
the next `---` line; a file without it has an empty description.

Duplicates by name keep the first occurrence (built-in > user > project >
plugin). The result is sorted: built-ins first in table order, then the
rest alphabetically by name. Every scan is bounded to the directories named
above. Symlinks are resolved explicitly (`filepath.EvalSymlinks` on each
directory, `os.Stat` on entries, a visited set against cycles): an adopted
Claude account links `commands/` to `~/.claude/commands` and individual
skill folders elsewhere, and `filepath.WalkDir` on its own treats a
symlinked root as a file and skips symlinked folders. A walk that errors
stops that one source, not the request.

**Wiring.** `SessionsController` gains `SlashCommands SlashCommandLister`
(`List(ctx, id) ([]slashcommands.Command, error)`), nil-guarded with
`apispec.NotImplemented` like the other optional deps; `daemon.go` builds
`slashcommandssvc.New(store, agents, claudeAccounts)` next to
`transcriptsvc.NewResolver(agents, claudeAccounts)` (`daemon.go:483`).

The route changes `openapi.yaml`, and CI fails on drift of the generated
desktop client (`.github/workflows/go.yml:96` diffs
`frontend/src/api/schema.ts`), so `npm run api:ts` in `frontend/` is part
of the same change.

## 5. Mobile

### 5.1 Data

`packages/mobile/lib/feature/terminal/data/`:

- `model/slash_command_model.dart` — `SlashCommandModel{String? name, String?
  description, String? source, bool? interactive}`, hand-written `fromJson`,
  fields nullable per convention, plus `static List<SlashCommandModel>
  listFromJson(dynamic)`.
- `EndPoints.sessionSlashCommands(String sessionId)` →
  `'${_session(sessionId)}/slash-commands'`.
- `TerminalRemoteDataSource.getSlashCommands(String sessionId)` →
  `GlobalResponse<List<SlashCommandModel>>` parsed with `withDataKey: false`
  and `fromJsonT: SlashCommandModel.listFromJson` (the payload is
  `{commands: [...]}`, so `listFromJson` reads `json['commands']`).
- `TerminalRepository.getSlashCommands(String sessionId)` →
  `FutureResult<GlobalResponse<List<SlashCommandModel>>>`, network-gated like
  the other methods.

### 5.2 `SlashMenuCubit`

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart`
(+ `slash_menu_state.dart` as a `part`). Registered with
`registerFactoryParam<SlashMenuCubit, TextEditingController, String>` and
provided in the terminal route's `MultiBlocProvider` for non-shell sessions
with `param1: terminalCubit.composer` — read from the already-created
`TerminalCubit` via `context.read` inside the `create` callback (the
providers list is ordered, `TerminalCubit` is first) — and `param2:
terminalArgs.sessionId`. It is the only widget-state owner for the menu:

```dart
class SlashMenuCubit extends Cubit<SlashMenuState> {
  SlashMenuCubit(this._repository, this.composer, {required this.sessionId})
      : super(const SlashMenuInitialState()) {
    composer.addListener(_onComposerChanged);
  }

  List<SlashCommandModel> commands = const [];   // full list from the daemon, interactive ones dropped
  List<SlashCommandModel> matches = const [];    // what the menu shows now
  String query = '';                              // text after the '/', lower-cased

  Future<void> getSlashCommands();   // emits GetSlashCommandsLoadingState / SuccessState / FailureState
  void _onComposerChanged();          // recomputes `matches`; emits SlashMenuChangedState(open, matches)
  void pick(SlashCommandModel command); // rewrites composer text to '/name ' and moves the cursor to the end
}
```

The menu is **open** when the composer text starts with `/`, contains no
whitespace yet, and at least one command matches; `query` is the text after
`/`. Matching is a case-insensitive prefix match on `name`, falling back to
"contains" when no prefix match exists (so `/analyze` still finds
`sc:analyze`). Interactive commands are dropped when the list is loaded, not
at match time. A failed fetch leaves `commands` empty and the menu simply
never opens; the failure is not surfaced (the composer must keep working
without the daemon route, e.g. against an older daemon).

The constructor starts the fetch, like every other cubit in the package
(`BlocksCubit`, `SessionCommandCubit`, `SessionsCubit`). Tests accept that
`bloc_test` subscribes after construction and so never sees the synchronous
loading state; they assert the success/failure state and the cubit's fields.

`pick` fills rather than sends: it sets `composer.text = '/${command.name} '`
with the selection at the end, which closes the menu (there is now
whitespace) and lets the user add arguments or hit Send. This is the TUI's
own behaviour for Tab/Enter on a menu row. The state file follows the
existing sealed-class shape (`terminal_cubit.dart` / `manual_connect_state.dart`).

### 5.3 UI

`packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart`
— a `StatelessWidget` rendered by `TerminalComposer` directly above the input
row (inside the existing `Column`, before the `BlocBuilder<TerminalCubit>`
that builds the field), wrapped in `BlocBuilder<SlashMenuCubit,
SlashMenuState>` with `buildWhen` on `SlashMenuChangedState`. When closed it
is `SizedBox.shrink()`. When open it is a rounded `AppContainer`-style panel
(`skin.bgElevated`, `skin.borderDefault`, radius 11 — the composer's own
tokens, `terminal_composer.dart:145-148`) holding at most 6 rows in a
`ListView` with `shrinkWrap: true`; each row is `SlashCommandRow(name,
description, source)` — a leaf taking primitives — showing `/name` in
`AppTextStyle.mono12Regular` and the description in `style11Regular` with
`skin.textTertiary`, one line, ellipsised, and a small source tag (`user`,
`project`, `plugin`; nothing for built-ins) in `style10Regular`. Tapping a
row calls `context.read<SlashMenuCubit>().pick(command)` and gives
`Haptics.selection()` if that helper exists (`core/utils/haptics.dart`),
else no haptic.

The panel does not steal focus: rows are `AppInkWell`/`InkWell` targets, not
focusable widgets, so the keyboard stays up.

### 5.4 Sending

No change to `TerminalCubit.send`. With §4.2 in place the daemon returns
`200`, the field clears, and the bubble arrives through the block stream
like any other prompt. The existing `Send failed:` banner stays as the
error path for genuine refusals.

## 6. Testing

Daemon:

- `slashcommands` package: table-driven `Lookup`/`IsBuiltin` test (`/compact`,
  `/compact args`, `  /compact`, `/sc:analyze`, `hello /compact`, `/`, `/Compact`).
- `session_manager`: `TestSend_BuiltinSlashCommandSkipsConfirm` — a
  signaling harness that never goes active, message `/compact`, expects
  `nil`, exactly one messenger write (no nudges), and the store's
  `LatestUserPrompt` untouched. Mirrors `TestSend_ConfirmBudgetCapsRetries`
  (`manager_test.go:6341`). `TestSend_InteractiveBuiltinIsRefused` — `/model`
  returns `ErrInteractiveSlashCommand` with zero messenger writes.
- controllers: `TestSendBuiltinSlashCommandRecordsPromptBlock` — fake
  recorder captures one `user-prompt-submit` signal with
  `LatestUserPrompt: "/compact"`; `TestSendPlainMessageRecordsNothing`.
- `service/slashcommands`: builds a temp config dir with `commands/sc/analyze.md`
  (front matter), `skills/paseo/SKILL.md`, a project `.claude/skills/x/SKILL.md`,
  `settings.json` with `enabledPlugins`, and `plugins/installed_plugins.json`
  with three installs: one enabled `user`-scope plugin, one installed but not
  enabled, and one `local`-scope plugin whose `projectPath` is another
  folder; asserts names, sources, descriptions, order, that only the first
  plugin's skills appear, and that a non-claude harness yields an empty list.
- controllers: `TestListSlashCommands` golden JSON; `404` on unknown session.

Mobile:

- `slash_command_model_test.dart` — `listFromJson` on the golden payload.
- `slash_menu_cubit_test.dart` (bloc_test, mocktail repository): opens on
  `/`, filters by prefix, falls back to contains, closes on whitespace,
  drops interactive, `pick` rewrites the composer and closes the menu, fetch
  failure keeps the menu closed.
- `slash_command_menu_test.dart` widget test: renders rows for matches and
  nothing when closed; tapping a row fills the composer.

## 7. Verification on real devices

After the daemon is rebuilt (`npm run tauri:dev` with the scrubbed env, or a
release), on the phone:

1. Type `/` — the menu lists `compact`, `clear`, … and the user's own
   `sc:*` commands and skills; type `co` — only `compact`, `context`, `cost`.
2. Tap `compact`, Send — the field clears, a `/compact` bubble appears, then
   the `CONVERSATION COMPACTED (MANUAL)` divider; no red banner.
3. Type `/model` by hand and Send — the phone shows the
   `SLASH_COMMAND_INTERACTIVE` refusal and the desktop TUI stays on its
   prompt.
4. Send `/sc:analyze` (or any user command) — if the phone shows
   `AGENT_NOT_RESPONDING`, apply the widening described in §4.2.
5. Send `/doctor` and `/export` — confirm neither parks the desktop TUI in a
   dialog; if one does, flip its `interactive` flag.
