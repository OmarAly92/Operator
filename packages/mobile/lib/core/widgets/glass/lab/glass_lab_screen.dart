import 'package:flutter/material.dart';
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
    return SkinScope(
      skin: dark ? const DarkSkin() : const LightSkin(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(child: GlassLabRegistry.build(launch)),
            const Positioned(left: 0, top: 0, child: GlassLabReady()),
          ],
        ),
      ),
    );
  }
}
