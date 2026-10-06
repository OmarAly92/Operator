import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/running_tasks_bubble.dart';

void main() {
  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
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

  Widget host(Widget child, {bool reduceMotion = false}) => SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
        ),
      ),
    ),
  );

  testWidgets('while collapsing to zero it keeps the last non-zero count, never "0 running tasks"', (tester) async {
    await tester.pumpWidget(host(RunningTasksBubble(count: 3, onTap: () {})));
    expect(find.text('3 running tasks'), findsOneWidget);

    await tester.pumpWidget(host(RunningTasksBubble(count: 0, onTap: () {})));
    expect(find.text('3 running tasks'), findsOneWidget);
    expect(find.textContaining('0 running'), findsNothing);

    await tester.pumpWidget(host(RunningTasksBubble(count: 2, onTap: () {})));
    expect(find.text('2 running tasks'), findsOneWidget);
  });

  testWidgets('reads one running task in the singular and several in the plural', (tester) async {
    await tester.pumpWidget(host(RunningTasksBubble(count: 1, onTap: () {})));
    expect(find.text('1 running task'), findsOneWidget);

    await tester.pumpWidget(host(RunningTasksBubble(count: 3, onTap: () {})));
    expect(find.text('3 running tasks'), findsOneWidget);
  });

  testWidgets('is a 36pt capsule of elevated fill and a subtle hairline, with the label in the link colour', (tester) async {
    await tester.pumpWidget(host(RunningTasksBubble(count: 2, onTap: () {})));

    const skin = DarkSkin();
    final capsule = find.byKey(RunningTasksBubble.capsuleKey);
    expect(tester.getSize(capsule).height, 36);
    final decoration = tester.widget<Container>(capsule).decoration! as ShapeDecoration;
    expect(decoration.color, skin.bgElevated.withValues(alpha: 0.6));
    final shape = decoration.shape as StadiumBorder;
    expect(shape.side.color, skin.borderSubtle);
    final label = tester.widget<Text>(find.text('2 running tasks'));
    expect(label.style?.color, skin.blue);
    expect(label.style?.fontSize, 15);
    expect(tester.getSize(find.byType(RunningTasksAsterisk)), const Size(18, 18));
    final gap = tester.getTopLeft(find.text('2 running tasks')).dx - tester.getTopRight(find.byType(RunningTasksAsterisk)).dx;
    expect(gap, 8);
    expect(tester.getTopLeft(find.byType(RunningTasksAsterisk)).dx - tester.getTopLeft(capsule).dx, closeTo(14, 0.5));
  });

  testWidgets('a tap fires a selection haptic and the callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(RunningTasksBubble(count: 2, onTap: () => taps++)));

    await tester.tap(find.byType(RunningTasksBubble));
    await tester.pump(AppMotion.fast);

    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('is one button labelled with the count and what it opens', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(RunningTasksBubble(count: 3, onTap: () {})));

    final node = tester.getSemantics(find.byType(RunningTasksBubble));
    expect(node.label, '3 running tasks, show background tasks');
    expect(node.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('the asterisk turns once every six seconds', (tester) async {
    await tester.pumpWidget(host(RunningTasksBubble(count: 1, onTap: () {})));

    double turns() => tester.widget<RotationTransition>(
      find.descendant(of: find.byType(RunningTasksAsterisk), matching: find.byType(RotationTransition)),
    ).turns.value;

    final start = turns();
    await tester.pump(AppMotion.runningTasksSpin ~/ 4);
    expect(turns() - start, closeTo(0.25, 0.01));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('the asterisk holds still under reduce motion', (tester) async {
    await tester.pumpWidget(host(RunningTasksBubble(count: 1, onTap: () {}), reduceMotion: true));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the asterisk holds still while TickerMode is off', (tester) async {
    AnimationController spin() => tester.widget<RotationTransition>(
      find.descendant(of: find.byType(RunningTasksAsterisk), matching: find.byType(RotationTransition)),
    ).turns as AnimationController;

    await tester.pumpWidget(host(TickerMode(enabled: false, child: RunningTasksBubble(count: 1, onTap: () {}))));
    await tester.pump(const Duration(seconds: 1));
    expect(spin().isAnimating, isFalse);
    expect(spin().value, 0);

    await tester.pumpWidget(host(TickerMode(enabled: true, child: RunningTasksBubble(count: 1, onTap: () {}))));
    await tester.pump(AppMotion.runningTasksSpin ~/ 4);
    expect(spin().isAnimating, isTrue);

    await tester.pumpWidget(host(TickerMode(enabled: false, child: RunningTasksBubble(count: 1, onTap: () {}))));
    final held = spin().value;
    await tester.pump(const Duration(seconds: 1));
    expect(spin().isAnimating, isFalse);
    expect(spin().value, held);
  });
}
