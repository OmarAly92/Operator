import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/permission_mode_page.dart';

import '../../../fake_recent_photos.dart';
import '../../../terminal_harness.dart';

const _supported = SessionModel(
  id: 's-1',
  harness: 'claude-code',
  permissionMode: 'bypass-permissions',
  permissionModeSupported: true,
  permissionModeCycle: ['default', 'accept-edits', 'plan', 'bypass-permissions'],
);

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() {
    if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>();
    sl.registerSingleton<RecentPhotosDataSource>(FakeRecentPhotos());
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, SessionModel session) async {
    harness = TerminalHarness()..start(harness: 'claude-code', session: session);
    await harness.pump(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> openPage(WidgetTester tester) async {
    await open(tester, _supported);
    await tester.tap(find.byKey(PermissionModeRow.rowKey));
    await tester.pumpAndSettle();
  }

  Finder check(String mode) =>
      find.descendant(of: find.byKey(ValueKey('permission-mode-$mode')), matching: find.byIcon(Icons.check_rounded));

  testWidgets('a harness without support shows no Permission row', (tester) async {
    await open(tester, const SessionModel(id: 's-1', harness: 'codex', permissionMode: 'default'));

    expect(find.byKey(PermissionModeRow.rowKey), findsNothing);
  });

  testWidgets('the row reads Permission and the current mode', (tester) async {
    await open(tester, _supported);

    expect(find.text('Permission'), findsOneWidget);
    expect(find.text('Bypass permissions'), findsOneWidget);
  });

  testWidgets('the page lists every mode, checks the current one and notes restarts', (tester) async {
    await openPage(tester);

    for (final mode in kPermissionModes) {
      expect(find.byKey(ValueKey('permission-mode-$mode')), findsOneWidget);
    }
    expect(check('bypass-permissions'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('permission-mode-auto')), matching: find.text(kPermissionRestartNote)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('permission-mode-plan')), matching: find.text(kPermissionRestartNote)), findsNothing);
  });

  testWidgets('choosing a mode applies it and returns to the sheet showing it', (tester) async {
    await openPage(tester);
    when(() => harness.controlRepository.sendCommand(any(), any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: SessionCommandResultModel(state: 'sent', permissionMode: 'plan'))),
    );

    await tester.tap(find.byKey(const ValueKey('permission-mode-plan')));
    await tester.pumpAndSettle();

    verify(() => harness.controlRepository.sendCommand('s-1', const SessionCommandParams(command: 'permission-mode', mode: 'plan'))).called(1);
    expect(find.byKey(PermissionModeRow.rowKey), findsOneWidget);
    expect(find.descendant(of: find.byKey(PermissionModeRow.rowKey), matching: find.text('Plan')), findsOneWidget);
  });

  testWidgets('a failure stays on the page, reverts the check and shows why', (tester) async {
    await openPage(tester);
    final reply = Completer<Result<GlobalResponse<SessionCommandResultModel>, Failure>>();
    when(() => harness.controlRepository.sendCommand(any(), any())).thenAnswer((_) => reply.future);

    await tester.tap(find.byKey(const ValueKey('permission-mode-auto')));
    await tester.pump();
    expect(check('auto'), findsNothing);
    reply.complete(Result.failure(ServerFailure(error: 'x', message: 'busy', apiStatus: 'SESSION_BUSY')));
    await tester.pumpAndSettle();

    expect(find.byKey(PermissionModeList.errorKey), findsOneWidget);
    expect(find.text('The agent is working — try again when it is idle'), findsOneWidget);
    expect(check('bypass-permissions'), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-mode-auto')), findsOneWidget);
  });
}
