# Plan 9 — Mobile replica cache (drift)

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`
Scope: `packages/mobile` only. No backend change, no desktop change, no API change.
Depends on: plan 2 (mobile block screen). Independent of plans 3–8.

## What this delivers

`packages/mobile` stops being a thin client and becomes a **replicating** one. On
launch it paints the last known sessions list and the last known blocks for the
session being opened, from on-device SQLite, before any network call resolves.
When the network answers it reconciles. When the app is backgrounded and resumed it
decides whether to revalidate at all rather than always re-fetching.

Three user-visible changes, and nothing else:

1. Cold launch shows content instead of a spinner.
2. A message sent while the link is down is visibly *pending* rather than lost.
3. Returning to the app after a few seconds does not re-fetch history.

Everything else — assembly, viewport, widgets, the mux — is untouched.

## The convention exception, stated once

`CLAUDE.md` and the spec's conventions list forbid `drift`, `build_runner`,
`freezed` and `json_serializable` in first-party mobile code. **The user reversed
that for this plan specifically on 2026-08-28**, naming drift
(https://pub.dev/packages/drift). `drift` requires `drift_dev`, which is a
`build_runner` generator, so adopting drift adopts `build_runner`. Both are in
scope.

**The boundary, which review must enforce:**

- `drift` and `build_runner` are used **only** for the cache under
  `lib/core/cache/`. No other package may import `package:drift/drift.dart`.
- **Wire models stay hand-written.** `BlockEventModel`, `SessionModel` and every
  other `data/model/` class keep their hand-written `fromJson` with all fields
  nullable. Drift never parses the wire and never replaces a model.
- `freezed` and `json_serializable` remain forbidden. This exception is for
  persistence, not for code generation in general.
- Generated files (`*.g.dart`) are committed, because CI runs `flutter analyze`
  and `flutter test` without a generation step.

If a task in this plan tempts you to widen any of these, stop and say so instead.

## Facts established by reading the real thing

Every number and signature below was read from the repository, not assumed.

**The daemon retains 500 events per session and trims.**
`backend/internal/service/blockevent/service.go:36` — `NewService(store, pub, retain)`
defaults `retain` to 500 when non-positive, and `Append` calls
`TrimBlockEvents(ctx, sessionID, s.retain)` at line 102. **Consequence: the phone
can legitimately hold history the server has already dropped**, and a re-fetch will
not restore it. The cache is therefore additive, not merely a latency optimization,
and a validation rule that treats "server has fewer rows than cache" as corruption
would delete real history. See Task 3.

**Block paging semantics**, from
`backend/internal/httpd/controllers/sessions.go:1118` and
`backend/internal/storage/sqlite/queries/block_events.sql`:

- `afterSeq` → `WHERE session_id = ? AND seq > ? ORDER BY seq LIMIT ?`
- `beforeSeq` → `WHERE session_id = ? AND seq < ? ORDER BY seq DESC LIMIT ?`, then
  re-sorted ascending. **`beforeSeq` is strict.**
- The two are **mutually exclusive**; sending both is a 400 `INVALID_QUERY`.
- `beforeSeq` must be `>= 1`. `limit`, when present, must be `1..500`.
- Absent or out-of-range `limit` is clamped to `retain` (500) by the service.

**There is no `epoch` on this endpoint.** The spec's `epoch`/cursor envelope is an
amendment that has not been implemented. This plan must therefore validate cached
rows without one, and must be written so that adopting the epoch later *replaces*
the validation rather than colliding with it. See Task 3.

**`BlocksCubit` holds its window in memory**
(`lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`):

```dart
const int kBlockWindow = 400;
const int kBlockPage = 100;
const int kBlockMaxWindow = 1200;

final SplayTreeMap<int, BlockEventModel> _events = SplayTreeMap<int, BlockEventModel>();
int _capacity = kBlockWindow;

