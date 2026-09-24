import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/thinking_row.dart';

Widget _host({bool reduceMotion = false}) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: const Scaffold(body: ThinkingRow()),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows a shimmering Thinking label in textTertiary', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.descendant(of: find.byType(Shimmer), matching: find.byType(ShaderMask)), findsOneWidget);
    final text = tester.widget<Text>(find.text('Thinking'));
    expect(text.style?.color, const DarkSkin().textTertiary);
    expect(text.style?.fontSize, 13);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('the shimmer stops under reduce motion', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
