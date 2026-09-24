import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/pickers/agent_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

void main() {
  String? selected;
  int refreshCalls = 0;

  setUp(() {
    selected = null;
    refreshCalls = 0;
  });

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
  }

  RankedAgent ranked(String id, {String? label, bool selectable = true, String status = ''}) => RankedAgent(
    id: id,
    label: label ?? id,
    availability: selectable ? AgentAvailability.authorized : AgentAvailability.needsInstall,
    status: status,
    selectable: selectable,
  );

  Future<void> openSheet(
    WidgetTester tester, {
    required List<RankedAgent> agents,
    String selectedId = '',
    String? error,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selected = await showAppSheet<String>(
                        context: context,
                        page: agentPickerPage(
                          agents: agents,
                          selected: selectedId,
                          onPicked: (context, id) => Navigator.of(context).pop(id),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              onPressed: () => refreshCalls++,
                            ),
                          ],
                          error: error,
                        ),
                        detent: AppSheetDetent.large,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('returns the tapped agent', (tester) async {
    await openSheet(tester, agents: [ranked('codex', selectable: true), ranked('amp', selectable: true)]);

    await tester.tap(find.text('codex'));
    await tester.pumpAndSettle();

    expect(selected, 'codex');
  });

  testWidgets('refuses an unusable agent instead of silently ignoring the tap', (tester) async {
    await openSheet(tester, agents: [ranked('goose', selectable: false, status: 'Needs install')]);

    await tester.tap(find.text('goose'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('Needs install'), findsOneWidget);
  });

  testWidgets('reports a catalog error inside the sheet', (tester) async {
    await openSheet(tester, agents: const [], error: 'Your desktop disconnected');

    expect(find.text('Your desktop disconnected'), findsOneWidget);
    expect(find.textContaining('No agents reported'), findsOneWidget);
  });

  testWidgets('refreshes on demand', (tester) async {
    await openSheet(tester, agents: [ranked('codex', selectable: true)]);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
  });

  testWidgets('search narrows agents by label or id and a filtered pick returns its id', (tester) async {
    await openSheet(
      tester,
      agents: [
        ranked('claude-code', label: 'Claude Code'),
        ranked('codex', label: 'Codex'),
        ranked('amp', label: 'Amp'),
      ],
    );
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Which harness should run this task.'), findsOneWidget);

    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'cla');
    await tester.pumpAndSettle();

    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
    expect(find.text('Amp'), findsNothing);

    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();

    expect(selected, 'claude-code');
  });
}
