# Mobile Start Flow and Local Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone opens straight onto the last known board, notifications and chat history from one drift store, and connection trouble is always visible, specific and recoverable across the whole start journey.

**Architecture:** drift schema v2 adds `settings`, `replica_documents` and `replica_block_events`; the upgrade wipes every table and the Keychain passwords. `AppPreferences` (static, memory-first, write-behind to drift) replaces `CacheHelper`. Each replicated repository writes the daemon's decoded JSON on every successful fetch and exposes a `cachedX()` read that parses through the same hand-written `fromJson`; cubits paint the cache once per desktop, then the network. A `ConnectionReportInterceptor` feeds `ConnectionCubit`, the single source of connection state, which drives the header status line, the retry schedule, the **+** button and the re-pair sheet.

**Tech Stack:** Flutter 3.44.5, Dart, drift 2.34 with drift_dev and build_runner, flutter_bloc (Cubit only), dio 5, flutter_secure_storage 11, mocktail, bloc_test, fake_async, the glass and sheet widgets (`AppSheet`, `GlassButton`, `Shimmer`, `AppToast`).

**Spec:** `docs/superpowers/specs/2026-09-25-mobile-start-flow-and-local-store-design.md`. Read it before Task 1. It supersedes Plan 9 (`docs/superpowers/plans/2026-08-28-mobile-replica-cache.md`).

## Deviations from spec

Each was checked against the code. The spec's intent is kept in every case.

1. **`ServerConfig` has no desktop id today** (`lib/core/api/server_config.dart:3-22`), so `ServerConfigStore` cannot scope anything by desktop. Task 2 adds a nullable `desktopId` to `ServerConfig`, set by `DesktopModel.toServerConfig`. `PairingRepositoryImp` now sets the saved desktop's config (with its id) instead of the bare verify target (`pairing_repository.dart:35-37`).
2. **Repositories expose `cachedX()` beside the existing `getX()`, not a `Stream<Replicated<T>> watchX()`.** `SessionsCubit` re-fetches the board on every mux board change through a 200 ms debounce, a queued refresh and a board epoch (`sessions_cubit.dart:76-157`). A watch stream would re-read drift and re-yield the cache on every one of those refreshes. So `getX()` writes the replica on success, `cachedX()` reads it, and each cubit reads the cache once per desktop (at construction and on a desktop switch), then fetches. On failure the cubit keeps what it shows, which is the spec's step 3. `Replicated<T>` carries `value` and `fetchedAt`.
3. **`NotificationsCubit` ignores desktop switches today** (`notifications_cubit.dart:23-27` subscribes to nothing), so it keeps the previous desktop's list. Task 5 adds config-change handling; the spec's scoping rule needs it.
4. **`ConnectionCubit` is provided at the app root, not above `HomeShell`.** The chat is its own route on the root navigator (`app_router.dart:100-148`), so a provider inside the sessions route would not reach it. Its resume retry joins the existing app-level `AppLifecycleListener` in `main.dart:86-89`. `SessionsBody` keeps its own pause/resume hook for board polling, which `sessions_body_test.dart:103` pins.
5. **`/healthz` needs no password** (`backend/internal/httpd/router.go:97`), and `NetworkStatusImp` pings it before every repository call (`network_status.dart:16-24`). So a `/healthz` 200 never clears `authFailed`. `authFailed` clears only on an authenticated 2xx, on the mux opening, or on a desktop change.
6. **Mux status:** `MuxStatus.open` means online. `MuxStatus.error` while online asks for one immediate re-probe and is not treated as offline, because the mux reconnects on its own backoff and flaps (`mux_client.dart:15`, `:262-270`).
7. **Rate-limited retries wait 60 s**, not the 1 s backoff. The daemon's lockout lasts about a minute (`connection_error.dart:87-88`), and probing inside it only extends the wait.
8. **The offline status line uses `skin.amber`, not `attentionText`.** `attentionText` is the brand green in both skins (`dark_skin.dart:107`, `light_skin.dart:107`), so "Offline" in it would read as healthy.
9. **The full-screen error for an auth failure offers Re-pair, not Retry.** A retry spends one of the 5 attempts before the lockout (`CLAUDE.md`, "Sequential auth probing").
10. **"Can't reach MacBook"** comes from a new optional `desktopName` parameter on `describeConnectionFailure`. Pairing callers pass nothing and keep "Your desktop disconnected".
11. **The Keychain purge runs on `onCreate` as well as `onUpgrade`.** iOS keeps Keychain items across an uninstall, so a fresh install can inherit passwords with no desktop row.
12. **`shared_preferences` stays a transitive dependency** of `easy_localization` (`pubspec.lock`). First-party code drops it, and a guard test pins that no file in `lib/` imports it.
13. **The chat replica covers the main conversation only**, meaning rows with an empty `agentId` that are not `task_update`. `GET /blocks` without `agentId` returns the main conversation only (`backend/internal/httpd/apispec/specgen/build.go:632`). Subagent screens are not replicated.
14. **No gap-fill logic for chat.** The daemon keeps 500 events per session (`backend/internal/service/blockevent/service.go:46-50`) and answers `afterSeq` with every retained event after it (`.../gen/block_events.sql.go:178-184`). So one fetch after the cached tail returns everything missed.
15. **The theme choice resets once.** The upgrade wipes local state and SharedPreferences is not migrated, so the theme returns to its Light default (`skin_cubit.dart:25`) until the user picks again.

## Flow additions beyond the spec

Audit of the start journey: first launch, onboarding, pairing (QR, manual, verify), first board, returning launch, desktop offline, wrong password, switching and adding desktops, and opening from a notification. Each addition below has its own task and tests.

- **A. Desktop switcher sheet (Task 10).** The header and "Switch desktop" open a glass sheet listing desktops instead of a full screen. Switching swaps the board in place, from the new desktop's cache, without tearing down the home shell.
- **B. Launch hand-off (Task 11).** Before the first frame, `main` waits up to 400 ms for the board cache, and the native splash colours match `bgBase`. The splash hands straight to the cached board: no skeleton flash, no colour jump, and no "No agents" frame from `SessionsInitialState`.
- **C. Pairing success step (Task 12).** A "Connected · <desktop name>" confirmation shows for 1.2 s after a QR or manual pair before the board. A first-time user gets a clear moment of success instead of a jump to a loading board.
- **D. Deep links wait for a paired desktop (Task 13).** A notification tap on a phone with no active desktop does nothing, instead of pushing a chat route over onboarding with no server behind it.

## Global Constraints

- Work only in the worktree `/Users/omaraly/development/AI/Operator-ios-polish`, branch `feat/mobile-ios-polish`. NEVER touch the main checkout `/Users/omaraly/development/AI/Operator`. Do not merge, push, rebase or open a PR.
- All commands run from `packages/mobile` unless a step says otherwise.
- Write NO code comments in anything you author. Keep upstream comments you did not write.
- Every commit message ends with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `frontend/package-lock.json` is dirty and not yours. Never stage it. Stage only the files each task names.
- Gate for every task: `flutter analyze` prints `No issues found!`, and the full `flutter test` passes (1827 tests on the base commit, plus each task's additions). Never weaken a test. A test of a changed API is ported to the new API with the same assertions, and the commit message names it.
- Colours come from `context.skin`. Type comes from `AppTextStyle`. Spacing, padding and radii are raw numbers or `AppConstants`; feature code never imports `flutter_screenutil`.
- Animation and on-screen timing durations come from `AppMotion`; add new ones there. Retry timing lives in `ConnectionBackoff`.
- Cubit only, never `Bloc`. Static-only classes are `sealed class X`. Hand-written models, all fields nullable, one params class per method. Parameterised paths get `EndPoints` static methods.
- drift tables and DAOs live in `lib/core/database/tables/<table>/`. No drift import above a data source. Wire models stay hand-written, and drift never parses the wire: the replica stores the daemon's decoded JSON, and the existing `fromJson` parses it. Regenerate with `dart run build_runner build --delete-conflicting-outputs`, and commit the generated `*.g.dart`.
- Passwords never enter SQLite. They stay in `flutter_secure_storage` under `server.password.<id>`.
- Preserve the sequential auth probe: `/sessions` is awaited alone before projects and accounts fan out (`sessions_remote_data_source.dart:20-26`), and its test (`sessions_remote_data_source_test.dart:28`) keeps passing unchanged.
- Keep the 12 s Dio `connectTimeout` and `receiveTimeout` (`dio_consumer.dart:45-46`).
- Keep the approved dark-mode glass looks unchanged: the tab bar, the glass buttons, `AppSheet` and the frosted header are reused as they are, not restyled.
- User-facing copy is inline English, exactly as written in each task.
- Simulator captures: the booted iOS simulator, bundle id `dev.operator.operatorMobile`. The theme resets to Light with the Task 1 wipe; set Settings → Theme → System once so `xcrun simctl ui booted appearance dark|light` flips the app. Never stop the user's `tauri:dev` (it kills live sessions). To make the desktop unreachable or to rotate its password, ask the user to turn Connect Mobile off or to rotate it. Re-pairing after the Task 1 wipe needs the user to type the password.

## Review Focus

1. **A desktop switch shows the previous desktop's data.** A cache read, a board fetch or a notifications fetch started for desktop A resolves after switching to B. B must never show A's rows, and A's response must never be written under B's id. Pinned by Task 4 (`SessionsCubit` epoch test, repository write-guard test) and Task 5 (notifications stale-fetch test).
2. **Cached JSON that no longer parses.** After a model change, a stored body throws in `fromJson`. The row is deleted, the read is a miss (skeletons, then the network), and the app never crashes or shows a half-parsed board. Pinned by Task 4, Task 5 and Task 6 repository tests.
3. **Retry storm and lockout on a rotated password.** After a 401 the app must not keep spending auth attempts. No retries, the unread poll holds, a `/healthz` 200 does not clear the state, and resuming the app does not re-fetch the board. Rate-limited waits 60 s. Pinned by Task 7 (`ConnectionCubit`, `SessionsCubit` and `NotificationsCubit` tests).
4. **A live mux event arrives before the cached history loads.** It must not move the history fetch's `afterSeq` past the cached tail (which would lose the gap), and it must not be overwritten by an older cached copy. Pinned by Task 6.
5. **A preference write lost on a quick app kill, or two writes landing out of order.** Writes update memory at once, go to drift immediately (never debounced) and serialized, and a failed write does not block later ones. Pinned by Task 3.

---

## File Structure

Created:

| Path (under `packages/mobile/`) | Responsibility |
|---|---|
| `lib/core/database/tables/settings/settings_table.dart`, `settings_dao.dart` | `settings(key, value)` rows |
| `lib/core/database/tables/replica_document/replica_document_table.dart`, `replica_document_dao.dart` | whole-resource snapshots per desktop |
| `lib/core/database/tables/replica_block_event/replica_block_event_table.dart`, `replica_block_event_dao.dart` | chat history rows, capped at 200 per session |
| `lib/core/replica/replica_limits.dart` | `ReplicaLimits.blockEventsPerSession` (no drift import) |
| `lib/core/replica/replica_keys.dart` | document keys `board.*`, `notifications.first` |
| `lib/core/replica/replicated.dart` | `Replicated<T>`: a cached value and when it was fetched |
| `lib/core/preferences/app_preferences.dart`, `preference_keys.dart` | memory-first settings over `SettingsDao` |
| `lib/core/connection/connection_report.dart` | `ConnectionOutcome`, `ConnectionReport`, `ConnectionReports` |
| `lib/core/connection/connection_backoff.dart` | retry timing |
| `lib/core/connection/connection_signals.dart` | the narrow port features listen to |
| `lib/core/connection/connection_cubit.dart`, `connection_state.dart` | the single source of connection state |
| `lib/core/connection/connection_status_line.dart` | pure state-to-copy mapping for the header |
| `lib/core/api/interceptors/connection_report_interceptor.dart` | turns every HTTP outcome into a report |
| `lib/core/widgets/connection/desktop_status_line.dart` | the header's desktop name and status |
| `lib/core/widgets/connection/connection_error_state.dart` | the full-screen failure with its way forward |
| `lib/feature/sessions/data/model/board_payload.dart` | the three board bodies as the daemon sent them |
| `lib/feature/sessions/data/data_source/sessions_local_data_source.dart` | board replica read/write |
| `lib/feature/sessions/presentation/sessions_screen/ui/widgets/board_skeleton.dart` | six shimmer cards |
| `lib/feature/sessions/presentation/sessions_screen/ui/widgets/home_title.dart` | tab title plus `DesktopStatusLine` |
| `lib/feature/notification/data/data_source/notification_local_data_source.dart` | first-page replica |
| `lib/feature/blocks/data/data_source/blocks_local_data_source.dart` | chat history replica |
| `lib/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart` | the auth re-pair sheet |
| `lib/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart` | Flow A |
| `lib/feature/pairing/presentation/pairing_success/ui/pairing_success_view.dart` | Flow C |
| `test/helpers/connection_harness.dart` | a real `ConnectionCubit` driven by hand for widget tests |

Deleted: `lib/core/helpers/cache/cache_helper.dart`, `lib/core/helpers/cache/cache_keys.dart`.

---

### Task 1: drift schema v2: settings and replica tables, wiped on upgrade

**Files:**
- Create: `packages/mobile/lib/core/replica/replica_limits.dart`
- Create: `packages/mobile/lib/core/database/tables/settings/settings_table.dart`, `settings_dao.dart` (+ generated `settings_dao.g.dart`)
- Create: `packages/mobile/lib/core/database/tables/replica_document/replica_document_table.dart`, `replica_document_dao.dart` (+ generated)
- Create: `packages/mobile/lib/core/database/tables/replica_block_event/replica_block_event_table.dart`, `replica_block_event_dao.dart` (+ generated)
- Modify: `packages/mobile/lib/core/database/app_database.dart` (+ regenerated `app_database.g.dart`)
- Modify: `packages/mobile/lib/core/database/tables/desktop/desktop_dao.dart` (+ regenerated `desktop_dao.g.dart`)
- Modify: `packages/mobile/lib/feature/pairing/data/data_source/desktops_local_data_source.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:87-88`
- Test: create `test/core/database/app_database_migration_test.dart`, `test/core/database/tables/settings/settings_dao_test.dart`, `test/core/database/tables/replica_document/replica_document_dao_test.dart`, `test/core/database/tables/replica_block_event/replica_block_event_dao_test.dart`; modify `test/core/database/tables/desktop/desktop_dao_test.dart`, `test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `sealed class ReplicaLimits { static const int blockEventsPerSession = 200; }`
  - `AppDatabase({Future<void> Function()? onWipe})`, `AppDatabase.forTesting(QueryExecutor executor, {Future<void> Function()? onWipe})`, `schemaVersion == 2`, generated accessors `settingsDao`, `replicaDocumentDao`, `replicaBlockEventDao`, `desktopDao`
  - `SettingsDao`: `Future<Map<String, String>> readAll()`, `Future<void> put(String key, String value)`
  - `ReplicaDocumentDao`: `Future<List<ReplicaDocumentEntity>> read(String desktopId, List<String> keys)`, `Stream<ReplicaDocumentEntity?> watch(String desktopId, String key)`, `Future<void> write(String desktopId, Map<String, String> bodies, DateTime fetchedAt)`, `Future<void> remove(String desktopId, List<String> keys)`
  - `ReplicaDocumentEntity { String desktopId; String key; String body; DateTime fetchedAt; }`
  - `ReplicaBlockEventDao`: `Future<List<ReplicaBlockEventEntity>> latest(String desktopId, String sessionId)` (oldest first, at most 200), `Future<void> write(String desktopId, String sessionId, Map<int, String> bodies)`, `Future<void> removeSession(String desktopId, String sessionId)`
  - `ReplicaBlockEventEntity { String desktopId; String sessionId; int seq; String body; }`
  - `DesktopDao.remove(String id)` now also deletes that desktop's replica rows, in one transaction
  - `static Future<void> DesktopsLocalDataSourceImp.purgePasswords(FlutterSecureStorage storage)`

- [ ] **Step 1: Write the failing tests.**

Create `test/core/database/app_database_migration_test.dart`. The DDL is the exact v1 `desktops` table the shipped schema 1 created, read from `sqlite_master` on the base commit:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';

const _v1Desktops =
    'CREATE TABLE "desktops" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "host" TEXT NOT NULL, "port" TEXT NOT NULL, '
    '"secure" INTEGER NOT NULL CHECK ("secure" IN (0, 1)), '
    '"is_active" INTEGER NOT NULL DEFAULT 0 CHECK ("is_active" IN (0, 1)), '
    '"renamed" INTEGER NOT NULL DEFAULT 0 CHECK ("renamed" IN (0, 1)), '
    '"last_connected_at" TEXT NULL, "created_at" TEXT NOT NULL, '
    'PRIMARY KEY ("id"), UNIQUE ("host", "port", "secure"))';

Future<List<String>> _tables(AppDatabase db) => db
    .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
    .map((row) => row.read<String>('name'))
    .get();

Future<int> _userVersion(AppDatabase db) =>
    db.customSelect('PRAGMA user_version').map((row) => row.read<int>('user_version')).getSingle();

void main() {
  test('a real v1 database is wiped to v2 and its saved passwords are purged', () async {
    var wipes = 0;
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(_v1Desktops);
          raw.execute(
            'INSERT INTO desktops (id, name, host, port, secure, is_active, renamed, last_connected_at, created_at) '
            "VALUES ('a', 'Mac', '10.0.0.5', '3011', 0, 1, 0, NULL, '2026-09-01T00:00:00.000')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
      onWipe: () async => wipes++,
    );
    addTearDown(db.close);

    expect(await db.desktopDao.getAll(), isEmpty);
    expect(wipes, 1);
    expect(await _tables(db), containsAll(['desktops', 'settings', 'replica_documents', 'replica_block_events']));
    expect(await _userVersion(db), 2);
  });

  test('a fresh install creates every table and clears passwords an earlier install left behind', () async {
    var wipes = 0;
    final db = AppDatabase.forTesting(NativeDatabase.memory(), onWipe: () async => wipes++);
    addTearDown(db.close);

    expect(await _tables(db), containsAll(['desktops', 'settings', 'replica_documents', 'replica_block_events']));
    expect(wipes, 1);
  });

  test('a failing password purge still opens the database', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(),
      onWipe: () async => throw StateError('keychain locked'),
    );
    addTearDown(db.close);

    expect(await db.desktopDao.getAll(), isEmpty);
  });
}
```

Create `test/core/database/tables/settings/settings_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('put then readAll round-trips every row', () async {
    await db.settingsDao.put('theme.mode', 'dark');
    await db.settingsDao.put('session.view.s-1', 'raw');

    expect(await db.settingsDao.readAll(), {'theme.mode': 'dark', 'session.view.s-1': 'raw'});
  });

  test('put overwrites an existing key', () async {
    await db.settingsDao.put('theme.mode', 'dark');
    await db.settingsDao.put('theme.mode', 'light');

    expect(await db.settingsDao.readAll(), {'theme.mode': 'light'});
  });
}
```

Create `test/core/database/tables/replica_document/replica_document_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';

void main() {
  late AppDatabase db;
  late ReplicaDocumentDao dao;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.replicaDocumentDao;
  });

  tearDown(() => db.close());

  test('read returns only the asked keys of that desktop', () async {
    await dao.write('a', {'board.sessions': '{"sessions":[]}', 'board.projects': '{"projects":[]}'}, at);
    await dao.write('b', {'board.sessions': '{"sessions":[1]}'}, at);

    final rows = await dao.read('a', ['board.sessions']);

    expect(rows.single.body, '{"sessions":[]}');
    expect(rows.single.fetchedAt.isAtSameMomentAs(at), isTrue);
  });

  test('write replaces the body and fetchedAt of an existing key', () async {
    await dao.write('a', {'board.sessions': '{"v":1}'}, at);
    final later = at.add(const Duration(minutes: 5));
    await dao.write('a', {'board.sessions': '{"v":2}'}, later);

    final row = (await dao.read('a', ['board.sessions'])).single;

    expect(row.body, '{"v":2}');
    expect(row.fetchedAt.isAtSameMomentAs(later), isTrue);
  });

  test('watch emits the row as it changes', () async {
    final seen = <String?>[];
    final sub = dao.watch('a', 'board.sessions').listen((row) => seen.add(row?.body));
    await pumpEventQueue();

    await dao.write('a', {'board.sessions': '{"sessions":[]}'}, at);
    await pumpEventQueue();

    expect(seen, [null, '{"sessions":[]}']);
    await sub.cancel();
  });

  test('remove deletes only the named keys of that desktop', () async {
    await dao.write('a', {'board.sessions': '{}', 'notifications.first': '{}'}, at);
    await dao.write('b', {'board.sessions': '{}'}, at);

    await dao.remove('a', ['board.sessions']);

    expect((await dao.read('a', ['board.sessions', 'notifications.first'])).map((row) => row.key), ['notifications.first']);
    expect(await dao.read('b', ['board.sessions']), hasLength(1));
  });
}
```

Create `test/core/database/tables/replica_block_event/replica_block_event_dao_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';

Map<int, String> _events(int from, int to) => {for (var seq = from; seq <= to; seq++) seq: '{"seq":$seq}'};

void main() {
  late AppDatabase db;
  late ReplicaBlockEventDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.replicaBlockEventDao;
  });

  tearDown(() => db.close());

  test('latest returns the session rows oldest first', () async {
    await dao.write('a', 's', {3: '{"seq":3}', 1: '{"seq":1}', 2: '{"seq":2}'});

    expect((await dao.latest('a', 's')).map((row) => row.seq), [1, 2, 3]);
  });

  test('keeps only the newest 200 events of a session', () async {
    await dao.write('a', 's', _events(1, 250));

    final kept = await dao.latest('a', 's');
    expect(kept, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(kept.first.seq, 51);
    expect(kept.last.seq, 250);

    await dao.write('a', 's', _events(251, 260));

    final after = await dao.latest('a', 's');
    expect(after, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(after.first.seq, 61);
    expect(after.last.seq, 260);
  });

  test('an event older than the kept window is trimmed on the write that adds it', () async {
    await dao.write('a', 's', _events(1, 200));
    await dao.write('a', 's', {0: '{"seq":0}'});

    final kept = await dao.latest('a', 's');
    expect(kept.first.seq, 1);
    expect(kept, hasLength(ReplicaLimits.blockEventsPerSession));
  });

  test('trimming one session leaves other sessions and desktops alone', () async {
    await dao.write('a', 'other', _events(1, 5));
    await dao.write('b', 's', _events(1, 5));
    await dao.write('a', 's', _events(1, 250));

    expect(await dao.latest('a', 'other'), hasLength(5));
    expect(await dao.latest('b', 's'), hasLength(5));
  });

  test('write replaces the body of an existing seq', () async {
    await dao.write('a', 's', {1: '{"seq":1,"text":"old"}'});
    await dao.write('a', 's', {1: '{"seq":1,"text":"new"}'});

    expect((await dao.latest('a', 's')).single.body, '{"seq":1,"text":"new"}');
  });

  test('removeSession deletes that session only', () async {
    await dao.write('a', 's', _events(1, 3));
    await dao.write('a', 't', _events(1, 3));

    await dao.removeSession('a', 's');

    expect(await dao.latest('a', 's'), isEmpty);
    expect(await dao.latest('a', 't'), hasLength(3));
  });
}
```

Append to `test/core/database/tables/desktop/desktop_dao_test.dart`, inside `main()`:

```dart
  test('remove deletes the desktop and every replica row it owns', () async {
    await dao.upsert(_row('a', host: '1.1.1.1'));
    await dao.upsert(_row('b', host: '2.2.2.2'));
    final at = DateTime.utc(2026, 9, 25);
    await db.replicaDocumentDao.write('a', {'board.sessions': '{}'}, at);
    await db.replicaDocumentDao.write('b', {'board.sessions': '{}'}, at);
    await db.replicaBlockEventDao.write('a', 's', {1: '{"seq":1}'});
    await db.replicaBlockEventDao.write('b', 's', {1: '{"seq":1}'});

    await dao.remove('a');

    expect((await dao.getAll()).map((desktop) => desktop.id), ['b']);
    expect(await db.replicaDocumentDao.read('a', ['board.sessions']), isEmpty);
    expect(await db.replicaDocumentDao.read('b', ['board.sessions']), hasLength(1));
    expect(await db.replicaBlockEventDao.latest('a', 's'), isEmpty);
    expect(await db.replicaBlockEventDao.latest('b', 's'), hasLength(1));
  });
```

Append to `test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`, inside `main()`:

```dart
  test('purgePasswords deletes every saved desktop password and nothing else', () async {
    when(() => storage.readAll()).thenAnswer(
      (_) async => {'server.password.a': 'x', 'server.password.b': 'y', 'other': 'z'},
    );

    await DesktopsLocalDataSourceImp.purgePasswords(storage);

    verify(() => storage.delete(key: 'server.password.a')).called(1);
    verify(() => storage.delete(key: 'server.password.b')).called(1);
    verifyNever(() => storage.delete(key: 'other'));
  });
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/database test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`
Expected: FAIL to compile, with errors such as `No named parameter with the name 'onWipe'`, `The getter 'settingsDao' isn't defined` and `Member not found: 'purgePasswords'`.

- [ ] **Step 3: Write the tables, DAOs and the migration.**

Create `lib/core/replica/replica_limits.dart`:

```dart
sealed class ReplicaLimits {
  static const int blockEventsPerSession = 200;
}
```

Create `lib/core/database/tables/settings/settings_table.dart`:

```dart
import 'package:drift/drift.dart';

@DataClassName('SettingEntity')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

Create `lib/core/database/tables/settings/settings_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<Map<String, String>> readAll() async {
    final rows = await select(settings).get().handleLocalFailure();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> put(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value))
      .handleLocalFailure();
}
```

Create `lib/core/database/tables/replica_document/replica_document_table.dart`:

```dart
import 'package:drift/drift.dart';

@DataClassName('ReplicaDocumentEntity')
class ReplicaDocuments extends Table {
  TextColumn get desktopId => text()();
  TextColumn get key => text()();
  TextColumn get body => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {desktopId, key};
}
```

Create `lib/core/database/tables/replica_document/replica_document_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'replica_document_dao.g.dart';

@DriftAccessor(tables: [ReplicaDocuments])
class ReplicaDocumentDao extends DatabaseAccessor<AppDatabase> with _$ReplicaDocumentDaoMixin {
  ReplicaDocumentDao(super.db);

  Future<List<ReplicaDocumentEntity>> read(String desktopId, List<String> keys) =>
      (select(replicaDocuments)..where((t) => t.desktopId.equals(desktopId) & t.key.isIn(keys)))
          .get()
          .handleLocalFailure();

  Stream<ReplicaDocumentEntity?> watch(String desktopId, String key) =>
      (select(replicaDocuments)..where((t) => t.desktopId.equals(desktopId) & t.key.equals(key)))
          .watchSingleOrNull()
          .handleLocalFailure();

  Future<void> write(String desktopId, Map<String, String> bodies, DateTime fetchedAt) => batch((batch) {
    batch.insertAllOnConflictUpdate(replicaDocuments, [
      for (final entry in bodies.entries)
        ReplicaDocumentsCompanion.insert(desktopId: desktopId, key: entry.key, body: entry.value, fetchedAt: fetchedAt),
    ]);
  }).handleLocalFailure();

