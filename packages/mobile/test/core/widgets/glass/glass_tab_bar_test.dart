import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar_logic.dart';

const _items = [
  GlassTabItem(icon: Icons.layers_outlined, label: 'Agents'),
  GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
  GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final haptics = <MethodCall>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host({
    required int selected,
    required ValueChanged<int> onSelected,
    double textScale = 1,
    bool reduceMotion = false,
  }) =>
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
            child: SkinScope(
              skin: const LightSkin(),
              child: Material(
                child: Center(
                  child: SizedBox(
                    width: 360,
                    child: GlassTabBar(items: _items, selectedIndex: selected, onSelected: onSelected),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('tapping an item selects it with a haptic', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    await tester.tap(find.text('PRs'));
    await tester.pumpAndSettle();
    expect(picked, [1]);
    expect(haptics, hasLength(1));
  });

  testWidgets('tapping the selected item reports it once per tap', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(picked, [0, 0]);
  });

  testWidgets('dragging across and releasing selects the slot under the finger', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, [2]);
  });

  testWidgets('a cancelled drag selects nothing and the droplet returns home', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final home = tester.getCenter(find.byKey(GlassTabBar.dropletKey));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(tester.getCenter(find.byKey(GlassTabBar.dropletKey)).dx, closeTo(home.dx, 0.5));
  });

  testWidgets('a second pointer during a drag does not double-select or steal the droplet', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final g1 = await tester.startGesture(tester.getCenter(find.text('Agents')), pointer: 1);
    await tester.pump();
    await g1.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    final g2 = await tester.startGesture(tester.getCenter(find.text('PRs')), pointer: 2);
    await tester.pump();
    await g2.up();
    await tester.pump();
    expect(picked, isEmpty);
    await g1.up();
    await tester.pumpAndSettle();
    expect(picked, [2]);
  });

  testWidgets('reduce motion drags without lift or stretch', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}, reduceMotion: true));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    final body = tester.getRect(find.byKey(GlassTabBar.dropletBodyKey));
    expect(body.height, closeTo(GlassMetrics.tabBarHeight - GlassMetrics.dropletInset * 2, 0.01));
    expect(body.width, closeTo(GlassTabBarLogic.pillWidth(360, 3), 0.01));
    expect(find.byType(DecoratedBox), findsWidgets);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a screen reader tap selects the item', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final handle = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel('PRs'));
    await tester.pumpAndSettle();
    expect(picked, [1]);
    expect(haptics, hasLength(1));
    handle.dispose();
  });

  testWidgets('large text does not overflow', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}, textScale: 2));
    expect(tester.takeException(), isNull);
    for (final item in _items) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(item.label));
      final contentHeight = GlassMetrics.tabGlyph + 1 + paragraph.size.height;
      expect(contentHeight, lessThanOrEqualTo(GlassMetrics.tabBarHeight));
    }
  });

  testWidgets('releasing far above the bar selects nothing', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final gesture = await tester.startGesture(tester.getCenter(find.text('PRs')));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(haptics, isEmpty);
  });

  testWidgets('releasing just above the bar still selects', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final gesture = await tester.startGesture(tester.getCenter(find.text('PRs')));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, [1]);
  });

  testWidgets('holding lifts the bar and turns the pill into a wider, taller lens', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}));
    final restBar = tester.getRect(find.byType(GlassTabBar));
    final restPill = tester.getRect(find.byKey(GlassTabBar.dropletBodyKey));
    final gesture = await tester.startGesture(tester.getCenter(find.text('PRs')));
    await tester.pumpAndSettle();
    final lens = tester.getRect(find.byKey(GlassTabBar.dropletBodyKey));
    expect(lens.width, closeTo(restPill.width * GlassTabBar.lensWidthScale * GlassTabBar.pressScale, 0.5));
    expect(lens.height, closeTo(restBar.height * GlassTabBar.lensHeightScale * GlassTabBar.pressScale, 0.5));
    expect(lens.center.dx, closeTo(tester.getCenter(find.byType(GlassTabBar)).dx, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the item under the lens is magnified and the others only grow with the bar', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}));
    final restPrs = tester.getSize(find.text('PRs'));
    final restAgents = tester.getRect(find.text('Agents'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('PRs')));
    await tester.pumpAndSettle();
    final heldPrs = tester.getRect(find.text('PRs'));
    final heldAgents = tester.getRect(find.text('Agents'));
    expect(heldPrs.width / restPrs.width, closeTo(GlassTabBar.pressScale * GlassTabBar.lensMagnify, 0.02));
    expect(heldAgents.width / restAgents.width, closeTo(GlassTabBar.pressScale, 0.02));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('releasing settles the lens back into the flat pill', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pump(GlassTabBar.minLift);
    await tester.pumpAndSettle();
    final pill = tester.getRect(find.byKey(GlassTabBar.dropletBodyKey));
    expect(pill.height, closeTo(GlassMetrics.tabBarHeight - GlassMetrics.dropletInset * 2, 0.01));
    expect(tester.getSize(find.byType(GlassTabBar)).width, 360);
  });

  testWidgets('a quick tap keeps the lens lifted for the minimum lift, then lands', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}));
    final restPill = tester.getRect(find.byKey(GlassTabBar.dropletBodyKey));
    final gesture = await tester.startGesture(tester.getCenter(find.text('PRs')));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(GlassTabBar.minLift ~/ 2);
    expect(tester.getRect(find.byKey(GlassTabBar.dropletBodyKey)).height, greaterThan(restPill.height));
    await tester.pump(GlassTabBar.minLift);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(GlassTabBar.dropletBodyKey)).height, closeTo(restPill.height, 0.01));
  });
}
