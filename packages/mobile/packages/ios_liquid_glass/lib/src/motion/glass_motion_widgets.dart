import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
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

@internal
class GlassSnapshotBoundary extends SingleChildRenderObjectWidget {
  const GlassSnapshotBoundary({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassSnapshotBoundary();
}

@internal
class RenderGlassSnapshotBoundary extends RenderRepaintBoundary {
  LayerHandle<OffsetLayer>? retain() {
    final painted = layer;
    if (painted is! OffsetLayer || !hasSize || size.isEmpty) return null;
    return LayerHandle<OffsetLayer>()..layer = painted;
  }
}

@internal
class GlassGhostHost extends StatelessWidget {
  const GlassGhostHost({super.key, required this.coordinator});

  final GlassMotionCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        coordinator.ghostHost = context as Element;
        final ghosts = coordinator.takeGhosts();
        return IgnorePointer(
          child: ExcludeSemantics(
            child: _GhostStack(
              children: [for (final ghost in ghosts) _GhostSlot(key: ObjectKey(ghost), global: ghost.rect, child: _Ghost(ghost: ghost))],
            ),
          ),
        );
      },
    );
  }
}

class _GhostParentData extends ContainerBoxParentData<RenderBox> {
  Rect global = Rect.zero;
}

class _GhostSlot extends ParentDataWidget<_GhostParentData> {
  const _GhostSlot({super.key, required this.global, required super.child});

  final Rect global;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _GhostParentData;
    if (data.global == global) return;
    data.global = global;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _GhostStack;
}

class _GhostStack extends MultiChildRenderObjectWidget {
  const _GhostStack({super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGhostStack();
}

class _RenderGhostStack extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _GhostParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GhostParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GhostParentData) child.parentData = _GhostParentData();
  }

  @override
  void performLayout() {
    size = constraints.biggest.isFinite ? constraints.biggest : constraints.smallest;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _GhostParentData;
      child.layout(BoxConstraints.tight(data.global.size));
      child = data.nextSibling;
    }
  }

  Offset _placement(RenderBox child) => globalToLocal((child.parentData! as _GhostParentData).global.topLeft);

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      context.paintChild(child, offset + _placement(child));
      child = childAfter(child);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final placement = _placement(child);
    transform.translateByDouble(placement.dx, placement.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.ghost});

  final GlassGhost ghost;

  @override
  Widget build(BuildContext context) {
    final snapshot = ghost.snapshot;
    return LiquidGlass.withOwnLayer(
      settings: ghost.settings,
      shape: ghost.shape,
      shadows: ghost.shadows,
      visibility: ghost.member.visibility,
      child: SizedBox.fromSize(
        size: ghost.rect.size,
        child: snapshot == null
            ? null
            : OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: RawImage(image: snapshot, scale: ghost.pixelRatio),
              ),
      ),
    );
  }
}
