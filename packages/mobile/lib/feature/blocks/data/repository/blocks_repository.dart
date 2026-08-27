import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRepository {
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  );
}

class BlocksRepositoryImp implements BlocksRepository {
  BlocksRepositoryImp(this._remoteDataSource, this._network);

  final BlocksRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  ) => _guard(() => _remoteDataSource.getSessionBlocks(sessionId, params));

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
