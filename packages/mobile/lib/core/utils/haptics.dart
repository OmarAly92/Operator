import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class Haptics {
  static const String channelName = 'operator/haptics';
  static const MethodChannel _channel = MethodChannel(channelName);

  static void tap() => _fire(HapticFeedback.lightImpact());

  static void select() => _fire(HapticFeedback.selectionClick());

  static void success() => _notify('success');

  static void warning() => _notify('warning');

  static void error() => _notify('error');

  static void _notify(String kind) => _fire(_channel.invokeMethod<void>('notify', kind));

  static void _fire(Future<void> call) {
    unawaited(call.catchError((Object error, StackTrace stack) {
      if (kDebugMode) debugPrint('haptics: $error');
    }));
  }
}
