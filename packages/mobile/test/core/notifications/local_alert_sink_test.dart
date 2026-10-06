import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _MockAndroid extends Mock implements AndroidFlutterLocalNotificationsPlugin {}

class _MockIos extends Mock implements IOSFlutterLocalNotificationsPlugin {}

NotificationsEnabledOptions _ios({required bool enabled}) => NotificationsEnabledOptions(
  isEnabled: enabled,
  isSoundEnabled: enabled,
  isAlertEnabled: enabled,
  isBadgeEnabled: enabled,
  isProvisionalEnabled: false,
  isCriticalEnabled: false,
  isProvidesAppNotificationSettingsEnabled: false,
);

void main() {
  late _MockPlugin plugin;
  late _MockAndroid android;
  late List<String> taps;

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
  });

  setUp(() {
    plugin = _MockPlugin();
    android = _MockAndroid();
    taps = [];
    when(
      () => plugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer((_) async => const NotificationAppLaunchDetails(false));
    when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()).thenReturn(android);
    when(() => android.requestNotificationsPermission()).thenAnswer((_) async => true);
    when(() => android.areNotificationsEnabled()).thenAnswer((_) async => true);
  });

  DidReceiveNotificationResponseCallback capturedTapHandler() =>
      verify(
            () => plugin.initialize(
              settings: any(named: 'settings'),
              onDidReceiveNotificationResponse: captureAny(named: 'onDidReceiveNotificationResponse'),
            ),
          ).captured.single
          as DidReceiveNotificationResponseCallback;

  test('forwards a tapped notification payload to the handler', () async {
    await FlutterLocalAlertSink(plugin).init(taps.add);

    final handler = capturedTapHandler();
    handler(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'operator://session/s1',
      ),
    );
    handler(const NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification));

    expect(taps, ['operator://session/s1']);
  });

  test('forwards the payload of the notification that launched the app', () async {
    when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
      (_) async => const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'operator://session/s2',
        ),
      ),
    );

    await FlutterLocalAlertSink(plugin).init(taps.add);

    expect(taps, ['operator://session/s2']);
  });

  test('ignores launch details when a notification did not launch the app', () async {
    when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
      (_) async => const NotificationAppLaunchDetails(
        false,
        notificationResponse: NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'operator://session/s2',
        ),
      ),
    );

    await FlutterLocalAlertSink(plugin).init(taps.add);

    expect(taps, isEmpty);
  });

  test('reports whether alerts can show from the Android permission', () async {
    expect(await FlutterLocalAlertSink(plugin).init(taps.add), isTrue);
    verify(() => android.requestNotificationsPermission()).called(1);

    when(() => android.requestNotificationsPermission()).thenAnswer((_) async => false);
    when(() => android.areNotificationsEnabled()).thenAnswer((_) async => false);
    expect(await FlutterLocalAlertSink(plugin).init(taps.add), isFalse);
  });

  test('reports whether alerts can show from the iOS authorization', () async {
    final ios = _MockIos();
    when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()).thenReturn(null);
    when(() => plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()).thenReturn(ios);
    when(() => ios.checkPermissions()).thenAnswer((_) async => _ios(enabled: true));
    expect(await FlutterLocalAlertSink(plugin).init(taps.add), isTrue);

    when(() => ios.checkPermissions()).thenAnswer((_) async => _ios(enabled: false));
    expect(await FlutterLocalAlertSink(plugin).init(taps.add), isFalse);
  });
}
