import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

@immutable
class GlassAnimation {
  const GlassAnimation.spring({Duration duration = const Duration(milliseconds: 500), double bounce = 0})
    : _duration = duration,
      _bounce = bounce,
      _response = null,
      _dampingFraction = null,
      isNone = false;

  const GlassAnimation.dampedSpring({required double response, required double dampingFraction})
    : _response = response,
      _dampingFraction = dampingFraction,
      _duration = null,
      _bounce = 0,
      isNone = false;

  const GlassAnimation._none() : _duration = null, _bounce = 0, _response = null, _dampingFraction = null, isNone = true;

  static const GlassAnimation defaultSpring = GlassAnimation.spring(duration: Duration(milliseconds: 550));
  static const GlassAnimation smooth = GlassAnimation.spring();
  static const GlassAnimation snappy = GlassAnimation.spring(bounce: 0.15);
  static const GlassAnimation bouncy = GlassAnimation.spring(bounce: 0.3);
  static const GlassAnimation none = GlassAnimation._none();

  final Duration? _duration;
  final double _bounce;
  final double? _response;
  final double? _dampingFraction;
  final bool isNone;

  double get response => _response ?? _duration!.inMicroseconds / Duration.microsecondsPerSecond;

  double get dampingFraction => _dampingFraction ?? (_bounce >= 0 ? 1 - _bounce : 1 / (1 + _bounce));

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 4 * math.pi * math.pi / (response * response),
    ratio: dampingFraction,
  );

  Simulation simulate(double from, double to, double velocity) =>
      SpringMotion(description).createSimulation(start: from, end: to, velocity: velocity);

  @override
  bool operator ==(Object other) =>
      other is GlassAnimation &&
      other.isNone == isNone &&
      (isNone || (other.response == response && other.dampingFraction == dampingFraction));

  @override
  int get hashCode => isNone ? 0 : Object.hash(response, dampingFraction);

  @override
  String toString() => isNone ? 'GlassAnimation.none' : 'GlassAnimation(response: $response, dampingFraction: $dampingFraction)';
}

GlassAnimation? _pending;
int _generation = 0;

void withGlassAnimation(GlassAnimation animation, VoidCallback body) {
  final generation = ++_generation;
  _pending = animation;
  try {
    body();
  } finally {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (_generation == generation) _pending = null;
      })
      ..ensureVisualUpdate();
  }
}

@internal
GlassAnimation? get pendingGlassAnimation => _pending;

@visibleForTesting
void debugResetGlassAnimation() {
  _generation++;
  _pending = null;
}

@internal
GlassAnimation resolveGlassAnimation(GlassAnimation? scope) => _pending ?? scope ?? GlassAnimation.defaultSpring;

class GlassAnimationScope extends InheritedWidget {
  const GlassAnimationScope({super.key, required this.animation, required super.child});

  final GlassAnimation animation;

  static GlassAnimation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassAnimationScope>()?.animation;

  @override
  bool updateShouldNotify(GlassAnimationScope oldWidget) => oldWidget.animation != animation;
}
