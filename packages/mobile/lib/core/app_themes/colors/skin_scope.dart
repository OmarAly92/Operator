import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class SkinScope extends InheritedWidget {
  const SkinScope({super.key, required this.skin, required super.child});

  final AppSkin skin;

  static AppSkin of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SkinScope>();
    assert(scope != null, 'SkinScope not found above this context');
    return scope!.skin;
  }

  @override
  bool updateShouldNotify(SkinScope oldWidget) => skin != oldWidget.skin;
}

extension SkinContext on BuildContext {
  AppSkin get skin => SkinScope.of(this);
}