  Future<void> remove(String desktopId, List<String> keys) =>
      (delete(replicaDocuments)..where((t) => t.desktopId.equals(desktopId) & t.key.isIn(keys)))
          .go()
          .handleLocalFailure();
}
```

Create `lib/core/database/tables/replica_block_event/replica_block_event_table.dart`:

```dart
import 'package:drift/drift.dart';

@DataClassName('ReplicaBlockEventEntity')
class ReplicaBlockEvents extends Table {
  TextColumn get desktopId => text()();
  TextColumn get sessionId => text()();
  IntColumn get seq => integer()();
  TextColumn get body => text()();

  @override
  Set<Column> get primaryKey => {desktopId, sessionId, seq};
}
```

Create `lib/core/database/tables/replica_block_event/replica_block_event_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';

part 'replica_block_event_dao.g.dart';

@DriftAccessor(tables: [ReplicaBlockEvents])
class ReplicaBlockEventDao extends DatabaseAccessor<AppDatabase> with _$ReplicaBlockEventDaoMixin {
  ReplicaBlockEventDao(super.db);

  Future<List<ReplicaBlockEventEntity>> latest(String desktopId, String sessionId) async {
    final newestFirst = await (select(replicaBlockEvents)
          ..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.seq)])
          ..limit(ReplicaLimits.blockEventsPerSession))
        .get()
        .handleLocalFailure();
    return newestFirst.reversed.toList();
  }

  Future<void> write(String desktopId, String sessionId, Map<int, String> bodies) => transaction(() async {
    if (bodies.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(replicaBlockEvents, [
        for (final entry in bodies.entries)
          ReplicaBlockEventsCompanion.insert(
            desktopId: desktopId,
            sessionId: sessionId,
            seq: entry.key,
            body: entry.value,
          ),
      ]);
    });
    final floor = await (select(replicaBlockEvents)
          ..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.seq)])
          ..limit(1, offset: ReplicaLimits.blockEventsPerSession - 1))
        .getSingleOrNull();
    if (floor == null) return;
    await (delete(replicaBlockEvents)
          ..where(
            (t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId) & t.seq.isSmallerThanValue(floor.seq),
          ))
        .go();
  }).handleLocalFailure();

  Future<void> removeSession(String desktopId, String sessionId) =>
      (delete(replicaBlockEvents)..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId)))
          .go()
          .handleLocalFailure();
}
```

Replace `lib/core/database/app_database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_table.dart';
import 'package:operator_mobile/core/helpers/logging/app_logger.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Desktops, Settings, ReplicaDocuments, ReplicaBlockEvents],
  daos: [DesktopDao, SettingsDao, ReplicaDocumentDao, ReplicaBlockEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({Future<void> Function()? onWipe})
    : _onWipe = onWipe,
      super(driftDatabase(name: 'operator_mobile'));

  AppDatabase.forTesting(super.executor, {Future<void> Function()? onWipe}) : _onWipe = onWipe;

  final Future<void> Function()? _onWipe;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _wipeSecrets();
    },
    onUpgrade: (m, from, to) async {
      for (final table in allTables) {
        await m.deleteTable(table.actualTableName);
      }
      await m.createAll();
      await _wipeSecrets();
    },
  );

  Future<void> _wipeSecrets() async {
    final wipe = _onWipe;
    if (wipe == null) return;
    try {
      await wipe();
    } catch (error, stackTrace) {
      AppLogger.warning('Could not clear saved desktop passwords', exception: error, stackTrace: stackTrace);
    }
  }

  @override
  DriftDatabaseOptions get options => const DriftDatabaseOptions(storeDateTimeAsText: true);
}
```

In `lib/core/database/tables/desktop/desktop_dao.dart`, add the two replica table imports, widen the accessor, and make `remove` a transaction:

```dart
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
```

```dart
@DriftAccessor(tables: [Desktops, ReplicaDocuments, ReplicaBlockEvents])
```

```dart
  Future<void> remove(String id) => transaction(() async {
    await (delete(replicaDocuments)..where((t) => t.desktopId.equals(id))).go();
    await (delete(replicaBlockEvents)..where((t) => t.desktopId.equals(id))).go();
    await (delete(desktops)..where((t) => t.id.equals(id))).go();
  }).handleLocalFailure();
```

In `lib/feature/pairing/data/data_source/desktops_local_data_source.dart`, replace `static String passwordKey(String id) => 'server.password.$id';` with:

```dart
  static const String _passwordPrefix = 'server.password.';

  static String passwordKey(String id) => '$_passwordPrefix$id';

  static Future<void> purgePasswords(FlutterSecureStorage storage) async {
    final entries = await storage.readAll();
    for (final key in entries.keys) {
      if (key.startsWith(_passwordPrefix)) await storage.delete(key: key);
    }
  }
```

In `lib/core/utils/service_locator.dart`, replace the two lines at `:87-88` with:

```dart
    sl.registerLazySingleton<AppDatabase>(
      () => AppDatabase(onWipe: () => DesktopsLocalDataSourceImp.purgePasswords(sl<FlutterSecureStorage>())),
    );
    sl.registerLazySingleton<DesktopDao>(() => DesktopDao(sl<AppDatabase>()));
    sl.registerLazySingleton<SettingsDao>(() => SettingsDao(sl<AppDatabase>()));
    sl.registerLazySingleton<ReplicaDocumentDao>(() => ReplicaDocumentDao(sl<AppDatabase>()));
    sl.registerLazySingleton<ReplicaBlockEventDao>(() => ReplicaBlockEventDao(sl<AppDatabase>()));
```

and add the three DAO imports:

```dart
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
```

- [ ] **Step 4: Generate the drift code.**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: it ends with `Built with build_runner` and writes `settings_dao.g.dart`, `replica_document_dao.g.dart`, `replica_block_event_dao.g.dart`, and rewrites `app_database.g.dart` and `desktop_dao.g.dart`.

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `flutter test test/core/database test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`
Expected: PASS.

- [ ] **Step 6: Gate.**

Run: `flutter analyze` → `No issues found!`. Run: `flutter test` → all pass.

- [ ] **Step 7: Commit.**

```bash
git add lib/core/replica/replica_limits.dart lib/core/database test/core/database \
  lib/feature/pairing/data/data_source/desktops_local_data_source.dart \
  test/feature/pairing/data/data_source/desktops_local_data_source_test.dart \
  lib/core/utils/service_locator.dart
git commit -m "$(cat <<'MSG'
feat(mobile): drift schema v2 with settings and replica tables, wiped on upgrade

The upgrade drops every table and purges the Keychain passwords the
desktops table pointed at. Deleting a desktop removes its replica rows in
the same transaction. Chat rows are capped at 200 per session.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: `ServerConfig` carries the active desktop's id

**Files:**
- Modify: `packages/mobile/lib/core/api/server_config.dart`
- Modify: `packages/mobile/lib/feature/pairing/data/model/desktop_model.dart:26-27`
- Modify: `packages/mobile/lib/feature/pairing/data/repository/pairing_repository.dart:22-42`
- Test: modify `test/core/api/server_config_test.dart`, `test/core/api/server_config_store_test.dart`, `test/feature/pairing/data/repository/pairing_repository_test.dart`, `test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `const ServerConfig({required String host, required String httpPort, required bool secure, required String password, String? desktopId})`, with `desktopId` in `props`. `DesktopModel.toServerConfig(password)` sets `desktopId: id`. `ServerConfigStore.current?.desktopId` is the active desktop's id after `load()`, after pairing and after `ConnectionsCubit.connectTo`.

- [ ] **Step 1: Write the failing tests.**

Append to `test/core/api/server_config_test.dart`, inside `main()`:

```dart
  test('two configs for different desktops are not equal', () {
    const a = ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'a');
    const b = ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'b');

    expect(a == b, isFalse);
  });
```

In `test/core/api/server_config_store_test.dart`, change the expectation of `load resolves the active desktop and its password into current` to:

```dart
    expect(
      store.current,
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a'),
    );
```

In `test/feature/pairing/data/repository/pairing_repository_test.dart`, add below `_saved`:

```dart
const _savedConfig = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
  desktopId: 'a',
);
```

and in `identifies, saves with the daemon name, then sets the active config`, change `() => store.set(_target),` to `() => store.set(_savedConfig),`.

In `test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart`, change `_config` to carry desktop `a`'s id (every use of `_config` in that file is desktop `a`):

```dart
const _config = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a');
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/api test/feature/pairing`
Expected: FAIL to compile with `No named parameter with the name 'desktopId'`.

- [ ] **Step 3: Implement.**

`lib/core/api/server_config.dart`:

```dart
import 'package:equatable/equatable.dart';

class ServerConfig extends Equatable {
  const ServerConfig({
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
    this.desktopId,
  });

  final String host;
  final String httpPort;
  final bool secure;
  final String password;
  final String? desktopId;

  String get httpBase => '${secure ? 'https' : 'http'}://$host:$httpPort';

  String get wsBase => '${secure ? 'wss' : 'ws'}://$host:$httpPort';

  @override
  List<Object?> get props => [host, httpPort, secure, password, desktopId];
}

bool hasServer(ServerConfig? server) => (server?.host.trim() ?? '').isNotEmpty;
```

`lib/feature/pairing/data/model/desktop_model.dart`, replace `toServerConfig`:

```dart
  ServerConfig toServerConfig(String password) => ServerConfig(
    host: host ?? '',
    httpPort: port ?? '',
    secure: secure ?? false,
    password: password,
    desktopId: id,
  );
```

`lib/feature/pairing/data/repository/pairing_repository.dart`, replace the body of `verifyAndConnect`'s `try` block:

```dart
      final identity = await _remote.identify(target);
      final name = identity.name?.trim();
      final saved = await _desktops.save(
        SaveDesktopParams(
          name: name == null || name.isEmpty ? '${target.host}:${target.httpPort}' : name,
          host: target.host,
          port: target.httpPort,
          secure: target.secure,
          password: target.password,
        ),
      );
      final desktop = saved.valueOrNull;
      if (desktop != null) _store.set(desktop.toServerConfig(target.password));
      return saved;
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/core/api test/feature/pairing`
Expected: PASS.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Commit.**

```bash
git add lib/core/api/server_config.dart lib/feature/pairing/data/model/desktop_model.dart \
  lib/feature/pairing/data/repository/pairing_repository.dart test/core/api/server_config_test.dart \
  test/core/api/server_config_store_test.dart test/feature/pairing/data/repository/pairing_repository_test.dart \
  test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): carry the active desktop's id on ServerConfig

Pairing now sets the saved desktop's config rather than the bare verify
target, so every consumer can scope local state by desktop. Ported
expectations in server_config_store_test, pairing_repository_test and
connections_cubit_test to include the id.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: `AppPreferences` replaces `CacheHelper`, and the project filter is per desktop

**Files:**
- Create: `packages/mobile/lib/core/preferences/preference_keys.dart`, `app_preferences.dart`
- Delete: `packages/mobile/lib/core/helpers/cache/cache_helper.dart`, `cache_keys.dart`
- Modify: `packages/mobile/lib/core/app_themes/colors/logic/skin_cubit.dart`
- Modify: `packages/mobile/lib/core/telemetry/runtime.dart:28-36`, `:78-110`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart:24-57`, `:96-115`
- Modify: `packages/mobile/lib/main.dart:27-31`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:60`, `:80-82`
- Modify: `packages/mobile/pubspec.yaml` (drop `shared_preferences: ^2.5.5`), `pubspec.lock`
- Test: create `test/core/preferences/app_preferences_test.dart`, `test/core/no_shared_preferences_test.dart`; port the 14 files listed in Step 4; add a test to `test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`

**Interfaces:**
- Consumes: `SettingsDao.readAll()`, `SettingsDao.put()` (Task 1); `ServerConfig.desktopId` (Task 2).
- Produces:
  - `sealed class PreferenceKeys { themeMode = 'theme.mode'; telemetryRateLimit = 'telemetry.rateLimit'; static String activeProject(String desktopId) => 'board.activeProject.$desktopId'; static String sessionView(String key) => 'session.view.$key'; }`
  - `sealed class AppPreferences` with `static Future<void> load(SettingsDao dao)`, `@visibleForTesting static void debugLoad(Map<String, String> values, {SettingsDao? dao})`, `static Future<void> flush()`, `static ThemeMode? get themeMode`, `static void setThemeMode(ThemeMode mode)`, `static String? activeProjectId(String desktopId)`, `static void setActiveProjectId(String desktopId, String projectId)`, `static String? sessionView(String key)`, `static void setSessionView(String key, String mode)`, `static String? get telemetryRateLimit`, `static void setTelemetryRateLimit(String value)`, `static String? string(String key)`, `static Future<void> setString(String key, String value)`
  - `PreferencesActiveStorage` replaces `CacheActiveStorage` in `runtime.dart`.
  - `SessionsCubit` reads and writes `activeProjectId` under the active desktop's id; a desktop switch reloads it.

- [ ] **Step 1: Write the failing tests.**

Create `test/core/preferences/app_preferences_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';

class _FlakyDao extends SettingsDao {
  _FlakyDao(super.db);

  int failures = 1;

  @override
  Future<void> put(String key, String value) {
    if (failures > 0) {
      failures--;
      return Future<void>.error(LocalFailure<void>(error: 'disk full'));
    }
    return super.put(key, value);
  }
}

class _UnreadableDao extends SettingsDao {
  _UnreadableDao(super.db);

  @override
  Future<Map<String, String>> readAll() => Future<Map<String, String>>.error(LocalFailure<void>(error: 'corrupt'));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  tearDown(() async {
    AppPreferences.debugLoad(const {});
    await db.close();
  });

  test('load reads every row, then answers synchronously', () async {
    await db.settingsDao.put(PreferenceKeys.themeMode, 'dark');
    await db.settingsDao.put(PreferenceKeys.sessionView('s-1'), 'raw');

    await AppPreferences.load(db.settingsDao);

    expect(AppPreferences.themeMode, ThemeMode.dark);
    expect(AppPreferences.sessionView('s-1'), 'raw');
  });

  test('each typed accessor writes under its own key', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setThemeMode(ThemeMode.system);
    AppPreferences.setActiveProjectId('d-1', 'p-1');
    AppPreferences.setSessionView('s-1', 'blocks');
    AppPreferences.setTelemetryRateLimit('{}');
    await AppPreferences.setString('opr.telemetry.day', '2026-09-25');
    await AppPreferences.flush();

    expect(await db.settingsDao.readAll(), {
      'theme.mode': 'system',
      'board.activeProject.d-1': 'p-1',
      'session.view.s-1': 'blocks',
      'telemetry.rateLimit': '{}',
      'opr.telemetry.day': '2026-09-25',
    });
    expect(AppPreferences.telemetryRateLimit, '{}');
    expect(AppPreferences.string('opr.telemetry.day'), '2026-09-25');
  });

  test('the active project is remembered per desktop', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setActiveProjectId('d-1', 'p-1');

    expect(AppPreferences.activeProjectId('d-1'), 'p-1');
    expect(AppPreferences.activeProjectId('d-2'), isNull);
  });

  test('an unknown theme value reads as unset', () {
    AppPreferences.debugLoad({PreferenceKeys.themeMode: 'sepia'});

    expect(AppPreferences.themeMode, isNull);
  });

  test('writes reach memory at once and drift in order, so a reload after flush sees the last value', () async {
    await AppPreferences.load(db.settingsDao);

    AppPreferences.setThemeMode(ThemeMode.dark);
    AppPreferences.setThemeMode(ThemeMode.light);
    expect(AppPreferences.themeMode, ThemeMode.light);
    await AppPreferences.flush();

    AppPreferences.debugLoad(const {});
    await AppPreferences.load(db.settingsDao);
    expect(AppPreferences.themeMode, ThemeMode.light);
  });

  test('a failed write keeps the value in memory and does not block later writes', () async {
    final flaky = _FlakyDao(db);
    AppPreferences.debugLoad(const {}, dao: flaky);

    AppPreferences.setThemeMode(ThemeMode.dark);
    AppPreferences.setSessionView('s-1', 'raw');
    await AppPreferences.flush();

    expect(AppPreferences.themeMode, ThemeMode.dark);
    expect(await db.settingsDao.readAll(), {'session.view.s-1': 'raw'});
  });

  test('an unreadable store loads as empty instead of failing launch', () async {
    await AppPreferences.load(_UnreadableDao(db));

    expect(AppPreferences.themeMode, isNull);
  });
}
```

Create `test/core/no_shared_preferences_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-party code keeps no key-value store beside drift', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('package:shared_preferences/') || source.contains('cache_helper.dart')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'drift is the only local store: settings go through AppPreferences, and the Keychain holds '
          'passwords only. Offenders: $offenders',
    );
  });
}
```

Append to `test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`, inside `main()`:

```dart
  test('remembers the project filter per desktop', () async {
    AppPreferences.debugLoad({PreferenceKeys.activeProject('d-a'): 'p2'});
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
    );
    source.current = const ServerConfig(
      host: '10.0.0.5',
      httpPort: '3011',
      secure: false,
      password: 'pw',
      desktopId: 'd-a',
    );

    final cubit = SessionsCubit(repository, mux, source);
    expect(cubit.activeProjectId, 'p2');

    source.set(const ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-b'));
    expect(cubit.activeProjectId, kAllProjects);

    cubit.setActiveProject('p9');
    expect(AppPreferences.activeProjectId('d-b'), 'p9');
    expect(AppPreferences.activeProjectId('d-a'), 'p2');
    await cubit.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/preferences test/core/no_shared_preferences_test.dart test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`
Expected: FAIL. The first and third files fail to compile (`app_preferences.dart` not found). The guard test fails listing `lib/main.dart`, `skin_cubit.dart`, `runtime.dart`, `session_view_cubit.dart`, `sessions_cubit.dart`, `service_locator.dart` and the two cache files.

- [ ] **Step 3: Implement `AppPreferences` and move every caller.**

Create `lib/core/preferences/preference_keys.dart`:

```dart
sealed class PreferenceKeys {
  static const String themeMode = 'theme.mode';
  static const String telemetryRateLimit = 'telemetry.rateLimit';

  static String activeProject(String desktopId) => 'board.activeProject.$desktopId';

  static String sessionView(String key) => 'session.view.$key';
}
```

Create `lib/core/preferences/app_preferences.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';

sealed class AppPreferences {
  static final Map<String, String> _values = {};
  static SettingsDao? _dao;
  static Future<void> _writes = Future<void>.value();

  static Future<void> load(SettingsDao dao) async {
    _dao = dao;
    _values.clear();
    try {
      _values.addAll(await dao.readAll());
    } on Failure {
      return;
    }
  }

  @visibleForTesting
  static void debugLoad(Map<String, String> values, {SettingsDao? dao}) {
    _dao = dao;
    _writes = Future<void>.value();
    _values
      ..clear()
      ..addAll(values);
  }

  static Future<void> flush() => _writes;

  static ThemeMode? get themeMode {
    final saved = _values[PreferenceKeys.themeMode];
    for (final mode in ThemeMode.values) {
      if (mode.name == saved) return mode;
    }
    return null;
  }

  static void setThemeMode(ThemeMode mode) => _write(PreferenceKeys.themeMode, mode.name);

  static String? activeProjectId(String desktopId) => _values[PreferenceKeys.activeProject(desktopId)];

  static void setActiveProjectId(String desktopId, String projectId) =>
      _write(PreferenceKeys.activeProject(desktopId), projectId);

  static String? sessionView(String key) => _values[PreferenceKeys.sessionView(key)];

  static void setSessionView(String key, String mode) => _write(PreferenceKeys.sessionView(key), mode);

  static String? get telemetryRateLimit => _values[PreferenceKeys.telemetryRateLimit];

  static void setTelemetryRateLimit(String value) => _write(PreferenceKeys.telemetryRateLimit, value);

  static String? string(String key) => _values[key];

  static Future<void> setString(String key, String value) {
    _write(key, value);
    return _writes;
  }

  static void _write(String key, String value) {
    _values[key] = value;
    final dao = _dao;
    if (dao == null) return;
    _writes = _writes.then((_) => dao.put(key, value)).catchError((Object _) {});
  }
}
```

Replace `lib/core/app_themes/colors/logic/skin_cubit.dart`'s import of `cache_helper.dart` with `import 'package:operator_mobile/core/preferences/app_preferences.dart';`, and replace `_savedSkin`, `setSkin` and `setSystemSkin`:

```dart
  static AppSkin _savedSkin() {
    final saved = AppPreferences.themeMode;
    if (saved == ThemeMode.dark) return const DarkSkin();
    if (saved == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
          ? const DarkSkin()
          : const LightSkin();
    }
    return const LightSkin();
  }

  void setSkin(AppSkin newSkin) {
    skin = newSkin;
    AppPreferences.setThemeMode(newSkin.themeMode);
    emit(SkinChangedState(newSkin));
  }
```

```dart
  void setSystemSkin() {
    skin = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        ? const DarkSkin()
        : const LightSkin();
    AppPreferences.setThemeMode(ThemeMode.system);
    emit(SkinChangedState(skin));
  }
```

In `lib/core/telemetry/runtime.dart`, swap the `cache_helper.dart` import for `app_preferences.dart`, replace `CacheActiveStorage` (`:28-36`) with:

```dart
class PreferencesActiveStorage implements ActiveStorage {
  const PreferencesActiveStorage();

  @override
  Future<String?> getItem(String key) async => AppPreferences.string(key);

  @override
  Future<void> setItem(String key, String value) => AppPreferences.setString(key, value);
}
```

change `active` to `await _telemetry?.active(const PreferencesActiveStorage(), now);`, the first line of `_loadRateState`'s read to `final raw = AppPreferences.telemetryRateLimit;`, and the write in `_allowEvent` to:

```dart
    AppPreferences.setTelemetryRateLimit(
      jsonEncode(_rateState.map((name, window) => MapEntry(name, window.toJson()))),
    );
```

In `lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`, swap the import for `app_preferences.dart`, and change `persistedViewMode`'s read to `final saved = AppPreferences.sessionView(key);` and `toggle`'s write to `if (key != null && key.isNotEmpty) AppPreferences.setSessionView(key, next.name);`.

In `lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`, swap the import for `app_preferences.dart`. Start the constructor body with the desktop's filter, replace the `activeProjectId` field and `setActiveProject`, and reload the filter in `_onConfigChanged`:

```dart
  SessionsCubit(this._repository, this._muxClient, this._configSource) : super(const SessionsInitialState()) {
    _desktopId = _configSource.current?.desktopId;
    activeProjectId = _savedProject(_desktopId);
    _muxSub = _muxClient.boardChanges.listen((_) {
```

```dart
  String activeProjectId = kAllProjects;
  String? _desktopId;

  static String _savedProject(String? desktopId) =>
      desktopId == null ? kAllProjects : AppPreferences.activeProjectId(desktopId) ?? kAllProjects;

  List<SessionModel> get visibleSessions => activeProjectId == kAllProjects
      ? sessions
      : sessions.where((s) => s.projectId == activeProjectId).toList();

  void setActiveProject(String id) {
    activeProjectId = id;
    final desktopId = _desktopId;
    if (desktopId != null) AppPreferences.setActiveProjectId(desktopId, id);
    _emitSessions();
  }
```

and in `_onConfigChanged`, right after `projects = [];`:

```dart
    _desktopId = next?.desktopId;
    activeProjectId = _savedProject(_desktopId);
```

In `lib/main.dart`, replace lines `:30-31` (`await CacheHelper.init();` then `await ServiceLocator.init();`) with:

```dart
  await ServiceLocator.init();
  await AppPreferences.load(sl<SettingsDao>());
```

and swap the `cache_helper.dart` import for `app_preferences.dart` plus `package:operator_mobile/core/database/tables/settings/settings_dao.dart`.

In `lib/core/utils/service_locator.dart`, delete the `shared_preferences` import (`:60`) and the two SharedPreferences lines at the top of `_coreSetup` (`:81-82`).

Delete `lib/core/helpers/cache/cache_helper.dart` and `lib/core/helpers/cache/cache_keys.dart`. In `pubspec.yaml`, delete the line `  shared_preferences: ^2.5.5`, then run `flutter pub get`.

- [ ] **Step 4: Port the tests that seeded SharedPreferences.** Same assertions, new store.

In each of these files, replace the two lines

```dart
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
```

with `AppPreferences.debugLoad(const {});`. Remove the `package:shared_preferences/shared_preferences.dart` and `cache_helper.dart` imports, and add `import 'package:operator_mobile/core/preferences/app_preferences.dart';`:

`test/core/app_themes/skin_cubit_test.dart`, `test/core/utils/service_locator_test.dart`, `test/core/app_routes/home_shell_test.dart`, `test/core/telemetry/call_sites_test.dart`, `test/core/telemetry/runtime_test.dart`, `test/feature/blocks/presentation/session_view_test.dart`, `test/feature/settings/presentation/settings_screen/logic/settings_cubit_test.dart`, `test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart`, `test/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_body_test.dart`, `test/feature/sessions/presentation/sessions_screen/ui/session_actions_sheet_test.dart`, `test/feature/sessions/presentation/session_route/session_route_screen_test.dart`, `test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`, `test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`, `test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart`.

Three tests seeded a value; port them like this, and add `import 'package:operator_mobile/core/preferences/preference_keys.dart';` to their files:

- `test/core/telemetry/runtime_test.dart`, `seeds the daily ceiling from persisted state…`: replace the `SharedPreferences.setMockInitialValues({CacheKeys.telemetryRateLimit: jsonEncode({...})}); await CacheHelper.init();` pair with `AppPreferences.debugLoad({PreferenceKeys.telemetryRateLimit: jsonEncode({...})});`, keeping the same `NameWindow` map.
- `test/feature/blocks/presentation/session_view_test.dart`, `ignores an unknown saved value`: replace its pair with `AppPreferences.debugLoad({PreferenceKeys.sessionView('s-9'): 'sideways'});`.
- `test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`, `names the project a persisted filter is pinned to`: the filter is now per desktop, so the board needs one. Replace `_StubConfigSource` with

```dart
class _StubConfigSource implements ServerConfigSource {
  const _StubConfigSource([this.current]);

  @override
  final ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}
```

  give `pumpBody` a parameter `{ServerConfigSource source = const _StubConfigSource()}` and build `SessionsCubit(repository, mux, source)` with it. Then replace the test's first two lines with:

```dart
      AppPreferences.debugLoad({PreferenceKeys.activeProject('d-1'): 'scratch'});
```

  and pass `source: const _StubConfigSource(ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1'))` to its `pumpBody` call. The three `expect`s stay as they are.

In `sessions_cubit_test.dart`, also add `import 'package:operator_mobile/core/preferences/preference_keys.dart';` for the new test.

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `flutter test test/core/preferences test/core/no_shared_preferences_test.dart test/core/app_themes test/core/telemetry test/feature/blocks/presentation/session_view_test.dart test/feature/sessions test/feature/settings test/feature/spawn test/feature/pull_request test/core/app_routes test/core/utils`
Expected: PASS.

- [ ] **Step 6: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass. Also run `grep -n "shared_preferences:" pubspec.lock -A2 | head -3` and confirm `dependency: transitive`.

