import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> platform = <MethodCall>[];
  final List<MethodCall> notification = <MethodCall>[];

  setUp(() {
    platform.clear();
    notification.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        notification.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
  });

  group('Haptics', () {
    test('tap is a light impact on the framework channel', () async {
      Haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(platform.single.method, 'HapticFeedback.vibrate');
      expect(platform.single.arguments, 'HapticFeedbackType.lightImpact');
      expect(notification, isEmpty);
    });

    test('select is a selection click on the framework channel', () async {
      Haptics.select();
      await Future<void>.delayed(Duration.zero);
      expect(platform.single.arguments, 'HapticFeedbackType.selectionClick');
      expect(notification, isEmpty);
    });

    test('success, warning and error go to the notification channel by name', () async {
      Haptics.success();
      Haptics.warning();
      Haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(notification.map((call) => call.method), ['notify', 'notify', 'notify']);
      expect(
        notification.map((call) => call.arguments),
        ['success', 'warning', 'error'],
      );
      expect(platform, isEmpty);
    });

    test('a channel that throws does not throw into the caller', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(Haptics.channelName),
        (call) async => throw PlatformException(code: 'unavailable'),
      );
      expect(Haptics.error, returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
