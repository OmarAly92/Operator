import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

class _MockSessionsRemoteDataSource extends Mock implements SessionsRemoteDataSource {}

class _MockSessionsLocalDataSource extends Mock implements SessionsLocalDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = _desktopA;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

const _desktopA = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'a');
const _desktopB = ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'pw', desktopId: 'b');

const _payload = BoardPayload(
  sessions: {
    'sessions': [
      {'id': 'proj-1'},
    ],
  },
  accounts: {
    'accounts': [
      {'id': 'default', 'label': 'Default'},
    ],
  },
);

void main() {
  late _MockSessionsRemoteDataSource dataSource;
  late _MockSessionsLocalDataSource local;
  late _MockNetworkStatus network;
  late _Config config;
  late SessionsRepositoryImp repository;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUpAll(() {
    registerFallbackValue(const BoardPayload(sessions: {}));
    registerFallbackValue(DateTime.utc(2026));
  });

  setUp(() {
    dataSource = _MockSessionsRemoteDataSource();
    local = _MockSessionsLocalDataSource();
    network = _MockNetworkStatus();
    config = _Config();
    repository = SessionsRepositoryImp(dataSource, network, local, config, clock: () => at);
    when(() => local.writeBoard(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteBoard(any())).thenAnswer((_) async {});
  });

  test('fails fast with noNetwork when the daemon is unreachable', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getBoard();

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getBoard());
  });

  test('returns the board snapshot on success', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);

    final result = await repository.getBoard();

    expect(result.isSuccess, isTrue);
    result.when(
      onSuccess: (r) => expect(r.data!.sessions.single.id, 'proj-1'),
      onFailure: (_) => fail('expected success'),
    );
  });

  test('stores the payload under the active desktop after a successful fetch', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);

    await repository.getBoard();

    verify(() => local.writeBoard('a', _payload, at)).called(1);
  });

  test('drops the write when the desktop changed while the fetch was in flight', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async {
      config.current = _desktopB;
      return _payload;
    });

    await repository.getBoard();

    verifyNever(() => local.writeBoard(any(), any(), any()));
  });

  test('a failed write still returns the fresh board', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => _payload);
    when(() => local.writeBoard(any(), any(), any())).thenThrow(LocalFailure<void>(error: 'disk full'));

    final result = await repository.getBoard();

    expect(result.isSuccess, isTrue);
  });

  test('a network body that does not parse is a failure and is not stored', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getBoard()).thenAnswer((_) async => const BoardPayload(sessions: {'sessions': 'nope'}));

    final result = await repository.getBoard();

    expect(result.isFailure, isTrue);
    verifyNever(() => local.writeBoard(any(), any(), any()));
  });

  test('cachedBoard parses the active desktop replica through the same model', () async {
    when(() => local.readBoard('a')).thenAnswer((_) async => Replicated(value: _payload, fetchedAt: at));

    final cached = await repository.cachedBoard();

    expect(cached!.value.sessions.single.id, 'proj-1');
    expect(cached.value.accountLabels, {'default': 'Default'});
    expect(cached.fetchedAt, at);
  });

  test('cachedBoard misses without an active desktop', () async {
    config.current = null;

    expect(await repository.cachedBoard(), isNull);
    verifyNever(() => local.readBoard(any()));
  });

  test('a replica that no longer parses is deleted and read as a miss', () async {
    when(() => local.readBoard('a')).thenAnswer(
      (_) async => Replicated(value: const BoardPayload(sessions: {'sessions': 'nope'}), fetchedAt: at),
    );

    expect(await repository.cachedBoard(), isNull);
    verify(() => local.deleteBoard('a')).called(1);
  });

  test('a replica that is not JSON is deleted and read as a miss', () async {
    when(() => local.readBoard('a')).thenThrow(const FormatException('not json'));

    expect(await repository.cachedBoard(), isNull);
    verify(() => local.deleteBoard('a')).called(1);
  });

  test('a drift read failure is a miss that keeps the row', () async {
    when(() => local.readBoard('a')).thenThrow(LocalFailure<void>(error: 'locked'));

    expect(await repository.cachedBoard(), isNull);
    verifyNever(() => local.deleteBoard(any()));
  });

  test('kill and restore propagate a Failure', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.kill('proj-1')).thenThrow(ServerFailure.noNetwork());

    final result = await repository.kill('proj-1');

    expect(result.isFailure, isTrue);
  });
}
