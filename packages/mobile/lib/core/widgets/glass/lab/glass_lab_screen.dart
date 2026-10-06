import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_registry.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final skin = dark ? const DarkSkin() : const LightSkin();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: SkinScope(
        skin: skin,
        child: GlassTheme(
          data: GlassThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            accent: skin.accent,
            scrollEdgeTint: skin.scrollEdgeTint,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(child: GlassLabRegistry.build(launch)),
                const Positioned(left: 0, top: 0, child: GlassLabReady()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
