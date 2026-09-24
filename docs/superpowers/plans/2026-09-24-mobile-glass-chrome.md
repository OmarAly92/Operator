# Mobile Glass Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the project-1 Liquid Glass engine on the real app's chrome: the tab bar, the top bars, the sheets and the **+** button, with scroll-edge fades where content runs under the bars.

**Architecture:** Swap at the shared seams. `HomeShell` hosts a floating `GlassTabBar`, the **+** button and the bottom scroll-edge fade over an `IndexedStack`, and tells each tab its bottom inset through `MediaQuery.padding.bottom`. `GlobalAppbar` becomes a transparent glass toolbar and wraps every action in a new `GlassBarItem`. A new `ScrollUnderBars` body wrapper paints the top fade under the bar on screens whose content scrolls under it. `AppSheetChrome` renders `GlassSheetChrome`, and a new `showAppSheet` passes the fitted barrier.

**Tech Stack:** Flutter 3.44.5, Dart, the vendored `liquid_glass_renderer`, the glass widgets in `packages/mobile/lib/core/widgets/glass/`, flutter_test, mocktail.

**Spec:** `docs/superpowers/specs/2026-09-24-mobile-glass-chrome-design.md`

## Global Constraints

- Work only in the worktree `/Users/omaraly/development/AI/Operator-ios-polish`, branch `feat/mobile-ios-polish`. NEVER touch the main checkout `/Users/omaraly/development/AI/Operator`.
- Do not merge, push, rebase onto development, or open a PR.
- Write NO code comments in anything you author (Dart, Swift, shell, Python, GLSL). Keep upstream comments in vendored files you edit.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not edit these files; another session owns uncommitted work in them: `terminal_chat_header.dart`, `session_card.dart`, `block_card.dart`, `block_list.dart`, `activity_string.dart`, `session_model.dart`, `turn_elapsed.dart`, `active_since.dart`, and their tests.
- Colours: icons and labels in the bars keep the colours they have today. Glass changes the material, not the colours.
- Gate for every task, run from `packages/mobile`: `flutter analyze` prints `No issues found!` and `flutter test` passes. Never weaken a test to make it pass. An existing test that asserts an old Material widget may be updated to the new widget; name each such change in the commit message.
- Feature code never imports `flutter_screenutil`. Spacing takes raw numbers or `GlassMetrics` constants.
- Navigation is `Navigator.of(context)` with `RoutesStrings` names.
- Visual claims need real simulator evidence (Task 6), not reasoning.

## Spec clarifications this plan makes

These are decisions the spec left open or got wrong once the code was read. Each is binding for the executor.

1. **Tab bar bottom position.** The spec says the bar sits `tabBarBottomInset` above the bottom safe-area edge. The native measurement in project 1 (and the lab) puts it 21pt above the **screen** edge. The plan follows the measurement. Content bottom inset is `max(safeBottom, tabBarBottomInset + tabBarHeight)` = 83 on the iPhone 17 Pro.
2. **The + button lives in `HomeShell`, not `SessionsScreen`.** It must paint above the bottom scroll-edge fade, which the shell paints over the whole `IndexedStack`. It shows only while the Agents tab is selected.
3. **The top scroll-edge fade is painted by the body, not by `GlobalAppbar`.** `Scaffold` paints the app bar above the body, so a fade at the top of the body sits under the bar. `ScrollUnderBars` does this. Screens whose content does not scroll under the bar get no fade, as on iOS.
4. **Dead `GlobalAppbar` parameters are removed.** `backgroundColor`, `elevation`, `surfaceTintColor`, `hasBorder` and `leadingWidth` would do nothing under glass. No screen needs an opaque bar. They are deleted, along with the two call sites that pass `backgroundColor`/`hasBorder` (Sessions, Settings). Every other argument and both constructors stay.
5. **Pushed routes.** `AppScaffold` gains `scrollsUnderAppBar` (default `false`). When false the body lays out below the bar exactly as today, over `bgBase`, so manual connect, pairing scan, spawn, preview, usage and the error routes need no body edits. Only Notifications sets it to `true`. Usage stays `false`: its list sits under a fixed bucket toggle, so it cannot scroll under the bar without restructuring the screen.
6. **Raw-`Scaffold` routes are unchanged.** `session_route_screen` shows centred states only. `subagent_screen`'s list is `block_list.dart`, which is off-limits. Both get the glass bar through `GlobalAppbar` and keep their body layout.
7. **Notifications "Mark all read".** Today the action is a `BlocBuilder` that returns `SizedBox.shrink()` at zero unread. Wrapped in glass, that would draw an empty glass circle. The screen moves the `BlocBuilder` above `AppScaffold` and passes the action only when there is something unread.
8. **Default back button.** The glass back button fires `Haptics.tap()` on every press through `GlassButton`. Before, the default `BackButton` fired no haptic and a custom `onAppPopIconPressed` fired one. Both now fire exactly one.
9. **Back chevron colour.** The old `BackButton` took Material's default `onSurface`. The glass chevron uses `skin.textPrimary`, the skin's own near-black/near-white.
10. **Out of scope, noted for the user.** Four sheets use `showModalBottomSheet`, not `showExpressiveSheet`, and stay Material: session actions, block actions, the model picker, and the subagent strip. The spec lists only the six `AppSheetChrome` sheets.

## Review Focus

