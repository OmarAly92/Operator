import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/logic/disconnect.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockDesktops desktops;
  late _MockStore store;

  setUp(() {
    desktops = _MockDesktops();
    store = _MockStore();
  });

  test('forgetServer deactivates the desktop and clears the live config', () async {
    when(() => desktops.deactivate()).thenAnswer((_) async => Result.success(null));

    await forgetServer(desktops, store);

    verifyInOrder([() => desktops.deactivate(), () => store.clear()]);
  });

  test('forgetServer still clears the live config when deactivation fails', () async {
    when(() => desktops.deactivate()).thenThrow(Exception('disk'));

    await expectLater(forgetServer(desktops, store), throwsA(isA<Exception>()));

    verify(() => store.clear()).called(1);
  });
}
