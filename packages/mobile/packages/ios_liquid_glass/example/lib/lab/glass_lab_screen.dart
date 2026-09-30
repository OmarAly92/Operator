import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import 'glass_lab_launch.dart';
import 'glass_lab_marker.dart';
import 'glass_lab_probe.dart';
import 'glass_lab_registry.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: GlassMaterialOverride(
        values: launch.material,
        side: launch.materialSide,
        child: GlassLabAccessibilityProbe(
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
