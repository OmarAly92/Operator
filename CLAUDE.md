# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read and follow [`AGENTS.md`](AGENTS.md) for repository layout, commands, coding conventions, and hard rules.

**Terminal work: read [`TERMINAL.md`](TERMINAL.md) first.** Before touching
`packages/terminal`, the pty-host (`backend/internal/adapters/runtime/ptyhost`),
`BlockTerminal`/`TerminalPane`/`useTerminalSession`, or any resize, attach,
replay, selection or copy code, read `TERMINAL.md` end to end. It records the
terminal pipeline, the bugs already solved and the tests that guard them, the
exact verify-and-ship recipe (both wasm builds, daemon rebuild, the Playwright
selection gate), and what is upstream and must not be chased again. The
reference for every rendering decision is Warp's source at
`/Users/omaraly/development/AI/warp`; match it and cite the file.

Two facts that are easy to get wrong from the code alone:

- **The transcript selection is the renderer's, not the browser's.**
  `DomBlockRenderer` owns it as grid points (`selection-model.ts`), paints it from
  geometry and copies it from the snapshot; `.terminal-block` is `user-select:
  none`. Never reach for `document.getSelection()` in terminal code.
- **The desktop shell is Tauri.** `npm run tauri:dev` from the repo root starts
  the app and supervises the daemon, and rebuilds `packages/terminal` on start.
  `RUN_APP_COMMANDS.md` is the truth.

**Branches: work on `development`, release from `master`.** `development` is the
default branch and holds unreleased changes. `master` is released code only: a
release is `development` merged into `master` plus a version bump on `master`,
which `.github/workflows/release-on-bump.yml` turns into a tagged desktop release.
Never commit ordinary work to `master`; never bump the version on `development`.
The commands are in `RUN_APP_COMMANDS.md` under "Push an update to installed apps".

**`AGENTS.md` covers `backend/` and `frontend/` only.** The third deliverable, the Flutter
mobile client at `packages/mobile`, is documented below.

## Release signing key is backed up — never regenerate it

The Tauri updater keypair lives at `~/.tauri/operator-updater.key`, `.key.pub` and
`.password` on the user's machine and is backed up in their password manager
(*Operator — Tauri updater signing key*, saved 2026-09-17). GitHub holds it as the
secrets `TAURI_SIGNING_PRIVATE_KEY` / `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` and the
repo variable `OPERATOR_UPDATER_PUBLIC_KEY`. Do not run `tauri signer generate` again
or overwrite those: the public key is compiled into every shipped build and a new
key would permanently break auto-update for every installed app. If a release needs
the key, point the user at the backup.

## Nested worktrees poison repo-wide search

Some git worktrees live *inside* this checkout (`.worktrees/`, `.claude/worktrees/`),
alongside external siblings (`../Operator-*`). A repo-wide `grep` or `find` from the
root matches stale duplicate copies of tracked files, including old `AGENTS.md`
versions. Scope searches to the real source directories, or exclude those two paths.

## Design System

Always read [`DESIGN.md`](DESIGN.md) before making any visual or UI decision —
**start with the "clone agent-orchestrator verbatim" banner at the top**, which
governs the current look.

> **Name collision warning:** the design reference below is a *separate* app of
> the user's, named `agent-orchestrator`. This product was also once called
> Agent Orchestrator before it was renamed to Operator. They are different
> codebases — do not treat the reference path as pointing at this repository.

The renderer **clones the agent-orchestrator web app verbatim**
(`~/Projects/agent-orchestrator/packages/web/src`) in looks and design, with a
refined-blue accent and the terminal keeping its own palette. This **supersedes the
older design-reference framing** in DESIGN.md (per explicit user decision 2026-06-10).
Build new UI from shadcn primitives (`components/ui/*`) where a component fits. Do not
deviate without explicit user approval. In QA/review, flag any renderer code that
diverges from **agent-orchestrator** — do **not** re-flag old design-reference mismatches.

## Mobile client (`packages/mobile`)

A Flutter thin client for the daemon, pubspec name `operator_mobile`. It runs no
agents — it talks to a paired daemon over REST, one multiplexed WebSocket, and SSE
for the daemon's event stream (blocks, terminal). It replaced an Expo/React Native
app that was deleted at milestone M6;
`docs/mobile-parity-ledger.md` records where each of that app's 99 source files went
and is the answer to "was this ever ported?".

### Commands

All from `packages/mobile`. CI (`.github/workflows/mobile-flutter.yml`) pins Flutter
**3.44.5** and runs exactly the first two:

