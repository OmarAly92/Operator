# Mobile saved desktops — design

**Date:** 2026-09-16
**Status:** approved in conversation, awaiting implementation
**Scope:** `packages/mobile` (Flutter), one new daemon route in `backend/internal/httpd`, `packages/mobile` section of `CLAUDE.md`.

## 1. Problem

The phone remembers exactly one desktop. `ServerConfigStore` holds a single
`ServerConfig` in four `shared_preferences` keys plus one keychain entry
(`packages/mobile/lib/core/api/server_config_store.dart:15-31`). Pairing a
second Mac overwrites the first; Disconnect throws the only one away and
sends the user back to onboarding
(`packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart:177-178`).

A "Your desktops" list screen exists but is a UI prototype: hard-coded rows
("Alex's MacBook Pro", "Office iMac"), a 900 ms fake connect timer, in-memory
add/edit/remove, reachable only from Settings
(`packages/mobile/lib/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart:9-47`,
`packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart:231`).

The phone also has no way to learn a desktop's name. The QR payload is
`{v, host, port, password}` (`frontend/src/renderer/lib/mobile-status.ts:30-35`)
and no daemon route reports identity; the only hostname on the wire is buried
in error-envelope `requestId`s. A saved list whose rows all read
`192.168.1.2:58682` is not useful.

## 2. Goals

- Keep every desktop the user has paired; switch between them in one tap.
- Show each desktop by its real name (`Omar's MacBook Pro`), not its address.
- On launch: no desktops → onboarding; an active desktop → sessions as today;
  desktops but none active → the list.
- Re-pairing a desktop whose password rotated updates its entry rather than
  duplicating it.
- Introduce drift for on-device state using the layout of
  `/Users/omaraly/development/projects/dont_say` (`lib/core/database/…`),
  which is the pattern the `flutter-knowledge:drift-local-database` skill
  documents. This widens the `CLAUDE.md` drift boundary by explicit user
  decision (2026-09-16).

## 3. Non-goals

- Migrating the existing single-config keys. Operator has no users; dev
  installs re-pair once. `ServerConfigStore.load()` simply stops reading the
  old keys and `clear()` stops writing them.
- A desktop-side custom display name (hostname is enough for now).
- Auto-reconnect across desktops when the active one is unreachable.
- The replica cache from `docs/superpowers/plans/2026-08-28-mobile-replica-cache.md`.
  It was never built (`packages/mobile/lib/core/cache/` does not exist); when it
  lands it joins the same `AppDatabase`.

## 4. Daemon: `GET /api/v1/desktop`

**Purpose.** Let an authenticated phone learn who it is talking to. One
round-trip replaces the pairing probe's `GET /api/v1/sessions`
(`packages/mobile/lib/feature/pairing/data/data_source/pairing_remote_data_source.dart:17`):
it verifies the password *and* returns the name.

**Response** `200`:

```json
{ "name": "Omars MacBook Pro 9", "hostname": "Omars-MacBook-Pro-9.local" }
```

- `hostname` is `os.Hostname()` verbatim.
- `name` is `hostname` with a trailing `.local` removed and hyphens replaced
  by spaces (`Omars MacBook Pro 9`). Pure function, unit-tested. Empty
  hostname → `name: "Desktop"`.
- Errors use the locked envelope (`{error, code, message, requestId}`).

**Placement.**
- DTO `DesktopResponse` in `backend/internal/httpd/controllers/dto.go`.
- Handler `DesktopController.Get` in a new
  `backend/internal/httpd/controllers/desktop.go`, with a `Hostname func()
  (string, error)` field defaulting to `os.Hostname` so tests inject a value.
- Mounted in `backend/internal/httpd/router.go` next to the other
  `/api/v1/*` app routes — **not** under `mountMobile`
  (`backend/internal/httpd/router.go:139-150`), because everything under
  `/api/v1/mobile` is 404'd on the LAN listener by `lanControlBlock`
  (`backend/internal/httpd/lan_listener.go:57-76`). The phone must reach it.
- `backend/internal/httpd/mobile_routes_test.go` gains a case proving
  `/api/v1/desktop` is served, not blocked, on the LAN handler.
- The OpenAPI document is code-first
  (`backend/internal/httpd/apispec/specgen/build.go`); regenerate
  `openapi.yaml` and let the parity tests in `go test ./internal/httpd/...`
  confirm.

