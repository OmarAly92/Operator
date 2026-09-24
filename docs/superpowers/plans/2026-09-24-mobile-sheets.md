# Mobile Sheets (T3 design) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the floating-glass sheets with T3's design: an opaque floating sheet with a grabber, a centred-title header with glass buttons, a floating search capsule, and pages pushed inside the sheet. Use it for theme, project, connection-menu and Spawn sheets.

**Architecture:** A new `AppSheet` widget in `lib/core/widgets/sheet/` owns the surface, header, page stack, search field and detent sizing, and `showAppSheet` presents it through `showExpressiveSheet`. A page is data, `AppSheetPage`, with a title, a subtitle, actions, an optional search hint and a `builder(context, query)` that returns rows. Pickers become page factories that both single-page sheets and the multi-page Spawn sheet reuse.

**Tech Stack:** Flutter 3.44.5, Dart, the project-1 glass widgets (`GlassButton`, `GlassBarItem`, `GlassSurface`, `GlassMetrics`, `GlassSheetLogic`), `expressive_sheet`, flutter_bloc, flutter_test, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-24-mobile-sheets-design.md`. It revises part 4 of `docs/superpowers/specs/2026-09-24-mobile-glass-chrome-design.md`.

This plan continues the glass-chrome plan. That plan's Tasks 1–5 have landed. Its Task 6 (real-app verification) is folded into Task 11 here.

## Global Constraints

- Work only in the worktree `/Users/omaraly/development/AI/Operator-ios-polish`, branch `feat/mobile-ios-polish`. NEVER touch the main checkout `/Users/omaraly/development/AI/Operator`. Do not merge, push, rebase onto development, or open a PR.
- Write NO code comments in anything you author.
- Every commit message ends with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not edit these files: `terminal_chat_header.dart`, `session_card.dart`, `block_card.dart`, `block_list.dart`, `activity_string.dart`, `session_model.dart`, `turn_elapsed.dart`, `active_since.dart`, or their tests.
- `frontend/package-lock.json` is dirty and not yours. Stage only files you changed.
- Sheet surface: `skin.bgSurface`, opaque, never glass. It sits 8pt (`GlassMetrics.sheetInset`) in from the left, right and bottom at every height. Its corner is a `RoundedSuperellipseBorder` of radius 56 (`GlassMetrics.displayCornerRadius - GlassMetrics.sheetInset`). The barrier is `GlassSheetLogic.barrierColor(skin)`.
- Detents:
  - `fit`: sizes to the content, up to the large height
  - `medium`: 0.55 × screen height
  - `large`: 0.92 × screen height
  - All are clamped to `available − topSafe − 16`. `available` is the height the route gives, which is the screen minus the keyboard.
- Header: 44pt row. The centred title is `AppTextStyle.style17Bold`, one line. The glass back button appears only when a page is pushed. Actions are wrapped in `GlassBarItem`.
- Search capsule: glass, 48pt tall, 16pt from the sheet's sides and 12pt from its bottom. Matching is case-insensitive substring. An empty result for a non-empty query shows "No matches".
- User-facing copy is inline English. Colours come from `context.skin`.
- Selection haptics are unchanged: one `Haptics.select()` per pick.
- Gate for every task, from `packages/mobile`: `flutter analyze` prints `No issues found!`, and the full `flutter test` passes. Never weaken a test. A test of a deleted API is ported to the new API with the same assertions, named in the commit.

## Review Focus

1. **Keyboard under a tall sheet.** Typing in the search field or the rename field must not push the sheet above the status bar or overflow it. The detent clamps to the space above the keyboard. Task 7 pins it.
2. **Search, then pick.** Picking a row from a filtered list returns that row's value, not the value at the same index in the unfiltered list. Tasks 8 and 10 pin it.
3. **Back from a pushed page.** The root page's rows must still work after a push and a pop. The search query resets on push and pop. Task 7 pins it.
4. **Account row visibility in Spawn.** The Account row and page appear only when the agent is `claude-code` and accounts exist, as on the Spawn screen today. Task 10 pins it.
5. **A long title with actions.** The title ellipsizes and never overlaps the back button or the actions. Task 7 pins it at a text scale of 2.

---

### Task 7: `AppSheet` core

**Files:**
- Create: `packages/mobile/lib/core/widgets/sheet/app_sheet.dart`
- Test: `packages/mobile/test/core/widgets/sheet/app_sheet_test.dart`

**Interfaces:**
- Consumes: `GlassButton.icon(foreground:)`, `GlassBarItem`, `GlassSurface`, `GlassShapeKind`, `GlassMetrics`, `GlassSheetLogic.barrierColor`, `showExpressiveSheet`, `AppMotion`, `AppTextStyle`, `AppText`.
- Produces:
  - `enum AppSheetDetent { fit, medium, large }`
  - `typedef AppSheetRows = List<Widget> Function(BuildContext context, String query);`
  - `class AppSheetPage { const AppSheetPage({required String title, required AppSheetRows rows, String? subtitle, List<Widget> actions = const [], String? searchHint, String? emptyText}); }`
  - `class AppSheetController { int get depth; void push(AppSheetPage page); void pop(); void close<T>([T? result]); }`
  - `class AppSheet extends StatefulWidget { const AppSheet({Key? key, required AppSheetPage root, List<AppSheetPage> pushed = const [], AppSheetDetent detent = AppSheetDetent.fit}); static AppSheetController of(BuildContext context); static const Key surfaceKey, grabberKey, searchFieldKey, backKey; }`
  - `sealed class AppSheetLogic { static double? fixedHeight(AppSheetDetent detent, double screenHeight); static double maxHeight({required double available, required double topSafe}); static double cornerRadius(); }`
  - `Future<T?> showAppSheet<T>({required BuildContext context, required AppSheetPage page, List<AppSheetPage> pushed = const [], AppSheetDetent detent = AppSheetDetent.fit, Widget Function(BuildContext context, Widget sheet)? scope})`

  This task adds `showAppSheet` to the new file. The old `app_sheet_chrome.dart` (its own `showAppSheet` and `AppSheetChrome`) stays until Task 10 deletes it. Callers import one or the other, never both.

- [ ] **Step 1: Write the failing tests.** Create `test/core/widgets/sheet/app_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
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
    expect(surface.bottom, 874 - 8);
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
    await tester.dragUntilVisible(find.text('Row 39'), find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    final capsule = tester.getRect(find.ancestor(of: find.byKey(AppSheet.searchFieldKey), matching: find.byType(GlassSurface)));
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
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
    expect(find.ancestor(of: find.text('Done'), matching: find.byType(GlassBarItem)), findsOneWidget);
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
    expect(title.right, lessThanOrEqualTo(tester.getRect(find.byType(GlassBarItem)).left));
  });

  test('detents and clamps', () {
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.fit, 874), isNull);
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.medium, 874), moreOrLessEquals(480.7));
    expect(AppSheetLogic.fixedHeight(AppSheetDetent.large, 874), moreOrLessEquals(804.08));
    expect(AppSheetLogic.maxHeight(available: 874, topSafe: 62), 796);
    expect(AppSheetLogic.maxHeight(available: 10, topSafe: 62), 0);
    expect(AppSheetLogic.cornerRadius(), 56);
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
```

The last test expects exactly one haptic, from the back button: `GlassButton` fires `Haptics.tap()`. Pushing through a `ListTile` fires none.

The large-detent expectation in 'fit sizes to the content…' evaluates to `min(874 × 0.92, 874 − 62 − 16) = min(804.08, 796) = 796`.

- [ ] **Step 2: Run and watch it fail.** Run `cd packages/mobile && flutter test test/core/widgets/sheet/app_sheet_test.dart`. Expected: compile failure, because `app_sheet.dart` does not exist.

- [ ] **Step 3: Implement `lib/core/widgets/sheet/app_sheet.dart`.**

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

enum AppSheetDetent { fit, medium, large }

typedef AppSheetRows = List<Widget> Function(BuildContext context, String query);

class AppSheetPage {
  const AppSheetPage({
    required this.title,
    required this.rows,
    this.subtitle,
    this.actions = const [],
    this.searchHint,
    this.emptyText,
  });

  final String title;
  final AppSheetRows rows;
  final String? subtitle;
  final List<Widget> actions;
  final String? searchHint;
  final String? emptyText;
}

sealed class AppSheetMetrics {
  static const double grabberTop = 6;
  static const double grabberWidth = 36;
  static const double grabberHeight = 5;
  static const double headerTop = 15;
  static const double headerHeight = 44;
  static const double headerSide = 12;
  static const double contentTop = headerTop + headerHeight + 8;
  static const double contentSide = 16;
  static const double contentBottom = 16;
  static const double searchHeight = 48;
  static const double searchSide = 16;
  static const double searchBottom = 12;
  static const double mediumFraction = 0.55;
  static const double largeFraction = 0.92;
}

sealed class AppSheetLogic {
  static double? fixedHeight(AppSheetDetent detent, double screenHeight) => switch (detent) {
        AppSheetDetent.fit => null,
        AppSheetDetent.medium => screenHeight * AppSheetMetrics.mediumFraction,
        AppSheetDetent.large => screenHeight * AppSheetMetrics.largeFraction,
      };

  static double maxHeight({required double available, required double topSafe}) =>
      math.max(0, available - topSafe - GlassMetrics.sheetInset * 2);

  static double cornerRadius() => GlassMetrics.displayCornerRadius - GlassMetrics.sheetInset;

  static double bottomClearance({required bool hasSearch}) => hasSearch
      ? AppSheetMetrics.searchBottom + AppSheetMetrics.searchHeight + AppSheetMetrics.contentBottom
      : AppSheetMetrics.contentBottom;
}

class AppSheetController {
  AppSheetController._(this._state);

  final _AppSheetState _state;

  int get depth => _state._pages.length - 1;

  void push(AppSheetPage page) => _state._push(page);

  void pop() => _state._pop();

  void close<T>([T? result]) => Navigator.of(_state.context).pop<T>(result);
}

class _AppSheetScope extends InheritedWidget {
  const _AppSheetScope({required this.controller, required super.child});

  final AppSheetController controller;

  @override
  bool updateShouldNotify(_AppSheetScope oldWidget) => false;
}

class AppSheet extends StatefulWidget {
  const AppSheet({super.key, required this.root, this.pushed = const [], this.detent = AppSheetDetent.fit});

  static const Key surfaceKey = ValueKey('app-sheet-surface');
  static const Key grabberKey = ValueKey('app-sheet-grabber');
  static const Key searchFieldKey = ValueKey('app-sheet-search');
  static const Key backKey = ValueKey('app-sheet-back');

  final AppSheetPage root;
  final List<AppSheetPage> pushed;
  final AppSheetDetent detent;

  static AppSheetController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppSheetScope>()!.controller;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet> {
  late final List<AppSheetPage> _pages = [widget.root, ...widget.pushed];
  late final AppSheetController _controller = AppSheetController._(this);
  final TextEditingController _search = TextEditingController();
  bool _forward = true;

  void _push(AppSheetPage page) {
    setState(() {
      _forward = true;
      _pages.add(page);
      _search.clear();
    });
  }

  void _pop() {
    if (_pages.length < 2) return;
    setState(() {
      _forward = false;
      _pages.removeLast();
      _search.clear();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _content(AppSheetPage page, bool shrinkWrap) {
    final skin = context.skin;
    final bottom = AppSheetLogic.bottomClearance(hasSearch: page.searchHint != null);
    return ValueListenableBuilder<TextEditingValue>(
      key: ValueKey<int>(_pages.length),
      valueListenable: _search,
      builder: (context, value, _) {
        final query = value.text.trim();
        final rows = page.rows(context, query);
        final String? message = rows.isNotEmpty ? null : (query.isNotEmpty ? 'No matches' : page.emptyText);
        return ListView(
          shrinkWrap: shrinkWrap,
          padding: EdgeInsets.fromLTRB(
            AppSheetMetrics.contentSide,
            AppSheetMetrics.contentTop,
            AppSheetMetrics.contentSide,
            bottom,
          ),
          children: [
            if (page.subtitle != null) ...[
              AppText(
                page.subtitle!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
            ],
            ...rows,
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: AppText(
                  message,
                  style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                  maxLines: 3,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey<int>(_pages.length);
    final from = incoming == _forward ? const Offset(1, 0) : const Offset(-1, 0);
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(begin: from, end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }

  Widget _header(AppSheetPage page) {
    final skin = context.skin;
    return NavigationToolbar(
      leading: _pages.length > 1
          ? GlassButton.icon(
              key: AppSheet.backKey,
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: 'Back',
              foreground: skin.textPrimary,
              onPressed: _pop,
            )
          : null,
      middle: AppText(page.title, style: AppTextStyle.style17Bold, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: page.actions.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < page.actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                  GlassBarItem(child: page.actions[i]),
                ],
              ],
            ),
      middleSpacing: GlassMetrics.toolbarItemGap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final page = _pages.last;
    final radius = BorderRadius.all(Radius.circular(AppSheetLogic.cornerRadius()));
    return _AppSheetScope(
      controller: _controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = AppSheetLogic.maxHeight(available: constraints.maxHeight, topSafe: media.padding.top);
          final fixed = AppSheetLogic.fixedHeight(widget.detent, media.size.height);
          final height = fixed == null ? null : math.min(fixed, maxHeight);
          final switcher = AnimatedSwitcher(
            duration: AppMotion.base,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeOut,
            transitionBuilder: _transition,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: _content(page, height == null),
          );
          final stack = Stack(
            children: [
              if (height == null) switcher else Positioned.fill(child: switcher),
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: AppSheetMetrics.contentTop + 8,
                child: _HeaderFade(),
              ),
              Positioned(
                top: AppSheetMetrics.grabberTop,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    key: AppSheet.grabberKey,
                    width: AppSheetMetrics.grabberWidth,
                    height: AppSheetMetrics.grabberHeight,
                    decoration: BoxDecoration(
                      color: skin.borderStrong,
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: AppSheetMetrics.headerTop,
                left: AppSheetMetrics.headerSide,
                right: AppSheetMetrics.headerSide,
                height: AppSheetMetrics.headerHeight,
                child: _header(page),
              ),
              if (page.searchHint != null)
                Positioned(
                  left: AppSheetMetrics.searchSide,
                  right: AppSheetMetrics.searchSide,
                  bottom: AppSheetMetrics.searchBottom,
                  height: AppSheetMetrics.searchHeight,
                  child: _SearchCapsule(controller: _search, hint: page.searchHint!),
                ),
            ],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              GlassMetrics.sheetInset,
              0,
              GlassMetrics.sheetInset,
              GlassMetrics.sheetInset,
            ),
            child: DecoratedBox(
              key: AppSheet.surfaceKey,
              decoration: ShapeDecoration(
                color: skin.bgSurface,
                shape: RoundedSuperellipseBorder(borderRadius: radius),
              ),
              child: ClipRSuperellipse(
                borderRadius: radius,
                child: Material(
                  type: MaterialType.transparency,
                  child: AnimatedSize(
                    duration: AppMotion.base,
                    curve: AppMotion.easeOut,
                    alignment: Alignment.bottomCenter,
                    child: height == null
                        ? ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: stack)
                        : SizedBox(height: height, child: stack),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderFade extends StatelessWidget {
  const _HeaderFade();

  @override
  Widget build(BuildContext context) {
    final surface = context.skin.bgSurface;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              ).createShader(rect),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: const SizedBox.expand(),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [surface, surface.withValues(alpha: 0.85), surface.withValues(alpha: 0)],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCapsule extends StatelessWidget {
  const _SearchCapsule({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return GlassSurface(
      kind: GlassShapeKind.capsule,
      size: AppSheetMetrics.searchHeight,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search, size: 22, color: skin.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: AppSheet.searchFieldKey,
                controller: controller,
                textInputAction: TextInputAction.search,
                style: AppTextStyle.style17Regular.copyWith(color: skin.textPrimary),
                cursorColor: skin.accent,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: AppTextStyle.style17Regular.copyWith(color: skin.textTertiary),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required AppSheetPage page,
  List<AppSheetPage> pushed = const [],
  AppSheetDetent detent = AppSheetDetent.fit,
  Widget Function(BuildContext context, Widget sheet)? scope,
}) {
  return showExpressiveSheet<T>(
    context: context,
    barrierColor: GlassSheetLogic.barrierColor(context.skin),
    builder: (sheetContext) {
      final sheet = AppSheet(root: page, pushed: pushed, detent: detent);
      return scope == null ? sheet : scope(sheetContext, sheet);
    },
  );
}
```

