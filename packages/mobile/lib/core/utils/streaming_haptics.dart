import 'package:operator_mobile/core/app_themes/app_motion.dart';

class StreamingHaptics {
  StreamingHaptics({
    required this.fire,
    required this.clock,
    bool reduceMotion = false,
  }) : enabled = !reduceMotion;

  final void Function() fire;
  final Duration Function() clock;
  final bool enabled;

  Duration? _lastFire;

  void onStreamStart() {
    if (!enabled) return;
    _lastFire = clock();
    fire();
  }

  void onTextGrew() {
    if (!enabled) return;
    final now = clock();
    if (_lastFire != null && now - _lastFire! < AppMotion.streamingHapticGap) return;
    _lastFire = now;
    fire();
  }
}
