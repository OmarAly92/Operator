import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_namespace.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_frame.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/glass_morph_geometry.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:meta/meta.dart';

@internal
enum GlassPresence { appearing, present, disappearing }

@internal
enum GlassGhostKind { dematerialize, pending, sink, content }

class _Arrival {
  _Arrival(this.animation, {required this.reduceMotion});

  final GlassAnimation animation;
  final bool reduceMotion;
  bool fades = false;
  Rect? partner;
}

@internal
class GlassMember extends ChangeNotifier implements GlassShapeMotion {
  GlassMember(this.coordinator);

  final GlassMotionCoordinator coordinator;
  final GlassMotionValue visibility = GlassMotionValue();
  final GlassSpring _presence = GlassSpring(1);
  final List<GlassSpring> _offset = [for (var i = 0; i < 4; i++) GlassSpring(0)];
  final GlassSpring _morph = GlassSpring(1);
  final GlassMotionValue contentOpacity = GlassMotionValue();
  final ValueNotifier<bool> contentBlurred = ValueNotifier(false);
  GlassEffectID? id;
  bool morphs = false;
  _Arrival? _arrival;
  bool _contentFades = false;
  bool _sinking = false;
  GlassPresence presence = GlassPresence.present;
  GlassMaterializeMapping _mapping = GlassMaterializeMapping.defaultSpring;
  bool reduceMotion = false;
  bool _reduceMotionAtStart = false;
  bool dark = true;
  bool _darkAtStart = true;
  bool onScreen = true;
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
  (GlassEffectUnion, LiquidShape, Glass?)? _union;

  LiquidGlassSettings? get settings => sharedSettings ?? material?.settings;

  bool get isMoving => _presence.isMoving || _morph.isMoving || _offset.any((spring) => spring.isMoving);

  bool get ownsLayer => presence != GlassPresence.present;

