import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

class IncomingResponse extends StatelessWidget {
  const IncomingResponse({
    super.key,
    required this.blockId,
    required this.animate,
    required this.child,
  });

  final String blockId;
  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate && !reduceMotion ? 0.4 : 1.0, end: 1.0),
      duration: reduceMotion ? Duration.zero : AppMotion.base,
      curve: AppMotion.easeOut,
      builder: (context, opacity, child) => Opacity(
        key: ValueKey('response-opacity-$blockId'),
        opacity: reduceMotion ? 1 : opacity,
        child: child,
      ),
      child: child,
    );
  }
}
