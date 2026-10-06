import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

class _MockDataSource extends Mock implements NotificationRemoteDataSource {}

class _MockLocal extends Mock implements NotificationLocalDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = const ServerConfig(
    host: '10.0.0.5',
    httpPort: '3011',
    secure: false,
    password: 'pw',
    desktopId: 'a',
  );

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  late _MockDataSource dataSource;
  late _MockLocal local;
  late _MockNetworkStatus network;
  late _Config config;
  late NotificationRepository repository;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(DateTime.utc(2026));
  });

  setUp(() {
    dataSource = _MockDataSource();
    local = _MockLocal();
    network = _MockNetworkStatus();
    config = _Config();
    repository = NotificationRepositoryImp(dataSource, network, local, config, clock: () => at);
    when(() => local.writeFirstPage(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteFirstPage(any())).thenAnswer((_) async {});
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
      (_) async => {'notifications': <dynamic>[], 'unreadCount': 4},
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    late NotificationPageModel page;
    result.when(onSuccess: (response) => page = response.data!, onFailure: (_) {});
    expect(page.unreadCount, 4);
  });

  test('stores the first page of all notifications under the active desktop', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    final body = {'notifications': <dynamic>[], 'unreadCount': 2};
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async => body);

    await repository.getNotifications(const GetNotificationsParams(status: 'all', limit: 50));

    verify(() => local.writeFirstPage('a', body, at)).called(1);
  });

  test('neither a later page nor the unread probe is stored', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async => {'notifications': <dynamic>[]});

    await repository.getNotifications(const GetNotificationsParams(status: 'all', cursor: 'c-2'));
    await repository.getNotifications(const GetNotificationsParams(status: 'unread', limit: 1));

    verifyNever(() => local.writeFirstPage(any(), any(), any()));
  });

  test('drops the write when the desktop changed while the fetch was in flight', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer((_) async {
      config.current = null;
      return {'notifications': <dynamic>[]};
    });

    await repository.getNotifications(const GetNotificationsParams(status: 'all'));

    verifyNever(() => local.writeFirstPage(any(), any(), any()));
  });

  test('cachedFirstPage parses the replica through NotificationPageModel', () async {
    when(() => local.readFirstPage('a')).thenAnswer(
      (_) async => Replicated(value: {'notifications': [{'id': 'n-1'}], 'unreadCount': 1}, fetchedAt: at),
    );

    final cached = await repository.cachedFirstPage();

    expect(cached!.value.notifications.single.id, 'n-1');
    expect(cached.value.unreadCount, 1);
  });

  test('a first page that no longer parses is deleted and read as a miss', () async {
    when(() => local.readFirstPage('a')).thenAnswer(
      (_) async => Replicated(value: {'notifications': 'nope'}, fetchedAt: at),
    );

    expect(await repository.cachedFirstPage(), isNull);
    verify(() => local.deleteFirstPage('a')).called(1);
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

  test('fetches phone alert status', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getPhoneAlerts()).thenAnswer(
      (_) async => const PhoneAlertStatusModel(enabled: true, claimed: true),
    );

    final result = await repository.getPhoneAlerts();

    late PhoneAlertStatusModel status;
    result.when(onSuccess: (value) => status = value, onFailure: (_) {});
    expect(status.claimed, isTrue);
  });

  test('subscribes for phone alerts', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.subscribePhoneAlerts()).thenAnswer(
      (_) async => const PhoneAlertSubscriptionModel(topic: 'abc', server: 'https://ntfy.sh'),
    );

    final result = await repository.subscribePhoneAlerts();

    late PhoneAlertSubscriptionModel subscription;
    result.when(onSuccess: (value) => subscription = value, onFailure: (_) {});
    expect(subscription.topic, 'abc');
  });

  test('sends a test phone alert', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.testPhoneAlert()).thenAnswer(
      (_) async => const PhoneAlertDeliveryModel(ok: false, error: 'ntfy answered 429'),
    );

    final result = await repository.testPhoneAlert();

    late PhoneAlertDeliveryModel delivery;
    result.when(onSuccess: (value) => delivery = value, onFailure: (_) {});
    expect(delivery.error, 'ntfy answered 429');
  });
}
