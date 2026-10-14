import 'dart:math' as math;
import 'dart:ui';

import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:ios_liquid_glass/src/motion/ios27_press.dart';
import 'package:meta/meta.dart';

@internal
class GlassPress {
  final GlassSpring _growth = GlassSpring(0);
  final GlassSpring _swell = GlassSpring(0);
  final GlassSpring _focusX = GlassSpring(0);
  final GlassSpring _focusY = GlassSpring(0);
  bool _pressed = false;
  bool _lit = false;
  bool _reduceMotion = false;
  double _cut = 0;
  Duration? _downAt;
  Duration? _upAt;
  bool _growthStarted = false;
  bool _releaseStarted = false;
  bool _fadeStarted = false;
  bool _downPending = false;
  bool _upPending = false;

  static const GlassAnimation growthAnimation =
      GlassAnimation.dampedSpring(response: ios27PressGrowthResponse, dampingFraction: ios27PressGrowthDamping);
  static const GlassAnimation releaseAnimation =
      GlassAnimation.dampedSpring(response: ios27PressReleaseResponse, dampingFraction: ios27PressReleaseDamping);
  static const GlassAnimation riseAnimation =
      GlassAnimation.dampedSpring(response: ios27PressGlowRiseResponse, dampingFraction: ios27PressGlowRiseDamping);
  static const GlassAnimation fadeAnimation =
      GlassAnimation.dampedSpring(response: ios27PressGlowFadeResponse, dampingFraction: ios27PressGlowFadeDamping);
  static const GlassAnimation followAnimation = GlassAnimation.dampedSpring(response: 1, dampingFraction: 1);

  bool get isPressed => _pressed;

  bool get isActive => _pressed || _lit || _growth.isMoving || _growth.value != 0 || _swell.isMoving || _focusX.isMoving || _focusY.isMoving;

  double get growth => _growth.value;

  double get hold => _lit ? 1 : 0;

  double get swell => _lit ? _swell.value.clamp(0.0, 1.0) : 0;

  Offset get focus => Offset(_focusX.value, _focusY.value);

  static double widthGrowth(Size size) {
    if (size.height <= 0 || size.width <= 0) return 0;
    return math.min(ios27PressGrowthCap, ios27PressGrowthAt100 * math.pow(100 / size.height, ios27PressGrowthPower) * math.pow(100 / size.width, ios27PressGrowthWidthPower));
  }

  static double scaleFor(Size size, double growth) {
    if (size.width <= 0 || growth == 0) return 1;
    return 1 + widthGrowth(size) / size.width * growth;
  }

  static (double, double) glowFor(Size size) {
    final area = size.width * size.height;
    return (_interpolate(area, ios27PressGlowHoldLuma) / 255, _interpolate(area, ios27PressGlowSwellLuma) / 255);
  }

  static double cutFor(Size size, {required bool reduceMotion}) =>
      reduceMotion ? ios27PressReduceMotionGlowCut : _interpolate(size.width * size.height, ios27PressGlowCutSeconds);

  static double _interpolate(double area, List<double> values) {
    const areas = ios27PressGlowAreas;
    if (area <= areas.first) return values.first;
    if (area >= areas.last) return values.last;
    for (var i = 1; i < areas.length; i++) {
      if (area <= areas[i]) {
        final a = math.log(areas[i - 1]), b = math.log(areas[i]);
        final t = (math.log(area) - a) / (b - a);
        return values[i - 1] + (values[i] - values[i - 1]) * t;
      }
    }
    return values.last;
  }

  void down(Offset position, {required bool reduceMotion, required double cut, Duration? now}) {
    _pressed = true;
    _cut = cut;
    _lit = true;
    _reduceMotion = reduceMotion;
    _downAt = now;
    _downPending = now == null;
    _upAt = null;
    _upPending = false;
    _growthStarted = false;
    _releaseStarted = false;
    _fadeStarted = false;
    _focusX.jumpTo(position.dx);
    _focusY.jumpTo(position.dy);
    _swell.restart(ios27PressGlowRiseJump, 0, 1, riseAnimation, now);
  }

  void move(Offset position, {Duration? now}) {
    if (!_pressed) return;
    _focusX.animateTo(position.dx, followAnimation, now);
    _focusY.animateTo(position.dy, followAnimation, now);
  }

  void up({Duration? now}) {
    if (!_pressed) return;
    _pressed = false;
    _upAt = now;
    _upPending = now == null;
  }

  bool sample(Duration now) {
    if (_downPending) {
      _downPending = false;
      _downAt = now;
    }
    if (_upPending) {
      _upPending = false;
      _upAt = now;
    }
    final down = _downAt;
    if (_pressed && down != null && !_growthStarted && !_reduceMotion && now - down >= _seconds(ios27PressGrowthDelay)) {
      _growthStarted = true;
      _growth.animateTo(1, growthAnimation, now);
    }
    final up = _upAt;
    if (!_pressed && up != null) {
      final since = now - up;
      if (!_releaseStarted && since >= _seconds(ios27PressReleaseDelay)) {
        _releaseStarted = true;
        _growthStarted = true;
        _growth.animateTo(0, releaseAnimation, now);
      }
      if (!_fadeStarted && since >= _seconds(ios27PressGlowHold)) {
        _fadeStarted = true;
        _swell.animateTo(0, fadeAnimation, now);
      }
      if (_lit && since >= _seconds(_cut)) {
        _lit = false;
        _swell.jumpTo(0);
        _upAt = null;
      }
    }
    var moving = _growth.sample(now);
    moving = _swell.sample(now) || moving;
    moving = _focusX.sample(now) || moving;
    moving = _focusY.sample(now) || moving;
    return moving || _pressed || _lit;
  }

  void settle() {
    _pressed = false;
    _lit = false;
    _upAt = null;
    _growth.jumpTo(0);
    _swell.jumpTo(0);
  }

  static Duration _seconds(double value) => Duration(microseconds: (value * Duration.microsecondsPerSecond).round());
}
