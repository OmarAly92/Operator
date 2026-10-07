import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';

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

  final LayerHandle<_SpaceTrackingLayer> _tracking = LayerHandle();

  @override
  bool get alwaysNeedsCompositing => true;

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
    final layer = _tracking.layer ??= _SpaceTrackingLayer();
    layer.member = _member;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _tracking.layer = null;
    super.dispose();
  }
}

class _SpaceTrackingLayer extends ContainerLayer {
  GlassMember? member;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    member?.spaceComposited();
    addChildrenToScene(builder);
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
    if (!TickerMode.valuesOf(context).enabled) coordinator.dropGhosts();
    return LayoutBuilder(
      builder: (context, constraints) {
        coordinator.ghostHost = context as Element;
        final ghosts = coordinator.takeGhosts();
        return IgnorePointer(
          child: ExcludeSemantics(
            child: _GhostStack(
              coordinator: coordinator,
              children: [for (final ghost in ghosts) _GhostSlot(key: ObjectKey(ghost), ghost: ghost, child: _Ghost(ghost: ghost))],
            ),
          ),
        );
      },
    );
  }
}

@internal
class GlassOverlayGhosts {
  GlassOverlayGhosts._(this._overlay);

  static final Expando<GlassOverlayGhosts> _hosts = Expando();

  final OverlayState _overlay;
  OverlayEntry? _entry;
  bool _inserted = false;
  GlassMotionCoordinator? _coordinator;
  int _users = 0;

  static GlassOverlayGhosts? of(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return null;
    return _hosts[overlay] ??= GlassOverlayGhosts._(overlay);
  }

  GlassMotionCoordinator? get coordinator => _coordinator;

  void retain() {
    _users++;
    if (_entry != null) return;
    final entry = _entry = OverlayEntry(builder: (context) => _OverlayGhostLayer(host: this));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!identical(_entry, entry) || !_overlay.mounted) return;
      _overlay.insert(entry);
      _inserted = true;
    });
  }

  void release() {
    _users--;
    _removeIfIdle();
  }

  void _removeIfIdle() {
    final entry = _entry;
    if (_users > 0 || entry == null || (_coordinator?.hasGhosts ?? false)) return;
    _entry = null;
    if (_inserted) entry.remove();
    _inserted = false;
    SchedulerBinding.instance.addPostFrameCallback((_) => entry.dispose());
  }
}

class _OverlayGhostLayer extends StatefulWidget {
  const _OverlayGhostLayer({required this.host});

  final GlassOverlayGhosts host;

  @override
  State<_OverlayGhostLayer> createState() => _OverlayGhostLayerState();
}

class _OverlayGhostLayerState extends State<_OverlayGhostLayer> with SingleTickerProviderStateMixin {
  late final GlassMotionCoordinator _coordinator = GlassMotionCoordinator(vsync: this, onIdle: widget.host._removeIfIdle);

  @override
  void initState() {
    super.initState();
    widget.host._coordinator = _coordinator;
  }

  @override
  void dispose() {
    if (identical(widget.host._coordinator, _coordinator)) widget.host._coordinator = null;
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassGhostHost(coordinator: _coordinator);
}

class _GhostParentData extends ContainerBoxParentData<RenderBox> {
  GlassGhost? ghost;
}

class _GhostSlot extends ParentDataWidget<_GhostParentData> {
  const _GhostSlot({super.key, required this.ghost, required super.child});

  final GlassGhost ghost;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _GhostParentData;
    if (identical(data.ghost, ghost)) return;
    data.ghost = ghost;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _GhostStack;
}

class _GhostStack extends MultiChildRenderObjectWidget {
  const _GhostStack({required this.coordinator, super.children});

  final GlassMotionCoordinator coordinator;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGhostStack(coordinator);

  @override
  void updateRenderObject(BuildContext context, _RenderGhostStack renderObject) {
    renderObject.coordinator = coordinator;
  }
}

class _RenderGhostStack extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _GhostParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GhostParentData> {
  _RenderGhostStack(this._coordinator);

