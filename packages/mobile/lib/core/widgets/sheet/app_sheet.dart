import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
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
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final outgoing = animation.status == AnimationStatus.reverse;
          final side = outgoing == _forward ? -1.0 : 1.0;
          return FractionalTranslation(
            translation: Offset(side * (1 - animation.value), 0),
            child: child,
          );
        },
      ),
    );
  }

  Widget _header(AppSheetPage page) {
    final skin = context.skin;
    return NavigationToolbar(
      leading: _pages.length > 1
          ? Center(
              widthFactor: 1,
              heightFactor: 1,
              child: FrostedCircleButton(
                key: AppSheet.backKey,
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: 'Back',
                foreground: skin.textPrimary,
                onPressed: _pop,
              ),
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
                  FrostedCapsule(child: page.actions[i]),
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
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: AppSheetMetrics.contentTop,
                child: _HeaderBar(key: AppSheet.headerBarKey),
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

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({super.key});

  static const double _softenExtent = 10;
  static const double _blurSigma = 10;
  static const double _tintAlpha = 0.5;

  @override
  Widget build(BuildContext context) {
    final surface = context.skin.bgSurface;
    return IgnorePointer(
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSheetLogic.topCornerRadius())),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
                child: ColoredBox(color: surface.withValues(alpha: _tintAlpha), child: const SizedBox.expand()),
              ),
            ),
            SizedBox(
              height: _softenExtent,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [surface.withValues(alpha: _tintAlpha), surface.withValues(alpha: 0)],
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