- [ ] **Step 7: Commit.**

```bash
git add lib/core/preferences lib/core/helpers/cache lib/core/app_themes/colors/logic/skin_cubit.dart \
  lib/core/telemetry/runtime.dart lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart \
  lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart lib/main.dart \
  lib/core/utils/service_locator.dart pubspec.yaml pubspec.lock test/core/preferences \
  test/core/no_shared_preferences_test.dart test/core/app_themes/skin_cubit_test.dart \
  test/core/utils/service_locator_test.dart test/core/app_routes/home_shell_test.dart \
  test/core/telemetry test/feature/blocks/presentation/session_view_test.dart test/feature/settings \
  test/feature/pull_request test/feature/sessions test/feature/spawn
git commit -m "$(cat <<'MSG'
feat(mobile): keep settings in drift through AppPreferences

AppPreferences loads every settings row at launch so reads stay
synchronous, and writes go to memory at once and to drift in order.
CacheHelper, CacheKeys and the direct shared_preferences dependency are
gone. The board's project filter is now remembered per desktop. Ported the
SharedPreferences seeding in 14 test files to AppPreferences.debugLoad,
with the same assertions.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: Board replica: the last known board, then fresh data

**Files:**
- Create: `packages/mobile/lib/core/replica/replicated.dart`, `replica_keys.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/board_payload.dart`
- Create: `packages/mobile/lib/feature/sessions/data/data_source/sessions_local_data_source.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/model/board_snapshot.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/repository/sessions_repository.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`, `sessions_state.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:40-52`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_sessionsFeatureSetup`)
- Test: create `test/feature/sessions/data/model/board_snapshot_test.dart`, `test/feature/sessions/data/data_source/sessions_local_data_source_test.dart`; rewrite `test/feature/sessions/data/repository/sessions_repository_test.dart`; port `test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`; add tests to `sessions_cubit_test.dart` and `session_route_screen_test.dart`; add a `cachedBoard` stub to the 7 other files that build a `SessionsCubit` (Step 4)

**Interfaces:**
- Consumes: `ReplicaDocumentDao` (Task 1), `ServerConfig.desktopId` (Task 2).
- Produces:
  - `class Replicated<T> extends Equatable { const Replicated({required T value, required DateTime fetchedAt}); final T value; final DateTime fetchedAt; }`
  - `sealed class ReplicaKeys { boardSessions = 'board.sessions'; boardProjects = 'board.projects'; boardAccounts = 'board.accounts'; notificationsFirst = 'notifications.first'; static const List<String> board = [...three board keys] }`
  - `class BoardPayload extends Equatable { const BoardPayload({required Map<String, dynamic> sessions, Map<String, dynamic>? projects, Map<String, dynamic>? accounts}); }`
  - `factory BoardSnapshot.fromPayload(BoardPayload payload)` (the one parse path, network or drift)
  - `SessionsRemoteDataSource.getBoard()` now returns `Future<BoardPayload>`
  - `SessionsLocalDataSource`: `Future<Replicated<BoardPayload>?> readBoard(String desktopId)`, `Future<void> writeBoard(String desktopId, BoardPayload payload, DateTime fetchedAt)`, `Future<void> deleteBoard(String desktopId)`
  - `SessionsRepository`: adds `Future<Replicated<BoardSnapshot>?> cachedBoard()`; `getBoard()` keeps its signature and writes the replica on success. Constructor: `SessionsRepositoryImp(SessionsRemoteDataSource remote, NetworkStatus network, SessionsLocalDataSource local, ServerConfigSource config, {DateTime Function()? clock})`
  - `SessionsCubit`: `DateTime? boardFetchedAt`, `bool boardIsCached`, `Future<void> get cacheReady`, and constructor `SessionsCubit(repository, mux, config, {DateTime Function()? clock})`
  - `GetSessionsSuccessState(int revision, {bool fromCache = false})` with `fromCache` in `props`

- [ ] **Step 1: Write the failing tests.**

Create `test/feature/sessions/data/model/board_snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

void main() {
  test('fromPayload maps sessions, projects and account labels', () {
    final board = BoardSnapshot.fromPayload(
      const BoardPayload(
        sessions: {
          'sessions': [
            {'id': 'w-1', 'projectId': 'p'},
          ],
        },
        projects: {
          'projects': [
            {'id': 'p', 'name': 'Proj'},
          ],
        },
        accounts: {
          'accounts': [
            {'id': 'default', 'label': 'Default'},
            {'id': 'bare'},
          ],
        },
      ),
    );

    expect(board.sessions.single.id, 'w-1');
    expect(board.projects.single.name, 'Proj');
    expect(board.accountLabels, {'default': 'Default', 'bare': 'bare'});
  });

  test('missing or malformed projects and accounts degrade to empty', () {
    final board = BoardSnapshot.fromPayload(
      const BoardPayload(sessions: {'sessions': []}, projects: {'projects': 'nope'}),
    );

    expect(board.projects, isEmpty);
    expect(board.accountLabels, isEmpty);
  });

  test('malformed sessions throw so the caller can drop the body', () {
    expect(
      () => BoardSnapshot.fromPayload(const BoardPayload(sessions: {'sessions': 'nope'})),
      throwsA(isA<TypeError>()),
    );
  });
}
```

Create `test/feature/sessions/data/data_source/sessions_local_data_source_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

void main() {
  late AppDatabase db;
  late SessionsLocalDataSourceImp source;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = SessionsLocalDataSourceImp(db.replicaDocumentDao);
  });

  tearDown(() => db.close());

  test('writeBoard then readBoard round-trips the three bodies and when they were fetched', () async {
    const payload = BoardPayload(
      sessions: {'sessions': [{'id': 'w-1'}]},
      projects: {'projects': [{'id': 'p'}]},
      accounts: {'accounts': [{'id': 'default'}]},
    );

    await source.writeBoard('a', payload, at);
    final stored = await source.readBoard('a');

    expect(stored!.value, payload);
    expect(stored.fetchedAt.isAtSameMomentAs(at), isTrue);
  });

  test('a desktop with nothing stored reads as a miss', () async {
    expect(await source.readBoard('a'), isNull);
  });

  test('a write without projects keeps the projects stored earlier', () async {
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': []}, projects: {'projects': [{'id': 'p'}]}), at);
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': [{'id': 'w-2'}]}), at);

    final stored = await source.readBoard('a');

    expect(stored!.value.projects, {'projects': [{'id': 'p'}]});
    expect(stored.value.sessions, {'sessions': [{'id': 'w-2'}]});
  });

  test('deleteBoard removes every board body of that desktop', () async {
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': []}, projects: {'projects': []}), at);

    await source.deleteBoard('a');

    expect(await source.readBoard('a'), isNull);
  });

  test('a body that is not JSON throws for the repository to drop', () async {
    await db.replicaDocumentDao.write('a', {'board.sessions': 'not json'}, at);

    expect(() => source.readBoard('a'), throwsA(isA<FormatException>()));
  });
}
```

Replace `test/feature/sessions/data/repository/sessions_repository_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

class _MockSessionsRemoteDataSource extends Mock implements SessionsRemoteDataSource {}

class _MockSessionsLocalDataSource extends Mock implements SessionsLocalDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = _desktopA;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

const _desktopA = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a');
const _desktopB = ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'pw', desktopId: 'b');

const _payload = BoardPayload(
  sessions: {
    'sessions': [
      {'id': 'proj-1'},
    ],
  },
  accounts: {
    'accounts': [
      {'id': 'default', 'label': 'Default'},
    ],
  },
);

void main() {
  late _MockSessionsRemoteDataSource dataSource;
  late _MockSessionsLocalDataSource local;
  late _MockNetworkStatus network;
  late _Config config;
  late SessionsRepositoryImp repository;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUpAll(() {
    registerFallbackValue(const BoardPayload(sessions: {}));
    registerFallbackValue(DateTime.utc(2026));
  });

  setUp(() {
    dataSource = _MockSessionsRemoteDataSource();
    local = _MockSessionsLocalDataSource();
    network = _MockNetworkStatus();
    config = _Config();
    repository = SessionsRepositoryImp(dataSource, network, local, config, clock: () => at);
    when(() => local.writeBoard(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteBoard(any())).thenAnswer((_) async {});
  });

  test('fails fast with noNetwork when the daemon is unreachable', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getBoard();

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getBoard());
  });

  test('returns the board snapshot on success', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);

    final result = await repository.getBoard();

    expect(result.isSuccess, isTrue);
    result.when(
      onSuccess: (r) => expect(r.data!.sessions.single.id, 'proj-1'),
      onFailure: (_) => fail('expected success'),
    );
  });

  test('stores the payload under the active desktop after a successful fetch', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);

    await repository.getBoard();

    verify(() => local.writeBoard('a', _payload, at)).called(1);
  });

  test('drops the write when the desktop changed while the fetch was in flight', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async {
      config.current = _desktopB;
      return _payload;
    });

    await repository.getBoard();

    verifyNever(() => local.writeBoard(any(), any(), any()));
  });

  test('a failed write still returns the fresh board', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);
    when(() => local.writeBoard(any(), any(), any())).thenThrow(LocalFailure<void>(error: 'disk full'));

    final result = await repository.getBoard();

    expect(result.isSuccess, isTrue);
  });

  test('a network body that does not parse is a failure and is not stored', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => const BoardPayload(sessions: {'sessions': 'nope'}));

    final result = await repository.getBoard();

    expect(result.isFailure, isTrue);
    verifyNever(() => local.writeBoard(any(), any(), any()));
  });

  test('cachedBoard parses the active desktop replica through the same model', () async {
    when(() => local.readBoard('a')).thenAnswer((_) async => Replicated(value: _payload, fetchedAt: at));

    final cached = await repository.cachedBoard();

    expect(cached!.value.sessions.single.id, 'proj-1');
    expect(cached.value.accountLabels, {'default': 'Default'});
    expect(cached.fetchedAt, at);
  });

  test('cachedBoard misses without an active desktop', () async {
    config.current = null;

    expect(await repository.cachedBoard(), isNull);
    verifyNever(() => local.readBoard(any()));
  });

  test('a replica that no longer parses is deleted and read as a miss', () async {
    when(() => local.readBoard('a')).thenAnswer(
      (_) async => Replicated(value: const BoardPayload(sessions: {'sessions': 'nope'}), fetchedAt: at),
    );

    expect(await repository.cachedBoard(), isNull);
    verify(() => local.deleteBoard('a')).called(1);
  });

  test('a replica that is not JSON is deleted and read as a miss', () async {
    when(() => local.readBoard('a')).thenThrow(const FormatException('not json'));

    expect(await repository.cachedBoard(), isNull);
    verify(() => local.deleteBoard('a')).called(1);
  });

  test('a drift read failure is a miss that keeps the row', () async {
    when(() => local.readBoard('a')).thenThrow(LocalFailure<void>(error: 'locked'));

    expect(await repository.cachedBoard(), isNull);
    verifyNever(() => local.deleteBoard(any()));
  });

  test('kill and restore propagate a Failure', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.kill('proj-1')).thenThrow(ServerFailure.noNetwork());

    final result = await repository.kill('proj-1');

    expect(result.isFailure, isTrue);
  });
}
```

Port `test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`. The probe-order test stays exactly as it is. Add `import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';` and change the other two board tests so the same assertions read through the one parser:

```dart
      final board = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(board.accountLabels, {'default': 'Default', 'personal': 'Personal'});

      when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenThrow(Exception('older daemon'));
      final degraded = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(degraded.accountLabels, isEmpty);
```

```dart
      final board = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(board.projects, isEmpty);
```

and add inside `group('getBoard', ...)`:

```dart
    test('returns each body exactly as the daemon sent it', () async {
      when(() => apiConsumer.get(EndPoints.sessions)).thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenThrow(Exception('older daemon'));

      final payload = await dataSource.getBoard();

      expect(payload.sessions, {'sessions': <dynamic>[]});
      expect(payload.projects, {'projects': <dynamic>[]});
      expect(payload.accounts, isNull);
    });
```

Append to `test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`. Add `import 'package:operator_mobile/core/replica/replicated.dart';`, and in `setUp` add `when(() => repository.cachedBoard()).thenAnswer((_) async => null);`. Then, inside `main()`:

```dart
  group('replica', () {
    Replicated<BoardSnapshot> cached(String id) => Replicated(
      value: BoardSnapshot(sessions: [SessionModel(id: id)]),
      fetchedAt: DateTime.utc(2026, 9, 25, 8),
    );

    test('paints the cached board before the network answers, then swaps in the fresh board', () async {
      final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      when(() => repository.cachedBoard()).thenAnswer((_) async => cached('cached'));
      when(() => repository.getBoard()).thenAnswer((_) => gate.future);

      final cubit = SessionsCubit(repository, mux, source);
      await cubit.cacheReady;

      expect(cubit.sessions.single.id, 'cached');
      expect(cubit.boardIsCached, isTrue);
      expect(cubit.boardFetchedAt, DateTime.utc(2026, 9, 25, 8));
      expect(cubit.state, isA<GetSessionsSuccessState>().having((s) => s.fromCache, 'fromCache', isTrue));

      gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'fresh')]))));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.sessions.single.id, 'fresh');
      expect(cubit.boardIsCached, isFalse);
      expect(cubit.state, isA<GetSessionsSuccessState>().having((s) => s.fromCache, 'fromCache', isFalse));
      await cubit.close();
    });

    test('a failed refresh keeps the cached board on screen', () async {
      when(() => repository.cachedBoard()).thenAnswer((_) async => cached('cached'));
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      final cubit = SessionsCubit(repository, mux, source);
      await cubit.cacheReady;
      await Future<void>.delayed(Duration.zero);

      expect(cubit.sessions.single.id, 'cached');
      expect(cubit.boardFetchedAt, DateTime.utc(2026, 9, 25, 8));
      expect(cubit.state, isA<GetSessionsFailureState>());
      await cubit.close();
    });

    test('a cache read that resolves after the fresh board is ignored', () async {
      final read = Completer<Replicated<BoardSnapshot>?>();
      when(() => repository.cachedBoard()).thenAnswer((_) => read.future);
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'fresh')]))),
      );

      final cubit = SessionsCubit(repository, mux, source);
      await Future<void>.delayed(Duration.zero);
      read.complete(cached('stale'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.sessions.single.id, 'fresh');
      expect(cubit.boardIsCached, isFalse);
      await cubit.close();
    });

    test('switching desktops never shows the previous desktop cache', () async {
      final firstRead = Completer<Replicated<BoardSnapshot>?>();
      var reads = 0;
      when(() => repository.cachedBoard()).thenAnswer((_) {
        reads++;
        return reads == 1 ? firstRead.future : Future.value(null);
      });
      when(() => repository.getBoard()).thenAnswer(
        (_) => Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>().future,
      );

      final cubit = SessionsCubit(repository, mux, source);
      source.set(_configB);
      firstRead.complete(cached('from-a'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.sessions, isEmpty);
      expect(cubit.boardFetchedAt, isNull);
      await cubit.close();
    });

    test('a desktop switch paints the new desktop cache', () async {
      var reads = 0;
      when(() => repository.cachedBoard()).thenAnswer((_) async {
        reads++;
        return reads == 1 ? null : cached('from-b');
      });
      when(() => repository.getBoard()).thenAnswer(
        (_) => Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>().future,
      );

      final cubit = SessionsCubit(repository, mux, source);
      await cubit.cacheReady;
      source.set(_configB);
      await cubit.cacheReady;

      expect(cubit.sessions.single.id, 'from-b');
      expect(cubit.boardIsCached, isTrue);
      await cubit.close();
    });
  });
```

In `test/feature/sessions/presentation/session_route/session_route_screen_test.dart`, add `import 'package:operator_mobile/core/replica/replicated.dart';` and `when(() => repository.cachedBoard()).thenAnswer((_) async => null);` to `setUp`. Split `pumpRoute` so its tree can be reused: move its `tester.pumpWidget(...)` call and the two `tester.pump` calls into

```dart
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(
                  create: (_) => SessionsCubit(repository, mux, _StubConfigSource()),
                ),
              ],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }
```

and have `pumpRoute` stub `getBoard` as it does now, then `await pumpScreen(tester);`. Add:

```dart
  testWidgets('a session missing from the cached board waits for the fresh board before saying so', (tester) async {
    final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
    when(() => repository.cachedBoard()).thenAnswer(
      (_) async => Replicated(value: const BoardSnapshot(), fetchedAt: DateTime.utc(2026, 9, 25)),
    );
    when(() => repository.getBoard()).thenAnswer((_) => gate.future);

    await pumpScreen(tester);
    expect(find.text('Session not found.'), findsNothing);

    gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
    await tester.pump();
    await tester.pump();

    expect(find.text('Session not found.'), findsOneWidget);
  });
```

(Add `import 'dart:async';` and the `Failure` import if the file lacks them.)

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/sessions`
Expected: FAIL to compile: `board_payload.dart`, `sessions_local_data_source.dart` and `replicated.dart` not found, and `cachedBoard` is not defined on `SessionsRepository`.

- [ ] **Step 3: Implement.**

Create `lib/core/replica/replicated.dart`:

```dart
import 'package:equatable/equatable.dart';

class Replicated<T> extends Equatable {
  const Replicated({required this.value, required this.fetchedAt});

  final T value;
  final DateTime fetchedAt;

  @override
  List<Object?> get props => [value, fetchedAt];
}
```

Create `lib/core/replica/replica_keys.dart`:

```dart
sealed class ReplicaKeys {
  static const String boardSessions = 'board.sessions';
  static const String boardProjects = 'board.projects';
  static const String boardAccounts = 'board.accounts';
  static const String notificationsFirst = 'notifications.first';

  static const List<String> board = [boardSessions, boardProjects, boardAccounts];
}
```

Create `lib/feature/sessions/data/model/board_payload.dart`:

```dart
import 'package:equatable/equatable.dart';

class BoardPayload extends Equatable {
  const BoardPayload({required this.sessions, this.projects, this.accounts});

  final Map<String, dynamic> sessions;
  final Map<String, dynamic>? projects;
  final Map<String, dynamic>? accounts;

