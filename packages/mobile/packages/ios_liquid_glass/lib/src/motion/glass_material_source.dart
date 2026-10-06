import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';

@internal
class GlassMaterialSource extends ChangeNotifier {
  GlassMaterialSource({required GlassMaterial Function(double side) resolve, Color? tint, required double side})
    : _resolve = resolve,
      _tint = tint,
      _side = side {
    _apply(resolve(side), notify: false);
  }

  GlassMaterial Function(double side) _resolve;
  Color? _tint;
  double _side;
  late LiquidGlassSettings _settings;
  late List<BoxShadow> _shadows;

  double get side => _side;

  LiquidGlassSettings get settings => _settings;

  List<BoxShadow> get shadows => _shadows;

  void configure({required GlassMaterial Function(double side) resolve, Color? tint}) {
    _resolve = resolve;
    _tint = tint;
    _apply(resolve(_side));
  }

  void resize(double side, {bool exact = false}) {
    if (side == _side || (!exact && (side - _side).abs() < 0.5)) return;
    _side = side;
    _apply(_resolve(side));
  }

  void _apply(GlassMaterial material, {bool notify = true}) {
    final settings = material.toSettings(tint: _tint);
    final shadows = material.shadows;
    if (notify && settings == _settings && listEquals(shadows, _shadows)) return;
    _settings = settings;
    _shadows = shadows;
    if (notify) notifyListeners();
  }
}
