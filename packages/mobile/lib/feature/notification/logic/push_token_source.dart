import 'package:operator_mobile/feature/notification/logic/push_status.dart';

abstract class PushTokenSource {
  bool get supported;

  String get platform;

  Future<PushStatus> permissionStatus();

  Future<bool> requestPermission();

  Future<String?> getToken();

  Future<String?> deviceName();
}

/// The source a build without Firebase configuration ships with: it can answer
/// every question honestly and mints nothing.
class UnconfiguredPushTokenSource implements PushTokenSource {
  const UnconfiguredPushTokenSource();

  @override
  bool get supported => false;

  @override
  String get platform => '';

  @override
  Future<PushStatus> permissionStatus() async => const PushStatus(
    supported: false,
    granted: false,
    canAskAgain: false,
    registered: false,
  );

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<String?> deviceName() async => null;
}
