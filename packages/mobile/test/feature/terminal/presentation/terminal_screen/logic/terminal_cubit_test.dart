import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
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

  const args = TerminalArgs(id: 's-1', sessionId: 's-1', projectId: 'p-1', title: 'Session');

  TerminalCubit build() => TerminalCubit(mux, terminalRepository, sessionsRepository, args);

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

  test('attaches the PTY on construction and never touches the socket lifecycle', () async {
    final cubit = build();

    verify(() => mux.openTerminal('s-1', projectId: 'p-1')).called(1);
    verifyNever(() => mux.connect());
    expect(cubit.status, MuxStatus.open);

    await cubit.close();
    verify(() => mux.closeTerminal('s-1', projectId: 'p-1')).called(1);
    verifyNever(() => mux.disconnect());
  });

  test('writes PTY output into the terminal, across a split rune', () async {
    final cubit = build();
    final bytes = utf8.encode('héllo');

    events.add(TerminalDataEvent('s-1', Uint8List.fromList(bytes.sublist(0, 2))));
    events.add(TerminalDataEvent('s-1', Uint8List.fromList(bytes.sublist(2))));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.terminal.buffer.getText(), contains('héllo'));
    await cubit.close();
  });

  test('ignores output for another handle on the shared socket', () async {
    final cubit = build();

    events.add(TerminalDataEvent('other', Uint8List.fromList(utf8.encode('nope'))));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.terminal.buffer.getText(), isNot(contains('nope')));
    await cubit.close();
  });

  group('grid negotiation', () {
    test('reports the phone fit to the daemon and renders it until the daemon answers', () async {
      final cubit = build();

      cubit.reportFit(const TerminalGrid(40, 20));

      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(1);
      expect(cubit.grid, const TerminalGrid(40, 20));
      expect(cubit.authoritative, isFalse);
      await cubit.close();
    });

    test('does not re-send an unchanged fit', () async {
      final cubit = build();

      cubit.reportFit(const TerminalGrid(40, 20));
      cubit.reportFit(const TerminalGrid(40, 20));

      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(1);
      await cubit.close();
    });

    // The daemon's grid is authoritative: a co-viewing desktop owns the size and
    // the phone must mirror it rather than re-fitting and mis-drawing a TUI.
    test('adopts the daemon grid and stops rendering its own fit', () async {
      final cubit = build();
      cubit.reportFit(const TerminalGrid(40, 20));

      events.add(const TerminalResizeEvent('s-1', 120, 30));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.authoritative, isTrue);
      expect(cubit.grid, const TerminalGrid(120, 30));
      expect(cubit.terminal.viewWidth, 120);

      cubit.reportFit(const TerminalGrid(44, 22));
      expect(cubit.grid, const TerminalGrid(120, 30));
      verify(() => mux.resize('s-1', 44, 22, projectId: 'p-1')).called(1);
      await cubit.close();
    });
  });

  group('liveness', () {
    test('tracks the socket status', () async {
      final cubit = build();

      statuses.add(MuxStatus.closed);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.status, MuxStatus.closed);
      await cubit.close();
    });

    test('offers Restore rather than an error banner when the PTY is gone', () async {
      final cubit = build();

      events.add(const TerminalErrorEvent('s-1', 'Session not found'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, isNull);
      await cubit.close();
    });

    test('surfaces any other terminal error in the banner', () async {
      final cubit = build();

      events.add(const TerminalErrorEvent('s-1', 'pty write failed'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.banner, 'pty write failed');
      expect(cubit.notFound, isFalse);
      await cubit.close();
    });

    test('marks an exited session dead with its code', () async {
      final cubit = build();

      events.add(const TerminalExitedEvent('s-1', 130));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, 'Session exited (code 130)');
      await cubit.close();
    });
  });

  blocTest<TerminalCubit, TerminalState>(
    'sends a control sequence straight to the PTY',
    build: build,
    act: (cubit) => cubit.sendKey('\x03'),
    verify: (_) => verify(() => mux.sendInput('s-1', '\x03', projectId: 'p-1')).called(1),
  );
}
