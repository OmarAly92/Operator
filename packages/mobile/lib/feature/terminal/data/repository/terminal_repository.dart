import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

abstract class TerminalRepository {
  FutureResult<GlobalResponse<ShellTerminalModel>> openSessionShell(OpenSessionShellParams params);
  FutureResult<bool> closeShellTerminal(String handleId);
  FutureResult<bool> sendSessionMessage(String sessionId, SendSessionMessageParams params);
}

class TerminalRepositoryImp implements TerminalRepository {
  TerminalRepositoryImp(this._remoteDataSource, this._network);

  final TerminalRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<ShellTerminalModel>> openSessionShell(
    OpenSessionShellParams params,
  ) => _guard(() async {
    final existing = await _existingShell(params.sessionId);
    if (existing != null) return GlobalResponse(data: existing);
    return _remoteDataSource.openShellTerminal(params);
  });

  /// A listing failure must not block opening a shell — the reuse is an
  /// optimisation, not a precondition.
  Future<ShellTerminalModel?> _existingShell(String sessionId) async {
    try {
      final listed = await _remoteDataSource.getShellTerminals();
      for (final shell in listed.data ?? const <ShellTerminalModel>[]) {
        if (shell.sessionId == sessionId) return shell;
      }
    } on Failure catch (_) {
      return null;
    }
    return null;
  }

  @override
  FutureResult<bool> closeShellTerminal(String handleId) =>
      _run(() => _remoteDataSource.closeShellTerminal(handleId));

  @override
  FutureResult<bool> sendSessionMessage(String sessionId, SendSessionMessageParams params) =>
      _run(() => _remoteDataSource.sendSessionMessage(sessionId, params));

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
