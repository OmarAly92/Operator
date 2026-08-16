import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

const ServerConfig _oldDaemon = ServerConfig(
  host: '10.0.0.9',
  httpPort: '3011',
  secure: true,
  password: 'old-secret',
);

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

  test('registers a device against the current daemon', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'), options: any(named: 'options')))
        .thenAnswer((_) async => _response(null));

    await dataSource.registerPushDevice(
      const RegisterPushDeviceParams(token: 't-1', platform: 'ios'),
    );

    final captured = verify(
      () => apiConsumer.post(
        EndPoints.pushDevices,
        body: captureAny(named: 'body'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    expect(captured.first, {'token': 't-1', 'platform': 'ios'});
    expect((captured.last as Options?)?.extra?['pairingTarget'], isNull);
  });

  test('unregisters a token from the daemon it was registered with', () async {
    when(() => apiConsumer.delete(any(), options: any(named: 'options')))
        .thenAnswer((_) async => _response(null));

    await dataSource.unregisterPushDevice('t-1', target: _oldDaemon);

    final captured = verify(
      () => apiConsumer.delete(EndPoints.pushDevice('t-1'), options: captureAny(named: 'options')),
    ).captured.single as Options;
    expect(captured.extra?['pairingTarget'], _oldDaemon);
  });
}
