import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/theme_preference.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    AppPreferences.debugLoad(const {});
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

  blocTest<SkinCubit, SkinState>(
    'exposes the chosen preference separately from the resolved skin',
    build: SkinCubit.new,
    act: (cubit) => cubit.setSystemSkin(),
    verify: (cubit) => expect(cubit.preference, ThemeMode.system),
  );

  group('following the platform brightness while system is chosen', () {
    late TestPlatformDispatcher dispatcher;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      dispatcher = WidgetsBinding.instance.platformDispatcher as TestPlatformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.light;
      AppPreferences.debugLoad({PreferenceKeys.themeMode: 'system'});
    });

    tearDown(() {
      dispatcher.clearPlatformBrightnessTestValue();
    });

    blocTest<SkinCubit, SkinState>(
      'flips the skin when the OS brightness changes',
      build: SkinCubit.new,
      act: (cubit) => dispatcher.platformBrightnessTestValue = Brightness.dark,
      expect: () => [const SkinChangedState(DarkSkin())],
      verify: (cubit) {
        expect(cubit.skin, isA<DarkSkin>());
        expect(cubit.preference, ThemeMode.system);
      },
    );

    blocTest<SkinCubit, SkinState>(
      'keeps following after flipping back',
      build: SkinCubit.new,
      act: (cubit) {
        dispatcher.platformBrightnessTestValue = Brightness.dark;
        dispatcher.platformBrightnessTestValue = Brightness.light;
      },
      expect: () => [const SkinChangedState(DarkSkin()), const SkinChangedState(LightSkin())],
    );

    int preExistingCalls = 0;

    blocTest<SkinCubit, SkinState>(
      'chains a pre-existing platform brightness handler instead of replacing it',
      build: () {
        preExistingCalls = 0;
        dispatcher.onPlatformBrightnessChanged = () => preExistingCalls++;
        return SkinCubit();
      },
      act: (cubit) => dispatcher.platformBrightnessTestValue = Brightness.dark,
      expect: () => [const SkinChangedState(DarkSkin())],
      verify: (cubit) {
        expect(preExistingCalls, 1);
        expect(cubit.skin, isA<DarkSkin>());
      },
    );

    test('close() restores the previously chained brightness handler', () async {
      void preExisting() {}
      dispatcher.onPlatformBrightnessChanged = preExisting;
      final cubit = SkinCubit();
      await cubit.close();
      expect(dispatcher.onPlatformBrightnessChanged, same(preExisting));
    });

    test('close() restores null when there was no previously chained handler', () async {
      dispatcher.onPlatformBrightnessChanged = null;
      final cubit = SkinCubit();
      await cubit.close();
      expect(dispatcher.onPlatformBrightnessChanged, isNull);
    });
  });

  group('not following the platform brightness with an explicit preference', () {
    late TestPlatformDispatcher dispatcher;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      dispatcher = WidgetsBinding.instance.platformDispatcher as TestPlatformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.light;
    });

    tearDown(() {
      dispatcher.clearPlatformBrightnessTestValue();
    });

    blocTest<SkinCubit, SkinState>(
      'a brightness change does not affect an explicit light preference',
      build: SkinCubit.new,
      act: (cubit) {
        cubit.setSkin(const LightSkin());
        dispatcher.platformBrightnessTestValue = Brightness.dark;
      },
      expect: () => [const SkinChangedState(LightSkin())],
      verify: (cubit) => expect(cubit.skin, isA<LightSkin>()),
    );

    blocTest<SkinCubit, SkinState>(
      'a brightness change does not affect an explicit dark preference',
      build: SkinCubit.new,
      act: (cubit) {
        cubit.setSkin(const DarkSkin());
        dispatcher.platformBrightnessTestValue = Brightness.dark;
      },
      expect: () => [const SkinChangedState(DarkSkin())],
      verify: (cubit) => expect(cubit.skin, isA<DarkSkin>()),
    );

    blocTest<SkinCubit, SkinState>(
      'switching away from system stops following the OS',
      build: SkinCubit.new,
      act: (cubit) {
        cubit.setSystemSkin();
        cubit.setSkin(const LightSkin());
        dispatcher.platformBrightnessTestValue = Brightness.dark;
      },
      expect: () => [const SkinChangedState(LightSkin())],
      verify: (cubit) {
        expect(cubit.skin, isA<LightSkin>());
        expect(cubit.preference, ThemeMode.light);
      },
    );
  });

  group('preferenceLabel', () {
    test('light preference maps to Light', () {
      expect(preferenceLabel(ThemeMode.light), 'Light');
    });

    test('dark preference maps to Dark', () {
      expect(preferenceLabel(ThemeMode.dark), 'Dark');
    });

    test('system preference maps to System', () {
      expect(preferenceLabel(ThemeMode.system), 'System');
    });
  });
}
