import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/frosted_header.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

void main() {
  void phone(WidgetTester tester, {double keyboard = 0}) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
  }

  Widget host(AppSkin skin, void Function(BuildContext context) open) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(onPressed: () => open(context), child: const Text('Open')),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> rows(List<String> labels, BuildContext context) => [
        for (final label in labels)
          ListTile(title: Text(label), onTap: () => Navigator.of(context).pop(label)),
      ];

  AppSheetPage fruitPage({String? searchHint}) => AppSheetPage(
        title: 'Fruit',
        subtitle: 'Pick one.',
        searchHint: searchHint,
        emptyText: 'Nothing to pick.',
        rows: (context, query) => rows(
          ['Apple', 'Banana', 'Cherry'].where((f) => f.toLowerCase().contains(query.toLowerCase())).toList(),
          context,
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the surface is opaque bgSurface, floats 8pt in and has a grabber and a centred title', (tester) async {
    phone(tester);
    await tester.pumpWidget(host(const LightSkin(), (context) => showAppSheet<String>(context: context, page: fruitPage())));
    await open(tester);

    final surface = tester.getRect(find.byKey(AppSheet.surfaceKey));
    expect(surface.left, 8);
    expect(surface.right, 402 - 8);
    expect(surface.bottom, moreOrLessEquals(874 - 8, epsilon: 0.5));
    final decoration = tester.widget<DecoratedBox>(find.byKey(AppSheet.surfaceKey)).decoration as ShapeDecoration;
    expect(decoration.color, const LightSkin().bgSurface);
    expect(find.descendant(of: find.byKey(AppSheet.surfaceKey), matching: find.byType(GlassSheetChrome)), findsNothing);
    expect(find.byKey(AppSheet.grabberKey), findsOneWidget);
    expect(tester.getCenter(find.text('Fruit')).dx, moreOrLessEquals(201, epsilon: 1));
    expect(find.byKey(AppSheet.backKey), findsNothing);
  });

  testWidgets('the barrier is the fitted glass-sheet dim', (tester) async {
    phone(tester);
    await tester.pumpWidget(host(const DarkSkin(), (context) => showAppSheet<String>(context: context, page: fruitPage())));
    await open(tester);
    final route = ModalRoute.of(tester.element(find.text('Fruit')))!;
    expect(route.barrierColor, GlassSheetLogic.barrierColor(const DarkSkin()));
  });

  testWidgets('a row closes the sheet with its value', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => picked = await showAppSheet<String>(context: context, page: fruitPage())),
    );
    await open(tester);
    await tester.tap(find.text('Banana'));
    await tester.pumpAndSettle();
    expect(picked, 'Banana');
    expect(find.byKey(AppSheet.surfaceKey), findsNothing);
  });

  testWidgets('fit sizes to the content and large takes 0.92 of the screen', (tester) async {
    phone(tester);
    await tester.pumpWidget(host(const LightSkin(), (context) => showAppSheet<String>(context: context, page: fruitPage())));
    await open(tester);
    expect(tester.getSize(find.byKey(AppSheet.surfaceKey)).height, lessThan(874 * 0.55));

    Navigator.of(tester.element(find.text('Fruit'))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(context: context, page: fruitPage(), detent: AppSheetDetent.large),
      ),
    );
    await open(tester);
    expect(tester.getSize(find.byKey(AppSheet.surfaceKey)).height, moreOrLessEquals(874 * 0.92 > 874 - 62 - 16 ? 874 - 62 - 16 : 874 * 0.92, epsilon: 0.5));
  });

  testWidgets('a large sheet shrinks to stay between the status bar and the keyboard', (tester) async {
    phone(tester, keyboard: 300);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(context: context, page: fruitPage(searchHint: 'Search fruit'), detent: AppSheetDetent.large),
      ),
    );
    await open(tester);
    final surface = tester.getRect(find.byKey(AppSheet.surfaceKey));
    expect(surface.height, moreOrLessEquals(874 - 300 - 62 - 16, epsilon: 0.5));
    expect(surface.bottom, moreOrLessEquals(874 - 300 - 8, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters the rows, shows No matches, and a filtered pick returns that row', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showAppSheet<String>(
          context: context,
          page: fruitPage(searchHint: 'Search fruit'),
          detent: AppSheetDetent.large,
        ),
      ),
    );
    await open(tester);
    expect(find.text('Search fruit'), findsOneWidget);
    expect(find.ancestor(of: find.byKey(AppSheet.searchFieldKey), matching: find.byType(GlassSurface)), findsOneWidget);

    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'CHER');
    await tester.pumpAndSettle();
    expect(find.text('Apple'), findsNothing);
    await tester.tap(find.text('Cherry'));
    await tester.pumpAndSettle();
    expect(picked, 'Cherry');
  });

  testWidgets('an empty page shows its empty text, not No matches', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(title: 'Empty', emptyText: 'Nothing to pick.', rows: (context, query) => const []),
        ),
      ),
    );
    await open(tester);
    expect(find.text('Nothing to pick.'), findsOneWidget);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('the first row starts below the header and the last clears the search capsule', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Many',
            searchHint: 'Search',
            rows: (context, query) => [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('Row $i'))],
          ),
          detent: AppSheetDetent.large,
        ),
      ),
    );
    await open(tester);
    final title = tester.getRect(find.text('Many'));
    expect(tester.getRect(find.text('Row 0')).top, greaterThan(title.bottom));
    await tester.dragUntilVisible(find.text('Row 39'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final capsule = tester.getRect(find.ancestor(of: find.byKey(AppSheet.searchFieldKey), matching: find.byType(GlassSurface)));
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(tester.getRect(find.text('Row 39')).bottom, lessThanOrEqualTo(capsule.top));
  });

  testWidgets('push shows a back button and the pushed title; pop returns to working root rows', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Root',
            rows: (context, query) => [
              ListTile(title: const Text('Go deeper'), onTap: () => AppSheet.of(context).push(fruitPage(searchHint: 'Search fruit'))),
              ListTile(title: const Text('Root pick'), onTap: () => Navigator.of(context).pop('root')),
            ],
          ),
          detent: AppSheetDetent.large,
        ),
      ),
    );
    await open(tester);
    await tester.tap(find.text('Go deeper'));
    await tester.pumpAndSettle();
    expect(find.text('Fruit'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsOneWidget);
    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'app');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsNothing);

    await tester.tap(find.text('Go deeper'));
    await tester.pumpAndSettle();
    expect(find.text('Banana'), findsOneWidget);
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Root pick'));
    await tester.pumpAndSettle();
    expect(picked, 'root');
  });

  testWidgets('a sheet can open with a page already pushed, and close returns a result', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showAppSheet<String>(
          context: context,
          page: AppSheetPage(title: 'Root', rows: (context, query) => const [Text('root row')]),
          pushed: [
            AppSheetPage(
              title: 'Deep',
              rows: (context, query) => [
                ListTile(title: const Text('Finish'), onTap: () => AppSheet.of(context).close('done')),
              ],
            ),
          ],
        ),
      ),
    );
    await open(tester);
    expect(find.text('Deep'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(picked, 'done');
  });

  testWidgets('actions sit in glass items in the header', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Root',
            actions: [TextButton(onPressed: () {}, child: const Text('Done'))],
            rows: (context, query) => const [Text('row')],
          ),
        ),
      ),
    );
    await open(tester);
    expect(find.ancestor(of: find.text('Done'), matching: find.byType(FrostedCapsule)), findsOneWidget);
  });

  testWidgets('a long title at text scale 2 ellipsizes between the back button and the actions', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(title: 'Root', rows: (context, query) => const [Text('row')]),
          pushed: [
            AppSheetPage(
              title: 'A remarkably long sheet title that cannot fit',
              actions: [TextButton(onPressed: () {}, child: const Text('Done'))],
              rows: (context, query) => const [Text('row')],
            ),
          ],
        ),
      ),
    );
    await open(tester);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.textContaining('A remarkably long'));
    expect(title.left, greaterThanOrEqualTo(tester.getRect(find.byKey(AppSheet.backKey)).right));
    expect(title.right, lessThanOrEqualTo(tester.getRect(find.byType(FrostedCapsule)).left));
  });

  test('detents and clamps', () {
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.fit, 874), isNull);
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.medium, 874), moreOrLessEquals(480.7));
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.large, 874), moreOrLessEquals(804.08));
    expect(AppSheetLogic.maxHeight(available: 874, topSafe: 62), 796);
    expect(AppSheetLogic.maxHeight(available: 10, topSafe: 62), 0);
    expect(AppSheetLogic.cornerRadius(), 56);
    expect(AppSheetLogic.topCornerRadius(), 44);
  });

  testWidgets('the back button is 38pt and a sheet action sits in a 38pt-tall frosted item, neither using the glass engine', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Root',
            actions: [TextButton(onPressed: () {}, child: const Text('Done'))],
            rows: (context, query) => [
              ListTile(title: const Text('Go deeper'), onTap: () => AppSheet.of(context).push(fruitPage())),
            ],
          ),
        ),
      ),
    );
    await open(tester);
    final actionItem = tester.getRect(find.ancestor(of: find.text('Done'), matching: find.byType(FrostedCapsule)));
    expect(actionItem.height, 38);
    expect(
      find.descendant(of: find.byType(FrostedCapsule), matching: find.byType(GlassSurface)),
      findsNothing,
    );

    await tester.tap(find.text('Go deeper'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(AppSheet.backKey)), const Size(38, 38));
    expect(
      find.descendant(of: find.byKey(AppSheet.backKey), matching: find.byType(GlassSurface)),
      findsNothing,
    );
  });

  testWidgets('the search field disables autocorrect and suggestions', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(context: context, page: fruitPage(searchHint: 'Search fruit')),
      ),
    );
    await open(tester);
    final field = tester.widget<TextField>(find.byKey(AppSheet.searchFieldKey));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  AppSheetPage manyPage({String title = 'Many', void Function(BuildContext context)? onFirst}) => AppSheetPage(
        title: title,
        rows: (context, query) => [
          for (var i = 0; i < 40; i++)
            SizedBox(
              height: 44,
              child: i == 0 && onFirst != null
                  ? TextButton(onPressed: () => onFirst(context), child: Text('$title row $i'))
                  : Text('$title row $i'),
            ),
        ],
      );

  Future<void> openMany(WidgetTester tester, {AppSheetPage? page}) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(context: context, page: page ?? manyPage(), detent: AppSheetDetent.large),
      ),
    );
    await open(tester);
  }

  ScrollPosition listPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable))).position;

  Future<void> scrollTo(WidgetTester tester, double offset) async {
    listPosition(tester).jumpTo(offset);
    await tester.pump();
  }

  Finder headerBlurs() => find.descendant(of: find.byKey(AppSheet.headerBarKey), matching: find.byType(BackdropFilter));

  AppSheetPage searchPage() => AppSheetPage(
        title: 'Many',
        searchHint: 'Search',
        rows: (context, query) => [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('Row $i'))],
      );

  BorderRadius sheetRadius() => BorderRadius.vertical(
        top: Radius.circular(AppSheetLogic.topCornerRadius()),
        bottom: Radius.circular(AppSheetLogic.cornerRadius()),
      );

  testWidgets('the surface layer clip saves a layer only while the header frosts', (tester) async {
    await openMany(tester, page: searchPage());
    ClipRSuperellipse layerClip() => tester.widget<ClipRSuperellipse>(find.byKey(AppSheet.layerClipKey));
    expect(layerClip().borderRadius, sheetRadius());
    expect(find.descendant(of: find.byKey(AppSheet.layerClipKey), matching: find.byKey(AppSheet.surfaceKey)), findsOneWidget);
    expect(find.descendant(of: find.byKey(AppSheet.surfaceKey), matching: find.byKey(AppSheet.headerBarKey)), findsOneWidget);
    expect(layerClip().clipBehavior, Clip.antiAlias);

    await scrollTo(tester, 4);
    expect(layerClip().clipBehavior, Clip.antiAliasWithSaveLayer);
    await scrollTo(tester, 40);
    expect(layerClip().clipBehavior, Clip.antiAliasWithSaveLayer);
    await scrollTo(tester, 0);
    expect(layerClip().clipBehavior, Clip.antiAlias);

    expect(AppSheetLogic.surfaceClip(0), Clip.antiAlias);
    expect(AppSheetLogic.surfaceClip(0.01), Clip.antiAliasWithSaveLayer);
  });

  testWidgets('the search capsule sits outside the save layer but under a rounded clip of the sheet shape', (tester) async {
    await openMany(tester, page: searchPage());
    expect(find.byKey(AppSheet.searchFieldKey), findsOneWidget);
    expect(find.descendant(of: find.byKey(AppSheet.layerClipKey), matching: find.byKey(AppSheet.searchFieldKey)), findsNothing);
    expect(find.descendant(of: find.byKey(AppSheet.outerClipKey), matching: find.byKey(AppSheet.searchFieldKey)), findsOneWidget);
    expect(find.descendant(of: find.byKey(AppSheet.outerClipKey), matching: find.byKey(AppSheet.layerClipKey)), findsOneWidget);
    final outer = tester.widget<ClipRSuperellipse>(find.byKey(AppSheet.outerClipKey));
    expect(outer.clipBehavior, Clip.antiAlias);
    expect(outer.borderRadius, sheetRadius());
    expect(tester.getRect(find.byKey(AppSheet.outerClipKey)), tester.getRect(find.byKey(AppSheet.surfaceKey)));
  });

  testWidgets('page content never paints in the grabber band at the top edge', (tester) async {
    await openMany(tester);
    final clip = tester.widget<ClipRect>(find.byKey(AppSheet.contentClipKey));
    final size = tester.getSize(find.byKey(AppSheet.contentClipKey));
    expect(clip.clipper!.getClip(size), Rect.fromLTRB(0, AppSheetMetrics.headerTop, size.width, size.height));
    expect(find.descendant(of: find.byKey(AppSheet.contentClipKey), matching: find.byType(ListView)), findsOneWidget);
  });

  testWidgets('at scroll offset 0 the header bar paints nothing', (tester) async {
    await openMany(tester);
    expect(find.byKey(AppSheet.headerBarKey), findsOneWidget);
    expect(headerBlurs(), findsNothing);
    expect(find.descendant(of: find.byKey(AppSheet.headerBarKey), matching: find.byType(ColoredBox)), findsNothing);
    expect(find.descendant(of: find.byKey(AppSheet.headerBarKey), matching: find.byType(DecoratedBox)), findsNothing);
  });

  testWidgets('the header bar fades in over the first 16pt of scroll and out again at the top', (tester) async {
    await openMany(tester);
    final skin = const LightSkin();

    await scrollTo(tester, 8);
    expect(tester.widget<BackdropFilter>(headerBlurs()).filter, FrostedMaterial.filter(0.5));
    final halfTints = tester
        .widgetList<ColoredBox>(find.descendant(of: find.byKey(AppSheet.headerBarKey), matching: find.byType(ColoredBox)))
        .toList();
    expect(halfTints.first.color.a, closeTo(0.225, 0.01));
    expect(halfTints.last.color.a, closeTo(FrostedMaterial.lightenAlpha / 2, 0.001));

    await scrollTo(tester, 40);
    expect(tester.widget<BackdropFilter>(headerBlurs()).filter, FrostedMaterial.filter());
    final tints = tester
        .widgetList<ColoredBox>(find.descendant(of: find.byKey(AppSheet.headerBarKey), matching: find.byType(ColoredBox)))
        .toList();
    expect(tints.first.color, skin.bgSurface.withValues(alpha: 0.45));
    expect(tints.last.color, skin.textPrimary.withValues(alpha: FrostedMaterial.lightenAlpha));

    await scrollTo(tester, 0);
    expect(headerBlurs(), findsNothing);
  });

  testWidgets('scrolled, the header bar is one full-width frosted material band with a hard bottom edge', (tester) async {
    await openMany(tester);
    await scrollTo(tester, 40);

    final headerBar = find.byKey(AppSheet.headerBarKey);
    final surface = tester.getRect(find.byKey(AppSheet.surfaceKey));
    final band = tester.getRect(headerBlurs());
    expect(band.width, surface.width);
    expect(band.top, surface.top);
    expect(band.height, AppSheetMetrics.contentTop);
    expect(find.descendant(of: headerBar, matching: find.byType(ClipRect)), findsOneWidget);
    expect(find.descendant(of: headerBar, matching: find.byType(ClipRSuperellipse)), findsNothing);
    expect(find.descendant(of: headerBar, matching: find.byType(ClipRRect)), findsNothing);
    expect(find.descendant(of: headerBar, matching: find.byType(ShaderMask)), findsNothing);
    expect(find.descendant(of: headerBar, matching: find.byType(DecoratedBox)), findsNothing);
    expect(find.descendant(of: headerBar, matching: find.byType(GlassSurface)), findsNothing);
  });

  test('the frosted material is a sigma 14 mirrored blur over a saturation boost', () {
    final filter = FrostedMaterial.filter();
    expect(filter, FrostedMaterial.filter(1));
    expect(filter.toString(), contains('14.0'));
    expect(filter.toString(), contains('mirror'));
    expect(FrostedMaterial.filter(0.5).toString(), contains('7.0'));
    expect(FrostedMaterial.blurSigma, 14);
    expect(FrostedMaterial.saturation, 1.7);
  });

  testWidgets('the header buttons share the material and frost only while content is under the header', (tester) async {
    await openMany(
      tester,
      page: AppSheetPage(
        title: 'Root',
        actions: [TextButton(onPressed: () {}, child: const Text('Done'))],
        rows: (context, query) => [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('Row $i'))],
      ),
    );
    Finder capsuleBlur() => find.descendant(of: find.byType(FrostedCapsule), matching: find.byType(BackdropFilter));
    expect(capsuleBlur(), findsNothing);

    await scrollTo(tester, 40);
    expect(tester.widget<BackdropFilter>(capsuleBlur()).filter, FrostedMaterial.filter());
    expect(tester.getRect(find.ancestor(of: find.text('Done'), matching: find.byType(FrostedCapsule))).height, 38);
  });

  testWidgets('a pushed page starts with the header bar hidden and popping follows the root list offset', (tester) async {
    await openMany(tester, page: manyPage(title: 'Root'));
    await scrollTo(tester, 40);
    expect(headerBlurs(), findsWidgets);

    AppSheet.of(tester.element(find.text('Root row 5'))).push(manyPage(title: 'Deep'));
    await tester.pumpAndSettle();
    expect(find.text('Deep'), findsOneWidget);
    expect(listPosition(tester).pixels, 0);
    expect(headerBlurs(), findsNothing);

    await scrollTo(tester, 40);
    expect(headerBlurs(), findsWidgets);

    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    final rootOffset = listPosition(tester).pixels;
    expect(headerBlurs(), AppSheetLogic.headerBarVisibility(rootOffset) > 0 ? findsWidgets : findsNothing);
  });

  testWidgets('push slides the old page out left and the new in from the right; pop mirrors it', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Root',
            rows: (context, query) => [
              ListTile(title: const Text('Go'), onTap: () => AppSheet.of(context).push(fruitPage())),
            ],
          ),
          detent: AppSheetDetent.large,
        ),
      ),
    );
    await open(tester);
    final rest = tester.getRect(find.text('Go')).left;

    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(find.text('Go')).left, lessThan(rest));
    expect(tester.getRect(find.text('Apple')).left, greaterThan(rest));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Apple')).left, moreOrLessEquals(rest));

    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(find.text('Apple')).left, greaterThan(rest));
    expect(tester.getRect(find.text('Go')).left, lessThan(rest));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Go')).left, moreOrLessEquals(rest));
  });

  testWidgets('a push fires no haptic and the back button fires one', (tester) async {
    final fired = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add(call);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<String>(
          context: context,
          page: AppSheetPage(
            title: 'Root',
            rows: (context, query) => [
              ListTile(title: const Text('Go'), onTap: () => AppSheet.of(context).push(fruitPage())),
            ],
          ),
        ),
      ),
    );
    await open(tester);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(fired, isEmpty);
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1));
  });
}
