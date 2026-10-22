import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

Widget _app(GlassShape shape, VoidCallback onTap) => MaterialApp(
  home: Center(
    child: GlassEffect(
      glass: Glass.regular.interactive(),
      shape: shape,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(key: const Key('child'), padding: EdgeInsets.zero, onPressed: onTap, icon: const Icon(Icons.add)),
      ),
    ),
  ),
);

GlassMember _member(WidgetTester tester) =>
    tester.renderObjectList<RenderGlassMemberBox>(find.byType(GlassMemberBox)).single.member;

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  for (final entry in {'circle': const GlassShape.circle(), 'capsule': const GlassShape.capsule()}.entries) {
    group(entry.key, () {
      testWidgets('a child receives a tap in the bounding-box corner outside the shape', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_app(entry.value, () => taps++));
        await tester.pump(const Duration(seconds: 2));
        final rect = tester.getRect(find.byKey(const Key('child')));
        await tester.tapAt(rect.topLeft + const Offset(2, 2));
        await tester.pump();
        expect(taps, 1);
      });

      testWidgets('a child still receives a centre tap', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_app(entry.value, () => taps++));
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.byKey(const Key('child')));
        await tester.pump();
        expect(taps, 1);
      });

      testWidgets('the glass press starts inside the shape and not in the corner', (tester) async {
        await tester.pumpWidget(_app(entry.value, () {}));
        await tester.pump(const Duration(seconds: 2));
        final rect = tester.getRect(find.byKey(const Key('child')));
        final corner = await tester.startGesture(rect.topLeft + const Offset(2, 2));
        await tester.pump();
        expect(_member(tester).press.isPressed, isFalse);
        await corner.up();
        await tester.pump();
        final centre = await tester.startGesture(rect.center);
        await tester.pump();
        expect(_member(tester).press.isPressed, isTrue);
        await centre.up();
        await tester.pump();
      });
    });
  }
}