Implementation notes:
- `?current` in the `layoutBuilder` is Dart's null-aware element. If the analyzer rejects it on this SDK, use `if (current != null) current`.
- If `AppMotion.easeOut` or `AppMotion.base` is named differently, read `lib/core/app_themes/app_motion.dart` and use the existing names.
- If `AppTextStyle.style17Regular` does not exist, use the closest 17pt regular style and state it in the report.

- [ ] **Step 4: Run the test file until it passes.** Where an expectation is off, print the measured value. Fix the code if it breaks the spec; fix the test only where the test misstates Flutter behaviour, and say so in the report with evidence.

- [ ] **Step 5: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/sheet/app_sheet.dart test/core/widgets/sheet/app_sheet_test.dart
git commit -m "feat(mobile): AppSheet with T3-style header, search capsule and page stack

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Picker filter, theme and project pickers on `AppSheet`

**Files:**
- Create: `packages/mobile/lib/core/widgets/pickers/picker_filter.dart`
- Rewrite: `packages/mobile/lib/core/widgets/pickers/theme_picker_sheet.dart`
- Rewrite: `packages/mobile/lib/core/widgets/pickers/project_picker_sheet.dart`
- Test: `packages/mobile/test/core/widgets/pickers/picker_filter_test.dart`
- Create test: `packages/mobile/test/core/widgets/pickers/project_picker_sheet_test.dart`
- Test (existing, must stay green unchanged): `packages/mobile/test/core/utils/haptics_call_sites_test.dart`

