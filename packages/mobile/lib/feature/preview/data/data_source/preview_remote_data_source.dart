import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';

abstract class PreviewRemoteDataSource {
  Future<GlobalResponse<PreviewEntryModel>> getPreview(String sessionId);
}

class PreviewRemoteDataSourceImp implements PreviewRemoteDataSource {
  PreviewRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<PreviewEntryModel>> getPreview(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionPreview(sessionId));
    return GlobalResponse<PreviewEntryModel>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      withDataKey: false,
      fromJsonT: PreviewEntryModel.fromJson,
    );
  }
}
