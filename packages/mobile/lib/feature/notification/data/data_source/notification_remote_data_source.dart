import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/mark_notification_read_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

abstract class NotificationRemoteDataSource {
  Future<GlobalResponse<NotificationPageModel>> getNotifications(GetNotificationsParams params);
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
  Future<void> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target});
  Future<void> unregisterPushDevice(String token, {ServerConfig? target});
}

class NotificationRemoteDataSourceImp implements NotificationRemoteDataSource {
  NotificationRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  Options? _target(ServerConfig? target) =>
      target == null ? null : Options(extra: {'pairingTarget': target});

  @override
  Future<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.notifications,
      queryParameters: params.toJson(),
    );
    return GlobalResponse<NotificationPageModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: NotificationPageModel.fromJson,
    );
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _apiConsumer.patch(
      EndPoints.notification(id),
      body: const MarkNotificationReadParams().toJson(),
    );
  }

  @override
  Future<void> markAllNotificationsRead() async {
    await _apiConsumer.post(EndPoints.notificationsReadAll);
  }

  @override
  Future<void> registerPushDevice(
    RegisterPushDeviceParams params, {
    ServerConfig? target,
  }) async {
    await _apiConsumer.post(
      EndPoints.pushDevices,
      body: params.toJson(),
      options: _target(target),
    );
  }

  @override
  Future<void> unregisterPushDevice(String token, {ServerConfig? target}) async {
    await _apiConsumer.delete(EndPoints.pushDevice(token), options: _target(target));
  }
}