**Interfaces:**
- Consumes: `AppSheet`, `AppSheetPage`, `AppSheetDetent`, `showAppSheet` (Task 7).
- Produces:
  - `sealed class PickerFilter { static bool matches(String query, Iterable<String?> fields); }`
  - `AppSheetPage projectPickerPage({required List<ProjectModel> projects, required String selected, required void Function(BuildContext context, String id) onPicked, bool includeAll = true, String title = 'Active project', String subtitle = 'Scopes the Agents and PRs tabs.'})`. Search hint "Search projects"; matches name, id, session prefix; `emptyText` is the existing "No projects yet…" copy. The "All projects" row shows only while the query is empty.
  - `showProjectPickerSheet(...)` keeps its exact signature and return value, now as `showAppSheet<String>(page: projectPickerPage(..., onPicked: (context, id) => Navigator.of(context).pop(id)), detent: AppSheetDetent.large)`.
  - `showThemePickerSheet(context, {required ThemeMode selected})` keeps its signature. It uses one `fit` page titled "Theme" with subtitle "Applies across the app." and the same option rows.

- [ ] **Step 1: Write the failing filter test** `test/core/widgets/pickers/picker_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/pickers/picker_filter.dart';

void main() {
  test('an empty or blank query matches everything', () {
    expect(PickerFilter.matches('', ['x']), isTrue);
    expect(PickerFilter.matches('   ', [null]), isTrue);
  });

  test('matches a case-insensitive substring of any field, ignoring nulls', () {
    expect(PickerFilter.matches('OPER', ['Operator', null]), isTrue);
    expect(PickerFilter.matches('ops', [null, 'devops']), isTrue);
    expect(PickerFilter.matches(' tor ', ['Operator']), isTrue);
    expect(PickerFilter.matches('zzz', ['Operator', 'op']), isFalse);
  });
}
```

