import 'dart:async';

import 'package:flutter/foundation.dart';

class WorkingClock extends ChangeNotifier implements ValueListenable<DateTime> {
  WorkingClock({DateTime Function()? now}) : _read = now ?? DateTime.now, _value = (now ?? DateTime.now)();

  static final WorkingClock shared = WorkingClock();

  static const Duration period = Duration(seconds: 1);

  final DateTime Function() _read;
  DateTime _value;
  Timer? _timer;

  @override
  DateTime get value => _value;

  bool get ticking => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _value = _read();
      _timer = Timer.periodic(period, (_) {
        _value = _read();
        notifyListeners();
      });
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
