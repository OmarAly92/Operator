import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/replica/replica_cache.dart';

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = _desktopA;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

const _desktopA = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a');
const _desktopB = ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'pw', desktopId: 'b');

void main() {
  late _Config config;
  late ReplicaCache cache;
  late List<String> forgotten;

  setUp(() {
    config = _Config();
    cache = ReplicaCache(config);
    forgotten = [];
  });

  Future<void> forget(String desktopId) async => forgotten.add(desktopId);

  group('read', () {
    test('a hit loads the active desktop body and parses it', () async {
      String? loadedFor;
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (desktopId) async {
          loadedFor = desktopId;
          return {'count': 3};
        },
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, 3);
      expect(loadedFor, 'a');
      expect(forgotten, isEmpty);
    });

    test('nothing stored is a miss that deletes nothing', () async {
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async => null,
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, isNull);
      expect(forgotten, isEmpty);
    });

    test('no active desktop is a miss that never loads', () async {
      config.current = null;
      var loads = 0;

      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async {
          loads++;
          return {'count': 3};
        },
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, isNull);
      expect(loads, 0);
    });

    test('a body the parser rejects is deleted and read as a miss', () async {
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async => {'count': 'three'},
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, isNull);
      expect(forgotten, ['a']);
    });

    test('a body that fails to decode while loading is deleted and read as a miss', () async {
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async => throw const FormatException('not json'),
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, isNull);
      expect(forgotten, ['a']);
    });

    test('a storage failure while loading is a miss that keeps the row', () async {
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async => throw LocalFailure<void>(error: 'locked'),
        parse: (body) => body['count'] as int,
        forget: forget,
      );

      expect(value, isNull);
      expect(forgotten, isEmpty);
    });

    test('a storage failure while deleting still reads as a miss', () async {
      final value = await cache.read<Map<String, dynamic>, int>(
        load: (_) async => {'count': 'three'},
        parse: (body) => body['count'] as int,
        forget: (_) async => throw LocalFailure<void>(error: 'locked'),
      );

      expect(value, isNull);
    });
  });

  group('remember', () {
    test('writes under the desktop the fetch started for while it is still active', () async {
      final written = <String>[];

      await cache.remember('a', (desktopId) async => written.add(desktopId));

      expect(written, ['a']);
    });

    test('drops the write when the active desktop changed', () async {
      final written = <String>[];
      config.current = _desktopB;

      await cache.remember('a', (desktopId) async => written.add(desktopId));

      expect(written, isEmpty);
    });

    test('drops the write when the fetch started with no desktop', () async {
      final written = <String>[];

      await cache.remember(null, (desktopId) async => written.add(desktopId));

      expect(written, isEmpty);
    });

    test('swallows a storage failure', () async {
      await expectLater(
        cache.remember('a', (_) async => throw LocalFailure<void>(error: 'disk full')),
        completes,
      );
    });
  });

  test('desktopId reads the active desktop', () {
    expect(cache.desktopId, 'a');
    config.current = null;
    expect(cache.desktopId, isNull);
  });
}
