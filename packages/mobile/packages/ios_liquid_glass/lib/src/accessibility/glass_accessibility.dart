import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@immutable
class GlassAccessibilityData {
  const GlassAccessibilityData({
    this.reduceTransparency = false,
    this.increaseContrast = false,
    this.reduceMotion = false,
  });

  factory GlassAccessibilityData.fromMap(Map<Object?, Object?> map) => GlassAccessibilityData(
    reduceTransparency: map['reduceTransparency'] == true,
    increaseContrast: map['increaseContrast'] == true,
    reduceMotion: map['reduceMotion'] == true,
  );

  final bool reduceTransparency;
  final bool increaseContrast;
  final bool reduceMotion;

  GlassAccessibilityData merge(GlassAccessibilityData other) => GlassAccessibilityData(
    reduceTransparency: reduceTransparency || other.reduceTransparency,
    increaseContrast: increaseContrast || other.increaseContrast,
    reduceMotion: reduceMotion || other.reduceMotion,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassAccessibilityData &&
      other.reduceTransparency == reduceTransparency &&
      other.increaseContrast == increaseContrast &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(reduceTransparency, increaseContrast, reduceMotion);
}

sealed class GlassAccessibility {
  static const EventChannel channel = EventChannel('ios_liquid_glass/accessibility');

  static final ValueNotifier<GlassAccessibilityData> platform = ValueNotifier(const GlassAccessibilityData());

  static GlassAccessibilityData? debugOverride;

  static StreamSubscription<Object?>? _subscription;

  static void ensureListening() {
    if (_subscription != null || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _subscription = channel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) platform.value = GlassAccessibilityData.fromMap(event);
      },
      onError: (Object _) {},
    );
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await _subscription?.cancel();
    _subscription = null;
    debugOverride = null;
    platform.value = const GlassAccessibilityData();
  }

  static GlassAccessibilityData of(BuildContext context) {
    final override = debugOverride;
    if (override != null) return override;
    ensureListening();
    final media = GlassAccessibilityData(
      increaseContrast: MediaQuery.maybeHighContrastOf(context) ?? false,
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    return media.merge(platform.value);
  }
}
