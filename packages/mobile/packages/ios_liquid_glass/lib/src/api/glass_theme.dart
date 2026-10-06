import 'package:flutter/widgets.dart';

@immutable
class GlassThemeData {
  const GlassThemeData({this.brightness, this.accent, this.scrollEdgeTint});

  final Brightness? brightness;
  final Color? accent;
  final Color? scrollEdgeTint;

  @override
  bool operator ==(Object other) => other is GlassThemeData && other.brightness == brightness && other.accent == accent && other.scrollEdgeTint == scrollEdgeTint;

  @override
  int get hashCode => Object.hash(brightness, accent, scrollEdgeTint);
}

class GlassTheme extends InheritedWidget {
  const GlassTheme({super.key, required this.data, required super.child});

  final GlassThemeData data;

  static GlassThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTheme>()?.data ?? const GlassThemeData();

  static Brightness brightnessOf(BuildContext context) =>
      of(context).brightness ?? MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;

  @override
  bool updateShouldNotify(GlassTheme oldWidget) => oldWidget.data != data;
}