1. **A drag that starts on the tab bar and ends far above it.** A user who starts a scroll gesture on the bar must not switch tabs. Today any release selects (project-1 sign-off). Task 1 fixes this and pins it.
2. **Pull-to-refresh under the glass.** The spinner must appear below the top bar, not under it. Tasks 3 and 4 pin `RefreshIndicator.edgeOffset` on every list that scrolls under the bar.
3. **An action that renders nothing.** It must not leave an empty glass circle. Task 2 pins that an empty `actions` list draws no `GlassBarItem`, and restructures Notifications (clarification 7).
4. **Sheet content that needs a `Material` ancestor.** `InkWell` and `ListTile` rows must still work inside glass sheets. The old chrome was a `Material` and `GlassSheetChrome` is not. Task 5 adds a transparent `Material` and pins a tap on an ink row.
5. **Large text in the bar.** At a text scale of 3.0, a long title and three actions must not overflow or overlap. Task 2 pins it, along with the three-line subagent title.

---

### Task 1: Tab bar ignores a release far off the bar

**Files:**
- Modify: `packages/mobile/lib/core/widgets/glass/glass_tab_bar_logic.dart`
- Modify: `packages/mobile/lib/core/widgets/glass/glass_tab_bar.dart` (`_up`)
- Test: `packages/mobile/test/core/widgets/glass/glass_tab_bar_logic_test.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_tab_bar_test.dart`

**Interfaces:**
- Produces: `GlassTabBarLogic.releaseSelects(Offset position, double width, double height) → bool`. True when `position` is inside the bar rect inflated by `GlassMetrics.hitTarget`.

- [ ] **Step 1: Write the failing logic test.** Append inside `main()` of `glass_tab_bar_logic_test.dart`, and add `import 'package:flutter/widgets.dart';` if the file lacks it:

```dart
  test('a release selects only within a hit target of the bar', () {
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 10), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -40), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -50), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 110), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(-50, 10), 300, 62), isFalse);
  });
```

- [ ] **Step 2: Write the failing widget tests.** Append inside `main()` of `glass_tab_bar_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the tests and watch them fail.**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_tab_bar_logic_test.dart test/core/widgets/glass/glass_tab_bar_test.dart`
Expected: the logic test fails to compile (`releaseSelects` is not defined). After Step 4 adds only the logic, 'releasing far above the bar selects nothing' fails with `picked` = `[1]`.

- [ ] **Step 4: Implement.** In `glass_tab_bar_logic.dart`, add the imports and the method:

```dart
import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
```

```dart
  static bool releaseSelects(Offset position, double width, double height) =>
      Rect.fromLTWH(0, 0, width, height).inflate(GlassMetrics.hitTarget).contains(position);
```

In `glass_tab_bar.dart`, replace `_up` with:

```dart
  void _up(PointerUpEvent event, double width) {
    if (event.pointer != _activePointer) return;
    final selects = GlassTabBarLogic.releaseSelects(event.localPosition, width, GlassMetrics.tabBarHeight);
    final slot = GlassTabBarLogic.slotAt(event.localPosition.dx, width, widget.items.length);
    _endDrag();
    if (!selects) return;
    Haptics.select();
    widget.onSelected(slot);
  }
```

- [ ] **Step 5: Run the tests and watch them pass.** Run the command from Step 3. Expected: all pass.

- [ ] **Step 6: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/glass/glass_tab_bar_logic.dart lib/core/widgets/glass/glass_tab_bar.dart test/core/widgets/glass/glass_tab_bar_logic_test.dart test/core/widgets/glass/glass_tab_bar_test.dart
git commit -m "fix(mobile): glass tab bar ignores a release far off the bar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Glass top bar

**Files:**
- Modify: `packages/mobile/lib/core/widgets/glass/glass_button.dart` (add `foreground`)
- Create: `packages/mobile/lib/core/widgets/glass/glass_bar_item.dart`
- Rewrite: `packages/mobile/lib/core/widgets/main_widgets/global_appbar.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart` (drop `backgroundColor`, `hasBorder`)
- Modify: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/settings_screen.dart` (drop `backgroundColor`, `hasBorder`)
- Modify: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/notifications_screen.dart` (clarification 7)
- Test: `packages/mobile/test/core/widgets/glass/glass_button_test.dart`
- Create test: `packages/mobile/test/core/widgets/main_widgets/global_appbar_test.dart`

**Interfaces:**
- Consumes: `GlassButton.icon`, `GlassSurface`, `GlassScope`, `GlassMetrics`, `GlassVariant`, `GlassShapeKind` (project 1).
- Produces:
  - `GlassButton.icon({..., Color? foreground})`. When non-null it replaces the icon colour; `null` keeps today's accent or `onGlassProminent`.
  - `GlassBarItem({Key? key, required Widget child})`. A glass capsule at least 44×44 and exactly 44 tall, with the child centred on a transparent `Material`.
  - `GlobalAppbar.main` / `.sub` with parameters `leading, title, titleText, actions, centerTitle, bottom, leadingText, onAppPopIconPressed, systemOverlayStyle, key`.
  - `GlobalAppbar.preferredSize.height == GlassMetrics.hitTarget + GlassMetrics.toolbarTopGap + (bottom?.preferredSize.height ?? 0)`, which is 44 with no `bottom`.

- [ ] **Step 1: Write the failing `GlassButton` test.** Append inside `main()` of `glass_button_test.dart`, using its existing `host(Widget child)` helper:

```dart
  testWidgets('an icon button takes an explicit foreground colour', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, foreground: const Color(0xFF123456), onPressed: () {})));
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).color, const Color(0xFF123456));
  });
```

- [ ] **Step 2: Write the failing `GlobalAppbar` tests.** Create `test/core/widgets/main_widgets/global_appbar_test.dart`:

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
```

- [ ] **Step 3: Run the tests and watch them fail.**

Run: `cd packages/mobile && flutter test test/core/widgets/main_widgets/global_appbar_test.dart test/core/widgets/glass/glass_button_test.dart`
Expected: compile failure. `glass_bar_item.dart` does not exist, and `foreground` is not a parameter.

- [ ] **Step 4: Add `foreground` to `GlassButton.icon`.** In `glass_button.dart`:
  - Add `this.foreground,` to the `GlassButton.icon` constructor's parameter list.
  - Add `foreground = null` to `GlassButton.label`'s initializer list, which becomes `: semanticLabel = null, foreground = null;`.
  - Add the field `final Color? foreground;`.
  - In `build`, change the colour line to:

```dart
    final foreground = widget.foreground ?? (widget.prominent ? skin.onGlassProminent : skin.accent);
