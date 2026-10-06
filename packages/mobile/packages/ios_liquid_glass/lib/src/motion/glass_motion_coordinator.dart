import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_frame.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:meta/meta.dart';

@internal
enum GlassPresence { appearing, present, disappearing }

@internal
class GlassMember extends ChangeNotifier implements GlassShapeMotion {
  GlassMember(this.coordinator);

  final GlassMotionCoordinator coordinator;
  final GlassMotionValue visibility = GlassMotionValue();
  final GlassSpring _presence = GlassSpring(1);
  final List<GlassSpring> _offset = [for (var i = 0; i < 4; i++) GlassSpring(0)];
  GlassPresence presence = GlassPresence.present;
  GlassMaterializeMapping _mapping = GlassMaterializeMapping.defaultSpring;
  bool reduceMotion = false;
  bool _reduceMotionAtStart = false;
  bool dark = true;
  bool _darkAtStart = true;
  GlassAnimation? scopeAnimation;
  bool animatesTransitions = true;
  LiquidShape? shape;
  LiquidGlassSettings? sharedSettings;
  GlassMaterialSource? material;
  List<ScrollableState> scrollables = const [];
  VoidCallback? onSettled;
  RenderBox? _box;
  Size? _size;
  Offset? _anchor;
  Offset? _live;
  RenderObject? _liveSpace;
  Offset? _spaceOrigin;
  Offset _innerAtLive = Offset.zero;
  Offset _outerAtOrigin = Offset.zero;
  int _originFrame = -1;
  int _animateUntil = -1;
  int _changeFrame = -2;
  Duration? _changeTime;
  bool _following = false;
  List<GlassSpring>? _held;
  int _heldFrame = -2;
  GlassAnimation? _requested;
  GlassMotionCoordinator? _ghostOwner;

  LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;

  bool get isMoving => _presence.isMoving || _offset.any((spring) => spring.isMoving);

  bool get ownsLayer => presence != GlassPresence.present;

  double get progress => GlassMaterialize.progress(
    _presence.value,
    appearing: presence != GlassPresence.disappearing,
    mapping: _mapping,
    reduceMotion: _reduceMotionAtStart,
    dark: _darkAtStart,
  );

  Size? get drawnSize {
    final size = _size;
    return size == null ? null : Size(size.width + _offset[2].value, size.height + _offset[3].value);
  }

  Rect? get drawn {
    _sync();
    return _lastDrawn;
  }

  Rect? get _lastDrawn {
    final live = _live, size = drawnSize;
    if (live == null || size == null) return null;
    return Rect.fromLTWH(live.dx + _offset[0].value, live.dy + _offset[1].value, size.width, size.height);
  }

  void attachBox(RenderBox box) => _box = box;

  void detachBox(RenderBox box) {
    if (identical(_box, box)) _box = null;
  }

  void rebuilt() {
    _animateUntil = GlassFrame.current + 1;
    _requested = resolveGlassAnimation(scopeAnimation);
  }

  bool get isFollowing => _following && _changeFrame >= GlassFrame.current - 1;

  GlassAnimation? _animationNow() {
    final frame = GlassFrame.current;
    var chosen = pendingGlassAnimation;
    if (chosen == null && frame <= _animateUntil) chosen = _requested;
    if (chosen == null && frame <= coordinator._structureUntil) chosen = coordinator._structureAnimation;
    return chosen == null || chosen.isNone ? null : chosen;
  }

  static const Duration followGap = Duration(milliseconds: 50);

  GlassAnimation? _changed() {
    final frame = GlassFrame.current;
    if (_changeFrame != frame) {
      final now = coordinator._now, last = _changeTime;
      _following = _changeFrame == frame - 1 && now != null && last != null && now - last <= followGap;
      _changeFrame = frame;
      _changeTime = now;
    }
    final pending = pendingGlassAnimation;
    if (pending != null) return pending.isNone ? null : pending;
    if (_following) {
      _letGo(frame);
      return null;
    }
    final animation = _animationNow();
    if (animation != null && _heldFrame != frame) {
      _held = [for (final spring in _offset) spring.copy()];
      _heldFrame = frame;
    }
    return animation;
  }

