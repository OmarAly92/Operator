import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_subscription_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';

class _MockRepo extends Mock implements NotificationRepository {}

void main() {
  late _MockRepo repo;
  late List<Uri> launched;
  late List<String> copied;

  PhoneAlertsCubit build({
    required bool Function(Uri uri) launchResult,
    bool ntfyDeepLink = true,
  }) => PhoneAlertsCubit(
    repo,
    launch: (uri) async {
      launched.add(uri);
      return launchResult(uri);
    },
    copy: (text) async => copied.add(text),
    ntfyDeepLink: ntfyDeepLink,
  );

  setUp(() {
    repo = _MockRepo();
    launched = [];
    copied = [];
    when(() => repo.getPhoneAlerts()).thenAnswer(
      (_) async => Result.success(const PhoneAlertStatusModel(enabled: true, claimed: true)),
    );
    when(() => repo.subscribePhoneAlerts()).thenAnswer(
      (_) async => Result.success(const PhoneAlertSubscriptionModel(topic: 'abc', server: 'https://ntfy.sh')),
    );
  });

  test('subscribe opens ntfy on the topic when the deep link works', () async {
    final cubit = build(launchResult: (_) => true);
    await cubit.subscribe();
    expect(launched, [Uri.parse('ntfy://ntfy.sh/abc')]);
    expect(copied, isEmpty);
    expect(cubit.state.status?.claimed, isTrue);
  });

  test('falls back to copying the bare topic and opening ntfy directly when the deep link fails', () async {
    final cubit = build(launchResult: (uri) => uri.scheme != 'ntfy' || uri.host.isEmpty);
    await cubit.subscribe();
    expect(copied, ['abc']);
    expect(launched, [Uri.parse('ntfy://ntfy.sh/abc'), Uri.parse('ntfy://')]);
    expect(cubit.state.copiedTopic, isTrue);
  });

  test('opens the App Store only when the bare ntfy:// launch also fails', () async {
    final cubit = build(launchResult: (uri) => uri.scheme != 'ntfy');
    await cubit.subscribe();
    expect(copied, ['abc']);
    expect(launched, [Uri.parse('ntfy://ntfy.sh/abc'), Uri.parse('ntfy://'), Uri.parse(kNtfyAppStoreUrl)]);
    expect(cubit.state.copiedTopic, isTrue);
  });

  test('without deep-link support it skips the topic link but still opens ntfy', () async {
    final cubit = build(launchResult: (_) => true, ntfyDeepLink: false);
    await cubit.subscribe();
    expect(launched, [Uri.parse('ntfy://')]);
    expect(copied, ['abc']);
  });

  test('sendTest keeps the delivery result', () async {
    when(() => repo.testPhoneAlert()).thenAnswer(
      (_) async => Result.success(const PhoneAlertDeliveryModel(ok: false, error: 'ntfy answered 429')),
    );
    final cubit = build(launchResult: (_) => true);
    await cubit.sendTest();
    expect(cubit.state.lastTest?.error, 'ntfy answered 429');
  });
}
