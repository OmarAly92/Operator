# Mobile start flow and one local store: design

Date: 2026-09-25. Branch `feat/mobile-ios-polish`, package `packages/mobile`.
Approved in chat on 2026-09-25: build all three parts (A, B, C), put every local store in drift, and keep passwords in the Keychain. The user allowed breaking changes and a fresh migration, and asked for the cleanest code and the best UX.

This spec supersedes `docs/superpowers/plans/2026-08-28-mobile-replica-cache.md` (Plan 9). Plan 9 was written and never built. It predates saved desktops, the chat screen and background tasks.

## Problem

Cold launch with an active desktop goes straight to the Agents board (`lib/main.dart:33-63`, `lib/feature/onboarding/logic/onboarding.dart`). The board has nothing to show until `GET /sessions` answers.

`SessionsCubit` emits `GetSessionsLoadingState`, then either success or `GetSessionsFailureState` (`sessions_cubit.dart:117-146`). The body renders that failure as a bare error icon and a Retry button (`sessions_body.dart:82`). The screen says nothing about what failed or what to do next.

The failure is already classified. `classifyConnectionFailure` in `core/error_handling/connection_error.dart` distinguishes unreachable, auth, rate-limited and server errors, and `describeConnectionFailure` has copy for each. Only the pairing screen uses them.

Local state is split across three stores:

| Store | Holds | Where |
|---|---|---|
| drift `AppDatabase`, schema 1 | saved desktops | `core/database/`, `tables/desktop/` |
| SharedPreferences, via `CacheHelper` | `current-theme`, `opr.activeProjectId`, `opr.session.view.<key>`, `opr.telemetry.rateLimit` and telemetry `getItem`/`setItem`, plus `opr.chat.draft.<id>` (declared but never read or written) | `core/helpers/cache/` |
| Keychain, via `flutter_secure_storage` | the password for each desktop, keyed `server.password.<id>` | `desktops_local_data_source.dart` |

## Goals

1. Opening the app shows your data at once: the last known board, notifications and chat history, drawn from drift. Fresh data then replaces it in place.
2. Connection trouble is always visible, specific, and paired with a way forward. The app never shows a bare error.
3. drift is the only local database. The Keychain holds only passwords.

Not goals:
- Queueing messages sent while offline.
- Background sync while the app is closed.
- Detecting a daemon that is too old: no version signal exists today.
- The terminal screen.

## Design

### 1. One drift database

`AppDatabase` goes to `schemaVersion` 2. `onUpgrade` drops every table and runs `createAll`. The app is pre-release, so wiping local state is acceptable. The same upgrade deletes every `server.password.*` Keychain entry, because the desktops table that points at them is gone. The user pairs again once.

New tables, each laid out as `core/database/tables/<table>/` with its table and DAO, following the desktop table:

- **`settings`**: `key TEXT PRIMARY KEY`, `value TEXT NOT NULL`.
- **`replica_documents`**:
  - columns: `desktopId TEXT`, `key TEXT`, `body TEXT` (the JSON exactly as the daemon sent it), `fetchedAt DATETIME`
  - primary key `(desktopId, key)`
  - holds whole-resource snapshots
- **`replica_block_events`**:
  - columns: `desktopId TEXT`, `sessionId TEXT`, `seq INTEGER`, `body TEXT`
  - primary key `(desktopId, sessionId, seq)`
  - holds chat history

Deleting a desktop deletes its replica rows in the same transaction.

**Settings.** `AppPreferences` in `core/preferences/` replaces `CacheHelper`.
- `main` calls `AppPreferences.load()` where `CacheHelper.init()` runs today. It reads every settings row into memory, so reads stay synchronous: `SkinCubit` and `SessionsCubit` read in their constructors.
- Writes update memory at once and write to drift in the background.
- Typed accessors, each with its own key:
  - `themeMode`
  - `activeProjectId(desktopId)`: now scoped to the desktop, since project ids are per daemon
  - `sessionView(key)`
  - `telemetryRateLimit`
  - a generic `string(key)`/`setString(key)` pair for the telemetry storage port

`shared_preferences`, `CacheHelper`, `CacheKeys` and the unused draft key are deleted.

**Keychain.** Unchanged: passwords only, never in SQLite.

### 2. Replica: the stored copy, then fresh data

The rule: drift stores the daemon's JSON, and the existing hand-written `fromJson` parses it. There is one parse path, whether the JSON came from the network or from drift. No wire model gains a drift twin.

**Replicated resources:**

| Resource | Replica key | Written when | Read by |
|---|---|---|---|
| Board | `board.sessions`, `board.projects`, `board.accounts` (the raw body of each of the three calls) | every successful board load | `SessionsCubit`, so the Agents and PRs tabs, since PRs derive from sessions |
| Notifications, first page | `notifications.first` | every successful first-page load | `NotificationsCubit` and the bell |
| Chat history | `replica_block_events` rows | each history page from `GET /blocks` and each live event from the mux | `BlocksCubit` when a chat opens |

Chat history is capped at the newest 200 events per session. Older rows are trimmed on write. Pagination further back still comes only from the daemon.

**Layering**, per feature, following `CLAUDE.md`:
- The remote data source for a replicated resource returns the decoded body, so the repository can store it.
- A new local data source reads and writes the replica through the DAO.
- The repository exposes `Stream<Replicated<T>> watchX()`:
  1. it yields the cached value, if any, with `isCached: true` and `fetchedAt`
  2. it fetches, stores, and yields the fresh value with `isCached: false`
  3. on failure it yields the failure, and the cached value stays on screen