  @override
  List<Object?> get props => [sessions, projects, accounts];
}
```

Add to `lib/feature/sessions/data/model/board_snapshot.dart` (import `board_payload.dart`), inside the class after the fields:

```dart
  factory BoardSnapshot.fromPayload(BoardPayload payload) => BoardSnapshot(
    sessions: (payload.sessions['sessions'] as List<dynamic>? ?? const [])
        .map((row) => SessionModel.fromJson(row as Map<String, dynamic>))
        .toList(),
    projects: _projects(payload.projects),
    accountLabels: _accountLabels(payload.accounts),
  );

  static List<ProjectModel> _projects(Map<String, dynamic>? body) {
    try {
      return (body?['projects'] as List<dynamic>? ?? const [])
          .map((row) => ProjectModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, String> _accountLabels(Map<String, dynamic>? body) {
    try {
      return {
        for (final account in (body?['accounts'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          if (account['id'] is String) account['id'] as String: (account['label'] as String?) ?? account['id'] as String,
      };
    } catch (_) {
      return const {};
    }
  }
```

Replace `lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

abstract class SessionsRemoteDataSource {
  Future<BoardPayload> getBoard();
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<BoardPayload> getBoard() async {
    final sessionsResponse = await _apiConsumer.get(EndPoints.sessions);
    final sessions = sessionsResponse.data;
    if (sessions is! Map<String, dynamic>) {
      throw MappingFailure(error: 'sessions body is ${sessions.runtimeType}', stacktrace: StackTrace.current);
    }

    final projectsFuture = _optionalBody(EndPoints.projects);
    final accountsFuture = _optionalBody(EndPoints.claudeAccounts);
    final projects = await projectsFuture;
    final accounts = await accountsFuture;

    return BoardPayload(sessions: sessions, projects: projects, accounts: accounts);
  }

  Future<Map<String, dynamic>?> _optionalBody(String path) async {
    try {
      final response = await _apiConsumer.get(path);
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> kill(String id) async {
    await _apiConsumer.post(EndPoints.sessionKill(id));
  }

  @override
  Future<void> restore(String id) async {
    await _apiConsumer.post(EndPoints.sessionRestore(id));
  }
}
```

Create `lib/feature/sessions/data/data_source/sessions_local_data_source.dart`:

```dart
import 'dart:convert';

import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/replica/replica_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

abstract class SessionsLocalDataSource {
  Future<Replicated<BoardPayload>?> readBoard(String desktopId);
  Future<void> writeBoard(String desktopId, BoardPayload payload, DateTime fetchedAt);
  Future<void> deleteBoard(String desktopId);
}

class SessionsLocalDataSourceImp implements SessionsLocalDataSource {
  SessionsLocalDataSourceImp(this._dao);

  final ReplicaDocumentDao _dao;

  @override
  Future<Replicated<BoardPayload>?> readBoard(String desktopId) async {
    final rows = {for (final row in await _dao.read(desktopId, ReplicaKeys.board)) row.key: row};
    final sessions = rows[ReplicaKeys.boardSessions];
    if (sessions == null) return null;
    return Replicated(
      value: BoardPayload(
        sessions: jsonDecode(sessions.body) as Map<String, dynamic>,
        projects: _decode(rows[ReplicaKeys.boardProjects]),
        accounts: _decode(rows[ReplicaKeys.boardAccounts]),
      ),
      fetchedAt: sessions.fetchedAt,
    );
  }

  @override
  Future<void> writeBoard(String desktopId, BoardPayload payload, DateTime fetchedAt) => _dao.write(desktopId, {
    ReplicaKeys.boardSessions: jsonEncode(payload.sessions),
    if (payload.projects != null) ReplicaKeys.boardProjects: jsonEncode(payload.projects),
    if (payload.accounts != null) ReplicaKeys.boardAccounts: jsonEncode(payload.accounts),
  }, fetchedAt);

  @override
  Future<void> deleteBoard(String desktopId) => _dao.remove(desktopId, ReplicaKeys.board);

  static Map<String, dynamic>? _decode(ReplicaDocumentEntity? row) =>
      row == null ? null : jsonDecode(row.body) as Map<String, dynamic>;
}
```

Replace `lib/feature/sessions/data/repository/sessions_repository.dart`:

```dart
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

abstract class SessionsRepository {
  Future<Replicated<BoardSnapshot>?> cachedBoard();
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard();
  FutureResult<bool> kill(String id);
  FutureResult<bool> restore(String id);
}

class SessionsRepositoryImp implements SessionsRepository {
  SessionsRepositoryImp(
    this._remoteDataSource,
    this._network,
    this._localDataSource,
    this._config, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SessionsRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final SessionsLocalDataSource _localDataSource;
  final ServerConfigSource _config;
  final DateTime Function() _clock;

  @override
  Future<Replicated<BoardSnapshot>?> cachedBoard() async {
    final desktopId = _config.current?.desktopId;
    if (desktopId == null) return null;
    try {
      final stored = await _localDataSource.readBoard(desktopId);
      if (stored == null) return null;
      return Replicated(value: BoardSnapshot.fromPayload(stored.value), fetchedAt: stored.fetchedAt);
    } on Failure {
      return null;
    } catch (_) {
      await _forget(desktopId);
      return null;
    }
  }

  @override
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard() async {
    if (!await _network.isConnected) return Result.failure(ServerFailure.noNetwork());
    final desktopId = _config.current?.desktopId;
    try {
      final payload = await _remoteDataSource.getBoard();
      final board = _parse(payload);
      await _remember(desktopId, payload);
      return Result.success(GlobalResponse(data: board));
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }

  @override
  FutureResult<bool> kill(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.kill(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> restore(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.restore(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  static BoardSnapshot _parse(BoardPayload payload) {
    try {
      return BoardSnapshot.fromPayload(payload);
    } catch (error, stackTrace) {
      throw MappingFailure(error: error, stacktrace: stackTrace);
    }
  }

  Future<void> _remember(String? desktopId, BoardPayload payload) async {
    if (desktopId == null || _config.current?.desktopId != desktopId) return;
    try {
      await _localDataSource.writeBoard(desktopId, payload, _clock());
    } on Failure {
      return;
    }
  }

  Future<void> _forget(String desktopId) async {
    try {
      await _localDataSource.deleteBoard(desktopId);
    } on Failure {
      return;
    }
  }
}
```

In `sessions_state.dart`, replace `GetSessionsSuccessState`:

```dart
final class GetSessionsSuccessState extends SessionsState {
  const GetSessionsSuccessState(this.revision, {this.fromCache = false});

  final int revision;
  final bool fromCache;

  @override
  List<Object?> get props => [revision, fromCache];
}
```

In `sessions_cubit.dart`:

1. Import `package:operator_mobile/core/replica/replicated.dart`.
2. Constructor signature: `SessionsCubit(this._repository, this._muxClient, this._configSource, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now, super(const SessionsInitialState()) {`. In the body, replace `scheduleMicrotask(() => unawaited(_refreshBoard()));` with:

```dart
    _cacheReady = _primeFromCache(_boardEpoch);
    scheduleMicrotask(() => unawaited(_refreshBoard()));
```

3. Add fields next to `sessions`:

```dart
  final DateTime Function() _clock;
  DateTime? boardFetchedAt;
  bool boardIsCached = false;
  bool _freshLoaded = false;
  Future<void> _cacheReady = Future<void>.value();

  Future<void> get cacheReady => _cacheReady;
```

4. Add:

```dart
  Future<void> _primeFromCache(int epoch) async {
    final cached = await _repository.cachedBoard();
    if (cached == null || isClosed || epoch != _boardEpoch || _freshLoaded) return;
    sessions = cached.value.sessions;
    projects = cached.value.projects;
    accountLabels = cached.value.accountLabels;
    boardFetchedAt = cached.fetchedAt;
    boardIsCached = true;
    emit(GetSessionsSuccessState(++_revision, fromCache: true));
  }
```

5. In `_onConfigChanged`, after `projects = [];` and the Task 3 lines, add `accountLabels = const {}; boardFetchedAt = null; boardIsCached = false; _freshLoaded = false;`. Replace its last line `unawaited(refresh());` with:

```dart
    _cacheReady = _primeFromCache(_boardEpoch);
    unawaited(refresh());
```

6. In `_loadBoard`'s `onSuccess`, right after `accountLabels = board.accountLabels;`, add:

```dart
        _freshLoaded = true;
        boardFetchedAt = _clock();
        boardIsCached = false;
```

In `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart`, change the `firstWhere` predicate in `_resolve` so a cached board does not end the wait:

```dart
      await cubit.stream.firstWhere(
        (state) => (state is GetSessionsSuccessState && !state.fromCache) || state is GetSessionsFailureState,
      );
```

and make the `if` above it also wait when the current state is cached:

```dart
    final current = cubit.state;
    if (current is SessionsInitialState ||
        current is GetSessionsLoadingState ||
        (current is GetSessionsSuccessState && current.fromCache)) {
```

In `lib/core/utils/service_locator.dart`, `_sessionsFeatureSetup`, register the local data source and pass it and the config store into the repository:

```dart
    sl.registerLazySingleton<SessionsRepository>(
      () => SessionsRepositoryImp(
        sl<SessionsRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<SessionsLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<SessionsLocalDataSource>(
      () => SessionsLocalDataSourceImp(sl<ReplicaDocumentDao>()),
    );
```

with the `sessions_local_data_source.dart` import.

- [ ] **Step 4: Stub the cache in every other test that builds a `SessionsCubit` over a mocked repository.**

An unstubbed `cachedBoard()` on a mocktail mock returns `null` where a `Future` is required. Add `when(() => <mock>.cachedBoard()).thenAnswer((_) async => null);` next to that mock's existing `getBoard()` stub, in `setUp` where the mock is created there, or in the test that creates it:

`test/core/app_routes/home_shell_test.dart` (`repository`), `test/core/telemetry/call_sites_test.dart` (both tests' local `repository`), `test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart` (`sessionsRepository`), `test/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_body_test.dart` (`sessionsRepository`), `test/feature/sessions/presentation/sessions_screen/ui/session_actions_sheet_test.dart`, `test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart` (`repository`), `test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart`.

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `flutter test test/feature/sessions test/core/app_routes test/core/telemetry test/feature/settings test/feature/pull_request test/feature/spawn`
Expected: PASS. The probe-order test in `sessions_remote_data_source_test.dart` passes unchanged.

- [ ] **Step 6: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 7: Commit.**

```bash
git add lib/core/replica lib/feature/sessions lib/core/utils/service_locator.dart test/feature/sessions \
  test/core/app_routes/home_shell_test.dart test/core/telemetry/call_sites_test.dart \
  test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart \
  test/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_body_test.dart \
  test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): paint the last known board from drift, then the fresh one

Every successful board load stores the three daemon bodies under the
active desktop, and BoardSnapshot.fromPayload is the one parse path for
network and drift alike. SessionsCubit reads the cache once per desktop
and never lets an older read or another desktop's replica overwrite what
it shows. Ported sessions_remote_data_source_test's board assertions to
BoardSnapshot.fromPayload; the probe-order test is unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Notifications replica, scoped to the active desktop

**Files:**
- Create: `packages/mobile/lib/feature/notification/data/data_source/notification_local_data_source.dart`
- Modify: `packages/mobile/lib/feature/notification/data/data_source/notification_remote_data_source.dart:12`, `:25-38`
- Modify: `packages/mobile/lib/feature/notification/data/repository/notification_repository.dart`
- Modify: `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_notificationFeatureSetup`)
- Test: create `test/feature/notification/data/data_source/notification_local_data_source_test.dart`; port `notification_remote_data_source_test.dart` and `notification_repository_test.dart`; add tests to `notifications_cubit_test.dart`; add stubs to `notifications_body_test.dart` and `test/core/app_routes/home_shell_test.dart`

**Interfaces:**
- Consumes: `ReplicaDocumentDao`, `Replicated<T>`, `ReplicaKeys.notificationsFirst`, `ServerConfig.desktopId`.
- Produces:
  - `NotificationRemoteDataSource.getNotifications(GetNotificationsParams params)` returns `Future<Map<String, dynamic>>`, the decoded body.
  - `NotificationLocalDataSource`: `Future<Replicated<Map<String, dynamic>>?> readFirstPage(String desktopId)`, `Future<void> writeFirstPage(String desktopId, Map<String, dynamic> body, DateTime fetchedAt)`, `Future<void> deleteFirstPage(String desktopId)`
  - `NotificationRepository.cachedFirstPage()` returns `Future<Replicated<NotificationPageModel>?>`. `getNotifications` stores the body when `status == 'all'` and `cursor == null`. Constructor: `NotificationRepositoryImp(remote, network, NotificationLocalDataSource local, ServerConfigSource config, {DateTime Function()? clock})`
  - `NotificationsCubit` paints the cached first page and its unread count, and clears and re-reads on every desktop change.

- [ ] **Step 1: Write the failing tests.**

Create `test/feature/notification/data/data_source/notification_local_data_source_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';

void main() {
  late AppDatabase db;
  late NotificationLocalDataSourceImp source;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = NotificationLocalDataSourceImp(db.replicaDocumentDao);
  });

  tearDown(() => db.close());

  test('writeFirstPage then readFirstPage round-trips the body per desktop', () async {
    await source.writeFirstPage('a', {'notifications': [], 'unreadCount': 3}, at);

    final stored = await source.readFirstPage('a');

    expect(stored!.value, {'notifications': [], 'unreadCount': 3});
    expect(stored.fetchedAt.isAtSameMomentAs(at), isTrue);
    expect(await source.readFirstPage('b'), isNull);
  });

  test('deleteFirstPage removes it', () async {
    await source.writeFirstPage('a', {'notifications': []}, at);

    await source.deleteFirstPage('a');

    expect(await source.readFirstPage('a'), isNull);
  });
}
```

In `test/feature/notification/data/data_source/notification_remote_data_source_test.dart`, add `import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';` and change the first test's read to parse through the model, same assertions:

```dart
    final page = NotificationPageModel.fromJson(
      await dataSource.getNotifications(const GetNotificationsParams(status: 'all', limit: 50)),
    );
```

Replace `test/feature/notification/data/repository/notification_repository_test.dart`'s header, `setUp` and the `returns the page when the data source succeeds` test. The phone-alert and mark-read tests stay as they are.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

class _MockDataSource extends Mock implements NotificationRemoteDataSource {}

class _MockLocal extends Mock implements NotificationLocalDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = const ServerConfig(
    host: '10.0.0.5',
    httpPort: '3011',
    secure: false,
    password: 'pw',
    desktopId: 'a',
  );

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  late _MockDataSource dataSource;
  late _MockLocal local;
  late _MockNetworkStatus network;
  late _Config config;
  late NotificationRepository repository;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(DateTime.utc(2026));
  });

  setUp(() {
    dataSource = _MockDataSource();
    local = _MockLocal();
    network = _MockNetworkStatus();
    config = _Config();
    repository = NotificationRepositoryImp(dataSource, network, local, config, clock: () => at);
    when(() => local.writeFirstPage(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteFirstPage(any())).thenAnswer((_) async {});
  });
```

```dart
  test('returns the page when the data source succeeds', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer(
      (_) async => {'notifications': <dynamic>[], 'unreadCount': 4},
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    late NotificationPageModel page;
    result.when(onSuccess: (response) => page = response.data!, onFailure: (_) {});
    expect(page.unreadCount, 4);
  });

  test('stores the first page of all notifications under the active desktop', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    final body = {'notifications': <dynamic>[], 'unreadCount': 2};
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async => body);

    await repository.getNotifications(const GetNotificationsParams(status: 'all', limit: 50));

    verify(() => local.writeFirstPage('a', body, at)).called(1);
  });

  test('neither a later page nor the unread probe is stored', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async => {'notifications': <dynamic>[]});

    await repository.getNotifications(const GetNotificationsParams(status: 'all', cursor: 'c-2'));
    await repository.getNotifications(const GetNotificationsParams(status: 'unread', limit: 1));

    verifyNever(() => local.writeFirstPage(any(), any(), any()));
  });

  test('drops the write when the desktop changed while the fetch was in flight', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async {
      config.current = null;
      return {'notifications': <dynamic>[]};
    });

    await repository.getNotifications(const GetNotificationsParams(status: 'all'));

    verifyNever(() => local.writeFirstPage(any(), any(), any()));
  });

  test('cachedFirstPage parses the replica through NotificationPageModel', () async {
    when(() => local.readFirstPage('a')).thenAnswer(
      (_) async => Replicated(value: {'notifications': [{'id': 'n-1'}], 'unreadCount': 1}, fetchedAt: at),
    );

    final cached = await repository.cachedFirstPage();

    expect(cached!.value.notifications.single.id, 'n-1');
    expect(cached.value.unreadCount, 1);
  });

  test('a first page that no longer parses is deleted and read as a miss', () async {
    when(() => local.readFirstPage('a')).thenAnswer(
      (_) async => Replicated(value: {'notifications': 'nope'}, fetchedAt: at),
    );

    expect(await repository.cachedFirstPage(), isNull);
    verify(() => local.deleteFirstPage('a')).called(1);
  });
```

In `test/feature/notification/presentation/notifications_screen/logic/notifications_cubit_test.dart`, add imports for `dart:async` and `package:operator_mobile/core/replica/replicated.dart`, a `late StreamController<ServerConfig?> changes;` beside the other `late`s, and in `setUp`:

```dart
    changes = StreamController<ServerConfig?>.broadcast(sync: true);
    when(() => serverConfigStore.changes).thenAnswer((_) => changes.stream);
    when(() => repository.cachedFirstPage()).thenAnswer((_) async => null);
```

with `tearDown(() => changes.close());`. Then append inside `main()`:

```dart
  group('replica', () {
    const serverB = ServerConfig(host: '10.0.0.9', httpPort: '4317', secure: false, password: 'secret', desktopId: 'b');

    Replicated<NotificationPageModel> cachedPage(String id, {int unread = 0}) => Replicated(
      value: NotificationPageModel(notifications: [item(id)], unreadCount: unread),
      fetchedAt: DateTime.utc(2026, 9, 25, 8),
    );

    test('paints the cached first page and its unread count before the network answers', () async {
      final gate = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      when(() => repository.cachedFirstPage()).thenAnswer((_) async => cachedPage('n-cached', unread: 3));
      when(() => repository.getNotifications(any())).thenAnswer((_) => gate.future);

      final cubit = build();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items.single.id, 'n-cached');
      expect(cubit.unreadCount, 3);
      expect(cubit.loading, isFalse);

      gate.complete(page([item('n-fresh')], unreadCount: 1));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items.single.id, 'n-fresh');
      expect(cubit.unreadCount, 1);
      await cubit.close();
    });

    test('a desktop switch clears the previous list at once and paints the new desktop cache', () async {
      when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-a')], unreadCount: 1));
      final cubit = build();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.items.single.id, 'n-a');

      final gate = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      when(() => repository.cachedFirstPage()).thenAnswer((_) async => cachedPage('n-b-cached'));
      when(() => repository.getNotifications(any())).thenAnswer((_) => gate.future);
      when(() => serverConfigStore.current).thenReturn(serverB);
      changes.add(serverB);

      expect(cubit.items, isEmpty);
      expect(cubit.unreadCount, 0);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.items.single.id, 'n-b-cached');
      await cubit.close();
    });

    test('a fetch that started for the previous desktop is dropped', () async {
      final first = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      var calls = 0;
      when(() => repository.getNotifications(any())).thenAnswer((_) {
        calls++;
        return calls == 1 ? first.future : Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>().future;
      });
      final cubit = build();
      await Future<void>.delayed(Duration.zero);

      when(() => serverConfigStore.current).thenReturn(serverB);
      changes.add(serverB);
      first.complete(page([item('n-a')], unreadCount: 5));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items, isEmpty);
      expect(cubit.unreadCount, 0);
      await cubit.close();
    });
  });
```

In `test/feature/notification/presentation/notifications_screen/ui/notifications_body_test.dart` `setUp`, add `when(() => serverConfigStore.changes).thenAnswer((_) => const Stream.empty());` and `when(() => repository.cachedFirstPage()).thenAnswer((_) async => null);`. In `test/core/app_routes/home_shell_test.dart` `setUp`, add `when(() => notificationRepository.cachedFirstPage()).thenAnswer((_) async => null);`.

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/notification test/core/app_routes/home_shell_test.dart`
Expected: FAIL to compile: `notification_local_data_source.dart` not found and `cachedFirstPage` not defined.

- [ ] **Step 3: Implement.**

In `notification_remote_data_source.dart`, change the abstract signature to `Future<Map<String, dynamic>> getNotifications(GetNotificationsParams params);`, drop the `global_response.dart` and `notification_page_model.dart` imports, add `import 'package:operator_mobile/core/error_handling/failures/failure.dart';`, and replace the implementation:

```dart
  @override
  Future<Map<String, dynamic>> getNotifications(GetNotificationsParams params) async {
    final response = await _apiConsumer.get(EndPoints.notifications, queryParameters: params.toJson());
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MappingFailure(error: 'notifications body is ${body.runtimeType}', stacktrace: StackTrace.current);
    }
    return body;
  }
```

Create `lib/feature/notification/data/data_source/notification_local_data_source.dart`:

```dart
import 'dart:convert';

import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/replica/replica_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';

abstract class NotificationLocalDataSource {
  Future<Replicated<Map<String, dynamic>>?> readFirstPage(String desktopId);
  Future<void> writeFirstPage(String desktopId, Map<String, dynamic> body, DateTime fetchedAt);
  Future<void> deleteFirstPage(String desktopId);
}

class NotificationLocalDataSourceImp implements NotificationLocalDataSource {
  NotificationLocalDataSourceImp(this._dao);

  final ReplicaDocumentDao _dao;

  @override
  Future<Replicated<Map<String, dynamic>>?> readFirstPage(String desktopId) async {
    final rows = await _dao.read(desktopId, const [ReplicaKeys.notificationsFirst]);
    if (rows.isEmpty) return null;
    return Replicated(value: jsonDecode(rows.single.body) as Map<String, dynamic>, fetchedAt: rows.single.fetchedAt);
  }

  @override
  Future<void> writeFirstPage(String desktopId, Map<String, dynamic> body, DateTime fetchedAt) =>
      _dao.write(desktopId, {ReplicaKeys.notificationsFirst: jsonEncode(body)}, fetchedAt);

  @override
  Future<void> deleteFirstPage(String desktopId) => _dao.remove(desktopId, const [ReplicaKeys.notificationsFirst]);
}
```

In `notification_repository.dart`, add imports for `server_config_interceptor.dart`, `replicated.dart` and `notification_local_data_source.dart`. Add `Future<Replicated<NotificationPageModel>?> cachedFirstPage();` to the abstract class. Replace the constructor, the fields and `getNotifications`, and add the helpers:

```dart
  NotificationRepositoryImp(
    this._remoteDataSource,
    this._network,
    this._localDataSource,
    this._config, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NotificationRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final NotificationLocalDataSource _localDataSource;
  final ServerConfigSource _config;
  final DateTime Function() _clock;

  @override
  Future<Replicated<NotificationPageModel>?> cachedFirstPage() async {
    final desktopId = _config.current?.desktopId;
    if (desktopId == null) return null;
    try {
      final stored = await _localDataSource.readFirstPage(desktopId);
      if (stored == null) return null;
      return Replicated(value: NotificationPageModel.fromJson(stored.value), fetchedAt: stored.fetchedAt);
    } on Failure {
      return null;
    } catch (_) {
      await _forget(desktopId);
      return null;
    }
  }

  @override
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(GetNotificationsParams params) =>
      _guard(() async {
        final desktopId = _config.current?.desktopId;
        final body = await _remoteDataSource.getNotifications(params);
        final page = GlobalResponse<NotificationPageModel>.fromJson(
          body,
          withDataKey: false,
          fromJsonT: NotificationPageModel.fromJson,
        );
        if (params.cursor == null && params.status == 'all') await _remember(desktopId, body);
        return page;
      });

  Future<void> _remember(String? desktopId, Map<String, dynamic> body) async {
    if (desktopId == null || _config.current?.desktopId != desktopId) return;
    try {
      await _localDataSource.writeFirstPage(desktopId, body, _clock());
    } on Failure {
      return;
    }
  }

  Future<void> _forget(String desktopId) async {
    try {
      await _localDataSource.deleteFirstPage(desktopId);
    } on Failure {
      return;
    }
  }
```

Replace `notifications_cubit.dart`'s class body from the constructor through `refreshUnread` with the version below. `open`, `markAllRead` and `load`/`refresh`/`loadMore` keep their current bodies. Import `package:operator_mobile/core/api/server_config.dart` for `ServerConfig`.

```dart
  NotificationsCubit._(this._repository, this._serverConfigStore, {required this._unreadPoll})
    : super(const NotificationsInitialState()) {
    _configSub = _serverConfigStore.changes.listen(_onConfigChanged);
    unawaited(_start(_epoch));
    _timer = Timer.periodic(_unreadPoll, (_) => unawaited(refreshUnread()));
  }

  final NotificationRepository _repository;
  final ServerConfigStore _serverConfigStore;
  final Duration _unreadPoll;

  bool get _hasServer => hasServer(_serverConfigStore.current);

  List<NotificationModel> items = [];
  int unreadCount = 0;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;
  String? error;

  String? _nextCursor;
  Timer? _timer;
  StreamSubscription<ServerConfig?>? _configSub;
  int _revision = 0;
  int _epoch = 0;
  bool _freshLoaded = false;

  void _emit() {
    if (isClosed) return;
    emit(NotificationsReadyState(++_revision));
  }

  Future<void> _start(int epoch) async {
    await _primeFromCache(epoch);
    if (isClosed || epoch != _epoch) return;
    await load();
  }

  Future<void> _primeFromCache(int epoch) async {
    if (!_hasServer) return;
    final cached = await _repository.cachedFirstPage();
    if (cached == null || isClosed || epoch != _epoch || _freshLoaded) return;
    items = cached.value.notifications;
    _nextCursor = cached.value.nextCursor;
    unreadCount = cached.value.unreadCount;
    loading = false;
    _emit();
  }

  void _onConfigChanged(ServerConfig? next) {
    if (isClosed) return;
    _epoch++;
    items = [];
    unreadCount = 0;
    _nextCursor = null;
    error = null;
    loading = true;
    _freshLoaded = false;
    _emit();
    unawaited(_start(_epoch));
  }
```

In `_fetch`, capture `final epoch = _epoch;` as its first line. Right after the `await _repository.getNotifications(...)` call, add `if (isClosed || epoch != _epoch) return;`, and inside `onSuccess`'s `if (reset)` branch add `_freshLoaded = true;`. In `refreshUnread`, capture `final epoch = _epoch;` after the `_hasServer` check and add `if (isClosed || epoch != _epoch) return;` after its await. In `close()`, add `unawaited(_configSub?.cancel());` before `return super.close();`.

In `service_locator.dart` `_notificationFeatureSetup`:

```dart
    sl.registerLazySingleton<NotificationRepository>(
      () => NotificationRepositoryImp(
        sl<NotificationRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<NotificationLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<NotificationLocalDataSource>(
      () => NotificationLocalDataSourceImp(sl<ReplicaDocumentDao>()),
    );
```

with the `notification_local_data_source.dart` import.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/feature/notification test/core/app_routes/home_shell_test.dart`
Expected: PASS, including all pre-existing `NotificationsCubit` tests.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Commit.**

```bash
git add lib/feature/notification lib/core/utils/service_locator.dart test/feature/notification \
  test/core/app_routes/home_shell_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): replicate the first notifications page per desktop

The bell and the list draw the cached first page and unread count at once.
NotificationsCubit now follows desktop switches: it clears, re-reads that
desktop's replica and drops any fetch that started for the previous one.
Ported notification_remote_data_source_test and notification_repository_test
to the body-returning data source, same assertions.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Chat history replica: cached events first, merged by seq

**Files:**
- Create: `packages/mobile/lib/feature/blocks/data/data_source/blocks_local_data_source.dart`
- Modify: `packages/mobile/lib/feature/blocks/data/data_source/blocks_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/blocks/data/repository/blocks_repository.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart:46-124`, `:166-183`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_blocksFeatureSetup`)
- Test: create `test/feature/blocks/data/blocks_local_data_source_test.dart`, `test/feature/blocks/presentation/blocks_cubit_replica_test.dart`; port `test/feature/blocks/data/blocks_repository_test.dart`; add stubs to `blocks_cubit_test.dart`, `blocks_cubit_tasks_test.dart`, `test/feature/terminal/terminal_harness.dart`, `session_route_screen_test.dart`

**Interfaces:**
- Consumes: `ReplicaBlockEventDao`, `ReplicaLimits.blockEventsPerSession`, `ServerConfig.desktopId`.
- Produces:
  - `BlocksRemoteDataSource.getSessionBlocks(String sessionId, GetSessionBlocksParams params)` returns `Future<Map<String, dynamic>>`, the decoded body.
  - `BlocksLocalDataSource`: `Future<List<Map<String, dynamic>>> readHistory(String desktopId, String sessionId)`, `Future<void> writeHistory(String desktopId, String sessionId, List<Map<String, dynamic>> rows)`, `Future<void> deleteHistory(String desktopId, String sessionId)`
  - `BlocksRepository`: `getSessionBlocks` keeps its signature and stores main-conversation rows. Adds `Future<List<BlockEventModel>> cachedHistory(String sessionId)` and `Future<void> rememberLive(String sessionId, Map<String, dynamic> row)`. Constructor: `BlocksRepositoryImp(remote, network, BlocksLocalDataSource local, ServerConfigSource config)`
  - `BlocksCubit` seeds from the cache (main scope only), anchors its first fetch's `afterSeq` to the cached tail, and remembers live main-scope events.

- [ ] **Step 1: Write the failing tests.**

Create `test/feature/blocks/data/blocks_local_data_source_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BlocksLocalDataSourceImp source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = BlocksLocalDataSourceImp(db.replicaBlockEventDao);
  });

  tearDown(() => db.close());

  test('writeHistory then readHistory returns the rows oldest first, keyed by seq', () async {
    await source.writeHistory('a', 's-1', [
      {'seq': 2, 'kind': 'stop'},
      {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
    ]);

    expect(await source.readHistory('a', 's-1'), [
      {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
      {'seq': 2, 'kind': 'stop'},
    ]);
  });

  test('keeps only the newest events per session', () async {
    await source.writeHistory('a', 's-1', [for (var seq = 1; seq <= 230; seq++) {'seq': seq}]);

    final rows = await source.readHistory('a', 's-1');

    expect(rows, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(rows.first['seq'], 31);
  });

  test('deleteHistory removes that session', () async {
    await source.writeHistory('a', 's-1', [{'seq': 1}]);

    await source.deleteHistory('a', 's-1');

    expect(await source.readHistory('a', 's-1'), isEmpty);
  });
}
```

Replace `test/feature/blocks/data/blocks_repository_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';

class _MockDataSource extends Mock implements BlocksRemoteDataSource {}

class _MockLocal extends Mock implements BlocksLocalDataSource {}

class _OnlineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => true;
}

class _OfflineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => false;
}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = const ServerConfig(
    host: '10.0.0.5',
    httpPort: '3011',
    secure: false,
    password: 'pw',
    desktopId: 'a',
  );

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  late _MockDataSource source;
  late _MockLocal local;
  late _Config config;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    source = _MockDataSource();
    local = _MockLocal();
    config = _Config();
    when(() => local.writeHistory(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteHistory(any(), any())).thenAnswer((_) async {});
  });

  BlocksRepositoryImp online() => BlocksRepositoryImp(source, _OnlineNetwork(), local, config);

  test('the endpoint encodes the session id', () {
    expect(EndPoints.sessionBlocks('a b/c'), '/api/v1/sessions/a%20b%2Fc/blocks');
  });

  test('returns the parsed log', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 1, 'kind': 'stop'},
        ],
      },
    );

    final result = await online().getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4));

    expect(result.isSuccess, isTrue);
    expect(result.getOrDefault(const []).single.seq, 1);
    verify(() => source.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4))).called(1);
  });

  test('fails without a network instead of calling the daemon', () async {
    final repository = BlocksRepositoryImp(source, _OfflineNetwork(), local, config);

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => source.getSessionBlocks(any(), any()));
  });

  test('surfaces a data-source failure as a Result failure', () async {
    when(() => source.getSessionBlocks(any(), any())).thenThrow(
      ServerFailure(error: 'boom', message: 'boom', statusCode: 500),
    );

    final result = await online().getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
  });

  test('stores main-conversation rows, not task updates or subagent rows', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 1, 'kind': 'stop'},
          {'seq': 2, 'kind': 'task_update'},
          {'seq': 3, 'kind': 'stop', 'agentId': 'a1'},
        ],
      },
    );

    await online().getSessionBlocks('s-1', const GetSessionBlocksParams());

    verify(() => local.writeHistory('a', 's-1', [
      {'seq': 1, 'kind': 'stop'},
    ])).called(1);
  });

  test('a subagent page is never stored', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 3, 'kind': 'stop', 'agentId': 'a1'},
        ],
      },
    );

    await online().getSessionBlocks('s-1', const GetSessionBlocksParams(agentId: 'a1'));

    verifyNever(() => local.writeHistory(any(), any(), any()));
  });

  test('cachedHistory parses the stored rows through BlockEventModel', () async {
    when(() => local.readHistory('a', 's-1')).thenAnswer(
      (_) async => [
        {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
      ],
    );

    final cached = await online().cachedHistory('s-1');

    expect(cached.single.seq, 1);
    expect(cached.single.text, 'hi');
  });

  test('history that no longer parses is deleted and read as empty', () async {
    when(() => local.readHistory('a', 's-1')).thenAnswer(
      (_) async => [
        {'seq': 'not a number'},
      ],
    );

    expect(await online().cachedHistory('s-1'), isEmpty);
    verify(() => local.deleteHistory('a', 's-1')).called(1);
  });

  test('rememberLive stores one main row and ignores it with no active desktop', () async {
    await online().rememberLive('s-1', {'seq': 9, 'kind': 'stop'});
    verify(() => local.writeHistory('a', 's-1', [
      {'seq': 9, 'kind': 'stop'},
    ])).called(1);

    config.current = null;
    await online().rememberLive('s-1', {'seq': 10, 'kind': 'stop'});
    verifyNever(() => local.writeHistory(any(), 's-1', [
      {'seq': 10, 'kind': 'stop'},
    ]));
  });
}
```

Create `test/feature/blocks/presentation/blocks_cubit_replica_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRepository extends Mock implements BlocksRepository {}

class _MockTasks extends Mock implements BackgroundTasksRepository {}

Map<String, dynamic> _stop(int seq, {String? agentId}) => {
  'seq': seq,
  'sessionId': 's-1',
  'kind': 'stop',
  'text': 'line $seq',
  'agentId': ?agentId,
};

BlockEventModel _row(int seq) => BlockEventModel.fromJson(_stop(seq));

