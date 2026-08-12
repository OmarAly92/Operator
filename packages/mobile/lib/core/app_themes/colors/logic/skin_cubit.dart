import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';

part 'skin_state.dart';

class SkinCubit extends Cubit<SkinState> {
  SkinCubit() : skin = _savedSkin(), super(const SkinInitialState());

  AppSkin skin;

  static AppSkin _savedSkin() {
    final savedTheme = CacheHelper.get(CacheKeys.currentTheme) as String?;
    if (savedTheme == ThemeMode.dark.name) return const DarkSkin();
    if (savedTheme == ThemeMode.system.name) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? const DarkSkin()
          : const LightSkin();
    }
    return const LightSkin();
  }

  void setSkin(AppSkin newSkin) {
    skin = newSkin;
    CacheHelper.save(CacheKeys.currentTheme, newSkin.themeMode.name);
    emit(SkinChangedState(newSkin));
  }

  void toggleSkin() {
    setSkin(
      skin.themeMode == ThemeMode.dark ? const LightSkin() : const DarkSkin(),
    );
  }

  void setSystemSkin() {
    skin =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark
        ? const DarkSkin()
        : const LightSkin();
    CacheHelper.save(CacheKeys.currentTheme, ThemeMode.system.name);
    emit(SkinChangedState(skin));
  }
}

extension SkinSwitcherContext on BuildContext {
  void setSkin(AppSkin skin) => read<SkinCubit>().setSkin(skin);

  void toggleSkin() => read<SkinCubit>().toggleSkin();

  void setSystemSkin() => read<SkinCubit>().setSystemSkin();
}
