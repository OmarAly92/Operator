import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';

part 'pull_request_state.dart';

enum PrFilter { open, merged, all }

class PullRequestCubit extends Cubit<PullRequestState> {
  PullRequestCubit(this._repository) : super(const PullRequestInitialState());

  static const int _batchSize = 6;

  final PullRequestRepository _repository;
  final Map<String, List<SessionPrSummaryModel>> _cache = {};
  final Set<String> _inFlight = {};
  int _revision = 0;

  PrFilter filter = PrFilter.open;

  void setFilter(PrFilter next) {
    if (next == filter) return;
    filter = next;
    _bump();
  }

  /// The loaded detail for one of a session's PRs. A workspace session can own
  /// `api#12` and `web#12` at once, so the PR's [url] decides when known; the
  /// number alone matches only a summary that names no other PR, and only when
  /// it is the one summary with that number.
  SessionPrSummaryModel? summaryFor(String sessionId, int number, {String? url}) {
    final summaries = _cache[sessionId] ?? const <SessionPrSummaryModel>[];
    final key = prUrlKey(url);
    if (key != null) {
      for (final summary in summaries) {
        if (prUrlKey(summary.url) == key || prUrlKey(summary.htmlUrl) == key) return summary;
      }
    }
    final byNumber = summaries.where((summary) {
      if (summary.number != number) return false;
      final other = prUrlKey(summary.url) ?? prUrlKey(summary.htmlUrl);
      return key == null || other == null;
    }).toList();
    return byNumber.length == 1 ? byNumber.single : null;
  }

  Future<void> reload(List<String> sessionIds) => _fetch(sessionIds, force: true);

  Future<void> load(List<String> sessionIds) => _fetch(sessionIds, force: false);

  Future<void> _fetch(List<String> sessionIds, {required bool force}) async {
    final targets = sessionIds
        .where((id) => id.isNotEmpty && !_inFlight.contains(id) && (force || !_cache.containsKey(id)))
        .toSet()
        .toList();
    if (targets.isEmpty) return;
    _inFlight.addAll(targets);

    for (var start = 0; start < targets.length; start += _batchSize) {
      final chunk = targets.skip(start).take(_batchSize).toList();
      await Future.wait(chunk.map(_fetchOne));
      if (isClosed) return;
      _bump();
    }
  }

  Future<void> _fetchOne(String sessionId) async {
    final result = await _repository.getSessionPr(sessionId);
    result.when(
      onSuccess: (response) => _cache[sessionId] = response.data ?? const [],
      onFailure: (_) => _cache.putIfAbsent(sessionId, () => const []),
    );
    _inFlight.remove(sessionId);
  }

  void _bump() => emit(PullRequestReadyState(++_revision));
}