```

- [ ] **Step 5: Create `glass_bar_item.dart`.**

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

class GlassBarItem extends StatelessWidget {
  const GlassBarItem({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      kind: GlassShapeKind.capsule,
      size: GlassMetrics.hitTarget,
      child: Theme(
        data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: GlassMetrics.hitTarget,
              minHeight: GlassMetrics.hitTarget,
              maxHeight: GlassMetrics.hitTarget,
            ),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Rewrite `global_appbar.dart`.**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlobalAppbar extends StatelessWidget implements PreferredSizeWidget {
  const GlobalAppbar.main({
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.centerTitle = false,
    this.bottom,
    super.key,
    this.leadingText,
    this.onAppPopIconPressed,
    this.systemOverlayStyle,
  }) : _isSub = false;

  const GlobalAppbar.sub({
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.centerTitle = true,
    this.bottom,
    super.key,
    this.leadingText,
    this.onAppPopIconPressed,
    this.systemOverlayStyle,
  }) : _isSub = true;

  static const double _maxTextScaleFactor = 1.8;

  final bool _isSub;
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final bool? centerTitle;
  final PreferredSizeWidget? bottom;
  final String? leadingText;
  final void Function()? onAppPopIconPressed;
  final SystemUiOverlayStyle? systemOverlayStyle;

  Widget? _buildLeading(BuildContext context) {
    if (!_isSub) return leading == null ? null : GlassBarItem(child: leading!);
    final button = leading != null
        ? GlassBarItem(child: leading!)
        : GlassButton.icon(
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: 'Back',
            foreground: context.skin.textPrimary,
            onPressed: onAppPopIconPressed ?? () => Navigator.maybePop(context),
          );
    if (leadingText == null) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(width: 6),
        Flexible(
          child: AppText(
            leadingText!,
            style: AppTextStyle.style12Regular.copyWith(color: context.skin.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget? _buildMiddle() {
    final middle = buildTitle();
    if (middle == null) return null;
    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      fit: OverflowBoxFit.deferToChild,
      child: middle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final trailing = actions ?? const <Widget>[];
    final overlay = systemOverlayStyle ??
        (skin.themeMode == ThemeMode.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Padding(
        padding: EdgeInsets.only(top: media.padding.top + GlassMetrics.toolbarTopGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GlassMetrics.toolbarSideInset),
              child: SizedBox(
                height: GlassMetrics.hitTarget,
                child: GlassScope(
                  variant: GlassVariant.regular,
                  size: GlassMetrics.hitTarget,
                  child: MediaQuery(
                    data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScaleFactor)),
                    child: NavigationToolbar(
                      leading: _buildLeading(context),
                      middle: _buildMiddle(),
                      trailing: trailing.isEmpty
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < trailing.length; i++) ...[
                                  if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                                  GlassBarItem(child: trailing[i]),
                                ],
                              ],
                            ),
                      centerMiddle: centerTitle ?? _isSub,
                      middleSpacing: GlassMetrics.toolbarItemGap,
                    ),
                  ),
                ),
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }

  Widget? buildTitle() {
    if (title != null) {
      return title!;
    }

    if (titleText != null) {
      return AppText(
        titleText!,
        style: _isSub ? AppTextStyle.style16SemiBold : AppTextStyle.style19SemiBold,
      );
    }

    return null;
  }

  @override
  Size get preferredSize => Size.fromHeight(
        GlassMetrics.hitTarget + GlassMetrics.toolbarTopGap + (bottom?.preferredSize.height ?? 0),
      );
}
```

- [ ] **Step 7: Update the two call sites that passed removed parameters.**
  - `sessions_screen.dart`: delete the lines `backgroundColor: context.skin.bgChrome,` and `hasBorder: true,` from `GlobalAppbar.main(...)`.
  - `settings_screen.dart`: delete the same two lines.

- [ ] **Step 8: Restructure the Notifications action (clarification 7).** Replace the `build` method of `notifications_screen.dart` with the version below and keep its imports. The `BlocListener` wrapper stays.

```dart
  @override
  Widget build(BuildContext context) => BlocListener<NotificationsCubit, NotificationsState>(
    listener: (context, state) {},
    child: BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) => current is NotificationsReadyState,
      builder: (context, state) {
        final cubit = context.read<NotificationsCubit>();
        return AppScaffold(
          appBar: GlobalAppbar.sub(
            titleText: 'Notifications',
            actions: [
              if (cubit.unreadCount > 0)
                TextButton(
                  onPressed: () {
                    Haptics.tap();
                    cubit.markAllRead();
                  },
                  child: AppText(
                    'Mark all read',
                    style: AppTextStyle.style15SemiBold.copyWith(color: context.skin.blue),
                  ),
                ),
            ],
          ),
          body: const NotificationsBody(),
        );
      },
    ),
  );
```

- [ ] **Step 9: Run the tests and watch them pass.** Run the command from Step 3. Expected: all pass. If '.main keeps its title on the left' gives a left edge other than 16, print `tester.getRect` and fix the layout, not the expectation: the spec requires the `.main` title at the toolbar inset.

