import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart';

@internal
sealed class GlassFrame {
  static int _count = 0;
  static SchedulerBinding? _binding;

  static int get current {
    final binding = SchedulerBinding.instance;
    if (!identical(binding, _binding)) {
      _binding = binding;
      binding.addPersistentFrameCallback((_) => _count++);
    }
    return _count;
  }
}
