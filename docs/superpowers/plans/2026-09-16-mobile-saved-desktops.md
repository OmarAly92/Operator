# Mobile Saved Desktops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone keeps every desktop it has paired in a drift table, shows them by name on a "Your desktops" screen, and connects to any of them in one tap.

**Architecture:** A new authenticated daemon route `GET /api/v1/desktop` reports the machine's name; the phone calls it as its pairing probe. On the phone, a drift `desktops` table under `lib/core/database/` (dont_say layout: table + DAO in core, local data source + repository in the feature) persists the list; passwords stay in `flutter_secure_storage` keyed by desktop id. `ServerConfigStore` shrinks to an in-memory "active config" that loads from the table at launch; a pure `launchDestination` picks onboarding / desktops / sessions.

**Tech Stack:** Go 1.x + chi (daemon); Flutter 3.44.5, `drift` ^2.34.1, `drift_flutter` ^0.3.0, `drift_dev` ^2.34.0, `build_runner` ^2.7.1, `sqlite3` ^3.3.4 (dev), `flutter_bloc` (Cubit only), `mocktail`, `bloc_test`.

**Spec:** `docs/superpowers/specs/2026-09-16-mobile-saved-desktops-design.md` — read it first; every file:line below comes from it.

## Global Constraints

- All mobile commands run from `packages/mobile`. Gate for every task: `flutter analyze` → `No issues found!`, `flutter test` green.
- Backend gate: `cd backend && go test ./internal/httpd/...`; after any DTO/route change run `npm run api` from the repo root and commit `openapi.yaml` + `frontend/src/api/schema.ts` with the Go change.
- Cubit only, never Bloc. Static-only classes are `sealed class`. No `freezed`/`json_serializable`.
- Hand-written models, all fields nullable, `fromDB` for local reads. One params class per write method under `data/model/params/`.
- Drift types (`DesktopEntity`, `DesktopsCompanion`, `Desktops`) never appear above `desktops_local_data_source.dart`. No `package:drift` import in a repository, cubit, or widget.
- Every DAO method chains `.handleLocalFailure()`.
- Passwords never enter SQLite. Keychain key: `server.password.<id>`.
- Generated `*.g.dart` files are committed (CI runs no codegen).
- User-facing copy is inline English. Feature code never imports `flutter_screenutil`; spacing/radii are raw ints.
- No comments in code (user's global instruction).
- Do not add `uuid` or any other new runtime dependency beyond drift's; ids come from `Random.secure()`.
- Commit after each task with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## File map

**Daemon (create):** `backend/internal/httpd/controllers/desktop.go`, `backend/internal/httpd/controllers/desktop_test.go`.
**Daemon (modify):** `backend/internal/httpd/controllers/dto.go` (append `DesktopResponse`), `backend/internal/httpd/api.go` (`API.desktop` field, construct, register), `backend/internal/httpd/apispec/specgen/build.go` (`schemaNames` entry + `desktopOperations()`), `backend/internal/httpd/mobile_routes_test.go` (LAN-served case), generated `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`.

**Mobile core (create):** `lib/core/database/app_database.dart` (+ `.g.dart`), `lib/core/database/tables/desktop/desktop_table.dart`, `lib/core/database/tables/desktop/desktop_dao.dart` (+ `.g.dart`), `lib/core/error_handling/drift_error_handler/drift_error_handler.dart`.
**Mobile core (modify):** `pubspec.yaml`, `lib/core/api/server_config_store.dart`, `lib/core/api/api_request_helpers/end_points.dart`, `lib/core/helpers/cache/cache_keys.dart`, `lib/core/utils/service_locator.dart`, `lib/core/app_routes/app_router.dart`, `lib/main.dart`.

**Mobile pairing feature (create):** `lib/feature/pairing/data/model/desktop_model.dart`, `lib/feature/pairing/data/model/desktop_identity_model.dart`, `lib/feature/pairing/data/model/params/save_desktop_params.dart`, `lib/feature/pairing/data/model/params/rename_desktop_params.dart`, `lib/feature/pairing/data/data_source/desktops_local_data_source.dart`, `lib/feature/pairing/data/repository/desktops_repository.dart`, `lib/feature/pairing/logic/relative_label.dart`, `lib/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart`.
**Mobile pairing feature (modify):** `pairing_remote_data_source.dart`, `pairing_repository.dart`, `disconnect.dart`, `connections_cubit.dart`, `connections_state.dart`, `connections_body.dart`, `connection_row.dart`, `connections_header.dart`, `connections_screen.dart`.
**Mobile pairing feature (delete):** `connections_screen/logic/saved_connection.dart`, `connections_screen/ui/widgets/connection_form_sheet.dart`.

**Mobile other (modify):** `lib/feature/onboarding/logic/onboarding.dart`, `lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart`, `lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart`, `lib/feature/settings/presentation/settings_screen/logic/settings_cubit.dart`, `CLAUDE.md`.

---

### Task 1: Daemon route `GET /api/v1/desktop`

**Files:**
- Create: `backend/internal/httpd/controllers/desktop.go`
- Create: `backend/internal/httpd/controllers/desktop_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go` (append at end)
- Modify: `backend/internal/httpd/api.go:75-93` (struct), `:98-131` (NewAPI), `:150-165` (Register)
- Modify: `backend/internal/httpd/apispec/specgen/build.go:146` (`schemaNames`), `:426-437` (ops list), new `desktopOperations()`
- Modify: `backend/internal/httpd/mobile_routes_test.go`

**Interfaces:**
- Produces: `GET /api/v1/desktop` → `200 {"name": string, "hostname": string}`, authenticated on the LAN listener like every other `/api/v1` route.
- Produces: `controllers.DesktopName(hostname string) string`.

- [ ] **Step 1: Write the failing handler test**

`backend/internal/httpd/controllers/desktop_test.go`:

```go
package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDesktopName(t *testing.T) {
	cases := map[string]string{
		"Omars-MacBook-Pro-9.local": "Omars MacBook Pro 9",
		"office-imac":               "office imac",
		"DESKTOP-ABC123":            "DESKTOP ABC123",
		"":                          "Desktop",
		".local":                    "Desktop",
	}
	for in, want := range cases {
		if got := DesktopName(in); got != want {
			t.Errorf("DesktopName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestDesktopControllerGet(t *testing.T) {
	c := &DesktopController{Hostname: func() (string, error) { return "Omars-MacBook-Pro-9.local", nil }}
	rec := httptest.NewRecorder()
	c.Get(rec, httptest.NewRequest(http.MethodGet, "/api/v1/desktop", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body DesktopResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Name != "Omars MacBook Pro 9" || body.Hostname != "Omars-MacBook-Pro-9.local" {
		t.Fatalf("body = %+v", body)
	}
}

func TestDesktopControllerGetHostnameError(t *testing.T) {
	c := &DesktopController{Hostname: func() (string, error) { return "", errors.New("no hostname") }}
	rec := httptest.NewRecorder()
	c.Get(rec, httptest.NewRequest(http.MethodGet, "/api/v1/desktop", nil))

	var body DesktopResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if rec.Code != http.StatusOK || body.Name != "Desktop" || body.Hostname != "" {
		t.Fatalf("status %d body %+v", rec.Code, body)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/httpd/controllers/ -run 'TestDesktop' -v`
Expected: compile error, `undefined: DesktopName`.

- [ ] **Step 3: Add the DTO**

Append to `backend/internal/httpd/controllers/dto.go`:

```go
// DesktopResponse is the body of GET /api/v1/desktop: how this machine
// introduces itself to a phone that has just authenticated.
type DesktopResponse struct {
	Name     string `json:"name" description:"Display name derived from the hostname: trailing .local stripped, hyphens as spaces. Never empty."`
	Hostname string `json:"hostname" description:"os.Hostname() verbatim; empty if the OS could not report one."`
}
```

(The Go side keeps its existing comment density; the no-comments rule is the user's Dart/TS instruction for this session's edits, and `dto.go` documents every type.)

- [ ] **Step 4: Write the controller**

`backend/internal/httpd/controllers/desktop.go`:

```go
package controllers

import (
	"net/http"
	"os"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
)

type DesktopController struct {
	Hostname func() (string, error)
}

func (c *DesktopController) Register(r chi.Router) {
	r.Get("/desktop", c.Get)
}

func (c *DesktopController) Get(w http.ResponseWriter, _ *http.Request) {
	hostname := c.Hostname
	if hostname == nil {
		hostname = os.Hostname
	}
	host, err := hostname()
	if err != nil {
		host = ""
	}
	envelope.WriteJSON(w, http.StatusOK, DesktopResponse{Name: DesktopName(host), Hostname: host})
}

func DesktopName(hostname string) string {
	name := strings.TrimSuffix(strings.TrimSpace(hostname), ".local")
	name = strings.TrimSpace(strings.ReplaceAll(name, "-", " "))
	if name == "" {
		return "Desktop"
	}
	return name
}
```

- [ ] **Step 5: Run the controller tests**

Run: `cd backend && go test ./internal/httpd/controllers/ -run 'TestDesktop' -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Mount it in `API`**

In `backend/internal/httpd/api.go`:
- add field `desktop *controllers.DesktopController` to the `API` struct after `browser`;
- in `NewAPI`, add `desktop: &controllers.DesktopController{},` after the `browser:` line;
- in `Register`, add `a.desktop.Register(r)` after `a.inbox.Register(r)` inside the timeout group.

- [ ] **Step 7: Write the failing LAN-route test**

Open `backend/internal/httpd/mobile_routes_test.go`, find the existing test that builds a LAN handler and asserts `/api/v1/mobile/status` is 404 on it, and add a sibling case in the same style asserting `GET /api/v1/desktop` with a valid bearer is **200** on the LAN handler. If the file's fixture does not go through auth, assert against `isLANControlBlockedPath("/api/v1/desktop") == false` and add a second, direct route test:

```go
func TestDesktopRouteIsNotLANBlocked(t *testing.T) {
	if isLANControlBlockedPath("/api/v1/desktop") {
		t.Fatal("/api/v1/desktop must be reachable from the phone")
	}
}
```

- [ ] **Step 8: Register the operation for the spec**

In `backend/internal/httpd/apispec/specgen/build.go`:
- add `"ControllersDesktopResponse": "DesktopResponse",` to `schemaNames` (keep alphabetical position near the other `Controllers*` entries);
- add after `mobileOperations()`:

```go
func desktopOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/desktop", id: "getDesktop", tag: "desktop",
			summary: "Identify this desktop to an authenticated phone",
			resps: []respUnit{
				{http.StatusOK, controllers.DesktopResponse{}},
			},
		},
	}
}
```
- append `ops = append(ops, desktopOperations()...)` after the `mobileOperations()` line (~437).

If `operation` has a required `tag` registry (a `tags` slice near the top of `build.go`), add `desktop` there too.

- [ ] **Step 9: Regenerate and run the httpd suite**

Run from repo root: `npm run api`
Run: `cd backend && go test ./internal/httpd/...`
Expected: all PASS, including spec-parity tests. If parity complains about a missing tag description, add it where the failure points.

- [ ] **Step 10: Manual probe against the dev daemon**

Run: `curl -s http://127.0.0.1:3002/api/v1/desktop` (loopback needs no bearer)
Expected: `{"name":"Omars MacBook Pro 9","hostname":"Omars-MacBook-Pro-9.local"}` (your hostname). If the dev daemon is an old binary, restart `npm run tauri:dev` per `RUN_APP_COMMANDS.md`.