- [ ] **Step 10: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/glass/glass_button.dart lib/core/widgets/glass/glass_bar_item.dart lib/core/widgets/main_widgets/global_appbar.dart lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart lib/feature/settings/presentation/settings_screen/ui/settings_screen.dart lib/feature/notification/presentation/notifications_screen/ui/notifications_screen.dart test/core/widgets/glass/glass_button_test.dart test/core/widgets/main_widgets/global_appbar_test.dart
git commit -m "feat(mobile): GlobalAppbar renders as a glass toolbar

Removes backgroundColor, elevation, surfaceTintColor, hasBorder and
leadingWidth, which do nothing under glass. Notifications passes its
Mark all read action only when there is something unread.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

If the full suite shows an existing test that asserted `AppBar` or `BackButton`, update it to `GlobalAppbar`/`GlassButton` and name the test in the commit body.

---

### Task 3: Content scrolls under the top bar

**Files:**
- Modify: `packages/mobile/lib/core/widgets/glass/glass_metrics.dart` (add two constants)
- Create: `packages/mobile/lib/core/widgets/glass/scroll_under_bars.dart`
- Modify: `packages/mobile/lib/core/widgets/main_widgets/app_scaffold.dart`
- Modify: `sessions_screen.dart`, `pull_requests_screen.dart`, `settings_screen.dart` (Scaffold flag and body wrapper)
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart` (list padding, `edgeOffset`)
- Modify: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart` (list padding, `edgeOffset`)
- Modify: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart` (list padding)
- Modify: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart` (list padding, `edgeOffset`)
- Modify: `notifications_screen.dart` (`scrollsUnderAppBar: true`)
- Test: `packages/mobile/test/core/widgets/core_widgets_test.dart`
- Create test: `packages/mobile/test/core/widgets/glass/scroll_under_bars_test.dart`
- Test: `packages/mobile/test/core/app_routes/home_shell_test.dart`
- Test: `packages/mobile/test/feature/notification/presentation/notifications_screen/ui/notifications_body_test.dart`

**Interfaces:**
- Consumes: `GlobalAppbar.preferredSize` of 44 (Task 2), `ScrollEdgeEffect(edge:, height:)` (project 1).
- Produces:
  - `GlassMetrics.topEdgeFadeExtent = 34`
  - `GlassMetrics.bottomEdgeFadeExtent = 37`. With the iPhone 17 Pro's 62pt top safe area these reproduce the fitted lab bands: 62 + 44 + 34 = 140 and 21 + 62 + 37 = 120.
  - `ScrollUnderBars({Key? key, required Widget child})`. It stacks the child with a top `ScrollEdgeEffect` whose height is `MediaQuery.paddingOf(context).top + GlassMetrics.topEdgeFadeExtent`.
  - `AppScaffold({..., bool scrollsUnderAppBar = false})`. The old `extendBodyBehindAppBar` parameter is removed; no caller passed it.
  - The inset rule used by every list that scrolls under the bars:
    - `insets = MediaQuery.paddingOf(context)`
    - top padding = `insets.top` plus the list's old top padding
    - bottom padding = `insets.bottom` plus the list's old bottom padding
    - `RefreshIndicator.edgeOffset = insets.top`

