import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

sealed class LabPresentationScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'sheet.detents': (launch) => _SheetScene(backdrop: launch.backdrop),
  };
}

class _SheetScene extends StatefulWidget {
  const _SheetScene({required this.backdrop});

  final String backdrop;

  @override
  State<_SheetScene> createState() => _SheetSceneState();
}

class _SheetSceneState extends State<_SheetScene> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    if (!mounted) return;
    final skin = context.skin;
    unawaited(
      showAppSheet<void>(
        context: context,
        detent: AppSheetDetent.medium,
        page: AppSheetPage(
          title: 'Sheet',
          rows: (context, _) => const [GlassLabMarker('sheet.top', child: SizedBox(height: 56))],
        ),
        scope: (_, sheet) => SkinScope(skin: skin, child: sheet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GlassLabBackdrop(id: widget.backdrop);
}
