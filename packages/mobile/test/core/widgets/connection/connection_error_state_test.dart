import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/connection/connection_error_state.dart';

void main() {
  Future<({List<String> calls})> pump(
    WidgetTester tester,
    ConnectionFailure reason, {
    String host = '10.0.0.5',
    TargetPlatform platform = TargetPlatform.iOS,
    bool rePair = false,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: ConnectionErrorState(
                reason: reason,
                host: host,
                port: '3011',
                desktopName: 'MacBook',
                onRetry: () => calls.add('retry'),
                onSwitchDesktop: () => calls.add('switch'),
                onRePair: rePair ? () => calls.add('re-pair') : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return (calls: calls);
  }

  testWidgets('unreachable names the desktop, the address and the local network hint', (tester) async {
    await pump(tester, ConnectionFailure.unreachable);

    expect(find.text("Can't reach MacBook"), findsOneWidget);
    expect(find.textContaining('10.0.0.5:3011'), findsOneWidget);
    expect(find.text(kLocalNetworkHint), findsOneWidget);
  });

  testWidgets('Retry is primary and Switch desktop is secondary', (tester) async {
    final result = await pump(tester, ConnectionFailure.serverError, host: 'mac.tail0.ts.net');

    expect(find.text('Your desktop returned an error'), findsOneWidget);
    expect(find.text(kLocalNetworkHint), findsNothing);
    await tester.tap(find.byKey(ConnectionErrorState.retryKey));
    await tester.tap(find.byKey(ConnectionErrorState.switchKey));

    expect(result.calls, ['retry', 'switch']);
  });

  testWidgets('rate-limited explains the lockout', (tester) async {
    await pump(tester, ConnectionFailure.rateLimited);

    expect(find.text('Too many attempts'), findsOneWidget);
  });

  testWidgets('an auth failure offers Re-pair instead of a retry that would spend an attempt', (tester) async {
    final result = await pump(tester, ConnectionFailure.auth, rePair: true);

    expect(find.text('Re-pair'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.byKey(ConnectionErrorState.retryKey));

    expect(result.calls, ['re-pair']);
  });
}
