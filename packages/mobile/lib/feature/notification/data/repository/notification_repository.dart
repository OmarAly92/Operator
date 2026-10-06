import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replica_cache.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';

abstract class NotificationRepository {
  Future<Replicated<NotificationPageModel>?> cachedFirstPage();
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  );
  FutureResult<bool> markNotificationRead(String id);
  FutureResult<bool> markAllNotificationsRead();
  FutureResult<PhoneAlertStatusModel> getPhoneAlerts();
  FutureResult<PhoneAlertSubscriptionModel> subscribePhoneAlerts();
  FutureResult<PhoneAlertDeliveryModel> testPhoneAlert();
}

class NotificationRepositoryImp implements NotificationRepository {
  NotificationRepositoryImp(
    this._remoteDataSource,
    this._network,
    this._localDataSource,
    ServerConfigSource config, {
    DateTime Function()? clock,
  }) : _replica = ReplicaCache(config),
       _clock = clock ?? DateTime.now;

  final NotificationRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final NotificationLocalDataSource _localDataSource;
  final ReplicaCache _replica;
  final DateTime Function() _clock;

  @override
  Future<Replicated<NotificationPageModel>?> cachedFirstPage() =>
      _replica.read<Replicated<Map<String, dynamic>>, Replicated<NotificationPageModel>>(
        load: _localDataSource.readFirstPage,
        parse: (stored) =>
            Replicated(value: NotificationPageModel.fromJson(stored.value), fetchedAt: stored.fetchedAt),
        forget: _localDataSource.deleteFirstPage,
      );

  @override
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  ) => _guard(() async {
    final desktopId = _replica.desktopId;
    final body = await _remoteDataSource.getNotifications(params);
    final page = GlobalResponse<NotificationPageModel>.fromJson(
      body,
      withDataKey: false,
      fromJsonT: NotificationPageModel.fromJson,
    );
    if (params.cursor == null && params.status == 'all') {
      await _replica.remember(desktopId, (id) => _localDataSource.writeFirstPage(id, body, _clock()));
    }
    return page;
  });

  @override
  FutureResult<bool> markNotificationRead(String id) =>
      _run(() => _remoteDataSource.markNotificationRead(id));

  @override
  FutureResult<bool> markAllNotificationsRead() =>
      _run(_remoteDataSource.markAllNotificationsRead);

  @override
  FutureResult<PhoneAlertStatusModel> getPhoneAlerts() =>
      _guard(_remoteDataSource.getPhoneAlerts);

  @override
  FutureResult<PhoneAlertSubscriptionModel> subscribePhoneAlerts() =>
      _guard(_remoteDataSource.subscribePhoneAlerts);

  @override
  FutureResult<PhoneAlertDeliveryModel> testPhoneAlert() =>
      _guard(_remoteDataSource.testPhoneAlert);

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