- [ ] **Step 11: Commit**

```bash
git add backend/internal/httpd frontend/src/api/schema.ts
git commit -m "feat(httpd): GET /api/v1/desktop identifies this machine to a paired phone

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Drift core — dependencies, error handler, table, DAO, database

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/lib/core/error_handling/drift_error_handler/drift_error_handler.dart`
- Create: `packages/mobile/lib/core/database/tables/desktop/desktop_table.dart`
- Create: `packages/mobile/lib/core/database/tables/desktop/desktop_dao.dart`
- Create: `packages/mobile/lib/core/database/app_database.dart`
- Create: `packages/mobile/test/core/database/tables/desktop/desktop_dao_test.dart`

**Interfaces:**
- Produces: `AppDatabase()`, `AppDatabase.forTesting(QueryExecutor)`.
- Produces: `DesktopDao(AppDatabase)` with `watchAll()`, `getAll()`, `getActive()`, `findByEndpoint(host, port, secure)`, `upsert(DesktopsCompanion) → Future<String>`, `setActive(id)`, `clearActive()`, `rename(id, name)`, `delete(id)`.
- Produces: generated `DesktopEntity` (fields `id, name, host, port, secure, isActive, renamed, lastConnectedAt, createdAt`) and `DesktopsCompanion`.

- [ ] **Step 1: Add dependencies**

In `packages/mobile/pubspec.yaml` add under `dependencies:`

```yaml
  drift: ^2.34.1
  drift_flutter: ^0.3.0
```

and under `dev_dependencies:`

```yaml
  build_runner: ^2.7.1
  drift_dev: ^2.34.0
  sqlite3: ^3.3.4
```

Run: `flutter pub get`
Expected: resolves without conflicts. If `drift_flutter ^0.3.0` conflicts with `flutter_secure_storage ^11`, record the resolved versions and proceed with what `pub` allows.

- [ ] **Step 2: Port the drift error handler**

`lib/core/error_handling/drift_error_handler/drift_error_handler.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

extension DriftFutureErrorHandler<T> on Future<T> {
  Future<T> handleLocalFailure() async {
    try {
      return await this;
    } catch (error, stacktrace) {
      throw LocalFailure<void>(
        error: error,
        stacktrace: stacktrace,
        message: error is StateError ? error.message.toString() : 'Something went wrong',
      );
    }
  }
}

extension DriftStreamErrorHandler<T> on Stream<T> {
  Stream<T> handleLocalFailure() => handleError((Object error, StackTrace stacktrace) {
    throw LocalFailure<void>(
      error: error,
      stacktrace: stacktrace,
      message: error is StateError ? error.message.toString() : 'Something went wrong',
    );
  });
}
```

- [ ] **Step 3: Write the table**

`lib/core/database/tables/desktop/desktop_table.dart`:

```dart
import 'package:drift/drift.dart';

@DataClassName('DesktopEntity')
class Desktops extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  TextColumn get port => text()();
  BoolColumn get secure => boolean()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  BoolColumn get renamed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {host, port, secure},
  ];
}
```

- [ ] **Step 4: Write the DAO**

`lib/core/database/tables/desktop/desktop_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'desktop_dao.g.dart';

@DriftAccessor(tables: [Desktops])
class DesktopDao extends DatabaseAccessor<AppDatabase> with _$DesktopDaoMixin {
  DesktopDao(super.db);

  Stream<List<DesktopEntity>> watchAll() => (select(desktops)..orderBy(_order)).watch().handleLocalFailure();

  Future<List<DesktopEntity>> getAll() => (select(desktops)..orderBy(_order)).get().handleLocalFailure();

  Future<DesktopEntity?> getActive() =>
      (select(desktops)..where((t) => t.isActive.equals(true))).getSingleOrNull().handleLocalFailure();

  Future<DesktopEntity?> findByEndpoint(String host, String port, bool secure) =>
      (select(desktops)..where((t) => t.host.equals(host) & t.port.equals(port) & t.secure.equals(secure)))
          .getSingleOrNull()
          .handleLocalFailure();

  Future<String> upsert(DesktopsCompanion row) => transaction(() async {
    final existing = await findByEndpoint(row.host.value, row.port.value, row.secure.value);
    if (existing == null) {
      await into(desktops).insert(row);
      return row.id.value;
    }
    if (!existing.renamed) {
      await (update(desktops)..where((t) => t.id.equals(existing.id))).write(DesktopsCompanion(name: row.name));
    }
    return existing.id;
  }).handleLocalFailure();

  Future<void> setActive(String id) => transaction(() async {
    await update(desktops).write(const DesktopsCompanion(isActive: Value(false)));
    await (update(desktops)..where((t) => t.id.equals(id))).write(
      DesktopsCompanion(isActive: const Value(true), lastConnectedAt: Value(DateTime.now())),
    );
  }).handleLocalFailure();

  Future<void> clearActive() =>
      update(desktops).write(const DesktopsCompanion(isActive: Value(false))).handleLocalFailure();

  Future<void> rename(String id, String name) => (update(desktops)..where((t) => t.id.equals(id)))
      .write(DesktopsCompanion(name: Value(name), renamed: const Value(true)))
      .handleLocalFailure();

  Future<void> delete(String id) => (delete(desktops)..where((t) => t.id.equals(id))).go().handleLocalFailure();

  static final List<OrderingTerm Function($DesktopsTable)> _order = [
    (t) => OrderingTerm.desc(t.isActive),
    (t) => OrderingTerm.desc(t.lastConnectedAt),
    (t) => OrderingTerm.desc(t.createdAt),
  ];
}
```

Note: `Future<void> delete(...)` shadows `DatabaseAccessor.delete`; if the analyzer objects, rename the method to `remove` and adjust Tasks 3–4 accordingly (`_dao.remove(id)`).

- [ ] **Step 5: Write the database**

`lib/core/database/app_database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Desktops], daos: [DesktopDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'operator_mobile'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}
```

- [ ] **Step 6: Generate**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` and `desktop_dao.g.dart` written. Run `flutter analyze` → no issues (fix the `delete` shadow per the note in Step 4 if flagged).

- [ ] **Step 7: Write the failing DAO test**

`test/core/database/tables/desktop/desktop_dao_test.dart`:

```dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';

