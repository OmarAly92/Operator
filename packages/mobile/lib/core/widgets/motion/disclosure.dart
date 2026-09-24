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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedRotation(
      turns: expanded ? expandedTurns : collapsedTurns,
      duration: reduceMotion ? Duration.zero : AppMotion.disclosure,
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
    if (MediaQuery.disableAnimationsOf(context)) {
      return ClipRect(child: expanded ? child : const SizedBox.shrink());
    }

    final switchDuration = expanded ? AppMotion.disclosureIn : AppMotion.disclosureOut;
    return ClipRect(
      child: AnimatedSize(
        duration: AppMotion.disclosure,
        curve: AppMotion.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: switchDuration,
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
