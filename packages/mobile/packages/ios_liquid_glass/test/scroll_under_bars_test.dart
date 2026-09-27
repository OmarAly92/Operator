import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  testWidgets('puts a top edge fade over the child, sized to the bar inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 106)),
            child: const GlassTheme(
              data: GlassThemeData(brightness: Brightness.light),
              child: ScrollUnderBars(child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.edge, ScrollEdge.top);
    expect(effect.style, ScrollEdgeStyle.automatic);
    expect(effect.height, 106 + ios27ScrollEdgeTable['light.automatic']!['extent']!);
    expect(effect.capExtent, 106);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('a soft style reaches further down than the automatic bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 62)),
            child: const GlassTheme(
              data: GlassThemeData(brightness: Brightness.dark),
              child: ScrollUnderBars(style: ScrollEdgeStyle.soft, child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.style, ScrollEdgeStyle.soft);
    expect(effect.height, 62 + ios27ScrollEdgeTable['dark.soft']!['extent']!);
    expect(effect.height, greaterThan(62 + ios27ScrollEdgeTable['dark.automatic']!['extent']!));
  });

  Future<ScrollController> pumpList(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
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
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
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
