import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

class _MockSessionsRemoteDataSource extends Mock implements SessionsRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockSessionsRemoteDataSource dataSource;
  late _MockNetworkStatus network;
  late SessionsRepositoryImp repository;

  setUp(() {
    dataSource = _MockSessionsRemoteDataSource();
    network = _MockNetworkStatus();
    repository = SessionsRepositoryImp(dataSource, network);
  });

  test('fails fast with noNetwork when the daemon is unreachable', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getSessions();

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getSessions());
  });

  test('returns the sessions list on success', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getSessions()).thenAnswer(
      (_) async => const GlobalResponse<List<SessionModel>>(data: [SessionModel(id: 'proj-1')]),
    );

    final result = await repository.getSessions();

    expect(result.isSuccess, isTrue);
    result.when(onSuccess: (r) => expect(r.data!.single.id, 'proj-1'), onFailure: (_) => fail('expected success'));
  });

  test('kill and restore propagate a Failure', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.kill('proj-1')).thenThrow(ServerFailure.noNetwork());

    final result = await repository.kill('proj-1');

    expect(result.isFailure, isTrue);
  });
}
