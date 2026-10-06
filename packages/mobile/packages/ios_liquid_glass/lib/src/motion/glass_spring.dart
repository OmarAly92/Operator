import 'package:flutter/animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:meta/meta.dart';

@internal
class GlassSpring {
  GlassSpring(double value) : _value = value, _target = value;

  double _value;
  double _velocity = 0;
  double _target;
  Simulation? _simulation;
  Duration? _start;

  double get value => _value;

  double get velocity => _velocity;

  double get target => _target;

  bool get isMoving => _simulation != null;

  void jumpTo(double value, {double velocity = 0}) {
    _value = value;
    _target = value;
    _velocity = velocity;
    _simulation = null;
  }

  void animateTo(double target, GlassAnimation animation, Duration? now) {
    if (now != null) sample(now);
    _target = target;
    if (animation.isNone) {
      jumpTo(target);
      return;
    }
    if (_value == target && _velocity == 0) {
      _simulation = null;
      return;
    }
    _simulation = animation.simulate(_value, target, _velocity);
    _start = now;
  }

  void offsetBy(double delta, GlassAnimation animation, Duration? now) {
    if (now != null) sample(now);
    restart(_value + delta, _velocity, 0, animation, now);
  }

  void restart(double value, double velocity, double target, GlassAnimation animation, Duration? now) {
    _value = value;
    _velocity = velocity;
    _simulation = null;
    animateTo(target, animation, now);
  }

  GlassSpring copy() => GlassSpring(_value)
    .._velocity = _velocity
    .._target = _target
    .._simulation = _simulation
    .._start = _start;

  void restoreFrom(GlassSpring other, Duration? now) {
    _value = other._value;
    _velocity = other._velocity;
    _target = other._target;
    _simulation = other._simulation;
    _start = other._start;
    if (now != null) sample(now);
  }

  bool sample(Duration now) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final start = _start ??= now;
    final t = (now - start).inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(t)) {
      _value = _target;
      _velocity = 0;
      _simulation = null;
      return false;
    }
    _value = simulation.x(t);
    _velocity = simulation.dx(t);
    return true;
  }
}

@internal
class GlassMotionValue extends Animation<double> with AnimationEagerListenerMixin, AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  GlassMotionValue([this._value = 1]);

  double _value;

  @override
  double get value => _value;

  set value(double next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;
}
