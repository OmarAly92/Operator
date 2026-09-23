import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

void main() {
  late _MockApiConsumer apiConsumer;
  late NotificationRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = NotificationRemoteDataSourceImp(apiConsumer);
  });

  test('lists notifications with the query the daemon expects', () async {
    when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => _response({
        'notifications': [
          {'id': 'n-1'},
        ],
        'unreadCount': 1,
      }),
    );

    final page = (await dataSource.getNotifications(
      const GetNotificationsParams(status: 'all', limit: 50),
    )).data!;

    expect(page.notifications.single.id, 'n-1');
    verify(
      () => apiConsumer.get(
        EndPoints.notifications,
        queryParameters: {'status': 'all', 'limit': 50},
      ),
    ).called(1);
  });

  test('marks one notification read with a PATCH', () async {
    when(() => apiConsumer.patch(any(), body: any(named: 'body')))
        .thenAnswer((_) async => _response(null));

    await dataSource.markNotificationRead('n-1');

    verify(() => apiConsumer.patch(EndPoints.notification('n-1'), body: {'status': 'read'}))
        .called(1);
  });

  test('marks everything read with a POST', () async {
    when(() => apiConsumer.post(any())).thenAnswer((_) async => _response(null));

    await dataSource.markAllNotificationsRead();

    verify(() => apiConsumer.post(EndPoints.notificationsReadAll)).called(1);
  });

  test('fetches phone alert status with a GET', () async {
    when(() => apiConsumer.get(any())).thenAnswer(
      (_) async => _response({
        'enabled': true,
        'claimed': false,
      }),
    );

    final status = await dataSource.getPhoneAlerts();

    expect(status.enabled, isTrue);
    expect(status.claimed, isFalse);
    verify(() => apiConsumer.get(EndPoints.phoneAlerts)).called(1);
  });

  test('subscribes for phone alerts with a POST', () async {
    when(() => apiConsumer.post(any())).thenAnswer(
      (_) async => _response({'topic': 'abc', 'server': 'https://ntfy.sh'}),
    );

    final subscription = await dataSource.subscribePhoneAlerts();

    expect(subscription.topic, 'abc');
    expect(subscription.server, 'https://ntfy.sh');
    verify(() => apiConsumer.post(EndPoints.phoneAlertsSubscribe)).called(1);
  });

  test('sends a test phone alert with a POST', () async {
    when(() => apiConsumer.post(any())).thenAnswer(
      (_) async => _response({'at': '2026-09-23T10:00:00Z', 'ok': true}),
    );

    final delivery = await dataSource.testPhoneAlert();

    expect(delivery.ok, isTrue);
    verify(() => apiConsumer.post(EndPoints.phoneAlertsTest)).called(1);
  });
}
