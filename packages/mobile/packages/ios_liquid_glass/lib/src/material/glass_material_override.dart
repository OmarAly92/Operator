import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class GlassMaterialOverride extends InheritedWidget {
  const GlassMaterialOverride({super.key, required this.values, this.side, required super.child});

  final Map<String, double> values;
  final double? side;

  static Map<String, double> of(BuildContext context) {
    if (!kDebugMode) return const {};
    return context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>()?.values ?? const {};
  }

  static Map<String, double> forSide(BuildContext context, double shorterSide) => valuesFor(scopeOf(context), shorterSide);

  static GlassMaterialOverride? scopeOf(BuildContext context) =>
      kDebugMode ? context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>() : null;

  static Map<String, double> valuesFor(GlassMaterialOverride? scope, double shorterSide) {
    if (!kDebugMode || scope == null) return const {};
    final side = scope.side;
    if (side != null && (shorterSide.clamp(44.0, 200.0) - side).abs() >= 1) return const {};
    return scope.values;
  }

  @override
  bool updateShouldNotify(GlassMaterialOverride oldWidget) => !mapEquals(oldWidget.values, values) || oldWidget.side != side;
}
