import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class LocalAlertSink {
  Future<void> init(void Function(String payload) onTap);
  Future<void> show({required int id, required String title, required String body, required String payload});
}

class FlutterLocalAlertSink implements LocalAlertSink {
  FlutterLocalAlertSink([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> init(void Function(String payload) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap(payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) onTap(payload);
  }

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'agent_alerts',
            'Agent alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true, presentList: true),
        ),
      );
}
