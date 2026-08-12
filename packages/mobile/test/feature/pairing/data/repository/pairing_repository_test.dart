import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

class _MockPairingRemoteDataSource extends Mock implements PairingRemoteDataSource {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

void main() {
  late _MockPairingRemoteDataSource dataSource;
  late _MockServerConfigStore store;
  late PairingRepositoryImp repository;

  setUpAll(() {
    registerFallbackValue(_target);
  });

  setUp(() {
    dataSource = _MockPairingRemoteDataSource();
    store = _MockServerConfigStore();
    repository = PairingRepositoryImp(dataSource, store);
  });

  test('saves the config only after the ping succeeds', () async {
    when(() => dataSource.ping(_target)).thenAnswer((_) async {});
    when(() => store.save(_target)).thenAnswer((_) async {});

    final result = await repository.verifyAndConnect(_target);

    expect(result.isSuccess, isTrue);
    verifyInOrder([() => dataSource.ping(_target), () => store.save(_target)]);
  });

  test('does not save when the ping fails', () async {
    final failure = ServerFailure.noNetwork();
    when(() => dataSource.ping(_target)).thenThrow(failure);

    final result = await repository.verifyAndConnect(_target);

    expect(result.isFailure, isTrue);
    verifyNever(() => store.save(any()));
  });
}
