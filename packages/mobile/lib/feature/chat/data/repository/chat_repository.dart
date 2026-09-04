import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
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

abstract class ChatRepository {
  FutureResult<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  });
  FutureResult<bool> sendMessage(String sessionId, SendMessageParams params);
  FutureResult<bool> steer(String sessionId, SteerConversationParams params);
  FutureResult<bool> interrupt(String sessionId);
  FutureResult<bool> compact(String sessionId);
  FutureResult<bool> resolveApproval(
    String sessionId,
    ResolveApprovalParams params,
  );
  FutureResult<bool> resolveInput(String sessionId, ResolveInputParams params);
  FutureResult<int> rollbackTurn(String sessionId, RollbackTurnParams params);
  FutureResult<bool> setTitle(
    String sessionId,
    SetConversationTitleParams params,
  );
  FutureResult<GlobalResponse<List<ChatModelModel>>> getModels(
    String sessionId,
  );
  FutureResult<bool> setSettings(String sessionId, TurnSettingsModel settings);
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(
    String sessionId,
  );
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  );
  FutureResult<GlobalResponse<List<ChatSkillModel>>> getSkills(
    String sessionId,
  );
  FutureResult<bool> reloadMcpServers(String sessionId);
  FutureResult<List<String>> stageAttachments(
    String sessionId,
    StageAttachmentsParams params,
  );
  FutureResult<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(
    String sessionId,
  );
  FutureResult<bool> resumeAgent(String sessionId);
}

class ChatRepositoryImp implements ChatRepository {
  ChatRepositoryImp(
    this._remoteDataSource,
    this._network,
  );

  final ChatRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  }) => _guard(
    () => _remoteDataSource.getConversationPage(
      sessionId,
      beforeSequence: beforeSequence,
    ),
  );

  @override
  FutureResult<bool> sendMessage(String sessionId, SendMessageParams params) =>
      _run(() => _remoteDataSource.sendMessage(sessionId, params));

  @override
  FutureResult<bool> steer(String sessionId, SteerConversationParams params) =>
      _run(() => _remoteDataSource.steer(sessionId, params));

  @override
  FutureResult<bool> interrupt(String sessionId) =>
      _run(() => _remoteDataSource.interrupt(sessionId));

  @override
  FutureResult<bool> compact(String sessionId) =>
      _run(() => _remoteDataSource.compact(sessionId));

  @override
  FutureResult<bool> resolveApproval(
    String sessionId,
    ResolveApprovalParams params,
  ) => _run(() => _remoteDataSource.resolveApproval(sessionId, params));

  @override
  FutureResult<bool> resolveInput(
    String sessionId,
    ResolveInputParams params,
  ) => _run(() => _remoteDataSource.resolveInput(sessionId, params));

  @override
  FutureResult<int> rollbackTurn(String sessionId, RollbackTurnParams params) =>
      _guard(() => _remoteDataSource.rollbackTurn(sessionId, params));

  @override
  FutureResult<bool> setTitle(
    String sessionId,
    SetConversationTitleParams params,
  ) => _run(() => _remoteDataSource.setTitle(sessionId, params));

  @override
  FutureResult<GlobalResponse<List<ChatModelModel>>> getModels(
    String sessionId,
  ) => _guard(() => _remoteDataSource.getModels(sessionId));

  @override
  FutureResult<bool> setSettings(
    String sessionId,
    TurnSettingsModel settings,
  ) => _run(() => _remoteDataSource.setSettings(sessionId, settings));

  @override
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(
    String sessionId,
  ) => _guard(() => _remoteDataSource.getConfigOptions(sessionId));

  @override
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  ) => _guard(() => _remoteDataSource.setConfigOption(sessionId, params));

  @override
  FutureResult<GlobalResponse<List<ChatSkillModel>>> getSkills(
    String sessionId,
  ) => _guard(() => _remoteDataSource.getSkills(sessionId));

  @override
  FutureResult<bool> reloadMcpServers(String sessionId) =>
      _run(() => _remoteDataSource.reloadMcpServers(sessionId));

  @override
  FutureResult<List<String>> stageAttachments(
    String sessionId,
    StageAttachmentsParams params,
  ) => _guard(() => _remoteDataSource.stageAttachments(sessionId, params));

  @override
  FutureResult<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(
    String sessionId,
  ) => _guard(() => _remoteDataSource.getWorkspacePaths(sessionId));

  @override
  FutureResult<bool> resumeAgent(String sessionId) =>
      _run(() => _remoteDataSource.resumeAgent(sessionId));

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  FutureResult<bool> _run(Future<void> Function() action) => _guard(() async {
    await action();
    return true;
  });
}
