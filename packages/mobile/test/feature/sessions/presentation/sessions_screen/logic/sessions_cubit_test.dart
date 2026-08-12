import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late StreamController<List<SessionPatch>> patchesController;

  setUp(() {
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
      when(() => repository.getSessions()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: [SessionModel(id: 'proj-1', status: 'working')])),
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
      when(() => repository.getSessions()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: [SessionModel(id: 'proj-1', status: 'working')])),
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
      when(() => repository.getSessions()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: [SessionModel(id: 'proj-1', status: 'working')])),
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
      when(() => repository.getSessions()).thenAnswer((_) async => Result.success(GlobalResponse(data: [])));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.success(true));
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    verify: (_) => verify(() => repository.getSessions()).called(2),
  );

  blocTest<SessionsCubit, SessionsState>(
    'kill emits KillFailureState without re-fetching on failure',
    build: () {
      when(() => repository.getSessions()).thenAnswer((_) async => Result.success(GlobalResponse(data: [])));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.failure(ServerFailure.noNetwork()));
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    skip: 2,
    expect: () => [isA<KillFailureState>()],
    verify: (_) => verify(() => repository.getSessions()).called(1),
  );

  test('stops polling after an auth failure instead of retrying every 8s', () {
    fakeAsync((async) {
      var callCount = 0;
      when(() => repository.getSessions()).thenAnswer((_) async {
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
}
