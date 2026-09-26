import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_lens.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar_logic.dart';

class GlassTabItem {
  const GlassTabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class GlassTabBar extends StatefulWidget {
  const GlassTabBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  static const Key dropletKey = ValueKey('glass-tab-bar-droplet');
  static const Key dropletBodyKey = ValueKey('glass-tab-bar-droplet-body');
  static const double pressScale = 1.053;
  static const double lensWidthScale = 1.115;
  static const double lensHeightScale = 1.13;
  static const double lensMagnify = 1.2;
  static const double lensShadowLight = 0.16;
  static const double lensShadowDark = 0.3;
  static const double lensShadowBlur = 4;
  static const double lensShadowOffset = 3;
  static const double lensShadowReach = 24;
  static const double glowEdge = 0.05;
  static const double glowLensEdge = 0.095;
  static const double glowLensCenter = 0.125;
  static const double followOmega = 38;
  static const double travelOmega = 18;
  static const double travelDamping = 0.8;
  static const double squashPerSpeed = 0.00028;
  static const double maxSquash = 0.12;
  static const double squashOmega = 14;
  static const double squashDamping = 0.2;
  static const double squashWidthShare = 0.6;
  static const Duration liftDuration = Duration(milliseconds: 300);
  static const Duration minLift = Duration(milliseconds: 120);
  static const double lensHandoff = 0.35;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> with SingleTickerProviderStateMixin {
  double? _dragX;
  int? _activePointer;
  Duration _downStamp = Duration.zero;
  double? _holdX;
  Timer? _holdTimer;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double? _lensX;
  double _lensVelocity = 0;
  double _target = 0;
  bool _following = false;
  bool _lifted = false;
  double _squash = 0;
  double _squashVelocity = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  void _down(PointerDownEvent event) {
    if (_activePointer != null) return;
    _holdTimer?.cancel();
    _downStamp = event.timeStamp;
    setState(() {
      _activePointer = event.pointer;
      _dragX = event.localPosition.dx;
      _holdX = null;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() => _dragX = event.localPosition.dx);
  }

  void _up(PointerUpEvent event, double width) {
    if (event.pointer != _activePointer) return;
    final selects = GlassTabBarLogic.releaseSelects(event.localPosition, width, GlassMetrics.tabBarHeight);
    final slot = GlassTabBarLogic.slotAt(event.localPosition.dx, width, widget.items.length);
    final remaining = GlassTabBar.minLift - (event.timeStamp - _downStamp);
    if (selects && remaining > Duration.zero && !MediaQuery.disableAnimationsOf(context)) {
      _holdX = event.localPosition.dx;
      _holdTimer = Timer(remaining, () {
        if (mounted) setState(() => _holdX = null);
      });
    }
    _endDrag();
    if (!selects) return;
    Haptics.select();
    widget.onSelected(slot);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _endDrag();
  }

  void _endDrag() {
    setState(() {
      _activePointer = null;
      _dragX = null;
    });
  }

  bool get _settled =>
      (_lensX! - _target).abs() < 0.05 &&
      _lensVelocity.abs() < 0.5 &&
      _squash.abs() < 0.001 &&
      _squashVelocity.abs() < 0.01;

  void _tick(Duration elapsed) {
    final seconds = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 30).toDouble();
    _lastTick = elapsed;
    final (x, v) = GlassTabBarLogic.springStep(
      value: _lensX!,
      velocity: _lensVelocity,
      target: _target,
      omega: _following ? GlassTabBar.followOmega : GlassTabBar.travelOmega,
      damping: _following ? 1 : GlassTabBar.travelDamping,
      seconds: seconds,
    );
    final squashTarget = _lifted ? -(v.abs() * GlassTabBar.squashPerSpeed).clamp(0.0, GlassTabBar.maxSquash) : 0.0;
    final (squash, squashVelocity) = GlassTabBarLogic.springStep(
      value: _squash,
      velocity: _squashVelocity,
      target: squashTarget,
      omega: GlassTabBar.squashOmega,
      damping: GlassTabBar.squashDamping,
      seconds: seconds,
    );
    setState(() {
      _lensX = x;
      _lensVelocity = v;
      _squash = squash;
      _squashVelocity = squashVelocity;
    });
    if (_settled) {
      _ticker.stop();
      _lensX = _target;
      _lensVelocity = 0;
      _squash = 0;
      _squashVelocity = 0;
    }
  }

  void _track({required double target, required bool following, required bool lifted, required bool still}) {
    _target = target;
    _following = following;
    _lifted = lifted;
    if (_lensX == null || still) {
      _lensX = target;
      _lensVelocity = 0;
      _squash = 0;
      _squashVelocity = 0;
      return;
    }
    if (_ticker.isActive || _settled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ticker.isActive) return;
      _lastTick = Duration.zero;
      _ticker.start();
    });
  }

  static LinearGradient _pressGlow(double center, double half, double lift) {
    Color white(double alpha) => const Color(0xFFFFFFFF).withValues(alpha: alpha * lift);
    final left = (center - half).clamp(0.0, 1.0).toDouble();
    final middle = center.clamp(left, 1.0).toDouble();
    final right = (center + half).clamp(middle, 1.0).toDouble();
    return LinearGradient(
      colors: [
        white(GlassTabBar.glowEdge),
        white(GlassTabBar.glowLensEdge),
        white(GlassTabBar.glowLensCenter),
        white(GlassTabBar.glowLensEdge),
        white(GlassTabBar.glowEdge),
      ],
      stops: [0, left, middle, right, 1],
    );
  }