```bash
flutter analyze                                   # must be "No issues found!"
flutter test                                      # full suite
flutter test test/path/to/file_test.dart          # one file
flutter test --plain-name 'substring of name'     # one test or group
flutter pub get                                   # after any pubspec/workspace change
```

`flutter analyze` and `flutter test` are the gate for every change. Native code is
**not** covered by either — if you touch `ios/`, `android/`, or a vendored package's
platform code, the only real check is a build:

```bash
flutter build apk --release
flutter build ios --release --no-codesign
```

### Architecture

`lib/core/` holds what every feature needs; `lib/feature/<feature>/` is split
`data/` (data sources, models, `model/params/`, repositories), `logic/` (pure
functions), `presentation/<screen>_screen/{logic,ui}` (cubit + widgets).
Twelve features: `pairing`, `onboarding`, `sessions`, `pull_request`,
`spawn`, `terminal`, `preview`, `notification`, `settings`,
`blocks`, `dictation`, `usage`. There is no `chat` feature — every session runs
the agent's own terminal UI; the ACP/chat subsystem was removed in Phase 4.

**`ServerConfig` is the spine.** The API base URL does not exist until pairing
completes, so no data source ever sees host/port/password. `ServerConfigStore` holds
the current config and `ServerConfigInterceptor` stamps `baseUrl` and the
`Authorization: Bearer` header onto every request; a request may pass a
`pairingTarget` in Dio's `extra` to aim at a server that is not saved yet, which is
how pairing verifies before persisting. Saved desktops live in the drift `desktops`
table; each one's password lives in `flutter_secure_storage` keyed by desktop id;
`ServerConfigStore` holds only the active one in memory, loaded at launch.
`ServerConfig.desktopId` names the active desktop; every replica read and write is
scoped by it, so a desktop never shows another desktop's data.

**Start flow and connection state.** Opening the app paints the last known board, first
notifications page and chat history from drift, then replaces them with fresh data. Each
replicated repository writes the daemon's decoded JSON on every successful fetch and exposes
a `cachedX()` read that parses through the same hand-written `fromJson`; cubits read the cache
once per desktop. `ConnectionCubit` (`core/connection/`, provided at the app root) is the single
source of connection state, fed by `ConnectionReportInterceptor` and `MuxClient.status`. It backs
off 1 s to 30 s while offline, waits 60 s when rate-limited, and stops on an auth failure so a
rotated password cannot trip the daemon's lockout. `/healthz` needs no password, so its 200 never
clears an auth failure.

**Two load-bearing behaviors that look like inefficiencies.** Do not "optimize" either:

- **12-second `connectTimeout`/`receiveTimeout`** (`dio_consumer.dart`). Over Tailscale a
  sleeping host otherwise hangs for the OS TCP timeout of 75–120s, freezing Kill, send,
  and the poll loop.
- **Sequential auth probing.** `sessions_remote_data_source.dart` awaits `/sessions`
  *alone* before fanning out to projects and account labels. The daemon locks a device
  out for a minute after 5 failed auths, so a stale password under `Future.wait` burns
  4 failures per poll tick and arms the lockout before the user can re-pair. A test
  pins the call order.

**`MuxClient` lives in `core/mux/`, not under `terminal/`.** The Kanban board depends on
the same socket for session patches, so nesting it under a feature would make the
board's liveness depend on a feature it has no business knowing about. Cubits subscribe
to its broadcast streams; nothing else touches the socket.

Block events carry an optional `agentId`. `BlocksCubit` is scoped by `BlocksScope`; the
main scope also collects `SubagentSummary` per agent from the events it discards, and
`subagentsOf` joins those to Agent cards for the strip and the `/session/agent` screen.

**Response envelope.** The daemon does not use `GlobalResponse`'s `data` key —
`/projects` returns `{projects: [...]}` directly — so every parse is
`GlobalResponse.fromJson(response.data, withDataKey: false)`. Errors are a locked
envelope `{error, code, message, requestId}`; `code` is machine-readable and the UI
branches on it. Keep `requestId` — dropping it is a regression, not a simplification.

**Theming.** `AppSkin` with `const LightSkin()`/`const DarkSkin()`, reached through
`context.skin` (`SkinScope`), with `SkinCubit` persisting the choice. Type is
`AppTextStyle.style<Size><Weight>` plus a parallel `mono*` set. Sizes 8–13 dominate
deliberately: this is a dense, information-first phone UI, and rounding up to a
Material scale would visibly change the design.

