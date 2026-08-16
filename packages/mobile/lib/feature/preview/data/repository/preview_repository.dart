import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

abstract class PreviewRepository {
  FutureResult<PreviewModel?> getPreview(String sessionId, {String? previewUrl});
}

class PreviewRepositoryImp implements PreviewRepository {
  PreviewRepositoryImp(this._remoteDataSource, this._network, this._configStore);

  final PreviewRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final ServerConfigStore _configStore;

  @override
  FutureResult<PreviewModel?> getPreview(String sessionId, {String? previewUrl}) async {
    if (!await _network.isConnected) return Result.failure(ServerFailure.noNetwork());
    try {
      final response = await _remoteDataSource.getPreview(sessionId);
      final entry = response.data?.entry ?? '';
      final config = _configStore.current;

      if (entry.isNotEmpty && config != null) {
        return Result.success(
          PreviewModel(
            entry: entry,
            url: '${config.httpBase}${EndPoints.sessionPreviewFile(sessionId, entry)}',
            authenticated: true,
          ),
        );
      }

      final external = mobileReachablePreviewUrl(previewUrl, config?.host ?? '');
      if (external == null) return Result.success(null);
      return Result.success(
        PreviewModel(entry: external.host, url: external.toString(), authenticated: false),
      );
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