  double get progress => _sinking ? 1 : GlassMaterialize.progress(
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

  void unite(GlassEffectUnion? union, {Glass? glass, required bool grouped}) {
    final shape = this.shape;
    final next = union == null || shape == null || !grouped ? null : (union, shape, glass);
    final previous = _union;
    if (next == previous) return;
    _union = next;
    coordinator._unionChanged(previous);
    coordinator._unionChanged(next);
  }

  bool get _drawsInUnion {
    final box = _box;
    return _union != null && box != null && box.attached && box.hasSize;
  }

  GlassUnionOutline? get unionOutline {
    final key = _union;
    if (key == null || !_drawsInUnion) return null;
    Rect? bounds;
    GlassMember? leader;
    var count = 0;
    var counted = false;
    for (final member in coordinator._members) {
      if (member._union != key || !member._drawsInUnion) continue;
      final rect = member.drawn;
      if (rect == null) continue;
      leader ??= member;
      count++;
      counted = counted || identical(member, this);
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    if (bounds == null || count < 2 || !counted) return null;
    return GlassUnionOutline(rect: bounds, shape: unionShape(key.$2), leads: identical(leader, this));
  }

  static LiquidShape unionShape(LiquidShape shape) => shape is LiquidOval ? const LiquidRoundedRectangle(borderRadius: 999) : shape;

  @override
  GlassUnionOutline? union(RenderBox shape) {
    final outline = unionOutline;
    final space = coordinator.space;
    if (outline == null || space == null || !shape.attached || !space.attached) return null;
    return outline.shift(-MatrixUtils.transformPoint(shape.getTransformTo(space), Offset.zero));
  }

  @override
  bool get isTransient => false;

  void _unionMoved() => notifyListeners();

  void attachBox(RenderBox box) => _box = box;

  void detachBox(RenderBox box) {
    if (identical(_box, box)) _box = null;
  }

  bool get _offScreen => !onScreen || coordinator._ticker.muted;

  void rebuilt() {
    _animateUntil = _offScreen ? -1 : GlassFrame.current + 1;
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
    if (_offScreen) return null;
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

  void settle() {
    _presence.jumpTo(_presence.target);
    for (final spring in _offset) {
      spring.jumpTo(spring.target);
    }
    _held = null;
    _publish();
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

  @override
  bool syncMoved() {
    _sync();
    return false;
  }

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
    final arrival = _arrival, size = _size;
    if (arrival != null && size != null) {
      _arrival = null;
      _anchor = anchor;
      _arrive(arrival, live & size);
      return;
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

  void _arrive(_Arrival arrival, Rect layout) {
    final partner = arrival.partner;
    Rect start;
    if (partner != null) {
      start = partner;
    } else {
      final source = coordinator._nearestSource(this, layout);
      final drawn = source?.drawn;
      if (source == null || drawn == null) {
        start = Rect.fromCenter(center: layout.center, width: 0, height: 0);
      } else {
        start = arrival.reduceMotion ? Rect.fromCenter(center: drawn.center, width: layout.width, height: layout.height) : drawn;
        coordinator._link(this, source);
      }
    }
    final now = coordinator._now, animation = arrival.animation;
    _offset[0].restart(start.left - layout.left, 0, 0, animation, now);
    _offset[1].restart(start.top - layout.top, 0, 0, animation, now);
    _offset[2].restart(start.width - layout.width, 0, 0, animation, now);
    _offset[3].restart(start.height - layout.height, 0, 0, animation, now);
    _morph.restart(0, 0, 1, animation, now);
    _contentFades = arrival.fades || arrival.reduceMotion;
    coordinator._start();
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

  void _begin(GlassAnimation animation, {required bool reduceMotion}) {
    _arrival = _Arrival(animation, reduceMotion: reduceMotion);
    contentOpacity.value = reduceMotion ? 0 : 1;
  }

  bool _sample(Duration now) {
    var moving = _presence.sample(now);
    moving = _morph.sample(now) || moving;
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
    if (_contentFades) contentOpacity.value = _morph.value.clamp(0.0, 1.0);
    _resizeMaterial();
    notifyListeners();
    if (coordinator._members.contains(this)) coordinator._unionChanged(_union, except: this);
  }

  void _resizeMaterial() {
    final size = drawnSize;
    if (size != null) material?.resize(size.shortestSide, exact: !_offset.any((spring) => spring.isMoving));
  }

  @override
  void dispose() {
    visibility.dispose();
    contentOpacity.dispose();
    contentBlurred.dispose();
    super.dispose();
  }
}

@internal
class GlassGhost extends ChangeNotifier implements GlassShapeMotion {
  GlassGhost({
    required this.member,
    required this.rect,
    required this.snapshot,
    required this.pixelRatio,
    required this.settings,
    required this.shape,
    required this.shadows,
    this.kind = GlassGhostKind.dematerialize,
    this.partner,
    this.blurred = false,
    this.reduceMotion = false,
  }) : current = rect;

  final GlassMember member;
  final Rect rect;
  final ui.Image? snapshot;
  final double pixelRatio;
  final LiquidGlassSettings settings;
  final LiquidShape shape;
  final List<BoxShadow> shadows;
  final GlassMember? partner;
  final bool blurred;
  final bool reduceMotion;
  final GlassMotionValue opacity = GlassMotionValue();
  GlassGhostKind kind;
  GlassMember? target;
  Offset? _goal;
  Rect current;

  bool get draws => kind != GlassGhostKind.content;

  Rect get placement => kind == GlassGhostKind.content ? Rect.fromCenter(center: current.center, width: rect.width, height: rect.height) : rect;

  void _sink(GlassMember into, Rect goal) {
    kind = GlassGhostKind.sink;
    target = into;
    _goal = goal.center;
    member._sinking = true;
  }

  void _aim() {
    final box = target?._box;
    if (box == null || !box.attached || !box.hasSize) return;
    _goal = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size).center;
  }

  bool _step(Duration now) {
    final partner = this.partner;
    if (kind == GlassGhostKind.content) {
      if (partner == null) return false;
      final drawn = partner.coordinator._globalRect(partner);
      if (drawn != null) current = drawn;
      final live = partner.coordinator._members.contains(partner);
      final moving = live ? partner._morph.isMoving : partner._morph.sample(now);
      opacity.value = 1 - (live ? partner.contentOpacity.value : partner._morph.value.clamp(0.0, 1.0));
      notifyListeners();
      return moving;
    }
    final moving = member._sample(now);
    final goal = _goal;
    if (kind == GlassGhostKind.sink && goal != null) {
      final remaining = member._presence.value.clamp(0.0, 1.0);
      final travel = reduceMotion ? 1 - remaining : 1 - GlassMaterialize.progress(member._presence.value, appearing: false, mapping: member._mapping);
      final centre = Offset.lerp(rect.center, goal, travel.clamp(0.0, 1.0))!;
      final scale = reduceMotion ? 1.0 : remaining;
      current = Rect.fromCenter(center: centre, width: rect.width * scale, height: rect.height * scale);
      opacity.value = remaining;
      notifyListeners();
    }
    return moving;
  }

  @override
  Rect resolve(RenderBox shape) {
    if (!shape.attached) return Offset.zero & shape.size;
    return current.shift(-MatrixUtils.transformPoint(shape.getTransformTo(null), Offset.zero));
  }

  @override
  GlassUnionOutline? union(RenderBox shape) => null;

  @override
  bool get isTransient => true;

  @override
  bool syncMoved() => false;

  @override
  void dispose() {
    snapshot?.dispose();
    opacity.dispose();
    member.dispose();
    super.dispose();
  }
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
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
    this.morphs = false,
    this.reduceMotion = false,
    this.local,
  });

  final GlassAnimation animation;
  final bool morphs;
  final bool reduceMotion;
  final Rect? local;
  GlassMember? partner;
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
  final GlassMotionValue spacing = GlassMotionValue(0);
  GlassSpring? _spacing;
  int _spacingFrame = -2;
  Duration? _spacingTime;
  final Set<GlassMember> _arrivals = {};
  int _arrivalFrame = -1;
  final Set<GlassMember> _blurred = {};
  final Map<GlassMember, Set<Object>> _links = {};
  bool _ghostsChanged = false;
  final _Notifier _ghostMotion = _Notifier();

  Listenable get ghostMotion => _ghostMotion;

  Iterable<GlassMember> get members => _members;

  void _unionChanged(Object? union, {GlassMember? except}) {
    if (union == null) return;
    for (final member in _members) {
      if (member._union == union && !identical(member, except)) member._unionMoved();
    }
  }

  void spacingTo(double target, {GlassAnimation? scope}) {
    final spring = _spacing;
    if (spring == null) {
      _spacing = GlassSpring(target);
      spacing.value = target;
      return;
    }
    if (spring.target == target) return;
    final frame = GlassFrame.current, now = _now, last = _spacingTime;
    final following = _spacingFrame == frame - 1 && now != null && last != null && now - last <= GlassMember.followGap;
    _spacingFrame = frame;
    _spacingTime = now;
    final animation = _disposed || _ticker.muted || (following && pendingGlassAnimation == null)
        ? GlassAnimation.none
        : resolveGlassAnimation(scope);
    spring.animateTo(target, animation, now);
    spacing.value = spring.value;
    if (spring.isMoving) _start();
  }

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

  Set<GlassMember> get _arrivedNow {
    final frame = GlassFrame.current;
    if (_arrivalFrame != frame) {
      _arrivalFrame = frame;
      _arrivals.clear();
    }
    return _arrivals;
  }

  GlassMember join({
    GlassAnimation? scope,
    bool animate = true,
    bool inserted = false,
    GlassMember? from,
    bool reduceMotion = false,
    bool dark = true,
    GlassEffectID? id,
    bool morphs = false,
  }) {
    final arrivals = _arrivedNow;
    final member = GlassMember(this)
      ..scopeAnimation = scope
      ..animatesTransitions = animate
      ..reduceMotion = reduceMotion
      ..dark = dark
      ..id = id
      ..morphs = morphs;
    final others = _members.any((other) => !arrivals.contains(other)) || _leaving.keys.any((other) => other.morphs);
    _members.add(member);
    if (from != null) {
      member._adopt(from);
      return member;
    }
    final animation = resolveGlassAnimation(scope);
    if (inserted && animate && !animation.isNone) {
      if (morphs && others) {
        member._begin(animation, reduceMotion: reduceMotion);
        arrivals.add(member);
        if (id != null) {
          for (final MapEntry(key: leaver, value: leaving) in _leaving.entries) {
            if (leaving.partner == null && leaving.morphs && leaver.id == id) {
              _pair(member, leaver, leaving);
              break;
            }
          }
        }
      } else {
        member._appear(animation, _now);
      }
      _structureChanged(animation);
      _start();
    }
    return member;
  }

  void _pair(GlassMember arrival, GlassMember leaver, _Leaving leaving) {
    leaving.partner = arrival;
    arrival._arrival
      ?..partner = leaving.local
      ..fades = true;
    arrival.contentOpacity.value = 0;
  }

  GlassMember? _nearestSource(GlassMember arrival, Rect layout) {
    GlassMember? best;
    var bestGap = double.infinity, bestDistance = double.infinity;
    for (final member in _members) {
      if (identical(member, arrival) || _arrivals.contains(member) || member.presence == GlassPresence.disappearing) continue;
      final drawn = member.drawn, shape = member.shape;
      if (drawn == null) continue;
      final gap = shape == null || arrival.shape == null ? (drawn.center - layout.center).distance : GlassMorphGeometry.gap(layout, arrival.shape!, drawn, shape);
      final distance = (drawn.center - layout.center).distance;
      if (gap < bestGap - 1e-9 || (gap < bestGap + 1e-9 && distance < bestDistance)) {
        best = member;
        bestGap = gap;
        bestDistance = distance;
      }
    }
    return best;
  }

  void _link(GlassMember arrival, GlassMember source) {
    if (arrival.reduceMotion) return;
    _links.putIfAbsent(arrival, () => {}).add(source);
    _links.putIfAbsent(source, () => {}).add(arrival);
    _blur(arrival);
    _blur(source);
  }

  void _blur(GlassMember member) {
    if (member.reduceMotion) return;
    _blurred.add(member);
    member.contentBlurred.value = true;
  }

  Iterable<(Rect, LiquidShape)> _morphShapes(Object except) sync* {
    for (final member in _blurred) {
      if (identical(member, except)) continue;
      final rect = _globalRect(member), shape = member.shape;
      if (rect != null && shape != null) yield (rect, shape);
    }
    for (final ghost in ghosts) {
      if (!identical(ghost, except) && ghost.blurred && ghost.draws) yield (ghost.current, ghost.shape);
    }
  }

  void _sharpen() {
    if (_blurred.isEmpty) return;
    final reach = spacing.value / 2;
    for (final member in _blurred.toList()) {
      final rect = _globalRect(member), shape = member.shape;
      if (rect == null || shape == null) continue;
      final sinking = _links[member]?.any((link) => link is GlassGhost && ghosts.contains(link)) ?? false;
      final joined = _morphShapes(member).any((other) => GlassMorphGeometry.gap(rect, shape, other.$1, other.$2) < reach);
      final settled = !_blurred.any((other) => other.isMoving) && !ghosts.any((ghost) => ghost.blurred);
      if ((sinking || joined) && !settled) continue;
      _blurred.remove(member);
      _links.remove(member);
      member.contentBlurred.value = false;
    }
  }

  void resolveGhosts() {
    for (final ghost in ghosts) {
      if (ghost.kind == GlassGhostKind.sink) ghost._aim();
      if (ghost.kind != GlassGhostKind.pending) continue;
      GlassMember? best;
      Rect? bestRect;
      var bestGap = double.infinity;
      for (final member in _members) {
        final box = member._box, shape = member.shape;
        if (box == null || shape == null || !box.attached || !box.hasSize || member.presence == GlassPresence.disappearing) continue;
        final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
        final gap = GlassMorphGeometry.gap(ghost.rect, ghost.shape, rect, shape);
        if (gap < bestGap) {
          best = member;
          bestRect = rect;
          bestGap = gap;
        }
      }
      if (best != null && bestRect != null && bestGap < spacing.value) {
        ghost._sink(best, bestRect);
        if (ghost.blurred) {
          _links.putIfAbsent(best, () => {}).add(ghost);
          _blur(best);
        }
      } else {
        ghost.kind = GlassGhostKind.dematerialize;
        _ghostsChanged = true;
      }
      _start();
    }
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
    final local = member._lastDrawn;
    _members.remove(member);
    _blurred.remove(member);
    _links.remove(member);
    _unionChanged(member._union);
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
      morphs: member.morphs,
      reduceMotion: member.reduceMotion,
      local: local,
    );
    _structureChanged(animation);
    member._ghostOwner = ghostOwner;
    ghostOwner._adopt(member, leaving);
    final id = member.id;
    if (member.morphs && id != null && identical(ghostOwner, this)) {
      for (final arrival in _arrivedNow) {
        if (arrival.morphs && arrival.id == id && arrival._arrival?.partner == null && !_leaving.values.any((other) => identical(other.partner, arrival))) {
          _pair(arrival, member, leaving);
          break;
        }
      }
    }
    return true;
  }

  void reattach(GlassMember member) {
    if (member._ghostOwner != null) return;
    _members.add(member);
    _unionChanged(member._union);
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
    if (_members.remove(member) || leaving != null) {
      _unionChanged(member._union);
      member.dispose();
    }
  }

  void rejoin(GlassMember member) {
    final leaving = member._ghostOwner?._leaving.remove(member);
    if (leaving == null) return;
    leaving.release();
    member._ghostOwner = null;
    _members.add(member);
    _unionChanged(member._union);
  }

  List<GlassGhost> takeGhosts() {
    if (_ticker.muted) {
      _dropLeaving();
      dropGhosts();
    }
    final morphing = _leaving.entries.any((entry) => entry.value.morphs && entry.value.partner == null);
    final others = _members.any((member) => member.presence != GlassPresence.disappearing);
    for (final MapEntry(key: member, value: leaving) in _leaving.entries) {
      final snapshot = leaving.snapshot();
      leaving.release();
      member.material = null;
      final partner = leaving.partner;
      final kind = partner != null
          ? GlassGhostKind.content
          : leaving.morphs && others && marker != null
          ? GlassGhostKind.pending
          : GlassGhostKind.dematerialize;
      if (partner == null) member._disappear(leaving.animation, _now);
      ghosts.add(GlassGhost(
        member: member,
        rect: leaving.rect,
        snapshot: snapshot,
        pixelRatio: leaving.pixelRatio,
        settings: leaving.settings,
        shape: leaving.shape,
        shadows: leaving.shadows,
        kind: kind,
        partner: partner,
        blurred: morphing && leaving.morphs && partner == null && !leaving.reduceMotion,
        reduceMotion: leaving.reduceMotion,
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
    final spacingSpring = _spacing;
    if (spacingSpring != null && spacingSpring.isMoving) {
      moving = spacingSpring.sample(now);
      spacing.value = spacingSpring.value;
    }
    for (final member in _members.toList()) {
      if (member._due) moving = member._sample(now) || moving;
    }
    var finished = _ghostsChanged;
    _ghostsChanged = false;
    for (final ghost in ghosts.toList()) {
      if (ghost._step(now) || ghost.kind == GlassGhostKind.pending) {
        moving = true;
      } else {
        ghosts.remove(ghost);
        ghost.dispose();
        finished = true;
      }
    }
    _sharpen();
    if (_blurred.isNotEmpty) moving = true;
    if (ghosts.isNotEmpty) _ghostMotion.notify();
    if (finished) _ghostHost?.markNeedsBuild();
    if (!moving && _leaving.isEmpty) {
      _ticker.stop();
      if (ghosts.isEmpty) onIdle?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _ticker.dispose();
    spacing.dispose();
    _ghostMotion.dispose();
    _blurred.clear();
    _links.clear();
    dropGhosts();
    _dropLeaving();
    for (final member in _members) {
      member.dispose();
    }
    _members.clear();
  }
}