## 5. Phone: storage on drift

### 5.1 Dependencies

`pubspec.yaml`: `drift`, `drift_flutter` (dependencies); `drift_dev`,
`build_runner`, `sqlite3` (dev), pinned to the versions dont_say uses
(`drift ^2.34.1`, `drift_flutter ^0.3.0`, `build_runner ^2.7.1`,
`drift_dev ^2.34.0`, `sqlite3 ^3.3.4`). Generated `*.g.dart` is committed;
CI (`.github/workflows/mobile-flutter.yml`) runs no codegen step.

### 5.2 Core layer

```
lib/core/database/app_database.dart
lib/core/database/tables/desktop/desktop_table.dart
lib/core/database/tables/desktop/desktop_dao.dart
lib/core/error_handling/drift_error_handler/drift_error_handler.dart
```

`AppDatabase`: `@DriftDatabase(tables: [Desktops], daos: [DesktopDao])`,
`AppDatabase() : super(driftDatabase(name: 'operator_mobile'))`,
`AppDatabase.forTesting(super.executor)`, `schemaVersion => 1`,
`MigrationStrategy(onCreate: (m) => m.createAll())`.

`Desktops` table, `@DataClassName('DesktopEntity')`:

| column | type | notes |
|---|---|---|
| `id` | text, primary key | UUID v4, generated in the local data source |
| `name` | text | from `/api/v1/desktop`, user-renamable |
| `host` | text | |
| `port` | text | kept as text to match `ServerConfig.httpPort` |
| `secure` | bool | |
| `isActive` | bool, default false | at most one true row (enforced by `setActive`'s transaction) |
| `renamed` | bool, default false | set by `rename`; see 5.3 |
| `lastConnectedAt` | datetime, nullable | |
| `createdAt` | datetime, clientDefault now | |

Unique index on `(host, port, secure)`.

`DesktopDao` (`@DriftAccessor(tables: [Desktops])`), every method chained
with `.handleLocalFailure()`:

- `Stream<List<DesktopEntity>> watchAll()` — ordered `isActive desc,
  lastConnectedAt desc nulls last, createdAt desc`.
- `Future<List<DesktopEntity>> getAll()`
- `Future<DesktopEntity?> getActive()`
- `Future<DesktopEntity?> findByEndpoint(String host, String port, bool secure)`
- `Future<String> upsert(DesktopsCompanion row)` — transaction:
  `findByEndpoint`; none → insert and return the new id; found → update
  `name` only when `renamed` is false, return the existing id (see 5.3).
- `Future<void> setActive(String id)` — transaction: clear all, set one,
  stamp `lastConnectedAt`.
- `Future<void> clearActive()`
- `Future<void> rename(String id, String name)`
- `Future<void> delete(String id)`

`drift_error_handler.dart` is ported verbatim from dont_say
(`lib/core/error_handling/drift_error_handler/drift_error_handler.dart`),
targeting Operator mobile's existing `LocalFailure`
(`packages/mobile/lib/core/error_handling/failures/local_failure.dart`).

### 5.3 Rename tracking

`rename` sets `renamed`; `upsert` on an existing endpoint keeps `name` when `renamed` is true and overwrites it from the
daemon otherwise. This is what makes "re-pair the same Mac" keep the user's
label while a fresh pair still picks up a changed hostname.

### 5.4 Passwords stay in the keychain

SQLite is plaintext on disk; the keychain is not. The password for desktop
`id` lives in `flutter_secure_storage` under `server.password.<id>`. The local
data source writes it in the same call that upserts the row and deletes it in
the same call that deletes the row. The old single key `server.password`
(`CacheKeys.serverPassword`) is removed along with `serverHost`,
`serverHttpPort`, `serverSecure` in `cache_keys.dart`.

### 5.5 Feature layer (`lib/feature/pairing/data/`)

- `model/desktop_model.dart` — `DesktopModel` (Equatable, all-nullable:
  `id, name, host, port, secure, isActive, lastConnectedAt`),
  `factory DesktopModel.fromDB(DesktopEntity)`,
  `ServerConfig toServerConfig(String password)`.
- `model/params/save_desktop_params.dart` — `name, host, port, secure,
  password` (all required).
- `model/params/rename_desktop_params.dart` — `id, name`.
- `data_source/desktops_local_data_source.dart` — `DesktopsLocalDataSource`
  / `DesktopsLocalDataSourceImp(DesktopDao, FlutterSecureStorage)`. The only
  file that touches `DesktopEntity`, `DesktopsCompanion`, or the keychain.
  Methods: `watchAll`, `getActive`, `save(SaveDesktopParams) → DesktopModel`
  (upsert + password + setActive), `activate(id)`, `deactivate()`,
  `rename(RenameDesktopParams)`, `remove(id)`, `passwordFor(id)`.
- `repository/desktops_repository.dart` — local-only, `FutureResult<T>`
  (`packages/mobile/lib/core/helpers/result/result.dart`), no `drift`
  import. `watchDesktops()` returns the stream directly.

### 5.6 `ServerConfigStore` becomes in-memory + load

Keeps its public surface so `ServerConfigInterceptor`, `DioConsumer`,
`NetworkStatusImp`, and `MuxClient` are untouched
(`packages/mobile/lib/core/utils/service_locator.dart:82-92`):

- `current` — unchanged getter.
- `load()` — reads the active row through `DesktopsLocalDataSource` and its
  password; sets `current` or leaves it null.
- `set(ServerConfig)` — in-memory only (renamed from `save`; the persistence
  moved to the repository).
- `clear()` — in-memory only.

Constructor takes `DesktopsLocalDataSource` instead of `FlutterSecureStorage`.

### 5.7 Pairing repository

`PairingRepository.verifyAndConnect(ServerConfig target)`
(`packages/mobile/lib/feature/pairing/data/repository/pairing_repository.dart:18-26`)
becomes:

1. `remote.identify(target)` → `DesktopIdentityModel {name, hostname}` via
   `GET /api/v1/desktop` with `pairingTarget` in Dio extra (replaces `ping`).
2. `desktops.save(SaveDesktopParams(name, host, port, secure, password))`.
3. `store.set(target)`.

`EndPoints.desktop = '/api/v1/desktop'`.

## 6. Launch routing

Pure function in `lib/feature/onboarding/logic/onboarding.dart`, replacing
`shouldOnboard`:

```dart
enum LaunchDestination { onboarding, desktops, sessions }

LaunchDestination launchDestination({required int desktopCount, required bool hasActive});
```

- `desktopCount == 0` → `onboarding`
- `hasActive` → `sessions`
- otherwise → `desktops`

`main.dart` (`packages/mobile/lib/main.dart:42-45`) calls
`ServerConfigStore.load()` (already does), counts desktops through the
repository, and maps the enum to `RoutesStrings.onboarding | connections |
sessions`.

## 7. Flows

**Pair (QR or manual).** Unchanged UI. On success the desktop is saved and
active; `fromOnboarding` navigation stays as is
(`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart:15-19`).
The `fromOnboarding` flag is also set when onboarding is opened from the
list's add action, so the result lands on sessions.

**List → tap row.** `ConnectionsCubit.connectTo(id)`:
1. read password (`passwordFor`), build `ServerConfig`;
2. `remote.identify(config)`;
3. success → `desktops.activate(id)` (also refreshes `name` unless
   `renamed`), `store.set(config)`, emit `ConnectSuccessState(id)` → screen
   `pushNamedAndRemoveUntil(sessions)`;
4. failure → `ConnectFailureState(id, ConnectionErrorCopy)` using
   `classifyConnectionFailure` / `describeConnectionFailure`
   (`packages/mobile/lib/core/error_handling/connection_error.dart`). The row
   shows the copy inline. For `auth` the row's message is "Password changed —
   scan the code on that computer again" and tapping the row's action opens
   the scanner; scanning the same endpoint upserts the entry.

**List → `+` or "Pair another desktop".** `pushNamed(onboarding,
arguments: {'fromDesktops': true})`. Onboarding's `PopScope(canPop:false)`
(`onboarding_screen.dart`) becomes `canPop: fromDesktops` so the back arrow
works when there is somewhere to go back to; the screen shows a back arrow
only in that case.

**Row menu.** Rename (sheet, name only — `connection_form_sheet.dart` loses
its address field and becomes `rename_desktop_sheet.dart`), Remove (existing
confirm dialog). Removing the active desktop: `store.clear()` as well.
Removing the last desktop: navigate to onboarding.

**Settings › Disconnect.** `forgetServer` becomes `desktops.deactivate()` +
`store.clear()`; `ForgetSuccessState` navigates to `connections` instead of
`onboarding` (`settings_body.dart:177-178`). "Connections" row stays.

## 8. UI

Reuse the existing widgets under
`lib/feature/pairing/presentation/connections_screen/ui/widgets/` and keep
the `docs/design/connections/connections.md` look (the file referenced in
those widgets' doc comments; it does not exist in the repo — the widgets
themselves are the reference). Changes:

- Header: app icon tile (`assets/images/app_icon_image.png`, 28 px, radius
  7 — same as onboarding) + "Operator" + trailing `+`.
- Title "Your desktops"; subtitle "Tap a desktop to connect."
- Row: icon tile, name (`style15SemiBold`), subtitle
  `192.168.1.2:58682 · LAN` or `… · Remote` (`isLocalNetworkHost`), trailing
  `2h ago` (pure `relativeLabel(DateTime, now)` — new, tested), replaced by a
  16 px spinner while connecting; a 6 px accent dot before the name on the
  active row. A failed row shows the error copy under the subtitle in
  `skin.danger`, with an "Scan again" text action on `auth`.
- Bottom: full-width `PrimaryButton('Pair another desktop')` pinned above
  the safe area.
- No empty state: the screen is never shown empty (routing + last-remove
  navigate away).

`SavedConnection` (`connections_screen/logic/saved_connection.dart`) is
deleted; the UI reads `DesktopModel`.

## 9. DI (`service_locator.dart`)

`_coreSetup`: `AppDatabase` lazy singleton; `DesktopDao(sl<AppDatabase>())`;
`DesktopsLocalDataSourceImp(sl<DesktopDao>(), sl<FlutterSecureStorage>())`;
`DesktopsRepositoryImp(sl<DesktopsLocalDataSource>())`;
`ServerConfigStore(sl<DesktopsLocalDataSource>())`.
Pairing: `PairingRepositoryImp(remote, desktopsRepo, store)`;
`ConnectionsCubit(desktopsRepo, pairingRemote, store)`.

## 10. Testing

- Go: `DesktopController` handler test (injected hostname, `.local`
  stripping, empty hostname), LAN-served route test, spec parity.
- Dart, `AppDatabase.forTesting(NativeDatabase.memory())`:
  DAO (`setActive` exclusivity, endpoint upsert honours `renamed`, ordering);
  local data source with an in-memory `FlutterSecureStorage` fake (password
  written on save, deleted on remove);
  repository with a mocked data source;
  `ConnectionsCubit` via `bloc_test` (success, auth failure copy, remove
  active clears store);
  `launchDestination` table test; `relativeLabel` table test;
  `PairingRepositoryImp` call order (identify → save → set).
- Existing tests to update: `disconnect_test.dart`, `onboarding_test.dart`,
  `call_sites_test.dart` (paired event unchanged), any test constructing
  `ServerConfigStore` with a secure-storage mock.
- Gate: `flutter analyze` clean, `flutter test` green, `cd backend && go test
  ./internal/httpd/...`.

## 11. `CLAUDE.md` update

Replace the drift bullet under "Conventions specific to this package" with:

> **`drift` and `build_runner` are permitted for on-device state under
> `lib/core/database/`** (saved desktops today; the replica cache when it
> lands), following the `flutter-knowledge:drift-local-database` layout:
> tables and DAOs in `core/database/tables/<table>/`, local data sources in
> the feature, no drift import above the data source. Wire models stay
> hand-written — drift never parses the wire. Passwords never enter SQLite;
> they stay in `flutter_secure_storage`. Generated `*.g.dart` is committed.

Also update the "`ServerConfig` is the spine" paragraph: the password lives
in `flutter_secure_storage` keyed by desktop id; everything else in the drift
`desktops` table.

## 12. Open risks

- `drift_flutter` on iOS/Android needs no native changes, but this is the
  first native-library dependency (`sqlite3_flutter_libs`) in the app: run
  `flutter build ios --release --no-codesign` and `flutter build apk
  --release` once, since `flutter test` does not exercise it.
- `os.Hostname()` on macOS returns the Bonjour-style name; on Windows it is
  the NetBIOS name. Both acceptable; the mapping function only strips `.local`.
