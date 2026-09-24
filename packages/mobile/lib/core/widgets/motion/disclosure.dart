import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

class DisclosureChevron extends StatelessWidget {
  const DisclosureChevron({
    super.key,
    required this.expanded,
    this.size = 14,
    this.color,
    this.collapsedTurns = 0,
    this.expandedTurns = 0.25,
  });

  final bool expanded;
  final double size;
  final Color? color;
  final double collapsedTurns;
  final double expandedTurns;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? expandedTurns : collapsedTurns,
      duration: AppMotion.disclosure,
      curve: AppMotion.easeOut,
      child: Icon(Icons.keyboard_arrow_down, size: size, color: color),
    );
  }
}

class Disclosure extends StatelessWidget {
  const Disclosure({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: AppMotion.disclosure,
        curve: AppMotion.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: expanded ? AppMotion.disclosureIn : AppMotion.disclosureOut,
          switchInCurve: AppMotion.easeOut,
          switchOutCurve: AppMotion.easeOut,
          transitionBuilder: (transitionChild, animation) =>
              FadeTransition(opacity: animation, child: transitionChild),
          child: expanded
              ? KeyedSubtree(key: const ValueKey('expanded'), child: child)
              : const SizedBox.shrink(key: ValueKey('collapsed')),
        ),
      ),
    );
  }
}
