import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';

abstract class PullRequestRemoteDataSource {
  Future<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId);
  Future<void> merge(int number);
}

class PullRequestRemoteDataSourceImp implements PullRequestRemoteDataSource {
  PullRequestRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionPr(sessionId));
    return GlobalResponse<List<SessionPrSummaryModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['prs'] as List<dynamic>? ?? const [])
          .map((pr) => SessionPrSummaryModel.fromJson(pr as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> merge(int number) async {
    await _apiConsumer.post(EndPoints.prMerge(number));
  }
}
