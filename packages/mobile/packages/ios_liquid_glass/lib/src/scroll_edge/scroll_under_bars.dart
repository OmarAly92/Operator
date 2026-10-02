import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/material/scroll_edge_material.dart';
import 'package:ios_liquid_glass/src/scroll_edge/scroll_edge_effect.dart';

class ScrollUnderBars extends StatefulWidget {
  const ScrollUnderBars({super.key, this.style = ScrollEdgeStyle.automatic, required this.child});

  final ScrollEdgeStyle style;
  final Widget child;

  @override
  State<ScrollUnderBars> createState() => _ScrollUnderBarsState();
}

class _ScrollUnderBarsState extends State<ScrollUnderBars> {
  final ValueNotifier<double> _visibility = ValueNotifier<double>(0);

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  bool _onScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _visibility.value = ScrollEdgeEffect.topVisibility(metrics);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final extent = ScrollEdgeEffect.materialOf(context, widget.style)['extent'];
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<Notification>(onNotification: _onScroll, child: widget.child),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _visibility,
            builder: (context, visibility, _) => ScrollEdgeEffect(
              edge: ScrollEdge.top,
              style: widget.style,
              height: top + extent,
              visibility: visibility,
              capExtent: top,
            ),
          ),
        ),
      ],
    );
  }
}
