import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_toolbar.dart';

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MediaQuery(
          data: MediaQueryData(size: const Size(402, 874), padding: const EdgeInsets.only(top: 62), textScaler: TextScaler.linear(textScale)),
          child: SkinScope(skin: const LightSkin(), child: Material(child: Align(alignment: Alignment.topCenter, child: child))),
        ),
      ),
    );

GlassToolbar _toolbar() => GlassToolbar(
      leading: GlassButton.icon(icon: Icons.chevron_left, onPressed: () {}),
      title: 'Agents',
      trailing: [GlassButton.label(label: 'Edit', onPressed: () {})],
    );

void main() {
  testWidgets('lays out leading, centred title and trailing in one glass layer', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_toolbar()));
    expect(find.text('Agents'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    final title = tester.getCenter(find.text('Agents'));
    expect(title.dx, closeTo(201, 1));
    expect(tester.getTopLeft(find.byType(GlassButton).first).dy, greaterThanOrEqualTo(62));
  });

  testWidgets('large text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_toolbar(), textScale: 2));
    expect(tester.takeException(), isNull);

    final titleParagraph = tester.renderObject<RenderParagraph>(find.text('Agents'));
    expect(titleParagraph.textSize.height, lessThanOrEqualTo(GlassMetrics.hitTarget));

    final editParagraph = tester.renderObject<RenderParagraph>(find.text('Edit'));
    expect(editParagraph.textSize.height, lessThanOrEqualTo(GlassMetrics.hitTarget));
  });
}
