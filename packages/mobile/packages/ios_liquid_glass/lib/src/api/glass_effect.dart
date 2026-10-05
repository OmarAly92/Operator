import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_transition.dart';
import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';

class GlassEffect extends StatefulWidget {
  const GlassEffect({
    super.key,
    this.glass = Glass.regular,
    this.shape = const GlassShape.capsule(),
    this.transition = GlassEffectTransition.materialize,
    this.sideHint,
    required this.child,
  });

  static const double fallbackSide = 88;

  final Glass glass;
  final GlassShape shape;
  final GlassEffectTransition transition;
  final double? sideHint;
  final Widget child;

  @override
  State<GlassEffect> createState() => _GlassEffectState();
}

class _GlassEffectState extends State<GlassEffect> with SingleTickerProviderStateMixin {
  final _childKey = GlobalKey();
  double? _shorterSide;
  GlassMotionCoordinator? _private;
  GlassMotionCoordinator? _coordinator;
  GlassMember? _member;
  bool _joined = false;
  bool _left = false;

  bool get _identity => widget.glass.kind == GlassKind.identity;

  void _measured(Size size) {
    final side = size.shortestSide;
    if (_shorterSide != null && (side - _shorterSide!).abs() < 0.5) return;
    setState(() => _shorterSide = side);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _join();
  }

  @override
  void didUpdateWidget(GlassEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glass.kind != widget.glass.kind || oldWidget.transition != widget.transition) _join();
  }

  static bool _laidOut(RenderObject? parent) => switch (parent) {
    RenderBox() => parent.hasSize,
    RenderSliver() => parent.geometry != null,
    _ => false,
  };

  void _join() {
    final container = GlassEffectContainer.scopeOf(context)?.coordinator;
    final coordinator = _identity ? null : container ?? (_private ??= GlassMotionCoordinator(vsync: this));
    final scope = GlassAnimationScope.maybeOf(context);
    final animate = widget.transition == GlassEffectTransition.materialize;
    final current = _member;
    if (coordinator == _coordinator && current != null) {
      current
        ..scopeAnimation = scope
        ..animatesTransitions = animate;
      return;
    }
    final inserted = container != null && !_joined && (pendingGlassAnimation != null || _laidOut(context.findAncestorRenderObjectOfType<RenderObject>()));
    _joined = true;
    _coordinator = coordinator;
    _member = coordinator?.join(
      scope: scope,
      animate: animate,
      inserted: inserted,
      from: current,
      reduceMotion: GlassAccessibility.of(context).reduceMotion,
    )?..onSettled = _settled;
    if (current != null) current.coordinator.drop(current);
  }

  void _settled() {
    if (mounted) setState(() {});
  }

  @override
  void deactivate() {
    final member = _member, coordinator = _coordinator;
    if (member != null && coordinator != null) {
      coordinator.leave(member, animate: false);
      _left = true;
    }
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    final member = _member;
    if (_left && member != null) member.coordinator.reattach(member);
    _left = false;
  }

  @override
  void dispose() {
    final member = _member;
    if (member != null) {
      if (!_left) {
        member.coordinator.drop(member);
      } else {
        member.dispose();
      }
    }
    _private?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _SizeReporter(key: _childKey, onSize: _measured, child: GlassEffectScope(glass: widget.glass, child: widget.child));
    final member = _member;
    if (_identity || member == null) return content;
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final material = resolveGlassMaterial(context, glass: widget.glass, shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide);
        final shape = widget.shape.liquidShape;
        final container = GlassEffectContainer.scopeOf(context);
        final grouped = container != null && container.glass.sameMaterial(widget.glass);
        member
          ..shape = shape
          ..sharedSettings = grouped ? container.settings : null
          ..reduceMotion = GlassAccessibility.of(context).reduceMotion;
        final Widget glass;
        if (grouped && !member.ownsLayer) {
          glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, motion: member, child: content);
        } else {
          glass = LiquidGlass.withOwnLayer(
            settings: grouped ? container.settings : material.toSettings(tint: widget.glass.tintColor),
            shape: shape,
            shadows: material.shadows,
            motion: member,
            visibility: member.visibility,
            child: content,
          );
        }
        final box = GlassMemberBox(member: member, child: glass);
        final private = _private;
        return container == null && private != null ? GlassCoordinatorSpace(coordinator: private, child: box) : box;
      },
    );
  }
}

class GlassEffectScope extends InheritedWidget {
  const GlassEffectScope({super.key, required this.glass, required super.child});

  final Glass glass;

  static Glass? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassEffectScope>()?.glass;

  @override
  bool updateShouldNotify(GlassEffectScope oldWidget) => oldWidget.glass != glass;
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({super.key, required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