DesktopsCompanion _row(String id, {String host = '192.168.1.2', String name = 'Mac'}) => DesktopsCompanion.insert(
  id: id,
  name: name,
  host: host,
  port: '58682',
  secure: false,
);

void main() {
  late AppDatabase db;
  late DesktopDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.desktopDao;
  });

  tearDown(() => db.close());

  test('upsert inserts a new endpoint and returns its id', () async {
    final id = await dao.upsert(_row('a'));
    expect(id, 'a');
    expect(await dao.getAll(), hasLength(1));
  });

  test('upsert on an existing endpoint keeps the row and refreshes the name', () async {
    await dao.upsert(_row('a', name: 'Old'));
    final id = await dao.upsert(_row('b', name: 'New'));
    expect(id, 'a');
    final all = await dao.getAll();
    expect(all.single.name, 'New');
  });

  test('upsert keeps a user rename', () async {
    await dao.upsert(_row('a', name: 'Old'));
    await dao.rename('a', 'Mine');
    await dao.upsert(_row('b', name: 'New'));
    expect((await dao.getAll()).single.name, 'Mine');
  });

  test('setActive leaves exactly one active row and stamps lastConnectedAt', () async {
    await dao.upsert(_row('a', host: '1.1.1.1'));
    await dao.upsert(_row('b', host: '2.2.2.2'));
    await dao.setActive('a');
    await dao.setActive('b');
    final active = await dao.getActive();
    expect(active?.id, 'b');
    expect(active?.lastConnectedAt, isNotNull);
    expect((await dao.getAll()).where((d) => d.isActive), hasLength(1));
  });

  test('clearActive leaves no active row', () async {
    await dao.upsert(_row('a'));
    await dao.setActive('a');
    await dao.clearActive();
    expect(await dao.getActive(), isNull);
  });

  test('watchAll orders active first, then most recently connected', () async {
    await dao.upsert(_row('a', host: '1.1.1.1'));
    await dao.upsert(_row('b', host: '2.2.2.2'));
    await dao.upsert(_row('c', host: '3.3.3.3'));
    await dao.setActive('b');
    await dao.setActive('c');
    await dao.setActive('a');
    await dao.clearActive();
    await dao.setActive('b');
    final ids = (await dao.watchAll().first).map((d) => d.id).toList();
    expect(ids.first, 'b');
    expect(ids, ['b', 'a', 'c']);
  });

  test('delete removes the row', () async {
    await dao.upsert(_row('a'));
    await dao.delete('a');
    expect(await dao.getAll(), isEmpty);
  });
}
```

- [ ] **Step 8: Run the DAO tests**

Run: `flutter test test/core/database/`
Expected: all PASS. If `NativeDatabase` cannot find sqlite on the host, add `sqlite3_flutter_libs` is *not* needed for tests — the `sqlite3` dev dependency uses the macOS system library; check `flutter test` output for the exact dlopen error before changing anything.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/database lib/core/error_handling/drift_error_handler test/core/database
git commit -m "feat(mobile): drift database with the desktops table and DAO

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Feature data — models, params, local data source

**Files:**
- Create: `lib/feature/pairing/data/model/desktop_model.dart`
- Create: `lib/feature/pairing/data/model/params/save_desktop_params.dart`
- Create: `lib/feature/pairing/data/model/params/rename_desktop_params.dart`
- Create: `lib/feature/pairing/data/data_source/desktops_local_data_source.dart`
- Create: `test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`

**Interfaces:**
- Consumes: `DesktopDao`, `DesktopEntity`, `DesktopsCompanion` (Task 2).
- Produces: `DesktopModel {id, name, host, port, secure, isActive, lastConnectedAt}` + `DesktopModel.fromDB(DesktopEntity)` + `ServerConfig toServerConfig(String password)`.
- Produces: `SaveDesktopParams(name, host, port, secure, password)`, `RenameDesktopParams(id, name)`.
- Produces: `DesktopsLocalDataSource`: `Stream<List<DesktopModel>> watchAll()`, `Future<DesktopModel?> getActive()`, `Future<DesktopModel> save(SaveDesktopParams)`, `Future<void> activate(String id)`, `Future<void> deactivate()`, `Future<void> rename(RenameDesktopParams)`, `Future<void> remove(String id)`, `Future<String?> passwordFor(String id)`.

- [ ] **Step 1: Write the model and params**

`lib/feature/pairing/data/model/desktop_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';

class DesktopModel extends Equatable {
  final String? id;
  final String? name;
  final String? host;
  final String? port;
  final bool? secure;
  final bool? isActive;
  final DateTime? lastConnectedAt;

  const DesktopModel({this.id, this.name, this.host, this.port, this.secure, this.isActive, this.lastConnectedAt});

  factory DesktopModel.fromDB(DesktopEntity entity) => DesktopModel(
    id: entity.id,
    name: entity.name,
    host: entity.host,
    port: entity.port,
    secure: entity.secure,
    isActive: entity.isActive,
    lastConnectedAt: entity.lastConnectedAt,
  );

  ServerConfig toServerConfig(String password) =>
      ServerConfig(host: host ?? '', httpPort: port ?? '', secure: secure ?? false, password: password);

  String get address => '$host:$port';

  @override
  List<Object?> get props => [id, name, host, port, secure, isActive, lastConnectedAt];
}
```

The `DesktopEntity` import is the one permitted drift-adjacent import in a model, solely for `fromDB` (skill: "reads come from `fromDB`").

`lib/feature/pairing/data/model/params/save_desktop_params.dart`:

```dart
class SaveDesktopParams {
  const SaveDesktopParams({
    required this.name,
    required this.host,
    required this.port,
    required this.secure,
    required this.password,
  });

  final String name;
  final String host;
  final String port;
  final bool secure;
  final String password;
}
```

`lib/feature/pairing/data/model/params/rename_desktop_params.dart`:

```dart
class RenameDesktopParams {
  const RenameDesktopParams({required this.id, required this.name});

  final String id;
  final String name;
}
```

- [ ] **Step 2: Write the failing local data source test**

`test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

const _params = SaveDesktopParams(name: 'Mac', host: '192.168.1.2', port: '58682', secure: false, password: 'pw1');

