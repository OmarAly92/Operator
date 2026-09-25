import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';

part 'skin_state.dart';

class SkinCubit extends Cubit<SkinState> {
  SkinCubit() : preference = _savedPreference(), skin = _resolvedSkin(_savedPreference()), super(const SkinInitialState()) {
    if (preference == ThemeMode.system) _startFollowingBrightness();
  }

  AppSkin skin;
  ThemeMode preference;

  VoidCallback? _chainedBrightnessHandler;
  bool _followingBrightness = false;

  static ThemeMode _savedPreference() => AppPreferences.themeMode ?? ThemeMode.light;

  static AppSkin _resolvedSkin(ThemeMode preference) {
    switch (preference) {
      case ThemeMode.dark:
        return const DarkSkin();
      case ThemeMode.system:
        return _systemSkin();
      case ThemeMode.light:
        return const LightSkin();
    }
  }

  static AppSkin _systemSkin() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
          ? const DarkSkin()
          : const LightSkin();

  void _startFollowingBrightness() {
    if (_followingBrightness) return;
    _followingBrightness = true;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _chainedBrightnessHandler = dispatcher.onPlatformBrightnessChanged;
    dispatcher.onPlatformBrightnessChanged = _onPlatformBrightnessChanged;
  }

  void _stopFollowingBrightness() {
    if (!_followingBrightness) return;
    _followingBrightness = false;
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged = _chainedBrightnessHandler;
    _chainedBrightnessHandler = null;
  }

  void _onPlatformBrightnessChanged() {
    _chainedBrightnessHandler?.call();
    if (isClosed || preference != ThemeMode.system) return;
    skin = _systemSkin();
    emit(SkinChangedState(skin));
  }

  void setSkin(AppSkin newSkin) {
    _stopFollowingBrightness();
    preference = newSkin.themeMode;
    skin = newSkin;
    AppPreferences.setThemeMode(newSkin.themeMode);
    emit(SkinChangedState(newSkin));
  }

  void toggleSkin() {
    setSkin(
      skin.themeMode == ThemeMode.dark ? const LightSkin() : const DarkSkin(),
    );
  }

  void setSystemSkin() {
    preference = ThemeMode.system;
    skin = _systemSkin();
    AppPreferences.setThemeMode(ThemeMode.system);
    _startFollowingBrightness();
    emit(SkinChangedState(skin));
  }

  @override
  Future<void> close() {
    _stopFollowingBrightness();
    return super.close();
  }
}

extension SkinSwitcherContext on BuildContext {
  void setSkin(AppSkin skin) => read<SkinCubit>().setSkin(skin);

  void toggleSkin() => read<SkinCubit>().toggleSkin();

  void setSystemSkin() => read<SkinCubit>().setSystemSkin();
}
