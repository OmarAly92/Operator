import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
  });

  blocTest<SkinCubit, SkinState>(
    'switches from light to dark and keeps the new skin',
    build: SkinCubit.new,
    act: (cubit) => cubit.setSkin(const DarkSkin()),
    expect: () => [const SkinChangedState(DarkSkin())],
    verify: (cubit) {
      expect(cubit.skin, isA<DarkSkin>());
      expect(cubit.skin.themeMode, ThemeMode.dark);
    },
  );

  blocTest<SkinCubit, SkinState>(
    'starts on the light skin with no saved preference',
    build: SkinCubit.new,
    verify: (cubit) => expect(cubit.skin, isA<LightSkin>()),
  );
}
