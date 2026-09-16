import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/feature/pairing/logic/disconnect.dart';

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockServerConfigStore store;

  setUp(() {
    store = _MockServerConfigStore();
  });

  group('forgetServer', () {
    test('clears the saved server', () async {
      when(() => store.clear()).thenAnswer((_) async {});

      await forgetServer(store);

      verify(() => store.clear()).called(1);
    });

    test('surfaces a failure to clear the config', () async {
      when(() => store.clear()).thenAnswer((_) async => throw Exception('keystore unavailable'));

      await expectLater(forgetServer(store), throwsA(isA<Exception>()));
    });
  });
}
