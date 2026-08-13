import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late PullRequestRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = PullRequestRemoteDataSourceImp(apiConsumer);
  });

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  test('parses the rich summary the card renders', () async {
    when(() => apiConsumer.get(EndPoints.sessionPr('s1'))).thenAnswer(
      (_) async => jsonResponse({
        'prs': [
          {
            'number': 184,
            'title': 'Fix auth timeouts',
            'state': 'open',
            'repo': 'o/r',
            'author': 'omar',
            'htmlUrl': 'https://github.com/o/r/pull/184',
            'sourceBranch': 'fix/auth',
            'targetBranch': 'main',
            'additions': 12,
            'deletions': 3,
            'changedFiles': 2,
            'ci': {
              'state': 'failing',
              'failingChecks': [{'name': 'go test'}, {'name': 'lint'}],
            },
            'review': {'decision': 'changes_requested', 'hasUnresolvedHumanComments': true},
            'mergeability': {'state': 'conflicting', 'reasons': ['behind_base']},
          },
        ],
      }),
    );

    final summaries = (await dataSource.getSessionPr('s1')).data!;
    final pr = summaries.single;

    expect(pr.number, 184);
    expect(pr.title, 'Fix auth timeouts');
    expect(pr.repo, 'o/r');
    expect(pr.changedFiles, 2);
    expect(pr.ciState, 'failing');
    expect(pr.failingChecks, ['go test', 'lint']);
    expect(pr.reviewDecision, 'changes_requested');
    expect(pr.hasUnresolvedHumanComments, isTrue);
    expect(pr.mergeabilityState, 'conflicting');
    expect(pr.mergeReasons, ['behind_base']);
  });

  test('tolerates a session with no PRs and missing nested objects', () async {
    when(() => apiConsumer.get(EndPoints.sessionPr('s1')))
        .thenAnswer((_) async => jsonResponse({'prs': <dynamic>[]}));
    expect((await dataSource.getSessionPr('s1')).data, isEmpty);

    when(() => apiConsumer.get(EndPoints.sessionPr('s2')))
        .thenAnswer((_) async => jsonResponse({'prs': [{'number': 7}]}));
    final pr = (await dataSource.getSessionPr('s2')).data!.single;
    expect(pr.ciState, isNull);
    expect(pr.failingChecks, isEmpty);
    expect(pr.mergeReasons, isEmpty);
  });

  test('posts a merge for the PR number', () async {
    when(() => apiConsumer.post(any())).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: null),
    );

    await dataSource.merge(184);

    verify(() => apiConsumer.post(EndPoints.prMerge(184))).called(1);
  });
}