void main() {
  late _MockMux mux;
  late _MockRepository repository;
  late _MockTasks tasks;
  late StreamController<BlockEventEnvelope> events;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(const GetSessionTasksParams(sessionId: ''));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mux = _MockMux();
    repository = _MockRepository();
    tasks = _MockTasks();
    events = StreamController<BlockEventEnvelope>.broadcast();
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'nf', statusCode: 404)),
    );
    when(() => repository.cachedHistory(any())).thenAnswer((_) async => const []);
    when(() => repository.rememberLive(any(), any())).thenAnswer((_) async {});
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success(const <BlockEventModel>[]),
    );
  });

  tearDown(() => events.close());

  BlocksCubit build({String? agentId}) => BlocksCubit(
    mux,
    repository,
    BlocksScope(sessionId: 's-1', harness: 'claude-code', agentId: agentId),
    tasks: tasks,
  );

  test('draws the cached history before the network answers, then fetches only what came after it', () async {
    final gate = Completer<Result<List<BlockEventModel>, Failure>>();
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) async => [_row(1), _row(2)]);
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) => gate.future);

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((block) => block.id), ['seq-1', 'seq-2']);
    verify(() => repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 2))).called(1);

    gate.complete(Result.success([_row(2), _row(3)]));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((block) => block.id), ['seq-1', 'seq-2', 'seq-3']);
    await cubit.close();
  });

  test('a live event that lands before the cache keeps the first fetch anchored to the cached tail', () async {
    final cache = Completer<List<BlockEventModel>>();
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) => cache.future);

    final cubit = build();
    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await Future<void>.delayed(Duration.zero);
    cache.complete([for (var seq = 1; seq <= 100; seq++) _row(seq)]);
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 100))).called(1);
    expect(cubit.blocks.last.id, 'seq-150');
    await cubit.close();
  });

  test('a full cache offers older history from the daemon', () async {
    when(() => repository.cachedHistory('s-1')).thenAnswer(
      (_) async => [for (var seq = 1; seq <= ReplicaLimits.blockEventsPerSession; seq++) _row(seq + 1000)],
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.hasOlder, isTrue);
    await cubit.close();
  });

  test('live main-conversation events are remembered', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _stop(7)));
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.rememberLive('s-1', _stop(7))).called(1);
    await cubit.close();
  });

  test('a subagent screen neither reads nor writes the replica', () async {
    final cubit = build(agentId: 'a1');
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _stop(7, agentId: 'a1')));
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.cachedHistory(any()));
    verifyNever(() => repository.rememberLive(any(), any()));
    await cubit.close();
  });
}
```

Add these stubs to the existing tests that build a real `BlocksCubit` over a mocked `BlocksRepository` (in `setUp`, or next to the mock's existing `getSessionBlocks` stub), and add `registerFallbackValue(<String, dynamic>{});` beside their other fallbacks:

```dart
when(() => <mock>.cachedHistory(any())).thenAnswer((_) async => const []);
when(() => <mock>.rememberLive(any(), any())).thenAnswer((_) async {});
```

Files: `test/feature/blocks/presentation/blocks_cubit_test.dart` (`repository`), `test/feature/blocks/presentation/blocks_cubit_tasks_test.dart` (`blocks`), `test/feature/terminal/terminal_harness.dart` (`blocksRepository`), `test/feature/sessions/presentation/session_route/session_route_screen_test.dart` (`blocksRepository`).

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/blocks`
Expected: FAIL to compile: `blocks_local_data_source.dart` not found, and `cachedHistory`/`rememberLive` not defined.

- [ ] **Step 3: Implement.**

Replace `lib/feature/blocks/data/data_source/blocks_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRemoteDataSource {
  Future<Map<String, dynamic>> getSessionBlocks(String sessionId, GetSessionBlocksParams params);
}

class BlocksRemoteDataSourceImp implements BlocksRemoteDataSource {
  BlocksRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<Map<String, dynamic>> getSessionBlocks(String sessionId, GetSessionBlocksParams params) async {
    final response = await _apiConsumer.get(EndPoints.sessionBlocks(sessionId), queryParameters: params.toJson());
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MappingFailure(error: 'blocks body is ${body.runtimeType}', stacktrace: StackTrace.current);
    }
    return body;
  }
}
```

Create `lib/feature/blocks/data/data_source/blocks_local_data_source.dart`:

```dart
import 'dart:convert';

import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';

abstract class BlocksLocalDataSource {
  Future<List<Map<String, dynamic>>> readHistory(String desktopId, String sessionId);
  Future<void> writeHistory(String desktopId, String sessionId, List<Map<String, dynamic>> rows);
  Future<void> deleteHistory(String desktopId, String sessionId);
}

class BlocksLocalDataSourceImp implements BlocksLocalDataSource {
  BlocksLocalDataSourceImp(this._dao);

  final ReplicaBlockEventDao _dao;

  @override
  Future<List<Map<String, dynamic>>> readHistory(String desktopId, String sessionId) async => [
    for (final row in await _dao.latest(desktopId, sessionId)) jsonDecode(row.body) as Map<String, dynamic>,
  ];

  @override
  Future<void> writeHistory(String desktopId, String sessionId, List<Map<String, dynamic>> rows) =>
      _dao.write(desktopId, sessionId, {for (final row in rows) (row['seq'] as num).toInt(): jsonEncode(row)});

  @override
  Future<void> deleteHistory(String desktopId, String sessionId) => _dao.removeSession(desktopId, sessionId);
}
```

Replace `lib/feature/blocks/data/repository/blocks_repository.dart`:

```dart
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRepository {
  FutureResult<List<BlockEventModel>> getSessionBlocks(String sessionId, GetSessionBlocksParams params);
  Future<List<BlockEventModel>> cachedHistory(String sessionId);
  Future<void> rememberLive(String sessionId, Map<String, dynamic> row);
}

class BlocksRepositoryImp implements BlocksRepository {
  BlocksRepositoryImp(this._remoteDataSource, this._network, this._localDataSource, this._config);

  final BlocksRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final BlocksLocalDataSource _localDataSource;
  final ServerConfigSource _config;

  @override
  FutureResult<List<BlockEventModel>> getSessionBlocks(String sessionId, GetSessionBlocksParams params) =>
      _guard(() async {
        final desktopId = _config.current?.desktopId;
        final body = await _remoteDataSource.getSessionBlocks(sessionId, params);
        final events = _parse(body);
        if ((params.agentId ?? '').isEmpty) await _remember(desktopId, sessionId, _rows(body));
        return events;
      });

  @override
  Future<List<BlockEventModel>> cachedHistory(String sessionId) async {
    final desktopId = _config.current?.desktopId;
    if (desktopId == null) return const [];
    try {
      final rows = await _localDataSource.readHistory(desktopId, sessionId);
      return rows.map(BlockEventModel.fromJson).toList();
    } on Failure {
      return const [];
    } catch (_) {
      await _forget(desktopId, sessionId);
      return const [];
    }
  }

  @override
  Future<void> rememberLive(String sessionId, Map<String, dynamic> row) =>
      _remember(_config.current?.desktopId, sessionId, [row]);

  static List<BlockEventModel> _parse(Map<String, dynamic> body) {
    try {
      return BlockEventModel.listFromJson(body);
    } catch (error, stackTrace) {
      throw MappingFailure(error: error, stacktrace: stackTrace);
    }
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> body) {
    final blocks = body['blocks'];
    return blocks is List ? blocks.whereType<Map<String, dynamic>>().toList() : const [];
  }

  static bool _replicable(Map<String, dynamic> row) {
    final agent = row['agentId'];
    return row['seq'] is num && (agent is! String || agent.isEmpty) && row['kind'] != 'task_update';
  }

  Future<void> _remember(String? desktopId, String sessionId, List<Map<String, dynamic>> rows) async {
    if (desktopId == null || _config.current?.desktopId != desktopId) return;
    final kept = rows.where(_replicable).toList();
    if (kept.isEmpty) return;
    try {
      await _localDataSource.writeHistory(desktopId, sessionId, kept);
    } on Failure {
      return;
    }
  }

  Future<void> _forget(String desktopId, String sessionId) async {
    try {
      await _localDataSource.deleteHistory(desktopId, sessionId);
    } on Failure {
      return;
    }
  }

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
```

In `blocks_cubit.dart` (import `package:operator_mobile/core/replica/replica_limits.dart`):

1. In the constructor, after `_mux.subscribeBlocks(sessionId);`, replace `unawaited(refresh());` with:

```dart
    loading = true;
    unawaited(_start());
```

2. Add fields beside `_capacity`:

```dart
  bool _historyLoaded = false;
  int? _cachedThrough;
```

3. Add, above `refresh()`:

```dart
  Future<void> _start() async {
    if (agentId == null) await _seedFromCache();
    if (isClosed) return;
    await refresh();
  }

  Future<void> _seedFromCache() async {
    final cached = await _repository.cachedHistory(sessionId);
    if (isClosed || cached.isEmpty) return;
    var through = 0;
    for (final record in cached) {
      final seq = record.seq;
      if (seq == null) continue;
      through = max(through, seq);
      if (_events.containsKey(seq)) continue;
      _merge(record);
    }
    _cachedThrough = through == 0 ? null : through;
    if (cached.length >= ReplicaLimits.blockEventsPerSession) hasOlder = true;
    _rebuild();
  }
```

4. In `refresh()`, anchor the first fetch to the cached tail and mark history loaded on success:

```dart
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(afterSeq: _historyLoaded ? _highestSeq : _cachedThrough, agentId: agentId),
    );
    result.when(
      onSuccess: (records) {
        error = null;
        _historyLoaded = true;
        for (final record in records) {
          _merge(record);
        }
      },
```

(the `onFailure` branch is unchanged.)

5. In `_onLive`, right after `final scopeId = record.agentId ?? '';`, add:

```dart
    if (agentId == null && scopeId.isEmpty) unawaited(_repository.rememberLive(sessionId, envelope.block));
```

In `service_locator.dart` `_blocksFeatureSetup`:

```dart
    sl.registerLazySingleton<BlocksRepository>(
      () => BlocksRepositoryImp(
        sl<BlocksRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<BlocksLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<BlocksLocalDataSource>(
      () => BlocksLocalDataSourceImp(sl<ReplicaBlockEventDao>()),
    );
```

with the `blocks_local_data_source.dart` import.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/feature/blocks test/feature/terminal test/feature/sessions/presentation/session_route`
Expected: PASS, including every pre-existing `BlocksCubit` test. `an event that lands before history is not lost or duplicated` still passes, because the first fetch now ignores live seqs.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Commit.**

```bash
git add lib/feature/blocks lib/core/utils/service_locator.dart test/feature/blocks \
  test/feature/terminal/terminal_harness.dart test/feature/sessions/presentation/session_route/session_route_screen_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): open a chat on its cached history, then merge fresh events by seq

History pages and live mux events of the main conversation are stored per
desktop and session, capped at the newest 200. The first fetch after the
cache asks only for what came after the cached tail, and a live event that
lands first can no longer move that anchor. Ported blocks_repository_test
to the body-returning data source, same assertions.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: `ConnectionCubit`: one source of connection state, with retries

**Files:**
- Create: `packages/mobile/lib/core/connection/connection_report.dart`, `connection_backoff.dart`, `connection_signals.dart`, `connection_cubit.dart`, `connection_state.dart`
- Create: `packages/mobile/lib/core/api/interceptors/connection_report_interceptor.dart`
- Create: `packages/mobile/test/helpers/connection_harness.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart:10-13`
- Modify: `packages/mobile/lib/core/api/server_config_store.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart` (constructor, `resumeUpdates`, `close`)
- Modify: `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart` (factory, `refreshUnread`, `close`)
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` (`_coreSetup`, `_sessionsFeatureSetup`, `_notificationFeatureSetup`)
- Modify: `packages/mobile/lib/main.dart` (create the cubit before the first request, provide it at the root, retry on resume)
- Test: create `test/core/connection/connection_cubit_test.dart`, `test/core/api/connection_report_interceptor_test.dart`; add to `test/core/api/dio_consumer_headers_test.dart`, `test/core/api/server_config_store_test.dart`, `sessions_cubit_test.dart`, `notifications_cubit_test.dart`

**Interfaces:**
- Consumes: `ServerConfigSource`, `MuxClient.status`, `ConnectionFailure` (`connection_error.dart`), `EndPoints.health`.
- Produces:
  - `enum ConnectionOutcome { online, unreachable, auth, rateLimited, serverError }`
  - `class ConnectionReport { const ConnectionReport(ConnectionOutcome outcome, {required String path, required DateTime at}); }`
  - `class ConnectionReports { ConnectionReport? get last; Stream<ConnectionReport> get stream; void add(ConnectionReport report); }`
  - `class ConnectionReportInterceptor extends Interceptor { ConnectionReportInterceptor(ConnectionReports reports, {DateTime Function()? clock}); }`
  - `sealed class ConnectionBackoff { initial = 1 s; ceiling = 30 s; rateLimited = 60 s; static Duration next(Duration current); }`
  - `abstract class ConnectionSignals { Stream<void> get retries; bool get authFailed; }`
  - `class ConnectionCubit extends Cubit<AppConnectionState> implements ConnectionSignals` with `ConnectionCubit(ConnectionReports reports, Stream<MuxStatus> muxStatus, ServerConfigSource config, {Stream<String?>? desktopNames, DateTime Function()? clock})`, `ServerConfig? get config`, `void resumed()`
  - States: `sealed class AppConnectionState { String? desktopName; AppConnectionState withName(String? name); }`, `ConnectionConnectingState`, `ConnectionOnlineState({required DateTime updatedAt})`, `ConnectionOfflineState({required ConnectionFailure reason, DateTime? lastSeenAt})`, `ConnectionAuthFailedState({required int episode})`
  - `DioConsumer(ServerConfigSource source, {ConnectionReports? reports})`
  - `Stream<String?> ServerConfigStore.activeDesktopName`
  - `SessionsCubit(..., {ConnectionSignals? connection, DateTime Function()? clock})`, `NotificationsCubit(repository, store, {Duration unreadPoll, ConnectionSignals? connection})`
  - Test helper `ConnectionHarness` (`cubit`, `report(ConnectionOutcome, {String path})`, `muxStatus`, `names`, `dispose()`), `TestConfigSource`, `kTestDesktop`

- [ ] **Step 1: Write the failing tests.**

Create `test/helpers/connection_harness.dart`:

```dart
import 'dart:async';

import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

const kTestDesktop = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1');

class TestConfigSource implements ServerConfigSource {
  TestConfigSource([this.current = kTestDesktop]);

  final StreamController<ServerConfig?> controller = StreamController<ServerConfig?>.broadcast(sync: true);

  @override
  ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => controller.stream;

  void set(ServerConfig? next) {
    current = next;
    controller.add(next);
  }
}

class ConnectionHarness {
  ConnectionHarness({TestConfigSource? config, String? desktopName = 'Mac', DateTime Function()? clock})
    : config = config ?? TestConfigSource() {
    cubit = ConnectionCubit(reports, muxStatus.stream, this.config, desktopNames: names.stream, clock: clock);
    if (desktopName != null) names.add(desktopName);
  }

  final ConnectionReports reports = ConnectionReports();
  final StreamController<MuxStatus> muxStatus = StreamController<MuxStatus>.broadcast(sync: true);
  final StreamController<String?> names = StreamController<String?>.broadcast(sync: true);
  final TestConfigSource config;
  late final ConnectionCubit cubit;

  void report(ConnectionOutcome outcome, {String path = '/api/v1/sessions', DateTime? at}) =>
      reports.add(ConnectionReport(outcome, path: path, at: at ?? DateTime.now()));

  Future<void> dispose() async {
    await cubit.close();
    await muxStatus.close();
    await names.close();
    await config.controller.close();
  }
}
```

Create `test/core/connection/connection_cubit_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

import '../../helpers/connection_harness.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 25, 9);

  group('maps each outcome to its state', () {
    final cases = <ConnectionOutcome, Matcher>{
      ConnectionOutcome.online: isA<ConnectionOnlineState>(),
      ConnectionOutcome.unreachable:
          isA<ConnectionOfflineState>().having((s) => s.reason, 'reason', ConnectionFailure.unreachable),
      ConnectionOutcome.rateLimited:
          isA<ConnectionOfflineState>().having((s) => s.reason, 'reason', ConnectionFailure.rateLimited),
      ConnectionOutcome.serverError:
          isA<ConnectionOfflineState>().having((s) => s.reason, 'reason', ConnectionFailure.serverError),
      ConnectionOutcome.auth: isA<ConnectionAuthFailedState>(),
    };
    for (final entry in cases.entries) {
      test(entry.key.name, () async {
        final harness = ConnectionHarness();
        harness.report(entry.key, at: t0);
        expect(harness.cubit.state, entry.value);
        expect(harness.cubit.state.desktopName, 'Mac');
        await harness.dispose();
      });
    }
  });

  test('starts connecting', () async {
    final harness = ConnectionHarness();
    expect(harness.cubit.state, isA<ConnectionConnectingState>());
    await harness.dispose();
  });

  test('seeds itself from a report that landed before it existed', () async {
    final reports = ConnectionReports()
      ..add(ConnectionReport(ConnectionOutcome.auth, path: EndPoints.sessions, at: t0));

    final cubit = ConnectionCubit(reports, const Stream<MuxStatus>.empty(), TestConfigSource());

    expect(cubit.state, isA<ConnectionAuthFailedState>());
    await cubit.close();
  });

  test('offline remembers when the desktop was last seen', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.online, at: t0);
    harness.report(ConnectionOutcome.unreachable, at: t0.add(const Duration(minutes: 5)));

    expect(harness.cubit.state, isA<ConnectionOfflineState>().having((s) => s.lastSeenAt, 'lastSeenAt', t0));
    await harness.dispose();
  });

  test('backs off 1 s, 2 s, 4 s … up to 30 s while offline, and resets once online', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      final retriesAt = <int>[];
      harness.cubit.retries.listen((_) {
        retriesAt.add(async.elapsed.inSeconds);
        harness.report(ConnectionOutcome.unreachable);
      });

      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(seconds: 125));
      expect(retriesAt, [1, 3, 7, 15, 31, 61, 91, 121]);

      harness.report(ConnectionOutcome.online);
      retriesAt.clear();
      final back = async.elapsed.inSeconds;
      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(seconds: 2));
      expect(retriesAt, [back + 1]);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('rate-limited waits a full minute before the next probe', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);

      harness.report(ConnectionOutcome.rateLimited);
      async.elapse(const Duration(seconds: 59));
      expect(retries, 0);
      async.elapse(const Duration(seconds: 1));
      expect(retries, 1);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('an auth failure stops every retry, and neither /healthz nor more failures clear it', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);

      harness.report(ConnectionOutcome.unreachable);
      harness.report(ConnectionOutcome.auth);
      async.elapse(const Duration(minutes: 5));
      expect(retries, 0);
      expect(harness.cubit.authFailed, isTrue);

      harness.report(ConnectionOutcome.online, path: EndPoints.health);
      harness.report(ConnectionOutcome.unreachable);
      harness.cubit.resumed();
      async.elapse(const Duration(minutes: 1));
      expect(harness.cubit.state, isA<ConnectionAuthFailedState>());
      expect(retries, 0);

      harness.report(ConnectionOutcome.online);
      expect(harness.cubit.state, isA<ConnectionOnlineState>());
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('each auth episode is counted once', () async {
    final harness = ConnectionHarness();
    final episodes = <int>[];
    final sub = harness.cubit.stream.listen((state) {
      if (state is ConnectionAuthFailedState) episodes.add(state.episode);
    });

    harness.report(ConnectionOutcome.auth);
    harness.report(ConnectionOutcome.auth);
    harness.report(ConnectionOutcome.online);
    harness.report(ConnectionOutcome.auth);
    await Future<void>.delayed(Duration.zero);

    expect(episodes, [1, 2]);
    await sub.cancel();
    await harness.dispose();
  });

  test('resuming while offline probes at once and restarts the backoff', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);
      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(milliseconds: 500));

      harness.cubit.resumed();
      async.flushMicrotasks();
      expect(retries, 1);

      harness.report(ConnectionOutcome.online);
      harness.cubit.resumed();
      async.flushMicrotasks();
      expect(retries, 1);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('the mux opening means online, even after an auth failure', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.auth);

    harness.muxStatus.add(MuxStatus.open);

    expect(harness.cubit.state, isA<ConnectionOnlineState>());
    await harness.dispose();
  });

  test('a mux error while online asks for one probe instead of going offline', () async {
    final harness = ConnectionHarness();
    var retries = 0;
    harness.cubit.retries.listen((_) => retries++);
    harness.report(ConnectionOutcome.online);

    harness.muxStatus.add(MuxStatus.error);
    await Future<void>.delayed(Duration.zero);

    expect(harness.cubit.state, isA<ConnectionOnlineState>());
    expect(retries, 1);
    await harness.dispose();
  });

  test('a desktop change cancels the pending retry and starts connecting, keeping the name', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);
      harness.report(ConnectionOutcome.unreachable);

      harness.config.set(const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'd-2'));
      async.elapse(const Duration(seconds: 5));

      expect(retries, 0);
      expect(harness.cubit.state, isA<ConnectionConnectingState>());
      expect(harness.cubit.state.desktopName, 'Mac');
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('the desktop name follows the active desktop row', () async {
    final harness = ConnectionHarness(desktopName: null);
    harness.report(ConnectionOutcome.online);

    harness.names.add('MacBook');

    expect(harness.cubit.state, isA<ConnectionOnlineState>().having((s) => s.desktopName, 'name', 'MacBook'));
    await harness.dispose();
  });
}
```

Create `test/core/api/connection_report_interceptor_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/connection_report_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      respond(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  final at = DateTime.utc(2026, 9, 25, 9);

  Future<List<ConnectionReport>> outcomeOf(
    Future<ResponseBody> Function(RequestOptions options) respond, {
    Options? options,
  }) async {
    final reports = ConnectionReports();
    final seen = <ConnectionReport>[];
    reports.stream.listen(seen.add);
    final dio = Dio(BaseOptions(baseUrl: 'http://10.0.0.5:3011'))
      ..httpClientAdapter = _Adapter(respond)
      ..interceptors.add(ConnectionReportInterceptor(reports, clock: () => at));
    try {
      await dio.get<dynamic>(EndPoints.sessions, options: options);
    } on DioException {
      return seen;
    }
    return seen;
  }

  ResponseBody json(int status) =>
      ResponseBody.fromString('{}', status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  test('a response means online', () async {
    expect(await outcomeOf((_) async => json(200)), [ConnectionReport(ConnectionOutcome.online, path: EndPoints.sessions, at: at)]);
  });

  test('a 4xx other than auth and rate limit still means the desktop answered', () async {
    expect((await outcomeOf((_) async => json(404))).single.outcome, ConnectionOutcome.online);
  });

  test('401 and 403 mean auth', () async {
    expect((await outcomeOf((_) async => json(401))).single.outcome, ConnectionOutcome.auth);
    expect((await outcomeOf((_) async => json(403))).single.outcome, ConnectionOutcome.auth);
  });

  test('429 means rate-limited', () async {
    expect((await outcomeOf((_) async => json(429))).single.outcome, ConnectionOutcome.rateLimited);
  });

  test('5xx means a server error', () async {
    expect((await outcomeOf((_) async => json(503))).single.outcome, ConnectionOutcome.serverError);
  });

  test('timeouts and connection errors mean unreachable', () async {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.connectionError,
    ]) {
      final seen = await outcomeOf((options) async => throw DioException(requestOptions: options, type: type));
      expect(seen.single.outcome, ConnectionOutcome.unreachable, reason: type.name);
    }
  });

  test('a pairing probe aimed at an unsaved desktop reports nothing', () async {
    final seen = await outcomeOf(
      (_) async => json(401),
      options: Options(
        extra: {'pairingTarget': const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p')},
      ),
    );

    expect(seen, isEmpty);
  });

  test('a cancelled request reports nothing', () async {
    final seen = await outcomeOf(
      (options) async => throw DioException(requestOptions: options, type: DioExceptionType.cancel),
    );

    expect(seen, isEmpty);
  });
}
```

Append to `test/core/api/dio_consumer_headers_test.dart` (import `connection_report.dart` and `connection_report_interceptor.dart`):

```dart
  test('reports every outcome to the connection state and keeps the 12 s timeouts', () {
    final consumer = DioConsumer(_StaticConfig(), reports: ConnectionReports());

    expect(consumer.client.interceptors.whereType<ConnectionReportInterceptor>(), hasLength(1));
    expect(consumer.client.options.connectTimeout, const Duration(seconds: 12));
    expect(consumer.client.options.receiveTimeout, const Duration(seconds: 12));
  });
```

Append to `test/core/api/server_config_store_test.dart`:

```dart
  test('activeDesktopName follows the active desktop row', () async {
    when(() => local.watchAll()).thenAnswer(
      (_) => Stream.value(const [
        DesktopModel(id: 'b', name: 'iMac', isActive: false),
        DesktopModel(id: 'a', name: 'Mac', isActive: true),
      ]),
    );

    expect(await store.activeDesktopName.first, 'Mac');
  });
```

Append to `sessions_cubit_test.dart` (import `package:operator_mobile/core/connection/connection_signals.dart`):

```dart
  group('connection signals', () {
    late StreamController<void> retries;
    late _Signals signals;

    setUp(() {
      retries = StreamController<void>.broadcast();
      signals = _Signals(retries.stream);
    });

    tearDown(() => retries.close());

    test('a connection retry refreshes the board', () async {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(GlobalResponse(data: const BoardSnapshot()));
      });
      final cubit = SessionsCubit(repository, mux, source, connection: signals);
      await Future<void>.delayed(Duration.zero);
      expect(fetches, 1);

      retries.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(fetches, 2);
      await cubit.close();
    });

    test('resuming the app while re-pairing is needed spends no auth attempt', () async {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });
      final cubit = SessionsCubit(repository, mux, source, connection: signals);
      await Future<void>.delayed(Duration.zero);
      signals.authFailed = true;

      cubit.pauseUpdates();
      cubit.resumeUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(fetches, 1);
      await cubit.close();
    });
  });
```

and at the file's top level:

```dart
class _Signals implements ConnectionSignals {
  _Signals(this.retries);

  @override
  final Stream<void> retries;

  @override
  bool authFailed = false;
}
```

Append to `notifications_cubit_test.dart` (import `connection_signals.dart`; reuse a `_Signals` class defined the same way at its top level):

```dart
  test('a connection retry reloads the list', () async {
    final retries = StreamController<void>.broadcast();
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-1')]));
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
      connection: _Signals(retries.stream),
    );
    await Future<void>.delayed(Duration.zero);

    retries.add(null);
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getNotifications(any())).called(2);
    await cubit.close();
    await retries.close();
  });

  test('the unread poll holds while re-pairing is needed, so it spends no auth attempts', () async {
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([]));
    final signals = _Signals(const Stream.empty())..authFailed = true;
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
      connection: signals,
    );
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.refreshUnread();

    verifyNever(() => repository.getNotifications(any()));
    await cubit.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/connection test/core/api test/feature/sessions/presentation/sessions_screen/logic test/feature/notification/presentation`
Expected: FAIL to compile: `connection_cubit.dart`, `connection_report.dart` and `connection_report_interceptor.dart` not found; `reports`/`connection` named parameters and `activeDesktopName` not defined.

- [ ] **Step 3: Implement.**

`lib/core/connection/connection_report.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';

enum ConnectionOutcome { online, unreachable, auth, rateLimited, serverError }

class ConnectionReport extends Equatable {
  const ConnectionReport(this.outcome, {required this.path, required this.at});

  final ConnectionOutcome outcome;
  final String path;
  final DateTime at;

  @override
  List<Object?> get props => [outcome, path, at];
}

class ConnectionReports {
  final StreamController<ConnectionReport> _controller = StreamController<ConnectionReport>.broadcast(sync: true);
  ConnectionReport? _last;

  ConnectionReport? get last => _last;

  Stream<ConnectionReport> get stream => _controller.stream;

  void add(ConnectionReport report) {
    _last = report;
    _controller.add(report);
  }
}
```

`lib/core/connection/connection_backoff.dart`:

```dart
sealed class ConnectionBackoff {
  static const Duration initial = Duration(seconds: 1);
  static const Duration ceiling = Duration(seconds: 30);
  static const Duration rateLimited = Duration(seconds: 60);

  static Duration next(Duration current) {
    final doubled = current * 2;
    return doubled > ceiling ? ceiling : doubled;
  }
}
```

`lib/core/connection/connection_signals.dart`:

```dart
abstract class ConnectionSignals {
  Stream<void> get retries;
  bool get authFailed;
}
```

`lib/core/connection/connection_state.dart`:

```dart
part of 'connection_cubit.dart';

