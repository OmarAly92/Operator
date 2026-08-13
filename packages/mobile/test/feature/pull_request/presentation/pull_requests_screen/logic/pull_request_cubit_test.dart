import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

void main() {
  late _MockPullRequestRepository repository;

  SessionPrSummaryModel summary(int number, String title) =>
      SessionPrSummaryModel(number: number, title: title);

  void stub(String sessionId, List<SessionPrSummaryModel> prs) {
    when(() => repository.getSessionPr(sessionId))
        .thenAnswer((_) async => Result.success(GlobalResponse(data: prs)));
  }

  setUp(() {
    repository = _MockPullRequestRepository();
  });

  test('exposes a loaded summary by session and number', () async {
    stub('s1', [summary(184, 'Fix auth')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);

    expect(cubit.summaryFor('s1', 184)?.title, 'Fix auth');
    expect(cubit.summaryFor('s1', 999), isNull);
    expect(cubit.summaryFor('other', 184), isNull);
    await cubit.close();
  });

  test('fetches each session once across repeated loads', () async {
    stub('s1', [summary(1, 'one')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.load(['s1']);
    await cubit.load(['s1']);

    verify(() => repository.getSessionPr('s1')).called(1);
    await cubit.close();
  });

  test('reload re-fetches everything', () async {
    stub('s1', [summary(1, 'one')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.reload(['s1']);

    verify(() => repository.getSessionPr('s1')).called(2);
    await cubit.close();
  });

  test('only fetches sessions it has never seen', () async {
    stub('s1', [summary(1, 'one')]);
    stub('s2', [summary(2, 'two')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.load(['s1', 's2']);

    verify(() => repository.getSessionPr('s1')).called(1);
    verify(() => repository.getSessionPr('s2')).called(1);
    await cubit.close();
  });

  test('keeps the detail already on screen when a refresh fails', () async {
    stub('s1', [summary(184, 'Fix auth')]);
    final cubit = PullRequestCubit(repository);
    await cubit.load(['s1']);

    when(() => repository.getSessionPr('s1'))
        .thenAnswer((_) async => Result.failure(ServerFailure(error: 'boom', message: 'boom')));
    await cubit.reload(['s1']);

    expect(cubit.summaryFor('s1', 184)?.title, 'Fix auth');
    await cubit.close();
  });

  blocTest<PullRequestCubit, PullRequestState>(
    'emits a distinct state per loaded batch so the list repaints',
    build: () {
      stub('s1', [summary(1, 'one')]);
      return PullRequestCubit(repository);
    },
    act: (cubit) => cubit.load(['s1']),
    expect: () => [isA<PullRequestReadyState>().having((s) => s.revision, 'revision', 1)],
  );

  blocTest<PullRequestCubit, PullRequestState>(
    'emits when the filter changes',
    build: () => PullRequestCubit(repository),
    act: (cubit) => cubit.setFilter(PrFilter.merged),
    expect: () => [isA<PullRequestReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.filter, PrFilter.merged),
  );
}