  GlassMotionCoordinator _coordinator;
  set coordinator(GlassMotionCoordinator value) {
    if (identical(value, _coordinator)) return;
    if (attached) _coordinator.ghostMotion.removeListener(markNeedsPaint);
    _coordinator = value;
    if (attached) value.ghostMotion.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _coordinator.ghostMotion.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _coordinator.ghostMotion.removeListener(markNeedsPaint);
    super.detach();
  }

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
      child.layout(BoxConstraints.tight(data.ghost?.rect.size ?? Size.zero));
      child = data.nextSibling;
    }
  }

  Offset _placement(RenderBox child) {
    final ghost = (child.parentData! as _GhostParentData).ghost;
    return ghost == null ? Offset.zero : globalToLocal(ghost.placement.topLeft);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _coordinator.resolveGhosts();
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
    final Widget? image = snapshot == null
        ? null
        : OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: GlassContentBlur(blurred: ghost.blurred, child: RawImage(image: snapshot, scale: ghost.pixelRatio)),
          );
    final content = SizedBox.fromSize(size: ghost.rect.size, child: image);
    return switch (ghost.kind) {
      GlassGhostKind.content => FadeTransition(opacity: ghost.opacity, child: content),
      GlassGhostKind.pending || GlassGhostKind.sink => LiquidGlass.grouped(
        shape: ghost.shape,
        shadows: ghost.shadows,
        motion: ghost,
        child: FadeTransition(opacity: ghost.opacity, child: content),
      ),
      GlassGhostKind.dematerialize => LiquidGlass.withOwnLayer(
        settings: ghost.settings,
        shape: ghost.shape,
        shadows: ghost.shadows,
        visibility: ghost.member.visibility,
        child: content,
      ),
    };
  }
}

@internal
class GlassContentBlur extends SingleChildRenderObjectWidget {
  const GlassContentBlur({super.key, this.blurred = false, this.listenable, super.child});

  final bool blurred;
  final ValueListenable<bool>? listenable;

  @override
  RenderGlassContentBlur createRenderObject(BuildContext context) => RenderGlassContentBlur(blurred: blurred, listenable: listenable);

  @override
  void updateRenderObject(BuildContext context, RenderGlassContentBlur renderObject) {
    renderObject
      ..blurred = blurred
      ..listenable = listenable;
  }
}

@internal
class RenderGlassContentBlur extends RenderProxyBox {
  RenderGlassContentBlur({required bool blurred, ValueListenable<bool>? listenable}) : _blurred = blurred, _listenable = listenable;

  static final ui.ImageFilter filter = ui.ImageFilter.blur(sigmaX: ios27MorphContentBlur, sigmaY: ios27MorphContentBlur, tileMode: TileMode.decal);

  final LayerHandle<ImageFilterLayer> _filter = LayerHandle();

  bool _blurred;
  set blurred(bool value) {
    if (value == _blurred) return;
    _blurred = value;
    markNeedsPaint();
  }

  ValueListenable<bool>? _listenable;
  set listenable(ValueListenable<bool>? value) {
    if (identical(value, _listenable)) return;
    if (attached) _listenable?.removeListener(_changed);
    _listenable = value;
    if (attached) value?.addListener(_changed);
    markNeedsPaint();
  }

  bool get isBlurred => _listenable?.value ?? _blurred;

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable?.addListener(_changed);
  }

  @override
  void detach() {
    _listenable?.removeListener(_changed);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!isBlurred) {
      _filter.layer = null;
      super.paint(context, offset);
      return;
    }
    final layer = _filter.layer ??= ImageFilterLayer();
    layer.imageFilter = filter;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _filter.layer = null;
    super.dispose();
  }
}

@internal
class GlassMorphContent extends StatelessWidget {
  const GlassMorphContent({super.key, required this.member, required this.child});

  final GlassMember member;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: member.contentOpacity,
      child: GlassContentBlur(listenable: member.contentBlurred, child: child),
    );
  }
}
