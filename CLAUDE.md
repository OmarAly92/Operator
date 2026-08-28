# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read and follow [`AGENTS.md`](AGENTS.md) for repository layout, commands, coding conventions, and hard rules.

**`AGENTS.md` covers `backend/` and `frontend/` only.** The third deliverable, the Flutter
mobile client at `packages/mobile`, is documented below.

## App state lives under `~/.operator` only

All app state, the daemon's data dir, `running.json`, worktrees, and the desktop
shell's webview state (cache, cookies, local/session storage, crash dumps) must
resolve under `~/.operator` (overridable via `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE`).
Never write to or read from `~/Library/Application Support` or any other OS-default
app-data location. See the hard rule in `AGENTS.md`.

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

When showing or demoing frontend changes, run `opr preview [url]` from inside the
session so the change opens in the user's default browser as an external preview
(`opr preview clear` removes the target without opening anything); do not just
describe it.

## Mobile client (`packages/mobile`)

A Flutter thin client for the daemon, pubspec name `operator_mobile`. It runs no
agents — it talks to a paired daemon over REST, one multiplexed WebSocket, and SSE
for chat. It replaced an Expo/React Native app that was deleted at milestone M6;
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
functions), `presentation/<screen>_screen/{logic,ui}` (cubit + widgets). Eleven
features: `pairing`, `onboarding`, `sessions`, `pull_request`, `orchestrator`,
`spawn`, `chat`, `terminal`, `preview`, `notification`, `settings`.

**`ServerConfig` is the spine.** The API base URL does not exist until pairing
completes, so no data source ever sees host/port/password. `ServerConfigStore` holds
the current config and `ServerConfigInterceptor` stamps `baseUrl` and the
`Authorization: Bearer` header onto every request; a request may pass a
`pairingTarget` in Dio's `extra` to aim at a server that is not saved yet, which is
how pairing verifies before persisting. The password lives in `flutter_secure_storage`,
everything else in `shared_preferences`.

**Two load-bearing behaviors that look like inefficiencies.** Do not "optimize" either:

- **12-second `connectTimeout`/`receiveTimeout`** (`dio_consumer.dart`). Over Tailscale a
  sleeping host otherwise hangs for the OS TCP timeout of 75–120s, freezing Kill, send,
  and the poll loop.
- **Sequential auth probing.** `sessions_remote_data_source.dart` awaits `/sessions`
  *alone* before fanning out to orchestrators and projects. The daemon locks a device
  out for a minute after 5 failed auths, so a stale password under `Future.wait` burns
  4 failures per poll tick and arms the lockout before the user can re-pair. A test
  pins the call order.

**`MuxClient` lives in `core/mux/`, not under `terminal/`.** The Kanban board depends on
the same socket for session patches, so nesting it under a feature would make the
board's liveness depend on a feature it has no business knowing about. Cubits subscribe
to its broadcast streams; nothing else touches the socket.

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

### Conventions specific to this package

- **Cubit only** — never `Bloc` with events. Static-only classes are `sealed class X`.
- **No `freezed` or `json_serializable`** in first-party code. Models are hand-written
  with all fields nullable and `fromJson` doing the wire→domain mapping. One params
  class per method under `data/model/params/`, never shared.
- **`drift` and `build_runner` are permitted for the on-device replica cache only**
  (`lib/core/cache/`), by explicit user decision 2026-08-28. No other package imports
  `package:drift/drift.dart`, and wire models stay hand-written — drift never parses
  the wire. See `docs/superpowers/plans/2026-08-28-mobile-replica-cache.md` for the
  boundary. Generated `*.g.dart` is committed, because CI runs `flutter analyze` and
  `flutter test` with no generation step.
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

Two subsystems are built and tested behind their seams but have no live SDK, and this
is intentional — do not "finish" them without the credentials:

- **Telemetry.** The sanitizer, rate limiter, daily-active tracker and closed event
  vocabulary all exist; the sink is the abstract `MobileTelemetryClient`. No PostHog key
  exists, so nothing is sent.
- **Push.** `push_registrar`, `push_registration`, `push_status` and the Settings switch
  exist behind `PushTokenSource`. FCM/APNs registration needs a Firebase project and an
  APNs key.
