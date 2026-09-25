import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';

class BoardSkeleton extends StatelessWidget {
  const BoardSkeleton({super.key});

  static const int cardCount = 6;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return Semantics(
      label: 'Loading agents',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: insets.top + 12, bottom: insets.bottom + 40),
        children: [for (var i = 0; i < cardCount; i++) const _SkeletonCard()],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget bar(double width, double height, {double radius = AppConstants.radiusSm}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: skin.shimmerBase, borderRadius: BorderRadius.circular(radius)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AppContainer(
        padding: const EdgeInsets.all(13),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: skin.borderDefault),
        child: Shimmer(
          base: skin.shimmerBase,
          highlight: skin.shimmerHi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  bar(20, 20, radius: AppConstants.radiusPill),
                  const HorizontalSpace(9),
                  bar(150, 14),
                  const Spacer(),
                  bar(64, 20, radius: AppConstants.radiusPill),
                ],
              ),
              const VerticalSpace(10),
              Padding(padding: const EdgeInsets.only(left: 29), child: bar(210, 11)),
              const VerticalSpace(7),
              Padding(padding: const EdgeInsets.only(left: 29), child: bar(120, 11)),
            ],
          ),
        ),
      ),
    );
  }
}
