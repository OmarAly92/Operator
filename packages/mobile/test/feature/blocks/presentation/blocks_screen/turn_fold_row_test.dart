import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_fold_row.dart';

Widget _host(Widget child) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  ),
);

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

  testWidgets('shows the label with a chevron pointing right while folded', (tester) async {
    await tester.pumpWidget(_host(TurnFoldRow(label: 'Worked for 13s', expanded: false, onTap: () {})));

    expect(find.text('Worked for 13s'), findsOneWidget);
    final chevron = tester.widget<DisclosureChevron>(find.byType(DisclosureChevron));
    expect(chevron.expanded, isFalse);
    expect(chevron.collapsedTurns, -0.25);
    expect(chevron.expandedTurns, 0);
  });

  testWidgets('tapping toggles and fires a selection haptic', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(TurnFoldRow(label: 'Worked for 13s', expanded: false, onTap: () => taps++)));

    await tester.tap(find.text('Worked for 13s'));
    await tester.pump();

    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('announces itself as an expandable button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(TurnFoldRow(label: 'Worked for 13s', expanded: true, onTap: () {})));

    expect(
      tester.getSemantics(find.byType(TurnFoldRow)),
      matchesSemantics(
        label: 'Worked for 13s',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
