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
  static const double liftScale = 1.15;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  double? _dragX;
  double _lastDx = 0;
  int? _activePointer;

  void _down(PointerDownEvent event) {
    if (_activePointer != null) return;
    setState(() {
      _activePointer = event.pointer;
      _dragX = event.localPosition.dx;
      _lastDx = 0;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _dragX = event.localPosition.dx;
      _lastDx = event.delta.dx;
    });
  }

  void _up(PointerUpEvent event, double width) {
    if (event.pointer != _activePointer) return;
    final slot = GlassTabBarLogic.slotAt(event.localPosition.dx, width, widget.items.length);
    setState(() {
      _activePointer = null;
      _dragX = null;
      _lastDx = 0;
    });
    Haptics.select();
    widget.onSelected(slot);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _activePointer = null;
      _dragX = null;
      _lastDx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: GlassMetrics.tabBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final count = widget.items.length;
          final slotWidth = width / count;
          final dropletWidth = slotWidth - GlassMetrics.dropletInset * 2;
          final dropletHeight = GlassMetrics.tabBarHeight - GlassMetrics.dropletInset * 2;
          final lifted = _dragX != null;
          final centerX = _dragX ?? GlassTabBarLogic.slotCenter(widget.selectedIndex, width, count);
          final left = GlassTabBarLogic.dropletLeft(centerX: centerX, dropletWidth: dropletWidth, barWidth: width);
          final stretch = lifted && !reduceMotion ? GlassTabBarLogic.stretchFor(_lastDx) : 1.0;
          final lift = lifted && !reduceMotion ? GlassTabBar.liftScale : 1.0;
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
                      curve: AppMotion.spring,
                      left: left,
                      top: GlassMetrics.dropletInset,
                      width: dropletWidth,
                      height: dropletHeight,
                      child: AnimatedScale(
                        scale: lift,
                        duration: AppMotion.base,
                        curve: AppMotion.spring,
                        child: Transform.scale(
                          scaleX: stretch,
                          scaleY: 1 / stretch,
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
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _TabItemView(
                              item: widget.items[i],
                              selected: i == widget.selectedIndex,
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
  const _TabItemView({required this.item, required this.selected});

  final GlassTabItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = selected ? skin.accent : skin.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 24, color: color),
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
