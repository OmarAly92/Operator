import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';

part 'skin_state.dart';

class SkinCubit extends Cubit<SkinState> {
  SkinCubit() : skin = _savedSkin(), super(const SkinInitialState());

  AppSkin skin;

  static AppSkin _savedSkin() {
    final saved = AppPreferences.themeMode;
    if (saved == ThemeMode.dark) return const DarkSkin();
    if (saved == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
          ? const DarkSkin()
          : const LightSkin();
    }
    return const LightSkin();
  }

  void setSkin(AppSkin newSkin) {
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
    skin = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        ? const DarkSkin()
        : const LightSkin();
    AppPreferences.setThemeMode(ThemeMode.system);
    emit(SkinChangedState(skin));
  }
}

extension SkinSwitcherContext on BuildContext {
  void setSkin(AppSkin skin) => read<SkinCubit>().setSkin(skin);

  void toggleSkin() => read<SkinCubit>().toggleSkin();

  void setSystemSkin() => read<SkinCubit>().setSystemSkin();
}
