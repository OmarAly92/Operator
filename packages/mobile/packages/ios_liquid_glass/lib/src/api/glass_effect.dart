import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_transition.dart';
import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
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
  final _snapshotKey = GlobalKey();
  double _pixelRatio = 1;
  GlassMotionCoordinator? _private;
  GlassMotionCoordinator? _coordinator;
  GlassMember? _member;
  GlassMaterialSource? _material;
  GlassOverlayGhosts? _overlay;
  RenderObject? _parent;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _joined = false;
  bool _left = false;
  bool _ghosted = false;

  bool get _identity => widget.glass.kind == GlassKind.identity;

  bool get _onScreen => _tickerMode?.value.enabled ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    _watchTickerMode();
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
    _useOverlay(coordinator != null && container == null);
    final scope = GlassAnimationScope.maybeOf(context);
    final animate = widget.transition == GlassEffectTransition.materialize;
    final current = _member;
    if (coordinator == _coordinator && current != null) {
      current
        ..scopeAnimation = scope
        ..animatesTransitions = animate;
      return;
    }
    final hosted = container != null || _overlay != null;
    final inserted = !_joined && hosted && _onScreen && (pendingGlassAnimation != null || _laidOut(context.findAncestorRenderObjectOfType<RenderObject>()));
    _joined = true;
    _coordinator = coordinator;
    _member = coordinator?.join(
      scope: scope,
      animate: animate,
      inserted: inserted,
      from: current,
      reduceMotion: GlassAccessibility.of(context).reduceMotion,
      dark: GlassTheme.brightnessOf(context) == Brightness.dark,
    )
      ?..onSettled = _settled
      ..onScreen = _onScreen;
    if (current != null) current.coordinator.drop(current);
  }

  void _watchTickerMode() {
    final next = TickerMode.getValuesNotifier(context);
    if (identical(next, _tickerMode)) return;
    _tickerMode?.removeListener(_tickerModeChanged);
    _tickerMode = next..addListener(_tickerModeChanged);
    _member?.onScreen = _onScreen;
  }

  void _tickerModeChanged() {
    final member = _member;
    if (member == null) return;
    member.onScreen = _onScreen;
    if (!_onScreen) member.settle();
  }

  void _useOverlay(bool standalone) {
    final overlay = standalone ? GlassOverlayGhosts.of(context) : null;
    if (identical(overlay, _overlay)) return;
    _overlay?.release();
    _overlay = overlay?..retain();
  }

  void _settled() {
    if (mounted) setState(() {});
  }

  List<ScrollableState> _scrollables() {
    final found = <ScrollableState>[];
    for (var scrollable = context.findAncestorStateOfType<ScrollableState>();
        scrollable != null;
        scrollable = scrollable.context.findAncestorStateOfType<ScrollableState>()) {
      found.add(scrollable);
    }
    return found;
  }

  @override
  void deactivate() {
    final member = _member, coordinator = _coordinator;
    if (member != null && coordinator != null) {
      final standalone = coordinator == _private;
      final owner = standalone ? _overlay?.coordinator : coordinator.ghostOwner;
      final parent = _parent;
      final animate = owner != null && _onScreen && (pendingGlassAnimation != null || (parent != null && parent.attached));
      final boundary = _snapshotKey.currentContext?.findRenderObject();
      final keep = animate && member.animatesTransitions && boundary is RenderGlassSnapshotBoundary;
      _ghosted = coordinator.leave(
        member,
        animate: animate,
        owner: owner,
        content: keep ? boundary.retain() : null,
        contentSize: keep && boundary.hasSize ? boundary.size : null,
        pixelRatio: _pixelRatio,
      );
      _left = true;
    }
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _watchTickerMode();
    final member = _member;
    if (_left && member != null) {
      if (_ghosted) {
        member.coordinator.rejoin(member);
      } else {
        member.coordinator.reattach(member);
      }
    }
    _left = false;
    _ghosted = false;
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_tickerModeChanged);
    final member = _member;
    if (member != null) {
      if (!_left) {
        member.coordinator.drop(member);
      } else if (!_ghosted) {
        member.dispose();
      }
    }
    _private?.dispose();
    _overlay?.release();
    _overlay = null;
    _material?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _parent = context.findAncestorRenderObjectOfType<RenderObject>();
    final content = GlassSnapshotBoundary(key: _snapshotKey, child: GlassEffectScope(glass: widget.glass, child: widget.child));
    final member = _member;
    if (_identity || member == null) return content;
    member
      ..scrollables = _scrollables()
      ..rebuilt();
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final resolve = glassMaterialResolver(context, glass: widget.glass);
        final tint = widget.glass.tintColor;
        final material = _material ??= GlassMaterialSource(resolve: resolve, tint: tint, side: widget.sideHint ?? GlassEffect.fallbackSide);
        material.configure(resolve: resolve, tint: tint);
        final shape = widget.shape.liquidShape;
        final container = GlassEffectContainer.scopeOf(context);
        final grouped = container != null && container.glass.sameMaterial(widget.glass);
        member
          ..shape = shape
          ..material = material
          ..sharedSettings = grouped ? container.settings : null
          ..reduceMotion = GlassAccessibility.of(context).reduceMotion
          ..dark = GlassTheme.brightnessOf(context) == Brightness.dark;
        final Widget glass;
        if (grouped && !member.ownsLayer) {
          glass = LiquidGlass.grouped(shape: shape, shadows: material.shadows, shadowSource: material, motion: member, child: content);
        } else {
          glass = LiquidGlass.withOwnLayer(
            settings: grouped ? container.settings : material.settings,
            settingsSource: grouped ? null : material,
            shape: shape,
            shadows: material.shadows,
            shadowSource: material,
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
