import 'package:flutter/services.dart';

const hapticChannel = MethodChannel('com.operator.mobile/haptics');

enum HapticType {
  tap,
  select,
  success,
  warning,
  error,
}

Future<void> triggerHaptic(HapticType feedback) async {
  switch (feedback) {
    case HapticType.tap:
      return HapticFeedback.lightImpact();
    case HapticType.select:
      return HapticFeedback.mediumImpact();
    case HapticType.success:
      return hapticChannel.invokeMethod('notification', {'type': 'success'});
    case HapticType.warning:
      return hapticChannel.invokeMethod('notification', {'type': 'warning'});
    case HapticType.error:
      return hapticChannel.invokeMethod('notification', {'type': 'error'});
  }
}
