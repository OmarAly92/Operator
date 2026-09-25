import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replica_cache.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRepository {
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  );
  Future<List<BlockEventModel>> cachedHistory(String sessionId);
  Future<void> rememberLive(String sessionId, Map<String, dynamic> row);
}

class BlocksRepositoryImp implements BlocksRepository {
  BlocksRepositoryImp(this._remoteDataSource, this._network, this._localDataSource, ServerConfigSource config)
    : _replica = ReplicaCache(config);

  final BlocksRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final BlocksLocalDataSource _localDataSource;
  final ReplicaCache _replica;

  @override
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  ) => _guard(() async {
    final desktopId = _replica.desktopId;
    final body = await _remoteDataSource.getSessionBlocks(sessionId, params);
    final events = _parse(body);
    if ((params.agentId ?? '').isEmpty && params.beforeSeq == null) await _remember(desktopId, sessionId, _rows(body));
    return events;
  });

  @override
  Future<List<BlockEventModel>> cachedHistory(String sessionId) async =>
      await _replica.read<List<Map<String, dynamic>>, List<BlockEventModel>>(
        load: (desktopId) => _localDataSource.readHistory(desktopId, sessionId),
        parse: (rows) => rows.map(BlockEventModel.fromJson).toList(),
        forget: (desktopId) => _localDataSource.deleteHistory(desktopId, sessionId),
      ) ??
      const [];

  @override
  Future<void> rememberLive(String sessionId, Map<String, dynamic> row) =>
      _remember(_replica.desktopId, sessionId, [row]);

  static List<BlockEventModel> _parse(Map<String, dynamic> body) {
    try {
      return BlockEventModel.listFromJson(body);
    } catch (error, stackTrace) {
      throw MappingFailure(error: error, stacktrace: stackTrace);
    }
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> body) {
    final blocks = body['blocks'];
    return blocks is List ? blocks.whereType<Map<String, dynamic>>().toList() : const [];
  }

  static bool _replicable(Map<String, dynamic> row) {
    final agent = row['agentId'];
    return row['seq'] is num && (agent is! String || agent.isEmpty) && row['kind'] != 'task_update';
  }

  Future<void> _remember(String? desktopId, String sessionId, List<Map<String, dynamic>> rows) async {
    final kept = rows.where(_replicable).toList();
    if (kept.isEmpty) return;
    await _replica.remember(desktopId, (id) => _localDataSource.writeHistory(id, sessionId, kept));
  }

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
}
