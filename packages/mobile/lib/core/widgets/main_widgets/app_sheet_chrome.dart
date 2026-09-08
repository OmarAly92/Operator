import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';

/// The visual container every bottom sheet uses with `showExpressiveSheet`
/// (`packages/expressive_sheet`), which only supplies the spring-driven
/// route/gesture — no background, radius, handle, or shadow of its own.
/// Matches the prototype's `S.sheet`/`S.sheetHandle` spec
/// (`docs/design/components.md`): `bgSurface`, top corners at
/// [AppConstants.radiusCard], a centered pill handle, "Bottom sheet" shadow
/// recipe from `docs/design/colors.md`.
class AppSheetChrome extends StatelessWidget {
  const AppSheetChrome({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Material(
      color: skin.bgSurface,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppConstants.radiusCard),
        topRight: Radius.circular(AppConstants.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: skin.scrim.withValues(alpha: 0.22),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: skin.borderStrong,
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