- [ ] **Step 1: Write the failing `ScrollUnderBars` test.** Create `test/core/widgets/glass/scroll_under_bars_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_under_bars.dart';

void main() {
  testWidgets('puts a top edge fade over the child, sized to the bar inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 106)),
            child: const SkinScope(
              skin: LightSkin(),
              child: ScrollUnderBars(child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.edge, ScrollEdge.top);
    expect(effect.height, 140);
    expect(find.text('content'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Write the failing `AppScaffold` tests.** Append inside `main()` of `core_widgets_test.dart`. Add imports for `package:operator_mobile/core/widgets/main_widgets/global_appbar.dart` and `package:operator_mobile/core/widgets/glass/scroll_under_bars.dart`.

```dart
  Widget wrap(Widget child) => MaterialApp(home: SkinScope(skin: const DarkSkin(), child: child));

  testWidgets('AppScaffold keeps the body below the glass bar by default', (tester) async {
    await tester.pumpWidget(wrap(const AppScaffold(appBar: GlobalAppbar.sub(titleText: 'T'), body: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBodyBehindAppBar, isFalse);
    expect(find.byType(ScrollUnderBars), findsNothing);
  });

  testWidgets('AppScaffold scrollsUnderAppBar extends the body and adds the top fade', (tester) async {
    double? bodyTop;
    await tester.pumpWidget(
      wrap(
        AppScaffold(
          appBar: const GlobalAppbar.sub(titleText: 'T'),
          scrollsUnderAppBar: true,
          body: Builder(
            builder: (context) {
              bodyTop = MediaQuery.paddingOf(context).top;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBodyBehindAppBar, isTrue);
    expect(find.byType(ScrollUnderBars), findsOneWidget);
    expect(bodyTop, 44);
  });
```

- [ ] **Step 3: Write the failing tab-root inset tests.** Append inside `main()` of `home_shell_test.dart`, and add imports for `package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`, `package:operator_mobile/feature/settings/presentation/settings_screen/ui/settings_screen.dart` and `package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart`. The test view has zero top padding and the glass bar is 44 tall, so the body's top inset is 44.

```dart
  ListView tabList(WidgetTester tester, int tab) => tester.widget<ListView>(
        find.byWidgetPredicate((w) => w is ListView && w.controller == HomeShell.controllerFor(tab)),
      );

  testWidgets('every tab list starts below the glass top bar', (tester) async {
    await pumpShell(tester);

    expect((tabList(tester, 0).padding! as EdgeInsets).top, 44);
    expect(
      tester.widget<RefreshIndicator>(
        find.descendant(of: find.byType(SessionsScreen), matching: find.byType(RefreshIndicator)),
      ).edgeOffset,
      44,
    );
    expect((tabList(tester, 1).padding! as EdgeInsets).top, 44);
    expect(
      tester.widget<RefreshIndicator>(
        find.descendant(of: find.byType(PullRequestsScreen), matching: find.byType(RefreshIndicator)),
      ).edgeOffset,
      44,
    );
    expect((tabList(tester, 2).padding! as EdgeInsets).top, 60);
  });

  testWidgets('tab roots extend their body under the bar', (tester) async {
    await pumpShell(tester);
    for (final screen in [SessionsScreen, PullRequestsScreen, SettingsScreen]) {
      final scaffold = tester.widget<Scaffold>(
        find.descendant(of: find.byType(screen), matching: find.byType(Scaffold)).first,
      );
      expect(scaffold.extendBodyBehindAppBar, isTrue, reason: '$screen');
    }
  });
```

`IndexedStack` keeps offstage children in the tree. If `find.byWidgetPredicate` cannot see an offstage tab's `ListView`, pass `skipOffstage: false` to that finder and to the `find.descendant` calls. Do not select the tab first; that would test something else.

- [ ] **Step 4: Write the failing Notifications inset test.** Append inside `main()` of `notifications_body_test.dart`. It reuses `item` and `stubPage` from that file.

```dart
  testWidgets('the list starts below the glass bar and clears the home indicator', (tester) async {
    stubPage([item('n-1')], unreadCount: 1);

    final cubit = await pump(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 106, bottom: 34)),
          child: const NotificationsBody(),
        ),
      ),
    );

    expect(tester.widget<ListView>(find.byType(ListView)).padding, const EdgeInsets.only(top: 114, bottom: 42));
    expect(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset, 106);
    await cubit.close();
  });
```

- [ ] **Step 5: Run the tests and watch them fail.**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/scroll_under_bars_test.dart test/core/widgets/core_widgets_test.dart test/core/app_routes/home_shell_test.dart test/feature/notification/presentation/notifications_screen/ui/notifications_body_test.dart`
Expected: compile failure (`scroll_under_bars.dart` is missing, `scrollsUnderAppBar` is undefined). Once those exist, the inset tests fail on padding values.

- [ ] **Step 6: Add the metrics.** In `glass_metrics.dart`, add:

```dart
  static const double topEdgeFadeExtent = 34;
  static const double bottomEdgeFadeExtent = 37;
```

- [ ] **Step 7: Create `scroll_under_bars.dart`.**

```dart
import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';

class ScrollUnderBars extends StatelessWidget {
  const ScrollUnderBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ScrollEdgeEffect(edge: ScrollEdge.top, height: top + GlassMetrics.topEdgeFadeExtent),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8: Update `AppScaffold`.**
  - Remove the `extendBodyBehindAppBar` field and constructor parameter.
  - Add `final bool scrollsUnderAppBar;` with constructor default `this.scrollsUnderAppBar = false`.
  - Import `scroll_under_bars.dart`.
  - In `build`, set `extendBodyBehindAppBar: scrollsUnderAppBar,` on the `Scaffold`.
  - Change the body to:

```dart
      body: Column(
        children: [
          Expanded(
            child: scrollsUnderAppBar
                ? ScrollUnderBars(child: Padding(padding: padding ?? EdgeInsets.zero, child: body))
                : Padding(padding: padding ?? EdgeInsets.zero, child: body),
          ),
        ],
      ),
```

- [ ] **Step 9: Tab-root screens.** In each of `sessions_screen.dart`, `pull_requests_screen.dart` and `settings_screen.dart`:
  - Add `extendBodyBehindAppBar: true,` to the `Scaffold`.
  - Wrap its body in `ScrollUnderBars`:
    - `body: const ScrollUnderBars(child: SessionsBody()),`
    - `body: const ScrollUnderBars(child: PullRequestsBody()),`
    - `body: ScrollUnderBars(child: SettingsBody(onOpenBoard: onOpenBoard)),`
  - Import `package:operator_mobile/core/widgets/glass/scroll_under_bars.dart`.

- [ ] **Step 10: List paddings.**
  - `sessions_body.dart`, inside the builder that returns the `RefreshIndicator`:
    - Add `final insets = MediaQuery.paddingOf(context);`.
    - Set `edgeOffset: insets.top,` on the `RefreshIndicator`.
    - Replace `padding: const EdgeInsets.only(bottom: 40),` with `padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom + GlassMetrics.primaryButtonBottomGap + GlassMetrics.hitTarget),`.
    - Import `glass_metrics.dart`.
  - `pull_requests_body.dart`:
    - Add `final insets = MediaQuery.paddingOf(context);` before `return RefreshIndicator(`.
    - Set `edgeOffset: insets.top,`.
    - Replace the list's `padding: const EdgeInsets.only(bottom: 40),` with `padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom + 40),`.
  - `settings_body.dart`:
    - Add `final insets = MediaQuery.paddingOf(context);` before `return ListView(`.
    - Replace `padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),` with `padding: EdgeInsets.fromLTRB(16, insets.top + 16, 16, insets.bottom + 40),`.
  - `notifications_body.dart`:
    - Add `final insets = MediaQuery.paddingOf(context);` before `return RefreshIndicator(`.
    - Set `edgeOffset: insets.top,`.
    - Replace `padding: const EdgeInsets.symmetric(vertical: 8),` on the `ListView.separated` with `padding: EdgeInsets.only(top: insets.top + 8, bottom: insets.bottom + 8),`.
  - `notifications_screen.dart`: add `scrollsUnderAppBar: true,` to its `AppScaffold`.

- [ ] **Step 11: Run the tests and watch them pass.** Run the command from Step 5. Expected: all pass.

- [ ] **Step 12: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/glass/glass_metrics.dart lib/core/widgets/glass/scroll_under_bars.dart lib/core/widgets/main_widgets/app_scaffold.dart lib/feature/sessions lib/feature/pull_request lib/feature/settings lib/feature/notification test/core/widgets/core_widgets_test.dart test/core/widgets/glass/scroll_under_bars_test.dart test/core/app_routes/home_shell_test.dart test/feature/notification
git status --short
git commit -m "feat(mobile): tab roots and notifications scroll under the glass bar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Before committing, check `git status --short`: it must list no off-limits file (see Global Constraints).

---

### Task 4: Floating glass tab bar and the + button

**Files:**
- Rewrite: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart` (remove the `floatingActionButton`)
- Test: `packages/mobile/test/core/app_routes/home_shell_test.dart`

**Interfaces:**
- Consumes:
  - `GlassTabBar`, `GlassTabItem`, `GlassButton.icon(prominent: true)`
  - `ScrollEdgeEffect`, `GlassMetrics.bottomEdgeFadeExtent` (Task 3)
  - `GlassTabBarLogic.releaseSelects` (Task 1)
- Produces:
  - `HomeShell.spawnButtonKey` (a `Key`)
  - `HomeShell.tabs` (`List<GlassTabItem>`)
  - `HomeShell.contentBottomInset(double safeBottom) → double`, equal to `max(safeBottom, GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight)`

- [ ] **Step 1: Update the existing shell tests to the new widget.** In `home_shell_test.dart`:
  - Replace `tabLabel` with `find.descendant(of: find.byType(GlassTabBar), matching: find.text(label))`.
  - Replace both `tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex` with `tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex`.
  - Add `onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}'), settings: settings),` to the host's `MaterialApp`.
  - Add these imports:
    - `package:operator_mobile/core/widgets/glass/glass_tab_bar.dart`
    - `package:operator_mobile/core/widgets/glass/glass_button.dart`
    - `package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart`
    - `package:operator_mobile/core/app_routes/routes_strings.dart`
    - `package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart`
    - `package:flutter/services.dart`

- [ ] **Step 2: Write the failing shell tests.** Append inside `main()`:

```dart
  testWidgets('uses the floating glass tab bar', (tester) async {
    await pumpShell(tester);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(GlassTabBar), findsOneWidget);
    final bottomFade = tester.widgetList<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect)).where((e) => e.edge == ScrollEdge.bottom);
    expect(bottomFade.single.height, 120);
  });

  testWidgets('the + button is prominent glass and opens spawn', (tester) async {
    await pumpShell(tester);
    expect(tester.widget<GlassButton>(find.byKey(HomeShell.spawnButtonKey)).prominent, isTrue);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byKey(HomeShell.spawnButtonKey));
    await settle(tester);
    expect(find.text('route ${RoutesStrings.spawn}'), findsOneWidget);
  });

  testWidgets('the + button shows only on the Agents tab', (tester) async {
    await pumpShell(tester);
    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(find.byKey(HomeShell.spawnButtonKey), findsNothing);
    await tester.tap(tabLabel('Agents'));
    await settle(tester);
    expect(find.byKey(HomeShell.spawnButtonKey), findsOneWidget);
  });

  testWidgets('a tab tap fires exactly one haptic', (tester) async {
    final haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpShell(tester);
    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(haptics, hasLength(1));
  });

  testWidgets('tab lists clear the floating tab bar and the + button', (tester) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(
            sessions: [
              for (var i = 0; i < 40; i++)
                SessionModel(id: 's$i', projectId: 'proj', displayName: 'Session $i', status: 'working'),
            ],
          ),
        ),
      ),
    );
    await pumpShell(tester);

    expect(HomeShell.contentBottomInset(0), 83);
    expect(HomeShell.contentBottomInset(100), 100);
    expect((tabList(tester, 0).padding! as EdgeInsets).bottom, 83 + 12 + 44);
    expect((tabList(tester, 1).padding! as EdgeInsets).bottom, 83 + 40);
    expect((tabList(tester, 2).padding! as EdgeInsets).bottom, 83 + 40);

    final controller = HomeShell.controllerFor(0);
    controller.jumpTo(controller.position.maxScrollExtent);
    await settle(tester);
    final lastCard = tester.getRect(find.byType(SessionCard).last);
    expect(lastCard.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(HomeShell.spawnButtonKey)).top));
    expect(lastCard.bottom, lessThanOrEqualTo(tester.getRect(find.byType(GlassTabBar)).top));
  });
```

`tabList` is the helper added in Task 3. The expected bottom paddings are 139, 123 and 123. The + button's top sits 83 + 12 + 44 = 139pt above the screen bottom, so the last card clears it.

- [ ] **Step 3: Run the tests and watch them fail.**

Run: `cd packages/mobile && flutter test test/core/app_routes/home_shell_test.dart`
Expected: failures. `GlassTabBar` is not found, and `spawnButtonKey` and `contentBottomInset` are undefined.

- [ ] **Step 4: Rewrite `home_shell.dart`.**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  static final List<ScrollController> _controllers = List<ScrollController>.generate(
    3,
    (_) => ScrollController(),
  );

  static ScrollController controllerFor(int tab) => _controllers[tab];

  static const Key spawnButtonKey = ValueKey('home-shell-spawn');

  static const List<GlassTabItem> tabs = [
    GlassTabItem(icon: Icons.auto_awesome_motion_outlined, label: 'Agents'),
    GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
    GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  static double contentBottomInset(double safeBottom) =>
      math.max(safeBottom, GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    HomeShell.selectedTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    HomeShell.selectedTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  void _select(int next) {
    if (next == HomeShell.selectedTab.value) {
      final controller = HomeShell.controllerFor(next);
      if (controller.hasClients && controller.offset > 0) {
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    HomeShell.selectedTab.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final selected = HomeShell.selectedTab.value;
    final bottomInset = HomeShell.contentBottomInset(media.padding.bottom);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(bottom: bottomInset)),
              child: IndexedStack(
                index: selected,
                children: [
                  const SessionsScreen(),
                  const PullRequestsScreen(),
                  SettingsScreen(onOpenBoard: () => HomeShell.selectedTab.value = 0),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ScrollEdgeEffect(
              edge: ScrollEdge.bottom,
              height: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.bottomEdgeFadeExtent,
            ),
          ),
          if (selected == 0)
            Positioned(
              right: GlassMetrics.primaryButtonInset,
              bottom: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.primaryButtonBottomGap,
              child: GlassButton.icon(
                key: HomeShell.spawnButtonKey,
                icon: Icons.add,
                semanticLabel: 'Spawn agent',
                prominent: true,
                onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.spawn),
              ),
            ),
          Positioned(
            left: GlassMetrics.tabBarSideInset,
            right: GlassMetrics.tabBarSideInset,
            bottom: GlassMetrics.tabBarBottomInset,
            child: GlassTabBar(items: HomeShell.tabs, selectedIndex: selected, onSelected: _select),
          ),
        ],
      ),
    );
  }
}
```

`GlassTabBar` already fires `Haptics.select()` on every selection, so `_select` does not; the old `onTap` did, and keeping both would double the haptic.

- [ ] **Step 5: Remove the old FAB.** In `sessions_screen.dart`, delete the whole `floatingActionButton: FloatingActionButton(...)` argument. Remove the `routes_strings.dart` import if it is now unused; `flutter analyze` will say.

- [ ] **Step 6: Run the tests and watch them pass.** Run the command from Step 3. Expected: all pass, including the six pre-existing shell tests.

- [ ] **Step 7: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/app_routes/home_shell.dart lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart test/core/app_routes/home_shell_test.dart
git commit -m "feat(mobile): floating glass tab bar and prominent glass + button

home_shell_test: the tab finder and selected-index checks now read
GlassTabBar instead of BottomNavigationBar; the assertions are unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Glass sheets

**Files:**
- Rewrite: `packages/mobile/lib/core/widgets/main_widgets/app_sheet_chrome.dart`
- Modify (swap `showExpressiveSheet` → `showAppSheet`):
  - `lib/core/widgets/pickers/project_picker_sheet.dart`
  - `lib/core/widgets/pickers/claude_account_picker_sheet.dart`
  - `lib/core/widgets/pickers/agent_picker_sheet.dart`
  - `lib/core/widgets/pickers/theme_picker_sheet.dart`
  - `lib/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart`
  - `lib/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart`
- Create test: `packages/mobile/test/core/widgets/main_widgets/app_sheet_chrome_test.dart`

**Interfaces:**
- Consumes: `GlassSheetChrome`, `GlassSheetChrome.floatingKey`, `GlassSheetLogic.barrierColor(AppSkin)` (project 1); `showExpressiveSheet<T>({context, builder, barrierColor})`.
- Produces:
  - `showAppSheet<T>({required BuildContext context, required WidgetBuilder builder}) → Future<T?>`
  - `AppSheetChrome({Key? key, required Widget child, EdgeInsetsGeometry? padding})`
  - `AppSheetChrome.defaultPadding == EdgeInsets.fromLTRB(16, 0, 16, 12)`

- [ ] **Step 1: Write the failing tests.** Create `test/core/widgets/main_widgets/app_sheet_chrome_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';
import 'package:operator_mobile/core/widgets/pickers/theme_picker_sheet.dart';

void main() {
  Widget host(AppSkin skin, void Function(BuildContext context) open) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () => open(context), child: const Text('Open')),
              ),
            ),
          ),
        ),
      );

  for (final skin in const <AppSkin>[LightSkin(), DarkSkin()]) {
    testWidgets('the theme picker floats as glass over the fitted barrier (${skin.themeMode.name})', (tester) async {
      await tester.pumpWidget(host(skin, (context) => showThemePickerSheet(context, selected: ThemeMode.system)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(GlassSheetChrome.floatingKey), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.text('Light')))!;
      expect(route.barrierColor, GlassSheetLogic.barrierColor(skin));
    });
  }

  testWidgets('a picked theme is still returned', (tester) async {
    ThemeMode? picked;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => picked = await showThemePickerSheet(context, selected: ThemeMode.system)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(picked, ThemeMode.dark);
    expect(find.byType(GlassSheetChrome), findsNothing);
  });

  testWidgets('sheet content spans the sheet and ink rows work inside it', (tester) async {
    const contentKey = ValueKey('content');
    var tapped = 0;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<void>(
          context: context,
          builder: (_) => AppSheetChrome(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(key: contentKey, height: 20),
                ListTile(title: const Text('Row'), onTap: () => tapped++),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final screenWidth = tester.getSize(find.byType(Scaffold).first).width;
    expect(tester.getSize(find.byKey(contentKey)).width, screenWidth - 8 * 2 - 16 * 2);
    await tester.tap(find.text('Row'));
    await tester.pump();
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });
}
```

The labels come from `preferenceLabel(mode)`; `haptics_call_sites_test.dart` already taps `'Light'`. If `'Dark'` differs, use the label `preferenceLabel(ThemeMode.dark)` returns. Do not change the sheet.

- [ ] **Step 2: Run the tests and watch them fail.**

Run: `cd packages/mobile && flutter test test/core/widgets/main_widgets/app_sheet_chrome_test.dart`
Expected: compile failure, because `showAppSheet` is undefined.

- [ ] **Step 3: Rewrite `app_sheet_chrome.dart`.** The old doc comment described the Material chrome and is removed with it.

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';

Future<T?> showAppSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showExpressiveSheet<T>(
    context: context,
    barrierColor: GlassSheetLogic.barrierColor(context.skin),
    builder: builder,
  );
}

class AppSheetChrome extends StatelessWidget {
  const AppSheetChrome({super.key, required this.child, this.padding});

  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(16, 0, 16, 12);

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return GlassSheetChrome(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding ?? defaultPadding, child: child),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Swap the six call sites.** In each file listed above:
  - Replace `showExpressiveSheet<` with `showAppSheet<`.
  - Delete the now-unused `import 'package:expressive_sheet/expressive_sheet.dart';`.
  - Keep the `app_sheet_chrome.dart` import; each file already has it for `AppSheetChrome`.
  - Leave every builder, result type and `Navigator.pop` unchanged.

Verify that nothing was missed:

```bash
cd packages/mobile && grep -rn "showExpressiveSheet" lib | grep -v "lib/core/widgets/glass/\|app_sheet_chrome.dart"
```

Expected: no output.

- [ ] **Step 5: Run the tests and watch them pass.** Run the command from Step 2, then the existing sheet tests: `flutter test test/core/utils/haptics_call_sites_test.dart`. Expected: all pass.

- [ ] **Step 6: Gate and commit.**

```bash
cd packages/mobile && flutter analyze && flutter test
git add lib/core/widgets/main_widgets/app_sheet_chrome.dart lib/core/widgets/pickers lib/feature/pairing/presentation/connections_screen/ui/widgets test/core/widgets/main_widgets/app_sheet_chrome_test.dart
git commit -m "feat(mobile): app sheets render as floating glass over the fitted barrier

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Real-app verification and report

**Files:**
- Create: `docs/superpowers/specs/2026-09-24-mobile-glass-chrome-report.md`
- Screenshots: `packages/mobile/build/glass-chrome/` (git-ignored). Use a fresh directory; delete it first.

This task needs the running Operator desktop (`npm run tauri:dev`, started with the scrubbed environment) and the paired app on the iPhone 17 Pro simulator, iOS 26.5, UDID `94D0C207-A90B-4806-BBAB-8AF9B3F16329`. Do not re-pair. If the pairing is lost, stop and ask the user; the user types the password.

- [ ] **Step 1: Build and launch the real app** (no `GLASS_LAB_SCENE` define):

```bash
cd packages/mobile && flutter build ios --simulator --debug
```

Launch `packages/mobile/build/ios/iphonesimulator/Runner.app` on the UDID above with the iOS simulator tool's `launch` action. Confirm the Agents board shows live sessions from the desktop.

- [ ] **Step 2: Capture light mode.**

```bash
rm -rf packages/mobile/build/glass-chrome && mkdir -p packages/mobile/build/glass-chrome
xcrun simctl ui 94D0C207-A90B-4806-BBAB-8AF9B3F16329 appearance light
```

For each screen below, navigate in the app, then run `xcrun simctl io 94D0C207-A90B-4806-BBAB-8AF9B3F16329 screenshot packages/mobile/build/glass-chrome/light-<name>.png`:

| Name | Screen |
|---|---|
| `agents` | Agents |
| `agents-scrolled` | Agents scrolled so cards sit under both bars |
| `prs` | PRs |
| `settings` | Settings |
| `notifications` | Notifications (the bell) |
| `usage` | Settings → Token usage |
| `theme-sheet` | Settings → Theme sheet open |

- [ ] **Step 3: Capture dark mode.** Run `xcrun simctl ui 94D0C207-A90B-4806-BBAB-8AF9B3F16329 appearance dark` and repeat Step 2 with the prefix `dark-`. Also check the live theme switch: switch appearance while the Agents tab is showing and confirm the glass updates without a remount.

- [ ] **Step 4: Inspect every screenshot.** Open each PNG with the Read tool and check:
  - (a) the tab bar floats, glass, 21pt above the screen edge, with the droplet under the selected tab;
  - (b) the top bar shows glass circles for back and actions, with today's icon colours, and titles are not clipped;
  - (c) no first or last list row is hidden under a bar at rest;
  - (d) in `agents-scrolled`, cards blur and dim under both bars;
  - (e) the + sits above the tab bar at the right and is not dimmed by the bottom fade;
  - (f) the theme sheet floats with inset rounded corners and a dimmed barrier;
  - (g) the status bar icons are readable in both themes.

  Record each failure with its screenshot name. Fix real defects in the owning task's files, rerun the gate, commit, and recapture that screen. Do not tune `GlassStyle` values in this project.

- [ ] **Step 5: Pull-to-refresh check.** On Agents, pull down and capture `light-agents-refresh.png` mid-pull. The spinner must be fully below the top glass bar.

- [ ] **Step 6: Write the report.** In `docs/superpowers/specs/2026-09-24-mobile-glass-chrome-report.md`, record:
  - the commits per task (`git log --oneline 9abac43f8..HEAD`)
  - the gate output: the `flutter analyze` line and the `flutter test` total
  - the screenshot list with a one-line finding each
  - what was fixed during Step 4
  - the ten spec clarifications above, marked as applied
  - what remains:
    - the four `showModalBottomSheet` sheets
    - the terminal header
    - Usage not scrolling under the bar
    - GPU cost on a physical iPhone, which is not measured

- [ ] **Step 7: Gate and commit the report.**

```bash
cd packages/mobile && flutter analyze && flutter test && (cd packages/liquid_glass_renderer && flutter test)
cd ../.. && git add docs/superpowers/specs/2026-09-24-mobile-glass-chrome-report.md
git commit -m "docs(mobile): glass chrome verification report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Send the screenshots to the user** with SendUserFile: both themes, all screens. Stop at user sign-off.
