import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

sealed class GlassSheetLogic {
  static bool isFloating({required double sheetHeight, required double screenHeight}) =>
      sheetHeight < screenHeight * GlassMetrics.floatingSheetMaxFraction;

  static double cornerRadius() => GlassMetrics.displayCornerRadius - GlassMetrics.sheetInset;
}

class GlassSheetChrome extends StatelessWidget {
  const GlassSheetChrome({super.key, required this.child});

  static const Key floatingKey = ValueKey('glass-sheet-floating');
  static const Key anchoredKey = ValueKey('glass-sheet-anchored');

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final screen = MediaQuery.sizeOf(context);
    final grabber = Center(
      child: Container(
        width: 36,
        height: 5,
        margin: const EdgeInsets.only(top: 6, bottom: 10),
        decoration: BoxDecoration(
          color: skin.borderStrong,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
        ),
      ),
    );
    final body = Column(mainAxisSize: MainAxisSize.min, children: [grabber, child]);
    return _MeasuredSheet(
      builder: (height) {
        if (height == null || GlassSheetLogic.isFloating(sheetHeight: height, screenHeight: screen.height)) {
          return Padding(
            key: floatingKey,
            padding: const EdgeInsets.fromLTRB(
              GlassMetrics.sheetInset,
              0,
              GlassMetrics.sheetInset,
              GlassMetrics.sheetInset,
            ),
            child: GlassSurface(
              kind: GlassShapeKind.rect,
              radius: GlassSheetLogic.cornerRadius(),
              size: screen.shortestSide,
              child: body,
            ),
          );
        }
        return DecoratedBox(
          key: anchoredKey,
          decoration: ShapeDecoration(
            color: skin.bgSurface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(GlassSheetLogic.cornerRadius())),
            ),
          ),
          child: SafeArea(top: false, child: body),
        );
      },
    );
  }
}

class _MeasuredSheet extends StatefulWidget {
  const _MeasuredSheet({required this.builder});

  final Widget Function(double? height) builder;

  @override
  State<_MeasuredSheet> createState() => _MeasuredSheetState();
}

class _MeasuredSheetState extends State<_MeasuredSheet> {
  double? _height;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return widget.builder(_height);
          },
        ),
      ),
    );
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_height == null || (h - _height!).abs() > 0.5) setState(() => _height = h);
  }
}

Future<T?> showGlassSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showExpressiveSheet<T>(
    context: context,
    barrierColor: const Color(0x00000000),
    builder: (context) => GlassSheetChrome(child: builder(context)),
  );
}
