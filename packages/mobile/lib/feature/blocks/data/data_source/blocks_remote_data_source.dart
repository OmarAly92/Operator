import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRemoteDataSource {
  Future<List<BlockEventModel>> getSessionBlocks(String sessionId, GetSessionBlocksParams params);
}

class BlocksRemoteDataSourceImp implements BlocksRemoteDataSource {
  final ApiConsumer _apiConsumer;

  BlocksRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.sessionBlocks(sessionId),
      queryParameters: params.toJson(),
    );
    final parsed = GlobalResponse<List<BlockEventModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: BlockEventModel.listFromJson,
    );
    return parsed.data ?? const [];
  }
}
