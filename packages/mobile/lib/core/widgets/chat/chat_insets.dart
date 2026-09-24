import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class ChatInsets extends InheritedWidget {
  const ChatInsets({super.key, required this.bottom, this.gap = 0, this.top = 0, required super.child});

  static const double listGap = 12;

  final ValueListenable<double> bottom;
  final double gap;
  final double top;

  double get inset => bottom.value + gap;

  static ChatInsets? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChatInsets>();

  @override
  bool updateShouldNotify(ChatInsets oldWidget) => bottom != oldWidget.bottom || gap != oldWidget.gap || top != oldWidget.top;
}

class MeasuredHeight extends SingleChildRenderObjectWidget {
  const MeasuredHeight({super.key, required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMeasuredHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderMeasuredHeight renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class RenderMeasuredHeight extends RenderProxyBox {
  RenderMeasuredHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && _reported == height) onHeight(height);
    });
  }
}
