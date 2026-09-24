import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';

void main() {
  testWidgets('does not intercept taps on content below it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const LightSkin(),
          child: Stack(
            children: [
              Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.orange))),
              const Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120)),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 40));
    expect(taps, 1);
    expect(tester.getSize(find.byType(ScrollEdgeEffect)).height, 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the fallback with no exception once settled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const LightSkin(),
          child: const Stack(
            children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
