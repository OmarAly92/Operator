import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

abstract class NotificationRepository {
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  );
  FutureResult<bool> markNotificationRead(String id);
  FutureResult<bool> markAllNotificationsRead();
  FutureResult<bool> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target});
  FutureResult<bool> unregisterPushDevice(String token, {ServerConfig? target});
}

class NotificationRepositoryImp implements NotificationRepository {
  NotificationRepositoryImp(this._remoteDataSource, this._network);

  final NotificationRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  ) => _guard(() => _remoteDataSource.getNotifications(params));

  @override
  FutureResult<bool> markNotificationRead(String id) =>
      _run(() => _remoteDataSource.markNotificationRead(id));

  @override
  FutureResult<bool> markAllNotificationsRead() =>
      _run(_remoteDataSource.markAllNotificationsRead);

  @override
  FutureResult<bool> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target}) =>
      _run(() => _remoteDataSource.registerPushDevice(params, target: target));

  @override
  FutureResult<bool> unregisterPushDevice(String token, {ServerConfig? target}) =>
      _run(() => _remoteDataSource.unregisterPushDevice(token, target: target));

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
