import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart';

ConversationSnapshotModel snapshot({
  List<String> capabilities = const [],
  TurnSettingsModel settings = const TurnSettingsModel(),
}) => ConversationSnapshotModel(
  conversationId: 'c-1',
  sessionId: 'w-1',
  harness: 'codex',
  controllerState: 'ready',
  latestSequence: 1,
  settings: settings,
  capabilities: capabilities,
);

Future<void> pumpHost(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (inner) => TextButton(
                onPressed: () => open(inner),
                child: const Text('open'),
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

void main() {
  test('keeps every approval label and safety hint exact', () {
    expect(kApprovalModes, const [
      (
        id: 'default',
        label: 'Default',
        hint: 'The worktree is the safety boundary',
      ),
      (
        id: 'accept-edits',
        label: 'Ask outside worktree',
        hint: 'Edits here are allowed; anything else asks',
      ),
      (
        id: 'auto',
        label: 'Ask when unsure',
        hint: 'The agent decides when to check with you',
      ),
      (
        id: 'bypass-permissions',
        label: 'Never ask',
        hint: 'No approvals or sandbox prompts',
      ),
    ]);
  });

  testWidgets('offers Operator turn settings when the provider owns none', (
    tester,
  ) async {
    TurnSettingsModel? chosen;
    await pumpHost(
      tester,
      (context) => showChatSettingsSheet(
        context,
        snapshot: snapshot(),
        models: const [
          ChatModelModel(
            id: 'opus',
            displayName: 'Opus',
            isDefault: true,
            efforts: ['low', 'high'],
          ),
        ],
        options: const [],
        disabled: false,
        onSettings: (settings) => chosen = settings,
        onOption: (_) {},
      ),
    );

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
    expect(
      find.textContaining('The worktree is the safety boundary'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never ask'));
    await tester.pumpAndSettle();
    expect(chosen?.approvalMode, 'bypass-permissions');
  });

  testWidgets(
    'hands the whole sheet to the provider when it advertises config options',
    (tester) async {
      SetConfigOptionParams? chosen;
      await pumpHost(
        tester,
        (context) => showChatSettingsSheet(
          context,
          snapshot: snapshot(capabilities: const ['config_options']),
          models: const [ChatModelModel(id: 'opus', displayName: 'Opus')],
          options: const [
            ChatConfigOptionModel(
              id: 'fast',
              name: 'Fast mode',
              type: 'boolean',
              currentBoolean: false,
            ),
          ],
          disabled: false,
          onSettings: (_) {},
          onOption: (params) => chosen = params,
        ),
      );

      expect(find.text('Model'), findsNothing);
      expect(find.text('Approvals'), findsNothing);
      expect(find.text('Fast mode'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(chosen?.optionId, 'fast');
      expect(chosen?.enabled, isTrue);
    },
  );

  testWidgets('says so when the provider has advertised nothing yet', (
    tester,
  ) async {
    await pumpHost(
      tester,
      (context) => showChatSettingsSheet(
        context,
        snapshot: snapshot(capabilities: const ['config_options']),
        models: const [],
        options: const [],
        disabled: false,
        onSettings: (_) {},
        onOption: (_) {},
      ),
    );
    expect(
      find.textContaining('has not advertised any turn controls'),
      findsOneWidget,
    );
  });

  testWidgets('offers only the menu rows this build can honour', (
    tester,
  ) async {
    await pumpHost(
      tester,
      (context) => showConversationMenuSheet(
        context,
        snapshot: snapshot(),
        compactSupported: false,
        mcpReloadSupported: false,
        compacting: false,
        mcpReloading: false,
      ),
    );

    expect(find.text('Conversation map'), findsOneWidget);
    expect(find.text('Pull requests'), findsOneWidget);
    expect(find.text('Turn settings'), findsOneWidget);
    expect(find.text('Compact history'), findsNothing);
    expect(find.text('Reload MCP servers'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Open Terminal UI'), findsNothing);
  });

  testWidgets('returns the chosen menu action', (tester) async {
    ConversationMenuResult? result;
    await pumpHost(
      tester,
      (context) async => result = await showConversationMenuSheet(
        context,
        snapshot: snapshot(capabilities: const ['compaction']),
        compactSupported: true,
        mcpReloadSupported: false,
        compacting: false,
        mcpReloading: false,
      ),
    );

    await tester.tap(find.text('Compact history'));
    await tester.pumpAndSettle();
    expect(result?.action, ConversationMenuAction.compact);
  });

  testWidgets(
    'lists every exchange in the map and returns the chosen sequence',
    (tester) async {
      int? chosen;
      await pumpHost(
        tester,
        (context) async => chosen = await showConversationMapSheet(
          context,
          markers: const [
            ConversationMarker(
              key: 'turn-t1',
              sequence: 1,
              title: 'First task',
              detail: 'First answer',
            ),
            ConversationMarker(
              key: 'turn-t2',
              sequence: 5,
              title: 'Second task',
              state: 'failed',
            ),
          ],
        ),
      );

      expect(find.text('2 exchanges'), findsOneWidget);
      await tester.tap(find.text('Second task'));
      await tester.pumpAndSettle();
      expect(chosen, 5);
    },
  );
}
