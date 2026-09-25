import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/mark_notification_read_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';

abstract class NotificationRemoteDataSource {
  Future<Map<String, dynamic>> getNotifications(GetNotificationsParams params);
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
  Future<PhoneAlertStatusModel> getPhoneAlerts();
  Future<PhoneAlertSubscriptionModel> subscribePhoneAlerts();
  Future<PhoneAlertDeliveryModel> testPhoneAlert();
}

class NotificationRemoteDataSourceImp implements NotificationRemoteDataSource {
  NotificationRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<Map<String, dynamic>> getNotifications(GetNotificationsParams params) async {
    final response = await _apiConsumer.get(EndPoints.notifications, queryParameters: params.toJson());
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MappingFailure(error: 'notifications body is ${body.runtimeType}', stacktrace: StackTrace.current);
    }
    return body;
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
  Future<PhoneAlertStatusModel> getPhoneAlerts() async {
    final response = await _apiConsumer.get(EndPoints.phoneAlerts);
    return PhoneAlertStatusModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<PhoneAlertSubscriptionModel> subscribePhoneAlerts() async {
    final response = await _apiConsumer.post(EndPoints.phoneAlertsSubscribe);
    return PhoneAlertSubscriptionModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<PhoneAlertDeliveryModel> testPhoneAlert() async {
    final response = await _apiConsumer.post(EndPoints.phoneAlertsTest);
    return PhoneAlertDeliveryModel.fromJson(response.data as Map<String, dynamic>);
  }
}
