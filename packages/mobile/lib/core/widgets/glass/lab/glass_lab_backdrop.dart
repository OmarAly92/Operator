import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassLabBackdrop extends StatelessWidget {
  const GlassLabBackdrop({super.key});

  static const double topBandHeight = 182;
  static const double bottomBandHeight = 180;
  static const double cardsTop = 20;
  static const double cardHeight = 72;
  static const double cardGap = 12;
  static const double sideMargin = 16;
  static const List<Color> stripes = [
    Color(0xFFE5484D),
    Color(0xFFE89527),
    Color(0xFFF0B45C),
    Color(0xFF1ACB64),
    Color(0xFF47BFFF),
    Color(0xFF8E6CF0),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.skin.bgBase,
      child: Column(
        children: [
          const SizedBox(height: topBandHeight, child: _Stripes()),
          Padding(
            padding: const EdgeInsets.fromLTRB(sideMargin, cardsTop, sideMargin, 0),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == 3 ? 0 : cardGap),
                    child: _LabCard(index: i),
                  ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: bottomBandHeight, child: _Stripes()),
        ],
      ),
    );
  }
}

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final color in GlassLabBackdrop.stripes) Expanded(child: ColoredBox(color: color))],
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      height: GlassLabBackdrop.cardHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        color: skin.bgSurface,
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('Session ${index + 1}', style: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary)),
          const SizedBox(height: 4),
          AppText('feat/branch-${index + 1}', style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
        ],
      ),
    );
  }
}
