import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';

class MockSessionControlRepository extends Mock
    implements SessionControlRepository {}

class _MockMux extends Mock implements MuxClient {}

class _MockUsageRepository extends Mock implements UsageRepository {}

BlockEventModel _event({String? kind}) => BlockEventModel(kind: kind);

void main() {
  late MockSessionControlRepository repo;
  late _MockMux mux;
  late StreamController<List<SessionPatch>> patches;
  late StreamController<BlockEventEnvelope> events;
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
    patches = StreamController<List<SessionPatch>>.broadcast();
    events = StreamController<BlockEventEnvelope>.broadcast();
    usageRepository = _MockUsageRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => patches.stream);
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => repo.getInteractions(any())).thenAnswer(
      (_) async =>
          Result.success(GlobalResponse<List<PendingInteractionModel>>()),
    );
    when(
      () => usageRepository.sessionContext(any()),
    ).thenAnswer((_) async => null);
    cubit = SessionCommandCubit(mux, repo, usageRepository, sessionId: 's1');
  });

  tearDown(() async {
    await patches.close();
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
    'a stop refused with SESSION_BUSY reports the agent as busy',
    build: () {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure<Map<String, dynamic>>(error: 'busy', message: 'busy', statusCode: 409, apiStatus: 'SESSION_BUSY'),
        ),
      );
      return cubit..onActivity('active');
    },
    act: (c) => c.run('stop'),
    verify: (c) {
      expect(c.phases['stop'], CommandPhase.idle);
      expect(c.lastRefusal, 'The agent is busy — try again in a moment');
    },
  );

  blocTest<SessionCommandCubit, SessionCommandState>(
    'a later success clears the refusal',
    build: () {
      var calls = 0;
      when(() => repo.sendCommand(any(), any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          return Result.failure(
            ServerFailure<Map<String, dynamic>>(error: 'busy', message: 'busy', apiStatus: 'SESSION_BUSY'),
          );
        }
        return Result.success(GlobalResponse(data: const SessionCommandResultModel()));
      });
      return cubit..onActivity('active');
    },
    act: (c) async {
      await c.run('stop');
      await c.run('stop');
    },
    verify: (c) => expect(c.lastRefusal, isNull),
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
    'a session patch off the mux feeds activity, so the row is enabled without an onActivity call',
    () async {
      expect(
        cubit.enabled('stop'),
        isFalse,
        reason: 'no activity is known yet',
      );

      patches.add(const [
        SessionPatch(
          id: 's1',
          status: 'running',
          activity: 'active',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.enabled('stop'), isTrue);
      expect(cubit.enabled('compact'), isFalse);
    },
  );

  test('a patch for another session is ignored', () async {
    cubit.onActivity('idle');
    patches.add(const [
      SessionPatch(
        id: 'other',
        status: 'running',
        activity: 'active',
      ),
    ]);
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

  test('a compaction event from a subagent does not confirm a parent compact command', () async {
    when(() => repo.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const SessionCommandResultModel(state: 'sent')),
      ),
    );
    cubit.onActivity('idle');
    await cubit.run('compact');
    expect(cubit.phases['compact'], CommandPhase.sent);

    events.add(const BlockEventEnvelope('s1', {'kind': 'compaction', 'agentId': 'a1'}));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.phases['compact'], CommandPhase.sent);
  });

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
      );
      await Future<void>.delayed(Duration.zero);

      expect(reconciled.pendingInteraction?.id, 'int-9');
      await reconciled.close();
    },
  );

  test('a live permission request refetches the dialog with its options', () async {
    when(() => repo.getInteractions('s1')).thenAnswer(
      (_) async => Result.success(
        GlobalResponse<List<PendingInteractionModel>>(
          data: const [
            PendingInteractionModel(
              id: 'int-1',
              kind: 'permission',
              toolName: 'Bash',
              options: ['Yes', "Yes, and don't ask again for this session", 'No'],
            ),
          ],
        ),
      ),
    );
    expect(cubit.state.pendingInteraction, isNull);

    events.add(
      const BlockEventEnvelope('s1', {
        'kind': 'permission_request',
        'interactionId': 'int-1',
        'toolName': 'Bash',
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.pendingInteraction?.id, 'int-1');
    expect(cubit.state.pendingInteraction?.options, hasLength(3));
  });

  test('a decision by option label sends the label, not a behavior', () async {
    when(() => repo.decide(any(), any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionCommandResultModel(state: 'sent'))),
    );
    cubit.onActivity('blocked');

    await cubit.decideOption('i1', "Yes, and don't ask again for this session");

    final params = verify(() => repo.decide('s1', captureAny())).captured.single as SessionDecisionParams;
    expect(params.option, "Yes, and don't ask again for this session");
    expect(params.behavior, isNull);
    expect(params.toJson().containsKey('behavior'), isFalse);
    expect(cubit.phases['decision'], CommandPhase.sent);
  });

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
      initialActivity: 'idle',
    );
    await Future<void>.delayed(Duration.zero);

    expect(reconciled.pendingInteraction, isNull);
    expect(reconciled.enabled('compact'), isTrue);
    await reconciled.close();
  });

  test('closing cancels the mux subscriptions', () async {
    await cubit.close();
    patches.add(const [
      SessionPatch(
        id: 's1',
        status: 'running',
        activity: 'active',
      ),
    ]);
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

  group('current model', () {
    test('fetchModels stores the picker rows and the ticked one as current', () async {
      when(() => repo.getModels(any())).thenAnswer(
        (_) async => Result.success(
          GlobalResponse<List<SessionModelOptionModel>>(
            data: const [
              SessionModelOptionModel(label: 'Opus (1M context)', description: 'Opus 5', current: false),
              SessionModelOptionModel(label: 'Sonnet', description: 'Sonnet 5', current: true),
            ],
          ),
        ),
      );

      await cubit.fetchModels();

      expect(cubit.currentModel, 'Sonnet');
      expect(cubit.models, ['Opus (1M context)', 'Sonnet']);
      expect(cubit.state.modelsLoading, isFalse);
      expect(cubit.modelOptions.length, 2);
    });

    test('a failed fetch clears loading and keeps what was known', () async {
      when(() => repo.getModels(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'busy', statusCode: 409)),
      );

      await cubit.fetchModels();

      expect(cubit.state.modelsLoading, isFalse);
      expect(cubit.currentModel, isNull);
    });

    test('a turn_model event names the model the turn ran on', () async {
      events.add(const BlockEventEnvelope('s1', {'kind': 'turn_model', 'text': 'claude-opus-5[1m]'}));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.currentModel, 'Opus 5 (1M)');
    });

    test('a turn_model event from a subagent does not change the parent model', () async {
      events.add(const BlockEventEnvelope('s1', {
        'kind': 'turn_model',
        'text': 'claude-haiku-4',
        'agentId': 'a1',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.currentModel, isNull);

      events.add(const BlockEventEnvelope('s1', {'kind': 'turn_model', 'text': 'claude-opus-5[1m]'}));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.currentModel, 'Opus 5 (1M)');
    });

    test('a successful switch shows the picked label until the next turn confirms it', () async {
      when(() => repo.sendCommand(any(), any())).thenAnswer(
        (_) async => Result.success(GlobalResponse<SessionCommandResultModel>(data: const SessionCommandResultModel())),
      );
      cubit.onActivity('idle');

      await cubit.run('model', model: 'Haiku');

      expect(cubit.currentModel, 'Haiku');
      expect(cubit.phases['model'], CommandPhase.sent);
    });
  });
}
