import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_action_sheet.dart';

const _hapticsChannel = MethodChannel('operator/haptics');

Future<void> _pump(
  WidgetTester tester, {
  required List<BlockAction> actions,
  Future<BlockAction?> Function(BuildContext, List<BlockAction>)? opener,
}) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () async {
                    final open = opener ?? showBlockActionSheet;
                    await open(context, actions);
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
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> platform = <MethodCall>[];
  final List<MethodCall> notification = <MethodCall>[];
  final List<String> clipboard = <String>[];

  setUp(() {
    platform.clear();
    notification.clear();
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platform.add(call);
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map;
        clipboard.add(args['text'] as String);
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticsChannel, (call) async {
      notification.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticsChannel, null);
  });

  testWidgets('shows one row per action with the documented labels', (tester) async {
    await _pump(
      tester,
      actions: const [
        BlockAction(kind: BlockActionKind.copyBlock, payload: 'block text'),
        BlockAction(kind: BlockActionKind.copyCommand, payload: 'ls'),
        BlockAction(kind: BlockActionKind.copyOutput, payload: 'file.txt'),
        BlockAction(kind: BlockActionKind.rerun, payload: 'do the thing'),
        BlockAction(kind: BlockActionKind.rewind, turnId: 't-1'),
      ],
    );

    expect(find.text('Copy block'), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);
    expect(find.text('Copy output'), findsOneWidget);
    expect(find.text('Re-run this prompt'), findsOneWidget);
    expect(find.text('Rewind the conversation'), findsOneWidget);
  });

  testWidgets('tapping a copy row copies the payload and shows a snackbar', (tester) async {
    await _pump(
      tester,
      actions: const [
        BlockAction(kind: BlockActionKind.copyBlock, payload: 'block text'),
      ],
    );

    await tester.tap(find.text('Copy block'));
    await tester.pumpAndSettle();

    expect(clipboard, ['block text']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('opening the sheet fires a haptics tap', (tester) async {
    await _pump(
      tester,
      actions: const [BlockAction(kind: BlockActionKind.copyBlock, payload: 'x')],
    );

    expect(
      platform.where((c) => c.method == 'HapticFeedback.vibrate'),
      isNotEmpty,
    );
  });
}