void main() {
  late AppDatabase db;
  late _MockSecureStorage storage;
  late DesktopsLocalDataSourceImp source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _MockSecureStorage();
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    source = DesktopsLocalDataSourceImp(db.desktopDao, storage);
  });

  tearDown(() => db.close());

  test('save stores the row, the password under its id, and activates it', () async {
    final saved = await source.save(_params);

    expect(saved.id, isNotEmpty);
    expect(saved.isActive, isTrue);
    expect(saved.name, 'Mac');
    verify(() => storage.write(key: 'server.password.${saved.id}', value: 'pw1')).called(1);
  });

  test('saving the same endpoint again reuses the id and rotates the password', () async {
    final first = await source.save(_params);
    final second = await source.save(const SaveDesktopParams(
      name: 'Mac', host: '192.168.1.2', port: '58682', secure: false, password: 'pw2',
    ));

    expect(second.id, first.id);
    expect(await source.watchAll().first, hasLength(1));
    verify(() => storage.write(key: 'server.password.${first.id}', value: 'pw2')).called(1);
  });

  test('passwordFor reads the keychain entry for that id', () async {
    when(() => storage.read(key: 'server.password.x')).thenAnswer((_) async => 'pw');
    expect(await source.passwordFor('x'), 'pw');
  });

  test('remove deletes the row and its password', () async {
    final saved = await source.save(_params);
    await source.remove(saved.id!);

    expect(await source.watchAll().first, isEmpty);
    verify(() => storage.delete(key: 'server.password.${saved.id}')).called(1);
  });

  test('deactivate leaves no active desktop; activate picks one', () async {
    final saved = await source.save(_params);
    await source.deactivate();
    expect(await source.getActive(), isNull);
    await source.activate(saved.id!);
    expect((await source.getActive())?.id, saved.id);
  });

  test('rename changes the label', () async {
    final saved = await source.save(_params);
    await source.rename(RenameDesktopParams(id: saved.id!, name: 'Studio'));
    expect((await source.watchAll().first).single.name, 'Studio');
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`
Expected: compile error, `DesktopsLocalDataSourceImp` undefined.

- [ ] **Step 4: Write the local data source**

`lib/feature/pairing/data/data_source/desktops_local_data_source.dart`:

```dart
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

abstract class DesktopsLocalDataSource {
  Stream<List<DesktopModel>> watchAll();
  Future<DesktopModel?> getActive();
  Future<DesktopModel> save(SaveDesktopParams params);
  Future<void> activate(String id);
  Future<void> deactivate();
  Future<void> rename(RenameDesktopParams params);
  Future<void> remove(String id);
  Future<String?> passwordFor(String id);
}

class DesktopsLocalDataSourceImp implements DesktopsLocalDataSource {
  DesktopsLocalDataSourceImp(this._dao, this._secureStorage);

  final DesktopDao _dao;
  final FlutterSecureStorage _secureStorage;

  static String passwordKey(String id) => 'server.password.$id';

  @override
  Stream<List<DesktopModel>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(DesktopModel.fromDB).toList());

  @override
  Future<DesktopModel?> getActive() async {
    final row = await _dao.getActive();
    return row == null ? null : DesktopModel.fromDB(row);
  }

  @override
  Future<DesktopModel> save(SaveDesktopParams params) async {
    final id = await _dao.upsert(
      DesktopsCompanion.insert(
        id: _newId(),
        name: params.name,
        host: params.host,
        port: params.port,
        secure: params.secure,
      ),
    );
    await _secureStorage.write(key: passwordKey(id), value: params.password);
    await _dao.setActive(id);
    final row = await _dao.getActive();
    return DesktopModel.fromDB(row!);
  }

  @override
  Future<void> activate(String id) => _dao.setActive(id);

  @override
  Future<void> deactivate() => _dao.clearActive();

  @override
  Future<void> rename(RenameDesktopParams params) => _dao.rename(params.id, params.name);

  @override
  Future<void> remove(String id) async {
    await _dao.delete(id);
    await _secureStorage.delete(key: passwordKey(id));
  }

  @override
  Future<String?> passwordFor(String id) => _secureStorage.read(key: passwordKey(id));

  static String _newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/feature/pairing/data/data_source/desktops_local_data_source_test.dart`
Expected: 6 PASS. Then `flutter analyze` → no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/feature/pairing/data test/feature/pairing/data/data_source/desktops_local_data_source_test.dart
git commit -m "feat(mobile): desktops local data source over drift and the keychain

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `DesktopsRepository` and DI

**Files:**
- Create: `lib/feature/pairing/data/repository/desktops_repository.dart`
- Create: `test/feature/pairing/data/repository/desktops_repository_test.dart`
- Modify: `lib/core/utils/service_locator.dart:75-99` (`_coreSetup`)

**Interfaces:**
- Consumes: `DesktopsLocalDataSource` (Task 3).
- Produces: `DesktopsRepository`: `Stream<List<DesktopModel>> watchDesktops()`, `FutureResult<DesktopModel?> getActive()`, `FutureResult<DesktopModel> save(SaveDesktopParams)`, `FutureResult<void> activate(String id)`, `FutureResult<void> deactivate()`, `FutureResult<void> rename(RenameDesktopParams)`, `FutureResult<void> remove(String id)`, `FutureResult<String?> passwordFor(String id)`.
- Produces DI registrations: `AppDatabase`, `DesktopDao`, `DesktopsLocalDataSource`, `DesktopsRepository`.

- [ ] **Step 1: Write the failing repository test**

`test/feature/pairing/data/repository/desktops_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

class _MockLocal extends Mock implements DesktopsLocalDataSource {}

const _params = SaveDesktopParams(name: 'Mac', host: 'h', port: '1', secure: false, password: 'p');
const _model = DesktopModel(id: 'a', name: 'Mac', host: 'h', port: '1', secure: false, isActive: true);

void main() {
  late _MockLocal local;
  late DesktopsRepositoryImp repository;

  setUpAll(() => registerFallbackValue(_params));

  setUp(() {
    local = _MockLocal();
    repository = DesktopsRepositoryImp(local);
  });

  test('save returns the saved model', () async {
    when(() => local.save(any())).thenAnswer((_) async => _model);
    final result = await repository.save(_params);
    expect(result.isSuccess, isTrue);
    result.when(onSuccess: (m) => expect(m, _model), onFailure: (_) => fail('failure'));
  });

  test('a LocalFailure from the data source becomes a failure result', () async {
    when(() => local.remove('a')).thenThrow(LocalFailure<void>(error: 'disk'));
    final result = await repository.remove('a');
    expect(result.isFailure, isTrue);
  });

  test('watchDesktops passes the stream through', () {
    when(() => local.watchAll()).thenAnswer((_) => Stream.value([_model]));
    expect(repository.watchDesktops(), emits([_model]));
  });
}
```

Check `Result` for the exact accessor names (`isSuccess`/`isFailure`) in `lib/core/helpers/result/result.dart` and match them.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/data/repository/desktops_repository_test.dart`
Expected: compile error, `DesktopsRepositoryImp` undefined.

- [ ] **Step 3: Write the repository**

`lib/feature/pairing/data/repository/desktops_repository.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

abstract class DesktopsRepository {
  Stream<List<DesktopModel>> watchDesktops();
  FutureResult<DesktopModel?> getActive();
  FutureResult<DesktopModel> save(SaveDesktopParams params);
  FutureResult<void> activate(String id);
  FutureResult<void> deactivate();
  FutureResult<void> rename(RenameDesktopParams params);
  FutureResult<void> remove(String id);
  FutureResult<String?> passwordFor(String id);
}

class DesktopsRepositoryImp implements DesktopsRepository {
  DesktopsRepositoryImp(this._local);

  final DesktopsLocalDataSource _local;

  @override
  Stream<List<DesktopModel>> watchDesktops() => _local.watchAll();

  @override
  FutureResult<DesktopModel?> getActive() => _guard(_local.getActive);

  @override
  FutureResult<DesktopModel> save(SaveDesktopParams params) => _guard(() => _local.save(params));

  @override
  FutureResult<void> activate(String id) => _guard(() => _local.activate(id));

  @override
  FutureResult<void> deactivate() => _guard(_local.deactivate);

  @override
  FutureResult<void> rename(RenameDesktopParams params) => _guard(() => _local.rename(params));

  @override
  FutureResult<void> remove(String id) => _guard(() => _local.remove(id));

  @override
  FutureResult<String?> passwordFor(String id) => _guard(() => _local.passwordFor(id));

  FutureResult<T> _guard<T>(Future<T> Function() run) async {
    try {
      return Result.success(await run());
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/feature/pairing/data/repository/desktops_repository_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Register in DI**

In `lib/core/utils/service_locator.dart` `_coreSetup`, after the `FlutterSecureStorage` registration and **before** `ServerConfigStore`:

```dart
    sl.registerLazySingleton<AppDatabase>(AppDatabase.new);
    sl.registerLazySingleton<DesktopDao>(() => DesktopDao(sl<AppDatabase>()));
    sl.registerLazySingleton<DesktopsLocalDataSource>(
      () => DesktopsLocalDataSourceImp(sl<DesktopDao>(), sl<FlutterSecureStorage>()),
    );
    sl.registerLazySingleton<DesktopsRepository>(() => DesktopsRepositoryImp(sl<DesktopsLocalDataSource>()));
```

Add the four imports. Leave `ServerConfigStore`'s registration as is for now (Task 5 changes it).

- [ ] **Step 6: Gate and commit**

Run: `flutter analyze && flutter test`
Expected: clean, green.

```bash
git add lib/feature/pairing/data/repository/desktops_repository.dart test/feature/pairing/data/repository/desktops_repository_test.dart lib/core/utils/service_locator.dart
git commit -m "feat(mobile): desktops repository and DI wiring

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `ServerConfigStore` on the table; pairing identifies and saves

**Files:**
- Modify: `lib/core/api/server_config_store.dart` (whole file)
- Modify: `lib/core/helpers/cache/cache_keys.dart:5-8` (remove `serverHost`, `serverHttpPort`, `serverSecure`, `serverPassword`)
- Modify: `lib/core/api/api_request_helpers/end_points.dart` (add `desktop`)
- Create: `lib/feature/pairing/data/model/desktop_identity_model.dart`
- Modify: `lib/feature/pairing/data/data_source/pairing_remote_data_source.dart` (whole file)
- Modify: `lib/feature/pairing/data/repository/pairing_repository.dart` (whole file)
- Modify: `lib/core/utils/service_locator.dart` (`ServerConfigStore`, `PairingRepository` registrations)
- Modify tests: `test/core/api/server_config_test.dart` (if it constructs the store), `test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart`, `test/feature/pairing/data/repository/pairing_repository_test.dart`, every test that stubs `store.save(...)` (grep `store.save` under `test/`).

**Interfaces:**
- Consumes: `DesktopsLocalDataSource`, `DesktopsRepository`, `SaveDesktopParams`.
- Produces: `ServerConfigStore(DesktopsLocalDataSource)` with `current`, `Future<void> load()`, `void set(ServerConfig)`, `void clear()`.
- Produces: `EndPoints.desktop = '/api/v1/desktop'`.
- Produces: `DesktopIdentityModel {name, hostname}` with `fromJson`.
- Produces: `PairingRemoteDataSource.identify(ServerConfig target) → Future<DesktopIdentityModel>` (replaces `ping`).
- Produces: `PairingRepository.verifyAndConnect(ServerConfig) → FutureResult<DesktopModel>`.

- [ ] **Step 1: Write the failing store test**

Replace/extend `test/core/api/server_config_store_test.dart` (create if absent):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';

class _MockLocal extends Mock implements DesktopsLocalDataSource {}

const _active = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);

void main() {
  late _MockLocal local;
  late ServerConfigStore store;

  setUp(() {
    local = _MockLocal();
    store = ServerConfigStore(local);
  });

  test('load resolves the active desktop and its password into current', () async {
    when(() => local.getActive()).thenAnswer((_) async => _active);
    when(() => local.passwordFor('a')).thenAnswer((_) async => 'pw');

    await store.load();

    expect(store.current, const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw'));
  });

  test('load leaves current null when nothing is active', () async {
    when(() => local.getActive()).thenAnswer((_) async => null);
    await store.load();
    expect(store.current, isNull);
  });

  test('load leaves current null when the password is missing', () async {
    when(() => local.getActive()).thenAnswer((_) async => _active);
    when(() => local.passwordFor('a')).thenAnswer((_) async => null);
    await store.load();
    expect(store.current, isNull);
  });

  test('set and clear only touch memory', () {
    const config = ServerConfig(host: 'h', httpPort: '1', secure: true, password: 'p');
    store.set(config);
    expect(store.current, config);
    store.clear();
    expect(store.current, isNull);
    verifyZeroInteractions(local);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/api/server_config_store_test.dart`
Expected: compile errors (`ServerConfigStore(local)` signature, `set`).

- [ ] **Step 3: Rewrite `ServerConfigStore`**

`lib/core/api/server_config_store.dart`:

```dart
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';

class ServerConfigStore implements ServerConfigSource {
  ServerConfigStore(this._desktops);

  final DesktopsLocalDataSource _desktops;

  ServerConfig? _current;

  @override
  ServerConfig? get current => _current;

  Future<void> load() async {
    final active = await _desktops.getActive();
    if (active?.id == null) return;
    final password = await _desktops.passwordFor(active!.id!);
    if (password == null) return;
    _current = active.toServerConfig(password);
  }

  void set(ServerConfig config) => _current = config;

  void clear() => _current = null;
}
```

Remove `serverHost`, `serverHttpPort`, `serverSecure`, `serverPassword` from `cache_keys.dart`. Grep `CacheKeys.server` across `lib/` and `test/` and delete every remaining use (there should be none outside the old store and its test).

- [ ] **Step 4: Run the store test**

Run: `flutter test test/core/api/server_config_store_test.dart`
Expected: 4 PASS.

- [ ] **Step 5: Add the endpoint and identity model**

`end_points.dart`: add `static const String desktop = '/api/v1/desktop';` after `health`. Add a case to `test/core/api/end_points_test.dart` if that file enumerates constants.

`lib/feature/pairing/data/model/desktop_identity_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class DesktopIdentityModel extends Equatable {
  final String? name;
  final String? hostname;

  const DesktopIdentityModel({this.name, this.hostname});

  factory DesktopIdentityModel.fromJson(Map<String, dynamic> json) => DesktopIdentityModel(
    name: json['name'] as String?,
    hostname: json['hostname'] as String?,
  );

  @override
  List<Object?> get props => [name, hostname];
}
```

- [ ] **Step 6: Write the failing remote data source test**

Rewrite `test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart` to the identify contract. Keep its existing `ApiConsumer` mock setup and assert:

```dart
  test('identify hits /api/v1/desktop with the pairing target and parses the name', () async {
    when(() => api.get(EndPoints.desktop, options: any(named: 'options'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: EndPoints.desktop),
        data: {'name': 'Omars MacBook Pro 9', 'hostname': 'Omars-MacBook-Pro-9.local'},
      ),
    );

    final identity = await source.identify(_target);

    expect(identity.name, 'Omars MacBook Pro 9');
    final options = verify(() => api.get(EndPoints.desktop, options: captureAny(named: 'options'))).captured.single as Options;
    expect(options.extra?['pairingTarget'], _target);
  });
```

- [ ] **Step 7: Rewrite the remote data source**

`lib/feature/pairing/data/data_source/pairing_remote_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';

abstract class PairingRemoteDataSource {
  Future<DesktopIdentityModel> identify(ServerConfig target);
}

class PairingRemoteDataSourceImp implements PairingRemoteDataSource {
  PairingRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<DesktopIdentityModel> identify(ServerConfig target) async {
    final response = await _apiConsumer.get(EndPoints.desktop, options: Options(extra: {'pairingTarget': target}));
    final data = response.data;
    return DesktopIdentityModel.fromJson(data is Map<String, dynamic> ? data : const {});
  }
}
```

- [ ] **Step 8: Write the failing pairing repository test**

Rewrite `test/feature/pairing/data/repository/pairing_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockStore extends Mock implements ServerConfigStore {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');
const _saved = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);

void main() {
  late _MockRemote remote;
  late _MockDesktops desktops;
  late _MockStore store;
  late PairingRepositoryImp repository;

  setUpAll(() {
    registerFallbackValue(_target);
    registerFallbackValue(const SaveDesktopParams(name: '', host: '', port: '', secure: false, password: ''));
  });

  setUp(() {
    remote = _MockRemote();
    desktops = _MockDesktops();
    store = _MockStore();
    repository = PairingRepositoryImp(remote, desktops, store);
  });

  test('identifies, saves with the daemon name, then sets the active config', () async {
    when(() => remote.identify(_target)).thenAnswer((_) async => const DesktopIdentityModel(name: 'Mac', hostname: 'mac.local'));
    when(() => desktops.save(any())).thenAnswer((_) async => Result.success(_saved));

    final result = await repository.verifyAndConnect(_target);

    expect(result.isSuccess, isTrue);
    final params = verify(() => desktops.save(captureAny())).captured.single as SaveDesktopParams;
    expect(params.name, 'Mac');
    expect(params.password, 'secret12');
    verifyInOrder([() => remote.identify(_target), () => desktops.save(any()), () => store.set(_target)]);
  });

  test('falls back to the address when the daemon sends no name', () async {
    when(() => remote.identify(_target)).thenAnswer((_) async => const DesktopIdentityModel());
    when(() => desktops.save(any())).thenAnswer((_) async => Result.success(_saved));

    await repository.verifyAndConnect(_target);

    final params = verify(() => desktops.save(captureAny())).captured.single as SaveDesktopParams;
    expect(params.name, '10.0.0.5:3011');
  });

  test('does not save or set when identify fails', () async {
    when(() => remote.identify(_target)).thenThrow(ServerFailure<Map<String, dynamic>>(error: 'x', message: 'no', statusCode: 401));

    final result = await repository.verifyAndConnect(_target);

    expect(result.isFailure, isTrue);
    verifyNever(() => desktops.save(any()));
    verifyNever(() => store.set(any()));
  });
}
```

Check `ServerFailure`'s constructor in `lib/core/error_handling/failures/server_failure.dart` and match its required parameters.

- [ ] **Step 9: Rewrite the pairing repository**

`lib/feature/pairing/data/repository/pairing_repository.dart`:

```dart
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

abstract class PairingRepository {
  FutureResult<DesktopModel> verifyAndConnect(ServerConfig target);
}

class PairingRepositoryImp implements PairingRepository {
  PairingRepositoryImp(this._remote, this._desktops, this._store);

  final PairingRemoteDataSource _remote;
  final DesktopsRepository _desktops;
  final ServerConfigStore _store;

  @override
  FutureResult<DesktopModel> verifyAndConnect(ServerConfig target) async {
    try {
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
      return saved.when(
        onSuccess: (desktop) {
          _store.set(target);
          return Result.success(desktop);
        },
        onFailure: Result.failure,
      );
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
```

If `Result.when` returns `void` in this codebase (check `result.dart:46`), use a `switch` on the sealed `Result` or its `fold`-style accessor instead; the intent is: on save success set the store and return the model, on save failure propagate it.

- [ ] **Step 10: Update DI and the remaining callers**

`service_locator.dart`:
- `ServerConfigStore(sl<DesktopsLocalDataSource>())`.
- `PairingRepositoryImp(sl<PairingRemoteDataSource>(), sl<DesktopsRepository>(), sl<ServerConfigStore>())`.

`PairingScanCubit` and `ManualConnectCubit` only inspect `result.isSuccess`/`onSuccess: (_)`; keep them as they are unless the analyzer flags the changed generic. Run `grep -rn "store.save\|\.ping(" test lib` and fix every hit: stubs of `store.save` become `store.set` (a `void` method: `when(() => store.set(any())).thenReturn(null)` or drop the stub, since mocktail returns null for void by default).

- [ ] **Step 11: Gate and commit**

Run: `flutter analyze && flutter test`
Expected: clean, green.

```bash
git add lib test
git commit -m "feat(mobile): pairing identifies the desktop and saves it; ServerConfigStore reads the active row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Launch routing and Disconnect

**Files:**
- Modify: `lib/feature/onboarding/logic/onboarding.dart` (whole file)
- Modify: `test/feature/onboarding/logic/onboarding_test.dart` (whole file)
- Modify: `lib/main.dart:42-45`
- Modify: `lib/feature/pairing/logic/disconnect.dart` (whole file)
- Modify: `test/feature/pairing/logic/disconnect_test.dart` (whole file)
- Modify: `lib/feature/settings/presentation/settings_screen/logic/settings_cubit.dart:24-27`
- Modify: `lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart:177-178`
- Modify: `lib/core/utils/service_locator.dart` (SettingsCubit construction — pass `DesktopsRepository`)

**Interfaces:**
- Produces: `enum LaunchDestination { onboarding, desktops, sessions }` and `LaunchDestination launchDestination({required int desktopCount, required bool hasActive})`.
- Produces: `Future<void> forgetServer(DesktopsRepository desktops, ServerConfigStore store)`.

- [ ] **Step 1: Write the failing routing test**

`test/feature/onboarding/logic/onboarding_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

void main() {
  group('launchDestination', () {
    test('a fresh install onboards', () {
      expect(launchDestination(desktopCount: 0, hasActive: false), LaunchDestination.onboarding);
    });

    test('an active desktop goes straight to sessions', () {
      expect(launchDestination(desktopCount: 2, hasActive: true), LaunchDestination.sessions);
    });

    test('saved desktops with none active show the list', () {
      expect(launchDestination(desktopCount: 1, hasActive: false), LaunchDestination.desktops);
    });

    test('an active flag without rows is treated as no desktops', () {
      expect(launchDestination(desktopCount: 0, hasActive: true), LaunchDestination.onboarding);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/onboarding/logic/onboarding_test.dart`
Expected: compile error, `launchDestination` undefined.

- [ ] **Step 3: Implement**

`lib/feature/onboarding/logic/onboarding.dart`:

```dart
enum LaunchDestination { onboarding, desktops, sessions }

LaunchDestination launchDestination({required int desktopCount, required bool hasActive}) {
  if (desktopCount == 0) return LaunchDestination.onboarding;
  return hasActive ? LaunchDestination.sessions : LaunchDestination.desktops;
}
```

`lib/main.dart` around line 42 — replace the `configured`/`initialRoute` lines with:

```dart
  final desktops = await sl<DesktopsRepository>().watchDesktops().first;
  final initialRoute = switch (launchDestination(
    desktopCount: desktops.length,
    hasActive: sl<ServerConfigStore>().current != null,
  )) {
    LaunchDestination.onboarding => RoutesStrings.onboarding,
    LaunchDestination.desktops => RoutesStrings.connections,
    LaunchDestination.sessions => RoutesStrings.sessions,
  };
```

(`ServerConfigStore.load()` is already awaited earlier in `main`; confirm with `grep -n "load()" lib/main.dart`.)

- [ ] **Step 4: Run and gate**

Run: `flutter test test/feature/onboarding/logic/onboarding_test.dart`
Expected: 4 PASS.

- [ ] **Step 5: Write the failing disconnect test**

`test/feature/pairing/logic/disconnect_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/logic/disconnect.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockDesktops desktops;
  late _MockStore store;

  setUp(() {
    desktops = _MockDesktops();
    store = _MockStore();
  });

  test('forgetServer deactivates the desktop and clears the live config', () async {
    when(() => desktops.deactivate()).thenAnswer((_) async => Result.success(null));

    await forgetServer(desktops, store);

    verifyInOrder([() => desktops.deactivate(), () => store.clear()]);
  });

  test('forgetServer still clears the live config when deactivation fails', () async {
    when(() => desktops.deactivate()).thenThrow(Exception('disk'));

    await expectLater(forgetServer(desktops, store), throwsA(isA<Exception>()));

    verify(() => store.clear()).called(1);
  });
}
```

- [ ] **Step 6: Implement disconnect**

`lib/feature/pairing/logic/disconnect.dart`:

```dart
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

Future<void> forgetServer(DesktopsRepository desktops, ServerConfigStore store) async {
  try {
    await desktops.deactivate();
  } finally {
    store.clear();
  }
}
```

`settings_cubit.dart`: add a `DesktopsRepository _desktops` constructor dependency, call `forgetServer(_desktops, _store)`. Update its DI registration in `service_locator.dart` and the constructor call in `test/feature/settings/presentation/settings_screen/logic/settings_cubit_test.dart` (+ `settings_body_test.dart` if it builds the cubit) with a `_MockDesktopsRepository` stubbing `deactivate()`.

`settings_body.dart:177-178`: `RoutesStrings.onboarding` → `RoutesStrings.connections`.

- [ ] **Step 7: Gate and commit**

Run: `flutter analyze && flutter test`
Expected: clean, green.

```bash
git add lib test
git commit -m "feat(mobile): launch routing across onboarding, desktops and sessions; disconnect keeps the desktop

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: `ConnectionsCubit` on real data

**Files:**
- Create: `lib/feature/pairing/logic/relative_label.dart`
- Create: `test/feature/pairing/logic/relative_label_test.dart`
- Modify: `lib/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart` (whole file)
- Modify: `lib/feature/pairing/presentation/connections_screen/logic/connections_state.dart` (whole file)
- Modify: `test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart` (whole file)
- Delete: `lib/feature/pairing/presentation/connections_screen/logic/saved_connection.dart`
- Modify: `lib/core/utils/service_locator.dart` (`ConnectionsCubit` registration)

**Interfaces:**
- Produces: `String relativeLabel(DateTime? at, DateTime now)`.
- Produces: `ConnectionsCubit(DesktopsRepository, PairingRemoteDataSource, ServerConfigStore)` with `List<DesktopModel> desktops`, `String? connectingId`, `Map<String, ConnectionErrorCopy> errors`, `Future<void> connectTo(String id, TargetPlatform platform)`, `Future<void> rename(String id, String name)`, `Future<void> remove(String id)`.
- Produces states: `ConnectionsInitialState`, `DesktopsUpdatedState(List<DesktopModel>)`, `ConnectLoadingState(id)`, `ConnectSuccessState(id)`, `ConnectFailureState(id, ConnectionErrorCopy)`, `LastDesktopRemovedState`.

- [ ] **Step 1: Write the failing relative-label test**

`test/feature/pairing/logic/relative_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/relative_label.dart';

void main() {
  final now = DateTime(2026, 9, 16, 12);

  test('never connected', () => expect(relativeLabel(null, now), 'not connected yet'));
  test('just now', () => expect(relativeLabel(now.subtract(const Duration(seconds: 30)), now), 'just now'));
  test('minutes', () => expect(relativeLabel(now.subtract(const Duration(minutes: 5)), now), '5m ago'));
  test('hours', () => expect(relativeLabel(now.subtract(const Duration(hours: 2)), now), '2h ago'));
  test('days', () => expect(relativeLabel(now.subtract(const Duration(days: 3)), now), '3d ago'));
  test('weeks and beyond', () => expect(relativeLabel(now.subtract(const Duration(days: 20)), now), '2w ago'));
}
```

- [ ] **Step 2: Implement**

`lib/feature/pairing/logic/relative_label.dart`:

```dart
String relativeLabel(DateTime? at, DateTime now) {
  if (at == null) return 'not connected yet';
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${diff.inDays ~/ 7}w ago';
}
```

Run: `flutter test test/feature/pairing/logic/relative_label_test.dart` → 6 PASS.

- [ ] **Step 3: Write the failing cubit test**

`test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockStore extends Mock implements ServerConfigStore {}

const _a = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: false);
const _b = DesktopModel(id: 'b', name: 'iMac', host: '10.0.0.6', port: '3011', secure: false, isActive: false);
const _config = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw');

void main() {
  late _MockDesktops desktops;
  late _MockRemote remote;
  late _MockStore store;
  late StreamController<List<DesktopModel>> list;

  setUpAll(() {
    registerFallbackValue(_config);
    registerFallbackValue(const RenameDesktopParams(id: '', name: ''));
  });

  setUp(() {
    desktops = _MockDesktops();
    remote = _MockRemote();
    store = _MockStore();
    list = StreamController<List<DesktopModel>>.broadcast();
    when(() => desktops.watchDesktops()).thenAnswer((_) => list.stream);
  });

  tearDown(() => list.close());

  ConnectionsCubit build() => ConnectionsCubit(desktops, remote, store);

  blocTest<ConnectionsCubit, ConnectionsState>(
    'mirrors the repository stream into desktops',
    build: build,
    act: (_) => list.add([_a, _b]),
    expect: () => [
      const DesktopsUpdatedState([_a, _b]),
    ],
    verify: (cubit) => expect(cubit.desktops, [_a, _b]),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'connectTo identifies with the stored password, activates, sets the store',
    build: build,
    setUp: () {
      when(() => desktops.passwordFor('a')).thenAnswer((_) async => Result.success('pw'));
      when(() => remote.identify(_config)).thenAnswer((_) async => const DesktopIdentityModel(name: 'Mac'));
      when(() => desktops.activate('a')).thenAnswer((_) async => Result.success(null));
    },
    seed: () => const DesktopsUpdatedState([_a]),
    act: (cubit) {
      cubit.desktops = [_a];
      return cubit.connectTo('a', TargetPlatform.iOS);
    },
    expect: () => [const ConnectLoadingState('a'), const ConnectSuccessState('a')],
    verify: (_) => verifyInOrder([
      () => remote.identify(_config),
      () => desktops.activate('a'),
      () => store.set(_config),
    ]),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'a 401 surfaces the rotated-password copy on that row',
    build: build,
    setUp: () {
      when(() => desktops.passwordFor('a')).thenAnswer((_) async => Result.success('pw'));
      when(() => remote.identify(any())).thenThrow(
        ServerFailure<Map<String, dynamic>>(error: 'x', message: 'bad', statusCode: 401),
      );
    },
    act: (cubit) {
      cubit.desktops = [_a];
      return cubit.connectTo('a', TargetPlatform.iOS);
    },
    expect: () => [
      const ConnectLoadingState('a'),
      isA<ConnectFailureState>().having((s) => s.copy.title, 'title', 'Your desktop rejected the password'),
    ],
    verify: (cubit) {
      expect(cubit.errors['a'], isNotNull);
      verifyNever(() => desktops.activate(any()));
      verifyNever(() => store.set(any()));
    },
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'removing the active desktop clears the store; removing the last one signals it',
    build: build,
    setUp: () {
      when(() => desktops.remove('a')).thenAnswer((_) async => Result.success(null));
    },
    act: (cubit) async {
      cubit.desktops = [_a.copyWithActive(true)];
      await cubit.remove('a');
      list.add(const []);
    },
    expect: () => [const DesktopsUpdatedState([]), const LastDesktopRemovedState()],
    verify: (_) => verify(() => store.clear()).called(1),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'rename forwards to the repository',
    build: build,
    setUp: () => when(() => desktops.rename(any())).thenAnswer((_) async => Result.success(null)),
    act: (cubit) => cubit.rename('a', 'Studio'),
    expect: () => <ConnectionsState>[],
    verify: (_) {
      final params = verify(() => desktops.rename(captureAny())).captured.single as RenameDesktopParams;
      expect(params.name, 'Studio');
    },
  );
}
```

Add to `DesktopModel` (Task 3 file) a `copyWithActive(bool)` helper if not present:

```dart
  DesktopModel copyWithActive(bool active) => DesktopModel(
    id: id, name: name, host: host, port: port, secure: secure, isActive: active, lastConnectedAt: lastConnectedAt,
  );
```

- [ ] **Step 4: Run it to verify it fails**

Run: `flutter test test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart`
Expected: compile errors against the old cubit.

- [ ] **Step 5: Rewrite state and cubit**

`connections_state.dart`:

```dart
part of 'connections_cubit.dart';

sealed class ConnectionsState extends Equatable {
  const ConnectionsState();

  @override
  List<Object?> get props => [];
}

final class ConnectionsInitialState extends ConnectionsState {
  const ConnectionsInitialState();
}

final class DesktopsUpdatedState extends ConnectionsState {
  const DesktopsUpdatedState(this.desktops);

  final List<DesktopModel> desktops;

  @override
  List<Object?> get props => [desktops];
}

final class ConnectLoadingState extends ConnectionsState {
  const ConnectLoadingState(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class ConnectSuccessState extends ConnectionsState {
  const ConnectSuccessState(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class ConnectFailureState extends ConnectionsState {
  const ConnectFailureState(this.id, this.copy);

  final String id;
  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [id, copy.title, copy.message];
}

final class LastDesktopRemovedState extends ConnectionsState {
  const LastDesktopRemovedState();
}
```

`connections_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

part 'connections_state.dart';

class ConnectionsCubit extends Cubit<ConnectionsState> {
  ConnectionsCubit(this._desktops, this._remote, this._store) : super(const ConnectionsInitialState()) {
    _subscription = _desktops.watchDesktops().listen(_onDesktops);
  }

  final DesktopsRepository _desktops;
  final PairingRemoteDataSource _remote;
  final ServerConfigStore _store;

  List<DesktopModel> desktops = const [];
  String? connectingId;
  final Map<String, ConnectionErrorCopy> errors = {};
  StreamSubscription<List<DesktopModel>>? _subscription;
  bool _hadDesktops = false;

  void _onDesktops(List<DesktopModel> next) {
    desktops = next;
    emit(DesktopsUpdatedState(next));
    if (_hadDesktops && next.isEmpty) emit(const LastDesktopRemovedState());
    _hadDesktops = next.isNotEmpty;
  }

  DesktopModel? byId(String id) {
    for (final desktop in desktops) {
      if (desktop.id == id) return desktop;
    }
    return null;
  }

  Future<void> connectTo(String id, TargetPlatform platform) async {
    final desktop = byId(id);
    if (desktop == null || connectingId != null) return;
    connectingId = id;
    errors.remove(id);
    emit(ConnectLoadingState(id));

    final password = await _desktops.passwordFor(id);
    final config = desktop.toServerConfig(password.valueOrNull ?? '');
    try {
      await _remote.identify(config);
      await _desktops.activate(id);
      _store.set(config);
      connectingId = null;
      emit(ConnectSuccessState(id));
    } on Failure catch (failure) {
      connectingId = null;
      final copy = describeConnectionFailure(
        classifyConnectionFailure(failure.statusCode),
        host: desktop.host ?? '',
        port: desktop.port ?? '',
        platform: platform,
      );
      errors[id] = copy;
      emit(ConnectFailureState(id, copy));
    }
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _desktops.rename(RenameDesktopParams(id: id, name: trimmed));
  }

  Future<void> remove(String id) async {
    final wasActive = byId(id)?.isActive ?? false;
    await _desktops.remove(id);
    errors.remove(id);
    if (wasActive) _store.clear();
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
```

`Result` needs a `valueOrNull` getter; add it to `lib/core/helpers/result/result.dart` if absent:

```dart
  T? get valueOrNull => switch (this) { _ResultSuccess(:final value) => value, _ResultFailure() => null };
```

(match the sealed subclass field names in that file).

Delete `saved_connection.dart`. Update DI: `sl.registerFactory<ConnectionsCubit>(() => ConnectionsCubit(sl<DesktopsRepository>(), sl<PairingRemoteDataSource>(), sl<ServerConfigStore>()))`.

- [ ] **Step 6: Run the cubit tests**

Run: `flutter test test/feature/pairing/presentation/connections_screen/logic/connections_cubit_test.dart`
Expected: 5 PASS. The UI does not compile yet (it imports `SavedConnection`) — that's Task 8; `flutter analyze` will report errors in `connections_body.dart` only. Do not commit a red analyzer: fold Task 8 into the same commit if you cannot land this task green on its own, or temporarily keep `saved_connection.dart` until Task 8 and delete it there.

- [ ] **Step 7: Commit (together with Task 8 if needed)**

```bash
git add lib/feature/pairing test/feature/pairing lib/core/utils/service_locator.dart lib/core/helpers/result/result.dart
git commit -m "feat(mobile): connections cubit backed by the desktops repository

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: "Your desktops" UI, rename sheet, onboarding back-navigation

**Files:**
- Modify: `lib/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart` (whole file)
- Modify: `lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart` (`_metaText`, add `active`, `error`, `onScanAgain`)
- Modify: `lib/feature/pairing/presentation/connections_screen/ui/widgets/connections_header.dart:19` (icon)
- Modify: `lib/feature/pairing/presentation/connections_screen/ui/connections_screen.dart` (listener)
- Create: `lib/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart`
- Delete: `lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_form_sheet.dart`
- Modify: `lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart` (`fromDesktops` arg, `canPop`, back arrow)
- Modify: `lib/core/app_routes/app_router.dart:34-35` (pass `fromDesktops`)
- Modify/Create widget tests under `test/feature/pairing/presentation/connections_screen/ui/` (see Step 6).

**Interfaces:**
- Consumes: `ConnectionsCubit` API from Task 7, `relativeLabel`, `isLocalNetworkHost`.
- Produces: `Future<String?> showRenameDesktopSheet(BuildContext, {required String initialName})`.
- Produces: `OnboardingScreen({bool fromDesktops = false})`.

- [ ] **Step 1: Rename sheet**

Create `rename_desktop_sheet.dart` by copying `connection_form_sheet.dart`, then: keep only the name field; title "Rename desktop"; primary action "Save"; return the trimmed name via `Navigator.pop(context, name)`; export `Future<String?> showRenameDesktopSheet(BuildContext context, {required String initialName})`. Delete `connection_form_sheet.dart`.

- [ ] **Step 2: Row**

In `connection_row.dart`:
- add constructor params `required bool active`, `ConnectionErrorCopy? error`, `VoidCallback? onScanAgain`;
- `_metaText()` returns `'Connecting…'` while connecting, otherwise `'$address · ${isLocalNetworkHost(host) ? 'LAN' : 'Remote'} · $lastConnectedLabel'` — pass `host` as its own param (split `address` into `host` + `address`);
- before the name `AppText`, when `active`, insert a 6 px dot: `Container(width: 6, height: 6, decoration: BoxDecoration(color: skin.accent, shape: BoxShape.circle))` + `HorizontalSpace(6)`;
- under the meta text, when `error != null`, add `VerticalSpace(4)`, `AppText(error.message, style: AppTextStyle.style11Regular.copyWith(color: skin.red), maxLines: 3)`, and when `onScanAgain != null` a `GestureDetector(onTap: onScanAgain, child: AppText('Scan again', style: AppTextStyle.style11SemiBold.copyWith(color: skin.accent)))`.

- [ ] **Step 3: Body**

Rewrite `connections_body.dart`'s `build` to read from `ConnectionsCubit.desktops` inside a `BlocConsumer`:
- `buildWhen`: every state (they all change row visuals);
- title "Your desktops", subtitle "Tap a desktop to connect.";
- the group card as today, rows built from `DesktopModel`: `name: d.name ?? d.address`, `host: d.host ?? ''`, `address: d.address`, `lastConnectedLabel: relativeLabel(d.lastConnectedAt, DateTime.now())`, `connecting: cubit.connectingId == d.id`, `active: d.isActive ?? false`, `error: cubit.errors[d.id]`, `onScanAgain: cubit.errors[d.id]?.title == 'Your desktop rejected the password' ? () => Navigator.of(context).pushNamed(RoutesStrings.pairingScan) : null` — better: compare on a new `ConnectionErrorCopy.isAuth` flag; add `final bool isAuth` to `ConnectionErrorCopy` in `connection_error.dart` set true only in the `auth` case (default false), and use `error.isAuth`;
- `onTap: () => cubit.connectTo(d.id!, Theme.of(context).platform)`;
- menu: `rename` → `showRenameDesktopSheet` → `cubit.rename`; `remove` → existing dialog → `cubit.remove`. Remove the `connect` menu action if the sheet has one (tap already connects) — keep the sheet file otherwise;
- bottom: `PrimaryButton(text: 'Pair another desktop', onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.onboarding, arguments: {'fromDesktops': true}))`; delete `_AddManuallyLink` and `_openAddSheet`. The header's `+` calls the same navigation.

`connections_header.dart:19`: replace the mascot with `ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset('assets/images/app_icon_image.png', width: 28, height: 28))`.

- [ ] **Step 4: Screen listener**

`connections_screen.dart`: wrap the body in a `BlocListener<ConnectionsCubit, ConnectionsState>`:
- `ConnectSuccessState` → `Haptics.success()`, `Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false)`;
- `ConnectFailureState` → `Haptics.error()`;
- `LastDesktopRemovedState` → `pushNamedAndRemoveUntil(RoutesStrings.onboarding, (_) => false)`.

`Haptics` lives in `lib/core/helpers/` (grep `class Haptics`).

- [ ] **Step 5: Onboarding back-navigation**

`onboarding_screen.dart`: add `final bool fromDesktops;` (`const OnboardingScreen({super.key, this.fromDesktops = false})`); `PopScope(canPop: widget.fromDesktops, …)`; when `fromDesktops`, render a leading back `IconButton(icon: Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.of(context).pop())` before the icon tile in the header row. `_pair` passes `{'fromOnboarding': true}` unchanged — the scan screen's `pushNamedAndRemoveUntil(sessions)` already lands correctly.

`app_router.dart:34-35`:

```dart
      case RoutesStrings.onboarding:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (context) => OnboardingScreen(fromDesktops: args?['fromDesktops'] as bool? ?? false),
          settings: settings,
        );
```

- [ ] **Step 6: Widget tests**

Create `test/feature/pairing/presentation/connections_screen/ui/connections_body_test.dart` following the pattern of an existing body test (e.g. `test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart` for `SkinScope` + `ScreenUtilInit` + `BlocProvider.value` scaffolding). Cover:

1. two desktops render their names, the active one shows the dot (find by `Container` with `BoxShape.circle`, or give the dot a `Key('active-dot-<id>')`);
2. a `ConnectFailureState` with `isAuth` shows "Scan again";
3. tapping "Pair another desktop" pushes `RoutesStrings.onboarding` with `{'fromDesktops': true}` (use a `NavigatorObserver` mock as other tests do).

Use a `_MockConnectionsCubit extends MockCubit<ConnectionsState> implements ConnectionsCubit` with `desktops`, `connectingId`, `errors` stubbed.

- [ ] **Step 7: Gate and commit**

Run: `flutter analyze && flutter test`
Expected: clean, green.

```bash
git add lib test
git commit -m "feat(mobile): Your desktops screen connects, renames and removes saved desktops

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Docs, native build check, real-device verification

**Files:**
- Modify: `CLAUDE.md` (mobile section: drift bullet, `ServerConfig` spine paragraph)
- Modify: `docs/mobile-parity-ledger.md` only if it lists `saved_connection.dart` or `connection_form_sheet.dart` (grep first)

- [ ] **Step 1: CLAUDE.md**

Replace the drift bullet under "Conventions specific to this package" with:

```
- **`drift` and `build_runner` are permitted for on-device state under
  `lib/core/database/`** (saved desktops today; the replica cache when it lands),
  following the `flutter-knowledge:drift-local-database` layout: tables and DAOs
  in `core/database/tables/<table>/`, local data sources in the feature, no drift
  import above the data source. Wire models stay hand-written — drift never
  parses the wire. Passwords never enter SQLite; they stay in
  `flutter_secure_storage` under `server.password.<id>`. Generated `*.g.dart` is
  committed, because CI runs `flutter analyze` and `flutter test` with no
  generation step. Regenerate with `dart run build_runner build
  --delete-conflicting-outputs`.
```

In the "`ServerConfig` is the spine" paragraph, replace the last sentence with: "Saved desktops live in the drift `desktops` table; each one's password lives in `flutter_secure_storage` keyed by desktop id; `ServerConfigStore` holds only the active one in memory, loaded at launch."

- [ ] **Step 2: Native builds**

Run: `flutter build ios --release --no-codesign` and `flutter build apk --release`
Expected: both succeed (first `sqlite3_flutter_libs` link). Fix pod/gradle issues before continuing.

- [ ] **Step 3: Real-device walkthrough**

With the dev daemon running (`npm run tauri:dev` with the scrubbed env per `RUN_APP_COMMANDS.md`) and the phone on the same Wi-Fi:
1. fresh install → onboarding → Pair Desktop → scan → sessions;
2. Settings › Disconnect → "Your desktops" shows the Mac by hostname with an address subtitle;
3. tap the row → sessions;
4. on the desktop, regenerate the password; on the phone, Disconnect, tap the row → the row shows "Your desktop rejected the password" + "Scan again"; scan → one row, connected;
5. rename → label persists across relaunch; remove → onboarding.

Record the outcome in the commit body.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs(mobile): drift boundary now covers saved desktops

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage.** §4 daemon route → Task 1. §5.1–5.2 deps/core → Task 2. §5.3 rename tracking → Task 2 (`upsert`/`rename`) + Task 7. §5.4 keychain → Task 3. §5.5 feature layer → Tasks 3–4. §5.6 store → Task 5. §5.7 pairing repository → Task 5. §6 routing → Task 6. §7 flows: tap/401/scan-again → Tasks 7–8; add → Task 8; rename/remove/last-removed → Tasks 7–8; Disconnect → Task 6. §8 UI → Task 8. §9 DI → Tasks 4, 5, 6, 7. §10 tests → each task. §11 CLAUDE.md → Task 9. §12 native build → Task 9.

**Type consistency.** `DesktopsLocalDataSource.remove` / `DesktopsRepository.remove` / `ConnectionsCubit.remove` all take `String id`. `DesktopDao.delete` may become `remove` per Task 2's note — Task 3 calls `_dao.delete(id)`; rename both together. `PairingRepository.verifyAndConnect` now returns `FutureResult<DesktopModel>`; the scan/manual cubits ignore the value. `ServerConfigStore.set` is `void` — mocktail stubs need no `thenAnswer`. `ConnectionErrorCopy` gains `isAuth` (Task 8 Step 3) — add it to the constructor with a default of `false` and set it in the `auth` case only; update `connection_error_test.dart` if it compares copies by field.

**Known judgment calls.** `ConnectionsCubit` exposes `desktops` as a settable field so `bloc_test` can seed it; the UI reads it, never writes it. `main.dart` takes `.first` of the watch stream for the count — a one-shot read is fine; the list screen subscribes separately.
