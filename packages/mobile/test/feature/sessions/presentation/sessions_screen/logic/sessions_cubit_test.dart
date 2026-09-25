import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _StubConfigSource implements ServerConfigSource {
  final controller = StreamController<ServerConfig?>.broadcast(sync: true);

  @override
  ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => controller.stream;

  void set(ServerConfig? next) {
    current = next;
    controller.add(next);
  }
}

const _configB = ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'pw');

class _Signals implements ConnectionSignals {
  _Signals(this.retries);

  @override
  final Stream<void> retries;

  @override
  bool authFailed = false;
}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _StubConfigSource source;
  late StreamController<void> changesController;
  late StreamController<MuxStatus> statusController;
  var streamReady = false;

  setUp(() async {
    AppPreferences.debugLoad(const {});
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    source = _StubConfigSource();
    streamReady = false;
    changesController = StreamController<void>.broadcast();
    statusController = StreamController<MuxStatus>.broadcast();
    when(() => mux.boardChanges).thenAnswer((_) => changesController.stream);
    when(() => mux.status).thenAnswer((_) => statusController.stream);
    when(() => mux.boardStreamReady).thenAnswer((_) => streamReady);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.cachedBoard()).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await changesController.close();
    await statusController.close();
    await source.controller.close();
  });

  blocTest<SessionsCubit, SessionsState>(
    'a config change clears the board, resets to the initial state and refreshes',
    build: () {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(
          GlobalResponse(
            data: BoardSnapshot(
              sessions: [SessionModel(id: 'worker-$fetches')],
              projects: [ProjectModel(id: 'project-$fetches')],
            ),
          ),
        );
      });
      return SessionsCubit(repository, mux, source);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      expect(cubit.sessions.single.id, 'worker-1');
      source.set(_configB);
      expect(cubit.sessions, isEmpty);
      expect(cubit.projects, isEmpty);
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [
      isA<GetSessionsLoadingState>(),
      isA<GetSessionsSuccessState>(),
      isA<SessionsInitialState>(),
      isA<GetSessionsLoadingState>(),
      isA<GetSessionsSuccessState>(),
    ],
    verify: (cubit) {
      expect(cubit.sessions.single.id, 'worker-2');
      verify(() => repository.getBoard()).called(2);
    },
  );

  test('a config change resumes fetching after an auth stop', () {
    fakeAsync((async) {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        if (fetches == 1) return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
        return Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'b')])));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      expect(fetches, 1);

      source.set(_configB);
      async.flushMicrotasks();
      expect(fetches, 2);
      expect(cubit.sessions.single.id, 'b');
      async.elapse(const Duration(seconds: 30));
      expect(fetches, 3);
      cubit.close();
    });
  });

  test('a null config clears the board without fetching', () {
    fakeAsync((async) {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'a')])));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      expect(cubit.sessions, hasLength(1));

      source.set(null);
      async.flushMicrotasks();
      expect(cubit.sessions, isEmpty);
      expect(cubit.state, isA<SessionsInitialState>());
      expect(fetches, 1);
      cubit.close();
    });
  });

  test('a board fetch started before a config change does not repopulate the new board', () {
    fakeAsync((async) {
      final pending = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) {
        fetches++;
        if (fetches == 1) return pending.future;
        return Future.value(Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'b')]))));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      expect(fetches, 1);

      source.set(_configB);
      async.flushMicrotasks();
      pending.complete(Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'a')]))));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 200));
      expect(cubit.sessions.map((s) => s.id), ['b']);
      cubit.close();
    });
  });

  test('switching away from a desktop whose fetch hangs fetches the new desktop at once', () {
    fakeAsync((async) {
      final hanging = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      final third = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) {
        fetches++;
        if (fetches == 1) return hanging.future;
        if (fetches == 2) {
          return Future.value(Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'b')]))));
        }
        return third.future;
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      expect(fetches, 1);

      source.set(_configB);
      async.flushMicrotasks();
      expect(fetches, 2);
      expect(cubit.sessions.map((s) => s.id), ['b']);
      expect(cubit.state, isA<GetSessionsSuccessState>());

      unawaited(cubit.refresh());
      async.flushMicrotasks();
      expect(fetches, 3);
      hanging.complete(Result.failure(ServerFailure(error: 'x', message: 'timeout')));
      async.flushMicrotasks();
      unawaited(cubit.refresh());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(fetches, 3);
      expect(cubit.sessions.map((s) => s.id), ['b']);
      cubit.close();
    });
  });

  blocTest<SessionsCubit, SessionsState>(
    'fetches sessions on construction and connects mux',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'proj-1', status: 'working')])),
        ),
      );
      return SessionsCubit(repository, mux, source);
    },
    expect: () => [isA<GetSessionsLoadingState>(), isA<GetSessionsSuccessState>()],
    verify: (cubit) {
      expect(cubit.sessions.single.id, 'proj-1');
      verify(() => mux.connect()).called(1);
      verify(() => mux.subscribeSessions()).called(1);
    },
  );

  test('coalesces board changes and replaces workers and projects', () {
    fakeAsync((async) {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(
          GlobalResponse(
            data: BoardSnapshot(
              sessions: [SessionModel(id: 'worker-$fetches')],
              projects: [ProjectModel(id: 'project-$fetches')],
            ),
          ),
        );
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      changesController.add(null);
      changesController.add(null);
      changesController.add(null);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetches, 2);
      expect(cubit.sessions.single.id, 'worker-2');
      expect(cubit.projects.single.id, 'project-2');
      cubit.close();
    });
  });

  test('queues a refresh when a change arrives during a fetch and ignores a late result after close', () {
    fakeAsync((async) {
      final pending = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) {
        fetches++;
        if (fetches == 1) return pending.future;
        return Future.value(
          Result.success(
            GlobalResponse(
              data: const BoardSnapshot(sessions: [SessionModel(id: 'new')]),
            ),
          ),
        );
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      changesController.add(null);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetches, 1);
      pending.complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
      async.elapse(const Duration(milliseconds: 200));
      expect(fetches, 2);
      expect(cubit.sessions.single.id, 'new');
      final lateResponse = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      when(() => repository.getBoard()).thenAnswer((_) => lateResponse.future);
      unawaited(cubit.refresh());
      cubit.close();
      lateResponse.complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
      async.flushMicrotasks();
      expect(cubit.sessions.single.id, 'new');
    });
  });

  test('polls only until subscription acknowledgement and while disconnected', () {
    fakeAsync((async) {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(GlobalResponse(data: const BoardSnapshot()));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      expect(fetches, 2);
      streamReady = true;
      changesController.add(null);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetches, 3);
      async.elapse(const Duration(minutes: 2));
      expect(fetches, 3);
      streamReady = false;
      statusController.add(MuxStatus.closed);
      async.elapse(const Duration(seconds: 30));
      expect(fetches, 4);
      streamReady = true;
      statusController.add(MuxStatus.open);
      changesController.add(null);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetches, 5);
      async.elapse(const Duration(minutes: 1));
      expect(fetches, 5);
      cubit.close();
    });
  });

  test('pauses background updates and refreshes on resume', () {
    fakeAsync((async) {
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.success(GlobalResponse(data: const BoardSnapshot()));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      cubit.pauseUpdates();
      changesController.add(null);
      async.elapse(const Duration(minutes: 2));
      expect(fetches, 1);
      cubit.resumeUpdates();
      async.flushMicrotasks();
      expect(fetches, 2);
      cubit.close();
    });
  });

  test('retries a failed event refresh even while the stream remains connected', () {
    fakeAsync((async) {
      streamReady = true;
      var fetches = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        fetches++;
        if (fetches == 2) return Result.failure(ServerFailure.noNetwork());
        return Result.success(GlobalResponse(data: const BoardSnapshot()));
      });
      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      changesController.add(null);
      async.elapse(const Duration(milliseconds: 200));
      expect(cubit.state, isA<GetSessionsFailureState>());
      async.elapse(const Duration(seconds: 30));
      expect(fetches, 3);
      expect(cubit.state, isA<GetSessionsSuccessState>());
      async.elapse(const Duration(minutes: 1));
      expect(fetches, 3);
      cubit.close();
    });
  });

  blocTest<SessionsCubit, SessionsState>(
    'kill re-fetches on success',
    build: () {
      when(() => repository.getBoard()).thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.success(true));
      return SessionsCubit(repository, mux, source);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    verify: (_) => verify(() => repository.getBoard()).called(2),
  );

  blocTest<SessionsCubit, SessionsState>(
    'kill emits KillFailureState without re-fetching on failure',
    build: () {
      when(() => repository.getBoard()).thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.failure(ServerFailure.noNetwork()));
      return SessionsCubit(repository, mux, source);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    skip: 2,
    expect: () => [isA<KillFailureState>()],
    verify: (_) => verify(() => repository.getBoard()).called(1),
  );

  test('stops polling after an auth failure instead of retrying on the fallback timer', () {
    fakeAsync((async) {
      var callCount = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        callCount++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });

      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      expect(callCount, 1);

      async.elapse(const Duration(seconds: 60));
      expect(callCount, 1, reason: 'polling stopped after the auth failure');

      cubit.close();
    });
  });

  test('refresh resumes polling after an auth failure instead of staying stuck forever', () {
    fakeAsync((async) {
      var callCount = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
        }
        return Result.success(
          GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'proj-1', status: 'working')])),
        );
      });

      final cubit = SessionsCubit(repository, mux, source);
      async.flushMicrotasks();
      expect(callCount, 1);
      expect(cubit.state, isA<GetSessionsFailureState>());

      async.elapse(const Duration(seconds: 60));
      expect(callCount, 1, reason: 'polling stays stopped until something calls refresh');

      unawaited(cubit.refresh());
      async.flushMicrotasks();
      expect(callCount, 2);
      expect(cubit.state, isA<GetSessionsSuccessState>());
      expect(cubit.sessions.single.id, 'proj-1');

      async.elapse(const Duration(seconds: 30));
      expect(callCount, 3, reason: 'the poll timer was re-armed by refresh');

      cubit.close();
    });
  });

  blocTest<SessionsCubit, SessionsState>(
    'exposes projects from one board fetch',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const BoardSnapshot(
              sessions: [SessionModel(id: 'proj-1', projectId: 'p')],
              projects: [ProjectModel(id: 'p', name: 'My App')],
            ),
          ),
        ),
      );
      return SessionsCubit(repository, mux, source);
    },
    act: (cubit) => Future<void>.delayed(Duration.zero),
    verify: (cubit) {
      expect(cubit.projects.single.name, 'My App');
      expect(cubit.sessions.single.id, 'proj-1');
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'scopes visibleSessions to the active project and repaints on the change',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const BoardSnapshot(
              sessions: [
                SessionModel(id: 'a', projectId: 'p1'),
                SessionModel(id: 'b', projectId: 'p2'),
              ],
            ),
          ),
        ),
      );
      return SessionsCubit(repository, mux, source);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      expect(cubit.visibleSessions.map((s) => s.id), ['a', 'b']);
      cubit.setActiveProject('p2');
    },
    expect: () => [
      isA<GetSessionsLoadingState>(),
      isA<GetSessionsSuccessState>().having((s) => s.revision, 'revision', 1),
      isA<GetSessionsSuccessState>().having((s) => s.revision, 'revision', 2),
    ],
    verify: (cubit) {
      expect(cubit.activeProjectId, 'p2');
      expect(cubit.visibleSessions.map((s) => s.id), ['b']);
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'defaults to every project',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
      );
      return SessionsCubit(repository, mux, source);
    },
    verify: (cubit) => expect(cubit.activeProjectId, kAllProjects),
  );

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
      expect(cubit.accountLabels, isEmpty);
      expect(cubit.boardIsCached, isFalse);
      await cubit.close();
    });

    test('a cache read that lands after a failed fetch loads the rows and keeps the failure current', () async {
      final read = Completer<Replicated<BoardSnapshot>?>();
      final failure = ServerFailure(error: 'unauthorized', message: 'unauthorized', statusCode: 401);
      when(() => repository.cachedBoard()).thenAnswer((_) => read.future);
      when(() => repository.getBoard()).thenAnswer((_) async => Result.failure(failure));

      final cubit = SessionsCubit(repository, mux, source);
      final states = <SessionsState>[];
      final sub = cubit.stream.listen(states.add);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<GetSessionsFailureState>());

      final settled = cubit.stream.firstWhere(
        (state) => (state is GetSessionsSuccessState && !state.fromCache) || state is GetSessionsFailureState,
      );
      read.complete(
        Replicated(
          value: const BoardSnapshot(
            sessions: [SessionModel(id: 'cached')],
            accountLabels: {'default': 'Default'},
          ),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );

      expect(await settled.timeout(const Duration(seconds: 1)), isA<GetSessionsFailureState>());
      expect(cubit.state, GetSessionsFailureState(failure));
      expect(states.last, GetSessionsFailureState(failure));
      expect(cubit.sessions.single.id, 'cached');
      expect(cubit.accountLabels, {'default': 'Default'});
      expect(cubit.boardIsCached, isTrue);
      expect(cubit.boardFetchedAt, DateTime.utc(2026, 9, 25, 8));
      await sub.cancel();
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

    test('a retry landing while a resume fetch is in flight does not fetch again', () {
      fakeAsync((async) {
        var fetches = 0;
        final pending = <Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>>[];
        when(() => repository.getBoard()).thenAnswer((_) {
          fetches++;
          final completer = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
          pending.add(completer);
          return completer.future;
        });
        final cubit = SessionsCubit(repository, mux, source, connection: signals);
        async.flushMicrotasks();
        pending.removeAt(0).complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
        async.flushMicrotasks();
        cubit.pauseUpdates();

        cubit.resumeUpdates();
        retries.add(null);
        async.flushMicrotasks();
        pending.removeAt(0).complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
        async.elapse(const Duration(seconds: 1));

        expect(fetches, 2);
        cubit.close();
        async.flushMicrotasks();
      });
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
}