- [ ] **Step 2: Write the failing project picker test** `test/core/widgets/pickers/project_picker_sheet_test.dart`. Model the host on `test/core/widgets/sheet/app_sheet_test.dart`'s `phone` and `host` helpers (copy them):

```dart
  testWidgets('search narrows projects and a filtered pick returns that project id', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showProjectPickerSheet(
          context,
          projects: const [
            ProjectModel(id: 'p-web', name: 'Website', sessionPrefix: 'web'),
            ProjectModel(id: 'p-op', name: 'Operator', sessionPrefix: 'op'),
          ],
          selected: kAllProjects,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Active project'), findsOneWidget);
    expect(find.text('All projects'), findsOneWidget);
    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'oper');
    await tester.pumpAndSettle();
    expect(find.text('All projects'), findsNothing);
    expect(find.text('Website'), findsNothing);
    await tester.tap(find.text('Operator'));
    await tester.pumpAndSettle();
    expect(picked, 'p-op');
  });

  testWidgets('matches on the session prefix too', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showProjectPickerSheet(
          context,
          projects: const [
            ProjectModel(id: 'p-web', name: 'Website', sessionPrefix: 'web'),
            ProjectModel(id: 'p-op', name: 'Operator', sessionPrefix: 'op'),
          ],
          selected: 'p-web',
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'WEB');
    await tester.pumpAndSettle();
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Operator'), findsNothing);
  });

  testWidgets('the project picker opens as a large sheet', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(const LightSkin(), (context) => showProjectPickerSheet(context, projects: const [], selected: kAllProjects)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(AppSheet.surfaceKey)).height, moreOrLessEquals(796, epsilon: 0.5));
    expect(find.textContaining('No projects yet'), findsOneWidget);
  });
```

