import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';

class MockSessionControlRepository extends Mock implements SessionControlRepository {}

BlockEventModel _event({String? kind}) => BlockEventModel(kind: kind);

void main() {
  late MockSessionControlRepository repo;
  late SessionCommandCubit cubit;

  setUpAll(() {
    registerFallbackValue(const SessionCommandParams(command: 'stop'));
    registerFallbackValue(const SessionDecisionParams(requestId: 'i', behavior: 'allow'));
    registerFallbackValue(const SessionAnswerParams(requestId: 'i', selections: []));
  });

  setUp(() {
    repo = MockSessionControlRepository();
    cubit = SessionCommandCubit(repo, sessionId: 's1');
  });

  test('stop is enabled only while active', () {
    cubit.onActivity('active');
    expect(cubit.enabled('stop'), isTrue);
    expect(cubit.enabled('compact'), isFalse);

    cubit.onActivity('idle');
    expect(cubit.enabled('stop'), isFalse);
    expect(cubit.enabled('compact'), isTrue);
  });

  test('every command is disabled while blocked, with a reason', () {
    cubit.onActivity('blocked');
    for (final command in ['stop', 'compact', 'model']) {
      expect(cubit.enabled(command), isFalse, reason: command);
      expect(cubit.disabledReason(command), isNotNull, reason: command);
    }
  });

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a successful command walks sending -> sent',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
      );
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('compact'),
    verify: (c) => expect(c.phases['compact'], CommandPhase.sent),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a compaction event moves compact from sent to confirmed',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
      );
      return cubit..onActivity('idle');
    },
    act: (c) async {
      await c.run('compact');
      c.onEvent(_event(kind: 'compaction'));
    },
    verify: (c) => expect(c.phases['compact'], CommandPhase.confirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a refused command returns to idle and never claims sent',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure<Map<String, dynamic>>(error: 'refused', message: 'refused', apiStatus: 'SESSION_COMMAND_UNAVAILABLE'),
        ),
      );
      return cubit..onActivity('active');
    },
    act: (c) => c.run('compact'),
    verify: (c) => expect(c.phases['compact'], CommandPhase.idle),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a model command stores the rows the picker offered',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent', models: ['sonnet', 'opus'])),
        ),
      );
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('model', model: 'opus'),
    verify: (c) => expect(c.models, ['sonnet', 'opus']),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a model rejection still refreshes the seed list from what was offered',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure<Map<String, dynamic>>(
            error: 'refused',
            message: 'refused',
            apiStatus: 'SESSION_MODEL_NOT_OFFERED',
            validationErrors: const {
              'models': ['sonnet', 'haiku'],
            },
          ),
        ),
      );
      return cubit..onActivity('idle');
    },
    act: (c) => c.run('model', model: 'opus'),
    verify: (c) {
      expect(c.phases['model'], CommandPhase.idle);
      expect(c.models, ['sonnet', 'haiku']);
    },
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'stop confirms when the session goes idle',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
      );
      return cubit..onActivity('active');
    },
    act: (c) async {
      await c.run('stop');
      c.onActivity('idle');
    },
    verify: (c) => expect(c.phases['stop'], CommandPhase.confirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a command whose signal never arrives becomes unconfirmed',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
      );
      return SessionCommandCubit(repo, sessionId: 's1', budget: Duration.zero)..onActivity('idle');
    },
    act: (c) async {
      await c.run('compact');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
    verify: (c) => expect(c.phases['compact'], CommandPhase.unconfirmed),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'model sits at sent with no timer, because turn_model may be a whole turn away',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
      );
      return SessionCommandCubit(repo, sessionId: 's1', budget: Duration.zero)..onActivity('idle');
    },
    act: (c) async {
      await c.run('model', model: 'opus');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
    verify: (c) => expect(c.phases['model'], CommandPhase.sent),
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a decision reporting unconfirmed is not shown as done',
    build: () {
      when(() => repo.decide(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'unconfirmed'))),
      );
      return cubit..onActivity('blocked');
    },
    act: (c) => c.decide('i1', 'allow'),
    verify: (c) => expect(c.phases['decision'], CommandPhase.unconfirmed),
  );

  test('stop confirms even when the idle signal beats the HTTP response back', () async {
    final pending = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => repo.sendCommand(any(), any())).thenAnswer((_) => pending.future);
    cubit.onActivity('active');

    final runFuture = cubit.run('stop');
    expect(cubit.phases['stop'], CommandPhase.sending);

    cubit.onActivity('idle');
    pending.complete(Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))));
    await runFuture;

    expect(cubit.phases['stop'], CommandPhase.confirmed);
  });

  test('compact confirms even when the compaction event beats the HTTP response back', () async {
    final pending = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => repo.sendCommand(any(), any())).thenAnswer((_) => pending.future);
    cubit.onActivity('idle');

    final runFuture = cubit.run('compact');
    expect(cubit.phases['compact'], CommandPhase.sending);

    cubit.onEvent(_event(kind: 'compaction'));
    pending.complete(Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))));
    await runFuture;

    expect(cubit.phases['compact'], CommandPhase.confirmed);
  });

  test('closing while a command is in flight does not throw when the response lands', () async {
    final pending = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => repo.sendCommand(any(), any())).thenAnswer((_) => pending.future);
    cubit.onActivity('idle');

    final runFuture = cubit.run('compact');
    await cubit.close();
    pending.complete(Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))));

    await expectLater(runFuture, completes);
  });
}
