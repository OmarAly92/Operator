import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';

class _MockLocal extends Mock implements DesktopsLocalDataSource {}

const _active = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);

void main() {
  late _MockLocal local;
  late ServerConfigStore store;

  setUp(() {
    local = _MockLocal();
    store = ServerConfigStore(local);
  });

  test('load resolves the active desktop and its password into current', () async {
    when(() => local.getActive()).thenAnswer((_) async => _active);
    when(() => local.passwordFor('a')).thenAnswer((_) async => 'pw');

    await store.load();

    expect(
      store.current,
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a'),
    );
  });

  test('load leaves current null when nothing is active', () async {
    when(() => local.getActive()).thenAnswer((_) async => null);
    await store.load();
    expect(store.current, isNull);
  });

  test('load leaves current null when the password is missing', () async {
    when(() => local.getActive()).thenAnswer((_) async => _active);
    when(() => local.passwordFor('a')).thenAnswer((_) async => null);
    await store.load();
    expect(store.current, isNull);
  });

  test('set emits the config on changes and clear emits null', () async {
    const config = ServerConfig(host: 'h', httpPort: '1', secure: true, password: 'p');
    final seen = <ServerConfig?>[];
    final sub = store.changes.listen(seen.add);

    store.set(config);
    store.clear();
    await Future<void>.delayed(Duration.zero);

    expect(seen, [config, null]);
    await sub.cancel();
  });

  test('load does not emit on changes', () async {
    when(() => local.getActive()).thenAnswer((_) async => _active);
    when(() => local.passwordFor('a')).thenAnswer((_) async => 'pw');
    final seen = <ServerConfig?>[];
    final sub = store.changes.listen(seen.add);

    await store.load();
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(store.current, isNotNull);
    await sub.cancel();
  });

  test('set and clear only touch memory', () {
    const config = ServerConfig(host: 'h', httpPort: '1', secure: true, password: 'p');
    store.set(config);
    expect(store.current, config);
    store.clear();
    expect(store.current, isNull);
    verifyZeroInteractions(local);
  });

  test('activeDesktopName follows the active desktop row', () async {
    when(() => local.watchAll()).thenAnswer(
      (_) => Stream.value(const [
        DesktopModel(id: 'b', name: 'iMac', isActive: false),
        DesktopModel(id: 'a', name: 'Mac', isActive: true),
      ]),
    );

    expect(await store.activeDesktopName.first, 'Mac');
  });
}