Check `ProjectModel`'s constructor (`lib/feature/sessions/data/model/project_model.dart`) and use its real field names. Import `kAllProjects` from `sessions_cubit.dart`, where the picker already gets it.

- [ ] **Step 3: Run and watch both fail** (compile failure: `picker_filter.dart` does not exist; no search field).

- [ ] **Step 4: Implement.**

`picker_filter.dart`:

```dart
sealed class PickerFilter {
  static bool matches(String query, Iterable<String?> fields) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return fields.any((field) => field != null && field.toLowerCase().contains(needle));
  }
}
```

In `project_picker_sheet.dart`:
- Keep `_ProjectOption` exactly as it is.
- Replace `showProjectPickerSheet` with `projectPickerPage` plus a `showProjectPickerSheet` that calls it. `rows: (context, query)` builds:
  - the "All projects" option when `includeAll && query.isEmpty`
  - then each project where `PickerFilter.matches(query, [project.name, project.id, project.sessionPrefix])`
- Each option's `onTap` does `Haptics.select();` then `onPicked(context, id)`.
- Do not put the "No projects" row in `rows`; that is `emptyText`.
- The title and subtitle move into the page's `title` and `subtitle`.
- Import `package:operator_mobile/core/widgets/sheet/app_sheet.dart` instead of `app_sheet_chrome.dart`.

In `theme_picker_sheet.dart`:
- Make one `AppSheetPage(title: 'Theme', subtitle: 'Applies across the app.', rows: ...)` returning the three `_ThemeOption`s unchanged.
- Present it with `showAppSheet<ThemeMode>(context: context, page: ...)`, detent `fit`.
- Import `app_sheet.dart` instead of `app_sheet_chrome.dart`.

`project_switcher.dart` and `settings_body.dart` call `showProjectPickerSheet` with an unchanged signature and need no edit.

- [ ] **Step 5: Run the new tests, `haptics_call_sites_test.dart` and `test/core/widgets/main_widgets/app_sheet_chrome_test.dart`.** The last one opens the theme picker and expects `GlassSheetChrome.floatingKey`. That test's subject is the chrome being replaced. Delete its two theme-picker tests: 'the theme picker floats as glass…' and 'a picked theme is still returned'. Port 'a picked theme is still returned' into a new `test/core/widgets/pickers/theme_picker_sheet_test.dart` with the same assertion (`picked == ThemeMode.dark`), plus a check that `find.byKey(AppSheet.surfaceKey)` is gone after the pick. Keep that file's third test, which covers `AppSheetChrome`, until Task 10 deletes the chrome. Name the moved tests in the commit body.

