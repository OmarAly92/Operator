import 'dart:math' as math;

import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/glass/frosted_header.dart';
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
  static const double headerFadeExtent = 16;
  static const double pushParallax = 0.3;
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

  static double topCornerRadius() => GlassMetrics.sheetTopCornerRadius;

  static double pageOffset({required bool incoming, required bool forward, required double progress}) {
    final hidden = incoming == forward ? 1.0 : -AppSheetMetrics.pushParallax;
    return hidden * (1 - progress);
  }

  static double headerBarVisibility(double offset) =>
      (offset / AppSheetMetrics.headerFadeExtent).clamp(0.0, 1.0).toDouble();

  static Clip surfaceClip(double headerVisibility) =>
      headerVisibility > 0 ? Clip.antiAliasWithSaveLayer : Clip.antiAlias;

  static LiquidGlassSettings calmGlass(LiquidGlassSettings settings) =>
      settings.copyWith(refractiveIndex: 1, chromaticAberration: 0);

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
  static const Key headerBarKey = ValueKey('app-sheet-header-bar');
  static const Key contentClipKey = ValueKey('app-sheet-content-clip');
  static const Key searchCapsuleKey = ValueKey('app-sheet-search-capsule');
  static const Key pageMaterialKey = ValueKey('app-sheet-page-material');
  static const Key outerClipKey = ValueKey('app-sheet-outer-clip');
  static const Key layerClipKey = ValueKey('app-sheet-layer-clip');

  final AppSheetPage root;
  final List<AppSheetPage> pushed;
  final AppSheetDetent detent;

  static AppSheetController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppSheetScope>()!.controller;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet> with SingleTickerProviderStateMixin {
  late final List<AppSheetPage> _pages = [widget.root, ...widget.pushed];
  late final AppSheetController _controller = AppSheetController._(this);
  final TextEditingController _search = TextEditingController();
  final ValueNotifier<double> _headerVisibility = ValueNotifier<double>(0);
  late final AnimationController _handoff = AnimationController(vsync: this, duration: AppMotion.sheetPush);
  late final Listenable _headerListenable = Listenable.merge([_headerVisibility, _handoff]);
  double _handoffFrom = 0;
  bool _forward = true;

  double get _shownVisibility {
    final target = _headerVisibility.value;
    if (!_handoff.isAnimating) return target;
    final t = AppMotion.sheetPushCurve.transform(_handoff.value);
    return _handoffFrom + (target - _handoffFrom) * t;
  }

  void _startHandoff() {
    _handoffFrom = _shownVisibility;
    _headerVisibility.value = 0;
    _handoff.forward(from: 0);
  }

  void _push(AppSheetPage page) {
    _startHandoff();
    setState(() {
      _forward = true;
      _pages.add(page);
      _search.clear();
    });
  }

  void _pop() {
    if (_pages.length < 2) return;
    _startHandoff();
    setState(() {
      _forward = false;
      _pages.removeLast();
      _search.clear();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _headerVisibility.dispose();
    _handoff.dispose();
    super.dispose();
  }

  bool _onScroll(Notification notification, int depth) {
    if (depth != _pages.length) return false;
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _headerVisibility.value = AppSheetLogic.headerBarVisibility(metrics.pixels);
    }
    return false;
  }

  Widget _content(AppSheetPage page, bool shrinkWrap) {
    final skin = context.skin;
    final depth = _pages.length;
    final bottom = AppSheetLogic.bottomClearance(hasSearch: page.searchHint != null);
    return ValueListenableBuilder<TextEditingValue>(
      key: ValueKey<int>(_pages.length),
      valueListenable: _search,
      builder: (context, value, _) {
        final query = value.text.trim();
        final rows = page.rows(context, query);
        final String? message = rows.isNotEmpty ? null : (query.isNotEmpty ? 'No matches' : page.emptyText);
        return NotificationListener<Notification>(
          onNotification: (notification) => _onScroll(notification, depth),
          child: ListView(
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
          ),
        );
      },
    );
  }

  Widget _transition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(
          AppSheetLogic.pageOffset(
            incoming: animation.status != AnimationStatus.reverse,
            forward: _forward,
            progress: animation.value,
          ),
          0,
        ),
        child: child,
      ),
      child: Material(key: AppSheet.pageMaterialKey, color: context.skin.bgSurface, child: child),
    );
  }

  Widget _fade(Widget child, Animation<double> animation) => FadeTransition(opacity: animation, child: child);

  Widget _crossFade(Widget child) => AnimatedSwitcher(
        duration: AppMotion.sheetPush,
        switchInCurve: AppMotion.sheetPushCurve,
        switchOutCurve: AppMotion.sheetPushCurve.flipped,
        transitionBuilder: _fade,
        child: child,
      );

  Widget _header(AppSheetPage page, double frost) {
    final skin = context.skin;
    final depth = _pages.length;
    return NavigationToolbar(
      leading: _crossFade(
        depth > 1
            ? Center(
                key: const ValueKey<bool>(true),
                widthFactor: 1,
                heightFactor: 1,
                child: FrostedCircleButton(
                key: AppSheet.backKey,
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: 'Back',
                foreground: skin.textPrimary,
                  frost: frost,
                  onPressed: _pop,
                ),
              )
            : const SizedBox.shrink(key: ValueKey<bool>(false)),
      ),
      middle: _crossFade(
        AppText(
          page.title,
          key: ValueKey<int>(depth),
          style: AppTextStyle.style17Bold,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: _crossFade(
        page.actions.isEmpty
            ? SizedBox.shrink(key: ValueKey<int>(depth))
            : Row(
                key: ValueKey<int>(depth),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < page.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                    FrostedCapsule(frost: frost, child: page.actions[i]),
                  ],
                ],
              ),
      ),
      middleSpacing: GlassMetrics.toolbarItemGap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final page = _pages.last;
    final radius = BorderRadius.vertical(
      top: Radius.circular(AppSheetLogic.topCornerRadius()),
      bottom: Radius.circular(AppSheetLogic.cornerRadius()),
    );
    return _AppSheetScope(
      controller: _controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = AppSheetLogic.maxHeight(available: constraints.maxHeight, topSafe: media.padding.top);
          final fixed = AppSheetLogic.fixedHeight(widget.detent, media.size.height);
          final height = fixed == null ? null : math.min(fixed, maxHeight);
          final switcher = AnimatedSwitcher(
            duration: AppMotion.sheetPush,
            switchInCurve: AppMotion.sheetPushCurve,
            switchOutCurve: AppMotion.sheetPushCurve.flipped,
            transitionBuilder: _transition,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: _forward ? [...previous, ?current] : [?current, ...previous],
            ),
            child: _content(page, height == null),
          );
          final content = ClipRect(key: AppSheet.contentClipKey, clipper: const _BelowGrabberClipper(), child: switcher);
          final stack = Stack(
            children: [
              if (height == null) content else Positioned.fill(child: content),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: AppSheetMetrics.contentTop,
                child: ListenableBuilder(
                  listenable: _headerListenable,
                  builder: (context, _) => _HeaderBar(key: AppSheet.headerBarKey, visibility: _shownVisibility),
                ),
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
                child: ListenableBuilder(
                  listenable: _headerListenable,
                  builder: (context, _) => _header(page, _shownVisibility),
                ),
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
            child: ClipRSuperellipse(
              key: AppSheet.outerClipKey,
              borderRadius: radius,
              child: Stack(
                children: [
                  ListenableBuilder(
                    listenable: _headerListenable,
                    builder: (context, child) => ClipRSuperellipse(
                      key: AppSheet.layerClipKey,
                      borderRadius: radius,
                      clipBehavior: AppSheetLogic.surfaceClip(_shownVisibility),
                      child: child,
                    ),
                    child: DecoratedBox(
                      key: AppSheet.surfaceKey,
                      decoration: ShapeDecoration(
                        color: skin.bgSurface,
                        shape: RoundedSuperellipseBorder(borderRadius: radius),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: AnimatedSize(
                          duration: AppMotion.sheetPush,
                          curve: AppMotion.sheetPushCurve,
                          alignment: Alignment.bottomCenter,
                          child: height == null
                              ? ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: stack)
                              : SizedBox(height: height, child: stack),
                        ),
                      ),
                    ),
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
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BelowGrabberClipper extends CustomClipper<Rect> {
  const _BelowGrabberClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, AppSheetMetrics.headerTop, size.width, size.height);

  @override
  bool shouldReclip(_BelowGrabberClipper oldClipper) => false;
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({super.key, required this.visibility});

  final double visibility;

  static const double _tintAlpha = 0.45;

  @override
  Widget build(BuildContext context) {
    if (visibility <= 0) return const SizedBox.expand();
    final skin = context.skin;
    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: FrostedMaterial.filter(visibility),
          child: ColoredBox(
            color: skin.bgSurface.withValues(alpha: _tintAlpha * visibility),
            child: ColoredBox(
              color: skin.textPrimary.withValues(alpha: FrostedMaterial.lightenAlpha * visibility),
              child: const SizedBox.expand(),
            ),
          ),
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
      key: AppSheet.searchCapsuleKey,
      kind: GlassShapeKind.capsule,
      size: AppSheetMetrics.searchHeight,
      shadows: const [],
      tune: AppSheetLogic.calmGlass,
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
                autocorrect: false,
                enableSuggestions: false,
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
