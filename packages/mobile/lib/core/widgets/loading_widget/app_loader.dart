import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.isCentered = false, this.strokeWidth = 4})
    : isPagination = false;

  const AppLoader.center({super.key, this.strokeWidth = 4})
    : isCentered = true,
      isPagination = false;

  const AppLoader.pagination({super.key, this.strokeWidth = 4})
    : isCentered = true,
      isPagination = true;

  final bool isCentered;
  final bool isPagination;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (isPagination) {
      return const CupertinoActivityIndicator();
    }
    if (isCentered) {
      return Center(
        child: CircularProgressIndicator(
          color: context.skin.accent,
          strokeWidth: strokeWidth,
        ),
      );
    }
    return CircularProgressIndicator(
      color: context.skin.accent,
      strokeWidth: strokeWidth,
    );
  }
}

/// The branded, "expressive" loading state matching the prototype's
/// `loaderSvg` shape-morph — a soft-burst/cookie/pentagon/pill/sunny cycle
/// (`docs/design/motion.md`). Backed by [LoadingIndicator] from
/// `package:expressive_loading_indicator`, which already ports the same
/// Material 3 Expressive shape sequence and 650ms pop timing
/// (`AppMotion.loaderPop`) the prototype uses — no need to re-derive the
/// shape math by hand. Use this for a screen's dedicated loading state (e.g.
/// "Syncing agents…"); use the plain [AppLoader] for small inline spinners.
///
/// Animates perpetually while mounted — only safe for genuinely transient
/// loading states. If it can still be on screen when a test calls
/// `pumpAndSettle`, that call will hang (see `docs/design/components.md`).
class AppExpressiveLoader extends StatelessWidget {
  const AppExpressiveLoader({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final indicator = LoadingIndicator(activeIndicatorColor: skin.accent);
    if (label == null) return indicator;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const VerticalSpace(12),
        AppText(
          label!,
          style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
        ),
      ],
    );
  }
}
