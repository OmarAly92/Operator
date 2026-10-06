import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

void main() {
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

  Widget host(PreferredSizeWidget bar, {AppSkin skin = const LightSkin(), double textScale = 1}) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(appBar: bar, body: const SizedBox.expand()),
              ),
            ),
          ),
        ),
      );

  Widget pushingHost(PreferredSizeWidget bar) => SkinScope(
        skin: const LightSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: bar, body: const Text('Detail body'))),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

  Finder inBar(Finder matching) => find.descendant(of: find.byType(GlobalAppbar), matching: matching);

  testWidgets('renders no Material AppBar or BackButton', (tester) async {
    await tester.pumpWidget(host(const GlobalAppbar.sub(titleText: 'Detail')));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(inBar(find.byType(GlassButton)), findsOneWidget);
    expect(inBar(find.byType(GlassSurface)), findsWidgets);
  });

  testWidgets('the default back button pops the route with one haptic', (tester) async {
    await tester.pumpWidget(pushingHost(const GlobalAppbar.sub(titleText: 'Detail')));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Detail body'), findsOneWidget);
    await tester.tap(inBar(find.byType(GlassButton)));
    await tester.pumpAndSettle();
    expect(find.text('Detail body'), findsNothing);
    expect(haptics, hasLength(1));
  });

  testWidgets('onAppPopIconPressed replaces the pop and fires one haptic', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(GlobalAppbar.sub(titleText: 'Detail', onAppPopIconPressed: () => pressed++)));
    await tester.tap(inBar(find.byType(GlassButton)));
    await tester.pump();
    expect(pressed, 1);
    expect(haptics, hasLength(1));
  });

  testWidgets('every action sits in its own glass item', (tester) async {
    const iconKey = ValueKey('icon-action');
    const textKey = ValueKey('text-action');
    await tester.pumpWidget(
      host(
        GlobalAppbar.sub(
          titleText: 'Detail',
          actions: [
            IconButton(key: iconKey, onPressed: () {}, icon: const Icon(Icons.refresh, size: 18)),
            TextButton(key: textKey, onPressed: () {}, child: const Text('Mark all read')),
          ],
        ),
      ),
    );
    expect(find.ancestor(of: find.byKey(iconKey), matching: find.byType(GlassBarItem)), findsOneWidget);
    expect(find.ancestor(of: find.byKey(textKey), matching: find.byType(GlassBarItem)), findsOneWidget);
    final iconItem = find.ancestor(of: find.byKey(iconKey), matching: find.byType(GlassBarItem));
    expect(tester.getSize(iconItem), const Size(44, 44));
    final textItem = find.ancestor(of: find.byKey(textKey), matching: find.byType(GlassBarItem));
    expect(tester.getSize(textItem).height, 44);
    expect(tester.getSize(textItem).width, greaterThan(44));
  });

  testWidgets('an empty action list draws no glass item', (tester) async {
    await tester.pumpWidget(host(const GlobalAppbar.sub(titleText: 'Detail', actions: [])));
    expect(find.byType(GlassBarItem), findsNothing);
  });

  testWidgets('.main keeps its title on the left and .sub centres it', (tester) async {
    await tester.pumpWidget(host(const GlobalAppbar.main(titleText: 'Agents')));
    expect(tester.getRect(find.text('Agents')).left, 16);

    await tester.pumpWidget(host(const GlobalAppbar.sub(titleText: 'Detail')));
    final width = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getCenter(find.text('Detail')).dx, moreOrLessEquals(width / 2, epsilon: 1));
  });

  testWidgets('is 44 tall below the status bar', (tester) async {
    expect(const GlobalAppbar.main().preferredSize.height, 44);
    expect(const GlobalAppbar.sub().preferredSize.height, 44);
  });

  testWidgets('the status bar icons follow the skin', (tester) async {
    await tester.pumpWidget(host(const GlobalAppbar.main(titleText: 'Agents'), skin: const DarkSkin()));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('a long title at text scale 3 does not overflow or overlap the actions', (tester) async {
    await tester.pumpWidget(
      host(
        GlobalAppbar.sub(
          titleText: 'A very long pushed screen title that cannot possibly fit',
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
          ],
        ),
        textScale: 3,
      ),
    );
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.textContaining('A very long'));
    final firstAction = tester.getRect(find.byType(GlassBarItem).first);
    final back = tester.getRect(inBar(find.byType(GlassButton)));
    expect(title.right, lessThanOrEqualTo(firstAction.left));
    expect(title.left, greaterThanOrEqualTo(back.right));
  });

  testWidgets('a three-line custom title does not throw', (tester) async {
    await tester.pumpWidget(
      host(
        const GlobalAppbar.sub(
          centerTitle: false,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('↩ Parent', style: TextStyle(fontSize: 10)),
              Text('Agent title', style: TextStyle(fontSize: 15)),
              Text('general · opus · running', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Agent title'), findsOneWidget);
  });
}
