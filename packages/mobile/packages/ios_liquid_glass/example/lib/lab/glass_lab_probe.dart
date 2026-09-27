import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import 'glass_lab_launch.dart';

void writeLabFile(String name, Object json) {
  final directory = GlassLabLaunch.directory;
  if (directory.path.isEmpty || !directory.existsSync()) return;
  final partial = File('${directory.path}/$name.partial');
  partial.writeAsStringSync(jsonEncode(json));
  partial.renameSync('${directory.path}/$name');
}

class GlassLabAccessibilityProbe extends StatefulWidget {
  const GlassLabAccessibilityProbe({super.key, required this.child});

  static const String file = 'accessibility.json';

  final Widget child;

  @override
  State<GlassLabAccessibilityProbe> createState() => _GlassLabAccessibilityProbeState();
}

class _GlassLabAccessibilityProbeState extends State<GlassLabAccessibilityProbe> {
  GlassAccessibilityData? _written;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final data = GlassAccessibility.of(context);
        if (data != _written) {
          _written = data;
          writeLabFile(GlassLabAccessibilityProbe.file, {
            'reduceTransparency': data.reduceTransparency,
            'increaseContrast': data.increaseContrast,
            'reduceMotion': data.reduceMotion,
          });
        }
        return widget.child;
      },
    );
  }
}
