import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

class _MockDataSource extends Mock implements NotificationRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockDataSource dataSource;
  late _MockNetworkStatus network;
  late NotificationRepository repository;

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
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
