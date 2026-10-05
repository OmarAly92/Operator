import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:meta/meta.dart';

@internal
class GlassCoordinatorSpace extends SingleChildRenderObjectWidget {
  const GlassCoordinatorSpace({super.key, required this.coordinator, super.child});

  final GlassMotionCoordinator coordinator;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassCoordinatorSpace(coordinator);

  @override
  void updateRenderObject(BuildContext context, RenderGlassCoordinatorSpace renderObject) {
    renderObject.coordinator = coordinator;
  }
}

@internal
class RenderGlassCoordinatorSpace extends RenderProxyBox {
  RenderGlassCoordinatorSpace(this._coordinator);

  GlassMotionCoordinator _coordinator;
  set coordinator(GlassMotionCoordinator value) {
    if (_coordinator == value) return;
    if (_coordinator.marker == this) _coordinator.marker = null;
    _coordinator = value;
    if (attached) _coordinator.marker = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _coordinator.marker = this;
  }

  @override
  void detach() {
    if (_coordinator.marker == this) _coordinator.marker = null;
    super.detach();
  }
}

@internal
class GlassMemberBox extends SingleChildRenderObjectWidget {
  const GlassMemberBox({super.key, required this.member, super.child});

  final GlassMember member;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassMemberBox(member);

  @override
  void updateRenderObject(BuildContext context, RenderGlassMemberBox renderObject) {
    renderObject.member = member;
  }
}

@internal
class RenderGlassMemberBox extends RenderProxyBox {
  RenderGlassMemberBox(this._member);

  GlassMember _member;
  GlassMember get member => _member;
  set member(GlassMember value) {
    if (identical(_member, value)) return;
    if (attached) {
      _member.detachBox(this);
      value.attachBox(this);
    }
    _member = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _member.attachBox(this);
  }

  @override
  void detach() {
    _member.detachBox(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _member.sized(size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _member.sync();
    super.paint(context, offset);
  }
}