- [ ] **Step 6: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/pickers/picker_filter.dart lib/core/widgets/pickers/theme_picker_sheet.dart lib/core/widgets/pickers/project_picker_sheet.dart test/core/widgets/pickers test/core/widgets/main_widgets/app_sheet_chrome_test.dart
git commit -m "feat(mobile): theme and project pickers on AppSheet, project search

Moves the theme-picker result test from app_sheet_chrome_test to
theme_picker_sheet_test; the floating-glass assertion it replaced is gone
with that chrome.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Connection menu with a Rename page

**Files:**
- Rewrite: `packages/mobile/lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart`
- Delete: `packages/mobile/lib/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart`, moving its body and `_GhostButton` into `connection_menu_sheet.dart`
- Modify: `packages/mobile/lib/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart` (`_openMenu`)
- Create test: `packages/mobile/test/feature/pairing/presentation/connections_screen/ui/connection_menu_sheet_test.dart`
- Test (existing): `test/feature/pairing/presentation/connections_screen/ui/connections_body_test.dart` must stay green

**Interfaces:**
- Consumes: Task 7's `AppSheet`, `AppSheetPage`, `showAppSheet`, `AppSheet.of(context).push/close`.
- Produces:
  - `sealed class ConnectionMenuResult` with `final class RenameDesktopResult extends ConnectionMenuResult { const RenameDesktopResult(this.name); final String name; }` and `final class RemoveDesktopResult extends ConnectionMenuResult { const RemoveDesktopResult(); }`.
  - `Future<ConnectionMenuResult?> showConnectionMenuSheet(BuildContext context, {required String name})`.
  - `enum ConnectionMenuAction` is deleted.

- [ ] **Step 1: Write the failing test.** Reuse the `phone`/`host` helpers from `app_sheet_test.dart`, copied:

```dart
  testWidgets('Rename opens a page in the same sheet and Save returns the trimmed name', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Studio'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename desktop'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Office Mac  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isA<RenameDesktopResult>());
    expect((result! as RenameDesktopResult).name, 'Office Mac');
  });

  testWidgets('Save is disabled while the name is blank', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Rename desktop'), findsOneWidget);
  });

  testWidgets('Back from Rename returns to the menu, and Remove returns a remove result', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove desktop'));
    await tester.pumpAndSettle();
    expect(result, isA<RemoveDesktopResult>());
  });

  testWidgets('Cancel on the Rename page closes the sheet with no result', (tester) async {
    phone(tester);
    var finished = false;
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async {
        result = await showConnectionMenuSheet(context, name: 'Studio');
        finished = true;
      }),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
  });
```

- [ ] **Step 2: Run and watch it fail** (the types do not exist).

- [ ] **Step 3: Implement.**
  - `showConnectionMenuSheet` returns `showAppSheet<ConnectionMenuResult>(context: context, page: AppSheetPage(title: name, rows: ...))`, detent `fit`.
  - The Rename row does `Haptics.select(); AppSheet.of(context).push(_renamePage(name));`.
  - The Remove row does `Haptics.select(); Navigator.of(context).pop(const RemoveDesktopResult());`.
  - Keep `_MenuRow` and `_MenuDivider`.
  - `_renamePage(String initialName)` returns `AppSheetPage(title: 'Rename desktop', rows: (context, query) => [_RenameDesktopForm(initialName: initialName)])`.
  - `_RenameDesktopForm` is the old `_RenameDesktopSheetBody` without its "Rename desktop" heading, which is now the page title. Keep:
    - the "Name" label, the field and the Cancel/Save row
    - `_save` popping `RenameDesktopResult(nameController.text.trim())` through `Navigator.of(context).pop(...)`
    - Cancel popping with no value
    - Save disabled while the trimmed text is empty
  - Move `_GhostButton` over unchanged.
  - Delete `rename_desktop_sheet.dart`.

  In `connections_body.dart`, `_openMenu` becomes:

```dart
    final result = await showConnectionMenuSheet(context, name: title);
    if (!context.mounted || result == null) return;
    switch (result) {
      case RenameDesktopResult(:final name):
        if (name.isEmpty) return;
        await cubit.rename(id, name);
      case RemoveDesktopResult():
        final confirmed = await showRemoveConnectionDialog(context, name: title);
        if (confirmed) await cubit.remove(id);
    }
```

  Remove the `rename_desktop_sheet.dart` import.

- [ ] **Step 4: Run the new test and `connections_body_test.dart`**, then the gate.

- [ ] **Step 5: Commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart lib/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart test/feature/pairing/presentation/connections_screen/ui/connection_menu_sheet_test.dart
git rm lib/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart
git commit -m "feat(mobile): connection menu pushes Rename as a page in the same sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Spawn options sheet, and retire `AppSheetChrome`

