import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/material/ios27_scroll_edge.dart';

enum ScrollEdgeStyle { soft, hard, automatic }

@immutable
class ScrollEdgeMaterial {
  const ScrollEdgeMaterial(this.values);

  static const String overridePrefix = 'edge.';

  static const Map<String, double> defaults = {
    'extent': 34,
    'blur': 4,
    'dim': 0.6,
    'knee': 0.45,
    'cap': 0.88,
    'capBlur': 6,
    'line': 0,
    'lineShade': 0.5,
  };

  final Map<String, double> values;

  double operator [](String name) => values[name] ?? defaults[name]!;

  ScrollEdgeMaterial withOverrides(Map<String, double> overrides) {
    final picked = {
      for (final entry in overrides.entries)
        if (entry.key.startsWith(overridePrefix)) entry.key.substring(overridePrefix.length): entry.value,
    };
    return picked.isEmpty ? this : ScrollEdgeMaterial({...values, ...picked});
  }

  static ScrollEdgeMaterial resolve({
    required ScrollEdgeStyle style,
    required Brightness brightness,
    Map<String, Map<String, double>> table = ios27ScrollEdgeTable,
  }) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';
    return ScrollEdgeMaterial(table['$appearance.${style.name}'] ?? const {});
  }
}