sealed class AppConnectionState extends Equatable {
  const AppConnectionState({this.desktopName});

  final String? desktopName;

  AppConnectionState withName(String? name);

  @override
  List<Object?> get props => [desktopName];
}

final class ConnectionConnectingState extends AppConnectionState {
  const ConnectionConnectingState({super.desktopName});

  @override
  ConnectionConnectingState withName(String? name) => ConnectionConnectingState(desktopName: name);
}

final class ConnectionOnlineState extends AppConnectionState {
  const ConnectionOnlineState({required this.updatedAt, super.desktopName});

  final DateTime updatedAt;

  @override
  ConnectionOnlineState withName(String? name) => ConnectionOnlineState(updatedAt: updatedAt, desktopName: name);

  @override
  List<Object?> get props => [updatedAt, desktopName];
}

final class ConnectionOfflineState extends AppConnectionState {
  const ConnectionOfflineState({required this.reason, this.lastSeenAt, super.desktopName});

  final ConnectionFailure reason;
  final DateTime? lastSeenAt;

  @override
  ConnectionOfflineState withName(String? name) =>
      ConnectionOfflineState(reason: reason, lastSeenAt: lastSeenAt, desktopName: name);

  @override
  List<Object?> get props => [reason, lastSeenAt, desktopName];
}

final class ConnectionAuthFailedState extends AppConnectionState {
  const ConnectionAuthFailedState({required this.episode, super.desktopName});

  final int episode;

  @override
  ConnectionAuthFailedState withName(String? name) => ConnectionAuthFailedState(episode: episode, desktopName: name);

  @override
  List<Object?> get props => [episode, desktopName];
}
```

`lib/core/connection/connection_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_backoff.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

part 'connection_state.dart';