void _merge(BlockEventModel record) {
  final seq = record.seq;
  if (seq == null) return;
  _events[seq] = record;
  while (_events.length > _capacity) {
    _events.remove(_events.firstKey());
  }
}
```

`refresh()` calls `getSessionBlocks(sessionId, GetSessionBlocksParams(afterSeq: _highestSeq))`
— on a cold start `_highestSeq` is null, so `afterSeq` is omitted and the daemon
returns the whole retained log. That call is what this plan makes conditional.

`_onStatus` re-subscribes and calls `refresh()` on every `MuxStatus.open`. That is
the reconnect path and Task 6 changes what it does after a long absence.

**`BlocksRepository` is the seam**
(`lib/feature/blocks/data/repository/blocks_repository.dart`):

```dart
abstract class BlocksRepository {
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  );
}
```

`BlocksRepositoryImp(this._remoteDataSource, this._network)` wraps every call in
`_guard`, which returns `ServerFailure.noNetwork()` when `_network.isConnected` is
false. **The cache goes in the repository**, not the cubit and not the data source:
the cubit already treats the repository as the source of truth, and the data source
is where the wire lives.

**`ServerConfig` has no id**
(`lib/core/api/server_config.dart`) — `{host, httpPort, secure, password}`, with
`httpBase` and `wsBase` getters. `ServerConfigStore`
(`lib/core/api/server_config_store.dart`) keeps `_current` in memory, host/port/secure
in `SharedPreferences` via `CacheHelper`, and the password in
`FlutterSecureStorage`. Task 1 derives a cache key from this; **the password is never
part of the key and never enters the database.**

**DI is `get_it` through `lib/core/utils/service_locator.dart`**, with
`_coreSetup()` async at line 75 (it already awaits `SharedPreferences.getInstance()`)
and one `_<feature>FeatureSetup()` per feature. `_blocksFeatureSetup()` registers:

```dart
sl.registerLazySingleton<BlocksRepository>(
  () => BlocksRepositoryImp(sl<BlocksRemoteDataSource>(), sl<NetworkStatus>()),
);
```

**Test conventions**: `mocktail` with `class _MockX extends Mock implements X {}`,
`registerFallbackValue` in `setUpAll`, stream controllers per test. See
`test/feature/blocks/presentation/blocks_cubit_test.dart:15-51` for the exact shape
this plan's tests must match.

**`analysis_options.yaml`** includes `package:flutter_lints/flutter.yaml` and
excludes only `packages/**`. Generated drift output is first-party and **will be
analyzed**, which is why Task 1 adds an exclude.

## Interfaces this plan introduces

Signatures neighbouring code depends on. Do not change them mid-plan without
updating every task that names them.

```dart
// lib/core/cache/replica_key.dart
String replicaKeyFor(ServerConfig? config);   // 'host:port' | '' when unpaired

// lib/core/cache/replica_database.dart
@DriftDatabase(tables: [CachedBlockEvents, CachedSessions, PendingSends, ReplicaMeta])
class ReplicaDatabase extends _$ReplicaDatabase { ... }

// lib/core/cache/block_event_cache.dart
abstract class BlockEventCache {
  Future<List<BlockEventModel>> read(String replicaKey, String sessionId);
  Future<void> write(String replicaKey, String sessionId, Iterable<BlockEventModel> events);
  Future<void> dropSession(String replicaKey, String sessionId);
  Future<void> dropReplica(String replicaKey);
  Future<void> enforceBudget();
}

// lib/core/cache/pending_send_store.dart
abstract class PendingSendStore {
  Future<String> enqueue(String replicaKey, String sessionId, String body);
  Future<List<PendingSend>> pending(String replicaKey, String sessionId);
  Future<void> resolve(String id);
  Future<void> fail(String id, String reason);
}
```

## Constraints and non-goals

- **No backend change.** If a task appears to need one, it is out of scope; record
  it and stop.
- **`~/.operator` does not apply here.** That hard rule governs the daemon and the
  desktop shell on macOS. The phone has no such directory; drift's database lives in
  the app's own sandbox via `drift_flutter`'s `driftDatabase(name:)`. State this in
  the PR description so a reviewer does not flag it.
- **Redaction is the daemon's job and stays there.** The cache persists exactly what
  arrived, including `redactedSpans`. It must never persist anything the daemon did
  not send.
- **No cache of terminal bytes.** Raw grid output is not cached, at any size.
- **Nothing in this plan may make an uncached launch slower.** Cache reads happen in
  parallel with the network call, never in front of it.

## Task 1 — Dependencies, database, DI. No behaviour change.

**Add to `packages/mobile/pubspec.yaml`:**

```yaml
dependencies:
  drift: ^2.34.3
  drift_flutter: ^0.3.1

dev_dependencies:
  drift_dev: ^2.34.5
  build_runner: ^2.4.0
```

`drift_flutter` already depends on `sqlite3_flutter_libs`, `path_provider` and
`sqlite3`; do **not** add those separately.

**Add to `packages/mobile/analysis_options.yaml`**, under the existing
`analyzer.exclude` that currently lists only `packages/**`:

```yaml
analyzer:
  exclude:
    - packages/**
    - lib/core/cache/**.g.dart
```

**Create `lib/core/cache/replica_key.dart`:**

```dart
String replicaKeyFor(ServerConfig? config) =>
    config == null ? '' : '${config.host}:${config.httpPort}';
```

The password is deliberately absent. Two daemons on the same host and port are the
same replica; re-pairing to a different host is a different one and sees no stale
rows.

**Create `lib/core/cache/replica_tables.dart`** with four tables:

- `CachedBlockEvents` — `replicaKey`, `sessionId`, `seq`, `payload` (the block's
  JSON as sent, encoded), `createdAt`. Primary key `(replicaKey, sessionId, seq)`.
- `CachedSessions` — `replicaKey`, `id`, `payload`, `updatedAt`. Primary key
  `(replicaKey, id)`.
- `PendingSends` — `id` (text, uuid), `replicaKey`, `sessionId`, `body`,
  `createdAt`, `attempts`, `lastError` (nullable).
- `ReplicaMeta` — `replicaKey`, `sessionId`, `lowestSeq`, `highestSeq`,
  `syncedAt`. Primary key `(replicaKey, sessionId)`.

Store the block as its **JSON payload string**, not as columns. The wire shape is
the daemon's and will grow; a column-per-field schema turns every daemon field
addition into a mobile migration. `payload` round-trips through the existing
hand-written `BlockEventModel.fromJson`, which is the one parser.

**Create `lib/core/cache/replica_database.dart`:**

```dart
@DriftDatabase(tables: [CachedBlockEvents, CachedSessions, PendingSends, ReplicaMeta])
class ReplicaDatabase extends _$ReplicaDatabase {
  ReplicaDatabase(super.e);
  ReplicaDatabase.defaults() : super(driftDatabase(name: 'operator_replica'));

  @override
  int get schemaVersion => 1;
}
```

**Migration policy, decided now so Task 2 does not have to invent one:** on any
`schemaVersion` change the cache is **dropped and recreated**, not migrated. Every
row here is a copy of something the daemon still has or has already trimmed; none of
it is authoritative, and a migration bug would corrupt the one thing a user would
notice. Implement this as `onUpgrade: (m, from, to) async { await m.drop...; await m.createAll(); }`
and pin it with a test.

**Register in `service_locator.dart`.** `_coreSetup()` is already `async`:

```dart
final replica = ReplicaDatabase.defaults();
sl.registerLazySingleton<ReplicaDatabase>(() => replica);
```

Do **not** `await` any drift call during startup. Opening is lazy; a cold start must
not block on the filesystem.

**Generate:** `dart run build_runner build --delete-conflicting-outputs` from
`packages/mobile`. Commit the generated `*.g.dart`.

**Gate:** `flutter analyze` prints "No issues found!" and `flutter test` is green,
both from `packages/mobile`. Nothing reads or writes the cache yet, so the suite
must be unchanged in count.

**Expect the generator to disagree with this plan in one place:** drift's generated
companion/class names follow its own pluralization of the table class. Take what the
generator produces; do not rename tables to force a guess in this document.

## Task 2 — Write path. Still no read path.

**Create `lib/core/cache/block_event_cache.dart`** implementing the interface above
over `ReplicaDatabase`.

`write` upserts by primary key inside one `transaction`, and updates the
`ReplicaMeta` row's `lowestSeq`/`highestSeq`/`syncedAt` in the same transaction. A
partially written window that disagrees with its own meta row is the failure mode
worth designing out.

**Debounce, following paseo's `PERSIST_DELAY_MS = 5_000`.** Live block events arrive
at token rate; writing each one is pointless I/O on a phone. Buffer and flush **5
seconds** after the first buffered event, and flush immediately on:

- the session's cubit closing,
- `MuxStatus` leaving `open`,
- the app leaving the foreground (Task 6 supplies the signal).

Implement the debounce as a **pure, injectable timer** so `fake_async` can drive it,
matching how the existing suite tests time.

**Wire it in `BlocksRepositoryImp`** — the constructor gains the cache and a
`ServerConfigSource`, and `getSessionBlocks` writes what it fetched on success. The
read path is not added yet, so behaviour is unchanged and every existing
`blocks_repository_test.dart` case must still pass with the cache mocked out.

**Tests** (`test/core/cache/block_event_cache_test.dart`, and additions to
`blocks_repository_test.dart`):

- an upsert of an existing `(replicaKey, sessionId, seq)` replaces rather than
  duplicating
- meta `lowestSeq`/`highestSeq` match the rows after an interleaved write
- the debounce coalesces N events into one transaction under `fake_async`
- an immediate flush on close writes buffered events
- two replica keys do not see each other's rows

Use drift's in-memory executor (`NativeDatabase.memory()`) in tests, one fresh
database per test.

**Gate:** `flutter analyze`, `flutter test`.

## Task 3 — Read path, hydration, and validation without an epoch.

`BlocksRepositoryImp.getSessionBlocks` gains a cached-first path, and this is the
task where correctness is actually at stake.

**Hydration.** On a request with no `afterSeq` and no `beforeSeq` — the cold-start
call from `BlocksCubit.refresh()` — read the cached window for
`(replicaKey, sessionId)` and return it **immediately**, while the network call runs.
The repository interface returns a single `FutureResult`, so introduce a second
method rather than changing the existing signature:

```dart
Future<List<BlockEventModel>> cachedSessionBlocks(String sessionId);
```

`BlocksCubit` calls it once in its constructor, merges through the existing
`_merge`, and rebuilds. `_merge` is already idempotent by `seq`, so the network
result reconciles by overwriting. **Do not add a second merge path.**

**Validation.** Cached `seq` values are only meaningful if the daemon has not
renumbered. There is no epoch, so validate by overlap:

1. Let `H` be the cached `highestSeq`.
2. Issue `GetSessionBlocksParams(beforeSeq: H + 1, limit: kValidationOverlap)` with
   `kValidationOverlap = 20`. Because `beforeSeq` is strict, this returns up to 20
   rows with `seq <= H`.
3. For each returned row whose `seq` is also cached, compare identity:
   `sourceId`, `kind`, `createdAt`. **Any disagreement means the log was renumbered
   — drop the session's cached rows and re-tail.**
4. **A `seq` the server no longer has is not a disagreement.** The daemon retains
   500 and trims (see Facts), so the cache legitimately outlives the server's copy.
   Compare only on the intersection, and never delete a cached row merely because
   the server did not return it.

Rule 4 is the one an implementer will get wrong. Write its test first.

**When the epoch amendment lands**, this whole validation is replaced by comparing
the stored epoch to the served one. Keep it in one function,
`validateCachedWindow(...)`, so that replacement is a deletion.

**Tests:**

- cold start with a populated cache emits blocks before the network future completes
- network result overwrites a cached row with the same `seq`
- an identity mismatch at an overlapping `seq` drops the session's rows
- rows the server has trimmed survive validation and are still rendered
- an empty cache behaves exactly as today (assert against the existing test's
  expectations, unchanged)

**Gate:** `flutter analyze`, `flutter test`.

## Task 4 — Sessions list cache.

Same shape, smaller: `SessionsRepositoryImp` gains `cachedSessions()` reading
`CachedSessions`, and writes on every successful fetch.

`SessionsCubit` is a `registerLazySingleton`, so it survives navigation and only
cold-starts once. Paint cached sessions on first build, then reconcile.

**One rule specific to this table:** a session absent from a successful full fetch is
**deleted** from the cache, in the same transaction as the upserts. A stale session
row that resurrects a deleted worktree is worse than a spinner.

**Tests:** first paint from cache; a session missing from a fetch is removed; a
failed fetch leaves the cache intact.

**Gate:** `flutter analyze`, `flutter test`.

## Task 5 — Pending sends.

Following paseo's `isUnreconciledLocalUserMessage`.

A send issued while the link is down currently fails and the text is gone. Instead:
`PendingSendStore.enqueue` persists it, the composer clears, and the block list shows
it as a **pending** block distinct from a delivered one — visibly different, never
silently identical.

- Retry when `MuxStatus` returns to `open`, and on app resume.
- `resolve(id)` on success; `fail(id, reason)` records the error and the block shows
  as failed with a retry affordance.
- **A pending send is never dropped silently.** If it cannot be delivered it stays
  visible and says why.
- Cap the queue per session; beyond the cap, refuse the new send and say so rather
  than evicting an older one the user believes is queued.

**Tests:** enqueue while disconnected; delivery on reconnect resolves exactly once;
a failed delivery is visible; queue cap refuses rather than evicts.

**Gate:** `flutter analyze`, `flutter test`.

## Task 6 — Resume policy, budget, and unpair.

**Resume policy**, following `SESSION_STALE_AFTER_MS = 60_000`. Add an
`AppLifecycleListener` (or `WidgetsBindingObserver`) that records the time the app
left the foreground and, on resume, computes `awayMs`:

- `awayMs < 60_000` → **do nothing**. No refresh, no re-subscribe. The socket
  either survived or its own reconnect path handles it.
- `awayMs >= 60_000` → revalidate: re-subscribe and `refresh()`.

Keep the threshold comparison a pure function so it is testable without a lifecycle.
This is the one task that changes existing behaviour on a path users hit constantly,
so its test must assert both branches explicitly.

**Budget**, following paseo's `MAX_TIMELINE_ITEMS = 50` and
`MAX_CACHE_BYTES = 32 * 1024 * 1024` — with our own numbers, because our window is
larger:

- per session, retain at most `kBlockMaxWindow` (1200) cached events, evicting
  lowest `seq` first;
- across all sessions, cap the database at **32 MB**, evicting whole sessions by
  oldest `syncedAt` until under budget;
- run `enforceBudget()` on a flush, never on a read.

**Unpair.** `ServerConfigStore.clear()` currently removes host, port, secure and the
password. It must also `dropReplica(replicaKey)`. **A user who unpairs must not leave
another machine's session text on the phone** — this is the one item in this plan
with a privacy consequence rather than a performance one, and it needs its own test.

**Tests:** both resume branches; per-session eviction keeps the newest; byte-budget
eviction drops whole sessions oldest-first; `clear()` empties that replica and leaves
others alone.

**Gate:** `flutter analyze`, `flutter test`.

## Task 7 — Verification against a real device.

Neither gate covers native code, and this plan ships a native SQLite dependency for
the first time. Both builds must be run:

```bash
flutter build apk --release
flutter build ios --release --no-codesign
```

Then, by hand on a device: pair, open a session with history, force-quit, relaunch
airplane-moded, and confirm blocks render from cache with a visible offline state.
Record the result in the PR. **A green `flutter test` is not evidence that
`sqlite3_flutter_libs` linked.**

## Risks

- **Generated code disagreeing with this document.** Expected in Task 1; take the
  generator's names.
- **The debounce hiding a write bug.** A dropped flush looks identical to a slow
  one. Every flush trigger gets its own test rather than one test for the timer.
- **Validation deleting real history.** Rule 4 of Task 3. The daemon's 500-event
  trim means "server does not have it" is normal, not corruption.
- **Scope creep into an offline mode.** This plan caches reads and queues sends. It
  does not make the app work offline, does not cache terminals, previews, PRs or
  file trees, and does not sync anything upward beyond pending sends.
