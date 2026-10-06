import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
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

class _Paired implements ServerConfigSource {
  const _Paired([this.current = const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1')]);

  @override
  final ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
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
    source.initial = Uri.parse('operator://session/abc');
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired());

    await service.start();
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.session);
  });

  testWidgets('a warm link arriving later lands too', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired());
    await service.start();

    source.controller.add(Uri.parse('operator://notifications'));
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.notifications);
  });

  testWidgets('a prs link selects the PRs tab instead of stacking a route', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired());
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('operator://prs'));
    await tester.pumpAndSettle();

    expect(HomeShell.selectedTab.value, 1);
    expect(observer.pushed, isEmpty);
  });

  testWidgets('an unknown link is ignored rather than crashing the app', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired());
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('operator://settings'));
    source.controller.add(Uri.parse('https://example.com/session/abc'));
    await tester.pumpAndSettle();

    expect(observer.pushed, isEmpty);
  });

  testWidgets('handling before the navigator exists reports that it did nothing', (tester) async {
    final service = DeepLinkService(source, GlobalKey<NavigatorState>(), const _Paired());

    expect(service.handle(Uri.parse('operator://session/abc')), isFalse);
  });

  test('dispose cancels the link-stream subscription', () async {
    final plainSource = _FakeSource();
    final service = DeepLinkService(plainSource, GlobalKey<NavigatorState>(), const _Paired());

    await service.start();
    expect(plainSource.controller.hasListener, isTrue);

    await service.dispose();

    expect(plainSource.controller.hasListener, isFalse);
  });

  testWidgets('with no paired desktop, a link opens nothing', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired(null));
    observer.pushed.clear();

    final handled = service.handle(Uri.parse('operator://session/abc'));
    await tester.pumpAndSettle();

    expect(handled, isFalse);
    expect(observer.pushed, isEmpty);
  });

  testWidgets('a paired session link lands on top of the board, not in place of it', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey, const _Paired());

    final handled = service.handle(Uri.parse('operator://session/abc'));
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(observer.pushed, contains(RoutesStrings.sessions));
    expect(observer.pushed.indexOf(RoutesStrings.sessions), lessThan(observer.pushed.indexOf(RoutesStrings.session)));
  });
}
