# Flutter Mobile Port — M0 (Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Flutter app at `packages/mobile` with a mirrored `lib/core`, the Operator skin, DI, routing, and CI — no features.

**Architecture:** The RN tree moves to `packages/mobile_rn` (frozen reference, CI disabled) and a Flutter project takes its place. `lib/core` mirrors `~/development/projects/dont_say/lib/core`, with two deliberate deviations: the API base URL is runtime-supplied from a `ServerConfigStore` (pairing has not happened yet at construction time), and `NetworkStatus` checks daemon reachability rather than public internet, because the daemon lives on the LAN or Tailscale.

**Tech Stack:** Flutter 3.44.5 / Dart 3.12.2, `flutter_bloc` (Cubit only), `get_it`, `dio`, `equatable`, `easy_localization`, `flutter_screenutil` (core only), `talker`, `shared_preferences`, `flutter_secure_storage`, `mocktail` + `bloc_test`.

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Conventions are the `flutter-knowledge` skill. Where the mirrored source contradicts it, the skill wins.
- **REQUIRED SUB-SKILL:** invoke `flutter-testing` before writing the first test file. Do not invent test layout.
- Cubit only — never `Bloc` with events.
- Static-only classes are `sealed class X`, never a private constructor.
- No comments except non-obvious business rules, external constraints, or workarounds.
- Single quotes, `const` constructors wherever possible, full 8-digit hex colors, `final` locals.
- No `flutter_screenutil` extensions (`.h`/`.w`/`.r`/`.sp`) outside `AppTextStyle`.
- No `drift`, no `freezed`, no `json_serializable`, no `build_runner`.
- Verification after every task: `flutter analyze` clean and `flutter test` green. Never run or build the app.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.

---

### Task 1: Freeze the RN tree

**Files:**
- Move: `packages/mobile/` → `packages/mobile_rn/`
- Modify: `.github/workflows/mobile.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `packages/mobile_rn/` as the read-only port reference; `packages/mobile/` empty and ready for Task 2.

- [ ] **Step 1: Move the tree**

```bash
cd /Users/omaraly/development/AI/Operator
git mv packages/mobile packages/mobile_rn
```

- [ ] **Step 2: Disable the RN workflow**

Replace the `on:` block of `.github/workflows/mobile.yml` so the frozen tree cannot fail CI, and repoint its paths:

```yaml
on:
  workflow_dispatch:
```

Then change every `working-directory: packages/mobile` to `packages/mobile_rn` and the `cache-dependency-path` to `packages/mobile_rn/package-lock.json`.

- [ ] **Step 3: Verify the workflow still parses**

Run:
```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/mobile.yml')); print(d.get(True, d.get('on')))"
```
Expected: `{'workflow_dispatch': None}`

- [ ] **Step 4: Verify nothing else references the old path**

Run:
```bash
grep -rn "packages/mobile/" --include="*.yml" --include="*.md" --include="*.json" . | grep -v node_modules | grep -v mobile_rn
```
Expected: no output. Fix any hit by repointing it to `packages/mobile_rn/`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(mobile): freeze the RN app as packages/mobile_rn"
```

---

### Task 2: Flutter project skeleton and CI

**Files:**
- Create: `packages/mobile/` (via `flutter create`)
- Create: `packages/mobile/analysis_options.yaml`
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/test/smoke_test.dart`
- Create: `.github/workflows/mobile-flutter.yml`

**Interfaces:**
- Consumes: Task 1's empty `packages/mobile/`.
- Produces: a Flutter package named `operator_mobile` where `flutter test` runs; CI job `Mobile (Flutter)`.

- [ ] **Step 1: Create the project**

```bash
cd /Users/omaraly/development/AI/Operator/packages
flutter create --org dev.operator --project-name operator_mobile --platforms ios,android mobile
```

- [ ] **Step 2: Set dependencies**

Replace the `dependencies` / `dev_dependencies` blocks of `packages/mobile/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.10.0
  flutter_bloc: ^9.1.1
  equatable: ^2.1.0
  get_it: ^9.2.1
  easy_localization: ^3.0.7+1
  intl: ^0.20.2
  flutter_screenutil: ^5.9.3
  flutter_svg: ^2.3.0
  talker: ^5.1.17
  talker_dio_logger: ^5.1.17
  talker_bloc_logger: ^5.1.17
  talker_flutter: ^5.1.17
  shared_preferences: ^2.5.5
  flutter_secure_storage: ^9.2.4
  shimmer: ^3.0.0
  flutter_spinkit: ^5.2.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mocktail: ^1.0.4
  bloc_test: ^10.0.0
```

- [ ] **Step 3: Write the smoke test**

`packages/mobile/test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test harness runs', () {
    expect(1 + 1, 2);
  });
}
```

- [ ] **Step 4: Run it**

Run: `cd packages/mobile && flutter pub get && flutter test`
Expected: PASS, 1 test.

- [ ] **Step 5: Add the CI workflow**

`.github/workflows/mobile-flutter.yml`:

```yaml
name: Mobile (Flutter)

on:
  push:
    branches: [master]
  pull_request:
    paths:
      - "packages/mobile/**"
      - ".github/workflows/mobile-flutter.yml"

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: packages/mobile
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.5
          channel: stable
          cache: true
      - run: flutter pub get
      - name: Analyze
        run: flutter analyze
      - name: Unit tests
        run: flutter test
```

- [ ] **Step 6: Delete the generated placeholder app and its test**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
rm -f test/widget_test.dart
```

Replace `lib/main.dart` with this exact stub; Task 13 replaces it with the real bootstrap:

```dart
void main() {}
```