  void _letGo(int frame) {
    final held = _held;
    _held = null;
    if (held == null || _heldFrame != frame - 1) return;
    final now = coordinator._now;
    for (var i = 0; i < _offset.length; i++) {
      _offset[i].restoreFrom(held[i], now);
    }
    coordinator._start();
  }

  void sized(Size size) {
    final previous = _size;
    _size = size;
    if (previous != null && previous != size) {
      final animation = _changed();
      if (animation != null) {
        final now = coordinator._now;
        _offset[2].offsetBy(previous.width - size.width, animation, now);
        _offset[3].offsetBy(previous.height - size.height, animation, now);
        coordinator._start();
      }
    }
    _resizeMaterial();
  }

  void sync() => _sync();

  void _sync() {
    final box = _box;
    final space = coordinator.space;
    if (box == null || space == null || !box.attached || !space.attached || !box.hasSize) return;
    final live = MatrixUtils.transformPoint(box.getTransformTo(space), Offset.zero);
    final inner = _scrollShift(space);
    final anchor = live - inner;
    _live = live;
    _liveSpace = space;
    _innerAtLive = inner;
    final frame = GlassFrame.current;
    if (_originFrame != frame) {
      _originFrame = frame;
      _readSpace(space, inner);
    }
    final previous = _anchor;
    _anchor = anchor;
    if (previous == null || previous == anchor) return;
    final animation = _changed();
    if (animation == null) return;
    final now = coordinator._now;
    _offset[0].offsetBy(previous.dx - anchor.dx, animation, now);
    _offset[1].offsetBy(previous.dy - anchor.dy, animation, now);
    coordinator._start();
  }

  void _readSpace(RenderObject space, Offset inner) {
    _spaceOrigin = MatrixUtils.transformPoint(space.getTransformTo(null), Offset.zero);
    _outerAtOrigin = _scrollShift(null) - inner;
  }

  void spaceComposited() {
    final space = _liveSpace;
    if (space != null && space.attached && identical(space, coordinator.space)) _readSpace(space, _scrollShift(space));
  }

  Offset _scrollShift(RenderObject? space) {
    var shift = Offset.zero;
    for (final scrollable in scrollables) {
      if (!scrollable.mounted) break;
      if (space != null) {
        final render = scrollable.context.findRenderObject();
        if (render == null || !_inside(render, space)) break;
      }
      final position = scrollable.position;
      if (!position.hasPixels) continue;
      final pixels = position.pixels;
      shift += switch (scrollable.axisDirection) {
        AxisDirection.down => Offset(0, -pixels),
        AxisDirection.up => Offset(0, pixels),
        AxisDirection.right => Offset(-pixels, 0),
        AxisDirection.left => Offset(pixels, 0),
      };
    }
    return shift;
  }

  static bool _inside(RenderObject render, RenderObject space) {
    for (var node = render.parent; node != null; node = node.parent) {
      if (identical(node, space)) return true;
    }
    return false;
  }

  @override
  Rect resolve(RenderBox shape) {
    final local = Offset.zero & shape.size;
    final current = drawn;
    final space = coordinator.space;
    if (current == null || space == null || !shape.attached || !space.attached) return local;
    return current.shift(-MatrixUtils.transformPoint(shape.getTransformTo(space), Offset.zero));
  }

  void _adopt(GlassMember other) {
    presence = other.presence;
    _mapping = other._mapping;
    _reduceMotionAtStart = other._reduceMotionAtStart;
    _darkAtStart = other._darkAtStart;
    _presence.jumpTo(other._presence.value, velocity: other._presence.velocity);
    if (other._presence.isMoving) {
      _presence.restart(other._presence.value, other._presence.velocity, other._presence.target, resolveGlassAnimation(scopeAnimation), coordinator._now);
      coordinator._start();
    }
    _publish();
  }

  void _appear(GlassAnimation animation, Duration? now) {
    final mapping = GlassMaterializeMapping.of(animation);
    if (presence == GlassPresence.disappearing) {
      final (value, velocity) = GlassMaterialize.reverse(_presence.value, _presence.velocity, toAppearing: true, from: _mapping, to: mapping);
      _presence.restart(value, velocity, 1, animation, now);
    } else {
      _presence.restart(0, 0, 1, animation, now);
    }
    _mapping = mapping;
    _reduceMotionAtStart = reduceMotion;
    _darkAtStart = dark;
    presence = GlassPresence.appearing;
    _publish();
  }