**Files:**
- Create: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_options_sheet.dart`
- Rewrite into page factories:
  - `packages/mobile/lib/core/widgets/pickers/agent_picker_sheet.dart` → `agentPickerPage`
  - `packages/mobile/lib/core/widgets/pickers/claude_account_picker_sheet.dart` → `claudeAccountPickerPage`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart` (the three `_open…Picker` methods)
- Delete:
  - `packages/mobile/lib/core/widgets/main_widgets/app_sheet_chrome.dart`
  - `packages/mobile/test/core/widgets/main_widgets/app_sheet_chrome_test.dart` (its remaining `AppSheetChrome` test goes with the chrome)
- Port: `packages/mobile/test/core/widgets/agent_picker_sheet_test.dart` → `packages/mobile/test/core/widgets/pickers/agent_picker_page_test.dart`
- Create test: `packages/mobile/test/feature/spawn/presentation/spawn_screen/ui/spawn_options_sheet_test.dart`

**Interfaces:**
- Consumes:
  - Task 7's `AppSheet`, `AppSheetPage`, `AppSheetDetent`, `showAppSheet(scope:)`
  - Task 8's `PickerFilter`, `projectPickerPage`
  - `SpawnCubit`, with `projectId`, `setProject(id, kind:)`, `agents`, `harness`, `setHarness`, `claudeAccounts`, `claudeAccountId`, `setClaudeAccount` and `refreshCatalog`
  - `SpawnState`, including `CatalogLoadingState` and `CatalogFailureState`
- Produces:
  - `AppSheetPage agentPickerPage({required List<RankedAgent> agents, required String selected, required void Function(BuildContext context, String id) onPicked, List<Widget> actions = const [], String? error})`. Title "Agent"; subtitle "Which harness should run this task."; search hint "Search agents", matching label and id. `error` shows as a red row above the agents. Unselectable agents keep today's dimmed, non-tappable row. `emptyText` is today's "No agents reported…" copy.
  - `AppSheetPage claudeAccountPickerPage({required List<ClaudeAccountModel> accounts, required String selected, required void Function(BuildContext context, String id) onPicked})`. Title "Claude account"; subtitle "Which Claude login this session runs on."; search hint "Search accounts", matching label, id and plan label.
  - `enum SpawnOption { project, agent, account }`
  - `Future<void> showSpawnOptionsSheet(BuildContext context, {required SpawnCubit cubit, required List<ProjectModel> projects, required SpawnOption open, required Future<void> Function() onRefreshAgents})`. The sheet is `large`, and its `scope` wraps it in `BlocProvider<SpawnCubit>.value(value: cubit, child: sheet)`.
    - The root page, "Spawn options", has a "Done" action (`TextButton` → `AppSheet.of(context).close()`).
    - Its rows are one `SettingsGroup` of `SettingsRow`s: Project, Agent, and Account only when `cubit.harness == 'claude-code' && cubit.claudeAccounts.isNotEmpty`. Values are computed the way `spawn_body.dart` computes them today, inside a `BlocBuilder<SpawnCubit, SpawnState>`.
    - Each row pushes its page.
    - The sheet opens with the `open` page already pushed.
    - Picking calls the cubit setter, then `Haptics.select()` (already in the row), then `AppSheet.of(context).pop()` back to the root.
    - The Project page uses `projectPickerPage(includeAll: false, title: 'Project', subtitle: 'Where this agent gets its workspace.', selected: cubit.projectId ?? '')`.
    - The Agent page's actions are one refresh `IconButton(icon: Icon(Icons.refresh, size: 20, color: skin.accent))`. It calls `onRefreshAgents`; while the cubit state is `CatalogLoadingState` it shows the 16pt `AppLoader(strokeWidth: 2)` instead and does nothing on tap.
    - The Agent page's `error` is 'Could not reach your Operator server' while the state is `CatalogFailureState`. Page rows read the cubit through a `BlocBuilder`, so a refresh updates them live.

- [ ] **Step 1: Port the agent picker tests.** Read `test/core/widgets/agent_picker_sheet_test.dart`. Recreate its four tests against `agentPickerPage` opened through `showAppSheet(page: agentPickerPage(..., onPicked: (context, id) => Navigator.of(context).pop(id)), detent: AppSheetDetent.large)`, in `test/core/widgets/pickers/agent_picker_page_test.dart`. Keep the same assertions:
  - returns the tapped agent
  - refuses an unusable agent
  - reports the catalog error inside the sheet
  - refreshes on demand, now through the refresh action passed in `actions`

  Add one test: typing "cla" in the search field leaves only agents whose label or id contains it, and tapping one returns its id. Delete the old file.

