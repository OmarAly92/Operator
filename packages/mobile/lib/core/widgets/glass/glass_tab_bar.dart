import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
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
  static const double liftScale = 1.3;
  static const double stretchVelocityDivisor = 400;
  static const Duration stretchIdleDelay = Duration(milliseconds: 80);

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  double? _dragX;
  int? _activePointer;
  VelocityTracker? _velocityTracker;
  double _stretchTarget = 1.0;
  Timer? _stretchIdleTimer;

  void _down(PointerDownEvent event) {
    if (_activePointer != null) return;
    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker!.addPosition(event.timeStamp, event.position);
    setState(() {
      _activePointer = event.pointer;
      _dragX = event.localPosition.dx;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    _scheduleStretchDecay();
    setState(() {
      _dragX = event.localPosition.dx;
      _stretchTarget = GlassTabBarLogic.stretchFor(velocity / GlassTabBar.stretchVelocityDivisor);
    });
  }

  void _up(PointerUpEvent event, double width) {
    if (event.pointer != _activePointer) return;
    final selects = GlassTabBarLogic.releaseSelects(event.localPosition, width, GlassMetrics.tabBarHeight);
    final slot = GlassTabBarLogic.slotAt(event.localPosition.dx, width, widget.items.length);
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
    _stretchIdleTimer?.cancel();
    _velocityTracker = null;
    setState(() {
      _activePointer = null;
      _dragX = null;
      _stretchTarget = 1.0;
    });
  }

  void _scheduleStretchDecay() {
    _stretchIdleTimer?.cancel();
    _stretchIdleTimer = Timer(GlassTabBar.stretchIdleDelay, () {
      if (!mounted) return;
      setState(() => _stretchTarget = 1.0);
    });
  }

  void _selectByTap(int index) {
    Haptics.select();
    widget.onSelected(index);
  }

  @override
  void dispose() {
    _stretchIdleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final curve = reduceMotion ? AppMotion.easeOut : AppMotion.spring;
    return SizedBox(
      height: GlassMetrics.tabBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final count = widget.items.length;
          final slotWidth = width / count;
          final dropletWidth = slotWidth - GlassMetrics.dropletInset * 2;
          final restHeight = GlassMetrics.tabBarHeight - GlassMetrics.dropletInset * 2;
          final lifted = _dragX != null;
          final liftActive = lifted && !reduceMotion;
          final dropletHeight = liftActive ? restHeight * GlassTabBar.liftScale : restHeight;
          final top = (GlassMetrics.tabBarHeight - dropletHeight) / 2;
          final centerX = _dragX ?? GlassTabBarLogic.slotCenter(widget.selectedIndex, width, count);
          final left = GlassTabBarLogic.dropletLeft(centerX: centerX, dropletWidth: dropletWidth, barWidth: width);
          final stretch = liftActive ? _stretchTarget : 1.0;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (event) => _up(event, width),
            onPointerCancel: _cancel,
            child: GlassScope(
              variant: GlassVariant.regular,
              size: GlassMetrics.tabBarHeight,
              child: LiquidGlassBlendGroup(
                blend: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: GlassSurface(
                        kind: GlassShapeKind.capsule,
                        size: GlassMetrics.tabBarHeight,
                        grouped: true,
                        child: SizedBox.expand(),
                      ),
                    ),
                    AnimatedPositioned(
                      key: GlassTabBar.dropletKey,
                      duration: lifted ? Duration.zero : AppMotion.slow,
                      curve: curve,
                      left: left,
                      top: top,
                      width: dropletWidth,
                      height: dropletHeight,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: stretch),
                        duration: AppMotion.base,
                        curve: curve,
                        builder: (context, animatedStretch, child) => Transform.scale(
                          scaleX: animatedStretch,
                          scaleY: 1 / animatedStretch,
                          child: child,
                        ),
                        child: lifted
                            ? const GlassSurface(
                                kind: GlassShapeKind.capsule,
                                size: GlassMetrics.tabBarHeight,
                                grouped: true,
                                child: SizedBox.expand(),
                              )
                            : DecoratedBox(
                                decoration: ShapeDecoration(color: skin.bgSubtle, shape: const StadiumBorder()),
                              ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _TabItemView(
                              item: widget.items[i],
                              selected: i == widget.selectedIndex,
                              onTap: () => _selectByTap(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabItemView extends StatelessWidget {
  const _TabItemView({required this.item, required this.selected, required this.onTap});

  final GlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = selected ? skin.accentText : skin.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: GlassMetrics.tabGlyph, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
            style: AppTextStyle.style11SemiBold.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
