import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';

Future<T?> showAppSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showExpressiveSheet<T>(
    context: context,
    barrierColor: GlassSheetLogic.barrierColor(context.skin),
    builder: builder,
  );
}

class AppSheetChrome extends StatelessWidget {
  const AppSheetChrome({super.key, required this.child, this.padding});

  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(16, 0, 16, 12);

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return GlassSheetChrome(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding ?? defaultPadding, child: child),
        ),
      ),
    );
  }
}
