import 'dart:async';

import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/glass_toolbar.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

class GlassLabScreen extends StatefulWidget {
  const GlassLabScreen({super.key, required this.scene});

  final GlassLabScene scene;

  @override
  State<GlassLabScreen> createState() => _GlassLabScreenState();
}

class _GlassLabScreenState extends State<GlassLabScreen> {
  final _tabBarKey = GlobalKey();
  final _firstRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scene == GlassLabScene.lifted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 500), _injectLiftTouch));
      });
    }
    if (widget.scene == GlassLabScene.sheetscroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openScrollSheet());
    }
    if (widget.scene != GlassLabScene.sheet) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      final skin = dark ? const DarkSkin() : const LightSkin();
      showExpressiveSheet<void>(
        context: context,
        barrierColor: GlassSheetLogic.barrierColor(skin),
        builder: (_) => SkinScope(
          skin: skin,
          child: GlassSheetChrome(
            child: SizedBox(
              height: 430,
              child: Center(
                child: Text('Sheet', style: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary)),
              ),
            ),
          ),
        ),
      );
    });
  }

  void _openScrollSheet() {
    final labContext = _tabBarKey.currentContext;
    if (!mounted || labContext == null) return;
    final skin = labContext.skin;
    final page = AppSheetPage(
      title: 'Agent',
      searchHint: 'Search agents',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Done', style: AppTextStyle.style15SemiBold.copyWith(color: skin.accent)),
        ),
      ],
      rows: (context, query) => [
        for (var i = 0; i < 40; i++)
          if ('Agent row $i'.toLowerCase().contains(query.toLowerCase()))
            _ScrollRow(key: i == 0 ? _firstRowKey : null, index: i),
      ],
    );
    unawaited(
      showAppSheet<void>(
        context: labContext,
        page: AppSheetPage(
          title: 'Spawn',
          rows: (context, _) => [
            ListTile(
              title: Text('Agent', style: AppTextStyle.style17Regular.copyWith(color: skin.textPrimary)),
              onTap: () => AppSheet.of(context).push(page),
            ),
          ],
        ),
        pushed: [page],
        detent: AppSheetDetent.large,
        scope: (_, sheet) => SkinScope(skin: skin, child: sheet),
      ),
    );
    unawaited(Future<void>.delayed(const Duration(milliseconds: 5000), _scrollSheet));
  }

  void _scrollSheet() {
    final rowContext = _firstRowKey.currentContext;
    if (rowContext == null) return;
    Scrollable.maybeOf(rowContext)?.position.jumpTo(150);
  }

  void _injectLiftTouch() {
    final box = _tabBarKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final prsCenter = box.localToGlobal(Offset(box.size.width / 3 * 1.5, box.size.height / 2));
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 9001, position: prsCenter, kind: PointerDeviceKind.touch),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return SkinScope(
      skin: dark ? const DarkSkin() : const LightSkin(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(child: GlassLabBackdrop()),
            if (scene != GlassLabScene.corners) ...[
              const Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 140)),
              const Positioned(left: 0, right: 0, bottom: 0, child: ScrollEdgeEffect(edge: ScrollEdge.bottom, height: 120)),
            ],
            if (scene == GlassLabScene.corners)
              Center(
                child: SizedBox(
                  width: 300,
                  height: 200,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LiquidGlass.withOwnLayer(
                          settings: const LiquidGlassSettings(thickness: 12, blur: 0, glassColor: Color(0x00000000)),
                          shape: const LiquidRoundedSuperellipse(borderRadius: 60),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.all(Radius.circular(60)),
                                side: BorderSide(color: Color(0xFF000000), width: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Positioned(
                left: GlassMetrics.tabBarSideInset,
                right: GlassMetrics.tabBarSideInset,
                bottom: GlassMetrics.tabBarBottomInset,
                child: GlassTabBar(
                  key: _tabBarKey,
                  items: const [
                    GlassTabItem(icon: Icons.layers, label: 'Agents'),
                    GlassTabItem(icon: Icons.call_merge, label: 'PRs'),
                    GlassTabItem(icon: Icons.settings, label: 'Settings'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            if (scene != GlassLabScene.corners)
              Positioned(
                right: GlassMetrics.primaryButtonInset,
                bottom: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.primaryButtonBottomGap,
                child: GlassButton.label(
                  label: 'Run',
                  icon: Icons.play_arrow_rounded,
                  prominent: true,
                  compact: true,
                  onPressed: () {},
                ),
              ),
            if (scene != GlassLabScene.corners)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: GlassToolbar(
                  leading: GlassButton.icon(icon: Icons.arrow_back_ios_new_rounded, onPressed: () {}),
                  title: 'Agents',
                  trailing: [GlassButton.label(label: 'Edit', onPressed: () {})],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrollRow extends StatelessWidget {
  const _ScrollRow({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final hue = (index * 37) % 360;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: HSLColor.fromAHSL(1, hue.toDouble(), 0.75, 0.5).toColor(),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agent row $index', style: AppTextStyle.style17Regular.copyWith(color: skin.textPrimary)),
              Text('Needs install', style: AppTextStyle.style15Regular.copyWith(color: skin.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}
