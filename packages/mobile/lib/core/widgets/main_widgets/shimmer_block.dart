import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:shimmer/shimmer.dart';

/// A skeleton-loading block matching the prototype's `SHIMMER` helper
/// (`docs/design/motion.md`'s `saShimmer` sweep): [AppSkin.shimmerBase] base
/// with an [AppSkin.shimmerHi] highlight sweeping across every
/// [AppMotion.shimmer].
///
/// Animates perpetually while mounted (the `shimmer` package doesn't check
/// `disableAnimations`); only use this for genuinely transient loading
/// states — like [AppLoader], if it can be the LAST thing on screen when a
/// test calls `pumpAndSettle`, that call will hang (see
/// `docs/design/components.md`).
class ShimmerBlock extends StatelessWidget {
  const ShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppConstants.radiusSm,
  });

  /// A pill-shaped shimmer block (radius [AppConstants.radiusPill]) — the
  /// prototype's `skelPill`/`skelPillWide`/`skelChip`.
  const ShimmerBlock.pill({super.key, required this.width, required this.height})
    : borderRadius = AppConstants.radiusPill;

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Shimmer.fromColors(
      baseColor: skin.shimmerBase,
      highlightColor: skin.shimmerHi,
      period: AppMotion.shimmer,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: skin.shimmerBase,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