**Phone alerts.** The phone gets alerts two ways: while the app is open, a live
`notifications` channel on `MuxClient` raises local notifications (skipping the
viewed session and quiet ones); while it is backgrounded or the phone is locked,
the daemon sends through ntfy (ntfy.sh) to a per-pairing topic claimed via
`POST /api/v1/phone-alerts/subscribe` and rotated with the desktop password.
Settings → Phone alerts covers install, subscribe and a test send against
`/api/v1/phone-alerts`. There is no Firebase or APNs dependency.

**Composer attachments and permission mode.** The agent composer is a two-row
glass card: the text on top, then **+**, the model chip, the mic, and one slot
for Send or Stop. **+** opens the Add context sheet (Camera, Photos, Files,
Show recent photos via `photo_manager`, and a Permission row). Attachments are
admitted against the daemon's caps (8 files, 10 MiB each, 25 MiB total, no
SVG), staged with `POST /sessions/{id}/attachments`, and named in the message
in the daemon's own reference format (`attachment_references.dart` mirrors
`appendAttachmentReferences`). A failed stage or send keeps the text and the
attachments; a send with attachments never reroutes to the terminal on
`SESSION_AWAITING_DECISION` the way a plain send does — it keeps the draft and
shows "Agent is waiting on a prompt — answer it, then send again." — and a
retry reuses already staged paths. The Permission row shows only when the
session DTO's `capabilities.permissionMode` is true; the live mode comes from
`permission_mode` block events, and a change goes through the
`permission-mode` session command, which answers `restarted: true` when it had
to relaunch the agent with `--resume`. `PermissionModeCubit` holds an
observed or chosen mode until a session DTO agrees, a newer block event
arrives, or the mux reconnects. Phone spawns default to `bypass-permissions`.

### Conventions specific to this package

- **Cubit only** — never `Bloc` with events. Static-only classes are `sealed class X`.
- **No `freezed` or `json_serializable`** in first-party code. Models are hand-written
  with all fields nullable and `fromJson` doing the wire→domain mapping. One params
  class per method under `data/model/params/`, never shared.
- **drift is the single local store**, under `lib/core/database/`: saved desktops, settings
  (read through `AppPreferences`, loaded once at launch so reads stay synchronous), and the
  replica (`replica_documents` for whole-resource snapshots, `replica_block_events` for chat
  history capped at 200 per session). Layout follows `flutter-knowledge:drift-local-database`:
  tables and DAOs in `core/database/tables/<table>/`, local data sources in the feature, no drift
  import above the data source. Wire models stay hand-written: drift never parses the wire, and
  the replica stores the daemon's JSON for the same `fromJson` to parse. Passwords never enter
  SQLite; the Keychain (`flutter_secure_storage`, `server.password.<id>`) holds passwords only.
  There is no SharedPreferences in first-party code (`easy_localization` still pulls it in
  transitively), and `test/core/no_shared_preferences_test.dart` pins that. The v1→v2 upgrade
  wiped and recreated every table and purged the Keychain passwords with it; every later schema
  bump must migrate in `onUpgrade`, never wipe. Generated
  `*.g.dart` is committed, because CI runs `flutter analyze` and `flutter test` with no
  generation step. Regenerate with `dart run build_runner build --delete-conflicting-outputs`.
- Parameterized paths get static methods on `EndPoints`; interpolating at a call site is
  forbidden.
- Feature code never imports `flutter_screenutil` — spacing, padding and radii take raw ints.
- User-facing copy is inline English. There is no `LocaleKeys` catalogue for product copy.
- Navigation is `Navigator.of(context)` with `RoutesStrings` names.

### Vendored packages

`packages/mobile/packages/` holds forks resolved as pub workspace members, not from
pub.dev: `xterm` (the terminal renderer) and `speech_to_text` +
`speech_to_text_platform_interface` (dictation). The speech fork exists to add
`contextualStrings`, the iOS audio-session configuration, and Android biasing extras
that the published package does not expose — see `packages/speech_to_text/FORK.md`
before upgrading. `analysis_options.yaml` excludes `packages/**`, so upstream lints do
not gate the app; keep fork diffs small enough to re-apply.

### Deliberately unwired

One subsystem is built and tested behind its seam but has no live SDK, and this
is intentional — do not "finish" it without the credentials:

- **Telemetry.** The sanitizer, rate limiter, daily-active tracker and closed event
  vocabulary all exist; the sink is the abstract `MobileTelemetryClient`. No PostHog key
  exists, so nothing is sent.
