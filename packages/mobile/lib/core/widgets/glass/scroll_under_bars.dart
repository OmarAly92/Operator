import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';

class ScrollUnderBars extends StatelessWidget {
  const ScrollUnderBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ScrollEdgeEffect(edge: ScrollEdge.top, height: top + GlassMetrics.topEdgeFadeExtent),
        ),
      ],
    );
  }
}