  void _selectByTap(int index) {
    Haptics.select();
    widget.onSelected(index);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final dark = skin.themeMode == ThemeMode.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pillColor = dark ? const Color(0x24FFFFFF) : const Color(0x141A1612);
    return SizedBox(
      height: GlassMetrics.tabBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const height = GlassMetrics.tabBarHeight;
          final count = widget.items.length;
          final pillWidth = GlassTabBarLogic.pillWidth(width, count);
          const pillHeight = height - GlassMetrics.dropletInset * 2;
          final lensWidth = pillWidth * GlassTabBar.lensWidthScale;
          const lensHeight = height * GlassTabBar.lensHeightScale;
          final dragX = _dragX ?? _holdX;
          final dragging = dragX != null;
          final lifted = dragging && !reduceMotion;
          final targetCenter = dragging
              ? GlassTabBarLogic.lensCenter(dragX, width, count)
              : GlassTabBarLogic.slotCenter(widget.selectedIndex, width, count);
          final active = dragging ? GlassTabBarLogic.slotAt(targetCenter, width, count) : widget.selectedIndex;
          _track(target: targetCenter, following: dragging, lifted: lifted, still: reduceMotion);
          final centerX = _lensX!;
          final squash = _squash;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (event) => _up(event, width),
            onPointerCancel: _cancel,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: lifted ? 1 : 0),
              duration: GlassTabBar.liftDuration,
              curve: AppMotion.spring,
              builder: (context, lift, _) {
                final t = lift.clamp(0.0, 1.2).toDouble();
                final fade = lift.clamp(0.0, 1.0).toDouble();
                final barScale = 1 + (GlassTabBar.pressScale - 1) * lift;
                final dropletWidth =
                    (pillWidth + (lensWidth - pillWidth) * t) * (1 - squash * GlassTabBar.squashWidthShare);
                final dropletHeight = (pillHeight + (lensHeight - pillHeight) * t) * (1 + squash);
                final showLens = lift > 0.02 && (lifted || lift > GlassTabBar.lensHandoff);
                final dropletRect = _scaled(
                  Rect.fromCenter(center: Offset(centerX, height / 2), width: dropletWidth, height: dropletHeight),
                  barScale,
                  width,
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Transform.scale(
                        scale: barScale,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned.fill(
                              child: GlassSurface(
                                kind: GlassShapeKind.capsule,
                                size: GlassMetrics.tabBarHeight,
                                variant: GlassVariant.chrome,
                                child: SizedBox.expand(),
                              ),
                            ),
                            if (lift > 0)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: ShapeDecoration(
                                      gradient: _pressGlow(centerX / width, lensWidth / 2 / width, fade),
                                      shape: const StadiumBorder(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      key: GlassTabBar.dropletKey,
                      rect: dropletRect,
                      child: IgnorePointer(
                        child: KeyedSubtree(
                          key: GlassTabBar.dropletBodyKey,
                          child: showLens
                              ? const GlassLens()
                              : DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: pillColor.withValues(
                                      alpha: pillColor.a * (1 - lift / GlassTabBar.lensHandoff).clamp(0.0, 1.0),
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (showLens)
                      Positioned.fromRect(
                        rect: Rect.fromLTRB(
                          dropletRect.left - GlassTabBar.lensShadowReach,
                          dropletRect.top,
                          dropletRect.right + GlassTabBar.lensShadowReach,
                          dropletRect.bottom + GlassTabBar.lensShadowReach,
                        ),
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _LensShadowPainter(
                              lens: Rect.fromLTWH(
                                GlassTabBar.lensShadowReach,
                                0,
                                dropletRect.width,
                                dropletRect.height,
                              ),
                              color: const Color(0xFF000000).withValues(
                                alpha: (dark ? GlassTabBar.lensShadowDark : GlassTabBar.lensShadowLight) * fade,
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (var i = 0; i < count; i++)
                      Positioned.fromRect(
                        rect: _scaled(
                          Rect.fromCenter(
                            center: Offset(GlassTabBarLogic.slotCenter(i, width, count), height / 2),
                            width: pillWidth,
                            height: height,
                          ),
                          barScale,
                          width,
                        ),
                        child: Transform.scale(
                          scale:
                              barScale *
                              (1 +
                                  (GlassTabBar.lensMagnify - 1) *
                                      fade *
                                      GlassTabBarLogic.proximity(
                                        GlassTabBarLogic.slotCenter(i, width, count),
                                        centerX,
                                        lensWidth,
                                      )),
                          child: _TabItemView(
                            item: widget.items[i],
                            selected: i == active,
                            onTap: () => _selectByTap(i),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  static Rect _scaled(Rect rect, double scale, double width) {
    final origin = Offset(width / 2, GlassMetrics.tabBarHeight / 2);
    return Rect.fromCenter(
      center: origin + (rect.center - origin) * scale,
      width: rect.width * scale,
      height: rect.height * scale,
    );
  }
}

class _LensShadowPainter extends CustomPainter {
  const _LensShadowPainter({required this.lens, required this.color});

  final Rect lens;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(lens, Radius.circular(lens.shortestSide / 2));
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTRB(0, lens.top, size.width, size.height)),
      Path()..addRRect(shape),
    );
    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        shape.shift(const Offset(0, GlassTabBar.lensShadowOffset)),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, GlassTabBar.lensShadowBlur),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_LensShadowPainter oldDelegate) => oldDelegate.lens != lens || oldDelegate.color != color;
}

class _TabItemView extends StatelessWidget {
  const _TabItemView({required this.item, required this.selected, required this.onTap});

  final GlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: selected ? skin.accentText : skin.textPrimary),
        duration: AppMotion.fast,
        builder: (context, color, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: GlassMetrics.tabGlyph, color: color),
            const SizedBox(height: 1),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
              style: AppTextStyle.style10Medium.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
