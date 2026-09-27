import 'dart:io';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';

class GlassLabBackdrop extends StatelessWidget {
  const GlassLabBackdrop({super.key, required this.id});

  static const Color missingColor = Color(0xFF808080);

  final String id;

  static File file(String id) => File('${GlassLabLaunch.directory.path}/$id.png');

  @override
  Widget build(BuildContext context) {
    if (id == 'none') return ColoredBox(color: context.skin.bgBase, child: const SizedBox.expand());
    if (id == 'scroll') return const GlassLabScrollBackdrop();
    return SizedBox.expand(
      child: Image.file(
        file(id),
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) => const ColoredBox(color: missingColor),
      ),
    );
  }
}

class GlassLabScrollBackdrop extends StatelessWidget {
  const GlassLabScrollBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return GlassLabMarker(
      'scroll.content',
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Image.file(
          GlassLabBackdrop.file('scroll'),
          width: size.width,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, _, _) => SizedBox(
            width: size.width,
            height: size.height * 3,
            child: const ColoredBox(color: GlassLabBackdrop.missingColor),
          ),
        ),
      ),
    );
  }
}
