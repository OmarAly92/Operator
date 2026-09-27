import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class GlassMaterialOverride extends InheritedWidget {
  const GlassMaterialOverride({super.key, required this.values, required super.child});

  final Map<String, double> values;

  static Map<String, double> of(BuildContext context) {
    if (!kDebugMode) return const {};
    return context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>()?.values ?? const {};
  }

  @override
  bool updateShouldNotify(GlassMaterialOverride oldWidget) => !mapEquals(oldWidget.values, values);
}
