import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

class _MockDataSource extends Mock implements NotificationRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockDataSource dataSource;
  late _MockNetworkStatus network;
  late NotificationRepository repository;

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
    registerFallbackValue(
      const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p'),
    );
  });

  setUp(() {
    dataSource = _MockDataSource();
    network = _MockNetworkStatus();
    repository = NotificationRepositoryImp(dataSource, network);
  });

  test('short-circuits to noNetwork without calling the data source when offline', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getNotifications(const GetNotificationsParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getNotifications(any()));
  });

  test('returns the page when the data source succeeds', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer(
      (_) async => const GlobalResponse(data: NotificationPageModel(unreadCount: 4)),
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    late NotificationPageModel page;
    result.when(onSuccess: (response) => page = response.data!, onFailure: (_) {});
    expect(page.unreadCount, 4);
  });

  test('surfaces a data-source failure as a failure result', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenThrow(
      ServerFailure(error: 'x', message: 'boom', statusCode: 500),
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    expect(result.isFailure, isTrue);
  });

  test('marks one and all read', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.markNotificationRead(any())).thenAnswer((_) async {});
    when(() => dataSource.markAllNotificationsRead()).thenAnswer((_) async {});

    expect((await repository.markNotificationRead('n-1')).isSuccess, isTrue);
    expect((await repository.markAllNotificationsRead()).isSuccess, isTrue);
  });

  test('registers a device', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(
      () => dataSource.registerPushDevice(any(), target: any(named: 'target')),
    ).thenAnswer((_) async {});

    expect(
      (await repository.registerPushDevice(const RegisterPushDeviceParams(token: 't-1'))).isSuccess,
      isTrue,
    );
  });

  test('unregisters a device from a named daemon', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(
      () => dataSource.unregisterPushDevice(any(), target: any(named: 'target')),
    ).thenAnswer((_) async {});

    const target = ServerConfig(host: 'old', httpPort: '3011', secure: false, password: 'p');
    expect((await repository.unregisterPushDevice('t-1', target: target)).isSuccess, isTrue);
    verify(() => dataSource.unregisterPushDevice('t-1', target: target)).called(1);
  });
}
