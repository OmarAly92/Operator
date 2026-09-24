import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/glass_toolbar.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.scene});

  final GlassLabScene scene;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return SkinScope(
      skin: dark ? const DarkSkin() : const LightSkin(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(child: GlassLabBackdrop()),
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
                  items: const [
                    GlassTabItem(icon: Icons.layers_outlined, label: 'Agents'),
                    GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
                    GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            if (scene != GlassLabScene.corners)
              Positioned(
                right: GlassMetrics.primaryButtonInset,
                bottom: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.primaryButtonInset,
                child: GlassButton.label(label: 'Run', icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
              ),
            if (scene != GlassLabScene.corners)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: GlassToolbar(
                  leading: GlassButton.icon(icon: Icons.chevron_left_rounded, onPressed: () {}),
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
