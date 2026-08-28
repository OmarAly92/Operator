import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_find_bar.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController queryController,
  required ValueChanged<String> onQueryChanged,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
  required VoidCallback onClose,
  required ValueChanged<bool> onToggleFilter,
  required int currentIndex,
  required int totalMatches,
  required bool filtering,
  required int hiddenCount,
}) => tester.pumpWidget(
  SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: BlockFindBar(
              queryController: queryController,
              onQueryChanged: onQueryChanged,
              onNext: onNext,
              onPrevious: onPrevious,
              onClose: onClose,
              onToggleFilter: onToggleFilter,
              currentIndex: currentIndex,
              totalMatches: totalMatches,
              filtering: filtering,
              hiddenCount: hiddenCount,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('typing into the field updates the controller', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      queryController: controller,
      onQueryChanged: (_) {},
      onNext: () {},
      onPrevious: () {},
      onClose: () {},
      onToggleFilter: (_) {},
      currentIndex: 0,
      totalMatches: 0,
      filtering: false,
      hiddenCount: 0,
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'foo');
    await tester.pump();

    expect(controller.text, 'foo');
    expect(find.byType(BlockFindBar), findsOneWidget);
  });

  testWidgets('counter shows current index over total matches', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      queryController: controller,
      onQueryChanged: (_) {},
      onNext: () {},
      onPrevious: () {},
      onClose: () {},
      onToggleFilter: (_) {},
      currentIndex: 2,
      totalMatches: 5,
      filtering: false,
      hiddenCount: 0,
    );
    await tester.pump();

    expect(find.text('2/5'), findsOneWidget);
  });

  testWidgets('next and previous buttons invoke their callbacks', (tester) async {
    final controller = TextEditingController();
    var nextCalls = 0;
    var prevCalls = 0;
    addTearDown(controller.dispose);

    await _pump(
      tester,
      queryController: controller,
      onQueryChanged: (_) {},
      onNext: () => nextCalls++,
      onPrevious: () => prevCalls++,
      onClose: () {},
      onToggleFilter: (_) {},
      currentIndex: 2,
      totalMatches: 3,
      filtering: false,
      hiddenCount: 0,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(prevCalls, 1);

    await tester.tap(find.byIcon(Icons.arrow_downward));
    await tester.pump();
    expect(nextCalls, 1);
  });

  testWidgets('close button invokes the close callback', (tester) async {
    final controller = TextEditingController();
    var closed = false;
    addTearDown(controller.dispose);

    await _pump(
      tester,
      queryController: controller,
      onQueryChanged: (_) {},
      onNext: () {},
      onPrevious: () {},
      onClose: () => closed = true,
      onToggleFilter: (_) {},
      currentIndex: 0,
      totalMatches: 0,
      filtering: false,
      hiddenCount: 0,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('filter toggle reflects on/off state', (tester) async {
    final controller = TextEditingController();
    final toggles = <bool>[];
    addTearDown(controller.dispose);

    await _pump(
      tester,
      queryController: controller,
      onQueryChanged: (_) {},
      onNext: () {},
      onPrevious: () {},
      onClose: () {},
      onToggleFilter: (value) => toggles.add(value),
      currentIndex: 0,
      totalMatches: 0,
      filtering: false,
      hiddenCount: 0,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pump();
    expect(toggles, [true]);
  });
}
