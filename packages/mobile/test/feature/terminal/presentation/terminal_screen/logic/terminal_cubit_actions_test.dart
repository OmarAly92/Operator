import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

void main() {
  late _MockMuxClient mux;
  late _MockTerminalRepository terminalRepository;
  late _MockSessionsRepository sessionsRepository;
  late StreamController<MuxStatus> statuses;
  late StreamController<TerminalEvent> events;

  const sessionArgs = TerminalArgs(
    id: 's-1',
    sessionId: 's-1',
    projectId: 'p-1',
    title: 'Session',
  );
  const shellArgs = TerminalArgs(
    id: 'h-1',
    sessionId: 's-1',
    projectId: 'p-1',
    title: 'Worktree shell',
    shellOnly: true,
  );

  TerminalCubit build([TerminalArgs args = sessionArgs]) => TerminalCubit(
    mux,
    terminalRepository,
    sessionsRepository,
    args,
    restoreDelay: const Duration(milliseconds: 10),
  );

  Failure awaitingDecision() => ServerFailure(
    error: 'x',
    message: 'answer it in the session terminal first',
    statusCode: 409,
    apiStatus: kAwaitingDecision,
  );

  setUpAll(() => registerFallbackValue(const SendSessionMessageParams(message: '')));

  setUp(() {
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    sessionsRepository = _MockSessionsRepository();
    statuses = StreamController<MuxStatus>.broadcast();
    events = StreamController<TerminalEvent>.broadcast();
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
  });

  tearDown(() async {
    await statuses.close();
    await events.close();
  });

  group('send', () {
    test('sends to the agent route by default and clears the composer', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.success(true));
      final cubit = build();
      cubit.composer.text = 'ship it';

      await cubit.send();

      final captured = verify(
        () => terminalRepository.sendSessionMessage('s-1', captureAny()),
      ).captured.single as SendSessionMessageParams;
      expect(captured.message, 'ship it');
      expect(cubit.composer.text, isEmpty);
      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      await cubit.close();
    });

    test('writes to the PTY, with a submit, on the terminal route', () async {
      final cubit = build();
      cubit.attach();
      cubit.setSendTarget(SendTarget.terminal);
      cubit.composer.text = 'yes,\nthe second one';

      await cubit.send();

      verify(() => mux.sendInput('s-1', 'yes, the second one\r', projectId: 'p-1')).called(1);
      expect(cubit.banner, kTerminalModeNotice);
      expect(cubit.composer.text, isEmpty);
      verifyNever(() => terminalRepository.sendSessionMessage(any(), any()));
      await cubit.close();
    });

    test('refuses the terminal route when the socket is not open, keeping the text', () async {
      when(() => mux.currentStatus).thenReturn(MuxStatus.closed);
      final cubit = build();
      cubit.setSendTarget(SendTarget.terminal);
      cubit.composer.text = 'y';

      await cubit.send();

      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      expect(cubit.banner, kTerminalUnavailableNotice);
      expect(cubit.composer.text, 'y');
      await cubit.close();
    });

    // The daemon refuses /send while the session is paused on a permission
    // prompt and says to answer in the terminal, so that is exactly what we do.
    test('reroutes to the PTY when the agent is blocked on a decision', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.failure(awaitingDecision()));
      final cubit = build();
      cubit.attach();
      cubit.composer.text = 'approve';

      await cubit.send();

      verify(() => mux.sendInput('s-1', 'approve\r', projectId: 'p-1')).called(1);
      expect(cubit.sendTarget, SendTarget.terminal);
      expect(cubit.banner, kReroutedNotice);
      expect(cubit.composer.text, isEmpty);
      await cubit.close();
    });

    test('does not reroute onto a socket that is not open', () async {
      when(() => mux.currentStatus).thenReturn(MuxStatus.closed);
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.failure(awaitingDecision()));
      final cubit = build();
      cubit.composer.text = 'approve';

      await cubit.send();

      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      expect(cubit.banner, startsWith('Send failed:'));
      expect(cubit.composer.text, 'approve');
      await cubit.close();
    });

    test('keeps the text on any failure it did not handle', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'nope', statusCode: 500, apiStatus: 'INTERNAL'),
        ),
      );
      final cubit = build();
      cubit.composer.text = 'ship it';

      await cubit.send();

      expect(cubit.composer.text, 'ship it');
      expect(cubit.banner, 'Send failed: nope');
      await cubit.close();
    });

    test('ignores an empty composer', () async {
      final cubit = build();
      cubit.composer.text = '   ';

      await cubit.send();

      verifyNever(() => terminalRepository.sendSessionMessage(any(), any()));
      await cubit.close();
    });
  });

  group('terminate', () {
    test('kills the session and reports closed', () async {
      when(() => sessionsRepository.kill(any())).thenAnswer((_) async => Result.success(true));
      final cubit = build();

      await cubit.terminate();

      verify(() => sessionsRepository.kill('s-1')).called(1);
      expect(cubit.state, isA<TerminalClosedState>());
      await cubit.close();
    });

    test('closes the shell handle instead when this is a worktree shell', () async {
      when(() => terminalRepository.closeShellTerminal(any()))
          .thenAnswer((_) async => Result.success(true));
      final cubit = build(shellArgs);

      await cubit.terminate();

      verify(() => terminalRepository.closeShellTerminal('h-1')).called(1);
      verifyNever(() => sessionsRepository.kill(any()));
      expect(cubit.state, isA<TerminalClosedState>());
      await cubit.close();
    });

    test('stays on the screen with a banner when the kill fails', () async {
      when(() => sessionsRepository.kill(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'busy', statusCode: 409)),
      );
      final cubit = build();

      await cubit.terminate();

      expect(cubit.state, isA<TerminalReadyState>());
      expect(cubit.banner, 'Kill failed: busy');
      await cubit.close();
    });
  });

  group('restore', () {
    test('re-attaches the PTY after the daemon has had a moment to bring it up', () async {
      when(() => sessionsRepository.restore(any())).thenAnswer((_) async => Result.success(true));
      final cubit = build();
      cubit.attach();
      cubit.reportFit(const TerminalGrid(40, 20));
      events.add(const TerminalErrorEvent('s-1', 'Session not found'));
      await Future<void>.delayed(Duration.zero);

      await cubit.restore();
      expect(cubit.notFound, isFalse);
      expect(cubit.restoring, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      verify(() => mux.openTerminal('s-1', projectId: 'p-1')).called(2);
      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(2);
      await cubit.close();
    });

    test('banners a failed restore and stays dead', () async {
      when(() => sessionsRepository.restore(any())).thenAnswer(
        (_) async =>
            Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: 409)),
      );
      final cubit = build();
      events.add(const TerminalExitedEvent('s-1', 1));
      await Future<void>.delayed(Duration.zero);

      await cubit.restore();

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, 'Restore failed: gone');
      await cubit.close();
    });
  });

  group('zoom', () {
    test('steps the font size within its bounds', () async {
      final cubit = build();

      cubit.zoom(1);
      expect(cubit.fontSize, 13);

      for (var i = 0; i < 20; i++) {
        cubit.zoom(1);
      }
      expect(cubit.fontSize, kTerminalMaxFontSize);

      for (var i = 0; i < 40; i++) {
        cubit.zoom(-1);
      }
      expect(cubit.fontSize, kTerminalMinFontSize);
      await cubit.close();
    });
  });
}
