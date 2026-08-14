import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_conversation_title_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/steer_conversation_params.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';

const int kChatPageSize = 200;

const Duration _attachmentTimeout = Duration(seconds: 60);

abstract class ChatRemoteDataSource {
  Future<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  });
  Future<void> sendMessage(String sessionId, SendMessageParams params);
  Future<void> steer(String sessionId, SteerConversationParams params);
  Future<void> interrupt(String sessionId);
  Future<void> compact(String sessionId);
  Future<void> resolveApproval(String sessionId, ResolveApprovalParams params);
  Future<void> resolveInput(String sessionId, ResolveInputParams params);
  Future<int> rollbackTurn(String sessionId, RollbackTurnParams params);
  Future<void> setTitle(String sessionId, SetConversationTitleParams params);
  Future<GlobalResponse<List<ChatModelModel>>> getModels(String sessionId);
  Future<void> setSettings(String sessionId, TurnSettingsModel settings);
  Future<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(
    String sessionId,
  );
  Future<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  );
  Future<GlobalResponse<List<ChatSkillModel>>> getSkills(String sessionId);
  Future<void> reloadMcpServers(String sessionId);
  Future<List<String>> stageAttachments(
    String sessionId,
    StageAttachmentsParams params,
  );
  Future<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(
    String sessionId,
  );
  Future<void> resumeAgent(String sessionId);
}

class ChatRemoteDataSourceImp implements ChatRemoteDataSource {
  final ApiConsumer _apiConsumer;

  ChatRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  }) async {
    final response = await _apiConsumer.get(
      EndPoints.sessionConversation(sessionId),
      queryParameters: {
        'limit': kChatPageSize,
        'beforeSequence': ?beforeSequence,
      },
    );
    return GlobalResponse<ConversationSnapshotModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: ConversationSnapshotModel.fromJson,
    );
  }

  @override
  Future<void> sendMessage(String sessionId, SendMessageParams params) async {
    await _apiConsumer.post(
      EndPoints.conversationMessages(sessionId),
      body: params.toJson(),
    );
  }

  @override
  Future<void> steer(String sessionId, SteerConversationParams params) async {
    await _apiConsumer.post(
      EndPoints.conversationSteer(sessionId),
      body: params.toJson(),
    );
  }

  @override
  Future<void> interrupt(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationInterrupt(sessionId));
  }

  @override
  Future<void> compact(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationCompact(sessionId));
  }

  @override
  Future<void> resolveApproval(
    String sessionId,
    ResolveApprovalParams params,
  ) async {
    await _apiConsumer.post(
      EndPoints.conversationApprovalResolve(sessionId, params.requestId),
      body: params.toJson(),
    );
  }

  @override
  Future<void> resolveInput(String sessionId, ResolveInputParams params) async {
    await _apiConsumer.post(
      EndPoints.conversationInputResolve(sessionId, params.requestId),
      body: params.toJson(),
    );
  }

  @override
  Future<int> rollbackTurn(String sessionId, RollbackTurnParams params) async {
    final response = await _apiConsumer.post(
      EndPoints.conversationTurnRollback(sessionId, params.turnId),
    );
    final body = response.data;
    return body is Map<String, dynamic>
        ? (body['turnsDiscarded'] as num?)?.toInt() ?? 0
        : 0;
  }

  @override
  Future<void> setTitle(
    String sessionId,
    SetConversationTitleParams params,
  ) async {
    await _apiConsumer.put(
      EndPoints.conversationTitle(sessionId),
      body: params.toJson(),
    );
  }

  @override
  Future<GlobalResponse<List<ChatModelModel>>> getModels(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.conversationModels(sessionId),
    );
    return GlobalResponse<List<ChatModelModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatModelModel.fromJson)
          .toList(),
    );
  }

  @override
  Future<void> setSettings(String sessionId, TurnSettingsModel settings) async {
    await _apiConsumer.patch(
      EndPoints.conversationSettings(sessionId),
      body: settings.toJson(),
    );
  }

  @override
  Future<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.conversationConfigOptions(sessionId),
    );
    return _configOptions(response.data as Map<String, dynamic>);
  }

  @override
  Future<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  ) async {
    final response = await _apiConsumer.patch(
      EndPoints.conversationConfigOption(sessionId, params.optionId),
      body: params.toJson(),
    );
    return _configOptions(response.data as Map<String, dynamic>);
  }

  @override
  Future<GlobalResponse<List<ChatSkillModel>>> getSkills(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.conversationSkills(sessionId),
    );
    return GlobalResponse<List<ChatSkillModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['skills'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatSkillModel.fromJson)
          .toList(),
    );
  }

  @override
  Future<void> reloadMcpServers(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationMcpReload(sessionId));
  }

  @override
  Future<List<String>> stageAttachments(
    String sessionId,
    StageAttachmentsParams params,
  ) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionAttachments(sessionId),
      body: params.toJson(),
      options: Options(
        sendTimeout: _attachmentTimeout,
        receiveTimeout: _attachmentTimeout,
      ),
    );
    final body = response.data;
    return body is Map<String, dynamic>
        ? (body['paths'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList()
        : const [];
  }

  @override
  Future<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.sessionWorkspaceFiles(sessionId),
    );
    return GlobalResponse<WorkspacePathsModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: WorkspacePathsModel.fromJson,
    );
  }

  @override
  Future<void> resumeAgent(String sessionId) async {
    await _apiConsumer.post(EndPoints.sessionResumeAgent(sessionId));
  }

  GlobalResponse<List<ChatConfigOptionModel>> _configOptions(
    Map<String, dynamic> body,
  ) => GlobalResponse<List<ChatConfigOptionModel>>.fromJson(
    body,
    withDataKey: false,
    fromJsonT: (json) => (json['options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatConfigOptionModel.fromJson)
        .toList(),
  );
}
