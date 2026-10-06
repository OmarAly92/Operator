import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRemoteDataSource {
  Future<Map<String, dynamic>> getSessionBlocks(String sessionId, GetSessionBlocksParams params);
}

class BlocksRemoteDataSourceImp implements BlocksRemoteDataSource {
  BlocksRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<Map<String, dynamic>> getSessionBlocks(String sessionId, GetSessionBlocksParams params) async {
    final response = await _apiConsumer.get(EndPoints.sessionBlocks(sessionId), queryParameters: params.toJson());
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MappingFailure(error: 'blocks body is ${body.runtimeType}', stacktrace: StackTrace.current);
    }
    return body;
  }
}
