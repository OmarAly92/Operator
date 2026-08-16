import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';

class _FakeSource implements AppLinkSource {
  Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get linkStream => controller.stream;
}

class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);
}

void main() {
  late _FakeSource source;
  late _RecordingObserver observer;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    source = _FakeSource();
    observer = _RecordingObserver();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        initialRoute: RoutesStrings.sessions,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cold-start link lands on its screen', (tester) async {
    source.initial = Uri.parse('aomobile://session/abc');
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);

    await service.start();
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.session);
  });

  testWidgets('a warm link arriving later lands too', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();

    source.controller.add(Uri.parse('aomobile://notifications'));
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.notifications);
  });

  testWidgets('a prs link selects the PRs tab instead of stacking a route', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('aomobile://prs'));
    await tester.pumpAndSettle();

    expect(HomeShell.selectedTab.value, 2);
    expect(observer.pushed, isEmpty);
  });

  testWidgets('an unknown link is ignored rather than crashing the app', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('aomobile://settings'));
    source.controller.add(Uri.parse('https://example.com/session/abc'));
    await tester.pumpAndSettle();

    expect(observer.pushed, isEmpty);
  });

  testWidgets('handling before the navigator exists reports that it did nothing', (tester) async {
    final service = DeepLinkService(source, GlobalKey<NavigatorState>());

    expect(service.handle(Uri.parse('aomobile://session/abc')), isFalse);
  });

  test('dispose cancels the link-stream subscription', () async {
    final plainSource = _FakeSource();
    final service = DeepLinkService(plainSource, GlobalKey<NavigatorState>());

    await service.start();
    expect(plainSource.controller.hasListener, isTrue);

    await service.dispose();

    expect(plainSource.controller.hasListener, isFalse);
  });
}
