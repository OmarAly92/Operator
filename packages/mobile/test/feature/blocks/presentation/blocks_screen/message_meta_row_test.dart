import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/message_meta_row.dart';

const _prompt = SessionBlock(
  id: 'p-1',
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.prompt,
  status: BlockStatus.ok,
  title: '',
  body: 'Hello there',
  createdAt: '2026-09-24T13:05:00Z',
);

Widget _host(Widget child) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  final clipboard = <String>[];
  final haptics = <String>[];

  setUp(() {
    clipboard.clear();
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('the user meta row sits right-aligned under the bubble with time then copy', (tester) async {
    await tester.pumpWidget(_host(const BlockCard(block: _prompt)));
    final screen = tester.getSize(find.byType(Scaffold));
    final bubble = tester.getRect(find.byKey(const ValueKey('user-bubble-p-1')));
    final time = tester.getRect(find.byKey(const ValueKey('bubble-timestamp-p-1')));
    final copy = tester.getRect(find.byKey(const ValueKey('message-copy-p-1')));
    expect(time.top, greaterThan(bubble.bottom));
    expect(copy.left, greaterThan(time.right - 1));
    expect(copy.size, const Size(28, 28));
    expect(tester.getSize(find.byIcon(Icons.content_copy_rounded)).width, 13);
    final icon = tester.getRect(find.byIcon(Icons.content_copy_rounded));
    expect(icon.right, closeTo(bubble.right, 1));
    expect(bubble.right, closeTo(screen.width - 16, 1));
  });

  testWidgets('the time uses mono 10.5 in the tertiary text colour', (tester) async {
    await tester.pumpWidget(_host(const BlockCard(block: _prompt)));
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(const ValueKey('bubble-timestamp-p-1')), matching: find.byType(Text)),
    );
    expect(text.style?.fontSize, 10.5);
    expect(text.style?.color, const DarkSkin().textTertiary);
    expect(text.data, messageTimeLabel(_prompt.createdAt));
  });

  testWidgets('copy writes the text, taps a haptic and shows a check for 1.2s', (tester) async {
    await tester.pumpWidget(_host(const BlockCard(block: _prompt)));
    await tester.tap(find.byKey(const ValueKey('message-copy-p-1')));
    await tester.pump();
    expect(clipboard, ['Hello there']);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await tester.pump(AppMotion.chatActionSwap);
    await tester.pump(AppMotion.chatActionSwap);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
    await tester.pump(AppMotion.copyConfirm - AppMotion.chatActionSwap * 2 - const Duration(milliseconds: 20));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  testWidgets('the icon swap cross-fades rather than cutting', (tester) async {
    await tester.pumpWidget(_host(const BlockCard(block: _prompt)));
    await tester.tap(find.byKey(const ValueKey('message-copy-p-1')));
    await tester.pump();
    await tester.pump(AppMotion.chatActionSwap ~/ 2);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the swap is instant under reduce motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(const BlockCard(block: _prompt)));
    await tester.tap(find.byKey(const ValueKey('message-copy-p-1')));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
    await tester.pump(AppMotion.copyConfirm);
    await tester.pump();
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  testWidgets('an assistant meta row is left-aligned with copy before time', (tester) async {
    await tester.pumpWidget(
      _host(
        const Align(
          alignment: Alignment.topCenter,
          child: MessageMetaRow(
            id: 'a-1',
            text: 'Done.',
            createdAt: '2026-09-24T13:05:00Z',
            side: MessageMetaSide.assistant,
          ),
        ),
      ),
    );
    final copy = tester.getRect(find.byKey(const ValueKey('message-copy-a-1')));
    final time = tester.getRect(find.text(messageTimeLabel('2026-09-24T13:05:00Z')));
    expect(copy.right, lessThan(time.left + 1));
  });

  testWidgets('the user bubble has radius 20 and caps at 85% of the content width', (tester) async {
    final long = _prompt.copyWith(body: List.filled(60, 'word').join(' '));
    await tester.pumpWidget(
      _host(Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, child: BlockCard(block: long)))),
    );
    final bubble = find.byKey(const ValueKey('user-bubble-p-1'));
    expect(tester.getSize(bubble).width, closeTo((300 - 32) * 0.85, 0.5));
    final decoration = tester.widget<Container>(bubble).decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(20));
  });

  test('time labels read as 12-hour clock times', () {
    final local = DateTime(2026, 9, 24, 13, 5);
    expect(messageTimeLabel(local.toIso8601String()), '1:05 PM');
    expect(messageTimeLabel(DateTime(2026, 9, 24, 0, 7).toIso8601String()), '12:07 AM');
    expect(messageTimeLabel(null), 'now');
  });
}
