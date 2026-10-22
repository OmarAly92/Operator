import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

@internal
class ClipHitBypass extends SingleChildRenderObjectWidget {
  const ClipHitBypass({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderClipHitBypass();
}

@internal
class RenderClipHitBypass extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final clip = child;
    final content = clip is RenderProxyBox ? clip.child : null;
    if (content == null) return super.hitTest(result, position: position);
    return content.hitTest(result, position: position);
  }
}