- `Replicated<T>` lives in `core/replica/`.
- The sequential auth probe in `sessions_remote_data_source.dart` (`/sessions` first, then projects and accounts) is preserved exactly.

**Scoping.** Every replica read and write takes the active desktop's id from `ServerConfigStore`. Switching desktops (`SessionsCubit._onConfigChanged`) re-reads the replica for the new id, so a desktop never shows another desktop's data.

### 3. Connection state

`ConnectionCubit`, in `core/connection/`, is the single source of connection state. It listens to two things:
- **Every HTTP outcome**, through a new `ConnectionReportInterceptor` beside `ServerConfigInterceptor`. A response means online. A connect or receive timeout, or a connection error, means unreachable. 401 and 403 mean auth. 429 means rate-limited. Other 5xx responses mean server error.
- **`MuxClient.status`.**

It has four states:

| State | Carries |
|---|---|
| `connecting` | — |
| `online` | `updatedAt` |
| `offline` | `reason` (unreachable, rate-limited or server error) and `lastSeenAt` |
| `authFailed` | — |

**Retry.**
- While offline, it emits on a `retries` stream. The delay starts at 1s, doubles each time, and is capped at 30s. `SessionsCubit` and `NotificationsCubit` listen and refresh, so `core/` never imports a feature.
- It retries at once on `AppLifecycleState.resumed`. This lifecycle hook moves from `SessionsBody` into the cubit's owner.
- `authFailed` stops retrying, in line with the lockout rule in `CLAUDE.md`.

`ConnectionCubit` is provided above `HomeShell`, so every tab and the chat can read it.

### 4. What the user sees

**Header.** Under the large "Agents" title, one line: the desktop's name and a status. Tapping the line opens the connections (desktop switcher) screen. The PRs tab shows the same line. The status reads:
- "Connecting…" with a small spinner
- "Updated just now", or "Updated 5m ago" once the data is more than a minute old
- "Offline · last seen 5m ago", in `attentionText` colour
- "Needs re-pairing", in red

**Loading.** Skeleton cards appear only when no cached value exists. They take the card's shape and use the existing `Shimmer`. Six cards, not a spinner.

**Failure with no cached data.** A full-screen state:
- an icon
- a title from `describeConnectionFailure`, e.g. "Can't reach MacBook"
- one line of hint
- **Retry** as the primary button, and **Switch desktop** as the secondary

The local-network hint that pairing already shows is reused.

**Failure with cached data.** The cached board stays on screen. Only the header line changes.

**Auth failure.** The app opens a re-pair sheet once per failure episode, with the host prefilled. It uses the existing pairing flow, which gains a prefilled mode. The header also offers "Needs re-pairing" as a tappable way back to it.

**The + button.** While offline or in `authFailed`, it shows at 40% opacity. A tap gives an error haptic and a short toast, "Needs a connection to your desktop". It does not navigate.

**Empty board**, online with no sessions: "No agents yet", then "Spawn your first agent", with a small arrow glyph toward the **+**.

**Chat.** Opening a session draws its cached history at once. Fresh history merges in by `seq`. The composer's send stays as it is today: it fails visibly when offline.

**Notifications.** The cached first page draws at once, and the bell badge shows the cached unread count until the fresh one arrives.

## Error handling

- A drift read failure is logged and treated as a cache miss. A write failure is logged and ignored, since the network value is still shown. Both go through the existing `handleLocalFailure`.
- Cached JSON that no longer parses, e.g. after a model change, is deleted and treated as a miss.
- The 12s Dio timeouts stay. The retry schedule sits on top of them.

## Testing

- **DAO tests** on an in-memory `AppDatabase.forTesting`, for:
  - settings round-trips
  - replica put, get and watch
  - the 200-event cap
  - deleting a desktop cascades to its replica rows
  - the v1 → v2 upgrade wipes all tables, with a real v1 schema fixture
- **`AppPreferences`:** loads, then answers reads synchronously. Each typed key maps correctly. The project selection is scoped per desktop.
- **Repository `watch` streams:**
  - cached then fresh
  - no cache, then fresh
  - cached then failure
  - JSON that won't parse is deleted
  - the auth probe order is still pinned
- **`ConnectionCubit`:**
  - each interceptor outcome maps to the right state
  - the backoff schedule, with a fake clock
  - an immediate retry on resume
  - no retry after `authFailed`
- **Widgets:**
  - skeletons only with no cache
  - cached board plus the offline header
  - the full-screen error copy for each reason
  - the dimmed **+**, its haptic and toast
  - the empty-board state
  - the header tap opens connections
  - the re-pair sheet opens once
- **Simulator**, dark and light:
  - a cold launch with a cache and the daemon down
  - a cold launch with no cache and the daemon down
  - online
  - the re-pair sheet
  - the empty board
- **Gate:** `flutter analyze` prints "No issues found!", and `flutter test` passes.

## Docs

`packages/mobile` parts of `CLAUDE.md`:
- The drift paragraph now says drift is the single local store: saved desktops, settings and the replica. The Keychain holds passwords only, and there is no SharedPreferences.
- Mark Plan 9 superseded, with a pointer to this spec.
