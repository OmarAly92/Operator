import 'package:flutter/material.dart';

String preferenceLabel(ThemeMode preference) {
  switch (preference) {
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
    case ThemeMode.system:
      return 'System';
  }
}
