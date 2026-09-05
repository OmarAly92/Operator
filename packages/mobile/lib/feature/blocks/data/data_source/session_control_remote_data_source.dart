import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';

abstract class SessionControlRemoteDataSource {
  Future<GlobalResponse<SessionCommandResultModel>> sendCommand(
    String sessionId,
    SessionCommandParams params,
  );
  Future<GlobalResponse<SessionCommandResultModel>> decide(
    String sessionId,
    SessionDecisionParams params,
  );
  Future<GlobalResponse<SessionCommandResultModel>> answer(
    String sessionId,
    SessionAnswerParams params,
  );
  Future<GlobalResponse<List<PendingInteractionModel>>> getInteractions(String sessionId);
}

class SessionControlRemoteDataSourceImp implements SessionControlRemoteDataSource {
  final ApiConsumer _apiConsumer;

  SessionControlRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<GlobalResponse<SessionCommandResultModel>> sendCommand(
    String sessionId,
    SessionCommandParams params,
  ) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionCommand(sessionId),
      body: params.toJson(),
    );
    return GlobalResponse<SessionCommandResultModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: SessionCommandResultModel.fromJson,
    );
  }

  @override
  Future<GlobalResponse<SessionCommandResultModel>> decide(
    String sessionId,
    SessionDecisionParams params,
  ) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionDecision(sessionId),
      body: params.toJson(),
    );
    return GlobalResponse<SessionCommandResultModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: SessionCommandResultModel.fromJson,
    );
  }

  @override
  Future<GlobalResponse<SessionCommandResultModel>> answer(
    String sessionId,
    SessionAnswerParams params,
  ) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionAnswer(sessionId),
      body: params.toJson(),
    );
    return GlobalResponse<SessionCommandResultModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: SessionCommandResultModel.fromJson,
    );
  }

  @override
  Future<GlobalResponse<List<PendingInteractionModel>>> getInteractions(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionInteractions(sessionId));
    return GlobalResponse<List<PendingInteractionModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: PendingInteractionModel.listFromJson,
    );
  }
}
