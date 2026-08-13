import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late StreamController<List<SessionPatch>> patchesController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    patchesController = StreamController<List<SessionPatch>>.broadcast();
    when(() => mux.sessionPatches).thenAnswer((_) => patchesController.stream);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
  });

  tearDown(() => patchesController.close());

  blocTest<SessionsCubit, SessionsState>(
    'fetches sessions on construction and connects mux',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'proj-1', status: 'working')])),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    expect: () => [isA<GetSessionsLoadingState>(), isA<GetSessionsSuccessState>()],
    verify: (cubit) {
      expect(cubit.sessions.single.id, 'proj-1');
      verify(() => mux.connect()).called(1);
      verify(() => mux.subscribeSessions()).called(1);
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'merges a mux patch into the held sessions',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'proj-1', status: 'working')])),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      patchesController.add([
        const SessionPatch(id: 'proj-1', status: 'needs_input', activity: 'blocked', attentionLevel: 'respond', lastActivityAt: 't2'),
      ]);
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.sessions.single.status, 'needs_input');
      expect(cubit.sessions.single.updatedAt, 't2');
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'emits a fresh success state for a mux patch so the board repaints',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'proj-1', status: 'working')])),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      patchesController.add([
        const SessionPatch(id: 'proj-1', status: 'needs_input', activity: 'blocked', attentionLevel: 'respond', lastActivityAt: 't2'),
      ]);
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [
      isA<GetSessionsLoadingState>(),
      isA<GetSessionsSuccessState>().having((state) => state.revision, 'revision', 1),
      isA<GetSessionsSuccessState>().having((state) => state.revision, 'revision', 2),
    ],
  );

  blocTest<SessionsCubit, SessionsState>(
    'kill re-fetches on success',
    build: () {
      when(() => repository.getBoard()).thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.success(true));
      return SessionsCubit(repository, mux);
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
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    skip: 2,
    expect: () => [isA<KillFailureState>()],
    verify: (_) => verify(() => repository.getBoard()).called(1),
  );

  test('stops polling after an auth failure instead of retrying every 8s', () {
    fakeAsync((async) {
      var callCount = 0;
      when(() => repository.getBoard()).thenAnswer((_) async {
        callCount++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });

      final cubit = SessionsCubit(repository, mux);
      async.flushMicrotasks();
      expect(callCount, 1);

      async.elapse(const Duration(seconds: 24));
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

      final cubit = SessionsCubit(repository, mux);
      async.flushMicrotasks();
      expect(callCount, 1);
      expect(cubit.state, isA<GetSessionsFailureState>());

      async.elapse(const Duration(seconds: 24));
      expect(callCount, 1, reason: 'polling stays stopped until something calls refresh');

      unawaited(cubit.refresh());
      async.flushMicrotasks();
      expect(callCount, 2);
      expect(cubit.state, isA<GetSessionsSuccessState>());
      expect(cubit.sessions.single.id, 'proj-1');

      async.elapse(const Duration(seconds: 8));
      expect(callCount, 3, reason: 'the poll timer was re-armed by refresh');

      cubit.close();
    });
  });

  blocTest<SessionsCubit, SessionsState>(
    'exposes projects and orchestrators from one board fetch',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const BoardSnapshot(
              sessions: [SessionModel(id: 'proj-1', projectId: 'p')],
              orchestrators: [OrchestratorModel(id: 'o1', projectId: 'p')],
              projects: [ProjectModel(id: 'p', name: 'My App')],
            ),
          ),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) => Future<void>.delayed(Duration.zero),
    verify: (cubit) {
      expect(cubit.projects.single.name, 'My App');
      expect(cubit.orchestrators.single.id, 'o1');
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
      return SessionsCubit(repository, mux);
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
      return SessionsCubit(repository, mux);
    },
    verify: (cubit) => expect(cubit.activeProjectId, kAllProjects),
  );
}