- [ ] **Step 2: Write the Spawn options test.** Build a real `SpawnCubit` the way the existing spawn tests do: `grep -rln "SpawnCubit(" test`, then copy that construction and its mocks. Seed:
  - agents `claude-code` (label "Claude Code") and `codex` (label "Codex")
  - accounts `default` ("Default") and `work` ("Work")
  - `cubit.setHarness('claude-code')`

  Tests:
  1. Opening with `open: SpawnOption.agent` shows the "Agent" page with a back button. Tapping "Codex" makes `cubit.harness == 'codex'` and pops to the "Spawn options" root, which now shows Codex as the Agent value.
  2. With `harness == 'codex'`, the root has no "Account" row. With `claude-code` and accounts present, it has one.
  3. Opening with `open: SpawnOption.account`, searching "wor" and tapping "Work" makes `cubit.claudeAccountId == 'work'`.
  4. Opening with `open: SpawnOption.project`, tapping a project calls `setProject` with that id: `cubit.projectId` equals it.
  5. "Done" closes the sheet: `find.byKey(AppSheet.surfaceKey)` finds nothing.

- [ ] **Step 3: Run and watch both fail.**

- [ ] **Step 4: Implement.**
  - Write the page factories and `spawn_options_sheet.dart` per the interfaces above. Keep the `_AgentOption` row widget and the account row layout from the old sheets.
  - In `spawn_body.dart`, `_openProjectPicker`, `_openAgentPicker` and `_openClaudeAccountPicker` each become `showSpawnOptionsSheet(context, cubit: _cubit, projects: _sessionsCubit.projects, open: SpawnOption.<x>, onRefreshAgents: _refreshCatalog)`.
  - Keep `_projectById`, because the Project page's `onPicked` needs the project's `kind`. Pass a lookup or the projects list, and call `cubit.setProject(id, kind: ...)` exactly as `spawn_body.dart` does today.
  - Delete `app_sheet_chrome.dart` and its test.
  - `grep -rn "app_sheet_chrome\|AppSheetChrome\|showAgentPickerSheet\|showClaudeAccountPickerSheet" lib test` must print nothing.

- [ ] **Step 5: Run the new tests, `haptics_call_sites_test.dart` and every spawn test** (`flutter test test/feature/spawn`), then the gate.

- [ ] **Step 6: Commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/pickers lib/feature/spawn test/core/widgets/pickers test/feature/spawn
git rm lib/core/widgets/main_widgets/app_sheet_chrome.dart test/core/widgets/main_widgets/app_sheet_chrome_test.dart test/core/widgets/agent_picker_sheet_test.dart
git status --short
git commit -m "feat(mobile): one Spawn options sheet with searchable project, agent and account pages

Ports agent_picker_sheet_test to agent_picker_page_test with the same
assertions; retires AppSheetChrome and its test.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Real-app verification and report (controller)

This replaces Task 6 of the glass-chrome plan and covers both plans. The controller runs it with the simulator tool, and code fixes go through an implementer and a review.

- [ ] **Step 1: Build and launch.** Run `cd packages/mobile && flutter build ios --simulator --debug`, then launch `build/ios/iphonesimulator/Runner.app` on UDID `94D0C207-A90B-4806-BBAB-8AF9B3F16329`. The paired desktop must be running. If pairing is lost, stop and ask; the user types the password.

- [ ] **Step 2: Capture light and dark** into a fresh `packages/mobile/build/glass-chrome/`, with `xcrun simctl ui <udid> appearance light|dark` and `xcrun simctl io <udid> screenshot`. Screens:

  | Name | Screen |
  |---|---|
  | `agents` | Agents |
  | `agents-scrolled` | Agents, scrolled |
  | `prs` | PRs |
  | `settings` | Settings |
  | `notifications` | Notifications |
  | `usage` | Settings → Token usage |
  | `theme-sheet` | Theme sheet |
  | `project-search` | Project picker with a query typed |
  | `spawn-root` | Spawn options root |
  | `spawn-agent` | Spawn options, Agent page |
  | `connection-menu` | Connection menu |
  | `rename-page` | Connection menu, Rename page with the keyboard up |

  Do not press Spawn agent, Save, or Remove desktop.

- [ ] **Step 3: Inspect each PNG**:
  - Sheets: opaque, 8pt inset, concentric corners, grabber, centred title, glass back and actions, and content fading under the header.
  - The search capsule floats and the list clears it.
  - The rename page sits above the keyboard.
  - Tab bar, **+** and app bar as built.
  - Readable status bar in both themes.

  Record the findings, and dispatch fixes through an implementer with a review.

- [ ] **Step 4: Write `docs/superpowers/specs/2026-09-24-mobile-glass-chrome-report.md`**:
  - commits for both plans (`git log --oneline a119690d7..HEAD`)
  - the gate output
  - a table of screenshots and findings
  - the rulings from both SDD ledgers
  - what remains:
    - the grey top/bottom scroll-edge bands on flat backgrounds (app bar left as is by user decision)
    - the four `showModalBottomSheet` sheets
    - the terminal header
    - Usage not scrolling under the bar
    - GPU cost on a physical phone, not measured

- [ ] **Step 5: Gate, commit the report, and send the screenshots to the user.**