class ConnectionCubit extends Cubit<AppConnectionState> implements ConnectionSignals {
  ConnectionCubit(
    this._reports,
    Stream<MuxStatus> muxStatus,
    this._config, {
    Stream<String?>? desktopNames,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ConnectionConnectingState()) {
    _reportSub = _reports.stream.listen(_onReport);
    _muxSub = muxStatus.listen(_onMux);
    _configSub = _config.changes.listen(_onConfig);
    _nameSub = desktopNames?.listen(_onName, onError: (Object _) {});
    final last = _reports.last;
    if (last != null) _onReport(last);
  }

  final ConnectionReports _reports;
  final ServerConfigSource _config;
  final DateTime Function() _clock;
  final StreamController<void> _retries = StreamController<void>.broadcast();

  StreamSubscription<ConnectionReport>? _reportSub;
  StreamSubscription<MuxStatus>? _muxSub;
  StreamSubscription<ServerConfig?>? _configSub;
  StreamSubscription<String?>? _nameSub;
  Timer? _retryTimer;
  Duration _delay = ConnectionBackoff.initial;
  DateTime? _lastSeenAt;
  int _episode = 0;

  ServerConfig? get config => _config.current;

  @override
  Stream<void> get retries => _retries.stream;

  @override
  bool get authFailed => state is ConnectionAuthFailedState;

  void resumed() {
    if (isClosed || state is! ConnectionOfflineState) return;
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _retries.add(null);
  }

  void _onReport(ConnectionReport report) {
    if (isClosed) return;
    switch (report.outcome) {
      case ConnectionOutcome.online:
        if (authFailed && report.path == EndPoints.health) return;
        _goOnline(report.at);
      case ConnectionOutcome.auth:
        _goAuthFailed();
      case ConnectionOutcome.unreachable:
        _goOffline(ConnectionFailure.unreachable);
      case ConnectionOutcome.rateLimited:
        _goOffline(ConnectionFailure.rateLimited);
      case ConnectionOutcome.serverError:
        _goOffline(ConnectionFailure.serverError);
    }
  }

  void _onMux(MuxStatus status) {
    if (isClosed || _config.current == null) return;
    if (status == MuxStatus.open) {
      _goOnline(_clock());
    } else if (status == MuxStatus.error && state is ConnectionOnlineState) {
      _retries.add(null);
    }
  }

  void _onConfig(ServerConfig? next) {
    if (isClosed) return;
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _lastSeenAt = null;
    emit(ConnectionConnectingState(desktopName: state.desktopName));
  }

  void _onName(String? name) {
    if (isClosed || name == state.desktopName) return;
    emit(state.withName(name));
  }

  void _goOnline(DateTime at) {
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _lastSeenAt = at;
    emit(ConnectionOnlineState(updatedAt: at, desktopName: state.desktopName));
  }

  void _goOffline(ConnectionFailure reason) {
    if (authFailed) return;
    emit(ConnectionOfflineState(reason: reason, lastSeenAt: _lastSeenAt, desktopName: state.desktopName));
    _scheduleRetry(reason);
  }

  void _goAuthFailed() {
    _cancelRetry();
    if (authFailed) return;
    _episode++;
    emit(ConnectionAuthFailedState(episode: _episode, desktopName: state.desktopName));
  }

  void _scheduleRetry(ConnectionFailure reason) {
    if (_retryTimer != null) return;
    final Duration wait;
    if (reason == ConnectionFailure.rateLimited) {
      wait = ConnectionBackoff.rateLimited;
    } else {
      wait = _delay;
      _delay = ConnectionBackoff.next(_delay);
    }
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      if (!isClosed && state is ConnectionOfflineState) _retries.add(null);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> close() async {
    _cancelRetry();
    await _reportSub?.cancel();
    await _muxSub?.cancel();
    await _configSub?.cancel();
    await _nameSub?.cancel();
    await _retries.close();
    return super.close();
  }
}
```

`lib/core/api/interceptors/connection_report_interceptor.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';

class ConnectionReportInterceptor extends Interceptor {
  ConnectionReportInterceptor(this._reports, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ConnectionReports _reports;
  final DateTime Function() _clock;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _report(response.requestOptions, ConnectionOutcome.online);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final outcome = _outcomeOf(err);
    if (outcome != null) _report(err.requestOptions, outcome);
    handler.next(err);
  }

  void _report(RequestOptions options, ConnectionOutcome outcome) {
    if (options.extra['pairingTarget'] != null) return;
    _reports.add(ConnectionReport(outcome, path: options.path, at: _clock()));
  }

  static ConnectionOutcome? _outcomeOf(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate => ConnectionOutcome.unreachable,
    DioExceptionType.badResponse => _fromStatus(error.response?.statusCode),
    DioExceptionType.cancel || DioExceptionType.unknown => null,
  };

  static ConnectionOutcome _fromStatus(int? status) {
    if (status == 401 || status == 403) return ConnectionOutcome.auth;
    if (status == 429) return ConnectionOutcome.rateLimited;
    if (status != null && status >= 500) return ConnectionOutcome.serverError;
    return ConnectionOutcome.online;
  }
}
```

`dio_consumer.dart`: change the constructor to take the reports and install the interceptor right after `ServerConfigInterceptor`:

```dart
  DioConsumer(this._configSource, {ConnectionReports? reports}) {
    setDefaultDioOptions();

    client.interceptors.add(ServerConfigInterceptor(_configSource));
    if (reports != null) client.interceptors.add(ConnectionReportInterceptor(reports));
```

with imports for `connection_report_interceptor.dart` and `connection_report.dart`.

`server_config_store.dart`, add:

```dart
  Stream<String?> get activeDesktopName => _desktops.watchAll().map((desktops) {
    for (final desktop in desktops) {
      if (desktop.isActive == true) return desktop.name;
    }
    return null;
  });
```

`sessions_cubit.dart` (import `connection_signals.dart`): the constructor becomes `SessionsCubit(this._repository, this._muxClient, this._configSource, {ConnectionSignals? connection, DateTime Function()? clock}) : _connection = connection, _clock = clock ?? DateTime.now, super(const SessionsInitialState()) {`. After `_configSub = ...` add `_retrySub = connection?.retries.listen((_) => unawaited(refresh()));`. Add fields `final ConnectionSignals? _connection;` and `StreamSubscription<void>? _retrySub;`. Replace `resumeUpdates`:

```dart
  void resumeUpdates() {
    if (!_paused) return;
    _paused = false;
    if (_connection?.authFailed ?? false) return;
    unawaited(refresh());
  }
```

and in `close()` add `unawaited(_retrySub?.cancel());`.

`notifications_cubit.dart` (import `connection_signals.dart`): the factory and private constructor take `ConnectionSignals? connection`:

```dart
  factory NotificationsCubit(
    NotificationRepository repository,
    ServerConfigStore serverConfigStore, {
    Duration unreadPoll = const Duration(seconds: 30),
    ConnectionSignals? connection,
  }) => NotificationsCubit._(repository, serverConfigStore, unreadPoll: unreadPoll, connection: connection);

  NotificationsCubit._(
    this._repository,
    this._serverConfigStore, {
    required this._unreadPoll,
    ConnectionSignals? connection,
  }) : _connection = connection,
       super(const NotificationsInitialState()) {
    _configSub = _serverConfigStore.changes.listen(_onConfigChanged);
    _retrySub = connection?.retries.listen((_) => unawaited(load()));
    unawaited(_start(_epoch));
    _timer = Timer.periodic(_unreadPoll, (_) => unawaited(refreshUnread()));
  }
```

Add fields `final ConnectionSignals? _connection;` and `StreamSubscription<void>? _retrySub;`. Make `refreshUnread` start with `if (!_hasServer || (_connection?.authFailed ?? false)) return;`, and cancel `_retrySub` in `close()`.

`service_locator.dart`:
- in `_coreSetup`, register before `ApiConsumer`:

```dart
    sl.registerLazySingleton<ConnectionReports>(ConnectionReports.new);
```

- change the `ApiConsumer` registration to `() => DioConsumer(sl<ServerConfigStore>(), reports: sl<ConnectionReports>())`;
- after the `MuxClient` registration, add:

```dart
    sl.registerLazySingleton<ConnectionCubit>(
      () => ConnectionCubit(
        sl<ConnectionReports>(),
        sl<MuxClient>().status,
        sl<ServerConfigStore>(),
        desktopNames: sl<ServerConfigStore>().activeDesktopName,
      ),
    );
```

- pass `connection: sl<ConnectionCubit>()` into the `SessionsCubit` and `NotificationsCubit` registrations;
- import `connection_cubit.dart` and `connection_report.dart`.

`main.dart` (import `connection_cubit.dart` and `package:flutter_bloc/flutter_bloc.dart` is already there):
- right after `await AppPreferences.load(sl<SettingsDao>());`, add `sl<ConnectionCubit>();` so it exists before the first request;
- in `_OperatorAppState`, change the lifecycle to

```dart
  late final AppLifecycleListener _lifecycle = phoneAlertsLifecycle(
    () => sl<PhoneAlertsRuntime>(),
    onResume: () {
      unawaited(TelemetryRuntime.active());
      sl<ConnectionCubit>().resumed();
    },
  );
```

- in `build`, replace `BlocProvider(create: (context) => SkinCubit(), child: BlocBuilder<SkinCubit, SkinState>(...))` with a `MultiBlocProvider` whose providers are `BlocProvider(create: (context) => SkinCubit())` and `BlocProvider<ConnectionCubit>.value(value: sl<ConnectionCubit>())`, keeping the same `BlocBuilder<SkinCubit, SkinState>` child.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/core test/feature/sessions test/feature/notification`
Expected: PASS.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Commit.**

```bash
git add lib/core/connection lib/core/api lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart \
  lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart \
  lib/core/utils/service_locator.dart lib/main.dart test/helpers test/core/connection test/core/api \
  test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart \
  test/feature/notification/presentation/notifications_screen/logic/notifications_cubit_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): one ConnectionCubit fed by every HTTP outcome and the mux

A ConnectionReportInterceptor turns each response into online, unreachable,
auth, rate-limited or server error. ConnectionCubit backs off 1 s to 30 s
while offline, waits a minute when rate-limited, and stops entirely on an
auth failure so a rotated password cannot trip the lockout. The board and
notifications refresh on its retries, and it lives at the app root so the
chat can read it too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8: Header status line, skeletons, full-screen error and empty board

**Files:**
- Create: `packages/mobile/lib/core/connection/connection_status_line.dart`
- Create: `packages/mobile/lib/core/widgets/connection/desktop_status_line.dart`
- Create: `packages/mobile/lib/core/widgets/connection/connection_error_state.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/board_skeleton.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/home_title.dart`
- Modify: `packages/mobile/lib/core/error_handling/connection_error.dart:47-76`
- Modify: `packages/mobile/lib/core/app_themes/app_motion.dart` (add `statusLineTick`)
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart:25-28`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart:75-84`, `:192-217`
- Modify: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart:19`
- Test: create `test/core/connection/connection_status_line_test.dart`, `test/core/widgets/connection/desktop_status_line_test.dart`, `test/core/widgets/connection/connection_error_state_test.dart`; add to `test/core/error_handling/connection_error_test.dart`, `sessions_body_test.dart`, `home_shell_test.dart`

**Interfaces:**
- Consumes: `ConnectionCubit`, `AppConnectionState` subclasses, `ConnectionHarness` (Task 7); `SessionsCubit.boardFetchedAt` (Task 4).
- Produces:
  - `enum StatusTone { neutral, attention, danger }`, `class StatusLine { final String text; final StatusTone tone; final bool busy; }`, `StatusLine connectionStatusLine(AppConnectionState state, {required DateTime now, DateTime? fetchedAt})`
  - `DesktopStatusLine({required DateTime? fetchedAt, required VoidCallback onTap, VoidCallback? onRePair, DateTime Function() clock = DateTime.now})`, `static const Key tapKey`
  - `ConnectionErrorState({required ConnectionFailure reason, required String host, required String port, required VoidCallback onRetry, required VoidCallback onSwitchDesktop, String? desktopName, VoidCallback? onRePair})` with `retryKey`, `switchKey`
  - `BoardSkeleton` (`cardCount = 6`)
  - `HomeTitle({required String title})`
  - `describeConnectionFailure(..., String? desktopName)`: unreachable titles read `Can't reach <desktopName>` when a name is given
  - `AppMotion.statusLineTick = Duration(seconds: 30)`

- [ ] **Step 1: Write the failing tests.**

Create `test/core/connection/connection_status_line_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_status_line.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  test('connecting shows a spinner', () {
    final line = connectionStatusLine(const ConnectionConnectingState(), now: now);
    expect(line.text, 'Connecting…');
    expect(line.busy, isTrue);
    expect(line.tone, StatusTone.neutral);
  });

  test('online reads updated just now, then minutes once the data is over a minute old', () {
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(seconds: 40))), now: now).text,
      'Updated just now',
    );
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(minutes: 5))), now: now).text,
      'Updated 5m ago',
    );
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(hours: 3))), now: now).text,
      'Updated 3h ago',
    );
  });

  test('offline names when the desktop was last seen, falling back to the cached board time', () {
    final seen = ConnectionOfflineState(
      reason: ConnectionFailure.unreachable,
      lastSeenAt: now.subtract(const Duration(minutes: 5)),
    );
    final line = connectionStatusLine(seen, now: now);
    expect(line.text, 'Offline · last seen 5m ago');
    expect(line.tone, StatusTone.attention);

    const coldStart = ConnectionOfflineState(reason: ConnectionFailure.unreachable);
    expect(
      connectionStatusLine(coldStart, now: now, fetchedAt: now.subtract(const Duration(days: 2))).text,
      'Offline · last seen 2d ago',
    );
    expect(connectionStatusLine(coldStart, now: now).text, 'Offline');
  });

  test('auth failure asks for re-pairing in red', () {
    final line = connectionStatusLine(const ConnectionAuthFailedState(episode: 1), now: now);
    expect(line.text, 'Needs re-pairing');
    expect(line.tone, StatusTone.danger);
  });
}
```

Create `test/core/widgets/connection/desktop_status_line_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/widgets/connection/desktop_status_line.dart';

import '../../../helpers/connection_harness.dart';

void main() {
  late ConnectionHarness harness;
  final now = DateTime.utc(2026, 9, 25, 12);

  setUp(() => harness = ConnectionHarness(clock: () => now));
  tearDown(() => harness.dispose());

  Future<void> pump(WidgetTester tester, {VoidCallback? onTap, VoidCallback? onRePair, DateTime? fetchedAt}) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<ConnectionCubit>.value(
                value: harness.cubit,
                child: Center(
                  child: DesktopStatusLine(
                    fetchedAt: fetchedAt,
                    onTap: onTap ?? () {},
                    onRePair: onRePair,
                    clock: () => now,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('names the desktop beside its status', (tester) async {
    harness.report(ConnectionOutcome.online, at: now);
    await pump(tester);

    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
  });

  testWidgets('offline reads in the warning hue, with the cached board time on a cold start', (tester) async {
    harness.report(ConnectionOutcome.unreachable, at: now);
    await pump(tester, fetchedAt: now.subtract(const Duration(minutes: 5)));

    final text = tester.widget<Text>(find.text('Offline · last seen 5m ago'));
    expect(text.style?.color, const DarkSkin().amber);
  });

  testWidgets('tapping opens the desktop list', (tester) async {
    var taps = 0;
    harness.report(ConnectionOutcome.online, at: now);
    await pump(tester, onTap: () => taps++);

    await tester.tap(find.byKey(DesktopStatusLine.tapKey));

    expect(taps, 1);
  });

  testWidgets('after an auth failure the line reads Needs re-pairing and tapping re-pairs', (tester) async {
    var taps = 0;
    var rePairs = 0;
    harness.report(ConnectionOutcome.auth, at: now);
    await pump(tester, onTap: () => taps++, onRePair: () => rePairs++);

    expect(find.text('Needs re-pairing'), findsOneWidget);
    await tester.tap(find.byKey(DesktopStatusLine.tapKey));

    expect(rePairs, 1);
    expect(taps, 0);
  });
}
```

Create `test/core/widgets/connection/connection_error_state_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/connection/connection_error_state.dart';

void main() {
  Future<({List<String> calls})> pump(
    WidgetTester tester,
    ConnectionFailure reason, {
    String host = '10.0.0.5',
    TargetPlatform platform = TargetPlatform.iOS,
    bool rePair = false,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: ConnectionErrorState(
                reason: reason,
                host: host,
                port: '3011',
                desktopName: 'MacBook',
                onRetry: () => calls.add('retry'),
                onSwitchDesktop: () => calls.add('switch'),
                onRePair: rePair ? () => calls.add('re-pair') : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return (calls: calls);
  }

  testWidgets('unreachable names the desktop, the address and the local network hint', (tester) async {
    await pump(tester, ConnectionFailure.unreachable);

    expect(find.text("Can't reach MacBook"), findsOneWidget);
    expect(find.textContaining('10.0.0.5:3011'), findsOneWidget);
    expect(find.text(kLocalNetworkHint), findsOneWidget);
  });

  testWidgets('Retry is primary and Switch desktop is secondary', (tester) async {
    final result = await pump(tester, ConnectionFailure.serverError, host: 'mac.tail0.ts.net');

    expect(find.text('Your desktop returned an error'), findsOneWidget);
    expect(find.text(kLocalNetworkHint), findsNothing);
    await tester.tap(find.byKey(ConnectionErrorState.retryKey));
    await tester.tap(find.byKey(ConnectionErrorState.switchKey));

    expect(result.calls, ['retry', 'switch']);
  });

  testWidgets('rate-limited explains the lockout', (tester) async {
    await pump(tester, ConnectionFailure.rateLimited);

    expect(find.text('Too many attempts'), findsOneWidget);
  });

  testWidgets('an auth failure offers Re-pair instead of a retry that would spend an attempt', (tester) async {
    final result = await pump(tester, ConnectionFailure.auth, rePair: true);

    expect(find.text('Re-pair'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.byKey(ConnectionErrorState.retryKey));

    expect(result.calls, ['re-pair']);
  });
}
```

Append inside `group('describeConnectionFailure', ...)` in `test/core/error_handling/connection_error_test.dart`:

```dart
    test('names the desktop when one is known, and keeps the pairing copy when not', () {
      final named = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: '10.0.0.5',
        port: '3011',
        platform: TargetPlatform.android,
        desktopName: 'MacBook',
      );
      final unnamed = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: '10.0.0.5',
        port: '3011',
        platform: TargetPlatform.android,
      );

      expect(named.title, "Can't reach MacBook");
      expect(unnamed.title, 'Your desktop disconnected');
    });
```

In `sessions_body_test.dart`: add imports for `dart:async`, `connection_cubit.dart`, `failure.dart`, `routes_strings.dart`, `board_skeleton.dart`, `connection_error_state.dart`, `replicated.dart` and `'../../../../../helpers/connection_harness.dart'`. Add `late ConnectionHarness connection;` to `main`, create it in `setUp` (`connection = ConnectionHarness();`) and dispose it in `tearDown` (`await connection.dispose();`, making that `tearDown` async). In `pumpBody`, wrap the existing `BlocProvider` in a `MultiBlocProvider` that also provides `BlocProvider<ConnectionCubit>.value(value: connection.cubit)`, and change `onGenerateRoute` so routes without a session id still build:

```dart
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => Text(
              settings.name == RoutesStrings.session
                  ? (settings.arguments as Map<String, dynamic>)['sessionId'] as String
                  : 'route ${settings.name}',
            ),
          ),
```

`SessionsBody` opens a card with `RoutesStrings.session`, so the existing session-id assertions keep matching. Then add a helper and the tests:

```dart
  Future<void> pumpWithBoard(WidgetTester tester, Future<Result<GlobalResponse<BoardSnapshot>, Failure>> Function() board) async {
    when(() => repository.getBoard()).thenAnswer((_) => board());
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => Text('route ${settings.name}')),
          home: SkinScope(
            skin: const DarkSkin(),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConnectionCubit>.value(value: connection.cubit),
                BlocProvider(create: (_) => SessionsCubit(repository, mux, const _StubConfigSource())),
              ],
              child: const Scaffold(body: SessionsBody()),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('start states', () {
    testWidgets('with nothing cached, six skeleton cards stand in until the board arrives', (tester) async {
      final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      await pumpWithBoard(tester, () => gate.future);

      expect(find.byType(BoardSkeleton), findsOneWidget);
      expect(find.text('No agents yet'), findsNothing);

      gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot(
        sessions: [SessionModel(id: 'w-1', displayName: 'Worker', status: 'working')],
      ))));
      await settle(tester);

      expect(find.byType(BoardSkeleton), findsNothing);
      expect(find.text('Worker'), findsOneWidget);
    });

    testWidgets('with nothing cached and the desktop down, a full-screen error names it and offers a way forward', (tester) async {
      await pumpWithBoard(
        tester,
        () async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      expect(find.byType(ConnectionErrorState), findsOneWidget);
      expect(find.text("Can't reach Mac"), findsOneWidget);
      expect(find.byKey(ConnectionErrorState.retryKey), findsOneWidget);
      expect(find.byKey(ConnectionErrorState.switchKey), findsOneWidget);
    });

    testWidgets('Retry on the full-screen error fetches the board again', (tester) async {
      var fetches = 0;
      await pumpWithBoard(tester, () async {
        fetches++;
        return Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6));
      });

      await tester.tap(find.byKey(ConnectionErrorState.retryKey));
      await settle(tester);

      expect(fetches, 2);
    });

    testWidgets('with a cached board, a failure keeps the board on screen', (tester) async {
      when(() => repository.cachedBoard()).thenAnswer(
        (_) async => Replicated(
          value: const BoardSnapshot(sessions: [SessionModel(id: 'w-1', displayName: 'Cached worker', status: 'working')]),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );
      await pumpWithBoard(
        tester,
        () async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      expect(find.text('Cached worker'), findsOneWidget);
      expect(find.byType(ConnectionErrorState), findsNothing);
    });

    testWidgets('an empty board online invites the first spawn toward the + button', (tester) async {
      await pumpWithBoard(tester, () async => Result.success(GlobalResponse(data: const BoardSnapshot())));

      expect(find.text('No agents yet'), findsOneWidget);
      expect(find.text('Spawn your first agent'), findsOneWidget);
      expect(find.byIcon(Icons.south_east_rounded), findsOneWidget);
    });
  });
```

In `test/core/app_routes/home_shell_test.dart`: import `connection_cubit.dart`, `connection_report.dart` and `'../../helpers/connection_harness.dart'`. Add `late ConnectionHarness connection;`, create it at the end of `setUp`, and add `await connection.dispose();` to `tearDown`. Add `BlocProvider<ConnectionCubit>.value(value: connection.cubit)` to `pumpShell`'s providers. Then add:

```dart
  testWidgets('the Agents header names the desktop and its status, and tapping it opens the desktop list', (tester) async {
    connection.report(ConnectionOutcome.online);
    await pumpShell(tester);

    expect(find.text('Mac'), findsWidgets);
    expect(find.text('Updated just now'), findsWidgets);

    await tester.tap(find.byKey(DesktopStatusLine.tapKey).first);
    await settle(tester);

    expect(find.text('route /connections'), findsOneWidget);
  });

  testWidgets('a cached board stays up under an offline header on a cold start', (tester) async {
    when(() => repository.cachedBoard()).thenAnswer(
      (_) async => Replicated(
        value: const BoardSnapshot(
          sessions: [SessionModel(id: 'w-1', projectId: 'proj', displayName: 'Cached worker', status: 'working')],
        ),
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
    );
    connection.report(ConnectionOutcome.unreachable);
    await pumpShell(tester);

    expect(find.text('Cached worker'), findsOneWidget);
    expect(find.text('Offline · last seen 5m ago'), findsWidgets);
  });
```

(import `desktop_status_line.dart`, `replicated.dart` and `failure.dart` if the file lacks them).

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/connection/connection_status_line_test.dart test/core/widgets/connection test/core/error_handling test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart test/core/app_routes/home_shell_test.dart`
Expected: FAIL to compile: `connection_status_line.dart`, `desktop_status_line.dart`, `connection_error_state.dart` and `board_skeleton.dart` not found, and no `desktopName` parameter.

- [ ] **Step 3: Implement.**

`lib/core/app_themes/app_motion.dart`, add beside the other durations:

```dart
  static const Duration statusLineTick = Duration(seconds: 30);
```

`lib/core/error_handling/connection_error.dart`: add `String? desktopName,` to `describeConnectionFailure`'s named parameters, and make the unreachable case's title:

```dart
        title: desktopName == null ? 'Your desktop disconnected' : "Can't reach $desktopName",
```

Create `lib/core/connection/connection_status_line.dart`:

```dart
import 'package:operator_mobile/core/connection/connection_cubit.dart';

enum StatusTone { neutral, attention, danger }

class StatusLine {
  const StatusLine(this.text, {this.tone = StatusTone.neutral, this.busy = false});

  final String text;
  final StatusTone tone;
  final bool busy;
}

StatusLine connectionStatusLine(AppConnectionState state, {required DateTime now, DateTime? fetchedAt}) =>
    switch (state) {
      ConnectionConnectingState() => const StatusLine('Connecting…', busy: true),
      ConnectionOnlineState(:final updatedAt) => StatusLine(_updated(now.difference(updatedAt))),
      ConnectionOfflineState(:final lastSeenAt) => StatusLine(
        _offline(lastSeenAt ?? fetchedAt, now),
        tone: StatusTone.attention,
      ),
      ConnectionAuthFailedState() => const StatusLine('Needs re-pairing', tone: StatusTone.danger),
    };

String _updated(Duration age) => age < const Duration(minutes: 1) ? 'Updated just now' : 'Updated ${_ago(age)} ago';

String _offline(DateTime? seen, DateTime now) {
  if (seen == null) return 'Offline';
  final age = now.difference(seen);
  return age < const Duration(minutes: 1) ? 'Offline · last seen just now' : 'Offline · last seen ${_ago(age)} ago';
}

String _ago(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  return '${age.inDays}d';
}
```

Create `lib/core/widgets/connection/desktop_status_line.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_status_line.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class DesktopStatusLine extends StatefulWidget {
  const DesktopStatusLine({
    super.key,
    required this.fetchedAt,
    required this.onTap,
    this.onRePair,
    this.clock = DateTime.now,
  });

  static const Key tapKey = ValueKey('desktop-status-line');

  final DateTime? fetchedAt;
  final VoidCallback onTap;
  final VoidCallback? onRePair;
  final DateTime Function() clock;

  @override
  State<DesktopStatusLine> createState() => _DesktopStatusLineState();
}

class _DesktopStatusLineState extends State<DesktopStatusLine> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(AppMotion.statusLineTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<ConnectionCubit, AppConnectionState>(
      builder: (context, state) {
        final line = connectionStatusLine(state, now: widget.clock(), fetchedAt: widget.fetchedAt);
        final color = switch (line.tone) {
          StatusTone.neutral => skin.textTertiary,
          StatusTone.attention => skin.amber,
          StatusTone.danger => skin.red,
        };
        final name = state.desktopName;
        final action = state is ConnectionAuthFailedState ? widget.onRePair ?? widget.onTap : widget.onTap;
        return Semantics(
          button: true,
          label: '${name ?? 'Desktop'}, ${line.text}',
          excludeSemantics: true,
          child: GestureDetector(
            key: DesktopStatusLine.tapKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.select();
              action();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.busy) ...[
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(strokeWidth: 1.4, color: skin.textTertiary),
                  ),
                  const HorizontalSpace(5),
                ],
                if (name != null) ...[
                  Flexible(
                    child: AppText(
                      name,
                      style: AppTextStyle.style12SemiBold.copyWith(color: skin.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppText(' · ', style: AppTextStyle.style12Regular.copyWith(color: skin.textFaint)),
                ],
                Flexible(
                  child: AppText(
                    line.text,
                    style: AppTextStyle.style12Medium.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const HorizontalSpace(2),
                Icon(Icons.expand_more_rounded, size: 14, color: skin.textFaint),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

Create `lib/core/widgets/connection/connection_error_state.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/fade_up_entrance.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionErrorState extends StatelessWidget {
  const ConnectionErrorState({
    super.key,
    required this.reason,
    required this.host,
    required this.port,
    required this.onRetry,
    required this.onSwitchDesktop,
    this.desktopName,
    this.onRePair,
  });

  static const Key retryKey = ValueKey('connection-error-retry');
  static const Key switchKey = ValueKey('connection-error-switch');

  final ConnectionFailure reason;
  final String host;
  final String port;
  final String? desktopName;
  final VoidCallback onRetry;
  final VoidCallback onSwitchDesktop;
  final VoidCallback? onRePair;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final copy = describeConnectionFailure(
      reason,
      host: host,
      port: port,
      platform: Theme.of(context).platform,
      desktopName: desktopName,
    );
    final rePair = copy.isAuth ? onRePair : null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        child: FadeUpEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: skin.bgElevated, shape: BoxShape.circle),
                child: Icon(
                  copy.isAuth ? Icons.lock_outline_rounded : Icons.wifi_off_rounded,
                  size: 32,
                  color: copy.isAuth ? skin.red : skin.textSecondary,
                ),
              ),
              const VerticalSpace(20),
              AppText(
                copy.title,
                style: AppTextStyle.style21Bold.copyWith(letterSpacing: -0.3),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              const VerticalSpace(8),
              AppText(
                copy.message,
                style: AppTextStyle.style13p5Regular.copyWith(color: skin.textSecondary, height: 1.45),
                textAlign: TextAlign.center,
                maxLines: 4,
              ),
              if (copy.showLocalNetworkHint) ...[
                const VerticalSpace(10),
                AppText(
                  kLocalNetworkHint,
                  style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                ),
              ],
              const VerticalSpace(24),
              PrimaryButton(
                key: retryKey,
                text: rePair == null ? 'Retry' : 'Re-pair',
                onPressed: rePair ?? onRetry,
              ),
              const VerticalSpace(6),
              TextButton(
                key: switchKey,
                onPressed: onSwitchDesktop,
                child: AppText(
                  'Switch desktop',
                  style: AppTextStyle.style13p5Medium.copyWith(color: skin.accentText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `lib/feature/sessions/presentation/sessions_screen/ui/widgets/board_skeleton.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';

class BoardSkeleton extends StatelessWidget {
  const BoardSkeleton({super.key});

  static const int cardCount = 6;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return Semantics(
      label: 'Loading agents',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: insets.top + 12, bottom: insets.bottom + 40),
        children: [for (var i = 0; i < cardCount; i++) const _SkeletonCard()],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget bar(double width, double height, {double radius = AppConstants.radiusSm}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: skin.shimmerBase, borderRadius: BorderRadius.circular(radius)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AppContainer(
        padding: const EdgeInsets.all(13),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: skin.borderDefault),
        child: Shimmer(
          base: skin.shimmerBase,
          highlight: skin.shimmerHi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  bar(20, 20, radius: AppConstants.radiusPill),
                  const HorizontalSpace(9),
                  bar(150, 14),
                  const Spacer(),
                  bar(64, 20, radius: AppConstants.radiusPill),
                ],
              ),
              const VerticalSpace(10),
              Padding(padding: const EdgeInsets.only(left: 29), child: bar(210, 11)),
              const VerticalSpace(7),
              Padding(padding: const EdgeInsets.only(left: 29), child: bar(120, 11)),
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `lib/feature/sessions/presentation/sessions_screen/ui/widgets/home_title.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/connection/desktop_status_line.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class HomeTitle extends StatelessWidget {
  const HomeTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(title, style: AppTextStyle.style19SemiBold.copyWith(letterSpacing: -0.3)),
      BlocBuilder<SessionsCubit, SessionsState>(
        buildWhen: (previous, current) =>
            current is SessionsInitialState || current is GetSessionsSuccessState || current is GetSessionsFailureState,
        builder: (context, state) => DesktopStatusLine(
          fetchedAt: context.read<SessionsCubit>().boardFetchedAt,
          onTap: () => Navigator.of(context).pushNamed(RoutesStrings.connections),
        ),
      ),
    ],
  );
}
```

`sessions_screen.dart`: replace the `title:` line with `title: const HomeTitle(title: 'Agents'),` (import `home_title.dart`; the `AppText`/`AppTextStyle` imports go if now unused).

`pull_requests_screen.dart`: replace `appBar: const GlobalAppbar.main(titleText: 'Pull Requests'),` with `appBar: const GlobalAppbar.main(title: HomeTitle(title: 'Pull Requests')),` and import `home_title.dart`.

`sessions_body.dart`:
1. Imports: drop `app_error_widget.dart` and `app_loader.dart`; add `connection_cubit.dart`, `connection_error.dart`, `failure.dart`, `connection_error_state.dart` and `board_skeleton.dart`.
2. Replace the `buildWhen` and the two early returns at `:75-84` with:

```dart
    return BlocBuilder<SessionsCubit, SessionsState>(
      buildWhen: (previous, current) =>
          current is SessionsInitialState ||
          current is GetSessionsLoadingState ||
          current is GetSessionsSuccessState ||
          current is GetSessionsFailureState,
      builder: (context, state) {
        if (cubit.boardFetchedAt == null) {
          if (state is GetSessionsFailureState) return _BoardError(failure: state.failure, onRetry: cubit.refresh);
          return const BoardSkeleton();
        }
```

3. Replace the `AppEmptyState(...)` block at `:192-217` with:

```dart
              if (grouped.sections.isEmpty && grouped.archived.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 80), child: _EmptyBoard()),
```

4. Add at the bottom of the file:

```dart
class _BoardError extends StatelessWidget {
  const _BoardError({required this.failure, required this.onRetry});

  final Failure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionCubit>();
    final config = connection.config;
    return ConnectionErrorState(
      reason: classifyConnectionFailure(failure.statusCode),
      host: config?.host ?? '',
      port: config?.httpPort ?? '',
      desktopName: connection.state.desktopName,
      onRetry: () => unawaited(onRetry()),
      onSwitchDesktop: () => Navigator.of(context).pushNamed(RoutesStrings.connections),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppEmptyState(
      title: 'No agents yet',
      message: 'Spawn your first agent',
      action: Align(
        alignment: Alignment.centerRight,
        child: Icon(Icons.south_east_rounded, size: 28, color: skin.textTertiary, semanticLabel: 'The + button'),
      ),
    );
  }
}
```

(add `import 'dart:async';`; `PrimaryButton` is no longer used here, so drop its import if the analyzer says so).

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/core test/feature/sessions test/feature/pull_request`
Expected: PASS.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Simulator capture (dark and light) into `build/start-flow/task-8/`.**

```bash
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
mkdir -p build/start-flow/task-8
```

For each screen below, launch with `xcrun simctl launch --terminate-running-process booted dev.operator.operatorMobile`, then run `xcrun simctl ui booted appearance dark` and `xcrun simctl io booted screenshot build/start-flow/task-8/<name>-dark.png`, and repeat with `light`:
- `online`: paired and reachable, the header reads `<name> · Updated just now`
- `cached-offline`: open once while online so the cache fills, ask the user to turn Connect Mobile off, then relaunch. Expect the cached board and `Offline · last seen …` in amber.
- `no-cache-offline`: Settings → Disconnect, re-pair, turn Connect Mobile off before the first board loads (or pair a second desktop that is off), then relaunch. Expect the full-screen error `Can't reach <name>` with Retry and Switch desktop.
- `empty`: a desktop with no sessions. Expect "No agents yet".

Compare the dark shots against the approved glass look: the tab bar, the **+** and the frosted header must be unchanged apart from the new status line.

- [ ] **Step 7: Commit.**

```bash
git add lib/core/connection/connection_status_line.dart lib/core/widgets/connection lib/core/error_handling/connection_error.dart \
  lib/core/app_themes/app_motion.dart lib/feature/sessions/presentation/sessions_screen/ui \
  lib/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart \
  test/core/connection/connection_status_line_test.dart test/core/widgets/connection test/core/error_handling \
  test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart test/core/app_routes/home_shell_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): say which desktop and how fresh, and never show a bare error

The Agents and PRs headers carry the desktop's name and a status line:
connecting, updated, offline with when it was last seen, or needs
re-pairing. With nothing cached the board shows six skeleton cards, and a
failure becomes a full-screen state with Retry and Switch desktop. An
empty board invites the first spawn.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 9: The dimmed **+** and the re-pair sheet

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart`
- Modify: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart:15-20`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:122-125`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart:62`
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart` (the **+** at `:140-147`, and the auth listener around the `Scaffold`)
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/home_title.dart`, `sessions_body.dart` (`_BoardError`)
- Test: create `test/feature/pairing/presentation/re_pair_sheet/re_pair_sheet_test.dart`; add to `manual_connect_cubit_test.dart` and `home_shell_test.dart`

**Interfaces:**
- Consumes: `ConnectionCubit` and its states, `ManualConnectCubit`, `showAppSheet`, `AppSheetPage`, `AppToast`, `Haptics`, `ConnectionFailureBanner`.
- Produces:
  - `enum ManualConnectMode { manual, rePair }`; `ManualConnectCubit(PairingRepository repository, ServerConfigStore store, {ManualConnectMode mode = ManualConnectMode.manual})`. In `rePair` mode the host is prefilled and the password starts empty.
  - `sl<ManualConnectCubit>(param1: ManualConnectMode)` (a `registerFactoryParam`)
  - `Future<void> showRePairSheet(BuildContext context)`; `class RePairForm` with `hostKey`, `reconnectKey`, `scanKey`
  - `HomeShell.offlineSpawnOpacity = 0.4`, `HomeShell.offlineSpawnMessage = 'Needs a connection to your desktop'`
  - `HomeTitle` and `_BoardError` pass `onRePair: () => showRePairSheet(context)`

- [ ] **Step 1: Write the failing tests.**

Append to `manual_connect_cubit_test.dart`:

```dart
  blocTest<ManualConnectCubit, ManualConnectState>(
    're-pair mode keeps the paired host and asks for a fresh password',
    build: () {
      when(() => store.current).thenReturn(
        const ServerConfig(host: '10.0.0.5', httpPort: '58682', secure: true, password: 'rotated-away'),
      );
      return ManualConnectCubit(repository, store, mode: ManualConnectMode.rePair);
    },
    verify: (cubit) {
      expect(cubit.hostController.text, '10.0.0.5:58682');
      expect(cubit.passwordController.text, isEmpty);
      expect(cubit.secure, isTrue);
    },
  );
```

Create `test/feature/pairing/presentation/re_pair_sheet/re_pair_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';

import '../../../../helpers/connection_harness.dart';

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late ConnectionHarness connection;
  late _MockPairingRepository repository;
  final notified = <String>[];

  setUpAll(() => registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: '')));

  setUp(() async {
    connection = ConnectionHarness();
    repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(kTestDesktop);
    await sl.reset();
    sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
      (mode, _) => ManualConnectCubit(repository, store, mode: mode),
    );
    notified.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        notified.add(call.arguments as String);
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
    await sl.reset();
    await connection.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}')),
            home: BlocProvider<ConnectionCubit>.value(
              value: connection.cubit,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(onPressed: () => showRePairSheet(context), child: const Text('open')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the desktop and shows its host, with an empty password', (tester) async {
    connection.report(ConnectionOutcome.auth);
    await open(tester);

    expect(find.text('Re-pair Mac'), findsOneWidget);
    expect(find.descendant(of: find.byKey(RePairForm.hostKey), matching: find.text('10.0.0.5')), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
  });

  testWidgets('a good password reconnects and closes the sheet', (tester) async {
    when(() => repository.verifyAndConnect(any())).thenAnswer(
      (_) async => Result.success(const DesktopModel(id: 'd-1', name: 'Mac')),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'fresh-password');
    await tester.tap(find.byKey(RePairForm.reconnectKey));
    await tester.pumpAndSettle();

    final target = verify(() => repository.verifyAndConnect(captureAny())).captured.single as ServerConfig;
    expect(target.password, 'fresh-password');
    expect(target.host, '10.0.0.5');
    expect(find.byType(RePairForm), findsNothing);
    expect(notified, ['success']);
  });

  testWidgets('a wrong password keeps the sheet open with the reason', (tester) async {
    when(() => repository.verifyAndConnect(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'still-wrong');
    await tester.tap(find.byKey(RePairForm.reconnectKey));
    await tester.pumpAndSettle();

    expect(find.byType(RePairForm), findsOneWidget);
    expect(find.text('Your desktop rejected the password'), findsOneWidget);
    expect(notified, ['warning']);
  });

  testWidgets('Scan the code instead closes the sheet and opens the scanner', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(RePairForm.scanKey));
    await tester.pumpAndSettle();

    expect(find.text('route /pair'), findsOneWidget);
  });
}
```

Append to `home_shell_test.dart` (import `haptics.dart`, `app_toast`-free, `manual_connect_cubit.dart`, `pairing_repository.dart`, `re_pair_sheet.dart`, `app_sheet.dart`, `flutter/services.dart`):

```dart
  group('connection-aware chrome', () {
    final notified = <String>[];

    setUp(() {
      notified.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(Haptics.channelName),
        (call) async {
          notified.add(call.arguments as String);
          return null;
        },
      );
      sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
        (mode, _) => ManualConnectCubit(_MockPairingRepository(), sl<ServerConfigStore>(), mode: mode),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
    });

    double spawnOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(HomeShell.spawnButtonKey), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;

    testWidgets('the + dims while the desktop is unreachable, and explains itself instead of opening Spawn', (tester) async {
      connection.report(ConnectionOutcome.unreachable);
      await pumpShell(tester);

      expect(spawnOpacity(tester), HomeShell.offlineSpawnOpacity);
      await tester.tap(find.byKey(HomeShell.spawnButtonKey));
      await settle(tester);

      expect(notified, ['error']);
      expect(find.text(HomeShell.offlineSpawnMessage), findsOneWidget);
      expect(find.text('route /spawn'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('the + opens Spawn while the desktop answers', (tester) async {
      connection.report(ConnectionOutcome.online);
      await pumpShell(tester);

      expect(spawnOpacity(tester), 1);
      await tester.tap(find.byKey(HomeShell.spawnButtonKey));
      await settle(tester);

      expect(find.text('route /spawn'), findsOneWidget);
    });

    testWidgets('the re-pair sheet opens once per auth failure', (tester) async {
      await pumpShell(tester);

      connection.report(ConnectionOutcome.auth);
      await settle(tester);
      connection.report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsOneWidget);

      await tester.tap(find.byKey(AppSheet.closeKey));
      await settle(tester);
      await settle(tester);
      expect(find.byType(RePairForm), findsNothing);

      connection.report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsNothing);

      connection.report(ConnectionOutcome.online);
      connection.report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsOneWidget);
    });
  });
```

and at the top level of that file `class _MockPairingRepository extends Mock implements PairingRepository {}`.

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/pairing test/core/app_routes/home_shell_test.dart`
Expected: FAIL to compile: `re_pair_sheet.dart` not found, and no `mode`, `offlineSpawnOpacity` or `offlineSpawnMessage`.

- [ ] **Step 3: Implement.**

`manual_connect_cubit.dart`:

```dart
enum ManualConnectMode { manual, rePair }

class ManualConnectCubit extends Cubit<ManualConnectState> {
  ManualConnectCubit(this._repository, ServerConfigStore serverConfigStore, {this.mode = ManualConnectMode.manual})
    : hostController = TextEditingController(text: _prefillHost(serverConfigStore.current)),
      passwordController = TextEditingController(
        text: mode == ManualConnectMode.manual ? serverConfigStore.current?.password ?? '' : '',
      ),
      _secure = serverConfigStore.current?.secure ?? false,
      super(const ManualConnectInitialState());

  final ManualConnectMode mode;
```

(the rest of the class is unchanged).

`service_locator.dart`, replace the `ManualConnectCubit` registration:

```dart
    sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
      (mode, _) => ManualConnectCubit(sl<PairingRepository>(), sl<ServerConfigStore>(), mode: mode),
    );
```

`app_router.dart:62`: `create: (_) => sl<ManualConnectCubit>(param1: ManualConnectMode.manual)`.

Create `lib/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

Future<void> showRePairSheet(BuildContext context) {
  final name = context.read<ConnectionCubit>().state.desktopName ?? 'your desktop';
  return showAppSheet<void>(
    context: context,
    scope: (sheetContext, sheet) => BlocProvider<ManualConnectCubit>(
      create: (_) => sl<ManualConnectCubit>(param1: ManualConnectMode.rePair),
      child: sheet,
    ),
    page: AppSheetPage(
      title: 'Re-pair $name',
      subtitle: 'Your desktop changed its password. Enter the new one from Settings › Connect Mobile, '
          'or scan the code again.',
      closeable: true,
      rows: (context, query) => const [RePairForm()],
    ),
  );
}

class RePairForm extends StatelessWidget {
  const RePairForm({super.key});

  static const Key hostKey = ValueKey('re-pair-host');
  static const Key reconnectKey = ValueKey('re-pair-reconnect');
  static const Key scanKey = ValueKey('re-pair-scan');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<ManualConnectCubit>();
    return BlocListener<ManualConnectCubit, ManualConnectState>(
      listener: (context, state) {
        if (state is ConnectSuccessState) {
          Haptics.success();
          Navigator.of(context).pop();
        }
        if (state is ConnectFailureState) Haptics.warning();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppContainer(
            key: hostKey,
            backgroundColor: skin.bgElevated,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.computer, size: 18, color: skin.textSecondary),
                const HorizontalSpace(10),
                Expanded(
                  child: AppText(
                    cubit.hostController.text,
                    style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const VerticalSpace(14),
          AppTextField(controller: cubit.passwordController, label: 'PASSWORD', obscureText: true),
          const VerticalSpace(14),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is ConnectFailureState || current is ConnectLoadingState,
            builder: (context, state) => state is ConnectFailureState
                ? Padding(padding: const EdgeInsets.only(bottom: 14), child: ConnectionFailureBanner(copy: state.copy))
                : const SizedBox.shrink(),
          ),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is ConnectLoadingState || current is ConnectFailureState,
            builder: (context, state) => PrimaryButton.expand(
              key: reconnectKey,
              text: 'Reconnect',
              isLoading: state is ConnectLoadingState,
              onPressed: () => cubit.connect(Theme.of(context).platform),
            ),
          ),
          const VerticalSpace(6),
          TextButton(
            key: scanKey,
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.pushNamed(RoutesStrings.pairingScan);
            },
            child: AppText('Scan the code instead', style: AppTextStyle.style13p5Medium.copyWith(color: skin.accentText)),
          ),
        ],
      ),
    );
  }
}
```

`home_shell.dart`: add the constants to `HomeShell`:

```dart
  static const double offlineSpawnOpacity = 0.4;
  static const String offlineSpawnMessage = 'Needs a connection to your desktop';
```

replace the `GlassButton.icon(...)` at `:140-147` with `const _SpawnButton(),`, wrap the returned `Scaffold` in

```dart
    return BlocListener<ConnectionCubit, AppConnectionState>(
      listenWhen: (previous, current) =>
          current is ConnectionAuthFailedState && previous is! ConnectionAuthFailedState,
      listener: (context, _) => showRePairSheet(context),
      child: Scaffold(
```

(closing the extra parenthesis after the `Scaffold`), and add at the bottom of the file:

```dart
class _SpawnButton extends StatelessWidget {
  const _SpawnButton();

  static bool _reachable(AppConnectionState state) =>
      state is! ConnectionOfflineState && state is! ConnectionAuthFailedState;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<ConnectionCubit, AppConnectionState>(
      buildWhen: (previous, current) => _reachable(previous) != _reachable(current),
      builder: (context, state) {
        final reachable = _reachable(state);
        return AnimatedOpacity(
          opacity: reachable ? 1 : HomeShell.offlineSpawnOpacity,
          duration: AppMotion.base,
          child: GlassButton.icon(
            key: HomeShell.spawnButtonKey,
            icon: Icons.add,
            semanticLabel: reachable ? 'Spawn agent' : 'Spawn agent. Needs a connection to your desktop',
            diameter: GlassMetrics.tabBarHeight,
            foreground: skin.textPrimary,
            haptic: reachable ? Haptics.tap : Haptics.error,
            onPressed: reachable
                ? () => Navigator.of(context).pushNamed(RoutesStrings.spawn)
                : () => AppToast.show(context, message: HomeShell.offlineSpawnMessage, icon: Icons.cloud_off_rounded),
          ),
        );
      },
    );
  }
}
```

with imports for `flutter_bloc`, `app_motion.dart`, `connection_cubit.dart`, `haptics.dart`, `app_toast.dart` and `re_pair_sheet.dart`.

`home_title.dart`: pass `onRePair: () => showRePairSheet(context),` to `DesktopStatusLine`. `sessions_body.dart` `_BoardError`: pass `onRePair: () => showRePairSheet(context),` to `ConnectionErrorState`. Import `re_pair_sheet.dart` in both.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/feature/pairing test/core/app_routes test/feature/sessions`
Expected: PASS. `app_router_test.dart`'s `routes pairing scan, manual connect, and sessions through a BlocProvider` still passes, since the provider's `create` runs lazily.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Simulator capture into `build/start-flow/task-9/`, dark and light** (build and install as in Task 8):
- `plus-offline`: Connect Mobile off (ask the user). The **+** at 40 %, and the toast after a tap.
- `re-pair-sheet`: ask the user to rotate the Connect Mobile password, then foreground the app. The sheet shows `Re-pair <name>` and the host. Also capture it after a wrong password (banner) and after the right one (sheet closed, header `Updated just now`).
- `needs-re-pairing-header`: dismiss the sheet. The header reads `Needs re-pairing` in red, and tapping it reopens the sheet.

- [ ] **Step 7: Commit.**

```bash
git add lib/feature/pairing lib/core/utils/service_locator.dart lib/core/app_routes \
  lib/feature/sessions/presentation/sessions_screen/ui test/feature/pairing test/core/app_routes/home_shell_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): dim the + while unreachable, and re-pair in a sheet on auth failure

Offline or unpaired, the + sits at 40 % and a tap gives an error haptic
and a toast instead of opening Spawn. A rejected password opens a re-pair
sheet once per failure episode, with the host prefilled and an empty
password field. The header's Needs re-pairing and the full-screen error's
Re-pair lead back to it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 10 (Flow A): Desktop switcher sheet

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart`
- Modify: `packages/mobile/lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart:21`, `:37`, `:112-120`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/home_title.dart`, `sessions_body.dart` (`_BoardError`)
- Test: create `test/feature/pairing/presentation/desktop_switcher/desktop_switcher_sheet_test.dart`; change the header test in `home_shell_test.dart`

**Interfaces:**
- Consumes: `ConnectionsCubit` (`desktops`, `connectingId`, `errors`, `connectTo`, `ConnectSuccessState`, `ConnectFailureState`), `ConnectionRow`, `relativeLabel`, `showAppSheet`.
- Produces: `Future<void> showDesktopSwitcherSheet(BuildContext context)`, `class DesktopSwitcherList` with `pairKey` and `manageKey`. `ConnectionRow.onMenuTap` becomes `VoidCallback?`, and the menu button is hidden when it is null.

- [ ] **Step 1: Write the failing tests.**

Create `test/feature/pairing/presentation/desktop_switcher/desktop_switcher_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockStore extends Mock implements ServerConfigStore {}

const _mac = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);
const _imac = DesktopModel(id: 'b', name: 'iMac', host: '10.0.0.6', port: '3011', secure: false, isActive: false);

void main() {
  late _MockDesktops desktops;
  late _MockRemote remote;
  late _MockStore store;

  setUpAll(() => registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: '')));

  setUp(() async {
    desktops = _MockDesktops();
    remote = _MockRemote();
    store = _MockStore();
    when(() => desktops.watchDesktops()).thenAnswer((_) => Stream.value(const [_mac, _imac]));
    when(() => desktops.passwordFor(any())).thenAnswer((_) async => Result.success('pw'));
    when(() => desktops.activate(any(), name: any(named: 'name'))).thenAnswer((_) async => Result.success(null));
    when(() => store.set(any())).thenReturn(null);
    await sl.reset();
    sl.registerFactory<ConnectionsCubit>(() => ConnectionsCubit(desktops, remote, store));
  });

  tearDown(() => sl.reset());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}')),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => showDesktopSwitcherSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every desktop with the active one marked, and ways to add or manage', (tester) async {
    await open(tester);

    expect(find.text('Desktops'), findsOneWidget);
    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('iMac'), findsOneWidget);
    expect(find.byKey(const Key('switcher-active-a')), findsOneWidget);
    expect(find.byKey(DesktopSwitcherList.pairKey), findsOneWidget);
    expect(find.byKey(DesktopSwitcherList.manageKey), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('tapping another desktop switches to it and closes the sheet', (tester) async {
    when(() => remote.identify(any())).thenAnswer((_) async => const DesktopIdentityModel(name: 'iMac'));
    await open(tester);

    await tester.tap(find.text('iMac'));
    await tester.pumpAndSettle();

    final config = verify(() => store.set(captureAny())).captured.single as ServerConfig;
    expect(config.desktopId, 'b');
    expect(find.text('Desktops'), findsNothing);
  });

  testWidgets('a desktop that rejects its password stays listed with the reason and a way to scan again', (tester) async {
    when(() => remote.identify(any())).thenThrow(ServerFailure(error: 'x', message: 'no', statusCode: 401));
    await open(tester);

    await tester.tap(find.text('iMac'));
    await tester.pumpAndSettle();

    expect(find.text('Desktops'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    verifyNever(() => store.set(any()));
  });

  testWidgets('tapping the active desktop just closes the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.text('Mac'));
    await tester.pumpAndSettle();

    expect(find.text('Desktops'), findsNothing);
    verifyNever(() => remote.identify(any()));
  });

  testWidgets('Pair another desktop and Manage desktops lead to their screens', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(DesktopSwitcherList.manageKey));
    await tester.pumpAndSettle();
    expect(find.text('route /connections'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DesktopSwitcherList.pairKey));
    await tester.pumpAndSettle();
    expect(find.text('route /onboarding'), findsOneWidget);
  });
}
```

In `home_shell_test.dart`, register the cubit the sheet needs in `setUp` (after `sl.reset()`), with a `_MockDesktopsRepository` whose `watchDesktops()` returns `Stream.value(const [])` and a `_MockPairingRemoteDataSource`:

```dart
    final switcherDesktops = _MockDesktopsRepository();
    when(() => switcherDesktops.watchDesktops()).thenAnswer((_) => Stream.value(const []));
    sl.registerFactory<ConnectionsCubit>(
      () => ConnectionsCubit(switcherDesktops, _MockPairingRemoteDataSource(), serverConfigStore),
    );
```

(add `class _MockPairingRemoteDataSource extends Mock implements PairingRemoteDataSource {}` and the imports). Then change the last three lines of the Task 8 header test from the `route /connections` expectation to:

```dart
    await tester.tap(find.byKey(DesktopStatusLine.tapKey).first);
    await settle(tester);
    await settle(tester);

    expect(find.byType(DesktopSwitcherList), findsOneWidget);
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/pairing/presentation/desktop_switcher test/core/app_routes/home_shell_test.dart`
Expected: FAIL to compile: `desktop_switcher_sheet.dart` not found.

- [ ] **Step 3: Implement.**

`connection_row.dart`: make the field `final VoidCallback? onMenuTap;` and the constructor parameter `this.onMenuTap,` (no longer `required`), and render the trailing menu `AppContainer` only `if (onMenuTap != null)`.

Create `lib/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/logic/relative_label.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart';

Future<void> showDesktopSwitcherSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  scope: (sheetContext, sheet) => BlocProvider<ConnectionsCubit>(create: (_) => sl<ConnectionsCubit>(), child: sheet),
  page: AppSheetPage(
    title: 'Desktops',
    subtitle: 'Choose the desktop this phone drives.',
    closeable: true,
    rows: (context, query) => const [DesktopSwitcherList()],
  ),
);

class DesktopSwitcherList extends StatelessWidget {
  const DesktopSwitcherList({super.key});

  static const Key pairKey = ValueKey('desktop-switcher-pair');
  static const Key manageKey = ValueKey('desktop-switcher-manage');

  void _leaveTo(BuildContext context, String route, {Object? arguments}) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed(route, arguments: arguments);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocConsumer<ConnectionsCubit, ConnectionsState>(
      listener: (context, state) {
        if (state is ConnectSuccessState) {
          Haptics.success();
          Navigator.of(context).pop();
        }
        if (state is ConnectFailureState) Haptics.error();
      },
      builder: (context, state) {
        final cubit = context.read<ConnectionsCubit>();
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cubit.desktops.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: skin.bgElevated,
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < cubit.desktops.length; i++) ...[
                      if (i > 0) Divider(color: skin.borderSubtle, height: 1),
                      _row(context, cubit, cubit.desktops[i], now),
                    ],
                  ],
                ),
              ),
            const VerticalSpace(12),
            _SheetAction(
              key: pairKey,
              icon: Icons.add,
              label: 'Pair another desktop',
              onTap: () => _leaveTo(context, RoutesStrings.onboarding, arguments: {'fromDesktops': true}),
            ),
            _SheetAction(
              key: manageKey,
              icon: Icons.tune_rounded,
              label: 'Manage desktops',
              onTap: () => _leaveTo(context, RoutesStrings.connections),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, ConnectionsCubit cubit, DesktopModel desktop, DateTime now) {
    final id = desktop.id!;
    final error = cubit.errors[id];
    final active = desktop.isActive ?? false;
    return ConnectionRow(
      name: desktop.name ?? desktop.address,
      host: desktop.host ?? '',
      address: desktop.address,
      lastConnectedLabel: relativeLabel(desktop.lastConnectedAt, now),
      connecting: cubit.connectingId == id,
      active: active,
      activeDotKey: Key('switcher-active-$id'),
      error: error,
      onScanAgain: error?.isAuth ?? false ? () => _leaveTo(context, RoutesStrings.pairingScan) : null,
      onTap: active ? () => Navigator.of(context).pop() : () => cubit.connectTo(id, Theme.of(context).platform),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: Colors.transparent,
      child: Row(
        children: [
          Icon(icon, size: 18, color: skin.accentText),
          const HorizontalSpace(10),
          AppText(label, style: AppTextStyle.style15Medium.copyWith(color: skin.accentText)),
        ],
      ),
    );
  }
}
```

`home_title.dart`: `onTap: () => showDesktopSwitcherSheet(context),` (import `desktop_switcher_sheet.dart`; drop the now-unused `routes_strings.dart` import). `sessions_body.dart` `_BoardError`: `onSwitchDesktop: () => showDesktopSwitcherSheet(context),`.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/feature/pairing test/core/app_routes test/feature/sessions`
Expected: PASS. `connections_body_test.dart` still passes: it passes `onMenuTap`, so the menu still renders.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Simulator capture into `build/start-flow/task-10/`, dark and light:** `switcher` (the sheet over the board, with two desktops if the user has two), `switching` (the row's connecting spinner), and `switched` (the board of the other desktop from its cache, header `Connecting…` then `Updated just now`).

- [ ] **Step 7: Commit.**

```bash
git add lib/feature/pairing/presentation lib/feature/sessions/presentation/sessions_screen/ui \
  test/feature/pairing/presentation/desktop_switcher test/core/app_routes/home_shell_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): switch desktops from a sheet instead of a full screen

Tapping the header, or Switch desktop on the full-screen error, opens a
glass sheet listing the saved desktops. Picking one switches in place: the
board swaps to that desktop's cache and then its fresh data, without
leaving the home shell. Pair another and Manage desktops lead on.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 11 (Flow B): Launch hand-off with no blank frame

**Files:**
- Modify: `packages/mobile/lib/main.dart` (between the launch destination and `runApp`)
- Modify: `packages/mobile/lib/core/app_themes/app_motion.dart` (add `launchCacheBudget`)
- Modify: `packages/mobile/flutter_native_splash.yaml`, plus the native files `flutter_native_splash:create` regenerates under `ios/` and `android/`
- Test: create `test/core/app_themes/native_splash_matches_skin_test.dart`; add a test to `sessions_body_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit.cacheReady` (Task 4), `sl<ConnectionCubit>()` (Task 7).
- Produces: `AppMotion.launchCacheBudget = Duration(milliseconds: 400)`. `main` holds the native splash until the board cache is applied or the budget runs out, and only when launching into the board.

- [ ] **Step 1: Write the failing tests.**

Create `test/core/app_themes/native_splash_matches_skin_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Set<String?> _values(String yaml, String key) =>
    RegExp('^\\s*$key: "(#[0-9A-Fa-f]{6})"', multiLine: true).allMatches(yaml).map((m) => m.group(1)?.toUpperCase()).toSet();

void main() {
  test('the native splash hands off to the skin background with no colour jump', () {
    final yaml = File('flutter_native_splash.yaml').readAsStringSync();

    expect(_values(yaml, 'color'), {_hex(const LightSkin().bgBase)});
    expect(_values(yaml, 'color_dark'), {_hex(const DarkSkin().bgBase)});
  });
}
```

Append to `sessions_body_test.dart`, inside `group('start states', ...)`:

```dart
    testWidgets('with the cache applied before the first frame, frame one is the board', (tester) async {
      when(() => repository.cachedBoard()).thenAnswer(
        (_) async => Replicated(
          value: const BoardSnapshot(sessions: [SessionModel(id: 'w-1', displayName: 'Cached worker', status: 'working')]),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );
      when(() => repository.getBoard()).thenAnswer(
        (_) => Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>().future,
      );
      final cubit = SessionsCubit(repository, mux, const _StubConfigSource());
      await cubit.cacheReady;

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: SkinScope(
              skin: const DarkSkin(),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConnectionCubit>.value(value: connection.cubit),
                  BlocProvider<SessionsCubit>.value(value: cubit),
                ],
                child: const Scaffold(body: SessionsBody()),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cached worker'), findsOneWidget);
      expect(find.byType(BoardSkeleton), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    });
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/app_themes/native_splash_matches_skin_test.dart test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`
Expected: the splash test FAILS with `Expected: {'#FAF7F2'} Actual: {'#F3EEE5'}` (and `#18171C` against `#121212`). The board test PASSES already, since it pins the Task 4 contract that `main` now relies on. Keep it as the guard.

- [ ] **Step 3: Implement.**

`app_motion.dart`, add:

```dart
  static const Duration launchCacheBudget = Duration(milliseconds: 400);
```

`main.dart`, right before `final packageInfo = await PackageInfo.fromPlatform();`:

```dart
  if (destination == LaunchDestination.sessions) {
    await sl<SessionsCubit>().cacheReady.timeout(AppMotion.launchCacheBudget, onTimeout: () {});
  }
```

(import `sessions_cubit.dart` and `app_motion.dart`).

`flutter_native_splash.yaml`: set both `color:` lines to `"#FAF7F2"` and both `color_dark:` lines to `"#18171C"`, the skins' `bgBase`. Then regenerate the native launch screens:

Run: `dart run flutter_native_splash:create`
Expected: `Native splash complete.`, with changes under `ios/Runner/` (LaunchScreen storyboard, `LaunchBackground` assets) and `android/app/src/main/res/`.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/core/app_themes test/feature/sessions`
Expected: PASS.

- [ ] **Step 5: Gate, including native builds.** `flutter analyze` → `No issues found!`; `flutter test` → all pass. Native files changed, so build both: `flutter build ios --release --no-codesign` and `flutter build apk --release` must both succeed.

- [ ] **Step 6: Simulator capture into `build/start-flow/task-11/`, dark and light.** Record the cold launch with a cache: `xcrun simctl io booted recordVideo build/start-flow/task-11/cold-launch-<appearance>.mov`, launch the app, and stop the recording after 3 s with Ctrl-C. Step through the frames: the splash colour must equal the board background, and no skeleton or "No agents" frame may appear between the splash and the cached board. Also take one screenshot of the first board frame.

- [ ] **Step 7: Commit.**

```bash
git add lib/main.dart lib/core/app_themes/app_motion.dart flutter_native_splash.yaml ios android \
  test/core/app_themes/native_splash_matches_skin_test.dart \
  test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): hand the splash straight to the cached board

main waits up to 400 ms for the board cache before the first frame when
launching into the board, so frame one is the last known board rather than
a skeleton or an empty-board flash. The native splash now uses the skins'
bgBase in both appearances, so the hand-off has no colour jump.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 12 (Flow C): Pairing success step

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_success/ui/pairing_success_view.dart`
- Modify: `packages/mobile/lib/core/app_themes/app_motion.dart` (add `pairingSuccessHold`)
- Modify: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_state.dart`, `pairing_scan_cubit.dart:47-55`
- Modify: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_state.dart`, `manual_connect_cubit.dart:44-48`
- Modify: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart`, `widgets/pairing_scan_body.dart:73-90`
- Modify: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart`, `widgets/manual_connect_body.dart`
- Test: create `test/feature/pairing/presentation/pairing_success/pairing_success_view_test.dart`, `test/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen_test.dart`; add to `pairing_scan_cubit_test.dart` and `manual_connect_cubit_test.dart`; port `test/core/utils/haptics_call_sites_test.dart:201`

**Interfaces:**
- Consumes: `PairingRepository.verifyAndConnect` returning the saved `DesktopModel`.
- Produces: `VerifySuccessState(String desktopName)`, `ConnectSuccessState(String desktopName)` (manual), `PairingSuccessView({required String desktopName})`, `AppMotion.pairingSuccessHold = Duration(milliseconds: 1200)`. The re-pair sheet (Task 9) still closes at once on success; only the full-screen pairing routes show the step.

- [ ] **Step 1: Write the failing tests.**

Create `test/feature/pairing/presentation/pairing_success/pairing_success_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_success/ui/pairing_success_view.dart';

void main() {
  testWidgets('confirms the connection and names the desktop', (tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(home: Scaffold(body: PairingSuccessView(desktopName: 'MacBook'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('MacBook'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
```

Create `test/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart';

class _MockManualConnectCubit extends MockCubit<ManualConnectState> implements ManualConnectCubit {}

void main() {
  testWidgets('a successful connect shows the success step, then returns true after the hold', (tester) async {
    final cubit = _MockManualConnectCubit();
    when(() => cubit.hostController).thenReturn(TextEditingController());
    when(() => cubit.passwordController).thenReturn(TextEditingController());
    when(() => cubit.secure).thenReturn(false);
    whenListen(
      cubit,
      Stream<ManualConnectState>.fromIterable([const ConnectSuccessState('MacBook')]),
      initialState: const ManualConnectInitialState(),
    );
    bool? result;

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => BlocProvider<ManualConnectCubit>.value(
                        value: cubit,
                        child: const ManualConnectScreen(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('MacBook'), findsOneWidget);
    expect(result, isNull);

    await tester.pump(AppMotion.pairingSuccessHold);
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
```

Append to `pairing_scan_cubit_test.dart` (its `_desktop` fixture is named `'Mac'`):

```dart
  blocTest<PairingScanCubit, PairingScanState>(
    'a verified scan names the saved desktop for the success step',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(_desktop));
      return PairingScanCubit(repository, store, fromOnboarding: true);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}', TargetPlatform.iOS),
    expect: () => [isA<VerifyLoadingState>(), const VerifySuccessState('Mac')],
  );
```

Append to `manual_connect_cubit_test.dart` (its `_desktop` is also named `'Mac'`):

```dart
  blocTest<ManualConnectCubit, ManualConnectState>(
    'a verified connect names the saved desktop for the success step',
    build: () {
      when(() => store.current).thenReturn(null);
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(_desktop));
      return ManualConnectCubit(repository, store);
    },
    act: (cubit) {
      cubit.hostController.text = '10.0.0.9';
      return cubit.connect(TargetPlatform.iOS);
    },
    expect: () => [isA<ConnectLoadingState>(), const ConnectSuccessState('Mac')],
  );
```

In `test/core/utils/haptics_call_sites_test.dart:201`, change `const ConnectSuccessState()` to `const ConnectSuccessState('Mac')`; its assertion (`fired == ['success']`) stays.

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/feature/pairing test/core/utils/haptics_call_sites_test.dart`
Expected: FAIL to compile: `pairing_success_view.dart` not found, `pairingSuccessHold` not defined, and the success states take no argument.

- [ ] **Step 3: Implement.**

`app_motion.dart`:

```dart
  static const Duration pairingSuccessHold = Duration(milliseconds: 1200);
```

`pairing_scan_state.dart`:

```dart
final class VerifySuccessState extends PairingScanState {
  const VerifySuccessState(this.desktopName);

  final String desktopName;

  @override
  List<Object?> get props => [desktopName];
}
```

`pairing_scan_cubit.dart`, `onSuccess`: take the saved desktop and end with `emit(VerifySuccessState(desktop.name ?? target.host));` (rename the `_` parameter to `desktop`).

`manual_connect_state.dart`:

```dart
final class ConnectSuccessState extends ManualConnectState {
  const ConnectSuccessState(this.desktopName);

  final String desktopName;

  @override
  List<Object?> get props => [desktopName];
}
```

`manual_connect_cubit.dart`, `onSuccess: (desktop) { TelemetryRuntime.capture(MobileEvents.paired, {'method': 'manual'}); emit(ConnectSuccessState(desktop.name ?? target.host)); },`.

Create `lib/feature/pairing/presentation/pairing_success/ui/pairing_success_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/fade_up_entrance.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class PairingSuccessView extends StatelessWidget {
  const PairingSuccessView({super.key, required this.desktopName});

  final String desktopName;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return ColoredBox(
      color: skin.bgBase,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeUpEntrance(
              index: 0,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: skin.tintGreen, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 38, color: skin.green),
              ),
            ),
            const VerticalSpace(18),
            FadeUpEntrance(
              index: 1,
              child: AppText('Connected', style: AppTextStyle.style24BoldDisplay.copyWith(letterSpacing: -0.4)),
            ),
            const VerticalSpace(6),
            FadeUpEntrance(
              index: 2,
              child: AppText(
                desktopName,
                style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

`pairing_scan_body.dart`: include `VerifySuccessState` in the overlay `BlocBuilder`'s `buildWhen`, and return `PairingSuccessView(desktopName: state.desktopName)` for it before the loading branch.

`pairing_scan_screen.dart`: make it a `StatefulWidget` that holds `Timer? _handoff` (cancelled in `dispose`). In the listener, on `VerifySuccessState`:

```dart
      _handoff?.cancel();
      _handoff = Timer(AppMotion.pairingSuccessHold, () {
        if (!mounted) return;
        final fromOnboarding = context.read<PairingScanCubit>().fromOnboarding;
        if (fromOnboarding) {
          Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
        } else {
          Navigator.of(context).pop();
        }
      });
```

`manual_connect_screen.dart`: the same `StatefulWidget` shape, with the listener's success branch becoming `_handoff = Timer(AppMotion.pairingSuccessHold, () { if (mounted) Navigator.of(context).pop<bool>(true); });`.

`manual_connect_body.dart`: keep the haptics `BlocListener` as it is, and make its child a `BlocBuilder<ManualConnectCubit, ManualConnectState>(buildWhen: (previous, current) => current is ConnectSuccessState, builder: (context, state) => state is ConnectSuccessState ? PairingSuccessView(desktopName: state.desktopName) : <the existing SingleChildScrollView>)`.

`re_pair_sheet.dart` already handles `ConnectSuccessState` by type, so it needs no change.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/feature/pairing test/core/utils/haptics_call_sites_test.dart test/core/telemetry/call_sites_test.dart`
Expected: PASS.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Simulator capture into `build/start-flow/task-12/`, dark and light:** `success-qr` (Settings → Disconnect, then Pair → scan: the success step with the desktop name) and `success-manual` (Enter manually → Connect). Then capture the first board after the hand-off.

- [ ] **Step 7: Commit.**

```bash
git add lib/core/app_themes/app_motion.dart lib/feature/pairing test/feature/pairing test/core/utils/haptics_call_sites_test.dart
git commit -m "$(cat <<'MSG'
feat(mobile): confirm a new pairing before handing off to the board

A QR or manual pair now shows a short Connected step naming the desktop,
held for 1.2 s, before the board. The success states carry the saved
desktop's name. Ported haptics_call_sites_test's ConnectSuccessState to
the new constructor, same assertion.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 13 (Flow D): Deep links wait for a paired desktop

**Files:**
- Modify: `packages/mobile/lib/core/deep_link/deep_link_service.dart:26-58`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:109-111`
- Test: modify `test/core/deep_link/deep_link_service_test.dart`, `test/core/deep_link/platform_deep_linking_test.dart`

**Interfaces:**
- Consumes: `ServerConfigSource`.
- Produces: `DeepLinkService(AppLinkSource source, GlobalKey<NavigatorState> navigatorKey, ServerConfigSource config)`. `handle` returns `false` and navigates nowhere while `config.current == null`.

- [ ] **Step 1: Write the failing tests.**

In both test files, add

```dart
class _Paired implements ServerConfigSource {
  const _Paired([this.current = const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1')]);

  @override
  final ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}
```

with imports for `server_config_interceptor.dart` and `server_config.dart`, and pass `const _Paired()` as the third argument to every existing `DeepLinkService(...)` construction (6 in `deep_link_service_test.dart`, 4 in `platform_deep_linking_test.dart`). Then add to `deep_link_service_test.dart`:

```dart
  testWidgets('with no paired desktop, a link opens nothing', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired(null));
    observer.pushed.clear();

    final handled = service.handle(Uri.parse('operator://session/abc'));
    await tester.pumpAndSettle();

    expect(handled, isFalse);
    expect(observer.pushed, isEmpty);
  });
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `flutter test test/core/deep_link`
Expected: FAIL to compile with `Too many positional arguments`.

- [ ] **Step 3: Implement.**

`deep_link_service.dart`: the constructor becomes `DeepLinkService(this._source, this._navigatorKey, this._config);`, add `final ServerConfigSource _config;` (import `server_config_interceptor.dart`), and make `handle` start with:

```dart
    if (_config.current == null) return false;
```

`service_locator.dart`: `() => DeepLinkService(AppLinksSource(), sl<GlobalKey<NavigatorState>>(), sl<ServerConfigStore>()),`.

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `flutter test test/core/deep_link test/core/notifications`
Expected: PASS.

- [ ] **Step 5: Gate.** `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 6: Commit.**

```bash
git add lib/core/deep_link/deep_link_service.dart lib/core/utils/service_locator.dart test/core/deep_link
git commit -m "$(cat <<'MSG'
fix(mobile): ignore deep links until a desktop is paired

A notification tap on a phone with no active desktop no longer pushes a
chat route over onboarding with no server behind it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 14: Docs: drift is the single local store, and Plan 9 is superseded

**Files:**
- Modify: `CLAUDE.md` (repo root, "Mobile client" section: the `ServerConfig` paragraph and the drift bullet)
- Modify: `docs/superpowers/plans/2026-08-28-mobile-replica-cache.md:3`

**Interfaces:** none.

- [ ] **Step 1: Update `CLAUDE.md`.** In the "Mobile client (`packages/mobile`)" section:

  1. At the end of the "`ServerConfig` is the spine." paragraph, add: `` `ServerConfig.desktopId` names the active desktop; every replica read and write is scoped by it, so a desktop never shows another desktop's data. ``

  2. After that paragraph, add a new paragraph:

  ```markdown
  **Start flow and connection state.** Opening the app paints the last known board, first
  notifications page and chat history from drift, then replaces them with fresh data. Each
  replicated repository writes the daemon's decoded JSON on every successful fetch and exposes
  a `cachedX()` read that parses through the same hand-written `fromJson`; cubits read the cache
  once per desktop. `ConnectionCubit` (`core/connection/`, provided at the app root) is the single
  source of connection state, fed by `ConnectionReportInterceptor` and `MuxClient.status`. It backs
  off 1 s to 30 s while offline, waits 60 s when rate-limited, and stops on an auth failure so a
  rotated password cannot trip the daemon's lockout. `/healthz` needs no password, so its 200 never
  clears an auth failure.
  ```

  3. Replace the drift bullet with:

  ```markdown
  - **drift is the single local store**, under `lib/core/database/`: saved desktops, settings
    (read through `AppPreferences`, loaded once at launch so reads stay synchronous), and the
    replica (`replica_documents` for whole-resource snapshots, `replica_block_events` for chat
    history capped at 200 per session). Layout follows `flutter-knowledge:drift-local-database`:
    tables and DAOs in `core/database/tables/<table>/`, local data sources in the feature, no drift
    import above the data source. Wire models stay hand-written: drift never parses the wire, and
    the replica stores the daemon's JSON for the same `fromJson` to parse. Passwords never enter
    SQLite; the Keychain (`flutter_secure_storage`, `server.password.<id>`) holds passwords only.
    There is no SharedPreferences in first-party code (`easy_localization` still pulls it in
    transitively), and `test/core/no_shared_preferences_test.dart` pins that. A schema bump may
    wipe and recreate every table, and the wipe purges the Keychain passwords with it. Generated
    `*.g.dart` is committed, because CI runs `flutter analyze` and `flutter test` with no
    generation step. Regenerate with `dart run build_runner build --delete-conflicting-outputs`.
  ```

- [ ] **Step 2: Mark Plan 9 superseded.** In `docs/superpowers/plans/2026-08-28-mobile-replica-cache.md`, change line 3 from `Status: written` to:

```markdown
Status: superseded, never built. Replaced by `docs/superpowers/specs/2026-09-25-mobile-start-flow-and-local-store-design.md` and its plan `docs/superpowers/plans/2026-09-25-mobile-start-flow-and-local-store.md`.
```

- [ ] **Step 3: Gate.** From `packages/mobile`: `flutter analyze` → `No issues found!`; `flutter test` → all pass.

- [ ] **Step 4: Commit.**

```bash
cd /Users/omaraly/development/AI/Operator-ios-polish
git add CLAUDE.md docs/superpowers/plans/2026-08-28-mobile-replica-cache.md
git commit -m "$(cat <<'MSG'
docs(mobile): drift is the single local store; supersede Plan 9

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

---

## Self-review record

- **Spec coverage.** §1 One drift database: Tasks 1 and 3. §2 Replica: Tasks 4 (board and PRs), 5 (notifications and bell) and 6 (chat, 200 cap, merge by seq). Scoping: Tasks 2, 4, 5 and 6. §3 Connection state: Task 7. §4 What the user sees: Task 8 (header, skeletons, full-screen error, cached failure, empty board), Task 9 (the **+**, the re-pair sheet, Needs re-pairing), Task 6 (chat) and Task 5 (notifications). Error handling: every repository's `cachedX` and `_remember` (drift failure is a miss or ignored; unparseable is deleted), and the Task 7 dio test pins the 12 s timeouts. Testing: each task's Step 1, with the simulator list spread over Tasks 8 to 12. Docs: Task 14.
- **Probe order.** `sessions_remote_data_source_test.dart`'s probe-order test is untouched in Task 4.
- **Type names used across tasks:** `Replicated<T>{value, fetchedAt}`; `cachedBoard()`, `cachedFirstPage()`, `cachedHistory()`, `rememberLive()`; `ConnectionSignals{retries, authFailed}`; `AppConnectionState` and its four `Connection*State` subclasses; `ConnectionHarness`, `TestConfigSource`, `kTestDesktop`; `DesktopStatusLine.tapKey`; `ConnectionErrorState.retryKey`/`switchKey`; `RePairForm.*Key`; `DesktopSwitcherList.*Key`; `ManualConnectMode`; `AppMotion.statusLineTick`/`launchCacheBudget`/`pairingSuccessHold`.
