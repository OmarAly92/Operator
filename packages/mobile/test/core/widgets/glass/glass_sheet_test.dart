import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';

class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.onInit, required this.height});

  final VoidCallback onInit;
  final double height;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: widget.height, child: const Text('Sheet'));
}

Widget _hostWithCounter(double childHeight, VoidCallback onInit) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: SkinScope(
          skin: const LightSkin(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassSheetChrome(child: _InitCounter(onInit: onInit, height: childHeight)),
          ),
        ),
      ),
    );

Widget _host(double childHeight) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: SkinScope(
          skin: const LightSkin(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassSheetChrome(child: SizedBox(height: childHeight, child: const Text('Sheet'))),
          ),
        ),
      ),
    );

void main() {
  test('floats below 90% of the screen and anchors above', () {
    expect(GlassSheetLogic.isFloating(sheetHeight: 437, screenHeight: 874), isTrue);
    expect(GlassSheetLogic.isFloating(sheetHeight: 800, screenHeight: 874), isFalse);
  });

  test('barrier dim is fitted per theme from native pixels', () {
    expect(GlassSheetLogic.barrierColor(const LightSkin()), const Color(0x33000000));
    expect(GlassSheetLogic.barrierColor(const DarkSkin()), const Color(0x79000000));
  });

  testWidgets('a half-height sheet floats as glass', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(400));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.floatingKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsNothing);
  });

  testWidgets('a full-height sheet anchors opaque', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(820));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.floatingKey), findsNothing);
  });

  testWidgets('body state survives the floating-to-anchored branch switch', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var initCount = 0;
    await tester.pumpWidget(_hostWithCounter(820, () => initCount++));
    expect(find.byKey(GlassSheetChrome.floatingKey), findsOneWidget);
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsOneWidget);
    expect(initCount, 1);
  });
}
