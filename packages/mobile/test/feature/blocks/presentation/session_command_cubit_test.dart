import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';

class MockSessionControlRepository extends Mock
    implements SessionControlRepository {}

class _MockSessions extends Mock implements SessionsCubit {}

class _MockMux extends Mock implements MuxClient {}

class _MockUsageRepository extends Mock implements UsageRepository {}

BlockEventModel _event({String? kind}) => BlockEventModel(kind: kind);

void main() {
  late MockSessionControlRepository repo;
  late _MockMux mux;
  late _MockSessions sessions;
  late StreamController<SessionModel> patches;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;
  late _MockUsageRepository usageRepository;
  late SessionCommandCubit cubit;

  setUpAll(() {
    registerFallbackValue(const SessionCommandParams(command: 'stop'));
    registerFallbackValue(
      const SessionDecisionParams(requestId: 'i', behavior: 'allow'),
    );
    registerFallbackValue(
      const SessionAnswerParams(requestId: 'i', selections: []),
    );
  });

  setUp(() {
    repo = MockSessionControlRepository();
    mux = _MockMux();
    sessions = _MockSessions();
    patches = StreamController<SessionModel>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    events = StreamController<BlockEventEnvelope>.broadcast();
    usageRepository = _MockUsageRepository();
    when(() => sessions.watchSession(any())).thenAnswer(
      (invocation) => patches.stream.where(
        (session) => session.id == invocation.positionalArguments.first,
      ),
    );
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => repo.getInteractions(any())).thenAnswer(
      (_) async =>
          Result.success(GlobalResponse<List<PendingInteractionModel>>()),
    );
    when(
      () => usageRepository.sessionContext(any()),
    ).thenAnswer((_) async => null);
    cubit = SessionCommandCubit(
      mux,
      repo,
      usageRepository,
      sessionId: 's1',
      sessions: sessions,
    );
  });

  tearDown(() async {
    await cubit.close();
    await patches.close();
    await statuses.close();
    await events.close();
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

  test(
    'construction and each activity tick refresh the context readout',
    () async {
      await Future<void>.delayed(Duration.zero);
      verify(() => usageRepository.sessionContext('s1')).called(1);
      clearInteractions(usageRepository);
      when(() => usageRepository.sessionContext('s1')).thenAnswer(
        (_) async => const SessionContextModel(used: 25000, window: 200000),
      );

      cubit.onActivity('idle');
      await Future<void>.delayed(Duration.zero);
      cubit.onActivity('idle');
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.contextReadout?.percentLabel, '13%');
      verify(() => usageRepository.sessionContext('s1')).called(2);
    },
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a successful command walks sending -> sent',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
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
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
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
          ServerFailure<Map<String, dynamic>>(
            error: 'refused',
            message: 'refused',
            apiStatus: 'SESSION_COMMAND_UNAVAILABLE',
          ),
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
          GlobalResponse(
            data: const SessionCommandResultModel(
              state: 'sent',
              models: ['sonnet', 'opus'],
            ),
          ),
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
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
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
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      return SessionCommandCubit(
        mux,
        repo,
        usageRepository,
        sessionId: 's1',
        sessions: sessions,
        budget: Duration.zero,
      )..onActivity('idle');
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
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      return SessionCommandCubit(
        mux,
        repo,
        usageRepository,
        sessionId: 's1',
        sessions: sessions,
        budget: Duration.zero,
      )..onActivity('idle');
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
        (_) async => Result.success(
          GlobalResponse(
            data: const SessionCommandResultModel(state: 'unconfirmed'),
          ),
        ),
      );
      return cubit..onActivity('blocked');
    },
    act: (c) => c.decide('i1', 'allow'),
    verify: (c) => expect(c.phases['decision'], CommandPhase.unconfirmed),
  );

  test(
    'stop confirms even when the idle signal beats the HTTP response back',
    () async {
      final pending =
          Completer<
            Result<GlobalResponse<SessionCommandResultModel>, Failure>
          >();
      when(
        () => repo.sendCommand(any(), any()),
      ).thenAnswer((_) => pending.future);
      cubit.onActivity('active');

      final runFuture = cubit.run('stop');
      expect(cubit.phases['stop'], CommandPhase.sending);

      cubit.onActivity('idle');
      pending.complete(
        Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      await runFuture;

      expect(cubit.phases['stop'], CommandPhase.confirmed);
    },
  );

  test(
    'compact confirms even when the compaction event beats the HTTP response back',
    () async {
      final pending =
          Completer<
            Result<GlobalResponse<SessionCommandResultModel>, Failure>
          >();
      when(
        () => repo.sendCommand(any(), any()),
      ).thenAnswer((_) => pending.future);
      cubit.onActivity('idle');

      final runFuture = cubit.run('compact');
      expect(cubit.phases['compact'], CommandPhase.sending);

      cubit.onEvent(_event(kind: 'compaction'));
      pending.complete(
        Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      await runFuture;

      expect(cubit.phases['compact'], CommandPhase.confirmed);
    },
  );

  test(
    'the shared session stream feeds activity, so the row is enabled without an onActivity call',
    () async {
      expect(
        cubit.enabled('stop'),
        isFalse,
        reason: 'no activity is known yet',
      );

      patches.add(
        const SessionModel(id: 's1', status: 'running', activity: 'active'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.enabled('stop'), isTrue);
      expect(cubit.enabled('compact'), isFalse);
    },
  );

  test('a patch for another session is ignored', () async {
    cubit.onActivity('idle');
    patches.add(
      const SessionModel(id: 'other', status: 'running', activity: 'active'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      cubit.enabled('compact'),
      isTrue,
      reason: 'another session must not move this row',
    );
  });

  test(
    'a block event off the mux confirms a sent command without an onEvent call',
    () async {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      cubit.onActivity('idle');
      await cubit.run('compact');
      expect(cubit.phases['compact'], CommandPhase.sent);

      events.add(const BlockEventEnvelope('s1', {'kind': 'compaction'}));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.phases['compact'], CommandPhase.confirmed);
    },
  );

  test(
    'authoritative idle status confirms stop and termination disables commands',
    () async {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );
      patches.add(const SessionModel(id: 's1', activity: 'active'));
      await Future<void>.delayed(Duration.zero);
      await cubit.run('stop');
      patches.add(const SessionModel(id: 's1', activity: 'idle'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.phases['stop'], CommandPhase.confirmed);
      patches.add(
        const SessionModel(id: 's1', activity: 'idle', isTerminated: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.enabled('compact'), isFalse);
      expect(cubit.enabled('model'), isFalse);
      expect(cubit.disabledReason('compact'), 'The session has ended');
    },
  );

  test('reconnect clears a dialog no longer pending on the daemon', () async {
    await Future<void>.delayed(Duration.zero);
    cubit.pendingInteraction = const PendingInteractionModel(
      id: 'old',
      kind: 'permission',
    );
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.pendingInteraction, isNull);
    verify(() => repo.getInteractions('s1')).called(2);
  });

  test(
    'a live interaction event wins over an older reconciliation response',
    () async {
      await Future<void>.delayed(Duration.zero);
      final pending =
          Completer<
            Result<GlobalResponse<List<PendingInteractionModel>>, Failure>
          >();
      when(() => repo.getInteractions('s1')).thenAnswer((_) => pending.future);
      statuses.add(MuxStatus.open);
      await Future<void>.delayed(Duration.zero);
      events.add(
        const BlockEventEnvelope('s1', {
          'kind': 'permission',
          'interactionId': 'new',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      pending.complete(
        Result.success(
          GlobalResponse(
            data: const [
              PendingInteractionModel(id: 'old', kind: 'permission'),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.pendingInteraction, isNull);
    },
  );

  test('a block event for another session is ignored', () async {
    when(() => repo.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
      ),
    );
    cubit.onActivity('idle');
    await cubit.run('compact');

    events.add(const BlockEventEnvelope('other', {'kind': 'compaction'}));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.phases['compact'], CommandPhase.sent);
  });

  test('the seeded activity enables the row before any patch arrives', () {
    final seeded = SessionCommandCubit(
      mux,
      repo,
      usageRepository,
      sessionId: 's1',
      sessions: sessions,
      initialActivity: 'idle',
    );
    expect(seeded.enabled('compact'), isTrue);
    unawaited(seeded.close());
  });

  test(
    'a pending dialog is backfilled from the interactions endpoint on start',
    () async {
      when(() => repo.getInteractions('s1')).thenAnswer(
        (_) async => Result.success(
          GlobalResponse<List<PendingInteractionModel>>(
            data: const [
              PendingInteractionModel(
                id: 'int-9',
                kind: 'permission',
                toolName: 'Write',
              ),
            ],
          ),
        ),
      );
      final reconciled = SessionCommandCubit(
        mux,
        repo,
        usageRepository,
        sessionId: 's1',
        sessions: sessions,
      );
      await Future<void>.delayed(Duration.zero);

      expect(reconciled.pendingInteraction?.id, 'int-9');
      await reconciled.close();
    },
  );

  test('a failing interactions fetch leaves the row usable', () async {
    when(() => repo.getInteractions('s1')).thenAnswer(
      (_) async =>
          Result.failure(ServerFailure(error: 'nope', message: 'nope')),
    );
    final reconciled = SessionCommandCubit(
      mux,
      repo,
      usageRepository,
      sessionId: 's1',
      sessions: sessions,
      initialActivity: 'idle',
    );
    await Future<void>.delayed(Duration.zero);

    expect(reconciled.pendingInteraction, isNull);
    expect(reconciled.enabled('compact'), isTrue);
    await reconciled.close();
  });

  test('closing cancels the mux subscriptions', () async {
    await cubit.close();
    patches.add(
      const SessionModel(id: 's1', status: 'running', activity: 'active'),
    );
    events.add(const BlockEventEnvelope('s1', {'kind': 'compaction'}));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.activity, isNull);
  });

  test(
    'closing while a command is in flight does not throw when the response lands',
    () async {
      final pending =
          Completer<
            Result<GlobalResponse<SessionCommandResultModel>, Failure>
          >();
      when(
        () => repo.sendCommand(any(), any()),
      ).thenAnswer((_) => pending.future);
      cubit.onActivity('idle');

      final runFuture = cubit.run('compact');
      await cubit.close();
      pending.complete(
        Result.success(
          GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
        ),
      );

      await expectLater(runFuture, completes);
    },
  );
}
