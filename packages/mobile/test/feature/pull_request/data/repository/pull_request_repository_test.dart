import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';

class _MockPullRequestRemoteDataSource extends Mock implements PullRequestRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockPullRequestRemoteDataSource dataSource;
  late _MockNetworkStatus network;
  late PullRequestRepositoryImp repository;

  setUp(() {
    dataSource = _MockPullRequestRemoteDataSource();
    network = _MockNetworkStatus();
    repository = PullRequestRepositoryImp(dataSource, network);
  });

  test('fails fast with noNetwork when the daemon is unreachable', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getSessionPr('s1');

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getSessionPr('s1'));
  });

  test('returns the PR summaries on success', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getSessionPr('s1')).thenAnswer(
      (_) async => const GlobalResponse<List<SessionPrSummaryModel>>(
        data: [
          SessionPrSummaryModel(
            number: 184,
            title: 'Fix auth timeouts',
            state: 'open',
            repo: 'o/r',
          ),
        ],
      ),
    );

    final result = await repository.getSessionPr('s1');

    expect(result.isSuccess, isTrue);
    result.when(
      onSuccess: (r) => expect(r.data!.single.number, 184),
      onFailure: (_) => fail('expected success'),
    );
  });

  test('merge and getSessionPr propagate a Failure', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getSessionPr('s1')).thenThrow(ServerFailure.noNetwork());

    final result = await repository.getSessionPr('s1');

    expect(result.isFailure, isTrue);
  });
}
