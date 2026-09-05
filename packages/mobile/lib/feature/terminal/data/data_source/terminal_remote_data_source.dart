import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

abstract class TerminalRemoteDataSource {
  Future<GlobalResponse<List<ShellTerminalModel>>> getShellTerminals();
  Future<GlobalResponse<ShellTerminalModel>> openShellTerminal(OpenSessionShellParams params);
  Future<void> closeShellTerminal(String handleId);
  Future<void> sendSessionMessage(String sessionId, SendSessionMessageParams params);
  Future<GlobalResponse<String?>> getDraft(String sessionId);
}

class TerminalRemoteDataSourceImp implements TerminalRemoteDataSource {
  final ApiConsumer _apiConsumer;

  TerminalRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<GlobalResponse<List<ShellTerminalModel>>> getShellTerminals() async {
    final response = await _apiConsumer.get(EndPoints.shellTerminals);
    return GlobalResponse<List<ShellTerminalModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: ShellTerminalModel.listFromJson,
    );
  }

  @override
  Future<GlobalResponse<ShellTerminalModel>> openShellTerminal(
    OpenSessionShellParams params,
  ) async {
    final response = await _apiConsumer.post(EndPoints.shellTerminals, body: params.toJson());
    return GlobalResponse<ShellTerminalModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) =>
          ShellTerminalModel.fromJson(json['shellTerminal'] as Map<String, dynamic>? ?? const {}),
    );
  }

  @override
  Future<void> closeShellTerminal(String handleId) async {
    await _apiConsumer.delete(EndPoints.shellTerminal(handleId));
  }

  @override
  Future<void> sendSessionMessage(String sessionId, SendSessionMessageParams params) async {
    await _apiConsumer.post(EndPoints.sessionSend(sessionId), body: params.toJson());
  }

  @override
  Future<GlobalResponse<String?>> getDraft(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionDraft(sessionId));
    return GlobalResponse<String?>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => json['draft'] as String?,
    );
  }
}
