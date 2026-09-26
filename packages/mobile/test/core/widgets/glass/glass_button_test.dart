import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

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

  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: SkinScope(skin: const LightSkin(), child: Center(child: child)),
          ),
        ),
      );

  double scaleOf(WidgetTester tester) => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('tap fires haptic then onPressed once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () => taps++)));
    await tester.tap(find.byType(GlassButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(haptics, hasLength(1));
  });

  testWidgets('press scales up and release returns to rest', (tester) async {
    await tester.pumpWidget(host(GlassButton.label(label: 'Edit', onPressed: () {})));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), GlassSurface.pressedScale);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('cancel returns to rest without calling onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () => taps++)));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
    expect(taps, 0);
  });

  testWidgets('disabled button neither animates nor fires haptics', (tester) async {
    await tester.pumpWidget(host(const GlassButton.icon(icon: Icons.add, onPressed: null)));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
  });

  testWidgets('reduce motion keeps scale at rest', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {}), reduceMotion: true));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
  });

  testWidgets('disabled button renders no GlassGlow', (tester) async {
    await tester.pumpWidget(host(const GlassButton.icon(icon: Icons.add, onPressed: null)));
    expect(find.byType(GlassGlow), findsNothing);
  });

  testWidgets('enabled button renders a GlassGlow', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {})));
    expect(find.byType(GlassGlow), findsOneWidget);
  });

  testWidgets('meets the 44pt minimum hit target', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {})));
    final size = tester.getSize(find.byType(GlassButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('disabling mid-press releases the pressed scale', (tester) async {
    VoidCallback? onPressed = () {};
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => GlassButton.icon(
            icon: Icons.add,
            onPressed: onPressed,
            semanticLabel: 'action',
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), GlassSurface.pressedScale);
    onPressed = null;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => GlassButton.icon(
            icon: Icons.add,
            onPressed: onPressed,
            semanticLabel: 'action',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
  });

  testWidgets('compact label button keeps a 44pt hit target with a 36pt capsule', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(GlassButton.label(label: 'Run', compact: true, onPressed: () => taps++)),
    );
    final buttonSize = tester.getSize(find.byType(GlassButton));
    expect(buttonSize.height, greaterThanOrEqualTo(44));
    final surfaceSize = tester.getSize(find.byType(GlassSurface));
    expect(surfaceSize.height, 36);
    final buttonCenter = tester.getCenter(find.byType(GlassButton));
    final marginPoint = Offset(buttonCenter.dx, buttonCenter.dy + (surfaceSize.height / 2) + 2);
    await tester.tapAt(marginPoint);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('an icon button takes an explicit foreground colour', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, foreground: const Color(0xFF123456), onPressed: () {})));
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).color, const Color(0xFF123456));
  });

  testWidgets('an icon button with no diameter is still 44', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {})));
    final size = tester.getSize(find.byType(GlassButton));
    expect(size, const Size(44, 44));
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).size, 22);
  });

  testWidgets('an icon button with a smaller diameter shrinks the circle and the glyph', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, diameter: 38, onPressed: () {})));
    final size = tester.getSize(find.byType(GlassButton));
    expect(size, const Size(38, 38));
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).size, 19);
    final surfaceSize = tester.getSize(find.byType(GlassSurface));
    expect(surfaceSize, const Size(38, 38));
  });
}
