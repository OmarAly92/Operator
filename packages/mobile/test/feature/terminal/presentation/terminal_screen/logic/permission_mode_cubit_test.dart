import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockControl extends Mock implements SessionControlRepository {}

const _claudeSession = SessionModel(
  id: 's-1',
  harness: 'claude-code',
  permissionMode: 'bypass-permissions',
  permissionModeSupported: true,
  permissionModeCycle: ['default', 'accept-edits', 'plan', 'bypass-permissions'],
);

BlockEventEnvelope modeEvent(String mode, {String sessionId = 's-1', String? agentId}) => BlockEventEnvelope(sessionId, {
  'seq': 9,
  'sessionId': sessionId,
  'kind': 'permission_mode',
  'text': mode,
  'agentId': ?agentId,
});

void main() {
  late _MockMuxClient mux;
  late _MockControl control;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<Object?> sessionChanges;
  late SessionModel? session;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() {
    mux = _MockMuxClient();
    control = _MockControl();
    events = StreamController<BlockEventEnvelope>.broadcast();
    sessionChanges = StreamController<Object?>.broadcast();
    session = _claudeSession;
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
  });

  tearDown(() async {
    await events.close();
    await sessionChanges.close();
  });

  PermissionModeCubit build() => PermissionModeCubit(
    mux,
    control,
    sessionId: 's-1',
    session: () => session,
    sessionChanges: sessionChanges.stream,
  );

  test('seeds the mode, support and cycle from the session', () async {
    final cubit = build();

    expect(cubit.state.mode, 'bypass-permissions');
    expect(cubit.state.supported, isTrue);
    expect(cubit.state.restarts('auto'), isTrue);
    expect(cubit.state.restarts('plan'), isFalse);
    await cubit.close();
  });

  test('a desktop-side change arriving as a block event updates the mode', () async {
    final cubit = build();

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('another session and a subagent never move the mode', () async {
    final cubit = build();

    events
      ..add(modeEvent('plan', sessionId: 's-2'))
      ..add(modeEvent('plan', agentId: 'agent-1'));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, 'bypass-permissions');
    await cubit.close();
  });

  test('choosing sends the permission-mode command and keeps the confirmed mode', () async {
    when(() => control.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'plan'))),
    );
    final cubit = build();

    expect(await cubit.choose('plan'), isTrue);

    verify(() => control.sendCommand('s-1', const SessionCommandParams(command: 'permission-mode', mode: 'plan'))).called(1);
    expect(cubit.state.mode, 'plan');
    expect(cubit.state.pending, isNull);
    await cubit.close();
  });

  test('a failed change reverts to the last observed mode and says why', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    final choosing = cubit.choose('auto');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.pending, 'auto');
    expect(cubit.state.mode, 'auto');
    events.add(modeEvent('accept-edits'));
    await Future<void>.delayed(Duration.zero);
    reply.complete(Result.failure(ServerFailure(error: 'x', message: 'busy', apiStatus: 'SESSION_BUSY')));

    expect(await choosing, isFalse);
    expect(cubit.state.mode, 'accept-edits');
    expect(cubit.state.pending, isNull);
    expect(cubit.state.error, 'The agent is working — try again when it is idle');
    await cubit.close();
  });

  test('a second choice while one is in flight is ignored', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    unawaited(cubit.choose('plan'));
    await Future<void>.delayed(Duration.zero);
    expect(await cubit.choose('auto'), isFalse);
    verify(() => control.sendCommand(any(), any())).called(1);

    reply.complete(Result.success(const GlobalResponse(data: SessionCommandResultModel(permissionMode: 'plan'))));
    await cubit.close();
  });

  test('a session refresh turns support on once the daemon reports it', () async {
    session = const SessionModel(id: 's-1', harness: 'claude-code', permissionMode: 'bypass-permissions');
    final cubit = build();
    expect(cubit.state.supported, isFalse);

    session = _claudeSession;
    sessionChanges.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.supported, isTrue);
    expect(cubit.state.cycle, contains('plan'));
    await cubit.close();
  });
}
