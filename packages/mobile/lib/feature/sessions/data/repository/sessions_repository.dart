import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replica_cache.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

abstract class SessionsRepository {
  Future<Replicated<BoardSnapshot>?> cachedBoard();
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard();
  FutureResult<bool> kill(String id);
  FutureResult<bool> restore(String id);
}

class SessionsRepositoryImp implements SessionsRepository {
  SessionsRepositoryImp(
    this._remoteDataSource,
    this._network,
    this._localDataSource,
    ServerConfigSource config, {
    DateTime Function()? clock,
  }) : _replica = ReplicaCache(config),
       _clock = clock ?? DateTime.now;

  final SessionsRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final SessionsLocalDataSource _localDataSource;
  final ReplicaCache _replica;
  final DateTime Function() _clock;

  @override
  Future<Replicated<BoardSnapshot>?> cachedBoard() => _replica.read<Replicated<BoardPayload>, Replicated<BoardSnapshot>>(
    load: _localDataSource.readBoard,
    parse: (stored) => Replicated(value: BoardSnapshot.fromPayload(stored.value), fetchedAt: stored.fetchedAt),
    forget: _localDataSource.deleteBoard,
  );

  @override
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard() async {
    if (!await _network.isConnected) return Result.failure(ServerFailure.noNetwork());
    final desktopId = _replica.desktopId;
    try {
      final payload = await _remoteDataSource.getBoard();
      final board = _parse(payload);
      await _replica.remember(desktopId, (id) => _localDataSource.writeBoard(id, payload, _clock()));
      return Result.success(GlobalResponse(data: board));
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }

  @override
  FutureResult<bool> kill(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.kill(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> restore(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.restore(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  static BoardSnapshot _parse(BoardPayload payload) {
    try {
      return BoardSnapshot.fromPayload(payload);
    } catch (error, stackTrace) {
      throw MappingFailure(error: error, stacktrace: stackTrace);
    }
  }
}
