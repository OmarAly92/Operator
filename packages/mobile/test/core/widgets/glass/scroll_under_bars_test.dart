import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_under_bars.dart';

void main() {
  testWidgets('puts a top edge fade over the child, sized to the bar inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 106)),
            child: const SkinScope(
              skin: LightSkin(),
              child: ScrollUnderBars(child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.edge, ScrollEdge.top);
    expect(effect.height, 140);
    expect(effect.capExtent, 106);
    expect(find.text('content'), findsOneWidget);
  });

  Future<ScrollController> pumpList(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const LightSkin(),
          child: ScrollUnderBars(
            child: ListView(
              controller: controller,
              children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i'))],
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  ScrollEdgeEffect topEffect(WidgetTester tester) => tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));

  Finder blur() => find.descendant(of: find.byType(ScrollEdgeEffect), matching: find.byType(BackdropFilter));

  testWidgets('at rest the top edge effect draws nothing', (tester) async {
    await pumpList(tester);
    expect(topEffect(tester).visibility, 0);
    expect(blur(), findsNothing);
  });

  testWidgets('the top edge effect fades in as content scrolls under it', (tester) async {
    final controller = await pumpList(tester);
    controller.jumpTo(8);
    await tester.pump();
    expect(topEffect(tester).visibility, 0.5);
    expect(blur(), findsOneWidget);
    controller.jumpTo(200);
    await tester.pump();
    expect(topEffect(tester).visibility, 1);
    controller.jumpTo(0);
    await tester.pump();
    expect(topEffect(tester).visibility, 0);
    expect(blur(), findsNothing);
  });

  testWidgets('a horizontal scroller inside does not drive the top edge effect', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const LightSkin(),
          child: ScrollUnderBars(
            child: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              children: [for (var i = 0; i < 60; i++) SizedBox(width: 80, child: Text('col $i'))],
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(200);
    await tester.pump();
    expect(topEffect(tester).visibility, 0);
  });
}
