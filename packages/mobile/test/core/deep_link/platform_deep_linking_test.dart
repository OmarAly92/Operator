import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

bool _iosEmbedderHandlesLinks() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final disabled = RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>');
  return !disabled.hasMatch(plist);
}

bool _androidEmbedderHandlesLinks() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final disabled = RegExp(
    r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+android:value="false"\s*/>',
  );
  return !disabled.hasMatch(manifest);
}

Future<void> _embedderPushes(WidgetTester tester, Uri uri) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': uri.toString()}),
    ),
    (_) {},
  );
}

void main() {
  final link = Uri.parse('operator://session/repo-21');

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
        onGenerateInitialRoutes: (name) => [
          MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink(), settings: RouteSettings(name: name)),
        ],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS: a cold-start notification tap pushes exactly the session route', (tester) async {
    source.initial = link;
    await pumpApp(tester);
    observer.pushed.clear();

    await DeepLinkService(source, navigatorKey).start();
    if (_iosEmbedderHandlesLinks()) await _embedderPushes(tester, link);
    await tester.pumpAndSettle();

    expect(observer.pushed, [RoutesStrings.session]);
  });

  testWidgets('iOS: a warm notification tap pushes exactly the session route', (tester) async {
    await pumpApp(tester);
    observer.pushed.clear();
    await DeepLinkService(source, navigatorKey).start();

    source.controller.add(link);
    if (_iosEmbedderHandlesLinks()) await _embedderPushes(tester, link);
    await tester.pumpAndSettle();

    expect(observer.pushed, [RoutesStrings.session]);
  });

  testWidgets('Android: a cold-start link keeps the launch route and pushes only the session', (tester) async {
    source.initial = link;
    if (_androidEmbedderHandlesLinks()) {
      tester.platformDispatcher.defaultRouteNameTestValue = link.path;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    }
    await pumpApp(tester);

    await DeepLinkService(source, navigatorKey).start();
    await tester.pumpAndSettle();

    expect(observer.pushed, [RoutesStrings.sessions, RoutesStrings.session]);
  });

  testWidgets('Android: a warm link pushes exactly the session route', (tester) async {
    await pumpApp(tester);
    observer.pushed.clear();
    await DeepLinkService(source, navigatorKey).start();

    source.controller.add(link);
    if (_androidEmbedderHandlesLinks()) await _embedderPushes(tester, link);
    await tester.pumpAndSettle();

    expect(observer.pushed, [RoutesStrings.session]);
  });
}
