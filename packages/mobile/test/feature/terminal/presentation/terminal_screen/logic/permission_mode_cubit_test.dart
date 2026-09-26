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
  late StreamController<MuxStatus> statuses;
  late SessionModel? session;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() {
    mux = _MockMuxClient();
    control = _MockControl();
    events = StreamController<BlockEventEnvelope>.broadcast();
    sessionChanges = StreamController<Object?>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    session = _claudeSession;
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
  });

  tearDown(() async {
    await events.close();
    await sessionChanges.close();
    await statuses.close();
  });

  PermissionModeCubit build() => PermissionModeCubit(
    mux,
    control,
    sessionId: 's-1',
    session: () => session,
    sessionChanges: sessionChanges.stream,
  );

  test('seeds the mode and support from the session without a restart notice', () async {
    final cubit = build();

    expect(cubit.state.mode, 'bypass-permissions');
    expect(cubit.state.supported, isTrue);
    expect(cubit.state.restarted, isFalse);
    await cubit.close();
  });

  test('a desktop-side change arriving as a block event updates the mode', () async {
    final cubit = build();

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('an unknown mode from the transcript clears the mode instead of keeping a stale one', () async {
    final cubit = build();

    events.add(modeEvent(''));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.mode, isNull);

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('a refresh reporting no mode shows the mode as unknown', () async {
    final cubit = build();

    session = const SessionModel(
      id: 's-1',
      harness: 'claude-code',
      permissionModeSupported: true,
    );
    sessionChanges.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.mode, isNull);
    expect(cubit.state.supported, isTrue);
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
    expect(cubit.state.restarted, isFalse);
    await cubit.close();
  });

  test('a change the daemon reached by restarting the agent is flagged until the next choice', () async {
    when(() => control.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'auto', restarted: true)),
      ),
    );
    final cubit = build();

    expect(await cubit.choose('auto'), isTrue);
    expect(cubit.state.mode, 'auto');
    expect(cubit.state.restarted, isTrue);

    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    unawaited(cubit.choose('plan'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.restarted, isFalse);
    reply.complete(Result.success(const GlobalResponse(data: SessionCommandResultModel(permissionMode: 'plan'))));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.restarted, isFalse);
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
    await cubit.close();
  });

  Future<void> refresh(String mode) async {
    session = SessionModel(
      id: 's-1',
      harness: 'claude-code',
      permissionMode: mode,
      permissionModeSupported: true,
    );
    sessionChanges.add(null);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> reconnect() async {
    statuses
      ..add(MuxStatus.closed)
      ..add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);
  }

  test('a refresh after an event does not revert the mode while it is held', () async {
    final cubit = build();

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);
    await refresh('bypass-permissions');

    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('a reconnect releases the held mode so the next refresh is followed', () async {
    final cubit = build();

    events.add(modeEvent('plan'));
    await Future<void>.delayed(Duration.zero);
    await reconnect();
    await refresh('accept-edits');

    expect(cubit.state.mode, 'accept-edits');
    await cubit.close();
  });

  test('a chosen mode survives a stale refresh and is released once a refresh agrees', () async {
    when(() => control.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'plan'))),
    );
    final cubit = build();
    await cubit.choose('plan');

    await refresh('bypass-permissions');
    expect(cubit.state.mode, 'plan');

    await refresh('plan');
    await refresh('accept-edits');
    expect(cubit.state.mode, 'accept-edits');
    await cubit.close();
  });

  test('a refresh while a choice is pending leaves the pending choice alone', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    unawaited(cubit.choose('plan'));
    await Future<void>.delayed(Duration.zero);
    await refresh('accept-edits');

    expect(cubit.state.pending, 'plan');
    expect(cubit.state.mode, 'plan');
    reply.complete(Result.success(const GlobalResponse(data: SessionCommandResultModel(permissionMode: 'plan'))));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.mode, 'plan');
    await cubit.close();
  });

  test('a failure after a refresh during the pending choice reverts to the refreshed mode', () async {
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => control.sendCommand(any(), any())).thenAnswer((_) => reply.future);
    final cubit = build();

    final choosing = cubit.choose('plan');
    await Future<void>.delayed(Duration.zero);
    await refresh('accept-edits');
    expect(cubit.state.mode, 'plan');
    reply.complete(Result.failure(ServerFailure(error: 'x', message: 'no', apiStatus: 'PERMISSION_MODE_UNCONFIRMED')));

    expect(await choosing, isFalse);
    expect(cubit.state.mode, 'accept-edits');
    expect(cubit.state.pending, isNull);
    await cubit.close();
  });

  test('a refresh that no longer finds the session keeps the row', () async {
    final cubit = build();

    session = null;
    sessionChanges.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.supported, isTrue);
    expect(cubit.state.mode, 'bypass-permissions');
    await cubit.close();
  });
}