- [ ] **Step 7: Verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean, 1 test passing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(mobile): scaffold the Flutter app and its CI"
```

---

### Task 3: Result and the Failure hierarchy

**Files:**
- Create: `packages/mobile/lib/core/helpers/result/result.dart`
- Create: `packages/mobile/lib/core/error_handling/failures/failure.dart`
- Create: `packages/mobile/lib/core/error_handling/failures/server_failure.dart`
- Create: `packages/mobile/lib/core/error_handling/failures/local_failure.dart`
- Create: `packages/mobile/lib/core/error_handling/failures/mapping_failure.dart`
- Create: `packages/mobile/lib/core/error_handling/dio_error_handler/status_code.dart`
- Create: `packages/mobile/lib/core/helpers/logging/app_logger.dart`
- Test: `packages/mobile/test/core/helpers/result_test.dart`

**Interfaces:**
- Consumes: Task 2's package.
- Produces:
  - `typedef FutureResult<T> = Future<Result<T, Failure>>;`
  - `Result.success(T)`, `Result.failure(E)`, `result.when(onSuccess:, onFailure:)`, `isSuccess`, `isFailure`, `getOrDefault(T)`
  - `abstract class Failure<T>` with `message`, `statusCode`, `apiStatus`, `validationErrors`
  - `ServerFailure({required Object error, ...})`, `ServerFailure.noNetwork()`, `MappingFailure`, `LocalFailure`
  - `StatusCode.noInternetConnection`

- [ ] **Step 1: Invoke the testing skill**

Invoke the `flutter-testing` skill before writing any test in this plan. Follow its layout and mocking rules for every subsequent task.

- [ ] **Step 2: Copy the sources verbatim**

Copy these files from `/Users/omaraly/development/projects/dont_say/lib/core/` to the same relative paths under `packages/mobile/lib/core/`, changing only the import prefix `package:dont_say/` → `package:operator_mobile/`:

- `helpers/result/result.dart`
- `error_handling/failures/failure.dart` (and its four `part` files)
- `error_handling/dio_error_handler/status_code.dart`
- `helpers/logging/app_logger.dart`

Do not restructure them. `Result` is a sealed class with `_ResultSuccess` / `_ResultFailure` variants and a `when` extension; `Failure` is an abstract Equatable implementing `Exception` with `ServerFailure`, `LocalFailure`, `MappingFailure`, `UnauthorizedFailure` as `part` files.

- [ ] **Step 3: Write the failing test**

`packages/mobile/test/core/helpers/result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';

