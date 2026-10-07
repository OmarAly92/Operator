import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

class _Center extends SingleChildLayoutDelegate {
  const _Center();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(((size.width - childSize.width) / 2).roundToDouble(), ((size.height - childSize.height) / 2).roundToDouble());

  @override
  bool shouldRelayout(_Center oldDelegate) => false;
}

class _Merge extends StatefulWidget {
  const _Merge();

  @override
  State<_Merge> createState() => _MergeState();
}

class _MergeState extends State<_Merge> {
  bool merged = false;

  void set(bool value, {bool animated = true}) {
    if (animated) {
      withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => merged = value));
    } else {
      setState(() => merged = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: const _Center(),
                child: GlassEffectContainer(
                  spacing: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GlassEffect(key: ValueKey('left'), shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
                      SizedBox(width: merged ? 0 : 80),
                      const GlassEffect(key: ValueKey('right'), shape: GlassShape.circle(), child: SizedBox.square(dimension: 80)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

GlassMember _member(WidgetTester tester, String key) => tester
    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
    .member;

Rect _onScreen(GlassMember member) => MatrixUtils.transformRect(member.coordinator.space!.getTransformTo(null), member.drawn!);

void main() {
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  testWidgets('both circles report that they moved in the frame the container shrinks and re-centres, and once only', (tester) async {
    await tester.pumpWidget(const _Merge());
    await tester.pump(const Duration(seconds: 1));
    final left = _member(tester, 'left'), right = _member(tester, 'right');
    expect(left.syncMoved(), isFalse);
    expect(right.syncMoved(), isFalse);
    final oldLeft = _onScreen(left), oldRight = _onScreen(right);
    tester.state<_MergeState>(find.byType(_Merge)).set(true);
    await tester.pump();
    expect(left.syncMoved(), isTrue);
    expect(right.syncMoved(), isTrue);
    expect(left.syncMoved(), isFalse);
    expect(right.syncMoved(), isFalse);
    expect(_onScreen(left), oldLeft);
    expect(_onScreen(right), oldRight);
    await tester.pump(const Duration(milliseconds: 16));
    expect(left.syncMoved(), isFalse);
    expect(right.syncMoved(), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('a move without an animation is reported as well, so the geometry never lags the layout by a frame', (tester) async {
    await tester.pumpWidget(const _Merge());
    await tester.pump(const Duration(seconds: 1));
    final left = _member(tester, 'left'), right = _member(tester, 'right');
    tester.state<_MergeState>(find.byType(_Merge)).set(true, animated: false);
    await tester.pump();
    expect(left.syncMoved(), isTrue);
    expect(right.syncMoved(), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('a member reads as unmoved when only the container around it changes size', (tester) async {
    await tester.pumpWidget(const _Merge());
    await tester.pump(const Duration(seconds: 1));
    final left = _member(tester, 'left');
    expect(left.syncMoved(), isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(left.syncMoved(), isFalse);
  });
}