  void _disappear(GlassAnimation animation, Duration? now) {
    final mapping = GlassMaterializeMapping.of(animation);
    if (presence == GlassPresence.appearing) {
      final (value, velocity) = GlassMaterialize.reverse(
        _presence.value,
        _presence.velocity,
        toAppearing: false,
        from: _mapping,
        to: mapping,
        reduceMotion: _reduceMotionAtStart,
        dark: _darkAtStart,
      );
      _presence.restart(value, velocity, 0, animation, now);
    } else {
      _presence.restart(1, 0, 0, animation, now);
    }
    _mapping = mapping;
    presence = GlassPresence.disappearing;
    _publish();
  }

  bool get _due => isMoving || presence == GlassPresence.appearing;

  bool _sample(Duration now) {
    var moving = _presence.sample(now);
    for (final spring in _offset) {
      moving = spring.sample(now) || moving;
    }
    _publish();
    if (!_presence.isMoving && presence == GlassPresence.appearing) {
      presence = GlassPresence.present;
      onSettled?.call();
    }
    return moving;
  }

  void _publish() {
    visibility.value = GlassMaterialize.visibility(progress);
    _resizeMaterial();
    notifyListeners();
  }

  void _resizeMaterial() {
    final size = drawnSize;
    if (size != null) material?.resize(size.shortestSide, exact: !_offset.any((spring) => spring.isMoving));
  }

  @override
  void dispose() {
    visibility.dispose();
    super.dispose();
  }
}

@internal
class GlassGhost {
  GlassGhost({
    required this.member,
    required this.rect,
    required this.snapshot,
    required this.pixelRatio,
    required this.settings,
    required this.shape,
    required this.shadows,
  });

  final GlassMember member;
  final Rect rect;
  final ui.Image? snapshot;
  final double pixelRatio;
  final LiquidGlassSettings settings;
  final LiquidShape shape;
  final List<BoxShadow> shadows;

  void dispose() {
    snapshot?.dispose();
    member.dispose();
  }
}

class _Leaving {
  _Leaving({
    required this.animation,
    required this.rect,
    required this.settings,
    required this.shape,
    required this.shadows,
    required this.content,
    required this.contentSize,
    required this.pixelRatio,
  });

  final GlassAnimation animation;
  final Rect rect;
  final LiquidGlassSettings settings;
  final LiquidShape shape;
  final List<BoxShadow> shadows;
  final LayerHandle<OffsetLayer>? content;
  final Size? contentSize;
  final double pixelRatio;

  ui.Image? snapshot() {
    final layer = content?.layer;
    final size = contentSize;
    if (layer == null || size == null || size.isEmpty) return null;
    return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }

  void release() => content?.layer = null;
}

@internal
class GlassMotionCoordinator {
  GlassMotionCoordinator({required TickerProvider vsync, this.onIdle}) {
    _ticker = vsync.createTicker(_tick);
  }

  final VoidCallback? onIdle;
  late final Ticker _ticker;
  final Set<GlassMember> _members = {};
  final List<GlassGhost> ghosts = [];
  final Map<GlassMember, _Leaving> _leaving = {};
  RenderObject? marker;
  Element? _ghostHost;
  bool _disposed = false;
  bool _departing = false;
  GlassMotionCoordinator? _successor;
  int _structureUntil = -1;
  GlassAnimation? _structureAnimation;

  Iterable<GlassMember> get members => _members;

  GlassMotionCoordinator? get ghostOwner => _departing ? _successor : this;

  void depart(GlassMotionCoordinator? successor) {
    _departing = true;
    _successor = successor;
  }

  void stay() {
    _departing = false;
    _successor = null;
  }

  bool get hasGhosts => ghosts.isNotEmpty || _leaving.isNotEmpty;

  RenderObject? get space => marker?.parent ?? marker;

  Duration? get _now {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == SchedulerPhase.idle ? null : binding.currentFrameTimeStamp;
  }

  GlassMember join({GlassAnimation? scope, bool animate = true, bool inserted = false, GlassMember? from, bool reduceMotion = false, bool dark = true}) {
    final member = GlassMember(this)
      ..scopeAnimation = scope
      ..animatesTransitions = animate
      ..reduceMotion = reduceMotion
      ..dark = dark;
    _members.add(member);
    if (from != null) {
      member._adopt(from);
      return member;
    }
    final animation = resolveGlassAnimation(scope);
    if (inserted && animate && !animation.isNone) {
      member._appear(animation, _now);
      _structureChanged(animation);
      _start();
    }
    return member;
  }

