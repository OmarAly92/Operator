import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/motion/glass_press.dart';
import 'package:ios_liquid_glass/src/motion/ios27_press.dart';

@internal
class GlassPressTarget extends SingleChildRenderObjectWidget {
  const GlassPressTarget({super.key, required this.member, required this.shape, this.scrolling, super.child});

  final GlassMember member;
  final LiquidShape shape;
  final ScrollPosition? scrolling;

  @override
  RenderGlassPressTarget createRenderObject(BuildContext context) => RenderGlassPressTarget(member: member, shape: shape, scrolling: scrolling);

  @override
  void updateRenderObject(BuildContext context, RenderGlassPressTarget renderObject) {
    renderObject
      ..member = member
      ..shape = shape
      ..scrolling = scrolling;
  }
}

@internal
class RenderGlassPressTarget extends RenderProxyBoxWithHitTestBehavior {
  RenderGlassPressTarget({required GlassMember member, required this.shape, ScrollPosition? scrolling})
    : _member = member,
      _scrolling = scrolling,
      super(behavior: HitTestBehavior.opaque);

  static final Map<int, RenderGlassPressTarget> _owners = {};

  @visibleForTesting
  static Iterable<int> get claimedPointers => _owners.keys;

  GlassMember _member;
  LiquidShape shape;
  ScrollPosition? _scrolling;
  int? _pointer;
  double? _pixelsAtDown;

  GlassMember get member => _member;
  set member(GlassMember value) {
    if (identical(value, _member)) return;
    _release();
    _member = value;
  }

  set scrolling(ScrollPosition? value) {
    if (identical(value, _scrolling)) return;
    if (attached) _scrolling?.removeListener(_scrolled);
    _scrolling = value;
    if (attached) _scrolling?.addListener(_scrolled);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrolling?.addListener(_scrolled);
  }

  @override
  void detach() {
    _scrolling?.removeListener(_scrolled);
    super.detach();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _scrolled() {
    final position = _scrolling;
    if (position == null || _pointer == null || !position.hasPixels) return;
    if (position.pixels != _pixelsAtDown) _release();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (!shape.getOuterPath(Offset.zero & size).contains(position)) return hitTestChildren(result, position: position);
    return super.hitTest(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      if (_pointer != null || _owners.containsKey(event.pointer)) return;
      _owners[event.pointer] = this;
      _pointer = event.pointer;
      final position = _scrolling;
      _pixelsAtDown = position != null && position.hasPixels ? position.pixels : null;
      _member.pressDown(event.localPosition);
      return;
    }
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _member.pressMove(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _release();
    }
  }

  void _release() {
    final pointer = _pointer;
    if (pointer == null) return;
    _pointer = null;
    if (identical(_owners[pointer], this)) _owners.remove(pointer);
    _member.pressUp();
  }
}

@internal
class GlassPressGlow extends CustomPainter {
  GlassPressGlow(this.member) : super(repaint: member);

  final GlassMember member;

  static const List<double> _stops = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final press = member.press;
    final hold = press.hold, swell = press.swell;
    if (hold == 0 && swell == 0) return;
    final (holdAlpha, swellAlpha) = GlassPress.glowFor(size);
    final rect = Offset.zero & size;
    if (hold > 0 && holdAlpha > 0) {
      canvas.drawRect(rect, Paint()
        ..color = Color.fromRGBO(255, 255, 255, (holdAlpha * hold).clamp(0.0, 1.0))
        ..blendMode = BlendMode.plus);
    }
    if (swell > 0 && swellAlpha > 0) {
      const reach = 3.0;
      final radius = ios27PressGlowSigma * reach;
      final peak = (swellAlpha * swell).clamp(0.0, 1.0);
      canvas.drawRect(rect, Paint()
        ..shader = RadialGradient(
          colors: [for (final stop in _stops) Color.fromRGBO(255, 255, 255, peak * math.exp(-(stop * reach) * (stop * reach) / 2))],
          stops: _stops,
        ).createShader(Rect.fromCircle(center: press.focus, radius: radius))
        ..blendMode = BlendMode.plus);
    }
  }

  @override
  bool shouldRepaint(GlassPressGlow oldDelegate) => !identical(oldDelegate.member, member);
}

@visibleForTesting
({bool pressed, double scale, double light}) debugGlassPress(Element element) {
  RenderGlassMemberBox? found;
  void visit(Element child) {
    if (found != null) return;
    final render = child.renderObject;
    if (child is RenderObjectElement && render is RenderGlassMemberBox) {
      found = render;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  final member = found?.member;
  if (member == null) return (pressed: false, scale: 1, light: 0);
  return (pressed: member.press.isPressed, scale: member.contentScale, light: member.press.hold + member.press.swell);
}
