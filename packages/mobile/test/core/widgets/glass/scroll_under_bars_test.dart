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
    expect(find.text('content'), findsOneWidget);
  });
}