  bool leave(
    GlassMember member, {
    required bool animate,
    GlassMotionCoordinator? owner,
    LayerHandle<OffsetLayer>? content,
    Size? contentSize,
    double pixelRatio = 1,
  }) {
    if (!_members.contains(member)) {
      content?.layer = null;
      return false;
    }
    final rect = _globalRect(member);
    _members.remove(member);
    final ghostOwner = owner ?? this;
    final animation = resolveGlassAnimation(member.scopeAnimation);
    final settings = member.settings, shape = member.shape;
    if (_disposed ||
        ghostOwner._disposed ||
        _ticker.muted ||
        ghostOwner._ticker.muted ||
        !animate ||
        !member.animatesTransitions ||
        animation.isNone ||
        rect == null ||
        settings == null ||
        shape == null) {
      content?.layer = null;
      return false;
    }
    final leaving = _Leaving(
      animation: animation,
      rect: rect,
      settings: settings,
      shape: shape,
      shadows: member.material?.shadows ?? const [],
      content: content,
      contentSize: contentSize,
      pixelRatio: pixelRatio,
    );
    _structureChanged(animation);
    member._ghostOwner = ghostOwner;
    ghostOwner._adopt(member, leaving);
    return true;
  }

  void reattach(GlassMember member) {
    if (member._ghostOwner == null) _members.add(member);
  }

  void _adopt(GlassMember member, _Leaving leaving) {
    _leaving[member] = leaving;
    _ghostHost?.markNeedsBuild();
    _start();
  }

  Rect? _globalRect(GlassMember member) {
    final drawn = member._lastDrawn;
    final origin = member._spaceOrigin;
    if (drawn == null || origin == null) return null;
    return drawn.shift(origin + member._scrollShift(null) - member._innerAtLive - member._outerAtOrigin);
  }

  void drop(GlassMember member) {
    final leaving = member._ghostOwner?._leaving.remove(member);
    leaving?.release();
    if (_members.remove(member) || leaving != null) member.dispose();
  }

  void rejoin(GlassMember member) {
    final leaving = member._ghostOwner?._leaving.remove(member);
    if (leaving == null) return;
    leaving.release();
    member._ghostOwner = null;
    _members.add(member);
  }

  List<GlassGhost> takeGhosts() {
    if (_ticker.muted) {
      _dropLeaving();
      dropGhosts();
    }
    for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
      final snapshot = leaving.snapshot();
      leaving.release();
      member
        ..material = null
        .._disappear(leaving.animation, _now);
      ghosts.add(GlassGhost(
        member: member,
        rect: leaving.rect,
        snapshot: snapshot,
        pixelRatio: leaving.pixelRatio,
        settings: leaving.settings,
        shape: leaving.shape,
        shadows: leaving.shadows,
      ));
    }
    _leaving.clear();
    return ghosts;
  }

  set ghostHost(Element? element) => _ghostHost = element;

  void dropGhosts() {
    for (final ghost in ghosts) {
      ghost.dispose();
    }
    ghosts.clear();
  }

  void _dropLeaving() {
    for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
      leaving.release();
      member.dispose();
    }
    _leaving.clear();
  }

  void _structureChanged(GlassAnimation animation) {
    _structureUntil = GlassFrame.current + 1;
    _structureAnimation = animation;
  }

  void _start() {
    if (!_disposed && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    var moving = false;
    for (final member in _members.toList()) {
      if (member._due) moving = member._sample(now) || moving;
    }
    var finished = false;
    for (final ghost in ghosts.toList()) {
      if (ghost.member._sample(now)) {
        moving = true;
      } else {
        ghosts.remove(ghost);
        ghost.dispose();
        finished = true;
      }
    }
    if (finished) _ghostHost?.markNeedsBuild();
    if (!moving && _leaving.isEmpty) {
      _ticker.stop();
      if (ghosts.isEmpty) onIdle?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _ticker.dispose();
    dropGhosts();
    _dropLeaving();
    for (final member in _members) {
      member.dispose();
    }
    _members.clear();
  }
}
