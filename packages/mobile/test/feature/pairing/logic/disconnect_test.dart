import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/pairing/logic/disconnect.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockServerConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    store = _MockServerConfigStore();
  });

  group('forgetServer', () {
    test('clears the saved server and re-arms onboarding', () async {
      await CacheHelper.save(CacheKeys.onboardingSkipped, true);
      when(() => store.clear()).thenAnswer((_) async {});

      await forgetServer(store);

      verify(() => store.clear()).called(1);
      expect(CacheHelper.get(CacheKeys.onboardingSkipped), isNull);
    });

    test('still clears onboarding when clearing the config throws', () async {
      await CacheHelper.save(CacheKeys.onboardingSkipped, true);
      when(() => store.clear()).thenAnswer((_) async => throw Exception('keystore unavailable'));

      await expectLater(forgetServer(store), throwsA(isA<Exception>()));

      expect(CacheHelper.get(CacheKeys.onboardingSkipped), isNull);
    });
  });
}