void main() {
  group('Result', () {
    test('success carries its value through when', () {
      final Result<int, Failure> result = Result.success(7);
      var seen = 0;
      result.when(onSuccess: (value) => seen = value, onFailure: (_) => seen = -1);
      expect(seen, 7);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('failure carries its failure through when', () {
      final failure = ServerFailure.noNetwork();
      final Result<int, Failure> result = Result.failure(failure);
      Failure? seen;
      result.when(onSuccess: (_) {}, onFailure: (error) => seen = error);
      expect(seen, same(failure));
      expect(result.getOrDefault(3), 3);
    });

    test('noNetwork carries the offline status code', () {
      expect(ServerFailure.noNetwork().statusCode, StatusCode.noInternetConnection);
    });
  });
}
```

- [ ] **Step 4: Run it**

Run: `cd packages/mobile && flutter test test/core/helpers/result_test.dart`
Expected: PASS (the implementation is a verbatim copy; a failure here means the copy or import rewrite is wrong).

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze
git add -A
git commit -m "feat(mobile): port Result and the Failure hierarchy"
```

---

### Task 4: GlobalResponse

**Files:**
- Create: `packages/mobile/lib/core/api/models/global_response.dart`
- Test: `packages/mobile/test/core/api/global_response_test.dart`

**Interfaces:**
- Consumes: `MappingFailure` from Task 3.
- Produces: `GlobalResponse<T>({status, message, data, isCached})` and
  `GlobalResponse.fromJson(Map<String, dynamic> json, {dynamic Function(Map<String, dynamic>)? fromJsonT, bool withDataKey = true, String key = 'data'})`.

- [ ] **Step 1: Copy the source verbatim**

Copy `/Users/omaraly/development/projects/dont_say/lib/core/api/models/global_response.dart`, rewriting the import prefix. It already supports `withDataKey: false`, which is what the Operator daemon needs — its payloads are bare (`{projects: [...]}`), not wrapped in `data`.

- [ ] **Step 2: Write the failing test**

`packages/mobile/test/core/api/global_response_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

class _Probe {
  const _Probe(this.count);
  final int count;

  static _Probe fromJson(Map<String, dynamic> json) =>
      _Probe((json['projects'] as List<dynamic>).length);
}

void main() {
  group('GlobalResponse', () {
    test('parses a bare daemon payload when withDataKey is false', () {
      final response = GlobalResponse<_Probe>.fromJson(
        {
          'projects': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
        fromJsonT: _Probe.fromJson,
        withDataKey: false,
      );

      expect(response.data?.count, 2);
    });

    test('throws MappingFailure when the payload shape is wrong', () {
      expect(
        () => GlobalResponse<_Probe>.fromJson(
          {'projects': 'not-a-list'},
          fromJsonT: _Probe.fromJson,
          withDataKey: false,
        ),
        throwsA(isA<MappingFailure>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run it**

Run: `flutter test test/core/api/global_response_test.dart`
Expected: PASS.

- [ ] **Step 4: Verify and commit**

```bash
flutter analyze
git add -A
git commit -m "feat(mobile): port GlobalResponse"
```

---

### Task 5: ServerConfig and its store

**Files:**
- Create: `packages/mobile/lib/core/api/server_config.dart`
- Create: `packages/mobile/lib/core/api/server_config_store.dart`
- Test: `packages/mobile/test/core/api/server_config_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class ServerConfig { final String host; final String httpPort; final bool secure; final String password; String get httpBase; String get wsBase; }`
  - `class ServerConfigStore { ServerConfig? get current; Future<void> save(ServerConfig); Future<void> load(); Future<void> clear(); }`

This is the first deliberate deviation from `dont_say`, whose `DioConsumer` assumes a compile-time host. Operator's base URL is unknown until pairing completes.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/api/server_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('builds an http base from host and port', () {
      const config = ServerConfig(
        host: '100.101.102.103',
        httpPort: '3011',
        secure: false,
        password: 'secret12',
      );

      expect(config.httpBase, 'http://100.101.102.103:3011');
      expect(config.wsBase, 'ws://100.101.102.103:3011');
    });

    test('switches scheme when secure', () {
      const config = ServerConfig(
        host: 'my-pc.tail1234.ts.net',
        httpPort: '443',
        secure: true,
        password: 'secret12',
      );

      expect(config.httpBase, 'https://my-pc.tail1234.ts.net:443');
      expect(config.wsBase, 'wss://my-pc.tail1234.ts.net:443');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/api/server_config_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:operator_mobile/core/api/server_config.dart'`.

- [ ] **Step 3: Implement ServerConfig**

`packages/mobile/lib/core/api/server_config.dart`:

```dart
import 'package:equatable/equatable.dart';

class ServerConfig extends Equatable {
  const ServerConfig({
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
  });

  final String host;
  final String httpPort;
  final bool secure;
  final String password;

  String get httpBase => '${secure ? 'https' : 'http'}://$host:$httpPort';

  String get wsBase => '${secure ? 'wss' : 'ws'}://$host:$httpPort';

  @override
  List<Object?> get props => [host, httpPort, secure, password];
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/api/server_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Implement the store**

`packages/mobile/lib/core/api/server_config_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigStore {
  ServerConfigStore(this._secureStorage, this._preferences);

  static const _hostKey = 'server.host';
  static const _portKey = 'server.httpPort';
  static const _secureKey = 'server.secure';
  static const _passwordKey = 'server.password';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _preferences;

  ServerConfig? _current;

  ServerConfig? get current => _current;

  Future<void> load() async {
    final host = _preferences.getString(_hostKey);
    final httpPort = _preferences.getString(_portKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (host == null || httpPort == null || password == null) return;

    _current = ServerConfig(
      host: host,
      httpPort: httpPort,
      secure: _preferences.getBool(_secureKey) ?? false,
      password: password,
    );
  }

  Future<void> save(ServerConfig config) async {
    _current = config;
    await _preferences.setString(_hostKey, config.host);
    await _preferences.setString(_portKey, config.httpPort);
    await _preferences.setBool(_secureKey, config.secure);
    await _secureStorage.write(key: _passwordKey, value: config.password);
  }

  Future<void> clear() async {
    _current = null;
    await _preferences.remove(_hostKey);
    await _preferences.remove(_portKey);
    await _preferences.remove(_secureKey);
    await _secureStorage.delete(key: _passwordKey);
  }
}
```

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add ServerConfig and its persistence store"
```

---

### Task 6: ApiConsumer and DioConsumer

**Files:**
- Create: `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`
- Create: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`
- Create: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/core/api/interceptors/server_config_interceptor.dart`
- Modify: `packages/mobile/lib/core/api/server_config_store.dart` (add `implements ServerConfigSource`)
- Test: `packages/mobile/test/core/api/server_config_interceptor_test.dart`

**Interfaces:**
- Consumes: `ServerConfigStore` (Task 5).
- Produces:
  - `abstract class ApiConsumer` with `get`/`post`/`put`/`delete`/`setDefaultDioOptions`
  - `abstract class ServerConfigSource { ServerConfig? get current; }`
  - `class ServerConfigInterceptor extends Interceptor` — constructor `ServerConfigInterceptor(ServerConfigSource source)`
  - `class DioConsumer implements ApiConsumer` — constructor **`DioConsumer(ServerConfigSource source)`**, no `baseUrl` parameter (Task 13 calls it as `DioConsumer(sl<ServerConfigStore>())`)
  - `sealed class EndPoints`

- [ ] **Step 1: Copy the consumer contract**

Copy `api/api_request_helpers/api_consumer.dart` verbatim from `dont_say`, rewriting the import prefix.

- [ ] **Step 2: Write the failing interceptor test**

`packages/mobile/test/core/api/server_config_interceptor_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';

class _StubStore implements ServerConfigSource {
  _StubStore(this.current);

  @override
  final ServerConfig? current;
}

void main() {
  group('ServerConfigInterceptor', () {
    test('stamps base url and authorization from the paired config', () {
      final interceptor = ServerConfigInterceptor(
        _StubStore(
          const ServerConfig(
            host: '10.0.0.5',
            httpPort: '3011',
            secure: false,
            password: 'secret12',
          ),
        ),
      );
      final options = RequestOptions(path: '/api/v1/projects');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.baseUrl, 'http://10.0.0.5:3011');
      expect(options.headers['Authorization'], 'Bearer secret12');
    });

    test('rejects the request when no config is paired', () {
      final interceptor = ServerConfigInterceptor(_StubStore(null));
      final options = RequestOptions(path: '/api/v1/projects');

      expect(
        () => interceptor.onRequest(options, RequestInterceptorHandler()),
        throwsA(isA<DioException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/core/api/server_config_interceptor_test.dart`
Expected: FAIL — the interceptor file does not exist.

- [ ] **Step 4: Implement the interceptor**

`packages/mobile/lib/core/api/interceptors/server_config_interceptor.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/server_config.dart';

abstract class ServerConfigSource {
  ServerConfig? get current;
}

class ServerConfigInterceptor extends Interceptor {
  ServerConfigInterceptor(this._source);

  final ServerConfigSource _source;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final config = _source.current;
    if (config == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'No paired Operator server',
      );
    }

    options.baseUrl = config.httpBase;
    options.headers['Authorization'] = 'Bearer ${config.password}';
    handler.next(options);
  }
}
```

Then make `ServerConfigStore` implement `ServerConfigSource` by adding `implements ServerConfigSource` to its declaration and `@override` to its `current` getter.

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/core/api/server_config_interceptor_test.dart`
Expected: PASS.

- [ ] **Step 6: Implement DioConsumer**

Copy `api/api_request_helpers/dio_consumer.dart` from `dont_say` and change three things:

1. Replace the `baseUrl` constructor parameter and the `savedDomain` lookup with a single required
   `ServerConfigSource` positional parameter — `DioConsumer(this._configSource)` — since the
   interceptor now owns the base URL. Drop the `_instance` singleton caching; `get_it` owns the
   lifetime.
2. Set `connectTimeout` and `receiveTimeout` to `const Duration(seconds: 12)`, **not** 40. Over Tailscale a sleeping host otherwise hangs for the OS TCP timeout (75–120s), freezing Kill, send, and the poll loop.
3. Register `ServerConfigInterceptor` first in `client.interceptors`, ahead of the Talker logger.

- [ ] **Step 7: Create EndPoints**

`packages/mobile/lib/core/api/api_request_helpers/end_points.dart`:

```dart
sealed class EndPoints {
  static const String projects = '/api/v1/projects';
  static const String sessions = '/api/v1/sessions';
  static const String settings = '/api/v1/settings';
  static const String agents = '/api/v1/agents';
  static const String notifications = '/api/v1/notifications';

  static String sessionPr(String sessionId) => '/api/v1/sessions/$sessionId/pr';
}
```

Later features add their own static members here. Interpolating a constant at a call site is forbidden.

- [ ] **Step 8: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the API consumer with runtime base URL and 12s timeouts"
```

---

### Task 7: Daemon reachability as NetworkStatus

**Files:**
- Create: `packages/mobile/lib/core/helpers/network/network_status.dart`
- Test: `packages/mobile/test/core/helpers/network_status_test.dart`

**Interfaces:**
- Consumes: `ServerConfigStore` (Task 5), `ApiConsumer` (Task 6).
- Produces: `abstract class NetworkStatus { Future<bool> get isConnected; }` and `NetworkStatusImp(ApiConsumer, ServerConfigSource)`.

This is the second deliberate deviation. `dont_say` uses `internet_connection_checker_plus`, which probes the public internet. Operator's daemon lives on the LAN or Tailscale, so a phone with no internet can still reach it — gating repositories on public connectivity would fail every call on an offline LAN. Reachability means "the daemon answers", not "the internet is up".

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/helpers/network_status_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _StubSource implements ServerConfigSource {
  _StubSource(this.current);

  @override
  final ServerConfig? current;
}

const _config = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

void main() {
  late _MockApiConsumer api;

  setUp(() => api = _MockApiConsumer());

  test('is disconnected when nothing is paired', () async {
    final status = NetworkStatusImp(api, _StubSource(null));
    expect(await status.isConnected, isFalse);
    verifyNever(() => api.get(any()));
  });

  test('is connected when the daemon answers the ping', () async {
    when(() => api.get(any())).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: '/'), statusCode: 200),
    );

    final status = NetworkStatusImp(api, _StubSource(_config));
    expect(await status.isConnected, isTrue);
  });

  test('is disconnected when the daemon is unreachable', () async {
    when(() => api.get(any())).thenThrow(
      DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionTimeout),
    );

    final status = NetworkStatusImp(api, _StubSource(_config));
    expect(await status.isConnected, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/helpers/network_status_test.dart`
Expected: FAIL — `network_status.dart` does not exist.

- [ ] **Step 3: Implement it**

`packages/mobile/lib/core/helpers/network/network_status.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';

abstract class NetworkStatus {
  Future<bool> get isConnected;
}

class NetworkStatusImp implements NetworkStatus {
  NetworkStatusImp(this._apiConsumer, this._configSource);

  final ApiConsumer _apiConsumer;
  final ServerConfigSource _configSource;

  @override
  Future<bool> get isConnected async {
    if (_configSource.current == null) return false;
    try {
      await _apiConsumer.get(EndPoints.projects);
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/helpers/network_status_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): gate repositories on daemon reachability, not public internet"
```

---

### Task 8: Operator's error envelope

**Files:**
- Create: `packages/mobile/lib/core/error_handling/dio_error_handler/dio_error_handler.dart`
- Test: `packages/mobile/test/core/error_handling/dio_error_handler_test.dart`

**Interfaces:**
- Consumes: `ServerFailure` (Task 3).
- Produces: `ServerFailure handleDioError(DioException error)` returning a failure whose `message` is the daemon's `message`, `apiStatus` is its `code`, and whose `validationErrors` carries `requestId`.

The daemon returns a locked envelope: `{error, code, message, requestId}`. `code` is machine-readable (e.g. `SESSION_AWAITING_DECISION`) and the UI branches on it; `requestId` correlates the failure with daemon logs. Flattening either into a string is a regression.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/error_handling/dio_error_handler_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';

DioException _exception(Map<String, dynamic> body, int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/sessions'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/v1/sessions'),
        statusCode: statusCode,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('handleDioError', () {
    test('keeps the daemon code and requestId', () {
      final failure = handleDioError(
        _exception({
          'error': 'conflict',
          'code': 'SESSION_AWAITING_DECISION',
          'message': 'Session is awaiting a decision',
          'requestId': 'req_01H',
        }, 409),
      );

      expect(failure.message, 'Session is awaiting a decision');
      expect(failure.apiStatus, 'SESSION_AWAITING_DECISION');
      expect(failure.statusCode, 409);
      expect(failure.validationErrors, {'requestId': 'req_01H'});
    });

    test('falls back to error when message is absent', () {
      final failure = handleDioError(_exception({'error': 'bad request'}, 400));

      expect(failure.message, 'bad request');
      expect(failure.apiStatus, isNull);
    });

    test('maps a timeout to a network failure', () {
      final failure = handleDioError(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/sessions'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(failure.statusCode, StatusCode.noInternetConnection);
    });
  });
}
```



- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/error_handling/dio_error_handler_test.dart`
Expected: FAIL — `handleDioError` is undefined.

- [ ] **Step 3: Implement it**

`packages/mobile/lib/core/error_handling/dio_error_handler/dio_error_handler.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

ServerFailure<Map<String, dynamic>> handleDioError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return ServerFailure<Map<String, dynamic>>(
        error: error,
        message: 'Could not reach your Operator server',
        statusCode: StatusCode.noInternetConnection,
      );
    default:
      break;
  }

  final body = error.response?.data;
  if (body is! Map<String, dynamic>) {
    return ServerFailure<Map<String, dynamic>>(
      error: error,
      message: error.message ?? 'Request failed',
      statusCode: error.response?.statusCode,
    );
  }

  final requestId = body['requestId'];
  return ServerFailure<Map<String, dynamic>>(
    error: error,
    message: (body['message'] ?? body['error'] ?? 'Request failed') as String,
    statusCode: error.response?.statusCode,
    apiStatus: body['code'] as String?,
    validationErrors: requestId is String ? {'requestId': requestId} : null,
  );
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/error_handling/dio_error_handler_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Wire it into DioConsumer**

In `dio_consumer.dart`, catch `DioException` in each verb and `throw handleDioError(error)` so a `Failure` reaches repositories, per the conventions.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): map the daemon error envelope onto ServerFailure"
```

---

### Task 9: AppSkin and the two palettes

**Files:**
- Create: `packages/mobile/lib/core/app_themes/colors/app_skin.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/dark_skin.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/light_skin.dart`
- Test: `packages/mobile/test/core/app_themes/skin_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `abstract class AppSkin` with `ThemeMode get themeMode` and 31 `Color` getters; `const DarkSkin()`; `const LightSkin()`.

Token values are ported from `packages/mobile_rn/lib/theme.ts`. `rgba(r,g,b,a)` becomes 8-digit ARGB: alpha byte = `round(a * 255)` in hex, then RGB. For example `rgba(255,255,255,0.04)` → `Color(0x0AFFFFFF)` (0.04 × 255 = 10.2 → `0x0A`).

**Dark palette:**

| Token | theme.ts | Dart |
|---|---|---|
| bgBase | `#0a0b0d` | `Color(0xFF0A0B0D)` |
| bgSide | `#08090b` | `Color(0xFF08090B)` |
| bgColumn | `#0e0f12` | `Color(0xFF0E0F12)` |
| bgSurface | `#121317` | `Color(0xFF121317)` |
| bgElevated | `#15171b` | `Color(0xFF15171B)` |
| bgElevatedHover | `#191b20` | `Color(0xFF191B20)` |
| bgSubtle | `rgba(255,255,255,0.04)` | `Color(0x0AFFFFFF)` |
| textPrimary | `#f4f5f7` | `Color(0xFFF4F5F7)` |
| textSecondary | `#9ba1aa` | `Color(0xFF9BA1AA)` |
| textTertiary | `#646a73` | `Color(0xFF646A73)` |
| textFaint | `#444951` | `Color(0xFF444951)` |
| borderSubtle | `rgba(255,255,255,0.06)` | `Color(0x0FFFFFFF)` |
| borderDefault | `rgba(255,255,255,0.10)` | `Color(0x1AFFFFFF)` |
| borderStrong | `rgba(255,255,255,0.16)` | `Color(0x29FFFFFF)` |
| blue | `#4d8dff` | `Color(0xFF4D8DFF)` |
| orange | `#f59f4c` | `Color(0xFFF59F4C)` |
| amber | `#e8c14a` | `Color(0xFFE8C14A)` |
| red | `#ef6b6b` | `Color(0xFFEF6B6B)` |
| purple | `#a371f7` | `Color(0xFFA371F7)` |
| green | `#74b98a` | `Color(0xFF74B98A)` |
| tintBlue | `rgba(77,141,255,0.14)` | `Color(0x244D8DFF)` |
| tintOrange | `rgba(245,159,76,0.14)` | `Color(0x24F59F4C)` |
| tintAmber | `rgba(232,193,74,0.14)` | `Color(0x24E8C14A)` |
| tintRed | `rgba(239,107,107,0.14)` | `Color(0x24EF6B6B)` |
| tintGreen | `rgba(116,185,138,0.14)` | `Color(0x2474B98A)` |
| tintPurple | `rgba(163,113,247,0.14)` | `Color(0x24A371F7)` |
| onAccent | `#06101f` | `Color(0xFF06101F)` |
| scrim | `rgba(0,0,0,0.6)` | `Color(0x99000000)` |
| accent | `#4d8dff` | `Color(0xFF4D8DFF)` |
| accentTint | `rgba(77,141,255,0.14)` | `Color(0x244D8DFF)` |
| attention | `#e8c14a` | `Color(0xFFE8C14A)` |

**Light palette:**

| Token | theme.ts | Dart |
|---|---|---|
| bgBase | `#f2f2f7` | `Color(0xFFF2F2F7)` |
| bgSide | `#eceef2` | `Color(0xFFECEEF2)` |
| bgColumn | `#f7f7fa` | `Color(0xFFF7F7FA)` |
| bgSurface | `#ffffff` | `Color(0xFFFFFFFF)` |
| bgElevated | `#ffffff` | `Color(0xFFFFFFFF)` |
| bgElevatedHover | `#ececf0` | `Color(0xFFECECF0)` |
| bgSubtle | `rgba(0,0,0,0.04)` | `Color(0x0A000000)` |
| textPrimary | `#1a1a1a` | `Color(0xFF1A1A1A)` |
| textSecondary | `#666666` | `Color(0xFF666666)` |
| textTertiary | `#8e8e93` | `Color(0xFF8E8E93)` |
| textFaint | `#b8b8bd` | `Color(0xFFB8B8BD)` |
| borderSubtle | `rgba(0,0,0,0.06)` | `Color(0x0F000000)` |
| borderDefault | `rgba(0,0,0,0.12)` | `Color(0x1F000000)` |
| borderStrong | `rgba(0,0,0,0.20)` | `Color(0x33000000)` |
| blue | `#2563eb` | `Color(0xFF2563EB)` |
| orange | `#b45309` | `Color(0xFFB45309)` |
| amber | `#946200` | `Color(0xFF946200)` |
| red | `#c0392b` | `Color(0xFFC0392B)` |
| purple | `#7c3aed` | `Color(0xFF7C3AED)` |
| green | `#2f7d32` | `Color(0xFF2F7D32)` |
| tintBlue | `rgba(37,99,235,0.12)` | `Color(0x1F2563EB)` |
| tintOrange | `rgba(180,83,9,0.12)` | `Color(0x1FB45309)` |
| tintAmber | `rgba(148,98,0,0.12)` | `Color(0x1F946200)` |
| tintRed | `rgba(192,57,43,0.12)` | `Color(0x1FC0392B)` |
| tintGreen | `rgba(47,125,50,0.12)` | `Color(0x1F2F7D32)` |
| tintPurple | `rgba(124,58,237,0.12)` | `Color(0x1F7C3AED)` |
| onAccent | `#ffffff` | `Color(0xFFFFFFFF)` |
| scrim | `rgba(0,0,0,0.45)` | `Color(0x73000000)` |
| accent | `#2563eb` | `Color(0xFF2563EB)` |
| accentTint | `rgba(37,99,235,0.12)` | `Color(0x1F2563EB)` |
| attention | `#946200` | `Color(0xFF946200)` |

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/app_themes/skin_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

void main() {
  group('DarkSkin', () {
    const skin = DarkSkin();

    test('drives dark mode', () => expect(skin.themeMode, ThemeMode.dark));

    test('carries the opaque surface tokens', () {
      expect(skin.bgBase, const Color(0xFF0A0B0D));
      expect(skin.bgSurface, const Color(0xFF121317));
      expect(skin.textPrimary, const Color(0xFFF4F5F7));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0AFFFFFF));
      expect(skin.borderDefault, const Color(0x1AFFFFFF));
      expect(skin.scrim, const Color(0x99000000));
      expect(skin.tintBlue, const Color(0x244D8DFF));
    });

    test('keeps the state hues distinct', () {
      expect(skin.blue, const Color(0xFF4D8DFF));
      expect(skin.orange, const Color(0xFFF59F4C));
      expect(skin.amber, const Color(0xFFE8C14A));
      expect(skin.red, const Color(0xFFEF6B6B));
      expect(skin.green, const Color(0xFF74B98A));
      expect(skin.purple, const Color(0xFFA371F7));
    });
  });

  group('LightSkin', () {
    const skin = LightSkin();

    test('drives light mode', () => expect(skin.themeMode, ThemeMode.light));

    test('darkens the state hues rather than reusing them', () {
      expect(skin.blue, const Color(0xFF2563EB));
      expect(skin.green, const Color(0xFF2F7D32));
      expect(skin.red, const Color(0xFFC0392B));
    });

    test('converts rgba tokens to ARGB', () {
      expect(skin.bgSubtle, const Color(0x0A000000));
      expect(skin.borderStrong, const Color(0x33000000));
      expect(skin.scrim, const Color(0x73000000));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/app_themes/skin_test.dart`
Expected: FAIL — the skin files do not exist.

- [ ] **Step 3: Implement AppSkin**

`app_skin.dart` declares `abstract class AppSkin { const AppSkin(); ThemeMode get themeMode; ... }` with one `Color get` per token in the tables above, in the table's order. Mirror `dont_say`'s doc-comment-per-token style, describing what each token paints in *this* app. The six state hues carry meaning and their doc comments must record it: blue = the conductor, orange = a working agent, amber = needs your input, red = failing, green = passed, purple = merged.

Do not carry over `dont_say`'s domain tokens (`categoryFood`, `income`, `heroGradient`, and the rest).

- [ ] **Step 4: Implement both palettes**

`dark_skin.dart` and `light_skin.dart` each declare `class DarkSkin extends AppSkin { const DarkSkin(); @override ... }` with the exact ARGB values from the tables.

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/core/app_themes/skin_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): port the Operator skin to Flutter"
```

---

### Task 10: AppTextStyle

**Files:**
- Create: `packages/mobile/lib/core/app_themes/text_style/font_weight_helper.dart`
- Create: `packages/mobile/lib/core/app_themes/text_style/app_text_style.dart`
- Test: `packages/mobile/test/core/app_themes/app_text_style_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `sealed class AppTextStyle` exposing `style9Regular` … `style17Bold`, `style19SemiBold`, `style24Bold`, `style26Bold`, `style32Bold`, and `mono10Regular` … `mono13Bold`.

Sizes come from measured usage in the RN app: 11 (57 uses), 12 (40), 13 (39), 10 (29), 15 (21), 17 (10), 14 (10), 9 (8), 8 (6), 16 (5), with one-offs at 19, 24, 26, 32. Weights: 700, 600, 800, 500.

`FONT_MONO` in `theme.ts` is `'JetBrains Mono, Menlo, ui-monospace, monospace'`, but the RN app has no `expo-font` dependency and therefore never bundles JetBrains Mono — on device it already renders the platform monospace. Parity is `fontFamilyFallback: ['Menlo', 'Courier New', 'monospace']` with no bundled family.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/app_themes/app_text_style_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';

void main() {
  test('exposes the dense sizes the app actually uses', () {
    expect(AppTextStyle.style11Regular.fontWeight, FontWeight.w400);
    expect(AppTextStyle.style11Bold.fontWeight, FontWeight.w700);
    expect(AppTextStyle.style12SemiBold.fontWeight, FontWeight.w600);
    expect(AppTextStyle.style13Medium.fontWeight, FontWeight.w500);
  });

  test('mono styles fall back to platform monospace', () {
    expect(AppTextStyle.mono11Bold.fontFamilyFallback, contains('monospace'));
    expect(AppTextStyle.mono11Bold.fontFamily, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/app_themes/app_text_style_test.dart`
Expected: FAIL — `AppTextStyle` is undefined.

- [ ] **Step 3: Implement FontWeightHelper**

Copy `app_themes/text_style/font_weight_helper.dart` from `dont_say` verbatim, rewriting the import prefix.

- [ ] **Step 4: Implement AppTextStyle**

`app_text_style.dart` declares `sealed class AppTextStyle` with `static TextStyle get styleNNWeight => TextStyle(fontSize: NN.spMin, fontWeight: FontWeightHelper.weight)` for every size 9–17 in Regular/Medium/SemiBold/Bold, plus `style19SemiBold`, `style24Bold`, `style26Bold`, `style32Bold`. Mono getters add `fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace']` for sizes 10–13 in Regular/Bold.

`.spMin` is used **here only** — feature code never imports `flutter_screenutil`.

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/core/app_themes/app_text_style_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add AppTextStyle from measured RN usage"
```

---

### Task 11: SkinScope, SkinCubit, and ThemeData

**Files:**
- Create: `packages/mobile/lib/core/app_themes/colors/skin_scope.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/logic/skin_cubit.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/logic/skin_state.dart`
- Create: `packages/mobile/lib/core/app_themes/themes/app_themes.dart`
- Create: `packages/mobile/lib/core/helpers/cache/cache_helper.dart`
- Create: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Test: `packages/mobile/test/core/app_themes/skin_cubit_test.dart`

**Interfaces:**
- Consumes: `AppSkin`, `DarkSkin`, `LightSkin` (Task 9); `AppTextStyle` (Task 10).
- Produces: `SkinScope` + `context.skin`; `SkinCubit` with `AppSkin skin` and `void setSkin(AppSkin)`; `sealed class SkinState` with `SkinInitialState` and `SkinChangedState`; `AppThemes.fromSkin(AppSkin) → ThemeData`.

- [ ] **Step 1: Copy the mechanism**

Copy from `dont_say`, rewriting import prefixes: `colors/skin_scope.dart`, `colors/logic/skin_cubit.dart`, `colors/logic/skin_state.dart`, `helpers/cache/cache_helper.dart`, `helpers/cache/cache_keys.dart`. Rename any state variant lacking the `State` suffix. Keep the three-mode behavior: saved `dark` → `DarkSkin`, saved `system` → resolve from `platformBrightness`, otherwise `LightSkin`.

- [ ] **Step 2: Write the failing test**

`packages/mobile/test/core/app_themes/skin_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  blocTest<SkinCubit, SkinState>(
    'switches from light to dark and keeps the new skin',
    build: SkinCubit.new,
    act: (cubit) => cubit.setSkin(const DarkSkin()),
    verify: (cubit) {
      expect(cubit.skin, isA<DarkSkin>());
      expect(cubit.skin.themeMode, ThemeMode.dark);
    },
  );

  blocTest<SkinCubit, SkinState>(
    'starts on the light skin with no saved preference',
    build: SkinCubit.new,
    verify: (cubit) => expect(cubit.skin, isA<LightSkin>()),
  );
}
```

Adjust `build:` if `SkinCubit`'s constructor takes a cache dependency after the copy.

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/core/app_themes/skin_cubit_test.dart`
Expected: FAIL until the copied files compile against the ported skins.

- [ ] **Step 4: Implement AppThemes.fromSkin**

Copy `app_themes/themes/app_themes.dart` from `dont_say` and replace every `dont_say` token reference with an Operator one: `scaffoldBackgroundColor: skin.bgBase`, `appBarTheme.backgroundColor: skin.bgSurface`, `titleTextStyle: AppTextStyle.style17SemiBold.copyWith(color: skin.textPrimary)`, `textSelectionTheme.cursorColor: skin.accent`, `selectionColor: skin.accentTint`. Drop `fontFamily`/`fontFamilyFallback` — this app bundles no custom font.

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/core/app_themes/skin_cubit_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): wire the skin scope, cubit, and ThemeData"
```

---

### Task 12: Core widgets

**Files:**
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_text.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_scaffold.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/global_appbar.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/space_widgets.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/primary_button.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_container.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_ink_well.dart`
- Create: `packages/mobile/lib/core/widgets/loading_widget/app_loader.dart`
- Create: `packages/mobile/lib/core/widgets/failure_widgets/app_error_widget.dart`
- Test: `packages/mobile/test/core/widgets/core_widgets_test.dart`

**Interfaces:**
- Consumes: `context.skin` (Task 11), `AppTextStyle` (Task 10).
- Produces: `AppText`, `AppScaffold`, `GlobalAppbar.main` / `GlobalAppbar.sub`, `VerticalSpace(double)`, `HorizontalSpace(double)`, `PrimaryButton` (with `.expand`), `AppContainer`, `AppInkWell`, `AppLoader`, `AppErrorWidget`.

Port only this set. `dont_say`'s `widgets/say/*` are its own domain; later milestones add widgets when a feature needs one.

- [ ] **Step 1: Copy and re-skin**

Copy each listed file from `dont_say`, rewrite import prefixes, and replace every color reference with an Operator token: surfaces → `skin.bgSurface` / `skin.bgElevated`, page background → `skin.bgBase`, text → `skin.textPrimary` / `skin.textSecondary` / `skin.textTertiary`, outlines → `skin.borderSubtle` / `skin.borderDefault`, primary action → `skin.accent` with `skin.onAccent` for its label, loader → `skin.accent`, error → `skin.red`.

- [ ] **Step 2: Write the failing test**

`packages/mobile/test/core/widgets/core_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

void main() {
  testWidgets('AppText renders its string', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: const Scaffold(body: AppText('Sessions')),
        ),
      ),
    );

    expect(find.text('Sessions'), findsOneWidget);
  });

  testWidgets('AppScaffold paints the base background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: const AppScaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF0A0B0D));
  });
}
```

`AppText` takes its string positionally (`AppText(this.text, {this.style, ...})`) and `AppScaffold`
takes `{this.appBar, required this.body, ...}` — both match `dont_say`'s signatures, which the port
keeps unchanged.

- [ ] **Step 3: Run it to verify it fails, then passes**

Run: `flutter test test/core/widgets/core_widgets_test.dart`
Expected: FAIL before the widgets exist, PASS after Step 1's port compiles.

- [ ] **Step 4: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): port the core widget set onto the Operator skin"
```

---

### Task 13: DI, routing, and bootstrap

**Files:**
- Create: `packages/mobile/lib/core/utils/service_locator.dart`
- Create: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Create: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/main.dart`
- Test: `packages/mobile/test/core/utils/service_locator_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 3–12.
- Produces: `final sl = GetIt.instance;`, `ServiceLocator.init()`, `sealed class RoutesStrings`, `AppRouter.generateRoute(RouteSettings) → Route<dynamic>`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/utils/service_locator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    await ServiceLocator.init();
  });

  test('resolves the core singletons', () {
    expect(sl<ApiConsumer>(), isA<ApiConsumer>());
    expect(sl<ServerConfigStore>(), isA<ServerConfigStore>());
    expect(sl<NetworkStatus>(), isA<NetworkStatus>());
  });

  test('returns the same instance for lazy singletons', () {
    expect(identical(sl<ApiConsumer>(), sl<ApiConsumer>()), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/utils/service_locator_test.dart`
Expected: FAIL — `service_locator.dart` does not exist.

- [ ] **Step 3: Implement the service locator**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sl = GetIt.instance;

class ServiceLocator {
  static Future<void> init() async {
    await _coreSetup();
  }

  static Future<void> _coreSetup() async {
    final preferences = await SharedPreferences.getInstance();
    sl.registerLazySingleton<SharedPreferences>(() => preferences);
    sl.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());

    sl.registerLazySingleton<ServerConfigStore>(
      () => ServerConfigStore(sl<FlutterSecureStorage>(), sl<SharedPreferences>()),
    );
    sl.registerLazySingleton<ApiConsumer>(() => DioConsumer(sl<ServerConfigStore>()));
    sl.registerLazySingleton<NetworkStatus>(
      () => NetworkStatusImp(sl<ApiConsumer>(), sl<ServerConfigStore>()),
    );
  }
}
```

Each later feature adds its own `_<feature>FeatureSetup()` called from `init()`. Never inline registrations into `init()`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/utils/service_locator_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Add routing**

`routes_strings.dart`:

```dart
sealed class RoutesStrings {
  static const String splash = '/';
}
```

`app_router.dart` exposes `static Route<dynamic> generateRoute(RouteSettings settings)` with a `switch` on `settings.name`, a `splash` case returning a `MaterialPageRoute` to a placeholder `AppScaffold`, and a default case returning a route to `AppErrorWidget`. `BlocProvider` belongs in these case bodies, never inside screen widgets.

- [ ] **Step 6: Wire main.dart**

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/themes/app_themes.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await ServiceLocator.init();
  await sl<ServerConfigStore>().load();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const OperatorApp(),
    ),
  );
}

class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => SkinCubit(),
        child: BlocBuilder<SkinCubit, SkinState>(
          buildWhen: (previous, current) => current is SkinChangedState,
          builder: (context, state) {
            final skin = context.read<SkinCubit>().skin;
            return SkinScope(
              skin: skin,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                minTextAdapt: true,
                builder: (context, child) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppThemes.fromSkin(skin),
                  themeMode: skin.themeMode,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  initialRoute: RoutesStrings.splash,
                  onGenerateRoute: AppRouter.generateRoute,
                ),
              ),
            );
          },
        ),
      );
}
```

Create `packages/mobile/assets/translations/en.json` and `ar.json` containing `{}`, and declare `assets/translations/` under `flutter: assets:` in `pubspec.yaml`.

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): wire DI, routing, and app bootstrap"
```

---

### Task 14: Close out M0

**Files:**
- Modify: `packages/mobile/README.md`
- Modify: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

**Interfaces:**
- Consumes: Tasks 1–13.
- Produces: an M0 the next milestone can build on.

- [ ] **Step 1: Run the full gate**

```bash
cd packages/mobile
flutter analyze
flutter test
```
Expected: analyze clean; all tests from Tasks 3–13 passing.

- [ ] **Step 2: Confirm no feature code leaked in**

Run: `ls packages/mobile/lib` — expected: `core` and `main.dart` only. M0 ships no features.

- [ ] **Step 3: Confirm the screenutil rule holds**

Run:
```bash
grep -rn "flutter_screenutil" packages/mobile/lib --include="*.dart" | grep -v app_text_style.dart | grep -v main.dart
```
Expected: no output.

- [ ] **Step 4: Write the README**

`packages/mobile/README.md`: what the app is, that `packages/mobile_rn` is the frozen RN reference until M6, how to run `flutter analyze` and `flutter test`, and that the app is not run or built as part of implementation.

- [ ] **Step 5: Mark M0 done in the spec**

Add `— done <date>` to the M0 row of the build-order table.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs(mobile): close out M0"
```

---

## What M0 deliberately does not include

- Any feature under `lib/feature/` — M1 delivers the first (pairing → sessions → Kanban).
- `MuxClient` — M1 needs it for live session patches; building it now would be untested speculation.
- Telemetry, push, voice, preview, terminal — M4 and M5.
- Widgets beyond the core set in Task 12. Features add them as they need them.
- The spec's **sequential auth probing** rule. It constrains the sessions repository, which does
  not exist until M1; M1's plan owns that requirement and the mirrored test that pins the call
  order.
